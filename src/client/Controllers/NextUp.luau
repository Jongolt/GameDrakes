--!strict
-- the line "what awaits you and
-- when" (Core/NextUp). The "NEXT" pill in place of the step banner under the coins when there is no step for Config.UI.nextUp.quietAfter s; lives in the
-- StepBanner screen, so it hides together with the HUD (menu, hatch scene) and under announcements (UIKit.bannerUntil), not visible when mounted; before
-- the first dragon it is not shown (a newcomer gets Old Ash's greeting and the steps). In a cycle:
-- the nearest timer (dragon growth in the nest or an egg in the incubator), tomorrow's calendar day (today's already claimed, Gifts.tomorrow) and
-- the next update (Content.Updates, no farther than updateWithin). A tap on the update line - the RSVP window of the Roblox event
-- (SocialService:PromptRsvpToEventAsync, per the docs: client, Enum.RsvpStatus None/Going/NotGoing); the same NextUp.rsvp
-- is used by the update block in the Gifts tab.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local NextCore = require(Shared:WaitForChild("Core"):WaitForChild("NextUp"))
local WeatherCore = require(Shared:WaitForChild("Core"):WaitForChild("Weather")) -- the storm timer only for those who will be shown the event

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))

local NextUp = {}

type Item = { kind: string, at: number, name: string?, stage: number?, title: string?, eventId: string?, first: boolean? } -- like Core/NextUp.Item

local C = Config.UI.nextUp
local S = Strings.Next
local me = Players.LocalPlayer
local frame: TextButton? = nil
local lineLabel: TextLabel? = nil
local gifts: any = nil
local stepGoneAt: number? = nil -- since when there is no step banner
local rot = 0 -- the item index in the cycle
local rotUntil = 0
local shown: Item? = nil
local status: { [string]: string } = {} -- eventId -> the Enum.RsvpStatus name ("None" | "Going" | "NotGoing"); no key - not asked
local asking: { [string]: boolean } = {}
local onStatus: { () -> () } = {}

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "")
end

local function analytics(name: string, from: string)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, { from = from })
	end
end

local function setStatus(eventId: string, st: string)
	if status[eventId] == st then
		return
	end
	status[eventId] = st
	for _, fn in onStatus do
		task.spawn(fn)
	end
end

-- ---------------------------------------------------------------------------------------------- RSVP
-- the event RSVP status (cached; the first call asks Roblox in the background and returns nil)
function NextUp.rsvpStatus(eventId: string): string?
	if status[eventId] == nil and not asking[eventId] then
		asking[eventId] = true
		task.spawn(function()
			local ok, st = pcall(function()
				return SocialService:GetEventRsvpStatusAsync(eventId)
			end)
			asking[eventId] = nil
			if ok and typeof(st) == "EnumItem" then
				setStatus(eventId, st.Name)
			end
		end)
	end
	return status[eventId]
end

-- the Roblox RSVP window; from - where it was pressed ("hud" | "gifts") for analytics
function NextUp.rsvp(eventId: string, from: string)
	analytics("rsvp_prompt", from)
	task.spawn(function()
		local ok, st = pcall(function()
			return SocialService:PromptRsvpToEventAsync(eventId)
		end)
		if not ok then
			warn("[NextUp] RSVP: " .. tostring(st))
			return
		end
		if typeof(st) == "EnumItem" then
			if st.Name == "Going" and status[eventId] ~= "Going" then
				analytics("rsvp_going", from)
			end
			setStatus(eventId, st.Name)
		end
	end)
end

-- a subscription to status changes (the Gifts tab redraws the block)
function NextUp.onStatus(fn: () -> ())
	table.insert(onStatus, fn)
end

-- the next update for the Gifts block: (the item, how much is left as a string)
function NextUp.nextUpdate(): (Item?, string)
	local now = workspace:GetServerTimeNow()
	local u = NextCore.update(Content.Updates, now, nil)
	return u, if u then NextCore.left(u.at - now, Loc.t(S.days)) else ""
end

-- ---------------------------------------------------------------------------------------------- the line
local function items(now: number): { Item }
	local out: { Item } = {}
	local t = NextCore.timer({ dragons = Store.get("dragons"), nestOrder = Store.get("nestOrder"), eggs = Store.get("eggs") }, now)
	if t then
		table.insert(out, t)
	end
	-- a goal on screen during the wait - the Storm dragon (WeatherState.DragonAt, every ~30 min) and Starfall right now
	local ws = ReplicatedStorage:FindFirstChild("WeatherState")
	if ws then
		local endsAt = ws:GetAttribute("EndsAt")
		if ws:GetAttribute("Kind") == "starfall" and typeof(endsAt) == "number" and endsAt > now then
			table.insert(out, { kind = "starfall", at = endsAt })
		end
		local dragonAt = ws:GetAttribute("DragonAt")
		if ws:GetAttribute("Dragon") ~= true and typeof(dragonAt) == "number" and dragonAt > now and WeatherCore.eligible(Store.get("dragons"), Config.Balance.stormDragon) then
			table.insert(out, { kind = "storm", at = dragonAt })
		end
	end
	if gifts and gifts.tomorrow then
		local n, word = gifts.tomorrow()
		if n and word then
			table.insert(out, { kind = "tomorrow", at = 0, stage = n, name = word })
		end
	end
	local u = NextCore.update(Content.Updates, now, C.updateWithin)
	if u then
		table.insert(out, u)
	end
	return out
end

-- the firstborn is growing and the player has not mounted / taken off yet - the line says what to wait for
local function onboarded(flag: string): boolean
	local ob = Store.get("onboarding")
	return typeof(ob) == "table" and ob[flag] == true
end

local function urgentGrow(it: Item): boolean
	return it.kind == "grow" and it.first == true and ((it.stage == 1 and not onboarded("rode")) or (it.stage == 2 and not onboarded("flew")))
end

local function text(it: Item, now: number): string
	if it.kind == "grow" then
		local left = NextCore.left(it.at - now, Loc.t(S.days))
		if urgentGrow(it) then
			return fmt(if it.stage == 1 then S.growThenRide else S.growThenFly, { name = it.name or "", time = left })
		end
		return fmt(S.grow, { name = it.name or "", stage = Loc.t((Strings.Stage :: any)[it.stage or 0] or ""), time = left })
	elseif it.kind == "storm" then
		return fmt(S.stormIn, { time = NextCore.left(it.at - now, Loc.t(S.days)) })
	elseif it.kind == "starfall" then
		return Loc.t(S.starfallNow)
	elseif it.kind == "hatch" then
		return fmt(S.hatch, { time = NextCore.left(it.at - now, Loc.t(S.days)) })
	elseif it.kind == "tomorrow" then
		return fmt(Strings.Rewards.tomorrowTitle, { n = it.stage or 0, gift = it.name or "" })
	end
	local line = fmt(S.update, { title = it.title or "", time = NextCore.left(it.at - now, Loc.t(S.days)) })
	if it.eventId and NextUp.rsvpStatus(it.eventId) ~= "Going" then
		line ..= "  🔔"
	end
	return line
end

-- the same items and texts for the "while you were
-- away" card (Controllers/Away); before the first dragon - empty, like the line under the coins
function NextUp.list(): { Item }
	local dd = Store.get("dragons")
	if typeof(dd) ~= "table" or next(dd) == nil then
		return {}
	end
	return items(workspace:GetServerTimeNow())
end

function NextUp.text(it: Item): string
	return text(it, workspace:GetServerTimeNow())
end

-- seconds to show an item in the cycle (a timer longer)
function NextUp.hold(it: Item): number
	return if it.kind == "grow" or it.kind == "hatch" then C.timerSeconds else C.otherSeconds
end

local function tick()
	local f, ll = frame, lineLabel
	if not f or not ll then
		return
	end
	local step = f.Parent and f.Parent:FindFirstChild("Step")
	local stepOn = step ~= nil and step:IsA("GuiObject") and step.Visible
	local clock = os.clock()
	if stepOn or me:GetAttribute("Mounted") ~= nil or clock < UIKit.bannerUntil then
		stepGoneAt = if stepOn then nil else stepGoneAt
		f.Visible = false
		return
	end
	stepGoneAt = stepGoneAt or clock
	local now = workspace:GetServerTimeNow()
	-- for a newcomer before the first hatch the line managed to show "Aurora update in 18d" before the first step banner - noise next to
	-- Old Ash's greeting; there is nothing to wait for yet, the line - from the first dragon
	local dd = Store.get("dragons")
	local list = if typeof(dd) == "table" and next(dd) ~= nil then items(now) else {}
	-- the firstborn's growth until riding/flight - at once, without the quietAfter silence, and the line holds on it
	-- (without it many players who hatched left while the dragon grew)
	local urgentAt: number? = nil
	for i, it in list do
		if urgentGrow(it) then
			urgentAt = i
			break
		end
	end
	local quiet = if urgentAt then (C.quietUrgent or 1) else C.quietAfter -- the urgent one also gets a second of silence after the step banner
	if clock - (stepGoneAt :: number) < quiet then
		f.Visible = false
		return
	end
	if #list == 0 then
		f.Visible = false
		shown = nil
		return
	end
	if urgentAt then
		rot = urgentAt
		rotUntil = clock + C.timerSeconds
	elseif clock >= rotUntil then
		rot = rot % #list + 1
		local it = list[rot]
		rotUntil = clock + (if it.kind == "grow" or it.kind == "hatch" then C.timerSeconds else C.otherSeconds)
	end
	local it = list[math.clamp(rot, 1, #list)]
	shown = it
	ll.Text = text(it, now)
	f.Visible = true
end

-- right under the coin pill at its real size
local function place()
	local f = frame
	local pg = me:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local coins = hud and hud:FindFirstChild("Coins")
	local g = f and f:FindFirstAncestorOfClass("ScreenGui")
	if not f or not coins or not coins:IsA("GuiObject") or not g then
		return
	end
	local bottom = coins.AbsolutePosition.Y + coins.AbsoluteSize.Y + 4 - g.AbsolutePosition.Y
	f.Position = UDim2.new(0.5, 0, 0, math.floor(math.max(bottom, g.AbsoluteSize.Y * Config.UI.stepBanner.y)))
end

function NextUp.state(): string
	local f = frame
	return string.format("visible=%s kind=%s text=%s rsvp=%s", tostring(f ~= nil and f.Visible), tostring(shown and shown.kind), if lineLabel then lineLabel.Text else "-",
		tostring(status[(Content.Updates[1] :: any).eventId or ""]))
end

function NextUp.init(_snapshot: any, loaded: any)
	gifts = loaded.Gifts
end

function NextUp.start()
	local pg = me:WaitForChild("PlayerGui")
	local g = pg:WaitForChild("StepBanner", 30)
	if not g then
		return
	end
	local SB = Config.UI.stepBanner
	-- a button without its own look: the same pill as the step banner, slightly more transparent (a secondary line)
	local f = Instance.new("TextButton")
	f.Name = "Next"
	f.Text = ""
	f.AutoButtonColor = false
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, SB.y)
	f.Size = UDim2.fromScale(SB.width, SB.height * 0.8)
	f.BackgroundColor3 = UIKit.PANEL
	f.BackgroundTransparency = 0.18 + C.alpha
	f.Visible = false
	UIKit.corner(f, 0.5)
	-- the step banner appears instantly while NEXT went out only on its own tick (0.5 s) - hide at once
	task.spawn(function()
		local step = g:WaitForChild("Step", 30)
		if step and step:IsA("GuiObject") then
			step:GetPropertyChangedSignal("Visible"):Connect(function()
				if step.Visible and frame then
					frame.Visible = false
				end
			end)
		end
	end)
	UIKit.text(f, S.label, Color3.fromRGB(150, 200, 255), { Name = "Category", Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.16, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
	lineLabel = UIKit.text(f, "", Color3.fromRGB(235, 235, 240), { Name = "Line", Position = UDim2.fromScale(0.2, 0.1), Size = UDim2.fromScale(0.77, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
	f.Activated:Connect(function()
		local it = shown
		if it and it.kind == "update" and it.eventId and NextUp.rsvpStatus(it.eventId) ~= "Going" then
			NextUp.rsvp(it.eventId, "hud")
		end
	end)
	f.Parent = g
	UIKit.plain(f) -- the "what awaits you" line - text with an outline
	frame = f
	while true do
		local ok, err = pcall(tick)
		if not ok then
			warn("[NextUp] " .. tostring(err))
		end
		pcall(place)
		task.wait(C.every)
	end
end

return NextUp
