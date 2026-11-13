--!strict
-- The hatch scene (02 §2 0:10-0:13, 03 §2). Look and timings - Core/HatchFx + Config.UI.hatchScene.
-- full (~2.9 s, the first hatches and Rare+): the HUD hides, the camera moves in on the bowl from the side, the background is blurred (depth of field, not Blur:
-- Blur would blur the egg itself); the egg copy rocks with growing
-- amplitude, the core lights up, two "knocks"; the crack: a flash, sparks in the element color, the shell flies apart, a sound; the hatchling grows from
-- a point (easeOutBack 0.7 s), the camera goes back. short (1.5 s, Common/Uncommon after the first ones): the same without the camera, blur and HUD hiding.
-- Legendary+: from the crack ~5 s more of element sky and light (ColorCorrection, a light pillar) and confetti - the controls are already with the player;
-- Mythic - the egg rises, the sky and the light for everyone on the server (Notice hatchFx). The server holds the egg in the bowl for holdSeconds (HatchingEgg):
-- the copy is removed at once, the original is hidden locally. The result ("Common Ember", "1 in N") is shown by Banners at bannerAt.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local HatchFx = require(Shared:WaitForChild("Core"):WaitForChild("HatchFx"))
local Voices = require(Shared:WaitForChild("Core"):WaitForChild("Voices"))
local Eggs = require(Shared:WaitForChild("Core"):WaitForChild("Eggs")) -- the rarity order for the name window

local Net = require(script.Parent:WaitForChild("Net"))
local Store = require(script.Parent:WaitForChild("Store"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local NameDialog = require(script.Parent:WaitForChild("NameDialog"))
local UIStack = require(script.Parent:WaitForChild("UIStack")) -- the name window not over an open menu
local UIKit = require(script.Parent:WaitForChild("UIKit")) -- worldUiHidden for UiBusy after the scene

local HatchScene = {}

local HS = Config.UI.hatchScene
local me = Players.LocalPlayer
local rng = Random.new()
local busy = false
local WHITE = Color3.new(1, 1, 1)

-- a hatch scene is playing - "tomorrow" (Gifts) and the opt-in prompt wait for its end
function HatchScene.busy(): boolean
	return busy
end

local function title(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function elementColor(element: any): Color3
	local el = Content.Elements[element]
	return if el then Color3.fromRGB(el.color[1], el.color[2], el.color[3]) else WHITE
end

-- besides the HUD and the step banner we hide the quest panel, the top bar and the world timers; restore what was on
local HIDE_GUIS = { "HUD", "StepBanner", "Quests", "Topbar", "WorldTimers" }
local hudWas: { [ScreenGui]: boolean } = {}
local function setHud(on: boolean)
	-- the scene hides the HUD by itself, the server did not see it - a Gloom wave ran at the player in the middle of the cinematic
	-- (the day-2 dragon of a returning player); UiBusy as in HUD.setVisible, after the scene - the actual menu state
	local rf = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	local busy = rf and rf:FindFirstChild("UiBusy")
	if busy and busy:IsA("RemoteEvent") then
		busy:FireServer(if on then UIKit.worldUiHidden else true)
	end
	local pg = me:FindFirstChild("PlayerGui")
	if not on then
		for _, name in HIDE_GUIS do
			local g = pg and pg:FindFirstChild(name)
			if g and g:IsA("ScreenGui") then
				hudWas[g] = g.Enabled
				g.Enabled = false
			end
		end
	else
		for g, was in hudWas do
			if g.Parent then
				g.Enabled = was
			end
		end
		table.clear(hudWas)
	end
end

local function hideLocal(inst: Instance, hidden: boolean)
	for _, part in inst:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function fxPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	if props.Shape then -- the shape before the size: changing Shape adjusts Size
		p.Shape = props.Shape
	end
	for k, v in props do
		if k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	p.Parent = workspace
	return p
end

-- the hatchling from a point: scale 0.05 -> 1 with a bounce
local function popIn(m: Model)
	local base = m:GetScale()
	local v = Instance.new("NumberValue")
	v.Value = 0.05
	m:ScaleTo(base * 0.05)
	local conn = v.Changed:Connect(function(x)
		if m.Parent then
			m:ScaleTo(base * math.max(0.05, x))
		end
	end)
	local tw = TweenService:Create(v, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
	tw:Play()
	tw.Completed:Wait()
	conn:Disconnect()
	if m.Parent then
		m:ScaleTo(base)
	end
	v:Destroy()
end

local function flash(at: Vector3, color: Color3, size: number)
	local p = fxPart({ Shape = Enum.PartType.Ball, Material = Enum.Material.Neon, Color = color, Size = Vector3.one, Position = at, Transparency = HS.flash.transparency })
	TweenService:Create(p, TweenInfo.new(HS.flash.seconds), { Size = Vector3.one * size, Transparency = 1 }):Play()
	task.delay(HS.flash.seconds + 0.1, function()
		p:Destroy()
	end)
end

-- element sparks: one burst of particles from the egg center
local function sparks(at: Vector3, color: Color3, n: number)
	local holder = fxPart({ Size = Vector3.one, Position = at, Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(color:Lerp(WHITE, 0.55), color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	pe.Speed = NumberRange.new(10, 20)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Drag = 4
	pe.Acceleration = Vector3.new(0, -12, 0)
	pe.Rate = 0
	pe.Enabled = false
	pe.Parent = holder
	pe:Emit(n)
	task.delay(1.6, function()
		holder:Destroy()
	end)
end

-- pieces flying in an arc: one loop per frame for all (shell, confetti)
type Bit = { part: BasePart, pos: Vector3, vel: Vector3, rot: CFrame, spin: Vector3, t0: number, life: number, base: number }
local function fly(bits: { Bit }, gravity: number, fall: number?, drag: number)
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local alive = 0
		for _, b in bits do
			if not b.part.Parent then
				continue
			end
			local age = now - b.t0
			if age >= b.life then
				b.part:Destroy()
				continue
			end
			alive += 1
			local v = b.vel - Vector3.new(0, gravity * dt, 0)
			v = Vector3.new(v.X * (1 - math.min(1, drag * dt)), if fall then math.max(v.Y, -fall) else v.Y, v.Z * (1 - math.min(1, drag * dt)))
			b.vel = v
			b.pos += v * dt
			b.rot = b.rot * CFrame.Angles(b.spin.X * dt, b.spin.Y * dt, b.spin.Z * dt)
			b.part.CFrame = CFrame.new(b.pos) * b.rot
			local k = age / b.life
			if k > 0.6 then
				b.part.Transparency = b.base + (1 - b.base) * (k - 0.6) / 0.4
			end
		end
		if alive == 0 and conn then
			conn:Disconnect()
		end
	end)
end

-- the shell: thin wedges from the egg surface outward and up
local function shards(center: Vector3, size: Vector3, color: Color3)
	local S = HS.shards
	local tone = color:Lerp(WHITE, 0.35)
	local bits: { Bit } = {}
	local now = os.clock()
	for _ = 1, S.count do
		local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.1, 1), rng:NextNumber(-1, 1)).Unit
		local s = rng:NextNumber(S.size[1], S.size[2])
		local pos = center + Vector3.new(d.X * size.X / 2, d.Y * size.Y / 2, d.Z * size.Z / 2)
		local rot = CFrame.lookAt(Vector3.zero, d) * CFrame.Angles(0, 0, rng:NextNumber(0, math.pi * 2))
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Material = Enum.Material.Glass
		w.Color = tone
		w.Transparency = 0.15
		w.Size = Vector3.new(0.1, s, s * 0.8)
		w.CFrame = CFrame.new(pos) * rot
		w.Parent = workspace
		table.insert(bits, { part = w, pos = pos, vel = d * rng:NextNumber(S.speed[1], S.speed[2]) + Vector3.new(0, S.up, 0), rot = rot,
			spin = Vector3.new(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), rng:NextNumber(-9, 9)), t0 = now, life = S.seconds, base = 0.15 })
	end
	fly(bits, S.gravity, nil, 0)
end

-- Legendary+ confetti: the colors of the game's elements, a fan launch and a slow spinning fall
local function confetti(at: Vector3)
	local C = HS.legend.confetti
	local cols: { Color3 } = {}
	for _, el in Content.Elements do
		table.insert(cols, Color3.fromRGB(el.color[1], el.color[2], el.color[3]))
	end
	if #cols == 0 then
		cols = { WHITE }
	end
	local bits: { Bit } = {}
	local now = os.clock()
	for i = 1, C.count do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = Vector3.new(math.cos(a) * C.spread, 1, math.sin(a) * C.spread).Unit
		local p = fxPart({ Material = Enum.Material.Neon, Color = cols[(i % #cols) + 1], Size = Vector3.new(C.size[1], C.size[2], C.size[3]), Position = at })
		local rot = CFrame.Angles(rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3), rng:NextNumber(0, 6.3))
		table.insert(bits, { part = p, pos = at, vel = d * rng:NextNumber(C.speed[1], C.speed[2]), rot = rot,
			spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-4, 4), rng:NextNumber(-8, 8)), t0 = now, life = C.seconds * rng:NextNumber(0.8, 1), base = 0 })
	end
	fly(bits, 30, C.fall, 1.2)
end

-- Legendary+ (03 §2): element sky and light for seconds s, a light pillar above the bowl, confetti; does not touch the camera or the HUD
local function legendFx(at: Vector3, color: Color3)
	local L = HS.legend
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "HatchLegend"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.8), { TintColor = WHITE:Lerp(color, L.tint), Brightness = L.brightness, Saturation = L.saturation }):Play()
	local P = L.pillar
	local pil = fxPart({ Name = "HatchPillar", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon, Color = color, Transparency = 1,
		Size = Vector3.new(P.height, P.width, P.width), CFrame = CFrame.new(at + Vector3.new(0, P.above + P.height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	TweenService:Create(pil, TweenInfo.new(0.6), { Transparency = P.transparency }):Play()
	confetti(at + Vector3.new(0, 3, 0))
	task.delay(L.seconds - L.fade, function()
		TweenService:Create(cc, TweenInfo.new(L.fade), { TintColor = WHITE, Brightness = 0, Saturation = 0 }):Play()
		TweenService:Create(pil, TweenInfo.new(L.fade), { Transparency = 1 }):Play()
		task.delay(L.fade + 0.1, function()
			cc:Destroy()
			pil:Destroy()
		end)
	end)
end

-- the egg copy from the bowl (the server holds the original HatchingEgg for holdSeconds); the original is hidden locally
local function eggCopy(src: any): Model?
	if typeof(src) ~= "Instance" or not src:IsA("Model") or not src.Parent then
		return nil
	end
	local ok, m = pcall(function()
		return src:Clone()
	end)
	if not ok or not m then
		return nil
	end
	hideLocal(src, true)
	m.Name = "HatchEggLocal"
	m.Parent = workspace
	return m
end

-- rocking around the base with growing amplitude, the core lights up; Mythic - the egg rises
local function shakeEgg(egg: Model, plan: HatchFx.Plan, t0: number, color: Color3)
	local cf, size = egg:GetBoundingBox()
	local bottom = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
	local off = bottom:ToObjectSpace(egg:GetPivot())
	local core = egg:FindFirstChild("Core", true)
	local corePart: BasePart? = if core and core:IsA("BasePart") then core else nil
	local core0 = if corePart then corePart.Transparency else 0
	local coreSize = if corePart then corePart.Size else Vector3.one
	local light: PointLight? = nil
	if corePart then
		local l = Instance.new("PointLight")
		l.Color = color
		l.Brightness = 0
		l.Range = HS.core.range
		l.Shadows = false
		l.Parent = corePart
		light = l
	end
	local a, b = plan.t.shakeFrom, plan.t.crackAt
	local beats = { a + (b - a) * 0.55, a + (b - a) * 0.85 } -- two "knocks" before the crack
	local beat = 1
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if not egg.Parent or t >= b then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local deg = HatchFx.shakeDeg(plan, t, HS.shake)
		local ph = math.max(0, t - a) * HS.shake.hz * 2 * math.pi
		local k = math.clamp((t - a) / math.max(b - a, 0.01), 0, 1)
		local lift = if plan.mythic then HS.mythicLift * k else 0
		egg:PivotTo(bottom * CFrame.new(0, lift, 0) * CFrame.Angles(math.rad(deg * 0.35 * math.sin(ph * 0.7)), 0, math.rad(deg * math.sin(ph))) * off)
		if corePart then
			corePart.Transparency = core0 + (HS.core.transparency - core0) * k
			corePart.Size = coreSize * (1 + (HS.core.grow - 1) * k)
		end
		if light then
			light.Brightness = HS.core.light * k
		end
		if beat <= #beats and t >= beats[beat] then
			beat += 1
			Sounds.play("egg_crack", { volume = 0.6 })
		end
	end)
end

-- the hatchling models (the copy in the nest and/or the companion) are hidden locally from their appearance until the bounce: the server builds them after the
-- hatch event (otherwise the hatchling stands in the bowl next to the rocking egg; the label "Ember / Legendary" above it gave the rarity away before
-- the crack). Parts - LocalTransparencyModifier; the label, particles and light - Enabled (like DragonLife.setHidden). seen - all found,
-- main - for the bounce (the nest matters more), was - what was on
local function hideWatch(uid: string)
	local w = { seen = {} :: { Model }, main = nil :: Model?, conns = {} :: { RBXScriptConnection }, was = {} :: { [Instance]: boolean } }
	local function hideOne(d: Instance)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			if w.was[d] == nil then
				w.was[d] = (d :: any).Enabled
			end
			;(d :: any).Enabled = false
		end
	end
	local function take(m: Model)
		if table.find(w.seen, m) then
			return
		end
		table.insert(w.seen, m)
		for _, d in m:GetDescendants() do
			hideOne(d)
		end
		table.insert(w.conns, m.DescendantAdded:Connect(hideOne))
		if not w.main or (w.main:GetAttribute("Companion") == true and m:GetAttribute("Companion") ~= true) then
			w.main = m
		end
	end
	for _, m in workspace:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Uid") == uid and m:GetAttribute("OwnerId") == me.UserId then
			take(m)
		end
	end
	table.insert(w.conns, workspace.DescendantAdded:Connect(function(d)
		if d:IsA("Model") and d:GetAttribute("Uid") == uid and d:GetAttribute("OwnerId") == me.UserId then
			take(d)
		end
	end))
	return w
end

-- the distance from a point to the segment a-b
local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = b - a
	local k = math.clamp((p - a):Dot(ab) / math.max(ab:Dot(ab), 1e-6), 0, 1)
	return (a + ab * k - p).Magnitude
end

-- the angle of the full scene (HS.camera.angles - degrees from the line bowl -> player): the first where the ray from the egg is clear (the table, neighboring bowls,
-- decor with CanQuery) and the character is no closer than clear to the line camera -> egg; base - the direction to the player (without a character - to the camera)
local function closeUp(at: Vector3, from: CFrame, exclude: { Instance }): (CFrame, number)
	local K = HS.camera
	local ch = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local rootPos: Vector3? = if root and root:IsA("BasePart") then root.Position else nil
	local toward = if rootPos then rootPos else from.Position
	local base = Vector3.new(toward.X - at.X, 0, toward.Z - at.Z)
	base = if base.Magnitude > 0.1 then base.Unit else Vector3.new(0, 0, 1)
	local target = at + Vector3.new(0, K.lookUp, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclude
	for _, a in K.angles do
		local pos = at + CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(base) * K.distance + Vector3.new(0, K.height, 0)
		local clearOfMe = rootPos == nil or segDist(rootPos, pos, target) >= K.clear
		if clearOfMe and not workspace:Raycast(target, pos - target, params) then
			return CFrame.lookAt(pos, target), (pos - target).Magnitude
		end
	end
	local pos = at + base * K.distance * 0.5 + Vector3.new(0, K.distance, 0) -- everything is blocked: from above
	return CFrame.lookAt(pos, target), (pos - target).Magnitude
end

-- a move-in along an arc around the bowl to the goal angle: a straight tween from behind the player's back to the other side of the bowl went through the character and the ground
-- . The radius no less than camera.distance, the height no lower than camera.height, the look on the egg all the time
local function orbitTo(cam: Camera, at: Vector3, goal: CFrame, seconds: number)
	local K = HS.camera
	local target = at + Vector3.new(0, K.lookUp, 0)
	local function polar(p: Vector3): (number, number, number)
		local d = Vector3.new(p.X - at.X, 0, p.Z - at.Z)
		return math.atan2(d.Z, d.X), d.Magnitude, p.Y - at.Y
	end
	local a0, r0, h0 = polar(cam.CFrame.Position)
	local a1, r1, h1 = polar(goal.Position)
	local da = (a1 - a0 + math.pi) % (2 * math.pi) - math.pi -- the shortest turn
	r0 = math.max(r0, K.distance)
	h0 = math.max(h0, K.height)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = 1 - (1 - k) * (1 - k)
		local a = a0 + da * e
		local r = r0 + (r1 - r0) * e
		cam.CFrame = CFrame.lookAt(at + Vector3.new(math.cos(a) * r, h0 + (h1 - h0) * e, math.sin(a) * r), target)
		if k >= 1 and conn then
			conn:Disconnect()
		end
	end)
end

local function play(p: any)
	local t0 = os.clock()
	local plan = HatchFx.plan(tostring(p.rarity), if typeof(p.n) == "number" then p.n else nil, HS, busy)
	local cine = plan.kind == "full"
	local function untilT(t: number)
		local d = t0 + t - os.clock()
		if d > 0 then
			task.wait(d)
		end
	end
	local cam = workspace.CurrentCamera
	local at: Vector3? = if typeof(p.at) == "Vector3" then p.at else nil
	local color = elementColor(p.element)
	if cine then
		busy = true
		setHud(false)
	end
	local egg = eggCopy(p.egg)
	if egg then
		shakeEgg(egg, plan, t0, color)
	end
	-- a sound by rarity (Content.Sounds hatch_<rarity>); Mythic - from the shake, its rise falls on the egg's ascent
	local rarity = tostring(p.rarity)
	local early = Voices.hatchStartsEarly(rarity)
	if early then
		task.delay(math.max(0, t0 + plan.t.shakeFrom - os.clock()), Sounds.hatch, rarity)
	end
	local watch = if typeof(p.uid) == "string" then hideWatch(p.uid) else nil
	local dof: DepthOfFieldEffect? = nil
	local oldType = cam.CameraType
	if cine then
		if at then
			local exclude: { Instance } = {}
			for _, x in { egg, p.egg, if typeof(p.egg) == "Instance" then p.egg.Parent else nil } do
				if typeof(x) == "Instance" then
					table.insert(exclude, x)
				end
			end
			local goal, focus = closeUp(at, cam.CFrame, exclude)
			cam.CameraType = Enum.CameraType.Scriptable
			orbitTo(cam, at, goal, plan.t.camIn)
			local D = HS.dof
			local e = Instance.new("DepthOfFieldEffect")
			e.Name = "HatchFocus"
			e.FocusDistance = focus
			e.InFocusRadius = D.radius
			e.FarIntensity = 0
			e.NearIntensity = 0
			e.Parent = Lighting
			TweenService:Create(e, TweenInfo.new(0.4), { FarIntensity = D.far, NearIntensity = D.near }):Play()
			dof = e
		end
	end
	untilT(plan.t.crackAt)
	-- the crack: a flash, sparks, the shell, a sound
	local center: Vector3? = if at then at + Vector3.new(0, 1.2, 0) else nil
	if egg and egg.Parent then
		local cf, size = egg:GetBoundingBox()
		center = cf.Position
		shards(cf.Position, size, color)
		egg:Destroy()
	end
	local m = watch and watch.main
	if not center and m then -- a gift outside the bowl (calendar): the sparks at the hatchling itself
		center = m:GetPivot().Position
	end
	if center then
		flash(center, color, if cine then HS.flash.full else HS.flash.short)
		sparks(center, color, if cine then HS.sparks.full else HS.sparks.short)
		if plan.legend then
			task.spawn(legendFx, center - Vector3.new(0, 1.2, 0), color)
		end
	end
	if not early then
		Sounds.hatch(rarity) -- Legendary: the fanfare is its own step
	end
	untilT(plan.t.popAt)
	if watch then
		for _, c in watch.conns do
			c:Disconnect()
		end
		for _, x in watch.seen do
			hideLocal(x, false)
		end
		for d, on in watch.was do
			if d.Parent then
				(d :: any).Enabled = on
			end
		end
		if watch.main then
			task.spawn(popIn, watch.main)
		end
	end
	-- the hatchling's first squeak at the bounce - from its body (3D); no model (a gift outside the nest) - 2D
	local baby = watch and watch.main
	task.delay(((Content :: any).Voices or {}).birthDelay or 0.15, Sounds.voice, 0, "birth", baby and baby.PrimaryPart)
	if cine then
		untilT(plan.t.camOutAt)
		if dof then
			TweenService:Create(dof, TweenInfo.new(0.3), { FarIntensity = 0, NearIntensity = 0 }):Play()
		end
		cam.CameraType = oldType
		if oldType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Custom
		end
	end
	untilT(plan.total)
	if dof then
		dof:Destroy()
	end
	if cine then
		setHud(true)
		busy = false
	end
	-- the name window (02 §2, 0:13-0:18): after the scene, closes by itself after 5 s without input; for Legendary+ - when the celebration fades
	-- within the first minute after the previous name the window does not pop up (the Config.Names.renameCooldown limit), the hatchling keeps the element name
	-- the window only for the first two hatches and for Rare+ (Config.UI.nameDialog) - Common/Uncommon hatch
	-- most often, a 5-second window ate their short scene; the element name stays, renaming is possible in the card (Rename)
	local ND = Config.UI.nameDialog
	local askName = (tonumber(p.n) or 1) <= ND.firstHatches or Eggs.rarityIndex(tostring(p.rarity)) >= Eggs.rarityIndex(ND.minRarity)
	-- a menu is open - no name window (the element name stays, rename - Rename in the card): windows do not open over an open menu
	if askName and UIStack.depth() > 0 then
		askName = false
	end
	if askName and p.where == "nest" and typeof(p.uid) == "string" and not p.named and NameDialog.cooldownLeft() <= 0 then -- named: a gift with a ready name (Solstice)
		if plan.legend then
			untilT(plan.fxEnd - HS.legend.fade)
		end
		local dragons = Store.get("dragons")
		local rec = typeof(dragons) == "table" and dragons[p.uid]
		NameDialog.open(p.uid, if rec and rec.name then rec.name else title(tostring(p.element)), { auto = Config.UI.nameDialog.autoCloseSeconds })
	end
end

function HatchScene.start()
	Net.on("hatch", function(p)
		task.spawn(play, p)
	end)
	-- a Mythic of another player (03 §2 "a scene for the whole server"): element sky and light, the pillar and confetti above their bowl
	Net.on("hatchFx", function(p)
		if p.ownerId == me.UserId or typeof(p.at) ~= "Vector3" then
			return
		end
		task.spawn(legendFx, p.at + Vector3.new(0, 0.5, 0), elementColor(p.element))
		Sounds.hatch(if typeof(p.rarity) == "string" then p.rarity else "Mythic", { volume = 0.5 })
	end)
	RunService.Heartbeat:Wait()
end

return HatchScene
