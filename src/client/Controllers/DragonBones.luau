--!strict
-- Dragon bones .
-- Models rigged with UniRig (`runs/roblox_rig_2026-10-13/`): a MeshPart with a Bone tree. Bone names bone_N differ per model,
-- so the roles (spine, neck, head, tail, wings, legs) are determined by geometry: the chain from the root to the highest
-- bone is the spine and the head; the chain from the root in the opposite direction and downward is the tail; subtrees going far sideways
-- are wings; subtrees going down are legs. Movement in code in PreSimulation (`Bone.Transform` is not replicated - each
-- client rotates all dragon bones within Config.Dragon.life.viewDistance of the camera): chest breathing, the head follows the nearest
-- player (with angle limits and smoothing), the tail in a wave, the wings - light swaying while standing and flaps in flight, the legs
-- tucked in flight. Flight/movement - by the body velocity and a ray to the ground (every 0.25 s).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local DragonBones = {}

local LIFE = Config.Dragon.life
local BN = Config.Dragon.bones
local me = Players.LocalPlayer

type BoneInfo = { bone: Bone, rest: CFrame, parent: Bone?, children: { Bone } }
type Rig = {
	mesh: BasePart, height: number, width: number, fwd: Vector3, right: Vector3, up: Vector3,
	info: { [Bone]: BoneInfo }, chest: Bone?, neck: { Bone }, head: Bone?, tail: { Bone }, wingL: { Bone }, wingR: { Bone },
	legs: { Bone }, lookYaw: number, lookPitch: number, phase: number, flying: boolean, speed: number, lastProbe: number, grounded: boolean,
}

local rigs: { [Model]: Rig | false } = {}
local errors: { [Model]: string } = {}
local retry: { [Model]: { at: number, tries: number } } = {}
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

-- ---------------------------------------------------------------------------------------------- skeleton analysis
local function subtreeStats(info: { [Bone]: BoneInfo }, b: Bone): (number, number, number, number)
	-- maxY, minY, maxAbsX, maxAbsZ over the bone positions of the subtree (in the mesh's local axes)
	local maxY, minY, maxX, maxZ = -1e9, 1e9, 0, 0
	local stack = { b }
	while #stack > 0 do
		local cur = table.remove(stack) :: Bone
		local p = info[cur].rest.Position
		maxY = math.max(maxY, p.Y)
		minY = math.min(minY, p.Y)
		maxX = math.max(maxX, math.abs(p.X))
		maxZ = math.max(maxZ, math.abs(p.Z))
		for _, c in info[cur].children do
			table.insert(stack, c)
		end
	end
	return maxY, minY, maxX, maxZ
end

local function build(model: Model): Rig?
	local mesh = model.PrimaryPart
	if not mesh then
		return nil
	end
	local bones: { Bone } = {}
	for _, d in mesh:GetDescendants() do
		if d:IsA("Bone") then
			d.Transform = CFrame.identity
			table.insert(bones, d)
		end
	end
	if #bones < BN.minBones then
		return nil
	end
	local size = mesh.Size
	local info: { [Bone]: BoneInfo } = {}
	for _, b in bones do
		local parent = if b.Parent and b.Parent:IsA("Bone") then b.Parent :: Bone else nil
		info[b] = { bone = b, rest = mesh.CFrame:ToObjectSpace(b.WorldCFrame), parent = parent, children = {} }
	end
	local roots: { Bone } = {}
	for _, b in bones do
		local p = info[b].parent
		if p then
			table.insert(info[p].children, b)
		else
			table.insert(roots, b)
		end
	end
	if #roots == 0 then
		return nil
	end
	local root = roots[1]
	local rootPos0 = info[root].rest.Position
	local function subtree0(b: Bone): { Bone }
		local out, stack = {}, { b }
		while #stack > 0 do
			local cur = table.remove(stack) :: Bone
			table.insert(out, cur)
			for _, c in info[cur].children do
				table.insert(stack, c)
			end
		end
		return out
	end
	local function pathTo(b: Bone): { Bone } -- from the root to b
		local p = {}
		local cur: Bone? = b
		while cur do
			table.insert(p, 1, cur)
			cur = info[cur].parent
		end
		return p
	end
	-- v3 (tuned offline on 24 v3 and v4 skeletons, runs/roblox_rig_2026-10-13/roles3.py): the head and the tail are the two bones farthest
	-- from the root near the body axis (|x| < axisX of the width) in opposite directions, the higher end is the head; the spine is the path to
	-- the head (on v4 with spread wings the "highest subtree" rule led the spine into a wing)
	local centered: { Bone } = {}
	for _, b in bones do
		if b ~= root and math.abs(info[b].rest.Position.X - rootPos0.X) < size.X * BN.axisX then
			table.insert(centered, b)
		end
	end
	if #centered == 0 then
		return nil
	end
	local far = centered[1]
	local farD = -1
	for _, b in centered do
		local d = info[b].rest.Position - rootPos0
		local h = Vector3.new(d.X, 0, d.Z).Magnitude
		if h > farD then
			far, farD = b, h
		end
	end
	local axd = info[far].rest.Position - rootPos0
	local ax = Vector3.new(axd.X, 0, axd.Z)
	ax = if ax.Magnitude > 1e-4 then ax.Unit else -Vector3.zAxis
	local endA, endB = centered[1], nil :: Bone?
	local maxP, minP = -1e9, 1e9
	for _, b in centered do
		local pr = (info[b].rest.Position - rootPos0):Dot(ax)
		if pr > maxP then
			maxP, endA = pr, b
		end
		if pr < minP then
			minP, endB = pr, b
		end
	end
	if minP > -size.Z * 0.05 then
		endB = nil
	end
	if endB and info[endB].rest.Position.Y > info[endA].rest.Position.Y then
		endA, endB = endB, endA
	end
	local spine = pathTo(endA)
	-- the head = the highest spine bone with children (horns and the jaw are leaves - they ride along with it)
	local head: Bone? = nil
	local headI = #spine
	local topY = -1e9
	for i, b in spine do
		if #info[b].children > 0 and info[b].rest.Position.Y > topY then
			topY, head, headI = info[b].rest.Position.Y, b, i
		end
	end
	if not head then
		head, headI = spine[#spine], #spine
	end
	for i = #spine, headI + 1, -1 do
		table.remove(spine, i)
	end
	local rootY = rootPos0.Y
	local shoulderI = 1
	for i = 1, headI - 1 do
		if info[spine[i]].rest.Position.Y < rootY + size.Y * 0.12 then
			shoulderI = i
		end
	end
	local neck: { Bone } = {}
	for i = shoulderI + 1, headI - 1 do
		table.insert(neck, spine[i])
	end
	local chest: Bone? = spine[shoulderI]
	-- axes: forward - from the root to the head horizontally
	local headPos = if head then info[head].rest.Position else Vector3.zAxis
	local rootPos = info[root].rest.Position
	local fwd = Vector3.new(headPos.X - rootPos.X, 0, headPos.Z - rootPos.Z)
	fwd = if fwd.Magnitude > 0.01 then fwd.Unit else -Vector3.zAxis
	local up = Vector3.yAxis
	local right = fwd:Cross(up).Unit
	local inSpine: { [Bone]: boolean } = {}
	for _, b in spine do
		inSpine[b] = true
	end
	local function subtree(b: Bone): { Bone }
		local out, stack = {}, { b }
		while #stack > 0 do
			local cur = table.remove(stack) :: Bone
			table.insert(out, cur)
			for _, c in info[cur].children do
				table.insert(stack, c)
			end
		end
		return out
	end
	-- the tail: the path from the root to the tail end without spine bones; side branches of the first two links are leg candidates
	local tail: { Bone } = {}
	local tailSide: { Bone } = {}
	if endB then
		for _, b in pathTo(endB) do
			if not inSpine[b] then
				table.insert(tail, b)
			end
		end
		local inTail0: { [Bone]: boolean } = {}
		for _, b in tail do
			inTail0[b] = true
		end
		for i = 1, math.min(2, #tail) do
			for _, k in info[tail[i]].children do
				if not inTail0[k] then
					table.insert(tailSide, k)
				end
			end
		end
	end
	local inTail: { [Bone]: boolean } = {}
	for _, b in tail do
		inTail[b] = true
	end
	-- limb candidates (v3): all bones whose parent is in the spine or the tail; a node with one child is walked up to 3 steps,
	-- and if there is a fork not far from the start (hubDist of the height) - split into the children (a shared pelvis/chest, legs on the tail in v4)
	local inBody: { [Bone]: boolean } = {}
	for _, b in spine do
		inBody[b] = true
	end
	for _, b in tail do
		inBody[b] = true
	end
	local limbRoots: { Bone } = {}
	for _, b in bones do
		local p = info[b].parent
		if not inBody[b] and p and inBody[p] then
			table.insert(limbRoots, b)
		end
	end
	local exp: { Bone } = {}
	for _, c in limbRoots do
		local cur = c
		local steps = 0
		while #info[cur].children == 1 and steps < 3 do
			cur = info[cur].children[1]
			steps += 1
		end
		if #info[cur].children >= 2 and (info[cur].rest.Position - info[c].rest.Position).Magnitude < size.Y * BN.hubDist then
			for _, k in info[cur].children do
				table.insert(exp, k)
			end
		else
			table.insert(exp, c)
		end
	end
	local wingL, wingR, legs, down = {}, {}, {}, {}
	for _, c in exp do
		local nodes = subtree(c)
		local maxX, minY = 0, 1e9
		local tip, tipD = c, -1
		for _, n in nodes do
			local p = info[n].rest.Position
			maxX = math.max(maxX, math.abs(p.X - rootPos.X))
			minY = math.min(minY, p.Y)
			local d = (p - info[c].rest.Position).Magnitude
			if d > tipD then
				tip, tipD = n, d
			end
		end
		local startSide = (info[c].rest.Position - rootPos):Dot(right)
		local sideR = if math.abs(startSide) < size.X * 0.03 then (info[tip].rest.Position - rootPos):Dot(right) > 0 else startSide > 0
		if maxX > size.X * BN.wingX and (info[tip].rest.Position.Y > rootPos.Y - size.Y * BN.wingTipY or #nodes >= 6) then
			table.insert(if sideR then wingR else wingL, c)
		elseif minY < rootPos.Y - size.Y * BN.legY then
			table.insert(down, c)
		end
	end
	-- extra "legs" (> 4): folded wings (the highest start) - to the side without a wing; small extras - discard
	table.sort(down, function(a, b)
		return info[a].rest.Position.Y > info[b].rest.Position.Y
	end)
	local extra = math.max(0, #down - 4)
	for i, c in down do
		local sideR = (info[c].rest.Position - rootPos):Dot(right) > 0
		if i <= extra then
			if (sideR and #wingR == 0) or ((not sideR) and #wingL == 0) then
				table.insert(if sideR then wingR else wingL, c)
			elseif #subtree(c) >= 3 then
				table.insert(legs, c)
			end
		else
			table.insert(legs, c)
		end
	end
	if #legs > 4 then
		table.sort(legs, function(a, b)
			return #subtree(a) > #subtree(b)
		end)
		for i = #legs, 5, -1 do
			table.remove(legs, i)
		end
	end
	return {
		mesh = mesh, height = size.Y, width = size.X, fwd = fwd, right = right, up = up, info = info,
		chest = chest, neck = neck, head = head, tail = tail, wingL = wingL, wingR = wingR, legs = legs,
		lookYaw = 0, lookPitch = 0, phase = math.random() * 6.28, flying = false, speed = 0, lastProbe = 0, grounded = true,
	}
end

-- ---------------------------------------------------------------------------------------------- movement
-- rotate a bone around an axis given in the mesh axes (angle in radians), plus a shift in the mesh axes
local function rot(r: Rig, b: Bone, axisMesh: Vector3, angle: number, shift: Vector3?): CFrame
	local rest = r.info[b].rest
	local axisLocal = rest:VectorToObjectSpace(axisMesh)
	local cf = if axisLocal.Magnitude > 1e-4 then CFrame.fromAxisAngle(axisLocal.Unit, angle) else CFrame.identity
	if shift then
		cf = CFrame.new(rest:VectorToObjectSpace(shift)) * cf
	end
	return cf
end

local function nearestHead(pos: Vector3, maxDist: number): Vector3?
	local best: Vector3? = nil
	local bestD = maxDist
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local h = ch and ch:FindFirstChild("Head")
		if h and h:IsA("BasePart") then
			local d = (h.Position - pos).Magnitude
			if d < bestD then
				best, bestD = h.Position, d
			end
		end
	end
	return best
end

local function probe(r: Rig, model: Model, now: number)
	if now - r.lastProbe < 0.25 then
		return
	end
	r.lastProbe = now
	local v = r.mesh.AssemblyLinearVelocity
	r.speed = Vector3.new(v.X, 0, v.Z).Magnitude
	if r.mesh.Anchored then
		r.flying, r.grounded = false, true
		return
	end
	params.FilterDescendantsInstances = { model }
	local hit = workspace:Raycast(r.mesh.Position, Vector3.new(0, -(r.height + BN.flyAbove), 0), params)
	r.grounded = hit ~= nil
	r.flying = not r.grounded -- in the air (and hovering) we flap
end

local function animate(r: Rig, model: Model, now: number, dt: number)
	local t = now + r.phase
	local info = r.info
	-- chest breathing
	if r.chest then
		local w = math.sin(t * LIFE.bobHz * 2 * math.pi)
		r.chest.Transform = rot(r, r.chest, r.right, math.rad(BN.breathDeg) * w, r.up * (BN.breathShift * r.height * w))
	end
	-- the head toward the nearest player
	if r.head then
		local headWorld = r.mesh.CFrame * info[r.head].rest.Position
		local target = nearestHead(headWorld, BN.lookDistance)
		local yawT, pitchT = math.rad(BN.idleYawDeg) * math.sin(t * 0.35), math.rad(3) * math.sin(t * 0.5)
		if target then
			local dir = r.mesh.CFrame:VectorToObjectSpace(target - headWorld)
			local f, s = dir:Dot(r.fwd), dir:Dot(r.right)
			yawT = math.clamp(math.atan2(s, f), -math.rad(BN.yawMax), math.rad(BN.yawMax))
			local horiz = math.sqrt(f * f + s * s)
			pitchT = math.clamp(math.atan2(dir.Y, math.max(horiz, 0.01)), -math.rad(BN.pitchMax), math.rad(BN.pitchMax))
		end
		if r.flying then
			yawT, pitchT = yawT * 0.3, pitchT * 0.3
		end
		local k = math.min(dt * BN.lookSpeed, 1)
		r.lookYaw += (yawT - r.lookYaw) * k
		r.lookPitch += (pitchT - r.lookPitch) * k
		local chain = table.clone(r.neck)
		table.insert(chain, r.head)
		local n = #chain
		for _, b in chain do
			-- yaw around the vertical, pitch around the "right" axis; pitch sign: up = nose up
			local yaw = rot(r, b, r.up, -r.lookYaw / n)
			local pitch = rot(r, b, r.right, r.lookPitch / n)
			b.Transform = yaw * pitch
		end
	end
	-- the tail in a wave
	for i, b in r.tail do
		local amp = math.rad(BN.tailDeg) * (0.5 + i / #r.tail)
		local w = math.sin(t * BN.tailHz * 2 * math.pi - i * 0.9)
		local extra = if r.flying then math.rad(BN.tailFlyDeg) * math.sin(t * LIFE.flapHz * 2 * math.pi - i * 0.6) else 0
		b.Transform = rot(r, b, r.up, amp * w) * rot(r, b, r.right, extra)
	end
	-- the wings: the chain shoulder -> elbow -> wrist ->
	-- fingers: each next link lags by wingLag of the cycle and flaps harder (wingGain), the membrane catches up; the flap shape -
	-- a fast downstroke (wingDown fraction of the cycle) and a smooth rise; standing - slow breathing with the wings
	local wingAmp, wingHz = math.rad(BN.wingIdleDeg), BN.wingIdleHz
	if r.flying then
		wingAmp, wingHz = math.rad(BN.wingFlapDeg), LIFE.flapHz
	end
	local cyc = (t * wingHz) % 1
	local function stroke(ph: number): number
		-- ph in [0,1): 0..wingDown - down (from +1 to -1, accelerating), then up (from -1 to +1, smoothly)
		local d = BN.wingDown
		if ph < d then
			local u = ph / d
			return 1 - 2 * (u * u)
		end
		local u = (ph - d) / (1 - d)
		return -1 + 2 * (0.5 - 0.5 * math.cos(u * math.pi))
	end
	local function flapChain(rootBone: Bone, sign: number)
		local stack = { { rootBone, 0 } }
		while #stack > 0 do
			local e = table.remove(stack) :: { any }
			local b, depth = e[1] :: Bone, e[2] :: number
			local ph = (cyc - depth * BN.wingLag) % 1
			local a = wingAmp * (1 + depth * BN.wingGain) * stroke(ph) * sign
			-- a light forward-back rotation on the rise (the wing "scoops")
			local sweep = math.rad(BN.wingSweepDeg) * math.sin((ph + 0.25) * 2 * math.pi) * (if r.flying then 1 else 0.2)
			b.Transform = rot(r, b, r.fwd, a) * rot(r, b, r.up, sweep * sign)
			if depth < BN.wingDepthMax then
				for _, c in r.info[b].children do
					table.insert(stack, { c, depth + 1 })
				end
			end
		end
	end
	for _, b in r.wingR do
		flapChain(b, 1)
	end
	for _, b in r.wingL do
		flapChain(b, -1)
	end
	-- the legs: tucked in flight, stepping while walking
	for i, b in r.legs do
		if r.flying then
			b.Transform = rot(r, b, r.right, -math.rad(BN.legTuckDeg))
		elseif r.speed > 2 then
			local w = math.sin(t * BN.stepHz * 2 * math.pi + (i % 2) * math.pi)
			b.Transform = rot(r, b, r.right, math.rad(BN.stepDeg) * w * math.min(r.speed / 20, 1))
		else
			b.Transform = CFrame.identity
		end
	end
end

local lifeCtl: any = nil -- P37: DragonLife hides other players' dragons

local function step(dt: number)
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local now = os.clock()
	for _, m in CollectionService:GetTagged("Dragon") do
		if m:IsA("Model") and m.Parent then
			local r = rigs[m]
			if r == nil then
				-- the bones arrive from the server not in one frame: without a rig - retry every retryEvery s, up to retryMax times
				local rt = retry[m]
				if not rt or now - rt.at >= BN.retryEvery then
					local ok, res = pcall(build, m)
					if not ok then
						errors[m] = tostring(res)
						warn("[DragonBones] build " .. tostring(m:GetAttribute("Uid")) .. ": " .. tostring(res))
					end
					r = if ok then res else nil
					if r then
						rigs[m] = r
						retry[m] = nil
					else
						rt = rt or { at = now, tries = 0 }
						rt.at = now
						rt.tries += 1
						retry[m] = rt
						if rt.tries >= BN.retryMax then
							rigs[m] = false
						end
					end
				end
			end
			if r and r.mesh.Parent and (r.mesh.Position - camPos).Magnitude <= LIFE.viewDistance and not (lifeCtl and lifeCtl.isHidden(m)) then -- P37: hidden foreign dragons are not animated
				probe(r, m, now)
				animate(r, m, now, dt)
			end
		end
	end
end

-- the model's flap phase (for the Fly rider: swaying in rhythm), nil without a rig
function DragonBones.flapPhase(m: Model, now: number): number?
	local r = rigs[m]
	if not r or not r.flying then
		return nil
	end
	return (now + r.phase) * LIFE.flapHz * 2 * math.pi
end

-- the world point of the head - the breath flies from here (the rig's head bone); no rig - nil
function DragonBones.mouth(m: Model): Vector3?
	local r = rigs[m]
	if not r or not r.head then
		return nil
	end
	local ok, cf = pcall(function()
		return (r.head :: Bone).TransformedWorldCFrame
	end)
	return if ok and cf then cf.Position else nil
end

-- whether the model has bones (for DragonLife: such models are not rocked as a whole)
function DragonBones.isRigged(m: Model): boolean
	local r = rigs[m]
	return r ~= nil and r ~= false
end

-- for Studio probes
function DragonBones.describe(m: Model): string
	local r = rigs[m]
	if not r then
		local n = 0
		local mesh = m.PrimaryPart
		if mesh then
			for _, d in mesh:GetDescendants() do
				if d:IsA("Bone") then
					n += 1
				end
			end
		end
		return "no rig (bones=" .. n .. (if errors[m] then ", err=" .. errors[m] else "") .. ")"
	end
	return string.format("bones chest=%s neck=%d head=%s tail=%d wingL=%d wingR=%d legs=%d flying=%s speed=%.0f yaw=%.0f", tostring(r.chest and r.chest.Name), #r.neck, tostring(r.head and r.head.Name), #r.tail, #r.wingL, #r.wingR, #r.legs, tostring(r.flying), r.speed, math.deg(r.lookYaw))
end

function DragonBones.init(_snapshot: any, loaded: any)
	lifeCtl = loaded.DragonLife
end

function DragonBones.start()
	CollectionService:GetInstanceRemovedSignal("Dragon"):Connect(function(m)
		if m:IsA("Model") then
			rigs[m] = nil
			retry[m] = nil
		end
	end)
	RunService.PreSimulation:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[DragonBones] " .. tostring(err))
		end
	end)
end

return DragonBones
