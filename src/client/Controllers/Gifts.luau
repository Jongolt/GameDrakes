--!strict
-- 2.4: gifts on the client (spec 06 §3, §4, §6; 02 §3 2:45). The 🎁 pill in the Roblox top bar (next to Settings):
-- the next gift timer, "Claim!" when one is ready, a red dot with the ready count (gifts + calendar day). The Gifts tab of the book:
-- gifts over time (8 tiles: timer / Claim / Done), the calendar (7 tiles of the week, Claim; day 7 - a choice of the Rare hatchling's element),
-- Free Gift (if the group is set in Config). The reward banner (Notice "reward") with a coin flight. "There was input" - Remote Active (AFK stop).
-- There is no room in the left HUD column (phone 812x375: three plaques of 54 px), hence the pill at the top.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GroupService = game:GetService("GroupService")
local ExperienceNotificationService = game:GetService("ExperienceNotificationService") -- the opt-in prompt
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Rewards = require(Core:WaitForChild("Rewards"))
local Format = require(Core:WaitForChild("Format"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local NextUp = require(script.Parent:WaitForChild("NextUp")) -- the next update and RSVP (R5)
local UIStack = require(script.Parent:WaitForChild("UIStack"))

local Gifts = {}

local me = Players.LocalPlayer
local R = Config.Rewards
local TG = R.timeGifts
local S = Strings.Rewards
local TAB_COLOR = Color3.fromRGB(196, 70, 110)
local banners: any = nil
local coins: any = nil
local menu: any = nil
local favorite: any = nil -- Controllers/Favorite - "tomorrow" yields to the "favorite" prompt
local hud: any = nil -- newbie mode (spec 19 §17, HUD.newbie) - "one thing at a time", "tomorrow" waits for its end
local hatchScene: any = nil -- the hatch scene hides the HUD by itself, worldUiHidden does not see it
local quiet: any = nil -- Controllers/Quiet - windows only when the player is idle
local freeCardAt = -math.huge -- when the Free Gift card was shown - windows do not open right after it
local promptOpen = false -- the Roblox "notifications" prompt is on screen
local pillText: TextLabel? = nil
local badge: TextLabel? = nil
local timers: { [TextLabel]: number } = {} -- tab tiles: timer -> gift minute
local lastSig = ""

local function analytics(name: string, fields: { [string]: any }?)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, fields or {})
	end
end

-- while the Roblox "notifications" prompt is on screen, the Gloom hunt does not place a wave (UiBusy, like for a menu); after it - the actual menu state
local function uiBusy(on: boolean)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("UiBusy")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(on)
	end
	-- on PC the Roblox player list lay over the opt-in prompt - hidden, like HUD.setVisible for a menu
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, not on)
	end)
end

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rewardsData(): any
	local rw = Store.get("rewards")
	return if typeof(rw) == "table" then rw else {}
end

local function claimedGifts(): { [string]: boolean }
	local tg = rewardsData().timeGifts
	return if typeof(tg) == "table" and typeof(tg.claimed) == "table" then tg.claimed else {}
end

local function season(): any
	local se = rewardsData().season
	return if typeof(se) == "table" then se else { points = 0, claimed = {} }
end

local function seasonReady(): { number }
	if workspace:GetServerTimeNow() >= R.season.endsAt then -- 09 §5: the track is closed
		return {}
	end
	local se = season()
	return Rewards.seasonClaimable(se.points or 0, if typeof(se.claimed) == "table" then se.claimed else {}, R.season.steps)
end

local function calendar(): any
	local c = rewardsData().calendar
	return if typeof(c) == "table" then c else { day = 0, claimed = 0 }
end

local function giftSec(): number
	return (me:GetAttribute("GiftSec") :: number?) or 0
end

-- "N minutes of income" in money - as the server computes it (Reward.minutesCoins: the nest income
-- without friends and weather x 60 x N, at least minMinutesReward); the income - the GiftRate attribute of the own nest (Nest)
local function minutesText(minutes: number): string
	local rate = 0
	for _, r in CollectionService:GetTagged("Incubator") do
		if r:GetAttribute("OwnerId") == me.UserId then
			local nest = r.Parent and r.Parent.Parent
			rate = (nest and nest:GetAttribute("GiftRate") :: number?) or 0
			break
		end
	end
	return "+" .. Format.number(math.max(Config.Quests.minMinutesReward, math.floor(rate * 60 * minutes)))
end

-- the egg in the zone color and the lantern are drawn
local function eggIcon(parent: Instance, key: string, pos: UDim2)
	local c = Config.UI.eggIcon[key] or Config.UI.eggIcon.Meadow
	local e = Instance.new("Frame")
	e.Name = "Egg"
	e.BackgroundColor3 = Color3.fromRGB(c[1], c[2], c[3])
	e.AnchorPoint = Vector2.new(0.5, 0)
	e.Position = pos
	e.Size = UDim2.fromOffset(20, 26)
	UIKit.corner(e, 0.5)
	UIKit.stroke(e, UIKit.STROKE, 2)
	UIKit.gloss(e, 0.45)
	local spot = Instance.new("Frame") -- speckle
	spot.BackgroundColor3 = Color3.new(1, 1, 1)
	spot.BackgroundTransparency = 0.45
	spot.Position = UDim2.fromScale(0.22, 0.2)
	spot.Size = UDim2.fromScale(0.28, 0.2)
	UIKit.corner(spot, 0.5)
	spot.Parent = e
	e.Parent = parent
end

local function lanternIcon(parent: Instance, pos: UDim2)
	local L = Config.UI.lanternIcon
	local root = Instance.new("Frame")
	root.Name = "Lantern"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = pos
	root.Size = UDim2.fromOffset(22, 26)
	local function piece(name: string, color: { number }, x: number, y: number, w: number, h: number, round: number)
		local p = Instance.new("Frame")
		p.Name = name
		p.BackgroundColor3 = Color3.fromRGB(color[1], color[2], color[3])
		p.Position = UDim2.fromScale(x, y)
		p.Size = UDim2.fromScale(w, h)
		UIKit.corner(p, round)
		p.Parent = root
		return p
	end
	piece("Handle", L.cap, 0.38, 0, 0.24, 0.12, 0.5)
	piece("Top", L.cap, 0.18, 0.1, 0.64, 0.12, 0.3)
	local body = piece("Body", L.glow, 0.14, 0.2, 0.72, 0.62, 0.35)
	UIKit.stroke(body, UIKit.STROKE, 2)
	UIKit.gloss(body, 0.4)
	piece("Bottom", L.cap, 0.18, 0.8, 0.64, 0.12, 0.3)
	root.Parent = parent
end

-- a short reward caption on a tile: an icon (an emoji or "coin" / "egg:<key>" / "lantern") and a word
local function tileFace(rw: any): (string?, string)
	if rw.minutes then
		return "coin", minutesText(rw.minutes) -- "10 min of income" on a 78 px tile gave 8 px - so a number
	elseif rw.berries then
		return "🍓", fmt(S.berries, { n = rw.berries })
	elseif rw.rareNest then
		return "egg:Rare", S.rareNest
	elseif rw.egg then
		return "egg:" .. (if rw.minRarity == "Epic" then "Epic" else tostring(rw.egg)), if rw.minRarity == "Epic" then S.epicEgg else fmt(S.egg, { zone = Loc.t(Strings.Zone[rw.egg] or rw.egg) })
	elseif rw.decor == "Banner" then
		return "🚩", S.banner
	elseif rw.decor then
		return "lantern", S.lantern
	elseif rw.hatchling then
		return "🐉", if rw.name then rw.name else S.rareDragon
	elseif rw.preset then
		return "🎨", Loc.t(S.solstice) -- {Solstice} - the name after translation
	end
	return "🎁", ""
end

-- a tile: title, icon (or a coin), caption, the bottom - state (button / timer / Done)
local function tile(parent: Instance, order: number, head: string, rw: any, state: string, onClaim: (() -> ())?, timerMin: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Tile" .. order
	f.LayoutOrder = order
	f.BackgroundColor3 = if state == "ready" then Color3.fromRGB(70, 52, 34) elseif state == "done" then Color3.fromRGB(40, 48, 40) else Color3.fromRGB(44, 44, 48)
	f.BackgroundTransparency = if state == "done" then 0.3 else 0
	UIKit.corner(f, 0.12)
	UIKit.stroke(f, if state == "ready" then UIKit.GOLD else UIKit.BORDER, if state == "ready" then 2 else 1)
	UIKit.text(f, head, if state == "done" then UIKit.GREEN else UIKit.CREAM, { Name = "Head", Position = UDim2.new(0, 2, 0, 2), Size = UDim2.new(1, -4, 0, 16) })
	local glyph, word = tileFace(rw)
	if glyph == "coin" then
		UIKit.coin(f, nil, { Position = UDim2.new(0.5, -12, 0, 20), Size = UDim2.fromOffset(24, 24) })
	elseif glyph == "lantern" then
		lanternIcon(f, UDim2.new(0.5, 0, 0, 19))
	elseif glyph and string.sub(glyph, 1, 4) == "egg:" then
		eggIcon(f, string.sub(glyph, 5), UDim2.new(0.5, 0, 0, 19))
	elseif glyph then
		UIKit.iconText(f, glyph, { Position = UDim2.new(0.5, -14, 0, 19), Size = UDim2.fromOffset(28, 26) })
	end
	if state == "done" then -- a claimed tile - a green check over the icon (the tile bottom is sometimes cut off on the phone)
		local ck = UIKit.text(f, "✓", UIKit.GREEN, { Name = "Check", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -3, 0, 18), Size = UDim2.fromOffset(20, 20) })
		ck.ZIndex = 5
	end
	UIKit.text(f, word, UIKit.GOLD, { Name = "Word", Position = UDim2.new(0, 2, 0, 47), Size = UDim2.new(1, -4, 0, 14) })
	if state == "ready" and onClaim then
		local b = UIKit.button(f, S.claim, UIKit.GREEN, function()
			onClaim()
		end, { minSize = Vector2.new(44, 44) })
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, 0, 1, -2)
		b.Size = UDim2.new(1, -6, 0, 44)
	else
		local t = UIKit.text(f, if state == "done" then S.claimed else "", if state == "done" then UIKit.GREEN else Color3.new(1, 1, 1),
			{ Name = "State", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -8, 0, 22) })
		if timerMin then
			timers[t] = timerMin
		end
	end
	f.Parent = parent
	return f
end

local function grid(parent: Instance, order: number, n: number, height: number): Frame
	local g = Instance.new("Frame")
	g.Name = "Grid" .. order
	g.LayoutOrder = order
	g.BackgroundTransparency = 1
	g.Size = UDim2.new(1, 0, 0, height)
	local l = Instance.new("UIGridLayout")
	l.CellPadding = UDim2.fromOffset(5, 5)
	l.CellSize = UDim2.new(1 / n, -5, 0, height)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = g
	g.Parent = parent
	return g
end

local function claim(kind: string, id: string?)
	Sounds.play("button")
	local r = Net.call("Claim", kind, id)
	if not r.ok and r.reason ~= "not_ready" and banners then
		banners.toast(Strings.Errors[r.reason or ""] or tostring(r.reason))
	end
end

local render: (Frame) -> ()

local function joinGroup()
	local id = R.freeGift.groupId
	if id == 0 then
		return
	end
	pcall(function()
		(GroupService :: any):PromptJoinAsync(id)
	end)
	claim("freeGift")
end

render = function(body: Frame)
	for _, c in body:GetChildren() do
		c:Destroy()
	end
	timers = {}
	local list = Instance.new("ScrollingFrame")
	list.Name = "Gifts"
	list.BackgroundTransparency = 1
	list.Size = UDim2.fromScale(1, 1)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = body
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 6)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
	-- order: the waiting calendar day first (phone: the book body ~230 px - the second block is below the fold), otherwise gifts over time
	local cal = calendar()
	local gBase, cBase = 0, 10
	if Rewards.calendarPending(cal) then
		gBase, cBase = 10, 0
	end
	-- gifts over time
	UIKit.text(list, Loc.t(S.giftsHeader) .. "  -  " .. Loc.t(S.giftsNote), UIKit.CREAM, { Name = "GiftsHead", LayoutOrder = gBase + 1, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
	local sec = giftSec()
	local claimed = claimedGifts()
	local g1 = grid(list, gBase + 2, #TG.list, 108)
	for i, gft in TG.list do
		local key = tostring(gft.min)
		local state = if claimed[key] then "done" elseif sec >= gft.min * 60 then "ready" else "wait"
		tile(g1, i, fmt(S.giftTile, { n = gft.min }), gft, state, function()
			claim("timeGift", key)
		end, if state == "wait" then gft.min else nil)
	end
	-- the calendar: the week of the waiting or the last day
	local day = math.max(cal.day or 0, 1)
	local cur = if Rewards.calendarPending(cal) then (cal.claimed or 0) + 1 else (cal.claimed or 0)
	UIKit.text(list, fmt(S.calendarHeader, { n = math.max(cal.day or 0, 1) }), UIKit.CREAM, { Name = "CalHead", LayoutOrder = cBase + 3, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
	local first = (math.max(cur, 1) - Rewards.calendarSlot(math.max(cur, 1))) + 1
	local g2 = grid(list, cBase + 4, 7, 108)
	for k = 0, 6 do
		local n = first + k
		local rw = Rewards.calendarRewardFor(n, R, me.UserId, Config.Elements)
		local state = if n <= (cal.claimed or 0) then "done" elseif n == (cal.claimed or 0) + 1 and Rewards.calendarPending(cal) then "ready" else "wait"
		local onClaim = if rw.hatchling and not rw.element then nil else function()
			claim("calendar")
		end
		local t = tile(g2, k + 1, fmt(S.dayTile, { n = n }), rw, state, onClaim, nil)
		if state == "ready" and rw.hatchling and not rw.element then
			UIKit.text(t, "↓", UIKit.GOLD, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.new(1, -8, 0, 22) })
		end
	end
	local curRw = Rewards.calendarRewardFor(cur, R, me.UserId, Config.Elements)
	if Rewards.calendarPending(cal) and curRw.hatchling and not curRw.element then -- day 7: element choice
		UIKit.text(list, S.pickDragon, UIKit.GOLD, { Name = "PickHead", LayoutOrder = cBase + 5, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
		local row = grid(list, cBase + 6, R.calendar.choices, 48)
		for i, el in Rewards.choices(cur, Config.Elements, R.calendar.choices) do
			local e = Content.Elements[el]
			local b = Loc.raw(UIKit.button(row, if e then e.name else el, if e then Color3.fromRGB(e.color[1], e.color[2], e.color[3]) else UIKit.GREY, function()
				claim("calendar", el)
			end, { minSize = Vector2.new(70, 44) })) -- element name
			b.LayoutOrder = i
		end
	elseif not Rewards.calendarPending(cal) then
		local note = S.calendarStart
		if (cal.day or 0) > 0 then -- what exactly waits tomorrow
			local _, word = tileFace(Rewards.calendarRewardFor(day + 1, R, me.UserId, Config.Elements))
			note = fmt(S.calendarNext, { n = day + 1, gift = Loc.t(word) })
		end
		UIKit.text(list, note, Color3.fromRGB(200, 200, 205),
			{ Name = "CalNote", LayoutOrder = cBase + 5, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
	end
	-- Season 1 (06 §8): 10 steps in two rows of 5, points come from the dailies
	local se = season()
	local pts = se.points or 0
	local sClaimed = if typeof(se.claimed) == "table" then se.claimed else {}
	local sBase = if #seasonReady() > 0 and not Rewards.calendarPending(cal) then -5 else 20
	local ended = workspace:GetServerTimeNow() >= R.season.endsAt
	-- with weekly quests (update 1 is on, Config.Rewards.weekly.on) points come from them too
	local weeklyOn = R.weekly.on and Rewards.weeklySet(Content.Updates, (ReplicatedStorage:GetAttribute("UpdatesLive") :: number?) or 0) ~= nil
	local note = if ended then Loc.t(S.seasonEnded) elseif weeklyOn then fmt(S.seasonNoteWeekly, { n = R.weekly.points }) else Loc.t(S.seasonNote)
	UIKit.text(list, (if pts == 1 then Loc.t(S.seasonHeaderOne) else fmt(S.seasonHeader, { n = pts })) .. "  -  " .. note, UIKit.CREAM, { Name = "SeasonHead", LayoutOrder = sBase + 1, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
	local g3 = grid(list, sBase + 2, 5, 108)
	g3.Size = UDim2.new(1, 0, 0, 108 * 2 + 5)
	for i, need in R.season.steps do
		local key = tostring(i)
		local state = if sClaimed[key] then "done" elseif pts >= need and not ended then "ready" else "wait"
		local t = tile(g3, i, fmt(S.seasonStep, { n = need }), R.season.rewards[i], state, function()
			claim("season", key)
		end, nil)
		if state == "wait" then
			local lbl = t:FindFirstChild("State") :: TextLabel?
			if lbl then
				lbl.Text = string.format("%d/%d", pts, need)
				lbl.TextColor3 = Color3.fromRGB(190, 190, 200)
			end
		end
	end
	-- Free Gift
	local F = R.freeGift
	if F.groupId ~= 0 then
		local fg = rewardsData().freeGift
		local taken = typeof(fg) == "table" and fg.group == true
		local card = Instance.new("Frame")
		card.Name = "FreeGift"
		card.LayoutOrder = 30
		card.BackgroundColor3 = Color3.fromRGB(44, 44, 48)
		card.Size = UDim2.new(1, 0, 0, if taken then 30 else 92)
		UIKit.corner(card, 0.12)
		UIKit.stroke(card, UIKit.BORDER, 1)
		if taken then
			UIKit.text(card, S.freeGiftDone, UIKit.GREEN, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(1, -16, 1, -8), TextXAlignment = Enum.TextXAlignment.Left })
		else
			UIKit.text(card, S.welcomeGift, UIKit.GOLD, { Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(0.7, -8, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
			UIKit.text(card, Loc.t(S.joinGroup), UIKit.CREAM, { Position = UDim2.new(0, 8, 0, 26), Size = UDim2.new(0.7, -8, 0, 36), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
			UIKit.text(card, S.likeNote, Color3.fromRGB(180, 180, 190), { Position = UDim2.new(0, 8, 0, 66), Size = UDim2.new(0.7, -8, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
			local b = UIKit.button(card, S.join, UIKit.GREEN, joinGroup)
			b.AnchorPoint = Vector2.new(1, 0.5)
			b.Position = UDim2.new(1, -8, 0.5, 0)
			b.Size = UDim2.new(0.26, 0, 0, 48)
		end
		card.Parent = list
	end
	-- the next update with a date and an RSVP button of the Roblox event (if the event exists - eventId in Content.Updates);
	-- signed up - a green line instead of the button
	local nu, left = NextUp.nextUpdate()
	if nu then
		local card = Instance.new("Frame")
		card.Name = "NextUpdate"
		card.LayoutOrder = 25
		card.BackgroundColor3 = Color3.fromRGB(44, 44, 48)
		card.Size = UDim2.new(1, 0, 0, 40)
		UIKit.corner(card, 0.12)
		UIKit.stroke(card, UIKit.BORDER, 1)
		UIKit.text(card, fmt(Strings.Next.updateHead, { title = nu.title or "", time = left }), UIKit.CREAM, { Name = "Head", Position = UDim2.new(0, 8, 0, 4), Size = UDim2.new(0.64, -8, 1, -8), TextXAlignment = Enum.TextXAlignment.Left })
		local id = nu.eventId
		if id then
			local st = NextUp.rsvpStatus(id)
			if st == "Going" then
				UIKit.text(card, Strings.Next.going, UIKit.GREEN, { Name = "Going", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 4), Size = UDim2.new(0.34, 0, 1, -8), TextXAlignment = Enum.TextXAlignment.Right })
			else
				local b = UIKit.button(card, Strings.Next.notify, UIKit.GOLD, function()
					NextUp.rsvp(id, "gifts")
				end)
				b.Name = "Rsvp"
				b.AnchorPoint = Vector2.new(1, 0.5)
				b.Position = UDim2.new(1, -6, 0.5, 0)
				b.Size = UDim2.new(0.3, 0, 0, 32)
			end
		end
		card.Parent = list
	end
end

-- what waits tomorrow if today's calendar day is already claimed - (the day number, the reward in
-- the player's language); otherwise nil. The NEXT line (Controllers/NextUp) and the "Tomorrow" banner once per session
function Gifts.tomorrow(): (number?, string?)
	local cal = calendar()
	if (cal.day or 0) <= 0 or Rewards.calendarPending(cal) then
		return nil, nil
	end
	local n = (cal.day or 0) + 1
	local _, word = tileFace(Rewards.calendarRewardFor(n, R, me.UserId, Config.Elements))
	return n, Loc.t(word)
end

-- how much is ready to claim (gifts + calendar day) and the pill caption
local function status(): (number, string, boolean)
	local sec = giftSec()
	local claimed = claimedGifts()
	local ready = Rewards.readyGifts(TG.list, sec, claimed)
	local n = #ready + (if Rewards.calendarPending(calendar()) then 1 else 0) + #seasonReady()
	if #ready > 0 then
		return n, S.pillReady, true
	end
	local _, left = Rewards.nextGift(TG.list, sec, claimed)
	if left > 0 then
		return n, if me:GetAttribute("GiftAfk") then S.paused else Format.clock(left), false
	end
	return n, S.tab, false
end

-- the chest of the own nest (06 §3): above it the same timer / Claim!, a touch - the Gifts tab
local chestGui: BillboardGui? = nil
local chestPrompt: ProximityPrompt? = nil
local function syncChest(text: string, hot: boolean, n: number)
	local box: BasePart? = nil
	for _, m in CollectionService:GetTagged("GiftChest") do
		local nest = m.Parent
		if nest and nest:GetAttribute("OwnerId") == me.UserId and m:IsA("Model") and m.PrimaryPart then
			box = m.PrimaryPart
		end
	end
	if not box then
		if chestGui then
			chestGui.Enabled = false
		end
		return
	end
	local C = R.chest
	if not chestGui or chestGui.Adornee ~= box then
		if chestGui then
			chestGui:Destroy()
		end
		local g = Instance.new("BillboardGui")
		g.Name = "GiftChestLabel"
		g.Adornee = box
		g.Size = UDim2.fromOffset(110, 34)
		g.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
		g.MaxDistance = C.labelDistance
		g.AlwaysOnTop = false
		UIKit.text(g, "", Color3.new(1, 1, 1), { Name = "T", Size = UDim2.fromScale(1, 1) })
		g.Parent = me:WaitForChild("PlayerGui")
		chestGui = g
	end
	if not chestPrompt or chestPrompt.Parent ~= box then
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = S.chestPrompt
		pr.ObjectText = S.chestObject
		pr.HoldDuration = 0
		pr.MaxActivationDistance = C.promptDistance
		pr.RequiresLineOfSight = false
		pr.Triggered:Connect(function()
			if menu and menu.open then
				menu.open("gifts")
			end
		end)
		pr.Parent = box
		chestPrompt = pr
	end
	local g = chestGui :: BillboardGui
	g.Enabled = true
	local t = g:FindFirstChild("T") :: TextLabel
	t.Text = "🎁 " .. (if n > 0 and not hot then S.pillReady else text)
	t.TextColor3 = if hot or n > 0 then UIKit.GOLD else Color3.new(1, 1, 1)
end

local function updatePill()
	local n, text, hot = status()
	pcall(syncChest, text, hot, n)
	if pillText then
		pillText.Text = text
		pillText.TextColor3 = if hot then UIKit.GOLD else Color3.new(1, 1, 1)
	end
	if badge then
		badge.Visible = n > 0
		badge.Text = tostring(n)
	end
	-- the tab is open: tile timers every second, a redraw when the ready state changes
	if menu and menu.current and menu.current() == "gifts" then
		local sec = giftSec()
		local sig = table.concat(Rewards.readyGifts(TG.list, sec, claimedGifts()), ",") .. "|" .. table.concat(seasonReady(), ",")
		if sig ~= lastSig then
			lastSig = sig
			menu.open("gifts")
			return
		end
		for t, min in timers do
			if t.Parent then
				t.Text = Format.clock(math.max(0, min * 60 - sec))
			end
		end
	end
end

local function buildPill(hud: any)
	if not hud or not hud.addTopbarButton then
		return
	end
	local b: TextButton = hud.addTopbarButton("Gifts", "🎁", function()
		if menu and menu.open then
			menu.open("gifts")
		end
	end)
	-- circle -> pill: the icon on the left, the timer on the right (the Roblox bar 58 px, the circle 44)
	b.Size = UDim2.fromScale(2.4, 1)
	local lim = b:FindFirstChildOfClass("UISizeConstraint")
	if lim then
		lim.MaxSize = Vector2.new(Config.UI.topbar.size * 2.4, Config.UI.topbar.size)
	end
	local icon = b:FindFirstChild("Icon") :: TextLabel?
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0.08, 0.5)
		icon.Size = UDim2.fromScale(0.28, 0.6)
	end
	pillText = UIKit.text(b, "", Color3.new(1, 1, 1), { Name = "Timer", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.38, 0.5), Size = UDim2.fromScale(0.56, 0.5) })
	badge = UIKit.text(b, "", Color3.new(1, 1, 1), { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 6, 0, 6), Size = UDim2.fromOffset(18, 18), BackgroundTransparency = 0, BackgroundColor3 = Color3.fromRGB(220, 50, 50), Visible = false, ZIndex = 3 })
	UIKit.corner(badge :: TextLabel, 1)
end

-- the Free Gift card at 2:45 of the first session (02 §3): top right, with a cross, not a window over everything
local function freeGiftCard()
	if R.freeGift.groupId == 0 then
		return
	end
	local g = UIKit.screen("FreeGiftCard", 4)
	freeCardAt = os.clock()
	if quiet and quiet.asked then
		quiet.asked() -- a request was shown - the next ones wait askGap
	end
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.PANEL
	-- in the top right corner the card lay on the step banner (HATCH / FLY) at 812x375 -
	-- now under the Keeper plaque (UIKit.sideCard), 72 px; hidden when mounted; the cross inside the corner
	f.Size = UDim2.fromOffset(350, 72)
	UIKit.corner(f, 0.12)
	UIKit.stroke(f, UIKit.BORDER, 2)
	UIKit.text(f, S.welcomeGift, UIKit.GOLD, { Position = UDim2.new(0, 10, 0, 3), Size = UDim2.new(0, 180, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.text(f, Loc.t(S.joinGroup), UIKit.CREAM, { Position = UDim2.new(0, 10, 0, 20), Size = UDim2.new(0, 180, 0, 33), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.text(f, S.likeNote, Color3.fromRGB(180, 180, 190), { Position = UDim2.new(0, 10, 0, 54), Size = UDim2.new(0, 230, 0, 15), TextXAlignment = Enum.TextXAlignment.Left }) -- 15 px: the font no smaller than 11 (add. 2.12)
	local join = UIKit.button(f, S.join, UIKit.GREEN, function()
		g:Destroy()
		joinGroup()
	end)
	join.AnchorPoint = Vector2.new(1, 0)
	join.Position = UDim2.new(1, -54, 0, 14)
	join.Size = UDim2.fromOffset(100, 44)
	local x = UIKit.button(f, "X", UIKit.GREY, function()
		g:Destroy()
	end, { minSize = Vector2.new(44, 44) })
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -4, 0, 4)
	x.Size = UDim2.fromOffset(44, 44)
	f.Parent = g
	UIKit.sideCard(g, f)
end

local rewardNext = 0 -- reward banners that arrive at once (a daily + a weekly quest on growth) go one after another, not over each other
local function showReward(p: any)
	if banners then
		local color = if p.color == "daily" then Color3.fromRGB(226, 150, 60) elseif p.color == "calendar" then Color3.fromRGB(110, 170, 255) else TAB_COLOR
		banners.banner(tostring(p.title or ""), color, if typeof(p.sub) == "string" and p.sub ~= "" then p.sub else nil, 2.8)
	end
	Sounds.play("stage_up")
	if coins and typeof(p.coins) == "number" and p.coins > 0 then
		coins.fly(p.coins, nil)
	end
end
local function onReward(p: any)
	local now = os.clock()
	local at = math.max(now, rewardNext)
	rewardNext = at + Config.Quests.chainDelay
	if at > now then
		task.delay(at - now, showReward, p)
	else
		showReward(p)
	end
end

local loadedRef: any = nil -- Glow (the pedestal board) - lazily

function Gifts.init(_snapshot: any, loaded: any)
	loadedRef = loaded
	banners = loaded.Banners
	favorite = loaded.Favorite
	hud = loaded.HUD
	hatchScene = loaded.HatchScene
	quiet = loaded.Quiet
	pcall(function() -- the opt-in prompt closed (Roblox does not report the answer - only the fact)
		ExperienceNotificationService.OptInPromptClosed:Connect(function()
			promptOpen = false
			analytics("notify_closed")
			uiBusy(UIKit.worldUiHidden)
		end)
	end)
	coins = loaded.CoinFlight
	menu = loaded.Menu
	if menu and menu.register then
		menu.register({ id = "gifts", word = S.tab, icon = "🎁", color = TAB_COLOR, order = 45, render = render })
	end
	local ok, err = pcall(buildPill, loaded.HUD)
	if not ok then
		warn("[Gifts] pill: " .. tostring(err))
	end
end

-- nothing is open, not mounted, the "favorite" prompt has played and is not queued - "tomorrow" is allowed
local function tomorrowQuiet(): boolean
	local TB = R.tomorrowBanner
	if UIKit.worldUiHidden or me:GetAttribute("Mounted") ~= nil or UIStack.depth() > 0 or me:GetAttribute("Fight") ~= nil then
		return false -- Fight - a fight with the Gloom is on (Controllers/Combat)
	end
	if quiet and quiet.busy() ~= nil then
		return false -- an egg in hand, a raid, flight, combat, hatching, a large banner
	end
	if favorite and (favorite.pending() or favorite.quietFor() < TB.quietFor) then
		return false
	end
	if (hatchScene and hatchScene.busy()) or promptOpen or os.clock() - freeCardAt < TB.quietFor then
		return false
	end
	-- one request at a time
	if loadedRef and loadedRef.Glow and loadedRef.Glow.boardVisible and loadedRef.Glow.boardVisible() then
		return false
	end
	if hud and hud.newbie and hud.newbie() then -- a newcomer is shown one thing at a time in the first minutes (combat spec 19 §17)
		return false
	end
	return true
end

-- the opt-in prompt is on screen - pass buttons and other windows wait (like Favorite.busy)
function Gifts.busy(): boolean
	return promptOpen
end

-- the Roblox "turn on notifications" prompt (13+, opt-in; Roblox itself does not show it again too often): the notification text -
-- "{dragon} is waiting at the nest, day N gift" (Config.Notify, sending by tools/notify_send.py)
-- waits for silence no longer than TB.maxWait s; false - did not get it (a forgotten menu, an endless fight) - the chain gives up with the mark tomorrow/stuck
local function waitQuiet(): boolean
	local TB = R.tomorrowBanner
	local t0 = os.clock()
	-- the first Config.Quiet.strictFor s - only while the player stands still, then - simply not busy
	local strictFor = (Config.Quiet and Config.Quiet.strictFor) or 60
	while not (tomorrowQuiet() and (not quiet or quiet.ok(os.clock() - t0 < strictFor))) do
		if os.clock() - t0 > TB.maxWait then
			return false
		end
		task.wait(1)
	end
	return true
end


local function promptNotify(can: boolean)
	local NC = Config.Notify
	if not (NC and NC.on and NC.prompt) or not can then
		return
	end
	if not waitQuiet() then -- CanPromptOptInAsync yielded to the network: the player could have mounted or opened a menu
		return
	end
	promptOpen = true
	if quiet and quiet.asked then
		quiet.asked()
	end
	uiBusy(true)
	local ok, err = pcall(function()
		ExperienceNotificationService:PromptOptIn()
	end)
	if not ok then
		promptOpen = false
		warn("[Gifts] notify prompt: " .. tostring(err))
		uiBusy(UIKit.worldUiHidden)
		return
	end
	analytics("notify_prompt")
	task.delay(R.tomorrowBanner.promptHold, function() -- the closing comes as OptInPromptClosed; a safeguard if the event never comes
		if promptOpen then
			promptOpen = false
			uiBusy(UIKit.worldUiHidden)
		end
	end)
end

-- whether asking is possible at all (13+, not yet opted in, not asked recently) - in advance: a web call, the answer is ready before the window chain
local function canPrompt(): boolean
	local NC = Config.Notify
	if not (NC and NC.on and NC.prompt) then
		return false
	end
	local okCan, can = pcall(function()
		return ExperienceNotificationService:CanPromptOptInAsync()
	end)
	return okCan and can == true
end

-- the chain banners go into the reward queue (rewardNext) so that a quest reward arriving right after does not wipe them
local function queuedBanner(line1: string, color: Color3, line2: string?, seconds: number)
	local now = os.clock()
	local at = math.max(now, rewardNext)
	rewardNext = at + seconds
	if at > now then
		task.wait(at - now)
	end
	if banners then
		banners.banner(line1, color, line2, seconds)
	end
end

local function tomorrowChain()
	local TB = R.tomorrowBanner
	local can = canPrompt()
	task.wait(TB.quietFor)
	local t0 = os.clock()
	local first = calendar()
	local hatchDay = Rewards.calendarPending(first)
		and Rewards.calendarRewardFor((first.claimed or 0) + 1, R, me.UserId, Config.Elements).hatchling ~= nil
	-- the day claim waits for silence briefly (the reward banner will wait by itself), but the dragon of the day (the hatch scene) does not start mid-fight
	-- and the whole chain does not run in newbie mode (spec 19 §17: one thing at a time - otherwise the reward banner pushes the onboarding step aside)
	while not tomorrowQuiet() and os.clock() - t0 < TB.maxWait
		and (os.clock() - t0 < TB.claimWait or (hatchDay and me:GetAttribute("Fight") ~= nil) or (hud and hud.newbie and hud.newbie())) do
		task.wait(1)
	end
	if hud and hud.newbie and hud.newbie() then -- newbie mode never ended (no dragon for 10 min) - do not claim over it
		analytics("tomorrow", { s = "stuck" })
		return
	end
	-- a Gloom wave is not announced mid-chain (the force banner would wipe "Tomorrow" and the wave would run at the player during the day-2 dragon scene):
	-- UiBusy is held from the claim to the end of the banner (the opt-in prompt holds its own)
	uiBusy(true)
	local cal = calendar()
	local pickDay = false
	if Rewards.calendarPending(cal) then
		local nextRw = Rewards.calendarRewardFor((cal.claimed or 0) + 1, R, me.UserId, Config.Elements)
		if nextRw.hatchling and not nextRw.element then
			pickDay = true -- a day with an element choice (the Rare hatchling of day 7) - only by the button in Gifts
		else
			local r = Net.call("Claim", "calendar") -- the reward comes as a Notice banner (onReward), "tomorrow" - after it
			if r and r.ok then
				task.wait(TB.claimGap) -- the reward banner is 2.8 s, the reward queue lets the next one through after 1.4 s - wait for the whole thing
			else
				local why = if r and typeof(r.reason) == "string" then r.reason else "no_reply"
				warn("[Gifts] tomorrow: calendar claim failed: " .. why)
				analytics("tomorrow", { s = "claim_fail", why = why })
			end
		end
	end
	if not waitQuiet() then
		warn("[Gifts] tomorrow: no quiet moment in " .. TB.maxWait .. " s")
		analytics("tomorrow", { s = "stuck" })
		uiBusy(UIKit.worldUiHidden)
		return
	end
	local n, word = Gifts.tomorrow()
	if pickDay then
		queuedBanner(fmt(S.calendarWaiting, { n = (cal.claimed or 0) + 1 }), UIKit.GOLD, nil, TB.seconds)
		analytics("tomorrow", { s = "no_banner" })
	elseif (function()
		-- an egg on
		-- the pedestal - the "tomorrow" line about the glowing dragon instead of the calendar gift
		local g = Store.get("glowEgg")
		return typeof(g) == "table" and (tonumber(g.readyAt) or 0) > workspace:GetServerTimeNow() and not g.hatched
	end)() then
		local SG = (Strings :: any).GlowEgg
		queuedBanner(Loc.t(SG.tomorrow), Color3.fromRGB(255, 170, 70), Loc.t(SG.tomorrowNote), TB.seconds)
		analytics("tomorrow", { s = "glow" })
	elseif n and word then
		queuedBanner(fmt(S.tomorrowTitle, { n = n, gift = word }), UIKit.GOLD, Loc.t(S.tomorrowNote), TB.seconds)
		analytics("tomorrow", { s = "shown", day = n })
		if quiet and quiet.asked then
			quiet.asked()
		end
	else
		analytics("tomorrow", { s = "no_banner" }) -- the calendar has not started
		uiBusy(UIKit.worldUiHidden)
		return -- without the "tomorrow" line the opt-in prompt would have no occasion
	end
	task.wait(TB.seconds + TB.promptGap)
	uiBusy(UIKit.worldUiHidden) -- the banner has played; the opt-in prompt (if any) holds the hunt by itself again
	promptNotify(can)
end

function Gifts.start()
	Net.on("reward", onReward)
	-- the server sends freeGift by time
	-- (Reward: showAt); show it only in idle, like the other windows (section 21), wait for silence up to tomorrowBanner.maxWait
	Net.on("freeGift", function()
		task.spawn(function()
			local TB = R.tomorrowBanner
			-- (P8 day1_walkthrough H2: "Welcome gift" lay on the "-1 h" button of the pedestal board, the click went into it; J2: after waiting for the board
			-- the card came out in flight): silence and no pedestal board - in the same moment; the board is visible - wait and ask for silence again
			local function boardOn(): boolean
				return loadedRef ~= nil and loadedRef.Glow ~= nil and loadedRef.Glow.boardVisible ~= nil and loadedRef.Glow.boardVisible() == true
			end
			local t0 = os.clock()
			while true do
				if quiet and not quiet.wait((TB and TB.maxWait) or 120, (Config.Quiet and Config.Quiet.strictFor) or 60) then
					return -- no silence (an endless fight, a forgotten menu): the card stays in the gifts menu
				end
				if not boardOn() then
					break
				end
				if os.clock() - t0 > 180 then
					return -- still standing at the pedestal: the card stays in the gifts menu
				end
				task.wait(1)
			end
			freeGiftCard()
		end)
	end)
	Store.on("rewards", function()
		if menu and menu.current and menu.current() == "gifts" then
			menu.open("gifts")
		end
		updatePill()
	end)
	NextUp.onStatus(function() -- signed up for the event - the update block turns green
		if menu and menu.current and menu.current() == "gifts" then
			menu.open("gifts")
		end
	end)
	-- "there was input" for gifts over time: a touch, a key, a click (no more often than activeEvery s)
	local sentAt = -math.huge
	local folder = ReplicatedStorage:WaitForChild("Remotes", 30)
	local active = folder and folder:FindFirstChild("Active")
	UserInputService.InputBegan:Connect(function()
		local now = os.clock()
		if active and active:IsA("RemoteEvent") and now - sentAt >= TG.activeEvery then
			sentAt = now
			active:FireServer()
		end
	end)
	-- "tomorrow" once per session in the first minutes - after the first dismount (not earlier than
	-- minSession) or at afterSeconds. Waits for silence (tomorrowQuiet), claims the calendar
	-- day without a choice (otherwise many newcomers never claim day 1 and day 2 never comes), the banner "Tomorrow, Day n", the opt-in prompt
	local TB = R.tomorrowBanner
	local started = os.clock()
	local fired = false
	local function fire()
		if fired then
			return
		end
		fired = true
		task.spawn(tomorrowChain)
	end
	-- a teen grew while mounted - the server dismounts by itself (Movement.refresh) exactly at "Your dragon can fly!"
	-- that is not "dismounted and resting" - the "tomorrow" banner and the opt-in prompt must not take the place of the first flight
	local grewAt = -math.huge
	me:GetAttributeChangedSignal("CompanionStage"):Connect(function()
		grewAt = os.clock()
	end)
	me:GetAttributeChangedSignal("Mounted"):Connect(function()
		if me:GetAttribute("Mounted") ~= nil or os.clock() - started < TB.minSession then
			return
		end
		-- the server dismounts first, then rebuilds the companion (CompanionStage) - decide after 1.2 s: the stage changed nearby - that is growth
		local t = os.clock()
		task.delay(1.2, function()
			if me:GetAttribute("Mounted") == nil and grewAt < t - 2 then
				fire()
			end
		end)
	end)
	task.delay(TB.afterSeconds, fire)
	-- a returning player (not the first session) - the day gift right on join, as soon as the "while you were away" card is closed
	-- (the chain waits for silence); for D1 this is the "welcome back" moment, including the day-2 dragon hatch for group B
	task.delay(TB.returnAfter, function()
		for _ = 1, 20 do -- the profile snapshot may not have arrived yet (slow loading) - wait up to 20 s, otherwise the newcomer timing
			local n = tonumber(Store.get("sessions"))
			if n then
				if n > 1 then
					fire()
				end
				return
			end
			task.wait(1)
		end
	end)
	while true do
		local ok, err = pcall(updatePill)
		if not ok then
			warn("[Gifts] " .. tostring(err))
			task.wait(5)
		end
		task.wait(1)
	end
end

return Gifts
