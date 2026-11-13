--!strict
-- Labels and buttons above the objects of the own nest (02 §1, §6): only for the owner, from attributes and tags set by the server.
-- Incubator: the pill "Meadow egg  2:59" (HatchAt - server time), when ready "Ready!" and the Hatch button (HatchReady).
-- A dragon tagged CanFeed: the button "Feed  60" (Feed). Above every dragon once per second "+N" in green (the Income attribute).
-- The coin pile: the sum (the Pot attribute). The "rarity / name / N/s" labels above a dragon are set by the server (DragonVisuals).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService") -- the arc of the first egg from the hands into the bowl
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Config = require(Shared:WaitForChild("Config")) -- 2.2: the Hatch now rules
local Content = require(Shared:WaitForChild("Content")) -- the element name on the incubator pill
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local Experiments = require(Core:WaitForChild("Experiments"))
local Economy = require(Core:WaitForChild("Economy")) -- the incubator price in coins

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))
local Store = require(script.Parent:WaitForChild("Store"))

local WorldUI = {}

local me = Players.LocalPlayer
local holder: Instance? = nil -- PlayerGui directly: a BillboardGui in a folder is not drawn
local warned: { [string]: boolean } = {}
local rings: { [BasePart]: BillboardGui } = {}
local pulses: { [UIScale]: Tween } = {} -- the pulse of the "Ready!" sign
local feeds: { [Model]: BillboardGui } = {}
local pileGui: BillboardGui? = nil

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function bb(adornee: Instance, size: UDim2, offsetY: number, interactive: boolean): BillboardGui
	local g = Instance.new("BillboardGui")
	g.Adornee = adornee
	g.Size = size
	g.StudsOffsetWorldSpace = UIKit.worldUp(adornee, offsetY) -- the rings and the pile are rotated cylinders
	g.AlwaysOnTop = true
	g.MaxDistance = 90
	g.Active = interactive
	g.ResetOnSpawn = false
	g.Name = "WUI"
	g.Parent = holder
	return g
end

-- show/hide a label with the menu in mind (HUD.setVisible): WantEnabled - what we want, Enabled - what is visible
local function want(g: BillboardGui, on: boolean)
	g:SetAttribute("WantEnabled", on)
	g.Enabled = on and not UIKit.worldUiHidden
end

local function myNest(): Model?
	for _, r in CollectionService:GetTagged("Incubator") do
		if r:GetAttribute("OwnerId") == me.UserId then
			local m = r.Parent and r.Parent.Parent
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	return nil
end

local loadedRef: any = nil -- 2.2: Shop (the context button Hatch now)

-- the pill and the button above the incubator ring
local function ringGui(r: BasePart): BillboardGui
	local g = rings[r]
	if g then
		return g
	end
	g = bb(r, UDim2.fromOffset(150, 124), 4.2, true) -- was 220x110 - on the phone it covered half the nest; +28 px for Hatch now
	g.MaxDistance = Config.UI.incubatorGui.maxDistance
	g:SetAttribute("DeclutterRank", 2)
	local sub: TextLabel
	if Config.UI.worldActionButtons then
		local b, s0 = UIKit.roundAction(g, Strings.Hints.hatch, UIKit.GREEN, function(btn)
			local reply = Net.call("HatchReady", (r:GetAttribute("Slot") :: number?) or 1)
			if not reply.ok then
				UIKit.shake(btn)
			end
		end)
		b.Name = "Hatch"
		b.Visible = false
		sub = s0
	else
		-- above the ring the "Ready!" sign with a pulse, the bottom Hatch button hatches (one on screen)
		sub = UIKit.text(g, "", UIKit.GOLD, { Name = "Sub", Position = UDim2.fromScale(0, 0.3), Size = UDim2.fromScale(1, 0.3) })
		local sc = Instance.new("UIScale")
		sc.Parent = sub
	end
	sub.Name = "Pill"
	sub.Position = UDim2.fromScale(0, 0.68)
	sub.Size = UDim2.fromScale(1, 0.3)
	-- 2.2 (07 §2 no. 1a): Hatch now under the pill while the egg warms (from 3:00 of the first session, remaining > 30 s); the price by step; a ticket - Use ticket
	local hn = UIKit.button(g, Strings.Shop.hatchNow, Color3.fromRGB(80, 150, 230), function(btn)
		local shop = loadedRef and loadedRef.Shop
		if shop then
			shop.buy("HatchNow", tostring((r:GetAttribute("Slot") :: number?) or 1), nil)
		else
			UIKit.shake(btn)
		end
	end, { minSize = Vector2.new(60, 30) })
	hn.Name = "HatchNow"
	hn.Visible = false
	hn.Position = UDim2.fromScale(0.1, 0.64)
	hn.Size = UDim2.fromScale(0.8, 0.36)
	rings[r] = g
	return g
end

local function updateRings(now: number)
	for _, r in CollectionService:GetTagged("Incubator") do
		if not r:IsA("BasePart") then
			continue
		end
		local state = r:GetAttribute("State")
		local mineR = r:GetAttribute("OwnerId") == me.UserId
		if not mineR or (state ~= "warming" and state ~= "ready") then
			local g = rings[r]
			if g then
				want(g, false)
			end
			continue
		end
		local g = ringGui(r)
		want(g, true)
		local pill = g:FindFirstChild("Pill") :: TextLabel
		local btn = g:FindFirstChild("Hatch") :: TextButton?
		local hn = g:FindFirstChild("HatchNow") :: TextButton?
		local pulse = pill:FindFirstChildOfClass("UIScale")
		if pulse then -- the "Ready!" sign breathes while the egg is ready (add. 2.17)
			local on = state == "ready"
			if on and not pulses[pulse] then
				local tw = TweenService:Create(pulse, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.15 })
				tw:Play()
				pulses[pulse] = tw
			elseif not on and pulses[pulse] then
				(pulses[pulse] :: Tween):Cancel()
				pulses[pulse] = nil
				pulse.Scale = 1
			end
		end
		if state == "ready" then
			pill.Text = Strings.Hints.ready
			pill.TextColor3 = UIKit.GOLD
			-- beyond hatchDistance the server answers too_far - no button, only "Ready!" (the button does not lie)
			local ch = me.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
			local d = if hrp then Vector3.new(r.Position.X - hrp.Position.X, 0, r.Position.Z - hrp.Position.Z).Magnitude else math.huge
			if btn then
				btn.Visible = d <= Config.Loop.hatchDistance
			end
			if hn then
				hn.Visible = false
			end
		else
			local left = math.max(0, ((r:GetAttribute("HatchAt") :: number?) or now) - now)
			-- the outcome is shown before any Hatch now payment - "Rare Storm inside 12:40" in the rarity color
			local rar = r:GetAttribute("Rarity") :: string?
			local elId = r:GetAttribute("Element") :: string?
			local elDef = elId and (Content.Elements :: any)[elId]
			if rar and elDef then
				pill.Text = fmt(Strings.Hatch.insideIn, { rarity = Loc.t(Strings.Rarity[rar] or rar), element = elDef.name, time = Format.clock(left) })
				pill.TextColor3 = UIKit.RARITY[rar] or Color3.new(1, 1, 1)
			else
				local egg = fmt(Strings.Hatch.eggAt, { zone = Loc.t(Strings.Zone[(r:GetAttribute("Zone") :: string?) or "Meadow"] or "") })
				pill.Text = fmt(Strings.Hatch.hatchingIn, { egg = egg, time = Format.clock(left) })
				pill.TextColor3 = Color3.new(1, 1, 1)
			end
			pill.Position = UDim2.fromScale(0, 0.3) -- without the button the pill is centered
			if btn then
				btn.Visible = false
			end
			local shop = loadedRef and loadedRef.Shop
			local show = hn ~= nil and shop ~= nil and Config.Shop.hatchNowEnabled and left >= Config.Shop.hatchNow.minRemaining and shop.robuxAllowed()
			if hn then
				hn.Visible = show
				if show then
					if shop.ticketFits("hatchNow", left) then
						hn.Text = Strings.Shop.useTicket
					else
						shop.contextPrice("hatchNow", left, function(txt: string)
							if hn.Parent and hn.Visible then
								hn.Text = Strings.Shop.hatchNow .. "  " .. txt
							end
						end)
					end
				end
			end
		end
		if state == "ready" then
			pill.Position = if btn and btn.Visible then UDim2.fromScale(0, 0.68) else UDim2.fromScale(0, 0.3)
		end
		-- without the round button and without Hatch now the window fits the label, otherwise an empty 150x124 px lay on the bottom
		-- Hatch button and Declutter dimmed "Ready!" right at the incubator
		local compact = not btn and not (hn and hn.Visible)
		g.Size = if compact then UDim2.fromOffset(150, 40) else UDim2.fromOffset(150, 124)
		if compact then
			pill.Position = UDim2.fromScale(0, 0)
			pill.Size = UDim2.fromScale(1, 1)
		else
			pill.Size = UDim2.fromScale(1, 0.3)
		end
	end
end

-- above the first locked own incubator - the button "Unlock 5K"
-- (Remote Buy "incubator"); the price - Economy.incubatorPrice by the number of open ones (Store incubators); not enough coins - the button shakes
-- the bowl and shelf buttons for coins - not when mounted and not on the
-- one-dragon day (no eggs beyond the first - no reason to buy space for them; they return with package 2)
local function hideUpgrades(): boolean
	if me:GetAttribute("Mounted") ~= nil then
		return true
	end
	local R = Config.Raid
	if R and R.on and R.firstEggOnly then
		local no = Store.get("nestOrder")
		if typeof(no) == "table" and #no >= 1 then
			-- eggs come again - the bowls and the shelf for coins are needed while raids remain today or an egg waits on the shelf
			local eggs = Store.get("eggs")
			local shelf = if typeof(eggs) == "table" and typeof(eggs.shelf) == "table" then #eggs.shelf else 0
			return not ((tonumber(me:GetAttribute("RaidLeft")) or 0) > 0 or shelf > 0)
		end
	end
	return false
end

local unlockGui: BillboardGui? = nil
local unlockRing: BasePart? = nil
local function updateUnlock()
	local first: BasePart? = nil
	for _, r in CollectionService:GetTagged("Incubator") do
		if r:IsA("BasePart") and r:GetAttribute("OwnerId") == me.UserId and r:GetAttribute("State") == "locked" then
			if not first or ((r:GetAttribute("Slot") :: number?) or 9) < ((first:GetAttribute("Slot") :: number?) or 9) then
				first = r
			end
		end
	end
	local price = Economy.incubatorPrice((Store.get("incubators") :: number?) or Config.Balance.incubators.start, Config.Balance)
	if not first or not price or hideUpgrades() then
		if unlockGui then
			want(unlockGui, false)
		end
		return
	end
	if unlockRing ~= first and unlockGui then
		unlockGui:Destroy()
		unlockGui = nil
	end
	if not unlockGui then
		local g = bb(first, UDim2.fromOffset(150, 44), 3.2, true)
		g.MaxDistance = 40
		local b = UIKit.button(g, "", Color3.fromRGB(226, 150, 60), function(btn)
			local reply = Net.call("Buy", "incubator")
			if not reply.ok then
				UIKit.shake(btn)
				local bn = loadedRef and loadedRef.Banners
				if bn then
					bn.toast(fmt(Strings.Errors[reply.reason or ""] or Strings.Errors.bad_request, { n = Format.number(reply.n or 0) }))
				end
			end
		end, { minSize = Vector2.new(60, 36) })
		b.Name = "Unlock"
		b.Size = UDim2.fromScale(1, 1)
		unlockGui = g
		unlockRing = first
	end
	local g = unlockGui :: BillboardGui
	want(g, true)
	local b = g:FindFirstChild("Unlock") :: TextButton?
	if b then
		local txt = fmt(Strings.Buy.unlock, { price = Format.number(price) })
		if b.Text ~= txt then
			b.Text = txt
		end
	end
end

-- above the first locked bowl of the own shelf - "+2 Shelf 10K" (Remote Buy "shelf")
local shelfGui: BillboardGui? = nil
local shelfCup: BasePart? = nil
local function updateShelf(nest: Model?)
	local cap = (Store.get("shelfCap") :: number?) or Config.Balance.shelf.start
	local price = Economy.shelfPrice(cap, Config.Balance)
	local f = nest and nest:FindFirstChild("Shelf")
	local cup = f and f:FindFirstChild("Shelf" .. tostring(cap + 1)) :: BasePart?
	if not price or not cup or hideUpgrades() then
		if shelfGui then
			want(shelfGui, false)
		end
		return
	end
	if shelfCup ~= cup and shelfGui then
		shelfGui:Destroy()
		shelfGui = nil
	end
	if not shelfGui then
		local g = bb(cup, UDim2.fromOffset(150, 44), 2.6, true)
		g.MaxDistance = 40
		local b = UIKit.button(g, "", Color3.fromRGB(226, 150, 60), function(btn)
			local reply = Net.call("Buy", "shelf")
			if not reply.ok then
				UIKit.shake(btn)
				local bn = loadedRef and loadedRef.Banners
				if bn then
					bn.toast(fmt(Strings.Errors[reply.reason or ""] or Strings.Errors.bad_request, { n = Format.number(reply.n or 0) }))
				end
			end
		end, { minSize = Vector2.new(60, 36) })
		b.Name = "ShelfPlus"
		b.Size = UDim2.fromScale(1, 1)
		shelfGui = g
		shelfCup = cup
	end
	local g = shelfGui :: BillboardGui
	want(g, true)
	local b = g:FindFirstChild("ShelfPlus") :: TextButton?
	if b then
		local txt = fmt(Strings.Buy.shelfButton, { price = Format.number(price) })
		if b.Text ~= txt then
			b.Text = txt
		end
	end
end

-- the feed button above a dragon tagged CanFeed
local function updateFeeds()
	for m, g in feeds do
		if not m.Parent or not m:HasTag("CanFeed") or m:GetAttribute("Companion") == true then
			g:Destroy()
			feeds[m] = nil
		end
	end
	for _, m in CollectionService:GetTagged("CanFeed") do
		-- no button above the companion - feeding happens at the nest (Feed All), in the field the server would answer too_far
		if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Companion") ~= true then
			local g = feeds[m]
			if not g and not Config.UI.worldActionButtons then
				-- above a hungry dragon the 🍖 sign without a price and without a press; Feed All at the bottom and the card feed
				local _, size = m:GetBoundingBox()
				g = bb(m.PrimaryPart or m, UDim2.fromOffset(40, 40), size.Y * 0.5 + 2.5, false)
				g.MaxDistance = 40
				g:SetAttribute("DeclutterRank", 2)
				UIKit.iconText(g, "🍖", { Name = "Hungry", Size = UDim2.fromScale(1, 1) })
				feeds[m] = g
			end
			if not g then
				local _, size = m:GetBoundingBox()
				g = bb(m.PrimaryPart or m, UDim2.fromOffset(110, 92), size.Y * 0.5 + 5.5, true) -- a circle + the price, above "+N"
				g.MaxDistance = 40
				local b, sub = UIKit.roundAction(g, Strings.Hints.feed, Color3.fromRGB(230, 120, 70), function(btn)
					local uid = m:GetAttribute("Uid")
					local reply = Net.call("Feed", if typeof(uid) == "string" then uid else "")
					if not reply.ok then
						UIKit.shake(btn)
					end
				end)
				b.Name = "Feed"
				sub.Name = "Price"
				feeds[m] = g
			end
			want(g, true)
			local sub = g:FindFirstChild("Price") :: TextLabel?
			local b = g:FindFirstChild("Feed") :: TextButton?
			if sub and b then
				local price = (m:GetAttribute("FeedPrice") :: number?) or 0
				sub.Text = Format.number(price)
				local canPay = (Store.get("coins") or 0) >= price
				b.BackgroundColor3 = if canPay then Color3.fromRGB(230, 120, 70) else UIKit.GREY
				sub.TextColor3 = if canPay then UIKit.GOLD else Color3.fromRGB(200, 200, 200)
			end
		end
	end
end

-- "+N" above every own dragon once per second
local function popIncome(nest: Model)
	local f = nest:FindFirstChild("Dragons")
	if not f then
		return
	end
	if UIKit.worldUiHidden then
		return
	end
	local models = f:GetDescendants()
	for _, c in CollectionService:GetTagged("Companion") do -- a companion without a copy in the nest - "+N" above it
		table.insert(models, c)
	end
	for _, m in models do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Income") then
			local _, size = m:GetBoundingBox()
			local g = bb(m.PrimaryPart or m, UDim2.fromOffset(80, 30), size.Y * 0.5 + 0.5, false) -- smaller, to the side, not under the Feed button
			g:SetAttribute("DeclutterRank", 0) -- when running into another label "+N" is dimmed first
			g.StudsOffsetWorldSpace = Vector3.new(size.X * 0.5 + 1.2, size.Y * 0.5 + 0.5, 0)
			g.MaxDistance = 45
			local t = UIKit.text(g, "+" .. Format.number((m:GetAttribute("Income") :: number) * UIKit.rateMult()), UIKit.GREEN, { Size = UDim2.fromScale(1, 1) }) -- with the nest multiplier
			TweenService:Create(g, TweenInfo.new(0.9), { StudsOffsetWorldSpace = g.StudsOffsetWorldSpace + Vector3.new(0, 2.2, 0) }):Play()
			TweenService:Create(t, TweenInfo.new(0.9), { TextTransparency = 1 }):Play()
			local s = t:FindFirstChildOfClass("UIStroke")
			if s then
				TweenService:Create(s, TweenInfo.new(0.9), { Transparency = 1 }):Play()
			end
			task.delay(0.95, function()
				g:Destroy()
			end)
		end
	end
end

local function updatePile(nest: Model?)
	local pile = nest and nest:FindFirstChild("CoinPile")
	local pot = pile and (pile:GetAttribute("Pot") :: number?) or 0
	if not pile or pot < 1 then
		if pileGui then
			want(pileGui, false)
		end
		return
	end
	if not pileGui or pileGui.Adornee ~= pile then
		if pileGui then
			pileGui:Destroy()
		end
		pileGui = bb(pile, UDim2.fromOffset(160, 44), 3, false)
		pileGui.MaxDistance = Config.UI.pileGui.maxDistance
		UIKit.coin(pileGui, 0, { Name = "Coin", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.42, 0.5), Size = UDim2.fromScale(0.2, 0.8) }) -- without the icon the number above the pile read as a random digit
		UIKit.text(pileGui, "", UIKit.GOLD, { Name = "Pot", Position = UDim2.fromScale(0.46, 0), Size = UDim2.fromScale(0.54, 1), TextXAlignment = Enum.TextXAlignment.Left })
	end
	local g = pileGui :: BillboardGui
	want(g, true)
	local lbl = g:FindFirstChild("Pot") :: TextLabel
	lbl.Text = Format.number(pot)
end

function WorldUI.init(_snapshot: any, _loaded: any)
	loadedRef = _loaded -- Shop loads after WorldUI: looked up on demand
	holder = me:WaitForChild("PlayerGui")
end

-- at the Keeper's stall the Feed prompt - the same berries as Feed All
-- at the nest (the server Nest.feed allows it at the stall too, stallFeedDistance)
-- the spawn point is 10 studs from the stall - the prompt is visible only
-- when there is someone to feed (my dragon tagged CanFeed: growing and not fed - the same rule as Feed all at the nest in the HUD)
-- everyone
-- spawns on the shared plaza plate (0,-30), the stall is 10 studs away (0,-40) with a prompt radius of 12. While the character stands on the plate
-- where it spawned, the stall button is off; stepped off the plate - as usual (until the next spawn). Not ProximityPromptService.Enabled:
-- a prompt that was within the radius while the service was off is not shown after switching on until you leave the radius
local onSpawnPad = true
local function updateSpawnPad()
	if onSpawnPad then
		local ch = me.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local pad = workspace:FindFirstChildWhichIsA("SpawnLocation")
		if not pad then
			onSpawnPad = false -- no plate (streaming) - do not hide
		elseif r and r:IsA("BasePart") then
			local d = pad.CFrame:PointToObjectSpace(r.Position)
			local half = pad.Size / 2
			if math.abs(d.X) > half.X + 0.5 or math.abs(d.Z) > half.Z + 0.5 or math.abs(d.Y) > 8 then
				onSpawnPad = false
			end
		end
	end
end

local stallPr: ProximityPrompt? = nil
local function updateStall()
	local pr = stallPr
	if not pr or not pr.Parent then
		return
	end
	local any = false
	for _, m in CollectionService:GetTagged("CanFeed") do
		if m:GetAttribute("OwnerId") == me.UserId then
			any = true
			break
		end
	end
	any = any and not onSpawnPad
	if pr.Enabled ~= any then
		pr.Enabled = any
	end
end

local function stallPrompt(stall: Instance)
	if not stall:IsA("BasePart") or stall:FindFirstChild("StallFeed") then
		return
	end
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "StallFeed"
	pr.ActionText = Strings.World.stallFeed
	pr.ObjectText = Strings.World.stallBerries
	pr.HoldDuration = 0
	pr.MaxActivationDistance = Config.Loop.stallFeedDistance - 2
	pr.RequiresLineOfSight = false
	pr.Triggered:Connect(function()
		Net.call("Feed", "all") -- the result (Fed! / not enough coins / everyone is fed) is shown by the server as a toast
	end)
	pr.Enabled = false
	pr.Parent = stall
	stallPr = pr
	updateStall()
end

-- the server puts the first egg into the bowl by itself - so the kid sees where it went
-- a copy of the egg flies from the hands in an arc into the bowl over seconds s (the own egg in hand is hidden locally for that time); on arrival the server places it
local function eggFly(p: any)
	if typeof(p) ~= "table" or typeof(p.from) ~= "Vector3" or typeof(p.to) ~= "Vector3" then
		return
	end
	local ch = me.Character
	local src = ch and ch:FindFirstChild("CarriedEgg")
	if not src or not src:IsA("Model") then
		return
	end
	local copy = src:Clone()
	for _, d in copy:GetDescendants() do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		end
	end
	copy.Parent = workspace
	local from, to = p.from :: Vector3, (p.to :: Vector3) + Vector3.new(0, 1.2, 0)
	local T = math.max(tonumber(p.seconds) or 0.45, 0.1)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / T, 0, 1)
		local at = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 4, 0)
		copy:PivotTo(CFrame.new(at) * CFrame.Angles(0, a * 6, 0))
		if a >= 1 then
			if conn then
				conn:Disconnect()
			end
			copy:Destroy()
		end
	end)
	task.delay(T + 1, function() -- a safeguard: no frames came (the window was minimized)
		if copy.Parent then
			if conn then
				conn:Disconnect()
			end
			copy:Destroy()
		end
	end)
end

function WorldUI.start()
	Net.on("eggFly", function(p)
		local ok, err = pcall(eggFly, p)
		if not ok then
			warn("[WorldUI] eggFly: " .. tostring(err))
		end
	end)
	me.CharacterAdded:Connect(function()
		onSpawnPad = true
	end)
	CollectionService:GetInstanceAddedSignal("Stall"):Connect(stallPrompt)
	for _, st in CollectionService:GetTagged("Stall") do
		stallPrompt(st)
	end
	-- the "no label" group (even UserId) dims the Meadow egg labels locally (tag EggLabel, server)
	if not Experiments.eggLabels(me.UserId, Config.World.eggMarks) then
		local function off(g: Instance)
			if g:IsA("BillboardGui") then
				g.Enabled = false
			end
		end
		CollectionService:GetInstanceAddedSignal("EggLabel"):Connect(off)
		for _, g in CollectionService:GetTagged("EggLabel") do
			off(g)
		end
	end
	local acc = 0
	while true do
		task.wait(0.25)
		local now = workspace:GetServerTimeNow()
		local nest = myNest()
		for name, fn in { rings = function()
			updateRings(now)
		end, feeds = updateFeeds, stall = function()
			updateSpawnPad()
			updateStall()
		end, unlock = updateUnlock, pile = function()
			updatePile(nest)
		end, shelf = function()
			updateShelf(nest)
		end } do
			local ok, err = pcall(fn)
			if not ok and not warned[name] then
				warned[name] = true
				warn("[WorldUI] " .. name .. ": " .. tostring(err))
			end
		end
		acc += 0.25
		if acc >= 1 then
			acc = 0
			if nest then
				pcall(popIncome, nest)
			end
		end
	end
end

return WorldUI
