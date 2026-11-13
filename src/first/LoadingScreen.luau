--!strict
-- The loading screen on join: a gradient sky, twinkling stars, drifting clouds, a text logo with a bounce, the "Your nest: ..." line from
-- the data snapshot, the step line. The logo in three colors ("Find, Feed & Fly" + "DRAGONS" as the second line), a loading bar with a hatchling dragon
-- that runs along the bar to the egg at the end, tips in a cycle (Strings.Loading.tips), "Tap to skip" after skipAfter (1.5 s) when
-- the world is already loaded (allowSkip); a tap/click anywhere hides the screen. Without a tap the screen leaves by itself when everything is ready and hold
-- seconds have passed (no longer than 3 s). Built in code, no images (Open Cloud images do not always reach phones).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LoadingScreen = {}
LoadingScreen.__index = LoadingScreen

export type LoadingScreen = typeof(setmetatable({} :: {
	gui: ScreenGui,
	back: Frame,
	logo: TextLabel,
	step: TextLabel,
	summary: TextLabel,
	tip: TextLabel,
	skip: TextLabel,
	catcher: TextButton,
	fill: Frame,
	runner: Frame,
	egg: Frame,
	clouds: { Frame },
	shownAt: number,
	conn: RBXScriptConnection?,
	minShow: number,
	hold: number,
	skipAfter: number,
	fade: number,
	target: number,
	shown: number,
	creep: number,
	tips: { string },
	tipSeconds: number,
	tipIndex: number,
	tipAt: number,
	skippable: boolean,
	hidden: boolean,
	view: { model: Model, base: CFrame, h: number }?, -- the 3D hatchling (useModel)
}, LoadingScreen))

local rng = Random.new()

-- the colors of the logo words in order (Find - the meadow, Feed - berries and fire, Fly - the sky); the dashes - cream
local WORD_COLORS = { "#86E06A", "#FFB547", "#7CCBFF" }
local DASH_COLOR = "#F4E6C8"
local LAST_COLOR = "#FFD45E" -- the fourth word ("Dragons") as the second line in gold
local DARK = Color3.fromRGB(32, 26, 24)

local function font(): Enum.Font
	local ok, name = pcall(function()
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		local cfg = Shared and Shared:FindFirstChild("Config")
		return cfg and (require(cfg :: ModuleScript) :: any).UI.font
	end)
	if ok and typeof(name) == "string" then
		local ok2, f = pcall(function()
			return (Enum.Font :: any)[name]
		end)
		if ok2 and typeof(f) == "EnumItem" then
			return f :: Enum.Font
		end
	end
	return Enum.Font.FredokaOne
end

local function stroke(obj: GuiObject, thickness: number, color: Color3?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color or DARK
	s.Thickness = thickness
	s.Parent = obj
	return s
end

local function round(obj: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(r, 0)
	c.Parent = obj
end

local function label(parent: Instance, text: string, fnt: Enum.Font, color: Color3, pos: UDim2, size: UDim2): TextLabel
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Position = pos
	t.Size = size
	t.BackgroundTransparency = 1
	t.Font = fnt
	t.TextScaled = true
	t.TextColor3 = color
	t.Text = text
	t.Parent = parent
	return t
end

-- a picture element: a frame in fractions of the parent, rounding r, an outline
local function blob(parent: Instance, name: string, color: Color3, x: number, y: number, w: number, h: number, r: number, z: number, edge: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.ZIndex = z
	round(f, r)
	if edge and edge > 0 then
		local s = stroke(f, edge)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	end
	f.Parent = parent
	return f
end

local function gloss(obj: GuiObject, k: number)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.new(1 - k, 1 - k, 1 - k)) })
	g.Parent = obj
end

-- the logo: words separated by " - " in their own colors (RichText), a shared vertical gradient gives volume to each color
-- "Find, Feed & Fly Dragons" - three words in their own colors, the separators (", ", " & ", " - ") cream, the words after the third -
-- the second line in gold; (the text, whether there is a second line)
local function logoText(title: string): (string, boolean)
	local out = {}
	local i = 0
	local second = false
	for word, sep in string.gmatch(title, "([%w']+)([^%w']*)") do
		i += 1
		if i <= #WORD_COLORS then
			table.insert(out, string.format('<font color="%s">%s</font>', WORD_COLORS[i], word))
			if i < #WORD_COLORS and sep ~= "" then
				table.insert(out, string.format('<font color="%s">%s</font>', DASH_COLOR, (string.gsub(sep, "&", "&amp;"))))
			end
		else
			table.insert(out, (if second then " " else "\n") .. string.format('<font color="%s">%s</font>', LAST_COLOR, string.upper(word)))
			second = true
		end
	end
	return if i < 2 then title else table.concat(out), second
end

-- the egg at the end of the bar: a cream "stadium" with spots and a glint
local function buildEgg(parent: Instance): Frame
	local egg = blob(parent, "Egg", Color3.fromRGB(250, 242, 222), 1, 0.5, 1.7, 2.2, 0.5, 3, 2)
	egg.AnchorPoint = Vector2.new(0.35, 0.82)
	egg.SizeConstraint = Enum.SizeConstraint.RelativeYY
	gloss(egg, 0.22)
	blob(egg, "Spot1", Color3.fromRGB(240, 150, 70), 0.18, 0.3, 0.26, 0.2, 0.5, 4, 0)
	blob(egg, "Spot2", Color3.fromRGB(240, 150, 70), 0.58, 0.52, 0.22, 0.17, 0.5, 4, 0)
	blob(egg, "Spot3", Color3.fromRGB(240, 150, 70), 0.3, 0.7, 0.16, 0.12, 0.5, 4, 0)
	blob(egg, "Shine", Color3.new(1, 1, 1), 0.2, 0.12, 0.18, 0.12, 0.5, 5, 0).BackgroundTransparency = 0.3
	return egg
end

function LoadingScreen.new(title: string, subtitle: string?): LoadingScreen
	local fnt = font()
	local gui = Instance.new("ScreenGui")
	gui.Name = "LoadingScreen"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- the sky: night at the top, a warm dawn at the horizon
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(1, 1, 1)
	back.BorderSizePixel = 0
	back.ClipsDescendants = true
	local sky = Instance.new("UIGradient")
	sky.Rotation = 90
	sky.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(18, 24, 56)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(58, 52, 96)),
		ColorSequenceKeypoint.new(0.85, Color3.fromRGB(190, 118, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(240, 176, 110)),
	})
	sky.Parent = back
	back.Parent = gui

	-- the stars: twinkle
	for _ = 1, 36 do
		local st = Instance.new("Frame")
		st.BackgroundColor3 = Color3.fromRGB(255, 250, 230)
		st.BorderSizePixel = 0
		local sz = rng:NextInteger(2, 4)
		st.Size = UDim2.fromOffset(sz, sz)
		st.Position = UDim2.fromScale(rng:NextNumber(0.02, 0.98), rng:NextNumber(0.03, 0.55))
		st.BackgroundTransparency = rng:NextNumber(0.1, 0.7)
		round(st, 1)
		st.Parent = back
		task.delay(rng:NextNumber(0, 2), function()
			while st.Parent do
				local tw = TweenService:Create(st, TweenInfo.new(rng:NextNumber(0.6, 1.6), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { BackgroundTransparency = rng:NextNumber(0, 0.85) })
				tw:Play()
				tw.Completed:Wait()
			end
		end)
	end

	-- the clouds: drift right to left, reappear past the edge
	local clouds: { Frame } = {}
	for i = 1, 6 do
		local cl = Instance.new("Frame")
		cl.Name = "Cloud" .. i
		cl.AnchorPoint = Vector2.new(0.5, 0.5)
		cl.BackgroundColor3 = Color3.fromRGB(255, 240, 230)
		cl.BackgroundTransparency = rng:NextNumber(0.72, 0.86)
		cl.BorderSizePixel = 0
		local w = rng:NextNumber(0.16, 0.3)
		cl.Size = UDim2.fromScale(w, w * rng:NextNumber(0.22, 0.32))
		cl.Position = UDim2.fromScale(rng:NextNumber(0, 1), rng:NextNumber(0.5, 0.9))
		round(cl, 1)
		cl:SetAttribute("Speed", rng:NextNumber(0.012, 0.03))
		cl.ZIndex = 2
		cl.Parent = back
		table.insert(clouds, cl)
	end

	-- the logo: three words in color, volume by a gradient, a dark outline, a bounce
	local logoStr, twoLines = logoText(title)
	local logo = label(back, logoStr, fnt, Color3.new(1, 1, 1), UDim2.fromScale(0.5, if twoLines then 0.27 else 0.3), UDim2.fromScale(0.86, if twoLines then 0.26 else 0.17))
	logo.Name = "Title"
	logo.RichText = true
	logo.ZIndex = 5
	stroke(logo, 5)
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(240, 240, 240)), ColorSequenceKeypoint.new(1, Color3.fromRGB(170, 170, 170)) })
	shade.Parent = logo
	local scale = Instance.new("UIScale")
	scale.Scale = 0.5
	scale.Parent = logo
	TweenService:Create(scale, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if subtitle and subtitle ~= "" then
		local sub = label(back, subtitle, fnt, Color3.fromRGB(246, 232, 200), UDim2.fromScale(0.5, 0.42), UDim2.fromScale(0.6, 0.06))
		sub.Name = "Subtitle"
		sub.ZIndex = 5
		stroke(sub, 2)
	end
	local summary = label(back, "", fnt, Color3.fromRGB(236, 228, 206), UDim2.fromScale(0.5, if subtitle and subtitle ~= "" then 0.5 else 0.45), UDim2.fromScale(0.8, 0.055))
	summary.Name = "Summary"
	summary.ZIndex = 5
	stroke(summary, 2)

	-- the loading bar: a dark trough, a green-gold fill, a hatchling dragon runs on the head of the fill toward the egg at the end
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.fromScale(0.5, 0.68)
	bar.Size = UDim2.fromScale(0.46, 0.034)
	bar.BackgroundColor3 = Color3.fromRGB(24, 22, 30)
	bar.BackgroundTransparency = 0.15
	bar.ZIndex = 5
	round(bar, 0.5)
	stroke(bar, 3)
	bar.Parent = back
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.new(1, 1, 1)
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 6
	round(fill, 0.5)
	local fg = Instance.new("UIGradient")
	fg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(60, 170, 60)), ColorSequenceKeypoint.new(0.7, Color3.fromRGB(120, 214, 80)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 214, 92)) })
	fg.Parent = fill
	fill.Parent = bar
	local egg = buildEgg(bar)
	egg.ZIndex = 7
	local runner = Instance.new("Frame")
	runner.Name = "Runner"
	runner.BackgroundTransparency = 1
	runner.AnchorPoint = Vector2.new(0.6, 1)
	runner.Position = UDim2.fromScale(0, 0.45)
	runner.Size = UDim2.fromScale(3.6, 3.0)
	runner.SizeConstraint = Enum.SizeConstraint.RelativeYY
	runner.ZIndex = 8
	runner.Parent = bar
	for _, d in runner:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 8
		end
	end
	for _, d in egg:GetDescendants() do
		if d:IsA("GuiObject") then
			d.ZIndex += 7
		end
	end

	local tip = label(back, "", fnt, Color3.new(1, 1, 1), UDim2.fromScale(0.5, 0.77), UDim2.fromScale(0.74, 0.055))
	tip.Name = "Tip"
	tip.ZIndex = 5
	stroke(tip, 2)
	local skip = label(back, "", fnt, Color3.fromRGB(130, 236, 92), UDim2.fromScale(0.5, 0.845), UDim2.fromScale(0.4, 0.05))
	skip.Name = "Skip"
	skip.ZIndex = 5
	skip.Visible = false
	stroke(skip, 2)
	Instance.new("UIScale").Parent = skip
	local step = label(back, "", Enum.Font.GothamMedium, Color3.fromRGB(225, 220, 235), UDim2.fromScale(0.5, 0.93), UDim2.fromScale(0.6, 0.032))
	step.Name = "Step"
	step.ZIndex = 5
	stroke(step, 1)

	-- a tap anywhere (when skipping is allowed)
	local catcher = Instance.new("TextButton")
	catcher.Name = "SkipCatcher"
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.ZIndex = 50
	catcher.Active = false
	catcher.AutoButtonColor = false
	catcher.Parent = back

	local self = setmetatable({
		gui = gui,
		back = back,
		logo = logo,
		step = step,
		summary = summary,
		tip = tip,
		skip = skip,
		catcher = catcher,
		fill = fill,
		runner = runner,
		egg = egg,
		clouds = clouds,
		shownAt = 0,
		conn = nil,
		minShow = 3,
		hold = 3,
		skipAfter = 1.5,
		fade = 0.8,
		target = 0,
		shown = 0,
		creep = 0,
		tips = {},
		tipSeconds = 3,
		tipIndex = 0,
		tipAt = 0,
		skippable = false,
		hidden = false,
	}, LoadingScreen)
	catcher.Activated:Connect(function()
		if self.skip.Visible then
			self:dismiss(0.35)
		end
	end)
	return self :: any
end

-- an animation frame: the bar catches up with the target (and creeps by itself a little while no step has arrived), the dragon runs, the egg rocks,
-- the tips rotate, "Tap to skip" appears after minShow
function LoadingScreen._tick(self: LoadingScreen, dt: number)
	local t = os.clock()
	for _, cl in self.clouds do
		local sp = (cl:GetAttribute("Speed") :: number?) or 0.02
		local x = cl.Position.X.Scale - sp * dt
		if x < -0.2 then
			x = 1.2
		end
		cl.Position = UDim2.fromScale(x, cl.Position.Y.Scale)
	end
	if self.shown < 1 then
		self.creep = math.min(self.creep + dt * 0.012, 0.08)
	end
	local goal = math.min(1, self.target + (if self.target < 1 then self.creep else 0))
	self.shown += (goal - self.shown) * (1 - math.exp(-dt * 3))
	local p = math.clamp(self.shown, 0, 1)
	self.fill.Size = UDim2.fromScale(p, 1)
	self.runner.Position = UDim2.fromScale(p * 0.9, 0.45)
	-- the 3D hatchling's run: hops and sways; at the egg - calmer
	local run = if p < 0.97 then 1 else 0.3
	local w = t * 13
	local V = self.view
	if V then -- the 3D hatchling - hops and sways with the whole model (the ViewportFrame is not rotated: Rotation does not suit it)
		local hop = V.h * 0.1 * math.abs(math.sin(w * 0.5)) * run
		V.model:PivotTo(CFrame.new(0, hop, 0) * CFrame.Angles(0, math.rad(10 * math.sin(t * 1.7)), math.rad(-6 * math.sin(w * 0.5) * run)) * V.base)
	end
	self.egg.Rotation = (4 + 8 * p) * math.sin(t * (3 + 5 * p))
	self.logo.Position = UDim2.fromScale(0.5, 0.3 + 0.006 * math.sin(t * 1.6))
	-- the tips in a cycle
	if #self.tips > 0 and t - self.tipAt >= self.tipSeconds then
		self.tipAt = t
		self.tipIndex = self.tipIndex % #self.tips + 1
		local tip = self.tip
		local text = self.tips[self.tipIndex]
		if tip.Text == "" then
			tip.Text = text
		else
			local out = TweenService:Create(tip, TweenInfo.new(0.18), { TextTransparency = 1 })
			out:Play()
			out.Completed:Once(function()
				if self.hidden then
					return
				end
				tip.Text = text
				TweenService:Create(tip, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
			end)
		end
	end
	-- "Tap to skip": the world is loaded (allowSkip) and skipAfter has passed (a tap enters faster, without a tap no longer than 3 s)
	if self.skippable and not self.skip.Visible and self.skip.Text ~= "" and t - self.shownAt >= self.skipAfter then
		self.skip.Visible = true
		self.catcher.Active = true
	end
	if self.skip.Visible then
		(self.skip:FindFirstChildOfClass("UIScale") :: UIScale).Scale = 1 + 0.06 * math.sin(t * 5)
	end
end

-- the real 3D hatchling from the game in a ViewportFrame. There is no frame-drawn fallback picture: without 3D
-- the bar runs without the hatchling, the hatchling appears when downloaded. The model (ReplicatedStorage.LoadingDragon, placed by the server) is already downloaded by the caller (PreloadAsync); the model's snout is at -Z, the camera
-- on the right side and slightly in front - the hatchling runs snout-first toward the egg. size - how many times the window is larger than the picture frame.
function LoadingScreen.useModel(self: LoadingScreen, model: Model, size: number?)
	if self.hidden or self.view then
		return
	end
	local m = model:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local cf, ext = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() - cf.Position) -- the model's frame center at the origin
	local vf = Instance.new("ViewportFrame")
	vf.Name = "Dragon3D"
	vf.BackgroundTransparency = 1
	vf.AnchorPoint = Vector2.new(0.5, 1)
	vf.Position = UDim2.fromScale(0.5, 1.48) -- at 1.06 the hatchling hung half a frame above the bar - the paws onto the bar
	vf.Size = UDim2.fromScale(size or 1.5, size or 1.5)
	-- almost white light from the camera side, a tighter frame, a 3/4 front angle
	vf.Ambient = Color3.fromRGB(235, 225, 215)
	vf.LightColor = Color3.fromRGB(255, 250, 240)
	vf.LightDirection = Vector3.new(-1, -0.6, 0.7)
	vf.ZIndex = 20
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	local dist = (math.max(ext.X, ext.Y, ext.Z) / 2) / math.tan(math.rad(15)) * 1.15
	cam.CFrame = CFrame.lookAt(Vector3.new(1, 0.32, -0.8).Unit * dist, Vector3.zero)
	cam.Parent = vf
	vf.CurrentCamera = cam
	m.Parent = vf
	vf.ImageTransparency = 1 -- the hatchling fades in over 0.25 s (no picture before it - no jerk on the empty bar)
	vf.Parent = self.runner
	game:GetService("TweenService"):Create(vf, TweenInfo.new(0.25), { ImageTransparency = 0 }):Play()
	self.view = { model = m, base = m:GetPivot(), h = ext.Y }
end

function LoadingScreen.show(self: LoadingScreen, text: string)
	self.step.Text = text
	self.shownAt = os.clock()
	if #self.tips == 0 then -- the tips are set before show (the splash probe) - the first at once, otherwise counted from the show
		self.tipAt = os.clock()
	end
	self.gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local warned = false
	self.conn = RunService.RenderStepped:Connect(function(dt: number)
		local ok, err = pcall(self._tick, self, dt)
		if not ok and not warned then
			warned = true
			warn("[LoadingScreen] " .. tostring(err))
		end
	end)
end

function LoadingScreen.setStep(self: LoadingScreen, text: string)
	self.step.Text = text
end

-- the loading fraction 0..1 (Main.client by steps); the bar catches up smoothly
function LoadingScreen.setProgress(self: LoadingScreen, p: number)
	if p > self.target then
		self.target = math.clamp(p, 0, 1)
		self.creep = 0
	end
end

function LoadingScreen.setSummary(self: LoadingScreen, text: string)
	self.summary.Text = text
end

-- tips in a cycle every seconds s, starting from a random one; skipText - the "Tap to skip" label (Strings)
function LoadingScreen.setTips(self: LoadingScreen, tips: { string }, seconds: number, skipText: string)
	self.tips = table.clone(tips)
	self.tipSeconds = seconds
	self.tipIndex = if #tips > 0 then rng:NextInteger(1, #tips) - 1 else 0
	self.tipAt = 0 -- the first tip - in the next frame
	self.skip.Text = skipText
end

-- the world is loaded: after minShow the screen can be skipped with a tap
function LoadingScreen.allowSkip(self: LoadingScreen)
	self.skippable = true
end

-- the font from Config once Shared has arrived (the splash is created earlier)
function LoadingScreen.setFont(self: LoadingScreen, name: string)
	local ok, f = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	if not ok or typeof(f) ~= "EnumItem" then
		return
	end
	for _, obj in self.back:GetDescendants() do
		if obj:IsA("TextLabel") and obj.Name ~= "Step" then
			obj.Font = f :: Enum.Font
		end
	end
end

-- minShow - not earlier; hold - how long to keep the screen without a tap if everything is ready; skipAfter - when to show "Tap to skip"
function LoadingScreen.setTiming(self: LoadingScreen, minShow: number, fade: number, hold: number?, skipAfter: number?)
	self.minShow = minShow
	self.fade = fade
	self.hold = math.max(minShow, hold or minShow)
	self.skipAfter = skipAfter or minShow
end

-- Studio probes: a screen of the given size at the center (a 1280x720 phone on the large P8 monitor)
function LoadingScreen.frameTo(self: LoadingScreen, w: number, h: number)
	self.back.AnchorPoint = Vector2.new(0.5, 0.5)
	self.back.Position = UDim2.fromScale(0.5, 0.5)
	self.back.Size = UDim2.fromOffset(w, h)
end

-- remove the screen now (a tap on "Tap to skip" or the end of loading)
function LoadingScreen.dismiss(self: LoadingScreen, fade: number?)
	if self.hidden then
		return
	end
	self.hidden = true
	self.catcher.Active = false
	local info = TweenInfo.new(fade or self.fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, obj in self.back:GetDescendants() do
		if obj:IsA("TextLabel") or obj:IsA("TextButton") then
			TweenService:Create(obj, info, { TextTransparency = 1 }):Play()
		elseif obj:IsA("UIStroke") then
			TweenService:Create(obj, info, { Transparency = 1 }):Play()
		end
		if obj:IsA("Frame") then
			TweenService:Create(obj, info, { BackgroundTransparency = 1 }):Play()
		end
	end
	TweenService:Create(self.back, info, { BackgroundTransparency = 1 }):Play()
	task.delay(info.Time, function()
		if self.conn then
			self.conn:Disconnect()
			self.conn = nil
		end
		self.gui:Destroy()
	end)
end

-- loading finished: the bar to the end (the dragon reaches the egg), the screen holds until hold seconds from the show unless skipped
-- earlier with a tap
function LoadingScreen.hide(self: LoadingScreen)
	self:setProgress(1)
	while not self.hidden and (os.clock() - self.shownAt < self.hold or self.shown < 0.985) do
		task.wait(0.05)
		if os.clock() - self.shownAt > self.hold + 3 then
			break
		end
	end
	self:dismiss()
end

return LoadingScreen
