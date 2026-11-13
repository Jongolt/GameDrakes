--!strict
-- Day phase announcement (P16/P32; craft/04 §7.11 HTTYD: on change - a plaque on a cloud at the top center with a sun or a moon
-- and the word Night for a couple of seconds). The source is the Phase attribute on ReplicatedStorage/DayCycle (set by the server). Not shown
-- on join (the player sees the sky), only on change. The cloud is made of rounded frames, the glyph ☀ / ☾ as text.
-- P35 (Ride A Pet "☀ in 1m 15s" by the jump, the storm higher): world timers above the jump button - the icon of what comes next
-- (☀ day / 🌙 night) and the time until the light part of the day (dawn+day) turns dark (dusk+night) and back; from the server's
-- PhaseEndsAt by its clock (GetServerTimeNow). The spot is chosen without overlapping the flight buttons, the jump, the Keeper and the action buttons
-- (layoutTimers). The spot for the storm timer (2.7) - a second pill left of the first, hidden.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))

local DayPhase = {}

local C = Config.UI.phaseBanner
-- "☾" did not render in the font, "☀" was tiny, the cloud dark -> the moon as the emoji 🌙 (renders, sampler), the sun larger
-- the cloud light gray-blue as in HTTYD
local GLYPH = { dawn = "☀", day = "☀", dusk = "🌙", night = "🌙" }
local EMOJI = { dusk = true, night = true }
local TINT = { dawn = Color3.fromRGB(255, 190, 120), day = Color3.fromRGB(255, 214, 92), dusk = Color3.fromRGB(240, 150, 110), night = Color3.fromRGB(190, 210, 255) }
-- the cloud as one silhouette - puffs and body
-- in a CanvasGroup (shared transparency, no seams between the circles), a light rim - a second slightly larger silhouette; color by phase
local LIGHT = { dawn = true, day = true }
local CLOUD_DAY, CLOUD_NIGHT = Color3.fromRGB(236, 242, 252), Color3.fromRGB(46, 60, 108)
local RIM_DAY, RIM_NIGHT = Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 176, 235)
local INK_DAY, INK_NIGHT = Color3.fromRGB(44, 52, 78), Color3.fromRGB(246, 240, 222)

local gui: ScreenGui? = nil
local seq = 0

-- ---------------------------------------------------------------------------------------------- P35 world timers
local WT = Config.UI.worldTimers
local MOB = Config.UI.mobile
local GROUP = { dawn = "light", day = "light", dusk = "dark", night = "dark" }
local me = Players.LocalPlayer
local timers: ScreenGui? = nil
local box: Frame? = nil
local list: UIListLayout? = nil
local dayPill: Frame? = nil
local dayText: TextLabel? = nil
local sunGlyph: TextLabel? = nil
local moonGlyph: TextLabel? = nil
local stormPill: Frame? = nil -- 2.7 Weather: "Storm in 3:40", hidden for now

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

-- the flight button size and the jump button - as in Fly (layoutButtons)
local function buttonSize(): number
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(800, 600)
	return if math.min(v.X, v.Y) < MOB.threshold then MOB.small else MOB.large
end

local function jumpButton(): GuiObject?
	local pg = me:FindFirstChild("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local fr = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = fr and fr:FindFirstChild("JumpButton")
	return if jb and jb:IsA("GuiObject") and jb.Visible then jb else nil
end

local function timerPill(parent: Instance, name: string, order: number): (Frame, TextLabel)
	local p = UIKit.pill(parent, { Name = name, LayoutOrder = order })
	local t = UIKit.text(p, "", UIKit.CREAM, { Name = "Time", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.36, 0.5), Size = UDim2.fromScale(0.6, 0.64), TextXAlignment = Enum.TextXAlignment.Left })
	return p, t
end

local function buildTimers()
	local g = UIKit.screen("WorldTimers", 2)
	timers = g
	local f = Instance.new("Frame")
	f.Name = "Box"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(1, 1)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.VerticalAlignment = Enum.VerticalAlignment.Bottom
	l.Padding = UDim.new(0, WT.gap)
	l.Parent = f
	list = l
	f.Parent = g
	box = f
	-- right to left: the day closer to the buttons, the storm to the left
	local sp, st = timerPill(f, "Storm", 1)
	sp.Visible = false
	UIKit.iconText(sp, "⛈️", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.06, 0.5), Size = UDim2.fromScale(0.26, 0.8) })
	st.Text = ""
	stormPill = sp
	local dp, dt = timerPill(f, "Day", 2)
	dayPill = dp
	dayText = dt
	local sun = UIKit.text(dp, GLYPH.day, TINT.day, { Name = "Sun", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.06, 0.5), Size = UDim2.fromScale(0.26, 0.9) })
	local ss = sun:FindFirstChildOfClass("UIStroke")
	if ss then
		ss.Thickness = 2
	end
	sunGlyph = sun
	moonGlyph = UIKit.iconText(dp, GLYPH.night, { Name = "Moon", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.07, 0.5), Size = UDim2.fromScale(0.24, 0.72), Visible = false })
end

-- the spot is chosen from variants, the first without overlaps.
-- Occupied spots - the Fly flight buttons in BOTH states (with the jump button and without it: mounted, Roblox hides it and Fly places the buttons from
-- ViewportSize), the jump button itself, the Keeper plaque (Quests.Panel), the action button strip at the bottom center (Hatch/Ride/Feed All).
-- Variants: (1) left of the Down spot in the Up/Down row (Ride A Pet: the sun left of the jump), (2) above the flight block, (3) under Dismount.
-- Coordinates - inside the own ScreenGui (UIKit.screen has the same insets as Movement).
type Rect = { number }

local function overlaps(a: Rect, b: Rect): boolean
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

local function rectOf(o: GuiObject, origin: Vector2): Rect
	local p = o.AbsolutePosition - origin
	return { p.X, p.Y, p.X + o.AbsoluteSize.X, p.Y + o.AbsoluteSize.Y }
end

-- the Fly button spots (as in Fly.layoutButtons): with the jump button and without it; plus the jump button itself
local function flightRects(g: ScreenGui, s: number): ({ Rect }, Rect, Rect)
	local gap = MOB.gap
	local h = s * 0.62
	local out: { Rect } = {}
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else g.AbsoluteSize
	-- without the jump (mounted): Dismount, Up above it, Down left of Up
	local offY = v.Y - 110 - h
	local upY = v.Y - 110 - 2 * h - gap
	local fUp = { v.X - 16 - s, upY, v.X - 16, upY + h }
	local fDown = { v.X - 16 - 2 * s - gap, upY, v.X - 16 - s - gap, upY + h }
	table.insert(out, fUp)
	table.insert(out, fDown)
	table.insert(out, { v.X - 16 - s, offY, v.X - 16, offY + h })
	local down = fDown
	local jb = jumpButton()
	if jb then
		local x, y = jb.AbsolutePosition.X, jb.AbsolutePosition.Y
		local w, jh = jb.AbsoluteSize.X, jb.AbsoluteSize.Y
		local tUp = { x + (w - s) / 2, y - gap - h, x + (w - s) / 2 + s, y - gap }
		local tDown = { x - gap - s, y - gap - h, x - gap, y - gap }
		table.insert(out, tUp)
		table.insert(out, tDown)
		table.insert(out, { x - gap - s, y + (jh - h) / 2, x - gap, y + (jh + h) / 2 })
		table.insert(out, rectOf(jb, g.AbsolutePosition))
		down = if tDown[1] < fDown[1] then tDown else fDown
	end
	return out, down, fUp
end

local function layoutTimers()
	local g, f, l = timers, box, list
	if not g or not f or not l then
		return
	end
	local s = buttonSize()
	local w, h = math.floor(WT.width * s + 0.5), math.floor(WT.height * s + 0.5)
	local origin = g.AbsolutePosition
	local size = g.AbsoluteSize
	local cluster, down, _ = flightRects(g, s)
	local avoid: { Rect } = table.clone(cluster)
	local pg = me:FindFirstChild("PlayerGui")
	local q = pg and pg:FindFirstChild("Quests")
	local panel = q and q:FindFirstChild("Panel")
	if panel and panel:IsA("GuiObject") and panel.Visible then
		table.insert(avoid, rectOf(panel, origin))
	end
	-- the action buttons at the bottom center (one at 0.5 or two: 0.38 and 0.6; height at least 44)
	local actH = math.max(44, size.Y * 0.095)
	table.insert(avoid, { size.X * 0.27, size.Y * 0.965 - actH - 4, size.X * 0.73, size.Y })
	local top, right = math.huge, -math.huge
	for _, r in cluster do
		top = math.min(top, r[2])
		right = math.max(right, r[3])
	end
	local bottomOfCluster = -math.huge
	for _, r in cluster do
		bottomOfCluster = math.max(bottomOfCluster, r[4])
	end
	local cands: { Rect } = {
		{ down[1] - WT.gap - w, (down[2] + down[4]) / 2 - h / 2, down[1] - WT.gap, (down[2] + down[4]) / 2 + h / 2 }, -- (1) left of Down
		{ right - w, top - WT.gap - h, right, top - WT.gap }, -- (2) above the block
		{ right - w, bottomOfCluster + WT.gap, right, bottomOfCluster + WT.gap + h }, -- (3) under the block
	}
	local pick = cands[1]
	for _, c in cands do
		local ok = c[1] >= 0 and c[2] >= 0 and c[3] <= size.X and c[4] <= size.Y
		for _, a in avoid do
			if ok and overlaps(c, a) then
				ok = false
			end
		end
		if ok then
			pick = c
			break
		end
	end
	-- the second pill (storm, 2.7) - left of the first in the same row
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	f.Position = UDim2.fromOffset(pick[3], pick[4])
	f.Size = UDim2.fromOffset(2 * w + WT.gap, h)
	for _, p in { dayPill, stormPill } do
		if p then
			p.Size = UDim2.fromOffset(w, h)
		end
	end
end

-- seconds until the light part of the day turns dark and vice versa; what comes next ("light" | "dark")
local function untilFlip(folder: Instance): (number?, string?)
	local phase = folder:GetAttribute("Phase")
	local ends = folder:GetAttribute("PhaseEndsAt")
	if typeof(phase) ~= "string" or typeof(ends) ~= "number" or not GROUP[phase] then
		return nil, nil
	end
	local phases = Config.World.dayCycle.phases
	local idx = 0
	for i, ph in phases do
		if ph.id == phase then
			idx = i
		end
	end
	if idx == 0 then
		return nil, nil
	end
	local left = ends - workspace:GetServerTimeNow()
	local g = GROUP[phase]
	local j = idx % #phases + 1
	for _ = 1, #phases - 1 do
		if GROUP[phases[j].id] ~= g then
			break
		end
		left += phases[j].seconds
		j = j % #phases + 1
	end
	return math.max(0, left), if g == "light" then "dark" else "light"
end

local function refreshTimers(folder: Instance)
	local p, t = dayPill, dayText
	if not p or not t then
		return
	end
	local left, coming = untilFlip(folder)
	p.Visible = left ~= nil and Config.World.dayCycle.enabled ~= false and WT.dayNight == true -- off until the mechanic exists (spec 02 add. 2.11)
	if not left then
		return
	end
	local secs = math.floor(left + 0.5)
	local span = if secs >= 60 then fmt(Strings.World.timerMinSec, { m = secs // 60, s = secs % 60 }) else fmt(Strings.World.timerSec, { s = secs })
	t.Text = fmt(Strings.World.timerIn, { t = span })
	if sunGlyph and moonGlyph then
		sunGlyph.Visible = coming == "light"
		moonGlyph.Visible = coming == "dark"
	end
end

-- for Studio probes: what the timer shows and where it is
function DayPhase.timerState(): string
	local p, t = dayPill, dayText
	if not p or not t then
		return "no timer"
	end
	return string.format("%s visible=%s at=%d,%d size=%d,%d sun=%s", t.Text, tostring(p.Visible), p.AbsolutePosition.X, p.AbsolutePosition.Y, p.AbsoluteSize.X, p.AbsoluteSize.Y, tostring(sunGlyph and sunGlyph.Visible))
end

-- the cloud silhouette in px (width C.width, height C.height): a pill body at the bottom and three puffs on top; inset - how many px smaller on all sides
local function silhouette(parent: Instance, color: Color3, inset: number)
	local W, H = C.width, C.height
	local function blob(x: number, y: number, w: number, h: number)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = color
		f.Position = UDim2.fromOffset(x + inset, y + inset)
		f.Size = UDim2.fromOffset(w - inset * 2, h - inset * 2)
		UIKit.corner(f, 1)
		f.Parent = parent
	end
	blob(0, H * 0.36, W, H * 0.64) -- body
	blob(W * 0.13, H * 0.16, H * 0.62, H * 0.62) -- puffs
	blob(W * 0.34, 0, H * 0.8, H * 0.8)
	blob(W * 0.6, H * 0.12, H * 0.66, H * 0.66)
end

local function cloud(parent: Instance, id: string): (Frame, { CanvasGroup }, { TextLabel })
	local W, H = C.width, C.height
	local root = Instance.new("Frame")
	root.Name = "Cloud"
	root.BackgroundTransparency = 1
	root.AnchorPoint = Vector2.new(0.5, 0)
	root.Position = UDim2.new(0.5, 0, 0, C.top)
	root.Size = UDim2.fromOffset(W, H)
	local light = LIGHT[id] == true
	local groups: { CanvasGroup } = {}
	for _, layer in { { name = "Rim", color = if light then RIM_DAY else RIM_NIGHT, inset = 0 }, { name = "Body", color = if light then CLOUD_DAY else CLOUD_NIGHT, inset = C.rim } } do
		local cg = Instance.new("CanvasGroup")
		cg.Name = layer.name
		cg.BackgroundTransparency = 1
		cg.Size = UDim2.fromScale(1, 1)
		cg.GroupTransparency = 1
		silhouette(cg, layer.color, layer.inset)
		cg.Parent = root
		table.insert(groups, cg)
	end
	-- the icon and the word over the cloud, opaque (readable on any sky)
	local ink = if light then INK_DAY else INK_NIGHT
	local texts: { TextLabel } = {}
	local glyphProps = { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, H * 0.62, 0.6, 0), Size = UDim2.fromOffset(H * 0.62, H * 0.62), ZIndex = 3, TextTransparency = 1 }
	local glyph = if EMOJI[id] then UIKit.iconText(root, GLYPH[id], glyphProps) else UIKit.text(root, GLYPH[id] or "☀", TINT[id] or UIKit.GOLD, glyphProps)
	table.insert(texts, glyph)
	local word = UIKit.text(root, (Strings.World.phase :: any)[id] or id, ink, { Name = "Word", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, H * 1.05, 0.62, 0), Size = UDim2.new(1, -H * 1.25, 0, H * 0.5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3, TextTransparency = 1 })
	local st = word:FindFirstChildOfClass("UIStroke")
	if st then
		st.Color = if light then Color3.new(1, 1, 1) else UIKit.STROKE
		st.Thickness = 1.5
		st.Transparency = 1
	end
	table.insert(texts, word)
	root.Parent = parent
	return root, groups, texts
end

-- hold - seconds on screen (default C.seconds; ClientDebug "phase night 20" holds longer for frames)
function DayPhase.show(id: string, hold: number?)
	local g = gui
	if not g then
		return
	end
	seq += 1
	local my = seq
	for _, c in g:GetChildren() do
		c:Destroy()
	end
	local root, groups, texts = cloud(g, id)
	local inInfo = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	root.Position = UDim2.new(0.5, 0, 0, C.top - C.slide)
	TweenService:Create(root, inInfo, { Position = UDim2.new(0.5, 0, 0, C.top) }):Play()
	TweenService:Create(groups[1], inInfo, { GroupTransparency = C.rimTransparency }):Play()
	TweenService:Create(groups[2], inInfo, { GroupTransparency = C.transparency }):Play()
	for _, t in texts do
		TweenService:Create(t, inInfo, { TextTransparency = 0 }):Play()
		local st = t:FindFirstChildOfClass("UIStroke")
		if st then
			TweenService:Create(st, inInfo, { Transparency = 0.2 }):Play()
		end
	end
	task.delay(hold or C.seconds, function()
		if my ~= seq or not root.Parent then
			return
		end
		local outInfo = TweenInfo.new(0.4)
		TweenService:Create(root, outInfo, { Position = UDim2.new(0.5, 0, 0, C.top - C.slide * 0.5) }):Play()
		for _, cg in groups do
			TweenService:Create(cg, outInfo, { GroupTransparency = 1 }):Play()
		end
		for _, t in texts do
			TweenService:Create(t, outInfo, { TextTransparency = 1 }):Play()
			local st = t:FindFirstChildOfClass("UIStroke")
			if st then
				TweenService:Create(st, outInfo, { Transparency = 1 }):Play()
			end
		end
		task.delay(0.45, function()
			if my == seq then
				root:Destroy()
			end
		end)
	end)
end

function DayPhase.init(_snapshot: any, _loaded: any)
	gui = UIKit.screen("DayPhase", 4)
	-- the plaque in the Roblox button row at the top center - coordinates from the very top of the screen
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.IgnoreGuiInset = true
	buildTimers()
end

function DayPhase.start()
	local f = ReplicatedStorage:WaitForChild("DayCycle", 30)
	if not f then
		if dayPill then
			dayPill.Visible = false
		end
		return
	end
	task.spawn(function()
		while true do
			local ok, err = pcall(function()
				layoutTimers()
				refreshTimers(f)
			end)
			if not ok then
				warn("[DayPhase] timers: " .. tostring(err))
				task.wait(5)
			end
			task.wait(WT.tick)
		end
	end)
	local last = f:GetAttribute("Phase")
	f:GetAttributeChangedSignal("Phase"):Connect(function()
		local id = f:GetAttribute("Phase")
		if typeof(id) == "string" and id ~= last then
			last = id
			-- the phase starts before the light catches up; the banner - at a fraction
			-- C.at of the phase length (dusk 60 s -> after 27 s, when the sun is already low)
			-- the phase length from the shared Config (the server writes the PhaseSeconds attribute after Phase - at the signal moment it is still from the previous phase)
			local seconds = 0
			for _, ph in Config.World.dayCycle.phases do
				if ph.id == id then
					seconds = ph.seconds
				end
			end
			local wait = seconds * (C.at or 0)
			task.delay(wait, function()
				if f:GetAttribute("Phase") == id then
					DayPhase.show(id)
				end
			end)
		end
	end)
end

return DayPhase
