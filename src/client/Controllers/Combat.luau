--!strict
-- Combat on the client (spec 19 "Sky guardians"): the BREATH button (phone - a circle left of the flight button column, PC - F)
-- auto-aim (Core/Combat.pick: the nearest Gloom in the cone in front of the camera, otherwise the nearest within the radius), AUTO for party members
-- (the AutoBreath attribute from the server), a breath projectile in the element color of the own companion, damage numbers and a cleansing flash per CombatFx,
-- the stage bar at the top (attributes Gloom_meadow / Gloom_sky: "stage|left|replay|guardian timer end"), the guardian's health
-- bar, the pulse circle. Damage and rewards are computed by the server; the client only aims and draws.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local CombatCore = require(Shared:WaitForChild("Core"):WaitForChild("Combat"))
local Economy = require(Shared:WaitForChild("Core"):WaitForChild("Economy"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Banners = require(script.Parent:WaitForChild("Banners"))
local Store = require(script.Parent:WaitForChild("Store"))

local Combat = {}

local C = Config.Combat
local S = Strings.Combat
local me = Players.LocalPlayer

local breathRemote: RemoteEvent? = nil
local gui: ScreenGui? = nil
local btn: TextButton? = nil
local autoBtn: TextButton? = nil
local bar: Frame? = nil
local barText: TextLabel? = nil
local barFill: Frame? = nil
local lastFire = 0
local autoOn = false
local muteUntil = 0
local companion: any = nil
local hud: any = nil -- HUD.setFocus - combat focus (spec 19 §17)
local incomingUntil = 0 -- a wave is announced - tense music until it arrives
local nearAt = -math.huge -- os.clock() when the Gloom was last closer than ui.focusRange
local clearAt = -math.huge -- the wave is cleared - the combat music lets go at once (victory phrase); musicHold - if the fight broke off
local chaseAt = -math.huge -- the own chase Gloom (tag GloomChase) closer than focusRange - combat music; the focus does NOT switch on (the home arrow stays visible)
local focusAcc = 0
local dragonBones: any = nil -- the mouth point from the head bone
local lastPurify: Vector3? = nil
local coinFlight: any = nil
local feedTipShown = false -- the feed-before-the-guardian toast - once per session
-- in "clear" the server writes next if the next wave is beyond the dragon's power (Core/Combat.huntStage) -
-- one "what next" line after the combat focus, no more often than weakEvery s;
-- in the quiet window it is shown only if the step banner is empty or leads to the same thing
local WEAK = { feed = S.weakFeed, grow = S.weakGrow, storm = S.weakStorm, sky = Strings.Hints.skyHint }
local OK: { [string]: { [string]: boolean } } = { feed = { feed = true }, sky = { fly = true, skyUp = true }, grow = {}, storm = {} }
local weakAt = -math.huge
local WEAK_EVERY = 45
local stepBanner: any = nil

-- the "what next" line after a win / loss; true - shown (or will be shown after delay s)
local function weakLine(next: any, delay: number): boolean
	local line = if typeof(next) == "string" then (WEAK :: any)[next] else nil
	if not line or os.clock() - weakAt < WEAK_EVERY then
		return false
	end
	local okK, kind = pcall(function()
		return if stepBanner and stepBanner.kind then stepBanner.kind() else nil
	end)
	if okK and kind ~= nil and not (OK[next] or {})[kind] then
		return false -- the banner leads to another step (mount, egg): that is the goal
	end
	weakAt = os.clock()
	if next == "feed" then
		feedTipShown = true -- do not repeat the same advice before the guardian
	end
	task.delay(delay, Banners.toast, line)
	return true
end
local keeperShown = false -- Old Ash's line about the Gloom - once per session until stage 1 is passed

local function fill(s: string, v: { [string]: any }): string
	return Loc.fill(s, v, nil, "")
end

local function elementColor(el: string?): Color3
	local g = C.glow and C.glow[el or "ember"]
	if g then
		return Color3.fromRGB(g[1], g[2], g[3])
	end
	local e = (Content.Elements :: any)[el or "ember"] or (Content.Elements :: any).ember
	return Color3.fromRGB(e.color[1], e.color[2], e.color[3])
end

local function myRoot(): BasePart?
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- the companion head of player uid (where the breath flies from); no model - the character root
local function mouthOf(userId: number): Vector3?
	if userId == me.UserId and companion and companion.model then
		local m = companion.model()
		local bm = if m and dragonBones and dragonBones.mouth then dragonBones.mouth(m) else nil
		if bm then
			return bm
		end
		if m then
			local head = m:FindFirstChild("Head", true)
			if head and head:IsA("BasePart") then
				return head.Position
			end
			return m:GetPivot().Position + Vector3.new(0, 1.5, 0)
		end
	end
	for _, m in CollectionService:GetTagged("Companion") do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == userId then
			local bm = if dragonBones and dragonBones.mouth then dragonBones.mouth(m) else nil
			return bm or (m:GetPivot().Position + Vector3.new(0, 1.5, 0))
		end
	end
	local p = Players:GetPlayerByUserId(userId)
	local ch = p and p.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r.Position + Vector3.new(0, 2, 0) else nil
end

local function gloomById(id: string): Model?
	for _, m in CollectionService:GetTagged("Gloom") do
		if m:IsA("Model") and m:GetAttribute("Id") == id then
			return m
		end
	end
	return nil
end

local function targets(): { CombatCore.Target }
	local list = {}
	for _, m in CollectionService:GetTagged("Gloom") do
		if m:IsA("Model") and m.Parent and ((m:GetAttribute("Hp") :: number?) or 0) > 0 then
			local p = m:GetPivot().Position
			table.insert(list, { id = m:GetAttribute("Id") :: string, pos = { x = p.X, y = p.Y, z = p.Z } })
		end
	end
	return list
end

local function myElement(): string?
	local data = Store.all()
	local uid = data.companion
	local d = if typeof(uid) == "string" and typeof(data.dragons) == "table" then data.dragons[uid] else nil
	return if d then d.element else nil
end

local function hasCompanion(): boolean
	return me:GetAttribute("CompanionStage") ~= nil
end

-- ---------------------------------------------------------------------------------------------- effects
-- the breath is not a beam but a stream of particles of the own element from the mouth: fire
-- billows and fades into smoke with sparks, ice - frosty vapor with crystals, water - spray, moss - spores, dusk - star mist, lightning -
-- a jagged discharge. The light at the mouth flickers. Particle speed - so the stream reaches the target in ~0.35 s
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local STYLE: { [string]: any } = {
	ember = { tex = FIRE, colors = { c3(255, 250, 220), c3(255, 170, 60), c3(200, 60, 20), c3(60, 30, 20) }, size = { 1.2, 4.2 }, rise = 4, smoke = true, sparks = c3(255, 200, 90), light = c3(255, 150, 60) },
	frost = { tex = SMOKE, colors = { c3(255, 255, 255), c3(200, 235, 255), c3(140, 200, 255) }, size = { 1.0, 3.6 }, rise = -1, sparks = c3(220, 245, 255), light = c3(170, 230, 255) },
	tide = { tex = SMOKE, colors = { c3(230, 255, 255), c3(120, 230, 230), c3(60, 170, 200) }, size = { 0.7, 2.6 }, rise = -6, sparks = c3(200, 255, 255), light = c3(80, 240, 230) },
	moss = { tex = SMOKE, colors = { c3(230, 255, 200), c3(160, 255, 120), c3(70, 160, 60) }, size = { 0.9, 3.2 }, rise = 1, sparks = c3(200, 255, 140), light = c3(160, 255, 120) },
	dusk = { tex = SMOKE, colors = { c3(240, 230, 255), c3(150, 140, 255), c3(70, 40, 140) }, size = { 1.0, 3.8 }, rise = 0, sparks = c3(255, 240, 255), light = c3(150, 140, 255) },
	storm = { tex = SPARK, colors = { c3(255, 255, 255), c3(255, 240, 150), c3(255, 220, 90) }, size = { 0.8, 2.0 }, rise = 0, bolt = true, sparks = c3(255, 250, 200), light = c3(255, 230, 109) },
}

local function emitter(parent: Attachment, tex: string, colors: { Color3 }, s0: number, s1: number, speed: number, life: number, spread: number, rise: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = tex
	local kp = {}
	for i, c in colors do
		table.insert(kp, ColorSequenceKeypoint.new((i - 1) / math.max(#colors - 1, 1), c))
	end
	e.Color = ColorSequence.new(kp)
	e.LightEmission = 0.9
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s0), NumberSequenceKeypoint.new(0.6, s1), NumberSequenceKeypoint.new(1, s1 * 1.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.7, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.EmissionDirection = Enum.NormalId.Front
	e.Speed = NumberRange.new(speed * 0.85, speed * 1.1)
	e.Lifetime = NumberRange.new(life * 0.85, life * 1.1)
	e.SpreadAngle = Vector2.new(spread, spread)
	e.Acceleration = Vector3.new(0, rise, 0)
	e.Drag = 1.2
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-180, 180)
	e.Rate = 0
	e.Parent = parent
	return e
end

-- own animated flame (flipbook 4x4) in the element color - a dense jet, a puff at the target
local FLAME: string? = if (C.breath.flameTex or 0) > 0 then "rbxassetid://" .. tostring(C.breath.flameTex) else nil
local function flameEmitter(parent: Attachment, colors: { Color3 }, s0: number, s1: number, speed: number, life: number, spread: number, rise: number): ParticleEmitter
	local e = emitter(parent, FLAME :: string, colors, s0, s1, speed, life, spread, rise)
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Rotation = NumberRange.new(-25, 25) -- flame tongues roughly upward, not in all directions
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.75, 0.25), NumberSequenceKeypoint.new(1, 1) })
	e.Drag = 0.8
	return e
end

-- an element clot with a trail: a glowing ball flies from the mouth to the target in seconds
local function ball(from: Vector3, to: Vector3, st: any, seconds: number)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * 1.3
	p.Material = Enum.Material.Neon
	p.Color = st.light
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(from)
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0.55, 0)
	a1.Parent = p
	local a2 = Instance.new("Attachment")
	a2.Position = Vector3.new(0, -0.55, 0)
	a2.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a1
	tr.Attachment1 = a2
	tr.Lifetime = 0.22
	tr.LightEmission = 1
	tr.FaceCamera = true
	tr.Color = ColorSequence.new(st.colors[1], st.colors[#st.colors])
	tr.Transparency = NumberSequence.new(0.1, 1)
	tr.Parent = p
	local l = Instance.new("PointLight")
	l.Color = st.light
	l.Range = 10
	l.Brightness = 3
	l.Parent = p
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
	Debris:AddItem(p, seconds + 0.05)
end

-- a puff of element flame at the hit point (together with the burst sparks and the enemy flash)
local function impact(at: Vector3, el: string?)
	if not FLAME then
		return
	end
	local st = STYLE[el or "ember"] or STYLE.ember
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local e = flameEmitter(a, st.colors, 2.0, 5.5, 6, 0.45, 180, 3)
	e:Emit(12)
	Debris:AddItem(a, 1)
end

-- a jagged lightning discharge of neon segments (two flashes)
local function bolt(from: Vector3, to: Vector3, color: Color3)
	for flashN = 1, 2 do
		task.delay((flashN - 1) * 0.09, function()
			local pts = { from }
			local n = 7
			local dir = to - from
			local side = dir:Cross(Vector3.yAxis)
			side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
			for i = 1, n - 1 do
				local t = i / n
				local jitter = side * (math.random() - 0.5) * 2.4 + Vector3.new(0, (math.random() - 0.5) * 2.4, 0)
				table.insert(pts, from + dir * t + jitter)
			end
			table.insert(pts, to)
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local seg = Instance.new("Part")
				seg.Anchored = true
				seg.CanCollide = false
				seg.CanQuery = false
				seg.CanTouch = false
				seg.CastShadow = false
				seg.Material = Enum.Material.Neon
				seg.Color = color
				seg.Size = Vector3.new(0.25, 0.25, (b - a).Magnitude)
				seg.CFrame = CFrame.lookAt((a + b) / 2, b)
				seg.Parent = workspace
				TweenService:Create(seg, TweenInfo.new(0.12), { Transparency = 1 }):Play()
				Debris:AddItem(seg, 0.15)
			end
		end)
	end
end

local function shot(from: Vector3, to: Vector3, color: Color3, el: string?)
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	local st = STYLE[el or "ember"] or STYLE.ember
	local a0 = Instance.new("Attachment")
	a0.WorldCFrame = CFrame.lookAt(from, to)
	a0.Parent = workspace.Terrain
	local life = 0.42
	local speed = dist / (life * 0.8)
	if FLAME then
		-- a dense jet of own flame from the mouth to the target (a puff at once + a stream for streamSeconds) and a clot with a trail
		local fl = flameEmitter(a0, st.colors, st.size[1] * 1.4, st.size[2] * 1.4, speed, life, 7, st.rise)
		fl:Emit(16)
		fl.Rate = C.breath.streamRate
		task.delay(C.breath.streamSeconds, function()
			fl.Rate = 0
		end)
		ball(from, to, st, C.breath.flySeconds)
	else
		local main = emitter(a0, st.tex, st.colors, st.size[1], st.size[2], speed, life, 9, st.rise)
		main:Emit(44)
		task.delay(0.08, function()
			main:Emit(30)
		end)
		task.delay(0.16, function()
			main:Emit(22)
		end)
	end
	if st.smoke then -- the fire fades into smoke at the target
		local sm = emitter(a0, SMOKE, { c3(90, 80, 75), c3(40, 36, 34) }, 1.6, 4.5, speed * 0.75, life * 1.5, 12, 5)
		sm.LightEmission = 0
		sm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.4, 0.6), NumberSequenceKeypoint.new(1, 1) })
		sm:Emit(14)
	end
	local sp = emitter(a0, SPARK, { st.sparks, st.sparks }, 0.35, 0.15, speed * 1.15, life * 0.9, 14, -8)
	sp.LightEmission = 1
	sp:Emit(18)
	if st.bolt then
		bolt(from, to, st.light)
	end
	local light = Instance.new("PointLight")
	light.Color = st.light
	light.Range = 12
	light.Brightness = 3
	light.Parent = a0
	task.spawn(function() -- flicker at the mouth
		for _ = 1, 6 do
			light.Brightness = 2 + math.random() * 2.5
			task.wait(0.05)
		end
		TweenService:Create(light, TweenInfo.new(0.2), { Brightness = 0 }):Play()
	end)
	Debris:AddItem(a0, life * 2.2)
end

-- enemy flash on hit (white highlight 0.12 s) and the health bar above it
local function flash(m: Model)
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.2
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = m
	h.Parent = m
	Debris:AddItem(h, 0.12)
end

local function hpBar(m: Model)
	if m:GetAttribute("Guardian") == true then
		return -- the guardian has the bar at the top of the screen
	end
	local body = m.PrimaryPart
	if not body then
		return
	end
	local bb = body:FindFirstChild("HpBar") :: BillboardGui?
	if not bb then
		local g = Instance.new("BillboardGui")
		g.Name = "HpBar"
		g.Size = UDim2.fromOffset(64, 9)
		g.StudsOffsetWorldSpace = Vector3.new(0, (body.Size.Y / 2) + 2.2, 0)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.MaxDistance = 90
		g.Adornee = body
		local back = Instance.new("Frame")
		back.Size = UDim2.fromScale(1, 1)
		back.BackgroundColor3 = Color3.fromRGB(24, 16, 34)
		back.BorderSizePixel = 0
		back.Parent = g
		UIKit.corner(back, 0.5)
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(196, 120, 255)
		f.BorderSizePixel = 0
		f.Parent = back
		UIKit.corner(f, 0.5)
		g.Parent = body
		bb = g
	end
	local hp = (m:GetAttribute("Hp") :: number?) or 0
	local mx = math.max((m:GetAttribute("MaxHp") :: number?) or 1, 1)
	local fill = (bb :: BillboardGui):FindFirstChild("Fill", true) :: Frame?
	if fill then
		TweenService:Create(fill, TweenInfo.new(0.15), { Size = UDim2.fromScale(math.clamp(hp / mx, 0, 1), 1) }):Play()
	end
end

local function burst(at: Vector3, color: Color3, count: number, size: number, light: boolean)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	e.LightEmission = if light then 1 else 0.5
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(6, 16)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	if light then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 240, 200)
		l.Range = size * 6
		l.Brightness = 4
		l.Parent = a
		TweenService:Create(l, TweenInfo.new(0.9), { Brightness = 0 }):Play()
	end
	Debris:AddItem(a, 1.6)
end

-- petals: warm dots slowly descend (cleansing is not an explosion but light and flowers). Public as Combat.bloom (spec 20: "the world answers
-- the light" - also triggered by the night glow of dragons)
local function petals(at: Vector3, big: boolean)
	local a = Instance.new("Attachment")
	a.WorldPosition = at
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 220)), ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 244, 196)), ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 255, 214)) })
	e.LightEmission = 0.4
	e.Size = NumberSequence.new(if big then 0.9 else 0.5)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.4, 2.4)
	e.Speed = NumberRange.new(2, if big then 10 else 5)
	e.Acceleration = Vector3.new(0, -3, 0)
	e.Drag = 1.5
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-120, 120)
	e.Rate = 0
	e.Parent = a
	e:Emit(if big then 90 else 24)
	Debris:AddItem(a, 3)
end

local function number(at: Vector3, text: string, color: Color3)
	local a = Instance.new("Attachment")
	a.WorldPosition = at + Vector3.new((math.random() - 0.5) * 2, 1.5, (math.random() - 0.5) * 2)
	a.Parent = workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(170, 58)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 120
	bb.Adornee = a
	bb.Parent = a
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = UIKit.FONT
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 1.7
	sc.Parent = t
	TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(C.ui.numberSeconds), { StudsOffsetWorldSpace = Vector3.new(0, C.ui.numberRise, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(C.ui.numberSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(a, C.ui.numberSeconds + 0.1)
end

-- ground height under the meadow guardian (the pulse circle lies on the grass)
local function groundGap(at: Vector3): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	local f = workspace:FindFirstChild("Gloom")
	if f then
		table.insert(skip, f)
	end
	if me.Character then
		table.insert(skip, me.Character)
	end
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(at, Vector3.new(0, -60, 0), params)
	return if hit then at.Y - hit.Position.Y - 0.2 else 0
end

local function buttonPx(): number
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(800, 600)
	return math.max(C.ui.minPx, math.min(C.ui.buttonPx, math.floor(v.Y * 0.2)))
end

local function ring(at: Vector3, radius: number, seconds: number, onGround: boolean)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(0.3, radius * 2, radius * 2)
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(170, 90, 230)
	p.Transparency = 0.75
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local y = if onGround then at.Y - groundGap(at) else at.Y
	p.CFrame = CFrame.new(at.X, y, at.Z) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Transparency = 0.25 }):Play()
	task.delay(seconds, function()
		p.Color = Color3.fromRGB(255, 255, 255)
		TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1, Size = Vector3.new(0.3, radius * 2.3, radius * 2.3) }):Play()
	end)
	Debris:AddItem(p, seconds + 0.5)
end

-- ---------------------------------------------------------------------------------------------- hit
local function fireAt(id: string)
	local r = breathRemote
	if not r then
		return
	end
	r:FireServer(id)
	local m = gloomById(id)
	local from = mouthOf(me.UserId)
	if m and from then
		shot(from, m:GetPivot().Position, elementColor(myElement()), myElement())
	end
	Sounds.play("wing", { pitch = true, volume = 0.5 })
end

local function tryBreath(manual: boolean): boolean
	local now = os.clock()
	if now - lastFire < C.breath.cooldown or now < muteUntil then
		return false
	end
	if not hasCompanion() then
		if manual then
			Banners.toast(S.noDragon)
		end
		return false
	end
	local r = myRoot()
	local cam = workspace.CurrentCamera
	if not r or not cam then
		return false
	end
	local p = r.Position
	local look = cam.CFrame.LookVector
	local id = CombatCore.pick({ x = p.X, y = p.Y, z = p.Z }, { x = look.X, y = look.Y, z = look.Z }, targets(), C)
	if not id then
		if manual then
			Banners.toast(S.noTarget)
		end
		return false
	end
	lastFire = now
	fireAt(id)
	if btn then
		btn.Size = UDim2.fromOffset(btn.AbsoluteSize.X * 0.92, btn.AbsoluteSize.Y * 0.92)
		task.delay(0.08, function()
			if btn then
				local s = buttonPx()
				btn.Size = UDim2.fromOffset(s, s)
			end
		end)
	end
	return true
end

-- ---------------------------------------------------------------------------------------------- screen

local function jumpButton(): GuiObject?
	local pg = me:FindFirstChild("PlayerGui")
	local tg = pg and pg:FindFirstChild("TouchGui")
	local fr = tg and tg:FindFirstChild("TouchControlFrame")
	local jb = fr and fr:FindFirstChild("JumpButton")
	return if jb and jb:IsA("GuiObject") and jb.Visible then jb else nil
end

-- the button left of the flight button column (Down/Dismount stand right next to the jump - Fly.layoutButtons), AUTO above it
local function layout()
	local b = btn
	if not b then
		return
	end
	local s = buttonPx()
	local gap = C.ui.gap
	b.Size = UDim2.fromOffset(s, s)
	local jb = jumpButton()
	local x, y
	-- left of the leftmost flight button (Fly.layoutButtons puts Up/Down/Dismount next to the jump; they exist even when invisible:
	-- the column width computed "by eye" ran into Down on PC), vertically - the center of the jump or of the Dismount button
	local pg = me:FindFirstChild("PlayerGui")
	local mv = pg and pg:FindFirstChild("Movement")
	local minX, midY = math.huge, nil
	if mv then
		for _, n in { "Up", "Down", "Dismount" } do
			local o = mv:FindFirstChild(n)
			if o and o:IsA("GuiObject") and o.AbsoluteSize.X > 0 then
				minX = math.min(minX, o.AbsolutePosition.X)
				if n == "Dismount" then
					midY = o.AbsolutePosition.Y + o.AbsoluteSize.Y / 2
				end
			end
		end
	end
	local cam = workspace.CurrentCamera
	local v = if cam then cam.ViewportSize else Vector2.new(800, 600)
	if jb then
		minX = math.min(minX, jb.AbsolutePosition.X)
		midY = jb.AbsolutePosition.Y + jb.AbsoluteSize.Y / 2
	end
	if minX == math.huge then
		minX = v.X - 16
	end
	x = minX - gap - s
	y = (midY or (v.Y - 110 - s / 2)) - s / 2
	-- the side card (Welcome gift / Invite, UIKit.sideCard) on the right under the Keeper plaque covered AUTO and the top of BREATH -
	-- the buttons go down below the visible card, not below the screen edge
	if pg then
		for _, name in { "FreeGiftCard", "InviteCard" } do
			local sg = pg:FindFirstChild(name)
			if sg and sg:IsA("ScreenGui") and sg.Enabled then
				for _, o in sg:GetChildren() do
					if o:IsA("GuiObject") and o.Visible and o.AbsolutePosition.X + o.AbsoluteSize.X > x then
						y = math.max(y, o.AbsolutePosition.Y + o.AbsoluteSize.Y + gap)
					end
				end
			end
		end
	end
	y = math.min(y, v.Y - s - 4)
	b.Position = UDim2.fromOffset(x, y)
	if autoBtn then
		local h = math.floor(s * 0.42)
		local w = math.floor(s * 0.8)
		autoBtn.Size = UDim2.fromOffset(w, h)
		local ax, ay = x - gap - w, y + s - h -- left of BREATH, aligned to the bottom
		-- on the left AUTO runs into the main HUD button
		-- strip (Ride / Fly / Hatch at the bottom center, together with Feed all - 0.38..0.6 of the width) - then on the left aligned to the top, otherwise above BREATH
		local hud = pg and pg:FindFirstChild("HUD")
		local act = hud and hud:FindFirstChild("Action")
		if hud and hud:IsA("ScreenGui") and act and act:IsA("GuiObject") and act.AbsoluteSize.X > 0 then
			local W, H = hud.AbsoluteSize.X, hud.AbsoluteSize.Y
			local aw, ah = act.AbsoluteSize.X, act.AbsoluteSize.Y
			local zx1, zx2 = W * 0.38 - aw / 2 - gap, W * 0.6 + aw / 2 + gap
			local zy1 = H * 0.965 - ah - gap
			local function inZone(px: number, py: number): boolean
				return px < zx2 and px + w > zx1 and py + h > zy1
			end
			if inZone(ax, ay) then
				if not inZone(ax, y) then
					ay = y -- on the left, aligned to the top of BREATH
				else
					ax, ay = x + (s - w) / 2, y - gap - h -- above BREATH
				end
			end
		end
		autoBtn.Position = UDim2.fromOffset(ax, ay)
	end
end

local function setAuto(on: boolean)
	autoOn = on
	if autoBtn then
		autoBtn.BackgroundColor3 = if on then UIKit.GREEN else Color3.fromRGB(70, 70, 82)
	end
end

local function waveInfo(arena: string): (number?, number, boolean, number?)
	local raw = me:GetAttribute("Gloom_" .. arena)
	if typeof(raw) ~= "string" then
		return nil, 0, false, nil
	end
	local st, left, rep, ends = string.match(raw, "^(%d+)|(%d+)|(%d)|(.*)$")
	return tonumber(st), tonumber(left) or 0, rep == "1", tonumber(ends)
end

-- the active wave nearest to the player (meadow or sky) and its label
local function refreshBar()
	local b, t, f = bar, barText, barFill
	if not b or not t or not f then
		return
	end
	local r = myRoot()
	local best: string? = nil
	for _, arena in { "meadow", "sky" } do
		local st = waveInfo(arena)
		if st then
			if arena == "sky" and r and r.Position.Y > C.arena.skyY - 40 then
				best = arena
			elseif not best and not (arena == "meadow" and r and r.Position.Y > C.arena.skyY - 40 and waveInfo("sky") ~= nil) then
				best = arena
			end
		end
	end
	if not best then
		b.Visible = false
		return
	end
	local pg = me:FindFirstChild("PlayerGui")
	local big = pg and pg:FindFirstChild("Banners")
	local bf = big and big:FindFirstChild("Banner")
	if bf and bf:IsA("GuiObject") and bf.Visible then
		b.Visible = false -- windows do not overlap - no bar while the banner is up
		return
	end
	local sb = pg and pg:FindFirstChild("StepBanner")
	local step = sb and sb:FindFirstChild("Step")
	local top = 74
	-- in combat focus the step banner is hidden (HUD.setFocus) - the stage bar takes its place under the coins
	if sb and sb:IsA("ScreenGui") and sb.Enabled and step and step:IsA("GuiObject") and step.Visible and step.AbsoluteSize.Y > 0 then
		top = step.AbsolutePosition.Y + step.AbsoluteSize.Y + 4
	else
		local hud = pg and pg:FindFirstChild("HUD")
		local coinsF = hud and hud:FindFirstChild("Coins")
		if coinsF and coinsF:IsA("GuiObject") then
			top = coinsF.AbsolutePosition.Y + coinsF.AbsoluteSize.Y + 4
		end
	end
	local g = b:FindFirstAncestorOfClass("ScreenGui")
	b.Position = UDim2.new(0.5, 0, 0, top - (if g then g.AbsolutePosition.Y else 0))
	local st, left, rep, ends = waveInfo(best)
	local def = st and CombatCore.stage(C, st)
	if not st or not def then
		b.Visible = false
		return
	end
	b.Visible = true
	if def.guardian then
		local hp, maxHp = 0, def.hp
		for _, m in CollectionService:GetTagged("Gloom") do
			if m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Guardian") == true then
				hp = (m:GetAttribute("Hp") :: number?) or 0
				maxHp = (m:GetAttribute("MaxHp") :: number?) or maxHp
			end
		end
		local leftS = if ends then math.max(0, math.floor(ends - workspace:GetServerTimeNow())) else 0
		t.Text = fill(S.timer, { name = def.name or "", time = string.format("%d:%02d", leftS // 60, leftS % 60) })
		f.Size = UDim2.fromScale(math.clamp(hp / math.max(maxHp, 1), 0, 1), 1)
		f.BackgroundColor3 = Color3.fromRGB(176, 104, 236)
	else
		local label = if rep then S.replay else fill(S.stage, { k = st, n = CombatCore.stageCount(C) })
		t.Text = label .. "  ·  " .. fill(S.left, { n = left })
		f.Size = UDim2.fromScale(math.clamp(1 - left / math.max(def.n or 1, 1), 0, 1), 1)
		f.BackgroundColor3 = UIKit.GOLD
	end
end

local function buildGui()
	local g = UIKit.screen("Combat", 3)
	gui = g
	local b = UIKit.button(g, S.breath, Color3.fromRGB(226, 110, 52), function()
		tryBreath(true)
	end, { minSize = Vector2.new(C.ui.minPx, C.ui.minPx) })
	b.Name = "Breath"
	UIKit.corner(b, 0.5)
	b.TextScaled = true
	btn = b
	local a = UIKit.button(g, S.auto, Color3.fromRGB(70, 70, 82), function()
		if me:GetAttribute("AutoBreath") == true then
			setAuto(not autoOn)
		else
			Banners.toast(S.autoLocked)
		end
	end, { minSize = Vector2.new(44, 24) })
	a.Name = "Auto"
	autoBtn = a
	-- the stage bar: top center under the step banner
	local f = Instance.new("Frame")
	f.Name = "StageBar"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 74)
	f.Size = UDim2.fromOffset(C.ui.barWidth, 26)
	f.BackgroundColor3 = Color3.fromRGB(28, 22, 40)
	f.BackgroundTransparency = 0.25
	f.Visible = false
	f.Parent = g
	UIKit.corner(f, 0.5)
	local fillF = Instance.new("Frame")
	fillF.Name = "Fill"
	fillF.Size = UDim2.fromScale(0, 1)
	fillF.BackgroundColor3 = UIKit.GOLD
	fillF.BackgroundTransparency = 0.15
	fillF.Parent = f
	UIKit.corner(fillF, 0.5)
	local t = UIKit.text(f, "", Color3.new(1, 1, 1), { Size = UDim2.fromScale(1, 1), TextScaled = true, ZIndex = 3 })
	t.Name = "Label"
	if Config.UI.plainText then
		-- the stage bar is a text line with an outline and a thin scale under it (not a plaque)
		f.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 0.78)
		local track = Instance.new("Frame")
		track.Name = "Track"
		track.BackgroundColor3 = Color3.fromRGB(28, 22, 40)
		track.BackgroundTransparency = 0.35
		track.Position = UDim2.fromScale(0.15, 0.82)
		track.Size = UDim2.fromScale(0.7, 0.16)
		track.Parent = f
		UIKit.corner(track, 0.5)
		fillF.Parent = track
		UIKit.plain(f)
	end
	bar, barText, barFill = f, t, fillF
	layout()
end

-- the button is visible when Gloom is near (own or foreign, closer than breath.showRange - within striking distance) and a companion exists; otherwise the screen stays clean
-- own Gloom near and the player is not breathing
-- for ui.pointAfter s - the same bouncing yellow arrow as for the steps (Hints), above BREATH; a shot or AUTO removes it. The FIGHT step arrow
-- from Hints (HintArrow2D) is already above the button - do not add a second one
local shownAt = -math.huge
local fightArrow: GuiObject? = nil
local arrowWarned = false
local function pointArrow(b: TextButton, show: boolean, mine: boolean)
	local now = os.clock()
	if not show then
		shownAt = -math.huge
	elseif shownAt == -math.huge then
		shownAt = now
	end
	-- stunned (muteUntil) - cannot shoot, the arrow does not call; for an experienced player (after autoFromStage stages) - less often
	local c = Store.get("combat")
	local cleared = if typeof(c) == "table" then tonumber(c.stage) or 0 else 0
	local after = if cleared >= (C.ui.autoFromStage or 2) then (C.ui.pointAfterOld or 4) else (C.ui.pointAfter or 2)
	local want = show and mine and not autoOn and now - math.max(lastFire, shownAt, muteUntil) >= after
		and b:FindFirstChild("HintArrow2D") == nil
	if want and not fightArrow then
		local g = UIKit.arrowGlyph(b, { Name = "FightArrow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromScale(0.5, 1.0), ZIndex = 5 })
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = g
		fightArrow = g
		task.spawn(function()
			while g.Parent do
				local t = TweenService:Create(g, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 0, -14) })
				t:Play()
				t.Completed:Wait()
				if not g.Parent then
					break
				end
				local t2 = TweenService:Create(g, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 0, -2) })
				t2:Play()
				t2.Completed:Wait()
			end
		end)
	elseif not want and fightArrow then
		fightArrow:Destroy()
		fightArrow = nil
	end
end

local function refreshButton()
	local b = btn
	if not b then
		return
	end
	local r = myRoot()
	local show, mine = false, false
	if r and hasCompanion() then
		for _, m in CollectionService:GetTagged("Gloom") do
			if m:IsA("Model") and (m:GetPivot().Position - r.Position).Magnitude < C.breath.showRange then
				show = true
				-- the arrow calls only to own Gloom within breath reach (C.breath.range - auto-aim; farther the button answers "No Gloom")
				if m:GetAttribute("OwnerId") == me.UserId and (m:GetPivot().Position - r.Position).Magnitude < C.breath.range then
					mine = true
					break
				end
			end
		end
	end
	b.Visible = show
	local okA, errA = pcall(pointArrow, b, show, mine) -- an arrow error does not break the stage bar and AUTO in the same tick
	if not okA and not arrowWarned then
		arrowWarned = true
		warn("[Combat] fight arrow: " .. tostring(errA))
	end
	if autoBtn then
		-- AUTO appears after the 2nd cleared stage - first the player learns to hit by hand
		local c = Store.get("combat")
		local cleared = if typeof(c) == "table" then tonumber(c.stage) or 0 else 0
		autoBtn.Visible = show and cleared >= (C.ui.autoFromStage or 2)
	end
end

-- ---------------------------------------------------------------------------------------------- server events
-- Gloom attacks: the hound's jump line (the strike spot is visible in advance), the shard-thrower's clot, a hit on the player
local function neonPart(size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local q = Instance.new("Part")
	q.Anchored = true
	q.CanCollide = false
	q.CanQuery = false
	q.CanTouch = false
	q.CastShadow = false
	q.Material = Enum.Material.Neon
	q.Color = color
	q.Transparency = transparency
	q.Size = size
	q.CFrame = cf
	q.Parent = workspace
	return q
end

local function lungeLine(from: Vector3, to: Vector3, warn: number)
	local flatFrom = Vector3.new(from.X, to.Y - 2.6, from.Z)
	local flatTo = Vector3.new(to.X, to.Y - 2.6, to.Z)
	local len = (flatTo - flatFrom).Magnitude
	if len < 1 then
		return
	end
	local line = neonPart(Vector3.new(1.4, 0.15, len), CFrame.lookAt((flatFrom + flatTo) / 2, flatTo), Color3.fromRGB(220, 70, 120), 0.45)
	local spot = neonPart(Vector3.new(0.15, 8, 8), CFrame.new(flatTo) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(220, 70, 120), 0.5)
	spot.Shape = Enum.PartType.Cylinder
	TweenService:Create(line, TweenInfo.new(warn), { Transparency = 0.15 }):Play()
	TweenService:Create(spot, TweenInfo.new(warn), { Transparency = 0.15 }):Play()
	Debris:AddItem(line, warn + 0.15)
	Debris:AddItem(spot, warn + 0.3)
end

local function orb(from: Vector3, to: Vector3, warn: number, seconds: number)
	local b = neonPart(Vector3.new(0.6, 0.6, 0.6), CFrame.new(from), Color3.fromRGB(170, 80, 255), 0)
	b.Shape = Enum.PartType.Ball
	local l = Instance.new("PointLight")
	l.Color = Color3.fromRGB(170, 80, 255)
	l.Range = 10
	l.Brightness = 3
	l.Parent = b
	local tr = Instance.new("ParticleEmitter")
	tr.Color = ColorSequence.new(Color3.fromRGB(190, 120, 255), Color3.fromRGB(60, 20, 90))
	tr.LightEmission = 0.8
	tr.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	tr.Lifetime = NumberRange.new(0.35)
	tr.Rate = 60
	tr.Speed = NumberRange.new(0)
	tr.Parent = b
	-- the hit spot on the ground - shows where to move away
	local mark = neonPart(Vector3.new(0.15, 6, 6), CFrame.new(to.X, to.Y - 2.6, to.Z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(170, 80, 255), 0.6)
	mark.Shape = Enum.PartType.Cylinder
	TweenService:Create(b, TweenInfo.new(warn), { Size = Vector3.new(1.8, 1.8, 1.8) }):Play() -- gathers strength
	task.delay(warn, function()
		if b.Parent then
			TweenService:Create(b, TweenInfo.new(math.max(seconds - warn, 0.1), Enum.EasingStyle.Linear), { CFrame = CFrame.new(to) }):Play()
		end
	end)
	task.delay(seconds, function()
		burst(to, Color3.fromRGB(170, 80, 255), 16, 1.4, false)
	end)
	Debris:AddItem(b, seconds + 0.05)
	Debris:AddItem(mark, seconds + 0.2)
end

local vignette: Frame? = nil
local function struck()
	Sounds.play("deny", { volume = 0.6 })
	local g = gui
	if g then
		local v = vignette
		if not v then
			local f = Instance.new("Frame")
			f.Name = "Struck"
			f.Size = UDim2.fromScale(1, 1)
			f.BackgroundColor3 = Color3.fromRGB(110, 40, 170)
			f.BackgroundTransparency = 1
			f.ZIndex = 0
			f.Parent = g
			v = f
			vignette = f
		end
		local vv = v :: Frame
		vv.BackgroundTransparency = 0.55
		TweenService:Create(vv, TweenInfo.new(0.45), { BackgroundTransparency = 1 }):Play()
	end
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType == Enum.CameraType.Custom then
		task.spawn(function()
			for i = 1, 5 do
				local o = (5 - i) * 0.12
				cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * o, (math.random() - 0.5) * o, 0)
				task.wait(0.03)
			end
		end)
	end
end

-- the guardian's entrance: the camera shows it whole for a second, then back
local function guardianIntro()
	local cam = workspace.CurrentCamera
	local r = myRoot()
	if not cam or not r or cam.CameraType ~= Enum.CameraType.Custom then
		return
	end
	local target: Model? = nil
	for _, m in CollectionService:GetTagged("Gloom") do
		if m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Guardian") == true then
			target = m
		end
	end
	if not target then
		return
	end
	local gp = (target :: Model):GetPivot().Position
	local dir = Vector3.new(gp.X - r.Position.X, 0, gp.Z - r.Position.Z)
	dir = if dir.Magnitude > 1 then dir.Unit else Vector3.zAxis
	local start = cam.CFrame
	local show = CFrame.lookAt(r.Position - dir * 8 + Vector3.new(0, 7, 0), gp + Vector3.new(0, 3, 0))
	cam.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(cam, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { CFrame = show }):Play()
	task.wait(1.6)
	TweenService:Create(cam, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = start }):Play()
	task.wait(0.5)
	cam.CameraType = Enum.CameraType.Custom
end

local function onFx(p: any)
	if typeof(p) ~= "table" then
		return
	end
	local k = p.k
	if k == "hit" then
		local m = gloomById(p.id)
		if m then
			local at = m:GetPivot().Position
			if p.by ~= me.UserId then
				local from = mouthOf(p.by)
				if from then
					shot(from, at, elementColor(p.el), p.el)
				end
			end
			task.delay(C.breath.flySeconds, function()
				impact(at, p.el)
				burst(at, elementColor(p.el), 14, 1.2, true)
				if m.Parent then -- the Gloom could have been cleansed during the flight (model destroyed)
					pcall(flash, m)
					pcall(hpBar, m)
				end
				number(at, "-" .. tostring(p.dmg), if p.by == me.UserId then UIKit.GOLD else Color3.fromRGB(200, 220, 255))
			end)
		end
	elseif k == "purify" then
		local at: Vector3 = p.pos
		lastPurify = at
		burst(at, Color3.fromRGB(255, 244, 210), if p.guardian then 120 else 40, if p.guardian then 4 else 2, true)
		petals(at, p.guardian == true)
		Sounds.play(if p.guardian then "quest_done" else "coin_plus", { pitch = true, volume = 0.6 })
	elseif k == "clear" then
		clearAt = os.clock()
		incomingUntil = 0
		me:SetAttribute("Fight", nil) -- before fightWin: otherwise Sounds would switch the combat track back on before the combat tick
		local okW, errW = pcall(Sounds.fightWin)
		if not okW then
			warn("[Combat] fightWin: " .. tostring(errW))
		end
		if coinFlight and coinFlight.fly and lastPurify then -- the coins fly to the counter from the cleansing point
			pcall(coinFlight.fly, math.clamp(math.floor((p.coins or 0) / 10), 3, 10), lastPurify)
		end
		local text = if p.egg then fill(S.clearEgg, { n = p.coins }) else fill(S.clear, { n = p.coins })
		if p.guardian and not p.replay then
			local def = CombatCore.stage(C, p.stage)
			Banners.banner(fill(S.guardianWin, { name = def and def.name or "" }), UIKit.GOLD, text, 4)
			if p.stage == CombatCore.firstSky(C) - 1 then
				task.delay(4.2, function()
					Banners.banner(S.skyOpen, Color3.fromRGB(140, 205, 255), nil, 4)
				end)
			end
		else
			Banners.toast(text)
		end
		weakLine(p.next, (C.ui.focusHold or 4) + 0.3)
	elseif k == "fail" then
		-- the guardian returns only if the dragon is strong enough - then the "feed / grow" line instead of "in N s"
		if not (p.next and weakLine(p.next, 0)) then
			Banners.toast(fill(S.fail, { s = p.retry }))
		end
	elseif k == "help" then
		Banners.toast(fill(S.help, { n = p.coins }))
	elseif k == "touch" then
		muteUntil = os.clock() + (p.seconds or 1)
		Banners.toast(S.muted)
		Sounds.play("deny", { volume = 0.5 })
	elseif k == "incoming" then -- a wave in a few seconds - a large line, tense music right away
		if p.cancel then -- the wave was cancelled (menu, mounted / took off) - the music does not hang for nothing
			incomingUntil = 0
			return
		end
		incomingUntil = os.clock() + (tonumber(p.seconds) or 2) + 3
		me:SetAttribute("Fight", true)
		Banners.banner(S.incoming, Color3.fromRGB(196, 120, 255), nil, 2.2, true)
		Sounds.play("wing", { pitch = true, volume = 0.7 })
	elseif k == "miss" then -- the server rejected the hit - a hint on what to fix
		Banners.toast(if p.why == "range" then S.noTarget else S.noDragon)
	elseif k == "stun" then
		muteUntil = os.clock() + (p.seconds or 2)
		Banners.toast(S.stunned)
		Sounds.play("deny", { volume = 0.7 })
	elseif k == "warn" then
		ring(p.pos, p.radius, p.seconds, not p.sky)
	elseif k == "lunge" then
		lungeLine(p.from, p.to, p.warn)
	elseif k == "orb" then
		orb(p.from, p.to, p.warn, p.seconds)
	elseif k == "struck" then
		muteUntil = os.clock() + (p.seconds or 1)
		struck()
	elseif k == "guardian" and p.owner == me.UserId then
		Sounds.play("storm", { volume = 0.6 })
		task.delay(0.3, guardianIntro)
		-- feeding = x2 power, and the "feed" step ranks below combat - say it once before the guardian if not fed and coins suffice
		local data = Store.all()
		local d = if typeof(data.companion) == "string" and typeof(data.dragons) == "table" then data.dragons[data.companion] else nil
		if d and not (d.fedUntil and d.fedUntil > os.time()) and not feedTipShown then
			local ok, price = pcall(Economy.feedPrice, d, data.ascension or 0, Config.Balance)
			if ok and (data.coins or 0) >= price then
				feedTipShown = true
				task.delay(1.5, Banners.toast, S.feedTip)
			end
		end
	end
end

-- bloom at a point (Gloom cleansing; spec 20 - the dragons' light at night): petals and, if big, larger and more of them
function Combat.bloom(at: Vector3, big: boolean?)
	petals(at, big == true)
end

-- the BREATH button (the FIGHT step arrow of Hints); hidden - nil
function Combat.button(): GuiObject?
	return if btn and btn.Visible then btn else nil
end

function Combat.init(_snapshot: any, loaded: any)
	companion = loaded.Companion
	hud = loaded.HUD
	stepBanner = loaded.StepBanner
	coinFlight = loaded.CoinFlight
	dragonBones = loaded.DragonBones
end

function Combat.start()
	if not C.on then
		return
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	breathRemote = remotes:WaitForChild("Breath") :: RemoteEvent
	local fx = remotes:WaitForChild("CombatFx") :: RemoteEvent
	fx.OnClientEvent:Connect(function(p)
		local ok, err = pcall(onFx, p)
		if not ok then
			warn("[Combat] fx: " .. tostring(err))
		end
	end)
	buildGui()
	setAuto(false)
	me:GetAttributeChangedSignal("AutoBreath"):Connect(function()
		if me:GetAttribute("AutoBreath") ~= true then
			setAuto(false)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F then
			tryBreath(true)
		end
	end)
	local cam = workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(layout)
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		-- Gloom near - only the fight on screen; leaves later, after ui.focusHold s (no flicker at the edge).
		-- Own pcall (silent-failure-hunter): an error in the rest of the tick logic does not leave the HUD hidden until the end of the session
		focusAcc += 1
		if hud and hud.setFocus and focusAcc >= 2 then
			focusAcc = 0
			local okF, errF = pcall(function()
				local r = myRoot()
				if r and hasCompanion() then
					for _, m in CollectionService:GetTagged("Gloom") do -- only own Gloom (foreign Gloom does not hide my plaques)
						if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and (m:GetPivot().Position - r.Position).Magnitude < C.ui.focusRange then
							nearAt = os.clock()
							break
						end
					end
				end
			end)
			if not okF then
				warn("[Combat] focus: " .. tostring(errF))
				nearAt = -math.huge -- unknown whether Gloom is near - better bring the screen back
			end
			pcall(function()
				local r = myRoot()
				if r then
					for _, m in CollectionService:GetTagged("GloomChase") do
						-- only an awake pack (Awake) - a sleeping one by the nest does not start the combat music
						if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Awake") == true
							and (m:GetPivot().Position - r.Position).Magnitude < C.ui.focusRange then
							chaseAt = os.clock()
							break
						end
					end
				end
			end)
			local fight = os.clock() - nearAt < C.ui.focusHold
			-- a glowing egg in hand or a chase Gloom near - chase focus (the "run home" step and the arrow stay)
			local eggs = Store.get("eggs")
			local carryGlow = typeof(eggs) == "table" and typeof(eggs.carry) == "table" and eggs.carry.glow == true
			-- and the whole raid (GlowWait - the dragon waits at the gate): Keeper, cards, labels hidden
			-- the shared ring-0 nests stand by the plaza - the waiting zone itself (GlowWait) does not switch the focus on, only an egg in hand and a chase
			local carryRaid = typeof(eggs) == "table" and typeof(eggs.carry) == "table" and eggs.carry.raid ~= nil
			local chasing = carryGlow or carryRaid or os.clock() - chaseAt < 1.5
			pcall(hud.setFocus, fight or chasing, chasing and not fight)
			-- Sounds plays the combat track while the (local) Fight attribute is on; it holds for musicHold s after the fight -
			-- no back-and-forth between hunt waves; after a cleared wave (clearAt) no hold - the victory phrase closes the fight
			local wantFight = (os.clock() - nearAt < C.ui.musicHold and nearAt > clearAt + 1) or os.clock() < incomingUntil
				or os.clock() - chaseAt < 1.5 -- chase: music while the Gloom is near, and it fades at once (home / fell behind)
			if (me:GetAttribute("Fight") == true) ~= wantFight then
				me:SetAttribute("Fight", if wantFight then true else nil)
			end
			-- the escape has its own music (Sounds: chase outranks fight) while the egg is in hand or the guardian chases
			if (me:GetAttribute("Chase") == true) ~= chasing then
				me:SetAttribute("Chase", if chasing then true else nil)
			end
			-- closeness 0..1 to the own egg that
			-- can be stolen (the FirstNest raid nest with an egg if raids remain today; the own golden nest with an egg) within Music.chaseNear.r
			local near = 0
			local CN = (Content :: any).Music and (Content :: any).Music.chaseNear
			local rr = myRoot()
			if CN and rr and not chasing then
				local firstId = me:GetAttribute("FirstNest")
				local left = me:GetAttribute("RaidLeft")
				if left == nil or (tonumber(left) or 0) > 0 then
					for _, m in CollectionService:GetTagged("RaidNest") do
						if m:IsA("Model") and m.PrimaryPart and m:GetAttribute("HasEgg") == true and (firstId == nil or m:GetAttribute("NestId") == firstId) then
							near = math.max(near, 1 - (m.PrimaryPart.Position - rr.Position).Magnitude / CN.r)
						end
					end
				end
				local gf = workspace:FindFirstChild("GlowEggs")
				local gm = gf and gf:FindFirstChild("GlowEgg_" .. me.UserId)
				if gm and gm:IsA("Model") and not gm:GetAttribute("Empty") then
					near = math.max(near, 1 - (gm:GetPivot().Position - rr.Position).Magnitude / CN.r)
				end
			end
			near = math.clamp(math.floor(near * 20 + 0.5) / 20, 0, 1)
			if ((me:GetAttribute("ChaseNear") :: number?) or 0) ~= near then
				me:SetAttribute("ChaseNear", if near > 0 then near else nil)
			end
		end
		local ok, err = pcall(function()
			refreshButton()
			refreshBar()
			if not keeperShown and me:GetAttribute("Gloom_meadow") ~= nil and hasCompanion() then
				local c = Store.get("combat")
				if typeof(c) ~= "table" or (tonumber(c.stage) or 0) == 0 then
					keeperShown = true
					Banners.toast("Old Ash: " .. Loc.fill(S.keeper, {}, nil, ""))
				end
			end
			if autoOn and btn and btn.Visible then
				tryBreath(false)
			end
		end)
		if not ok then
			warn("[Combat] tick: " .. tostring(err))
		end
	end)
	task.spawn(function()
		while gui and gui.Parent do
			task.wait(1)
			pcall(layout) -- the Roblox jump button appears and moves later (device change, rotation)
		end
	end)
end

return Combat
