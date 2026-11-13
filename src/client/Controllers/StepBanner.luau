--!strict
-- The current step banner (P10, 02 addendum 1.3; craft/04 §7.1: in DA the player never searches for what to do): at the top center under
-- the coin counter - the category in color (HATCH / COINS / EGG / FEED), one task line, progress 0/1. The target is given by Hints (the same
-- logic Core/Hints), the banner stays while the target exists. On a step change - "Done!" in green for 1 s with a sound, then the next step.
-- Before the Keeper's quests (06 §1) the steps are computed from the state; with quests the line is taken from them.
-- P34 (Ride A Pet "Go To Gear Shop 62m Away"): on the right - the distance to the step target "{n} m" in gold (the target is given by
-- Hints.goalPart), every Config.UI.stepBanner.distEvery s; no target (or mounted and the target is the dragon itself) - progress 0/1 in that spot.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local StepBanner = {}

local C = Config.UI.stepBanner
local CATEGORY = { companion = "companion", table = "hatch", incubator = "hatch", hatch = "hatch", pile = "coins", glide = "glide", egg = "egg", feed = "feed", ride = "ride", fly = "fly", ring = "fly", gloom = "fight", guardian = "fight", sky = "fight", skyUp = "fly", glowEgg = "glow", glowHome = "glow", raid = "raid", raidFirst = "raid", raidWait = "raid", raidHome = "raid", raidDragon = "raid", raidRide = "raid", warm = "glow", stall = "feed" } -- raid -- the glowing egg; 1.9: RIDE / FLY (DA RIDING / FLYING)
local LINE = { companion = "companionHint", table = "goTable", incubator = "toIncubator", hatch = "tapHatch", pile = "collectPile", glide = "glideHint", egg = "findEgg", feed = "feedHint", ride = "rideHint", fly = "takeOffHint", ring = "windRings", gloom = "gloomHint", guardian = "guardianHint", sky = "gloomHint", skyUp = "skyHint", glowEgg = "glowEggHint", glowHome = "glowHomeHint", raid = "raidHint", raidFirst = "raidFirstHint", raidWait = "raidWaitHint", raidHome = "raidHomeHint", raidDragon = "raidDragonHint", raidRide = "raidRideHint" }
local COLOR = { companion = Color3.fromRGB(226, 150, 60), hatch = Color3.fromRGB(255, 150, 60), coins = UIKit.GOLD, glide = Color3.fromRGB(140, 205, 255), egg = UIKit.GREEN, feed = Color3.fromRGB(240, 110, 90), ride = Color3.fromRGB(226, 150, 60), fly = Color3.fromRGB(110, 190, 240), fight = Color3.fromRGB(176, 104, 236), glow = Color3.fromRGB(255, 170, 70), raid = Color3.fromRGB(255, 120, 72) }

local frame: Frame? = nil
local catLabel: TextLabel? = nil
local lineLabel: TextLabel? = nil
local progLabel: TextLabel? = nil
local currentKind: string? = nil
local doneUntil = 0
local hints: any = nil
local me = Players.LocalPlayer

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function render(kind: string?)
	local f, cl, ll, pl = frame, catLabel, lineLabel, progLabel
	if not f or not cl or not ll or not pl then
		return
	end
	if not kind then
		f.Visible = false
		return
	end
	local cat = CATEGORY[kind] or "hatch"
	cl.Text = (Strings.Steps :: any)[cat] or ""
	cl.TextColor3 = COLOR[cat] or Color3.new(1, 1, 1)
	ll.Text = (Strings.Hints :: any)[LINE[kind]] or ""
	if kind == "raidWait" then -- before the first timer tick the line showed a raw "Next egg in {t}"
		ll.Text = fmt(Strings.Hints.raidWaitHint, { t = "0:20" })
	end
	ll.TextColor3 = Color3.new(1, 1, 1)
	pl.Text = "" -- a single-action step has no count
	pl.TextColor3 = Color3.fromRGB(220, 220, 230)
	local fill = f:FindFirstChild("Bar") and (f:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill")
	if fill and fill:IsA("Frame") then
		fill.Size = UDim2.fromScale(0, 1)
	end
	if not f.Visible then
		f.Visible = true
		local sc = f:FindFirstChildOfClass("UIScale") :: UIScale
		sc.Scale = 0.7
		TweenService:Create(sc, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

-- the step is credited: Done! for a second (not for walking away from the egg on the island - there the target simply leaves the radius)
local function completed(prev: string, nextKind: string?): boolean
	if prev == "egg" then
		return nextKind == "incubator"
	end
	return nextKind ~= prev
end

-- which step the banner leads now (nil - no step); the combat "what next" line does not argue with it
function StepBanner.kind(): string?
	return currentKind
end

function StepBanner.setGoal(goal: { kind: string }?)
	local kind = goal and goal.kind or nil
	if kind == currentKind then
		return
	end
	local prev = currentKind
	currentKind = kind
	if prev and completed(prev, kind) and os.clock() >= doneUntil then
		local f, cl, ll, pl = frame, catLabel, lineLabel, progLabel
		if f and cl and ll and pl then
			f.Visible = true
			cl.Text = (Strings.Steps :: any)[CATEGORY[prev] or "hatch"] or ""
			ll.Text = Strings.Steps.done
			ll.TextColor3 = UIKit.GREEN
			pl.Text = "" -- "1/1" is not shown either, "Done!" is visible anyway
			pl.TextColor3 = UIKit.GREEN
			local fill = f:FindFirstChild("Bar") and (f:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill")
			if fill and fill:IsA("Frame") then
				TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.fromScale(1, 1) }):Play()
			end
			Sounds.play("quest_done")
			doneUntil = os.clock() + C.doneSeconds
			task.delay(C.doneSeconds, function()
				render(currentKind)
			end)
			return
		end
	end
	render(kind)
end

function StepBanner.current(): string
	local f, ll, pl = frame, lineLabel, progLabel
	return if f and f.Visible and ll and pl then tostring(currentKind) .. ":" .. ll.Text .. " [" .. pl.Text .. "]" else "hidden"
end

-- the banner right under the coin pill at its real size (on the phone the pill is taller than the 0.09 fraction - otherwise an overlap)
local function placeUnderCoins()
	local f = frame
	local pg = me:FindFirstChild("PlayerGui")
	local hud = pg and pg:FindFirstChild("HUD")
	local coins = hud and hud:FindFirstChild("Coins")
	local g = f and f:FindFirstAncestorOfClass("ScreenGui")
	if not f or not coins or not coins:IsA("GuiObject") or not g then
		return
	end
	local bottom = coins.AbsolutePosition.Y + coins.AbsoluteSize.Y + 4 - g.AbsolutePosition.Y
	local want = math.max(bottom, g.AbsoluteSize.Y * C.y)
	f.Position = UDim2.new(0.5, 0, 0, math.floor(want))
end

-- P34: the distance to the step target in place of the progress
local function updateDistance()
	local f, pl = frame, progLabel
	if not f or not pl or not f.Visible or os.clock() < doneUntil then
		return
	end
	local part = hints and hints.goalPart()
	local ch = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local dist = if part and root and root:IsA("BasePart") then (part.Position - root.Position).Magnitude else nil
	-- "Tap Hatch!" only at the incubator; from afar - "go to your nest"
	local ll = lineLabel
	if currentKind == "hatch" and ll and dist then
		ll.Text = if dist > Config.Loop.hatchDistance then Strings.Hints.hatchGo else Strings.Hints.tapHatch
	end
	-- the nests of the open ring are empty - a timer until the next egg (the nest's ReadyAt attribute, server time)
	if currentKind == "raidWait" and ll and part then
		local m = part.Parent
		local ra = m and tonumber(m:GetAttribute("ReadyAt"))
		local left = math.max(0, (ra or 0) - workspace:GetServerTimeNow())
		ll.Text = fmt(Strings.Hints.raidWaitHint, { t = string.format("%d:%02d", math.floor(left / 60), math.floor(left % 60)) })
	end
	-- for a player with a dragon - how many eggs are left today
	if currentKind == "raid" and ll then
		local dl = tonumber(me:GetAttribute("RaidLeft"))
		if dl and dl > 0 then
			ll.Text = fmt(Strings.Hints.raidDayHint, { n = dl })
		end
	end
	if dist and dist >= (C.distMin or 8) then -- closer than 8 m the player is there - no distance written
		pl.Text = fmt(Strings.Steps.distance, { n = math.floor(dist + 0.5) })
		pl.TextColor3 = UIKit.GOLD
	else
		pl.Text = "" -- a single-action step has no count
		pl.TextColor3 = Color3.fromRGB(220, 220, 230)
	end
end

function StepBanner.init(_snapshot: any, loaded: any)
	hints = loaded.Hints
	local g = UIKit.screen("StepBanner", 2)
	local f = UIKit.pill(g, { Name = "Step", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, C.y), Size = UDim2.fromScale(C.width, C.height), Visible = false }) -- one style with the coin pill
	Instance.new("UIScale").Parent = f
	catLabel = UIKit.text(f, "", UIKit.GOLD, { Name = "Category", Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.2, 0.6), TextXAlignment = Enum.TextXAlignment.Left })
	-- P34: the line 0.24-0.82, on the right a cell 0.83-0.98 for "0/1" or "123 m"
	lineLabel = UIKit.text(f, "", Color3.new(1, 1, 1), { Name = "Line", Position = UDim2.fromScale(0.24, 0.1), Size = UDim2.fromScale(0.58, 0.6), TextXAlignment = Enum.TextXAlignment.Left })
	progLabel = UIKit.text(f, "", Color3.fromRGB(220, 220, 230), { Name = "Progress", Position = UDim2.fromScale(0.83, 0.14), Size = UDim2.fromScale(0.15, 0.52) })
	-- a progress bar under the line; on "Done!" it fills green
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	bar.BackgroundTransparency = 1 -- the track is invisible, only the growth is visible
	bar.Position = UDim2.fromScale(0.24, 0.74)
	bar.Size = UDim2.fromScale(0.58, 0.14)
	UIKit.corner(bar, 0.5)
	bar.Parent = f
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = UIKit.GREEN
	fill.Size = UDim2.fromScale(0, 1)
	UIKit.corner(fill, 0.5)
	fill.Parent = bar
	UIKit.plain(f) -- the step - text with an outline, no pill (the progress bar stays)
	frame = f
end

function StepBanner.start()
	-- the server announcement and the Done! banner printed over the step banner - while a banner is up, the step screen is off
	-- (the screen itself is not touched: it is switched by the HUD, the menu and the hatch scene)
	local hiddenByBanner = false
	RunService.Heartbeat:Connect(function()
		local f = frame
		if not f then
			return
		end
		if os.clock() < UIKit.bannerUntil then
			if f.Visible then
				f.Visible = false
				hiddenByBanner = true
			end
		elseif hiddenByBanner then
			hiddenByBanner = false
			f.Visible = currentKind ~= nil
		end
	end)
	while true do
		task.wait(C.distEvery or 0.3)
		pcall(updateDistance)
		pcall(placeUnderCoins)
	end
end

return StepBanner
