--!strict
-- Riding and flight (1.9; 04 §5-5.1, 02 §2 2:30-8:00, 02 §4; craft/04 §4 P1). The server (Services/Movement) seats the player in the Seat and gives
-- the rider network ownership; the physics is computed by this controller: LinearVelocity + AlignOrientation on the dragon's body.
-- On the ground: joystick/WASD -> the teen's speed (Config.Dragon.stages[2].speed), hovering at hoverClearance above the ground by a ray
-- downward (slopes, stairs). Adult and older: hold Jump (Space / the jump button / the Up button) for takeoffHold s - takeoff;
-- in the air Jump - up, Down (LeftShift / C / the Down button) - down, vertical = base x verticalMult, the ceiling flight.ceiling.
-- Dive: the nose below the horizon by dive.pitchDeg -> a boost of dive.accel/s up to base x maxMult, otherwise it decays over decaySeconds.
-- Camera: CameraOffset flight.cameraOffset, zoom-out flight.maxZoom, field of view fov.base -> fov.max by the boost, shake
-- shakeAmplitude (8 Hz) above shakeAbove, fades over 0.3 s. Landing: ground closer than landProbe under the belly while descending or
-- moving slowly - a puff of ground-colored dust (landingDust particles) and a sound. Buttons (02 §4): Dismount always when mounted, Up / Down
-- in flight on phone and gamepad, 70 / 120 px, right of the jump button. Wind rings: Notice ring -> a ring flash and a sound;
-- Fly.nextRing - the nearest unpassed ring along the route (for the arrow chain in the air, Hints).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Fly = {}

local D = Config.Dragon
local FL = D.flight
local RD = D.ride
local RINGS = Config.World.windRings
local MOB = Config.UI.mobile
local me = Players.LocalPlayer
local banners: any = nil
local bones: any = nil -- DragonBones (the flap phase for the rider's swaying)

type State = {
	uid: string, model: Model, body: BasePart, seat: BasePart, hum: Humanoid, size: Vector3, stage: number, base: number, ground: number,
	canFly: boolean, mode: string, vh: Vector3, vy: number, boost: number, takeoff: number, lv: LinearVelocity, ao: AlignOrientation,
	att: Attachment, prevZoom: number, prevMinZoom: number, shake: number, yaw: Vector3, told: boolean, stuck: number, spray: ParticleEmitter?,
	roll: number, pose: { [Instance]: CFrame }, poseT: { [Instance]: CFrame }, queryOff: { BasePart }, leanK: number, edgeToldAt: number?, youngToldAt: number?,
}
local st: State? = nil
local held = { up = false, down = false }
local autoLand = false -- Dismount in flight - land first (the server answers in_air), dismount on the ground (downHeld/land)
local gui: ScreenGui? = nil
local btnUp: TextButton? = nil
local btnDown: TextButton? = nil
local btnOff: TextButton? = nil
local passed: { [number]: number } = {}
local toldTakeOff = false
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function humanoid(): Humanoid?
	local ch = me.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	return if h and h.Health > 0 then h else nil
end

local function moveTowards(v: Vector3, target: Vector3, maxDelta: number): Vector3
	local d = target - v
	local m = d.Magnitude
	if m <= maxDelta or m < 1e-4 then
		return target
	end
	return v + d / m * maxDelta
end

-- the clearance under the lowest point of the rotated bounding box (in a dive the nose drops below the "belly" by size.Z/2 x sin(pitch) - the first
-- the body hit the ground while the ray from the center gave 4.5 studs and the landing never came)
local function groundBelow(s: State): (number?, RaycastResult?)
	local cf, size = s.model:GetBoundingBox()
	local h = size / 2
	local drop = math.abs(cf.UpVector.Y) * h.Y + math.abs(cf.LookVector.Y) * h.Z + math.abs(cf.RightVector.Y) * h.X
	local bottom = cf.Position.Y - drop
	params.FilterDescendantsInstances = { me.Character :: Instance, s.model }
	local hit = workspace:Raycast(cf.Position, Vector3.new(0, -(drop + 120), 0), params)
	if not hit then
		return nil, nil
	end
	return bottom - hit.Position.Y, hit
end

-- ---------------------------------------------------------------------------------------------- input
local function gamepadDown(k: Enum.KeyCode): boolean
	for _, g in UserInputService:GetConnectedGamepads() do
		if UserInputService:IsGamepadButtonDown(g, k) then
			return true
		end
	end
	return false
end

local function upHeld(s: State): boolean
	return held.up or s.hum.Jump or UserInputService:IsKeyDown(Enum.KeyCode.Space) or gamepadDown(Enum.KeyCode.ButtonA) or (gui ~= nil and gui:GetAttribute("Up") == true)
end

local function downHeld(): boolean
	return autoLand or held.down or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.C) or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or gamepadDown(Enum.KeyCode.ButtonB) or (gui ~= nil and gui:GetAttribute("Down") == true)
end

local function moveDir(s: State): Vector3
	local m = s.hum.MoveDirection
	local forced = gui and gui:GetAttribute("Move")
	if m.Magnitude < 0.1 and typeof(forced) == "Vector3" and forced.Magnitude > 0.1 then
		m = forced.Unit
	end
	return Vector3.new(m.X, 0, m.Z)
end

-- ---------------------------------------------------------------------------------------------- buttons
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

local function layoutButtons()
	local g, up, down, off = gui, btnUp, btnDown, btnOff
	if not g or not up or not down or not off then
		return
	end
	local s = buttonSize()
	local gap = MOB.gap
	local jb = jumpButton()
	for _, b in { up, down, off } do
		b.Size = UDim2.fromOffset(s, s * 0.62)
		b.AnchorPoint = Vector2.new(0, 0)
	end
	if jb then
		local x, y = jb.AbsolutePosition.X, jb.AbsolutePosition.Y
		local w, h = jb.AbsoluteSize.X, jb.AbsoluteSize.Y
		up.Position = UDim2.fromOffset(x + (w - s) / 2, y - gap - s * 0.62)
		down.Position = UDim2.fromOffset(x - gap - s, y - gap - s * 0.62)
		off.Position = UDim2.fromOffset(x - gap - s, y + (h - s * 0.62) / 2)
	else
		local cam = workspace.CurrentCamera
		local v = if cam then cam.ViewportSize else Vector2.new(800, 600)
		off.Position = UDim2.fromOffset(v.X - 16 - s, v.Y - 110 - s * 0.62)
		up.Position = UDim2.fromOffset(v.X - 16 - s, v.Y - 110 - 2 * s * 0.62 - gap)
		down.Position = UDim2.fromOffset(v.X - 16 - 2 * s - gap, v.Y - 110 - 2 * s * 0.62 - gap)
	end
end

local function holdable(b: TextButton, key: string)
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held[key] = true
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			held[key] = false
		end
	end)
	b.MouseLeave:Connect(function()
		held[key] = false
	end)
end

-- over the sea the server refuses (over_water) - a hint; the other refusals are silent (already etc.)
local function tryDismount()
	local r = Net.call("Dismount")
	if not r.ok and r.reason == "over_water" and banners then
		banners.toast(Strings.Hints.overWater)
	elseif not r.ok and r.reason == "in_air" then
		autoLand = true
	end
end

local function buildGui()
	local g = UIKit.screen("Movement", 3)
	g.Enabled = false
	gui = g
	local blue = Color3.fromRGB(52, 88, 160)
	local up = UIKit.button(g, Strings.Hints.up, blue, function() end, { minSize = Vector2.new(44, 30) })
	up.Name = "Up"
	holdable(up, "up")
	local down = UIKit.button(g, Strings.Hints.down, blue, function() end, { minSize = Vector2.new(44, 30) })
	down.Name = "Down"
	holdable(down, "down")
	local off = UIKit.button(g, Strings.Hints.dismount, Color3.fromRGB(200, 90, 60), function()
		tryDismount()
	end, { minSize = Vector2.new(44, 30) })
	off.Name = "Dismount"
	btnUp, btnDown, btnOff = up, down, off
	layoutButtons()
end

-- :
-- the card mounts (Mount) before UIStack.close while the HUD is hidden; HUD.setVisible remembered HudWasEnabled=false (not mounted back then) and on
-- closing it switched Movement off over the mount. While the HUD is hidden we write the desired state into HudWasEnabled - the HUD restores it when the menu closes.
local function setGuiOn(g: ScreenGui, on: boolean)
	if g:GetAttribute("HudWasEnabled") ~= nil then
		g:SetAttribute("HudWasEnabled", on)
		g.Enabled = false
	else
		g.Enabled = on
	end
end

local function showButtons(s: State?)
	local g = gui
	if not g then
		return
	end
	if not s then
		setGuiOn(g, false)
		return
	end
	local kind = me:GetAttribute("InputKind")
	local touch = kind == "touch" or kind == "gamepad"
	if btnUp then
		btnUp.Visible = s.canFly and touch
	end
	if btnDown then
		btnDown.Visible = s.canFly and touch and s.mode == "air"
	end
	if btnOff then
		btnOff.Visible = true
	end
	layoutButtons()
	setGuiOn(g, true)
end

-- ---------------------------------------------------------------------------------------------- camera
local function cameraStep()
	local s = st
	local cam = workspace.CurrentCamera
	if not s or not cam then
		return
	end
	local maxBoost = s.base * (FL.dive.maxMult - 1)
	local k = if maxBoost > 0 then math.clamp(s.boost / maxBoost, 0, 1) else 0
	local fovT = FL.fov.base + (FL.fov.max - FL.fov.base) * k
	cam.FieldOfView += (fovT - cam.FieldOfView) * 0.12
	local speed = s.vh.Magnitude
	if speed > FL.shakeAbove then
		s.shake = FL.shakeAmplitude
	else
		s.shake = math.max(0, s.shake - FL.shakeAmplitude / 0.3 / 60)
	end
	if s.shake > 0.001 then
		local t = os.clock() * 8 * math.pi * 2
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad(s.shake * math.sin(t)), math.rad(s.shake * math.sin(t + 1.3)), 0)
	end
end

-- ---------------------------------------------------------------------------------------------- landing
local function dust(s: State, hit: RaycastResult)
	local color = if hit.Instance == workspace.Terrain then workspace.Terrain:GetMaterialColor(hit.Material) else (hit.Instance :: BasePart).Color
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 1, 1)
	p.CFrame = CFrame.new(hit.Position + Vector3.new(0, 0.5, 0))
	p.Parent = workspace
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, s.size.Y * 0.12), NumberSequenceKeypoint.new(1, s.size.Y * 0.3) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(s.size.Y * 0.5, s.size.Y * 0.9)
	e.SpreadAngle = Vector2.new(85, 85)
	e.Rate = 0
	e.Parent = p
	e:Emit(FL.landingDust)
	task.delay(2, function()
		p:Destroy()
	end)
end

local function land(s: State, hit: RaycastResult?)
	s.mode = "ground"
	s.boost = 0
	s.vy = 0
	s.stuck = 0
	me:SetAttribute("Flying", nil)
	s.hum.CameraOffset = Vector3.new(0, s.size.Y * 0.2, 0)
	if hit then
		dust(s, hit)
	end
	Sounds.play("land")
	showButtons(s)
	if autoLand then -- the player asked to dismount in flight - landed, now dismount
		autoLand = false
		task.defer(function()
			local r = Net.call("Dismount")
			if not r.ok and r.reason == "over_water" and banners then
				banners.toast(Strings.Hints.overWater)
			end
		end)
	end
end

local function takeOff(s: State)
	s.mode = "air"
	s.takeoff = 0
	s.vy = s.base * FL.verticalMult
	me:SetAttribute("Flying", true)
	s.hum.CameraOffset = Vector3.new(0, FL.cameraOffset, 0)
	Sounds.play("wing")
	Sounds.voice(s.stage, "roar", s.body) -- a roar on takeoff (no more often than Content.Voices.roarCooldown, otherwise only the flap)
	if not s.told and banners then
		s.told = true
		banners.toast(Strings.Hints.flyControls)
	end
	showButtons(s)
end

-- ---------------------------------------------------------------------------------------------- physics
local function step(dt: number)
	local s = st
	if not s then
		return
	end
	local dir = moveDir(s)
	local up = upHeld(s)
	local down = downHeld()
	local clearance, hit = groundBelow(s)
	local cf = s.model:GetBoundingBox()
	local speedNow = s.vh.Magnitude
	if s.mode == "ground" then
		s.vh = moveTowards(s.vh, dir * s.ground, FL.accel * dt)
		if clearance then
			s.vy = math.clamp((RD.hoverClearance - clearance) * RD.hoverGain, -25, 25)
		else
			s.vy = -40
		end
		if s.canFly and up then
			s.takeoff += dt
			if s.takeoff >= FL.takeoffHold then
				takeOff(s)
			end
		else
			s.takeoff = 0
			-- a teen does not fly - explain why the jump does nothing
			if up and not s.canFly and banners and os.clock() - (s.youngToldAt or -100) > 12 then
				s.youngToldAt = os.clock()
				banners.toast(Strings.Hints.tooYoung)
			end
		end
		if s.vh.Magnitude > 1 then
			s.yaw = s.vh.Unit
		end
		s.roll = 0
		s.ao.CFrame = CFrame.lookAt(Vector3.zero, s.yaw)
	else
		local vin = (if up then 1 else 0) - (if down then 1 else 0)
		s.vy = vin * s.base * FL.verticalMult
		if cf.Position.Y >= FL.ceiling and s.vy > 0 then
			s.vy = 0
		end
		local pitch = math.clamp(math.deg(math.atan2(s.vy, math.max(speedNow, 1))), -FL.pitchMax, FL.pitchMax)
		local maxBoost = s.base * (FL.dive.maxMult - 1)
		if pitch < -FL.dive.pitchDeg and speedNow > 5 then
			s.boost = math.min(s.boost + FL.dive.accel * dt, maxBoost)
		else
			s.boost = math.max(0, s.boost - maxBoost / FL.dive.decaySeconds * dt)
		end
		s.vh = moveTowards(s.vh, dir * (s.base + s.boost), FL.accel * dt)
		if s.vh.Magnitude > 1 then
			s.yaw = s.vh.Unit
		elseif dir.Magnitude < 0.1 then
			local cam = workspace.CurrentCamera
			if cam then
				local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
				if look.Magnitude > 0.05 then
					s.yaw = look.Unit
				end
			end
		end
		-- bank in a turn: by the angle between the heading and the desired direction, fades on a straight line
		local LIFE = D.life
		local want = if dir.Magnitude > 0.1 then dir.Unit else s.yaw
		local cross = s.yaw:Cross(want).Y
		local targetRoll = -math.clamp(cross * LIFE.bankGain, -1, 1) * LIFE.bankDeg * math.min(speedNow / math.max(s.base, 1), 1)
		s.roll += (targetRoll - s.roll) * math.min(dt * 4, 1)
		s.ao.CFrame = CFrame.lookAt(Vector3.zero, s.yaw) * CFrame.Angles(math.rad(pitch), 0, math.rad(s.roll))
		-- "flap": light vertical swaying in flight while moving
		if speedNow > 5 and clearance and clearance > FL.landProbe * 2 then
			s.vy += LIFE.flapBob * math.cos(os.clock() * LIFE.flapHz * math.pi * 2) * math.min(speedNow / math.max(s.base, 1), 1)
		end
		if clearance and clearance < FL.landProbe and s.vy <= 0 and (down or speedNow < 8) then
			land(s, hit)
		elseif s.vy < -1 and s.body.AssemblyLinearVelocity.Y > -1 then
			-- asking for down while the body does not descend: we hit the ground or a rock - that is a landing too (after stuckSeconds)
			s.stuck += dt
			if s.stuck >= FL.stuckSeconds then
				land(s, hit)
			end
		else
			s.stuck = 0
		end
	end
	-- the soft world boundary (Config.World.bounds.warnAt/holdAt): a hint and damping of the outward speed
	do
		local B = Config.World.bounds
		local limit = Config.World.waterSize / 2 - B.margin
		local p = s.body.Position
		local r = math.max(math.abs(p.X), math.abs(p.Z))
		if r > limit * (B.warnAt or 0.9) then
			local now = os.clock()
			if now - (s.edgeToldAt or 0) > (B.warnEvery or 8) and banners then
				s.edgeToldAt = now
				banners.banner(Strings.Hints.turnBack, Color3.fromRGB(230, 120, 60), nil, 2.5)
			end
			if r > limit * (B.holdAt or 0.985) then
				local out = Vector3.new(if math.abs(p.X) >= math.abs(p.Z) then math.sign(p.X) else 0, 0, if math.abs(p.Z) > math.abs(p.X) then math.sign(p.Z) else 0)
				local k = s.vh:Dot(out)
				if k > 0 then
					s.vh -= out * k -- no flying outward, along the edge is fine
				end
			end
		end
	end
	s.lv.VectorVelocity = s.vh + Vector3.new(0, s.vy, 0)
	-- spray over the water: low over the water while moving - white foam on the surface under the dragon
	-- (an emitter on an anchored part at water level, particles up and sideways; the first run: an emitter on the body sprayed under water - invisible)
	local LIFE = D.life
	local overWater = hit ~= nil and hit.Material == Enum.Material.Water and clearance ~= nil and clearance < LIFE.sprayAbove and speedNow > 6
	if overWater and hit then
		local sp = s.spray
		if not sp then
			local part = Instance.new("Part")
			part.Name = "SprayAnchor"
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(s.size.X * 0.5, 0.2, s.size.Z * 0.4)
			part.Parent = workspace
			local e = Instance.new("ParticleEmitter")
			e.Name = "Spray"
			e.Texture = "rbxasset://textures/particles/smoke_main.dds"
			e.Color = ColorSequence.new(Color3.new(0.96, 0.98, 1))
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(0.4, 2.2), NumberSequenceKeypoint.new(1, 3) }) -- 2.5-7 gave a white cloud over the whole frame
			e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.5, 0.6), NumberSequenceKeypoint.new(1, 1) })
			e.Lifetime = NumberRange.new(0.35, 0.7)
			e.Speed = NumberRange.new(10, 16)
			e.SpreadAngle = Vector2.new(55, 55)
			e.EmissionDirection = Enum.NormalId.Top
			e.Acceleration = Vector3.new(0, -24, 0)
			e.Rate = LIFE.sprayRate
			e.LightEmission = 0.2
			e.Parent = part
			sp = e
			s.spray = e
		end
		local anchor = sp.Parent :: BasePart
		anchor.CFrame = CFrame.new(s.body.Position.X, hit.Position.Y + 0.3, s.body.Position.Z)
		sp.Rate = LIFE.sprayRate * math.clamp(speedNow / s.base, 0.4, 1.6)
	elseif not overWater and s.spray then
		local anchor = s.spray.Parent
		s.spray = nil
		if anchor then
			anchor:Destroy()
		end
	end
end

-- AnimationConstraint: the animator writes Transform every frame in PreRender (Character priority), the pose - right after it
local function holdPose()
	local s = st
	if not s then
		return
	end
	-- in flight the rider leans to the neck (HTTYD clip): the torso and the arms farther forward, smoothly
	local want = if s.mode == "air" then 1 else 0
	s.leanK += (want - s.leanK) * 0.08
	-- a lively seat - the torso sways with the flap (rig phase) in the air and with the step on the ground while moving
	local now = os.clock()
	local osc = 0
	if s.mode == "air" then
		local ph = if bones then bones.flapPhase(s.model, now) else nil
		osc = math.sin(ph or (now * D.life.flapHz * 2 * math.pi)) * math.rad(RD.pose.flapLean or 0)
	elseif s.vh.Magnitude > (RD.pose.gallopMinSpeed or 4) then
		osc = math.sin(now * D.bones.stepHz * 2 * math.pi) * math.rad(RD.pose.gallopLean or 0)
	end
	local extra = CFrame.Angles(-math.rad(RD.pose.leanAir) * s.leanK + osc, 0, 0)
	for m, cf in s.poseT do
		if m.Parent then
			local name = (m :: Instance).Name
			if name == "Waist" then
				(m :: any).Transform = cf * extra
			elseif name == "LeftShoulder" or name == "RightShoulder" then
				(m :: any).Transform = cf * CFrame.Angles(math.rad(RD.pose.armAir) * s.leanK, 0, 0)
			else
				(m :: any).Transform = cf
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------- rider pose
-- legs apart and forward, knees bent, arms forward, torso tilt (Motor6D C0);
-- the standard "sit" animation is stopped. C0 is restored in finish. Returns the number of joints found (for probes).
local function applyPose(s: State): number
	local ch = me.Character
	if not ch then
		return 0
	end
	local PO = RD.pose
	local n = 0
	-- Motor6D (the old rig): rotation through C0; AnimationConstraint: through Transform, which
	-- animations overwrite every frame - so the pose is kept in s.poseT and repeated in step()
	local function bend(name: string, cf: CFrame)
		local m = ch:FindFirstChild(name, true)
		if not m or s.pose[m :: any] then
			return
		end
		if m:IsA("Motor6D") then
			s.pose[m :: any] = m.C0
			m.C0 = m.C0 * cf
			n += 1
		elseif m:IsA("AnimationConstraint") then
			s.pose[m :: any] = CFrame.identity
			s.poseT[m :: any] = cf
			m.Transform = cf
			n += 1
		end
	end
	bend("LeftHip", CFrame.Angles(math.rad(PO.hipForward), 0, math.rad(PO.hipSpread)))
	bend("RightHip", CFrame.Angles(math.rad(PO.hipForward), 0, -math.rad(PO.hipSpread)))
	bend("LeftKnee", CFrame.Angles(-math.rad(PO.knee), 0, 0))
	bend("RightKnee", CFrame.Angles(-math.rad(PO.knee), 0, 0))
	bend("LeftShoulder", CFrame.Angles(math.rad(PO.armForward), 0, math.rad(PO.armIn)))
	bend("RightShoulder", CFrame.Angles(math.rad(PO.armForward), 0, -math.rad(PO.armIn)))
	bend("Waist", CFrame.Angles(-math.rad(PO.lean), 0, 0))
	bend("Left Hip", CFrame.Angles(math.rad(PO.hipForward), 0, math.rad(PO.hipSpread))) -- R6
	bend("Right Hip", CFrame.Angles(math.rad(PO.hipForward), 0, -math.rad(PO.hipSpread)))
	bend("Left Shoulder", CFrame.Angles(math.rad(PO.armForward), 0, 0))
	bend("Right Shoulder", CFrame.Angles(math.rad(PO.armForward), 0, 0))
	return n
end

-- ---------------------------------------------------------------------------------------------- mount / dismount
local function finish()
	local s = st
	if not s then
		return
	end
	st = nil
	me:SetAttribute("Flying", nil)
	if s.spray and s.spray.Parent then
		s.spray.Parent:Destroy()
	end
	for _, i in { s.lv, s.ao, s.att } do
		if i then
			i:Destroy()
		end
	end
	pcall(function()
		s.hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		s.hum.CameraOffset = Vector3.zero
		local label = s.body:FindFirstChild("Label")
		if label and label:IsA("BillboardGui") then
			label.Enabled = true
		end
	end)
	me.CameraMaxZoomDistance = s.prevZoom
	me.CameraMinZoomDistance = s.prevMinZoom
	for m, c0 in s.pose do
		if m.Parent then
			if m:IsA("Motor6D") then
				m.C0 = c0
			elseif m:IsA("AnimationConstraint") then
				m.Transform = CFrame.identity
			end
		end
	end
	for _, p in s.queryOff do
		if p.Parent then
			p.CanQuery = true
		end
	end
	local cam = workspace.CurrentCamera
	if cam then
		TweenService:Create(cam, TweenInfo.new(0.4), { FieldOfView = FL.fov.base }):Play()
	end
	RunService:UnbindFromRenderStep("DragonFlyCam")
	held.up, held.down = false, false
	autoLand = false
	showButtons(nil)
end

local function begin(model: Model, seat: BasePart, hum: Humanoid, uid: string)
	local body = model.PrimaryPart
	if not body then
		return
	end
	local _, size = model:GetBoundingBox()
	local stage = (model:GetAttribute("Stage") :: number?) or 1
	local def = D.stages[stage + 1] or D.stages[2]
	local att = Instance.new("Attachment")
	att.Name = "FlyAtt"
	att.Parent = body
	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlyVel"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.max(body.AssemblyMass, 1) * 400
	lv.VectorVelocity = Vector3.zero
	lv.Parent = body
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlyRot"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = FL.turnResponsiveness
	ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(body.CFrame.LookVector.X, 0, body.CFrame.LookVector.Z))
	ao.Parent = body
	local look = Vector3.new(body.CFrame.LookVector.X, 0, body.CFrame.LookVector.Z)
	st = {
		uid = uid, model = model, body = body, seat = seat, hum = hum, size = size, stage = stage, base = def.speed,
		ground = D.stages[2].speed * RD.groundSpeedMult, canFly = def.fly == true, mode = "ground", vh = Vector3.zero, vy = 0,
		boost = 0, takeoff = 0, lv = lv, ao = ao, att = att, prevZoom = me.CameraMaxZoomDistance, shake = 0,
		yaw = if look.Magnitude > 0.05 then look.Unit else Vector3.zAxis, told = false, stuck = 0,
		prevMinZoom = me.CameraMinZoomDistance, roll = 0, pose = {}, poseT = {}, queryOff = {}, spray = nil, leanK = 0,
	}
	pcall(function()
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) -- jump = up, not dismount
	end)
	local label = body:FindFirstChild("Label") -- the companion label hung over the rider's head when mounted
	if label and label:IsA("BillboardGui") then
		label.Enabled = false
	end
	-- zoom no closer than zoomMin, the camera above the back; the dragon's parts do not
	-- catch the camera popper ray (CanQuery) while riding
	local zoomMin = math.max(RD.zoomMinFloor, size.Magnitude * RD.zoomMinOfSize)
	hum.CameraOffset = Vector3.new(0, size.Y * RD.cameraUpOfHeight, 0)
	me.CameraMaxZoomDistance = math.max(FL.maxZoom, zoomMin + 10, me.CameraMaxZoomDistance)
	me.CameraMinZoomDistance = zoomMin
	local st2 = st :: State
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p.CanQuery then
			p.CanQuery = false
			table.insert(st2.queryOff, p)
		end
	end
	-- rider pose: applyPose after 0.25 s (after SitAnim)
	if RD.pose.enabled ~= false then
		task.delay(0.25, function()
			if st == st2 then
				applyPose(st2)
			end
		end)
	end
	RunService:BindToRenderStep("DragonFlyCam", Enum.RenderPriority.Camera.Value + 1, cameraStep)
	Sounds.voice(stage, "call", body) -- the dragon answers when the player mounts (3D from its body)
	if (st :: State).canFly and not toldTakeOff and banners then
		toldTakeOff = true
		banners.toast(Strings.Hints.takeOff)
	end
	showButtons(st)
end

local function watch()
	local uid = me:GetAttribute("Mounted")
	local hum = humanoid()
	local seat = hum and hum.SeatPart
	local s = st
	if s then
		if uid == nil or not hum or seat ~= s.seat or not s.model.Parent then
			finish()
		end
		return
	end
	if typeof(uid) == "string" and hum and seat and seat.Name == "Saddle" then
		local model = seat.Parent
		if model and model:IsA("Model") and model:GetAttribute("Uid") == uid then
			begin(model, seat, hum, uid)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- wind rings
local function ringModel(index: number): Model?
	for _, m in CollectionService:GetTagged("WindRing") do
		if m:IsA("Model") and m:GetAttribute("Ring") == index then
			return m
		end
	end
	return nil
end

local function flash(index: number)
	local m = ringModel(index)
	if not m then
		return
	end
	for _, seg in m:GetChildren() do
		if seg:IsA("BasePart") and seg.Name == "Seg" then
			local c0, s0 = seg.Color, seg.Size
			local t = TweenService:Create(seg, TweenInfo.new(0.12), { Color = Color3.new(1, 1, 1), Size = s0 * 1.6 })
			t:Play()
			t.Completed:Once(function()
				TweenService:Create(seg, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Color = c0, Size = s0 }):Play()
			end)
		end
	end
end

-- the next unpassed ring along the route (the first whose reward is available again)
function Fly.nextRing(): Model?
	local now = os.clock()
	for i = 1, #RINGS.positions do
		local at = passed[i]
		if not at or now - at >= RINGS.rearmSeconds then
			return ringModel(i)
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------- public
function Fly.isMounted(): boolean
	return st ~= nil
end

function Fly.isFlying(): boolean
	local s = st
	return s ~= nil and s.mode == "air"
end

function Fly.upButton(): GuiObject?
	local b = btnUp
	return if b and b.Visible and gui and gui.Enabled then b else nil
end

function Fly.state(): string
	local s = st
	if not s then
		return "off"
	end
	local cf = s.model:GetBoundingBox()
	return string.format("%s s%d mode=%s v=%.0f vy=%.0f boost=%.0f y=%.0f hum=%s sit=%s", s.uid, s.stage, s.mode, s.vh.Magnitude, s.vy, s.boost, cf.Position.Y, s.hum:GetState().Name, tostring(s.hum.Sit))
end

-- Studio probes (ClientDebug "fly ..."): "up on|off", "down on|off", "move x,z", "off" (dismount), "state"
function Fly.debug(arg: string): string
	local g = gui
	local verb, val = string.match(arg, "^(%a+)%s*(%S*)")
	if g and (verb == "up" or verb == "down") then
		g:SetAttribute(if verb == "up" then "Up" else "Down", val == "on")
	elseif g and verb == "move" then
		local x, z = string.match(val, "^(%-?[%d%.]+),(%-?[%d%.]+)$")
		g:SetAttribute("Move", if x and z then Vector3.new(tonumber(x) or 0, 0, tonumber(z) or 0) else nil)
	elseif verb == "off" then
		local r = Net.call("Dismount")
		return "dismount " .. tostring(r.ok) .. "/" .. tostring(r.reason)
	elseif verb == "pose" then
		local s = st
		if not s then
			return "pose: not mounted"
		end
		local n = applyPose(s)
		local have = 0
		for _ in s.pose do
			have += 1
		end
		return string.format("pose: applied now %d, total %d", n, have)
	end
	return Fly.state()
end

function Fly.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	bones = loaded.DragonBones
end

function Fly.start()
	buildGui()
	Net.on("ring", function(p)
		if typeof(p.ring) == "number" then
			passed[p.ring] = os.clock()
			flash(p.ring)
			Sounds.play("ring")
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not st then
			return
		end
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonY then
			tryDismount()
		end
	end)
	me:GetAttributeChangedSignal("InputKind"):Connect(function()
		showButtons(st)
	end)
	me.CharacterRemoving:Connect(finish)
	-- the animator writes Transform in PreRender at the Character priority; the rider pose - at the next priority (Stepped/Heartbeat are not visible)
	RunService:BindToRenderStep("RiderPose", Enum.RenderPriority.Character.Value + 1, holdPose)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(function()
			watch()
			step(dt)
		end)
		if not ok then
			warn("[Fly] " .. tostring(err))
			finish()
		end
	end)
end

return Fly
