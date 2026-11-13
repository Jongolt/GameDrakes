--!strict
-- The HUD of the first minutes (02 §6): the screen center is empty. Top center - coins in large type (K/M/B) and under them the income "+N/s" in green
-- (computed from the nest data with the same formula as on the server: Core/Economy.nestRate). Bottom center - one button by
-- situation: Hatch (own incubator tagged ReadyToHatch) or Feed all (an own dragon tagged CanFeed and enough coins).
-- The left column - colored menu plaques (Shop, Dragons, Index); the menu controllers add them through HUD.addMenuButton.
-- P33 (Ride A Pet): Settings - a dark round button in the Roblox button row at the top left (HUD.addTopbarButton). Coins from pickups fly in as icons (CoinFlight) and call HUD.catch: the counter "catches"
-- (x1.25 for 0.15 s), "+N" floats up (02 §2, 0:18-0:30).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local ShopCore = require(Core:WaitForChild("Shop")) -- 2.2: income multipliers as on the server
local IndexCore = require(Core:WaitForChild("Index"))
local Economy = require(Core:WaitForChild("Economy"))
local Dragons = require(Core:WaitForChild("Dragons"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))

local HUD = {}

local B = Config.Balance
local me = Players.LocalPlayer
local gui: ScreenGui? = nil
local coinsLabel: TextLabel? = nil
local rateLabel: TextLabel? = nil
local coinBox: Frame? = nil
local boostLeft, boostAt = 0, 0 -- 2.2: the x2 boost timer in the income line ("+83/s x2 29:57"); the seconds run only online, the client counts from the boost packet
local boostSuffix = ""
local coinIcon: GuiObject? = nil
local actionBtn: TextButton? = nil
local feedBtn: TextButton? = nil -- the second button Feed all
local action: { kind: string, slot: number?, uid: string? }? = nil
local leftCount, rightCount = 0, 0
local leftColumn: Frame? = nil -- the plaque column on the left (UIListLayout)
local companion: any = nil -- the Ride / Fly button at the bottom center
local perf: any = nil -- the act=... note in the Perf journal when an action button is pressed
local uistack: any = nil

-- the fact goes into the Perf journal - the action kind, the server reply (ok | reason) and its time, which modal screen was open at the moment of the click
local function noteAction(kind: string, reply: any, t0: number, modal: string?)
	if perf and perf.note then
		pcall(perf.note, string.format("act=%s:%s/%.1f modal=%s", kind, if typeof(reply) == "table" and reply.ok then "ok" else tostring(typeof(reply) == "table" and reply.reason or reply), os.clock() - t0, modal or "-"))
	end
end
local ACTION_COLOR = { hatch = UIKit.GREEN, feed = UIKit.GREEN, ride = Color3.fromRGB(226, 150, 60), fly = Color3.fromRGB(80, 150, 230) }

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rate(): number
	local data = Store.all()
	if typeof(data.dragons) ~= "table" or typeof(data.nestOrder) ~= "table" then
		return 0
	end
	-- 2.2: the same multipliers as on the server (Index, VIP, x2, boost) - the "+N/s" figure matches the accrual
	return Economy.nestRate(Dragons.nestList(data :: any) :: any, ShopCore.rateMods(data, IndexCore.pct(data.index)) :: any, B)
end

local function refresh()
	if coinsLabel then
		coinsLabel.Text = Format.number(math.floor(Store.get("coins") or 0))
	end
	if rateLabel then
		local r = rate()
		rateLabel.Text = "+" .. fmt(Strings.HUD.perSecond, { n = Format.number(r) }) .. boostSuffix
		rateLabel.Visible = r > 0 or boostSuffix ~= "" -- "+0/s" for a newcomer is noise
	end
end

local function mine(inst: Instance): boolean
	return inst:GetAttribute("OwnerId") == me.UserId
end

local function rootPos(): Vector3?
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position else nil
end

local function flatDist(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- the center of the own nest
local nestCache: Model? = nil
local function myNestPos(): Vector3?
	local n = nestCache
	if not n or not n.Parent or n:GetAttribute("OwnerId") ~= me.UserId then
		n = nil
		local world = workspace:FindFirstChild("World")
		local nests = world and world:FindFirstChild("Nests")
		if nests then
			for _, c in nests:GetChildren() do
				if c:IsA("Model") and c:GetAttribute("OwnerId") == me.UserId then
					n = c
					break
				end
			end
		end
		nestCache = n
	end
	if not n then
		return nil
	end
	local base = n.PrimaryPart or n:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base.Position else nil
end

-- the button by situation: Hatch outranks Feed all; only nearby (Feed all - at the nest; the server checks the same distances);
-- the main button - Hatch > Ride/Fly > Feed all;
-- if both the companion and hungry dragons are nearby - a second Feed all button left of the main one
local function pickActions(): ({ kind: string, slot: number?, uid: string? }?, boolean)
	local pos = rootPos()
	if not pos then
		return nil, false
	end
	local LP = Config.Loop
	local coins = Store.get("coins") or 0
	local canFeed = false
	local nestPos = myNestPos()
	local atNest = nestPos ~= nil and flatDist(nestPos, pos) <= LP.feedDistance -- the same rule as on the server
	for _, m in if atNest then CollectionService:GetTagged("CanFeed") else {} do
		if mine(m) and m:IsA("Model") and coins >= ((m:GetAttribute("FeedPrice") :: number?) or math.huge) and flatDist(m:GetPivot().Position, pos) <= LP.feedDistance then
			canFeed = true
			break
		end
	end
	for _, r in CollectionService:GetTagged("ReadyToHatch") do
		if mine(r) and r:IsA("BasePart") and flatDist(r.Position, pos) <= LP.hatchDistance then
			return { kind = "hatch", slot = r:GetAttribute("Slot") :: number }, canFeed
		end
	end
	if companion then -- the companion nearby (stage >= 1, not mounted): Ride for a teen, Fly for an adult
		local uid, stage = companion.near()
		if uid then
			return { kind = if (stage or 1) >= 2 then "fly" else "ride", uid = uid }, canFeed
		end
	end
	if canFeed then
		return { kind = "feed" }, false
	end
	return nil, false
end

local function styleAction(b: TextButton, k: string)
	b.Text = if k == "hatch" then Strings.Hints.hatch elseif k == "feed" then Strings.Hints.feedAll elseif k == "fly" then Strings.Hints.fly else Strings.Hints.ride
	b.BackgroundColor3 = ACTION_COLOR[k] or UIKit.GREEN
end

local function updateAction()
	local b = actionBtn
	local b2 = feedBtn
	if not b then
		return
	end
	local a, alsoFeed = pickActions()
	action = a
	if not a then
		b.Visible = false
		if b2 then
			b2.Visible = false
		end
		return
	end
	b.Visible = true
	styleAction(b, a.kind)
	local two = alsoFeed and b2 ~= nil
	b.Position = UDim2.fromScale(if two then 0.6 else 0.5, 0.965)
	if b2 then
		b2.Visible = two
		if two then
			styleAction(b2, "feed")
			b2.Position = UDim2.fromScale(0.38, 0.965)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- public interface
function HUD.setVisible(on: boolean)
	if gui then
		gui.Enabled = on
	end
	-- the server does not place an ambush while a menu is open or a scene is playing
	local rf = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local busy = rf and rf:FindFirstChild("UiBusy")
	if busy and busy:IsA("RemoteEvent") then
		busy:FireServer(not on)
	end
	UIKit.worldUiHidden = not on
	UIKit.hudHidden = not on
	-- on PC the Roblox player list (CoreGui, always above ours) covered the book's cross and the name window
	-- the click landed on a player row and opened Examine Avatar; while a menu or a scene is open - the list is hidden
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, on)
	end)
	local pg = me:FindFirstChild("PlayerGui")
	if pg then
		for _, name in { "Movement", "Quests", "StepBanner", "WorldTimers", "Topbar", "FreeGiftCard", "InviteCard" } do -- ; P33/P35: the Roblox row and the timers by the jump; side cards
			local s = pg:FindFirstChild(name)
			if s and s:IsA("ScreenGui") then
				if on then
					s.Enabled = s:GetAttribute("HudWasEnabled") ~= false -- Movement is off by itself until mounted (Fly): restore as it was
					s:SetAttribute("HudWasEnabled", nil)
				else
					s:SetAttribute("HudWasEnabled", s.Enabled)
					s.Enabled = false
				end
			end
		end
		for _, g in pg:GetChildren() do
			if g:IsA("BillboardGui") and (g.Name == "WUI" or g.Name == "HintArrow") then
				g.Enabled = on and g:GetAttribute("WantEnabled") ~= false
			end
		end
	end
	local sb = pg and pg:FindFirstChild("StepBanner") -- the step banner hides together with the HUD (menu, hatch scene)
	if sb and sb:IsA("ScreenGui") then
		sb.Enabled = on
	end
end

-- :
-- combat focus - while Gloom is near, only the fight is on screen (coins, the stage bar, BREATH, controls): the Keeper, the step banner (and NextUp in
-- it), event timers, side cards and offer windows, labels with buttons (WUI), hint arrows and paths, "Pick up" buttons
-- are hidden. Combat calls every 0.25 s: anything that pops up mid-fight is hidden again, after the fight everything returns. ProximityPrompt hints -
-- one by one (Enabled), not by the service: a ProximityPromptService switched off and on again does not show the prompt until you leave
-- the radius
local FOCUS_HIDE = { "Quests", "StepBanner", "WorldTimers", "FreeGiftCard", "InviteCard", "PassCard", "AwayCard" }
local focusOn = false
local focusPrompts: { [ProximityPrompt]: boolean } = {}
ProximityPromptService.PromptShown:Connect(function(p: ProximityPrompt)
	if focusOn and p.Enabled then
		focusPrompts[p] = true
		p.Enabled = false
	end
end)
-- keepGuide - chase
-- focus, one task on screen "run home": the same is hidden as in combat, except the step banner and the home arrow
function HUD.setFocus(on: boolean, keepGuide: boolean?): boolean
	local pg = me:FindFirstChild("PlayerGui")
	if not pg or (gui and not gui.Enabled) then
		return focusOn -- a menu is open or a scene is playing: HUD.setVisible owns the screens, the focus is not changed until it ends
	end
	if on then
		for _, name in FOCUS_HIDE do
			local s = pg:FindFirstChild(name)
			if keepGuide and name == "StepBanner" then
				if s and s:IsA("ScreenGui") and s:GetAttribute("FocusHid") then -- hidden by combat focus - restore
					s:SetAttribute("FocusHid", nil)
					s.Enabled = true
				end
			elseif s and s:IsA("ScreenGui") and s.Enabled then
				s:SetAttribute("FocusHid", true)
				s.Enabled = false
			end
		end
		for _, g in pg:GetChildren() do
			if g:IsA("BillboardGui") and g.Name == "HintArrow" and keepGuide then
				if not g.Enabled and g:GetAttribute("WantEnabled") ~= false then
					g.Enabled = true
				end
			elseif g:IsA("BillboardGui") and (g.Name == "WUI" or g.Name == "HintArrow") and g.Enabled then
				g.Enabled = false
			end
		end
		UIKit.worldUiHidden = true
		UIKit.focusGuide = keepGuide == true -- a chase with the egg - the screen-edge pointer (Hints.updateEdge) is not hidden
	elseif focusOn then
		for _, s in pg:GetChildren() do
			if s:IsA("ScreenGui") and s:GetAttribute("HudWasEnabled") ~= nil and not s:GetAttribute("FocusHid") then
				-- a side card created during the fight (UIKit.sideCard sees worldUiHidden and waits for the HUD) - restore
				s.Enabled = s:GetAttribute("HudWasEnabled") == true
				s:SetAttribute("HudWasEnabled", nil)
			end
			if s:IsA("ScreenGui") and s:GetAttribute("FocusHid") then
				s:SetAttribute("FocusHid", nil)
				s.Enabled = true
			elseif s:IsA("BillboardGui") and (s.Name == "WUI" or s.Name == "HintArrow") then
				s.Enabled = s:GetAttribute("WantEnabled") ~= false
			end
		end
		for p in focusPrompts do
			if p.Parent then
				p.Enabled = true
			end
		end
		focusPrompts = {}
		UIKit.worldUiHidden = false
		UIKit.focusGuide = false
	end
	focusOn = on
	return focusOn
end

-- a start in waves.
-- A newcomer - no dragon yet, or the first session, no Gloom cleared and less than newbie.seconds played. They see the coins, the egg and one
-- step; the left menu (Shop, Dragons, Index), the Keeper, pass buttons and offer cards appear after the first cleared stage.
-- Old players (sessions > 1) are not affected. onboarding.stage in the profile does not move past "spawn" - we do not rely on it
local NEWBIE_HIDE = { "Quests", "FreeGiftCard", "InviteCard", "PassCard" }
local newbieOn = false
local clientStart = os.clock() -- playSeconds is not updated on the client - play time is counted with our own clock
local playAtStart: number? = nil
local function isNewbie(): boolean
	local N = Config.UI.newbie
	if not (N and N.on) then
		return false
	end
	local d = Store.all()
	local n = 0
	for _ in (if typeof(d.dragons) == "table" then d.dragons else {}) :: any do
		n += 1
	end
	-- newbie mode by play time from the profile (playSeconds + this session), not by sessions - after Reset and rejoins
	-- the session count is > 1, while old players have a lot of play time and the mode does not switch on
	if n == 0 then
		playAtStart = playAtStart or (tonumber(d.playSeconds) or 0)
		return (playAtStart :: number) + (os.clock() - clientStart) < N.seconds
	end
	-- newbie mode holds until the golden egg is home (or until newbie.seconds of play), not until the first cleared Gloom stage -
	-- otherwise the left menu, the Keeper, chips, cards and the storm pill all come out at once
	local ge = if typeof(d.glowEgg) == "table" then d.glowEgg else nil
	local glowTaken = ge ~= nil and (tonumber(ge.taken) or 0) > 0
	playAtStart = playAtStart or (tonumber(d.playSeconds) or 0)
	local played = (playAtStart :: number) + (os.clock() - clientStart)
	return not glowTaken and played < N.seconds
end
function HUD.newbie(): boolean
	return newbieOn
end
-- a newcomer sees
-- the shop in the left menu; Dragons and Index - after the golden egg, as before
local function keepForNewbie(b: Instance): boolean
	return b.Name == "Menu_" .. Strings.HUD.shop
end
local function setNewbie(on: boolean)
	local pg = me:FindFirstChild("PlayerGui")
	if not pg or (gui and not gui.Enabled) then
		return -- a menu or a scene: HUD.setVisible owns the screens
	end
	if leftColumn then
		leftColumn.Visible = true
		for _, b in leftColumn:GetChildren() do
			if b:IsA("GuiButton") then
				b.Visible = not on or keepForNewbie(b)
			end
		end
	end
	for _, name in NEWBIE_HIDE do
		local s = pg:FindFirstChild(name)
		if s and s:IsA("ScreenGui") then
			if on and s.Enabled then
				s:SetAttribute("NewbieHid", true)
				s.Enabled = false
			elseif not on and s:GetAttribute("NewbieHid") then
				s:SetAttribute("NewbieHid", nil)
				if not focusOn then
					s.Enabled = true
				else
					s:SetAttribute("FocusHid", true) -- a fight is on: it returns together with the focus
				end
			end
		end
	end
	newbieOn = on
end

-- the center of the coin icon on screen (for the coin flight); nil if the HUD is hidden
function HUD.coinAnchor(): Vector2?
	local i = coinIcon
	if not i or not gui or not gui.Enabled then
		return nil
	end
	return i.AbsolutePosition + i.AbsoluteSize / 2
end

-- the counter "catches" coins: x1.25 for 0.15 s; plus > 0 - "+N" floats up
function HUD.catch(plus: number)
	local box = coinBox
	if not box then
		return
	end
	local sc = box:FindFirstChildOfClass("UIScale") :: UIScale
	sc.Scale = 1.25
	TweenService:Create(sc, TweenInfo.new(0.15), { Scale = 1 }):Play()
	if plus > 0 then
		local p = UIKit.text(box, "+" .. Format.number(plus), UIKit.GREEN, { Position = UDim2.fromScale(0.3, 1.05), Size = UDim2.fromScale(0.5, 0.4) })
		TweenService:Create(p, TweenInfo.new(1), { Position = UDim2.fromScale(0.3, 0.2), TextTransparency = 1 }):Play()
		local st = p:FindFirstChildOfClass("UIStroke") -- the stroke did not fade with the text - "+N" turned muddy brown
		if st then
			TweenService:Create(st, TweenInfo.new(1), { Transparency = 1 }):Play()
		end
		task.delay(1, function()
			p:Destroy()
		end)
	end
end

-- the HUD screen and the coin pill - the pass buttons stand on its sides; the nest income per second (like "+N/s")
function HUD.coinFrame(): (ScreenGui?, Frame?)
	return gui, coinBox
end

function HUD.rate(): number
	return rate()
end

-- the action button at the bottom (for the hint arrow above it); nil if not visible
function HUD.actionButton(): TextButton?
	local b = actionBtn
	if b and b.Visible and gui and gui.Enabled then
		return b
	end
	return nil
end

function HUD.currentAction(): string?
	return action and action.kind
end

-- menu plaques (02 §6; craft/04 §7, §7.9: the leaders have buttons of one style with an icon and a word): left - the column under the Roblox
-- button, right - the column at the vertical center on the right. One color and size for all; the icon on top, the word below.
function HUD.addMenuButton(side: string, text: string, color: Color3?, onClick: () -> (), iconId: string?): TextButton
	local g = gui :: ScreenGui
	local P = Config.UI.plaque
	local b = Instance.new("TextButton")
	b.Name = "Menu_" .. text
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = color or Color3.fromRGB(P.color[1], P.color[2], P.color[3])
	UIKit.corner(b, 0.22)
	local st = Instance.new("UIStroke")
	st.Color = UIKit.STROKE
	st.Thickness = 3
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	UIKit.gloss(b, 0.26)
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(54, 54) -- at 44 the word on the plaque is 10 px; at 54 - 12-13 px
	lim.Parent = b
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = P.aspect
	ar.Parent = b
	-- the icon from primitives, the word below (HTTYD Shop/Menu)
	-- an emoji icon on top, the word below, the color of the book tab
	local hasIcon = iconId ~= nil and iconId ~= ""
	if hasIcon then
		UIKit.iconText(b, iconId :: string, { Position = UDim2.fromScale(0.1, 0.05), Size = UDim2.fromScale(0.8, 0.55) })
	end
	UIKit.text(b, text, Color3.new(1, 1, 1), { Name = "Word", Position = UDim2.fromScale(0.04, if hasIcon then 0.63 else 0.2), Size = UDim2.fromScale(0.92, if hasIcon then 0.32 else 0.6) })
	b.Activated:Connect(function()
		local sc = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
		sc.Parent = b
		sc.Scale = 0.9
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if UIKit.onPress then
			UIKit.onPress()
		end
		-- before that, presses
		-- were not counted; now Analytics "ui" {k} -> the ui_tap event + a counter in the profile (analytics.taps)
		pcall(function()
			local folder = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			local r = folder and folder:FindFirstChild("Analytics")
			if r and r:IsA("RemoteEvent") then
				local k = string.lower(string.sub((string.gsub(text, "[^%a]", "")), 1, 16))
				if k ~= "" then
					r:FireServer("ui", { k = side .. "_" .. k })
				end
			end
		end)
		onClick()
	end)
	if side == "left" then
		-- a column with UIListLayout - the plaques stand at their real size (no smaller than 44 px) with a gap
		local col = leftColumn
		if not col then
			local c = Instance.new("Frame")
			c.Name = "LeftColumn"
			c.BackgroundTransparency = 1
			c.Position = UDim2.fromScale(0.015, 0.15)
			c.Size = UDim2.fromScale(0.2, 0.62)
			local l = Instance.new("UIListLayout")
			l.FillDirection = Enum.FillDirection.Vertical
			l.HorizontalAlignment = Enum.HorizontalAlignment.Left
			l.SortOrder = Enum.SortOrder.LayoutOrder
			l.Padding = UDim.new(0, 6)
			l.Parent = c
			c.Parent = g
			col = c
			leftColumn = c
		end
		b.LayoutOrder = leftCount
		b.Size = UDim2.fromScale(1, P.height / 0.62)
		b.Visible = not newbieOn or keepForNewbie(b) -- a button created while already in newbie mode
		b.Parent = col
		leftCount += 1
		return b
	else -- on the right top-down from 0.28: does not touch the flight buttons at the bottom
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.fromScale(0.985, 0.28 + rightCount * (P.height + 0.02))
		rightCount += 1
	end
	b.Size = UDim2.fromScale(0.2, P.height)
	b.Parent = g
	return b
end

-- P33 (Ride A Pet [EVENT]: "backpack" and "settings" - dark circles right after the Roblox menu and chat): a row of own buttons in
-- the free part of the Roblox top bar (ScreenInsets.TopbarSafeInsets), a circle of the same color and size as the system ones,
-- an emoji icon. The order is the call order.
local topbar: Frame? = nil
function HUD.addTopbarButton(name: string, glyph: string, onClick: () -> ()): TextButton
	local T = Config.UI.topbar
	local row = topbar
	if not row then
		local g = UIKit.screen("Topbar", 3)
		g.ScreenInsets = Enum.ScreenInsets.TopbarSafeInsets
		local f = Instance.new("Frame")
		f.Name = "Row"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromScale(1, 1)
		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Horizontal
		-- the system circles sit at
		-- 12-56 of 58 - we press to the bar bottom with an inset T.bottom, a gap T.left on the left as between the Roblox circles
		list.VerticalAlignment = Enum.VerticalAlignment.Bottom
		list.HorizontalAlignment = Enum.HorizontalAlignment.Left
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Padding = UDim.new(0, T.gap)
		list.Parent = f
		local pad = Instance.new("UIPadding")
		pad.PaddingBottom = UDim.new(0, T.bottom or 2)
		pad.PaddingLeft = UDim.new(0, T.left or 9)
		pad.Parent = f
		f.Parent = g
		row = f
		topbar = f
	end
	local r = row :: Frame
	local b = Instance.new("TextButton")
	b.Name = "Top_" .. name
	b.LayoutOrder = #r:GetChildren()
	b.AutoButtonColor = false
	b.Text = ""
	b.BackgroundColor3 = Color3.fromRGB(T.color[1], T.color[2], T.color[3])
	b.BackgroundTransparency = T.transparency
	b.SizeConstraint = Enum.SizeConstraint.RelativeYY -- the bar height, no larger than the system circle
	b.Size = UDim2.fromScale(1, 1)
	local lim = Instance.new("UISizeConstraint")
	lim.MaxSize = Vector2.new(T.size, T.size)
	lim.Parent = b
	UIKit.corner(b, 1)
	UIKit.iconText(b, glyph, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.56, 0.56) })
	b.Activated:Connect(function()
		UIKit.press(b)
		onClick()
	end)
	b.Parent = r
	return b
end

function HUD.init(_snapshot: any, loaded: any)
	companion = loaded.Companion
	perf = loaded.Perf
	uistack = loaded.UIStack
	local g = UIKit.screen("HUD", 2)
	gui = g
	-- the pill at the top center, "+N/s" in green under it
	local box = Instance.new("Frame")
	box.Name = "Coins"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.fromScale(0.5, 0.012)
	box.Size = UDim2.fromScale(0.22, 0.09)
	local boxLim = Instance.new("UISizeConstraint") -- on the phone the pill is 29 px and "+N/s" 9 px; not below 46 (the step banner goes under it)
	boxLim.MinSize = Vector2.new(150, 46)
	boxLim.Parent = box
	Instance.new("UIScale").Parent = box
	local pill = UIKit.pill(box, { Name = "Pill", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.62) })
	coinIcon = UIKit.coin(pill, 0, { Name = "CoinIcon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.05, 0.5), Size = UDim2.fromScale(0.2, 0.8) })
	coinsLabel = UIKit.text(pill, "0", UIKit.CREAM, { Name = "Amount", Position = UDim2.fromScale(0.3, 0.08), Size = UDim2.fromScale(0.64, 0.84), TextXAlignment = Enum.TextXAlignment.Left })
	rateLabel = UIKit.text(box, "+0/s", UIKit.GREEN, { Name = "Rate", Position = UDim2.fromScale(0.3, 0.64), Size = UDim2.fromScale(0.6, 0.34), TextXAlignment = Enum.TextXAlignment.Left })
	box.Parent = g
	coinBox = box
	local b = UIKit.button(g, Strings.Hints.hatch, UIKit.GREEN, function(btn)
		local a = action
		if not a then
			return
		end
		local reply
		local t0 = os.clock()
		local modal = if uistack and uistack.top then uistack.top() else nil
		if a.kind == "hatch" then
			reply = Net.call("HatchReady", a.slot or 1)
		elseif a.kind == "feed" then
			reply = Net.call("Feed", "all")
		else
			reply = Net.call("Mount", a.uid or "")
		end
		noteAction(a.kind, reply, t0, modal)
		if not reply.ok then
			UIKit.shake(btn)
		end
		task.delay(0.3, updateAction)
	end)
	b.Name = "Action"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.fromScale(0.5, 0.965)
	b.Size = UDim2.fromScale(0.22, 0.095) -- more compact, does not reach the jump button on the right; slightly larger under Ride / Fly
	b.Visible = false
	actionBtn = b
	-- the second Feed all button left of the main one when both the companion (Ride/Fly) and hungry dragons are nearby
	local b2 = UIKit.button(g, Strings.Hints.feedAll, UIKit.GREEN, function(btn)
		local t0 = os.clock()
		local modal = if uistack and uistack.top then uistack.top() else nil
		local reply = Net.call("Feed", "all")
		noteAction("feedall", reply, t0, modal)
		if not reply.ok then
			UIKit.shake(btn)
		end
		task.delay(0.3, updateAction)
	end)
	b2.Name = "Action2"
	b2.AnchorPoint = Vector2.new(0.5, 1)
	b2.Position = UDim2.fromScale(0.38, 0.965)
	b2.Size = UDim2.fromScale(0.2, 0.085)
	b2.Visible = false
	feedBtn = b2
end

local function refreshBoost()
	local left = boostLeft - (os.clock() - boostAt)
	local suffix = if left > 0 then "   " .. fmt(Strings.HUD.boost, { time = Format.clock(left) }) else ""
	if suffix ~= boostSuffix then
		boostSuffix = suffix
		refresh()
	elseif suffix ~= "" and rateLabel then
		rateLabel.Text = "+" .. fmt(Strings.HUD.perSecond, { n = Format.number(rate()) }) .. suffix
	end
end

function HUD.start()
	task.spawn(function() -- a start in waves - a check every 0.5 s (cheap: the Store table)
		while true do
			local ok, err = pcall(function()
				local want = isNewbie()
				if want or newbieOn then
					setNewbie(want)
				end
			end)
			if not ok then
				warn("[HUD] newbie: " .. tostring(err))
			end
			task.wait(0.5)
		end
	end)
	refresh()
	for _, k in { "coins", "dragons", "nestOrder", "ascension", "owned", "boost" } do -- 2.2: passes and the boost change the income
		Store.on(k, function()
			refresh()
			updateAction()
		end)
	end
	local function syncBoost()
		local bst = Store.get("boost")
		boostLeft = if typeof(bst) == "table" then (tonumber(bst.secondsLeft) or 0) else 0
		boostAt = os.clock()
		refreshBoost()
	end
	syncBoost()
	Store.on("boost", syncBoost)
	task.spawn(function()
		while true do
			task.wait(1)
			refreshBoost()
		end
	end)
	for _, tag in { "ReadyToHatch", "CanFeed" } do
		CollectionService:GetInstanceAddedSignal(tag):Connect(updateAction)
		CollectionService:GetInstanceRemovedSignal(tag):Connect(updateAction)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			updateAction()
		end
	end)
end

return HUD
