--!strict
-- Movement (1.9; 04 §5-5.1, 02 §2, 10 §4): the companion next to the player and everything the server decides about riding and flight.
-- The companion is one dragon of the nest (data.companion, by default the first hatched; SetCompanion changes it): a hatchling is welded to the shoulder
-- (a WeldConstraint to UpperTorso, Config.Dragon.shoulderOffset), a teen and older follow the owner on a leash
-- (AlignPosition / AlignOrientation, network ownership with the owner; the leash target is set by the client Controllers/Companion). The model in
-- the nest stays (Feed, the label, the income) - the companion is shown as a separate copy at the base scale of the stage (03 §1.2).
-- Mount(uid): the companion within mountDistance, stage >= 1 -> Seat.Sit, the body solid, the character in the Rider group (does not snag),
-- the leash off; the riding physics (speed, takeoff, dive, landing) is computed by the rider's client (Controllers/Fly), the server every
-- checkTick s checks the speed against the stage ceiling (flight: flight.maxSpeedCheck) and the height ceiling - a return to the last
-- honest point. Wind rings: the rider's body crossing the ring plane within the radius -> coins = rewardSeconds of the nest
-- income (at least rewardMin), a repeat after rearmSeconds, Notice ring + coins. Onboarding steps: glided (Freefall with the hatchling for
-- glideSeconds), rode (the first mount), flew (mounted higher than flewHeight above the ground), ring (the first ring).

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Core = Shared:WaitForChild("Core")
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local Layout = require(Core:WaitForChild("Layout"))
local IndexCore = require(Core:WaitForChild("Index"))

local Movement = {}

local B = Config.Balance
local D = Config.Dragon
local RD = D.ride
local FL = D.flight
local RINGS = Config.World.windRings
local services: { [string]: any } = {}

-- the hatchling (stage 0): mode = "hatch" (at the ring, waiting for the jump) | "shoulder" (welded to the torso) | "ground" (jumped off, fiddles nearby)
-- busy - a jump/step in progress; lift - the pivot height above the bounding box sole
type Companion = { model: Model, body: BasePart, uid: string, stage: number, sig: string, weld: WeldConstraint?, breathAt: number?, breathOff: number?, mode: string?, busy: boolean?, lift: number? }
type Mounted = { uid: string, stage: number, speed: number, lastPos: Vector3, lastAt: number, strikes: number, rings: { [number]: number }, seat: Seat, occConn: RBXScriptConnection?, flyAcc: number?, soft: number? } -- soft - small overspeeds in a row

local companions: { [Player]: Companion } = {}
local buildGen: { [Player]: number } = {} -- the number of the last companion build
local mounted: { [Player]: Mounted } = {}
local airSince: { [Player]: number } = {} -- gliding: since when the hatchling is in the air
local folder: Folder? = nil
local rings: { { index: number, center: Vector3, axis: Vector3 } } = {}

local function v3(t: { number }): Vector3
	return Vector3.new(t[1], t[2], t[3])
end

local function character(player: Player): (Model?, BasePart?, Humanoid?)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if ch and root and root:IsA("BasePart") and hum and hum.Health > 0 then
		return ch, root, hum
	end
	return nil, nil, nil
end

-- collision groups: Rider (a mounted character) collides with nothing; Dragon - with the world, but not with dragons and riders
local function groups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Rider")
		PhysicsService:RegisterCollisionGroup("Dragon")
		PhysicsService:CollisionGroupSetCollidable("Rider", "Default", false)
		PhysicsService:CollisionGroupSetCollidable("Rider", "Dragon", false)
		PhysicsService:CollisionGroupSetCollidable("Rider", "Rider", false)
		PhysicsService:CollisionGroupSetCollidable("Dragon", "Dragon", false)
	end)
end

local function setCharacterGroup(ch: Model?, group: string)
	if not ch then
		return
	end
	for _, p in ch:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = group
		end
	end
end

local function groundY(pos: Vector3, ignore: { Instance }): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos, Vector3.new(0, -400, 0), params)
	return if hit then hit.Position.Y else nil
end

-- ---------------------------------------------------------------------------------------------- the companion
-- land under the point - a ray down without water, a hit above sea level
local SW = Config.World.swim
local SEA = Config.World.island2.seaLevel
local shoreAt: { [Player]: number } = {}
local function landBelow(pos: Vector3, ignore: { Instance }): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = true
	local top = math.max(pos.Y, SEA) + 60
	local hit = workspace:Raycast(Vector3.new(pos.X, top, pos.Z), Vector3.new(0, -(top - (SEA - 30)), 0), params) -- down to the bottom at any flight height
	if hit and hit.Position.Y >= SEA + SW.shoreAbove and hit.Material ~= Enum.Material.Water then
		return hit
	end
	return nil
end

local function signature(d: any): string
	return table.concat({ d.uid, tostring(d.stage), tostring(d.size), tostring(d.shiny), d.element }, "|")
end

local function destroyCompanion(player: Player)
	local c = companions[player]
	if not c then
		return
	end
	companions[player] = nil
	player:SetAttribute("CompanionStage", nil)
	if c.model.Parent then
		c.model:Destroy()
	end
end

-- ---------------------------------------------------------------------------------------------- the hatchling: the shoulder, the ring, jumps, fiddling
-- "hatched at the incubator, looked around and jumped onto the shoulder"; "while you stand, it jumps off and fiddles nearby".
-- The model is anchored while not on the shoulder (the server drives the CFrame itself: the jump arc, steps), on the shoulder - welded to the torso (network ownership with the player).
local HH = D.hatchHop
local PL = D.play
local rng = Random.new()

local function torsoOf(player: Player): BasePart?
	local ch = player.Character
	local t = ch and (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
	return if t and t:IsA("BasePart") then t else nil
end

-- the model pivot on the shoulder: the bounding box sole at the shoulderOffset point, looking where the character looks
local function shoulderCFrame(player: Player, c: Companion): CFrame?
	local torso = torsoOf(player)
	if not torso then
		return nil
	end
	local o = D.shoulderOffset
	local target = (torso.CFrame * CFrame.new(o[1], o[2], o[3])).Position
	return CFrame.lookAt(target, target + torso.CFrame.LookVector) + Vector3.new(0, c.lift or 0, 0)
end

local function weldShoulder(player: Player, c: Companion)
	local torso = torsoOf(player)
	if not torso or not c.model.Parent then
		return
	end
	local cf = shoulderCFrame(player, c)
	if cf then
		c.model:PivotTo(cf)
	end
	c.body.Anchored = false
	c.body.AssemblyLinearVelocity = Vector3.zero
	local w = Instance.new("WeldConstraint")
	w.Name = "ShoulderWeld"
	w.Part0 = torso
	w.Part1 = c.body
	w.Parent = c.body
	c.weld = w
	c.mode = "shoulder"
	pcall(function()
		c.body:SetNetworkOwner(player)
	end)
end

local function unweldShoulder(c: Companion)
	if c.weld then
		c.weld:Destroy()
		c.weld = nil
	end
	c.body.Anchored = true
	c.body.AssemblyLinearVelocity = Vector3.zero
end

-- an arc from the current pivot to the target (the target is recomputed every frame: the shoulder moves); blocks until the end
local function hopTo(c: Companion, targetFn: () -> CFrame?, seconds: number, height: number)
	local start = c.model:GetPivot()
	local t0 = os.clock()
	while c.model.Parent do
		local t = math.min(1, (os.clock() - t0) / math.max(0.05, seconds))
		local target = targetFn() or start
		local pos = start.Position:Lerp(target.Position, t) + Vector3.new(0, height * math.sin(t * math.pi), 0)
		c.model:PivotTo(start.Rotation:Lerp(target.Rotation, t) + pos)
		if t >= 1 then
			break
		end
		task.wait()
	end
end

local function groundPoint(player: Player, c: Companion, pos: Vector3): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character :: Instance, c.model }
	params.IgnoreWater = false
	local hit = workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
	if hit and hit.Material ~= Enum.Material.Water then
		return hit.Position
	end
	return nil
end

-- fiddling nearby: you stand - it jumps off and walks in steps around, you walked/jumped/mounted/left - it jumps back
local function playLoop(player: Player, c: Companion)
	local still = 0
	local nextStep = 0
	while companions[player] == c and c.model.Parent do
		task.wait(0.1)
		if c.busy or c.mode == "hatch" then
			continue
		end
		local ch, root, hum = character(player)
		if not ch or not root or not hum then
			continue
		end
		local v = root.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		local state = hum:GetState()
		local grounded = hum.FloorMaterial ~= Enum.Material.Air and state ~= Enum.HumanoidStateType.Swimming and state ~= Enum.HumanoidStateType.Freefall and state ~= Enum.HumanoidStateType.Jumping
		-- while the player has an own Gloom wave, the hatchling sits on the shoulder (breathes from there), and if it was fiddling below - it jumps back
		-- (in the grass at the feet it is not visible); "in combat" - own Gloom closer than focusRange (not any own wave: the meadow arena under the nest stands almost always)
		local fighting = false
		if player:GetAttribute("Gloom_meadow") ~= nil or player:GetAttribute("Gloom_sky") ~= nil then
			for _, g in CollectionService:GetTagged("Gloom") do
				if g:IsA("Model") and g:GetAttribute("OwnerId") == player.UserId
					and (g:GetPivot().Position - root.Position).Magnitude < Config.Combat.ui.focusRange then
					fighting = true
					break
				end
			end
		end
		if c.mode == "shoulder" then
			still = if speed < 1 and grounded and not mounted[player] and not fighting then still + 0.1 else 0
			if still >= PL.stillSeconds then
				still = 0
				local side = (root.CFrame * CFrame.new(PL.radius * 0.5, 0, -PL.radius * 0.6)).Position
				local g = groundPoint(player, c, side)
				if g then
					c.busy = true
					unweldShoulder(c)
					hopTo(c, function()
						local r = root.Position
						local at = g + Vector3.new(0, c.lift or 0, 0)
						local face = Vector3.new(r.X - g.X, 0, r.Z - g.Z)
						return CFrame.lookAt(at, at + (if face.Magnitude > 0.1 then face.Unit else root.CFrame.LookVector))
					end, PL.hopSeconds, HH.height)
					c.mode = "ground"
					nextStep = os.clock() + rng:NextNumber(PL.stepEvery[1], PL.stepEvery[2])
					c.busy = false
				end
			end
		elseif c.mode == "ground" then
			local flat = Vector3.new(root.Position.X - c.body.Position.X, 0, root.Position.Z - c.body.Position.Z)
			if speed > PL.moveSpeed or flat.Magnitude > PL.leaveDistance or mounted[player] or not grounded or fighting then
				c.busy = true
				hopTo(c, function()
					return shoulderCFrame(player, c)
				end, PL.hopSeconds, HH.height)
				weldShoulder(player, c)
				still = 0
				c.busy = false
			elseif os.clock() >= nextStep then
				nextStep = os.clock() + rng:NextNumber(PL.stepEvery[1], PL.stepEvery[2])
				local a = rng:NextNumber(0, math.pi * 2)
				local rr = rng:NextNumber(1.5, PL.radius)
				local g = groundPoint(player, c, root.Position + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr))
				if g then
					c.busy = true
					local from = c.body.Position
					local dir = Vector3.new(g.X - from.X, 0, g.Z - from.Z)
					local face = if dir.Magnitude > 0.1 then dir.Unit else root.CFrame.LookVector
					local at = g + Vector3.new(0, c.lift or 0, 0)
					hopTo(c, function()
						return CFrame.lookAt(at, at + face)
					end, PL.stepSeconds, PL.stepHeight)
					if c.model.Parent then -- after the step the snout toward the player
						local cur = c.model:GetPivot()
						local toP = Vector3.new(root.Position.X - cur.Position.X, 0, root.Position.Z - cur.Position.Z)
						if toP.Magnitude > 0.1 then
							c.model:PivotTo(CFrame.lookAt(cur.Position, cur.Position + toP.Unit))
						end
					end
					c.busy = false
				end
			end
		end
	end
end

-- the copy's physics: everything detached from the anchor, welded to the body, no collisions (the body is solid only when mounted)
local function preparePhysics(m: Model, body: BasePart, masslessBody: boolean)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = p == body
			p.Massless = p ~= body or masslessBody -- the hatchling on the shoulder is weightless, like an accessory
			p.CollisionGroup = "Dragon"
			if p:IsA("Seat") then
				p.Disabled = false -- CanTouch = false: it seats nobody by itself, only Seat:Sit from Mount
			end
			if p ~= body then
				local welded = false
				for _, w in p:GetChildren() do
					if w:IsA("WeldConstraint") and (w.Part0 == body or w.Part1 == body) then
						welded = true
						break
					end
				end
				if not welded then
					local w = Instance.new("WeldConstraint")
					w.Part0 = body
					w.Part1 = p
					w.Parent = p
				end
			end
		end
	end
	body.CustomPhysicalProperties = PhysicalProperties.new(0.35, 0.3, 0.1, 1, 1)
end

local function followConstraints(body: BasePart, at: CFrame)
	local att = Instance.new("Attachment")
	att.Name = "Follow"
	att.Parent = body
	local ap = Instance.new("AlignPosition")
	ap.Name = "FollowPos"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.ApplyAtCenterOfMass = true
	ap.MaxForce = math.huge
	ap.MaxVelocity = D.leash.maxVelocity
	ap.Responsiveness = D.leash.responsiveness
	ap.Position = at.Position
	ap.Parent = body
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FollowRot"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = D.leash.turn
	ao.CFrame = at
	ao.Parent = body
end

local function setFollow(c: Companion, on: boolean)
	local ap = c.body:FindFirstChild("FollowPos")
	local ao = c.body:FindFirstChild("FollowRot")
	if ap and ap:IsA("AlignPosition") then
		ap.Enabled = on
		if on then
			ap.Position = c.body.Position
		end
	end
	if ao and ao:IsA("AlignOrientation") then
		ao.Enabled = on
		if on then
			ao.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(c.body.CFrame.LookVector.X, 0, c.body.CFrame.LookVector.Z))
		end
	end
end

-- 1.14 (Admin, bots for FPS measurement): the same physics as the companion - the body on AlignPosition/AlignOrientation (the target is set by Admin),
-- a mannequin rider in the Rider group; the network with the server
function Movement.rigFlier(m: Model, body: BasePart, at: CFrame)
	preparePhysics(m, body, false)
	followConstraints(body, at)
	pcall(function()
		body:SetNetworkOwner(nil)
	end)
end

function Movement.rigFlierRider(rider: Model)
	setCharacterGroup(rider, "Rider")
end

-- the model's bounding box at a point without solid parts and without visible tall ones (a post, a sign, a torch)
-- the terrain, the own character and the model itself do not count; untouchable decor (grass, crowns) is not seen by the spatial query (CanQuery).
-- The intersection by the real shape (GetPartsInPart with a temporary block): by the described boxes (GetPartBoundsInBox) the tilted
-- plaza plates and the terrace body gave false "occupied"
local SPOT = D.spawnSpot
local function spotFree(probe: Part, cf: CFrame, size: Vector3, ignore: { Instance }): boolean
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = ignore
	probe.Size = Vector3.new(size.X * SPOT.shrink, math.max(1, size.Y - SPOT.lift), size.Z * SPOT.shrink)
	probe.CFrame = cf + Vector3.new(0, SPOT.lift / 2, 0)
	for _, q in workspace:GetPartsInPart(probe, op) do
		if q ~= workspace.Terrain and (q.CanCollide or (q.Transparency < 0.95 and q.Size.Y >= SPOT.tallPart)) then
			return false
		end
	end
	return true
end

-- the spot for the copy: where the previous one stood, otherwise to the right of the character on the ground. to the right of the spawn
-- on the plaza stands the Top Nests board - the ray to the ground hit the board, the elder stood on it and stalled on takeoff; now the point
-- is chosen free (spotFree) with the ground at foot level (spawnSpot.step), sweeping sides and distances. None free - the first
-- point with ground, none such either - as before. free = also level (spawnSpot.level); strict (relocating a stuck one,
-- Movement.regroup) - without fallback points: no free level one - nil
-- view, dirs (relocation): the sides from the camera look along the ground instead of the character look, its own direction list
local function spawnCFrame(player: Player, size: Vector3, prev: Vector3?, strict: boolean?, view: Vector3?, dirs: { number }?): CFrame?
	local ch, root, hum = character(player)
	if not ch or not root or not hum then
		return nil
	end
	local foot = root.Position.Y - root.Size.Y / 2 - hum.HipHeight
	local mine: { Instance } = { ch :: Instance }
	local folderNow = folder
	if folderNow then
		for _, x in folderNow:GetChildren() do -- the previous copies of this player (buildCompanion removes them after the build)
			if x:GetAttribute("OwnerId") == player.UserId then
				table.insert(mine, x)
			end
		end
	end
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = mine
	rayParams.IgnoreWater = false
	local ignore = table.clone(mine)
	table.insert(ignore, workspace.Terrain)
	local solidParams = RaycastParams.new() -- levelness - by the same thing the client leash stands on: solid only
	solidParams.FilterType = Enum.RaycastFilterType.Exclude
	solidParams.FilterDescendantsInstances = mine
	solidParams.RespectCanCollide = true
	local function level(cf: CFrame): boolean
		local spread = D.leash.footSpread or 0.35
		local top = cf.Position.Y + size.Y / 2 + 2
		local bottom = cf.Position.Y - size.Y / 2
		local center = workspace:Raycast(Vector3.new(cf.Position.X, top, cf.Position.Z), Vector3.new(0, -(size.Y + SPOT.step + 4), 0), solidParams)
		local tol = SPOT.level or 1
		if not center or math.abs(center.Position.Y - bottom) > tol then -- the box bottom was set by a ray without RespectCanCollide: nothing solid under it - not level
			return false
		end
		for _, o in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local off = cf.Rotation * Vector3.new(o[1] * size.X * spread, 0, o[2] * size.Z * spread)
			local hit = workspace:Raycast(Vector3.new(cf.Position.X + off.X, top, cf.Position.Z + off.Z), Vector3.new(0, -(size.Y + SPOT.step + 4), 0), solidParams)
			if not hit or hit.Material == Enum.Material.Water or math.abs(hit.Position.Y - center.Position.Y) > tol then
				return false
			end
		end
		return true
	end
	local function placeAt(pos: Vector3): CFrame?
		local top = foot + math.max(size.Y, 12) + 5
		local hit = workspace:Raycast(Vector3.new(pos.X, top, pos.Z), Vector3.new(0, -(top - foot + SPOT.step + 1), 0), rayParams)
		if not hit or hit.Material == Enum.Material.Water or math.abs(hit.Position.Y - foot) > SPOT.step then
			return nil
		end
		local y = hit.Position.Y + size.Y / 2 + (D.leash.footClearance or RD.hoverClearance) -- the box bottom footClearance above the ground - like the client leash target, no jump at the build
		return CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(root.Position.X, y, root.Position.Z))
	end
	local probe = Instance.new("Part")
	probe.Name = "CompanionSpotProbe"
	probe.Anchored = true
	probe.CanCollide = false
	probe.CanTouch = false
	probe.CanQuery = false
	probe.Transparency = 1
	probe.Parent = workspace -- GetPartsInPart searches in the same WorldRoot as the block
	local first: CFrame? = nil
	local function try(pos: Vector3): CFrame?
		local cf = placeAt(pos)
		if not cf then
			return nil
		end
		first = first or cf
		return if spotFree(probe, cf, size, ignore) and level(cf) then cf else nil
	end
	local function search(): CFrame?
		local found = if prev then try(prev) else nil
		if found then
			return found
		end
		local base = D.leash.distance + size.Z * 0.4
		local basis = if view then CFrame.lookAt(Vector3.zero, view) else root.CFrame
		for _, extra in SPOT.reach do
			for _, deg in dirs or SPOT.dirs do
				local a = math.rad(deg)
				local dir = basis:VectorToWorldSpace(Vector3.new(math.sin(a), 0, -math.cos(a)))
				local flat = Vector3.new(dir.X, 0, dir.Z)
				if flat.Magnitude > 0.01 then
					found = try(root.Position + flat.Unit * (base + extra))
					if found then
						return found
					end
				end
			end
		end
		return nil
	end
	local ok, found = pcall(search)
	probe:Destroy()
	if not ok then
		warn("[Movement] spawnCFrame: " .. tostring(found))
	elseif found then
		return found
	end
	if strict then
		return nil
	end
	if first then
		return first
	end
	local pos = prev or (root.CFrame * CFrame.new(D.leash.distance + size.Z * 0.4, 0, 2)).Position
	local gy = groundY(pos + Vector3.new(0, 20, 0), { ch })
	local y = if gy then gy + size.Y / 2 + (D.leash.footClearance or RD.hoverClearance) else pos.Y
	return CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(root.Position.X, y, root.Position.Z))
end

local function buildCompanion(player: Player, d: any, prev: Vector3?)
	destroyCompanion(player)
	local ch, root, hum = character(player)
	if not ch or not root or not hum or not folder then
		return
	end
	local DV = services.DragonVisuals
	local gen = (buildGen[player] or 0) + 1
	buildGen[player] = gen
	local m: Model = DV.build(d, false)
	-- DV.build on a live server waits for the mesh load; meanwhile
	-- on join more calls arrive (Nest.assign, CharacterAdded, growth during absence) - before, each built its own companion, the extras
	-- stayed in Companions forever. The last call wins, an outdated build is destroyed.
	if buildGen[player] ~= gen or player.Parent ~= Players then
		m:Destroy()
		return
	end
	m.Name = "Companion"
	m:SetAttribute("Uid", d.uid)
	m:SetAttribute("OwnerId", player.UserId)
	m:SetAttribute("Companion", true)
	local body = m.PrimaryPart
	if not body then
		m:Destroy()
		return
	end
	-- there is no copy in the nest anymore (Nest.refresh skips the companion) - this model shows the income; the hatchling on the shoulder has the label
	-- fully off: it hung right on the coin counter
	local lbl = body:FindFirstChild("Label")
	if lbl and lbl:IsA("BillboardGui") and d.stage == 0 then
		lbl.Enabled = false
	end
	local _, size = m:GetBoundingBox()
	preparePhysics(m, body, d.stage == 0)
	if d.stage >= 1 then
		body.CanCollide = true -- a teen and older - a solid body always, not only when mounted
	end
	CollectionService:AddTag(m, "Companion")
	local c: Companion = { model = m, body = body, uid = d.uid, stage = d.stage, sig = signature(d), weld = nil, breathAt = nil, breathOff = nil }
	if d.stage == 0 then
		-- the hatchling: the bounding box sole at the shoulder point (shoulderOffset from UpperTorso), looking where the character looks
		if not torsoOf(player) then
			m:Destroy()
			return
		end
		m:PivotTo(CFrame.new(0, 0, 0))
		local cf0 = m:GetBoundingBox()
		c.lift = m:GetPivot().Position.Y - (cf0.Position.Y - size.Y / 2)
		m.Parent = folder
		local origin = if services.Nest and services.Nest.takeHatchOrigin then services.Nest.takeHatchOrigin(player, d.uid) else nil
		if origin then
			-- just hatched - at the ring, snout toward the player; after sitSeconds in an arc onto the shoulder
			body.Anchored = true
			local at = origin + Vector3.new(0, 0.5 + (c.lift or 0), 0)
			local look = Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z)
			m:PivotTo(CFrame.lookAt(at, at + (if look.Magnitude > 0.1 then look.Unit else root.CFrame.LookVector)))
			c.mode = "hatch"
			c.busy = true
			task.delay(HH.sitSeconds, function()
				if companions[player] ~= c or not c.model.Parent then
					return
				end
				hopTo(c, function()
					return shoulderCFrame(player, c)
				end, HH.hopSeconds, HH.height)
				weldShoulder(player, c)
				c.busy = false
			end)
		else
			weldShoulder(player, c)
		end
	else
		local at = spawnCFrame(player, size, prev)
		if not at then
			m:Destroy()
			return
		end
		m:PivotTo(at)
		local cf = m:GetBoundingBox()
		m:PivotTo(m:GetPivot() + (at.Position - cf.Position)) -- the bounding box center onto the point
		m.Parent = folder
		followConstraints(body, CFrame.lookAt(Vector3.zero, at.LookVector) + body.Position)
	end
	for _, x in (folder :: Folder):GetChildren() do -- orphans of this player's previous builds (and old sessions)
		if x ~= m and x:GetAttribute("OwnerId") == player.UserId then
			x:Destroy()
		end
	end
	companions[player] = c
	player:SetAttribute("CompanionStage", d.stage)
	pcall(function()
		body:SetNetworkOwner(player)
	end)
	if d.stage == 0 then
		task.spawn(playLoop, player, c) -- after writing into companions: the loop lives while this is the same companion
	end
	if services.Nest and services.Nest.syncModel then -- the attributes and CanFeed like the copy in the nest (the Feed button, the income, the card)
		local data = services.PlayerData.get(player)
		if data then
			services.Nest.syncModel(m, d, data, os.time())
		end
	end
end

-- rebuild the companion from the data (after a nest refresh, a companion change, a new character)
function Movement.refresh(player: Player)
	local data = services.PlayerData.get(player)
	if not data or not folder then
		return
	end
	local uid = data.companion
	local d = uid and data.dragons[uid]
	local inNest = d ~= nil and table.find(data.nestOrder, uid) ~= nil
	if not d or not inNest then
		if mounted[player] then
			Movement.dismount(player, true)
		end
		destroyCompanion(player)
		return
	end
	local c = companions[player]
	local ch = character(player)
	if c and c.model.Parent and ch and c.model:IsDescendantOf(workspace) then
		if c.sig == signature(d) then
			services.DragonVisuals.relabel(c.model, d)
			return
		end
	end
	local prev = if c and c.model.Parent and c.stage >= 1 then c.body.Position else nil
	if mounted[player] then
		-- the model under the rider is not
		-- rebuilt and the rider is not dismounted - the dragon keeps flying as it was, the rebuild after landing (Movement.dismount -> refresh, already there)
		return
	end
	buildCompanion(player, d, prev)
end

function Movement.companionOf(player: Player): Model?
	local c = companions[player]
	return if c and c.model.Parent then c.model else nil
end

-- ---------------------------------------------------------------------------------------------- mounted
local function cleanupMount(player: Player)
	local st = mounted[player]
	if not st then
		return
	end
	mounted[player] = nil
	if st.occConn then
		st.occConn:Disconnect()
	end
	player:SetAttribute("Mounted", nil)
	local ch = player.Character
	setCharacterGroup(ch, if services.AntiCheat then services.AntiCheat.walkGroup() else "Default") -- on foot - Player (no collisions)
	local c = companions[player]
	if c and c.model.Parent then
		c.model:SetAttribute("Rider", nil)
		c.body.CanCollide = false
		c.body.AssemblyLinearVelocity = Vector3.zero
		c.body.AssemblyAngularVelocity = Vector3.zero
		setFollow(c, true)
	end
end

function Movement.dismount(player: Player, force: boolean?): { ok: boolean, reason: string? }
	local st = mounted[player]
	if not st then
		return { ok = false, reason = "already" }
	end
	local seat = st.seat
	-- no dismount over the sea - to the shore first
	local ch0, _, _ = character(player)
	local c0 = companions[player]
	if not force and ch0 and c0 and c0.model.Parent then
		local _, size0 = c0.model:GetBoundingBox()
		local spot = c0.body.Position + c0.body.CFrame.RightVector * (size0.X / 2 + 2.5)
		if not landBelow(spot, { ch0 :: Instance, c0.model }) and not landBelow(c0.body.Position, { ch0 :: Instance, c0.model }) then
			return { ok = false, reason = "over_water" }
		end
	end
	-- on the player's request in the air there is no dismount (a player who took off is never dropped) - the client
	-- (Fly.tryDismount) on the in_air refusal lowers the dragon by itself and dismounts after landing
	if not force and c0 and c0.model.Parent and ch0 then
		local gy0 = groundY(c0.body.Position, { ch0 :: Instance, c0.model })
		if gy0 and c0.body.Position.Y - gy0 > RD.flewHeight + c0.body.Size.Y / 2 then
			return { ok = false, reason = "in_air" }
		end
	end
	local weld = seat:FindFirstChild("SeatWeld")
	-- a dismount in the air - to the console with a trace and to analytics, to see on P8 who dismounted
	if RD.logAirDismount ~= false and c0 and c0.model.Parent and ch0 then
		local gy = groundY(c0.body.Position, { ch0 :: Instance, c0.model })
		if gy and c0.body.Position.Y - gy > RD.flewHeight + c0.body.Size.Y / 2 then
			warn(string.format("[Movement] dismount IN AIR: %s force=%s h=%.0f\n%s", player.Name, tostring(force), c0.body.Position.Y - gy, debug.traceback()))
			if services.Analytics then
				pcall(services.Analytics.custom, player, "dismount_air", math.floor(c0.body.Position.Y - gy), { force = force == true })
			end
		end
	end
	cleanupMount(player)
	if weld then
		weld:Destroy()
	end
	local _, root, hum = character(player)
	if hum then
		hum.Sit = false
	end
	local c = companions[player]
	if root and c and c.model.Parent then
		-- stand next to the dragon, not inside it
		local _, size = c.model:GetBoundingBox()
		root.CFrame = CFrame.new(c.body.Position + c.body.CFrame.RightVector * (size.X / 2 + 2.5) + Vector3.new(0, 1, 0)) * (root.CFrame - root.CFrame.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		if services.AntiCheat then -- a server relocation - a new honest point
			services.AntiCheat.moved(player)
		end
	end
	task.defer(function() -- while flying over the water the dragon grew - rebuild the companion already on the ground
		local data = services.PlayerData.get(player)
		local cc = companions[player]
		local dd = data and data.companion and data.dragons[data.companion]
		if cc and dd and cc.sig ~= signature(dd) and not mounted[player] then
			Movement.refresh(player)
		end
	end)
	return { ok = true }
end

-- the owner client sees that the solid companion cannot reach
-- the leash target (stuck on the way - "far", lying belly-down on a terrace edge - "high"). The new spot - as on join, only free and
-- level (spawnCFrame strict: to the side of the player, not behind the back in the camera); a relocation in an arc (the body anchored for a while, the network with the server, like warp)
local RG = D.regroup
local regroupAt: { [Player]: number } = {}
function Movement.regroup(player: Player, why: string?, vx: number?, vz: number?): { ok: boolean, reason: string?, [string]: any }
	if mounted[player] then
		return { ok = false, reason = "riding" }
	end
	local c = companions[player]
	if not c or not c.model.Parent or c.stage < 1 then
		return { ok = false, reason = "no_dragon" }
	end
	if c.busy then
		return { ok = false, reason = "not_ready" }
	end
	local ap = c.body:FindFirstChild("FollowPos")
	if not ap or not ap:IsA("AlignPosition") or not ap.Enabled then
		return { ok = false, reason = "not_ready" }
	end
	local now = os.clock()
	if regroupAt[player] and now - regroupAt[player] < RG.serverCooldown then
		return { ok = false, reason = "too_fast" }
	end
	regroupAt[player] = now
	local box, size = c.model:GetBoundingBox()
	local view = if vx and vz and Vector3.new(vx, 0, vz).Magnitude > 0.2 then Vector3.new(vx, 0, vz).Unit else nil
	local at = spawnCFrame(player, size, nil, true, view, RG.dirs)
	if not at then
		c.model:SetAttribute("RegroupMiss", ((c.model:GetAttribute("RegroupMiss") :: number?) or 0) + 1)
		return { ok = false, reason = "no_target" }
	end
	-- the model pivot such that the bounding box center lands at at (as at the build), the rotation - toward the player
	local off = c.model:GetPivot():PointToObjectSpace(box.Position)
	local dest = at.Rotation + (at.Position - at.Rotation * off)
	c.busy = true
	pcall(function()
		c.body:SetNetworkOwner(nil)
	end)
	c.body.Anchored = true
	hopTo(c, function()
		return dest
	end, RG.hopSeconds, math.max(RG.hopMin, size.Y * RG.hopHeight))
	if companions[player] == c and c.model.Parent then
		c.body.Anchored = false
		c.body.AssemblyLinearVelocity = Vector3.zero
		c.body.AssemblyAngularVelocity = Vector3.zero
		setFollow(c, true)
		ap.Position = c.body.AssemblyCenterOfMass -- FollowPos drives the center of mass: the target "in place", without a shift by the center-of-mass offset
		pcall(function()
			c.body:SetNetworkOwner(player)
		end)
		c.model:SetAttribute("Regroups", ((c.model:GetAttribute("Regroups") :: number?) or 0) + 1)
		c.model:SetAttribute("RegroupWhy", why or "-")
	end
	c.busy = false
	return { ok = true }
end

-- into the saddle of companion c (the checks are the caller's: Movement.mount, the regrowRider re-seat onto the grown one)
local function seatOn(player: Player, c: Companion, ch: Model, hum: Humanoid): boolean
	local seat = c.model:FindFirstChild("Saddle", true)
	if not seat or not seat:IsA("Seat") then
		return false
	end
	local stage = D.stages[c.stage + 1]
	setFollow(c, false)
	c.body.CanCollide = true
	setCharacterGroup(ch, "Rider")
	hum.Sit = false
	seat:Sit(hum)
	local st: Mounted = { uid = c.uid, stage = c.stage, speed = stage.speed, lastPos = c.body.Position, lastAt = os.clock(), strikes = 0, rings = {}, seat = seat, occConn = nil }
	mounted[player] = st
	c.model:SetAttribute("Rider", player.UserId)
	player:SetAttribute("Mounted", c.uid)
	pcall(function()
		c.body:SetNetworkOwner(player)
	end)
	st.occConn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil and mounted[player] == st then
			cleanupMount(player)
		end
	end)
	return true
end

-- the companion grew into an adult under the rider. Movement.refresh does not touch the model under the rider (otherwise
-- the rider falls out of the sky), but a teen does not fly - the rider is on the ground: re-seat onto the adult in the same spot, otherwise the banner "Your dragon can
-- fly!" lies until the dismount (and with the golden egg one cannot mount again - Movement.mount glow_raid)
local regrowing: { [Player]: boolean } = {}
local function regrowRider(player: Player)
	if regrowing[player] then
		return
	end
	local st = mounted[player]
	local c = companions[player]
	local data = services.PlayerData.get(player)
	local d = data and st and data.dragons[st.uid]
	if not st or not c or not c.model.Parent or c.uid ~= st.uid or c.busy or st.stage >= 2 or not d or (d.stage or 0) < 2 or data.companion ~= st.uid then
		return
	end
	local ch, root, hum = character(player)
	if not ch or not root or not hum or hum.SeatPart ~= st.seat then
		return
	end
	local gy = groundY(c.body.Position, { ch :: Instance, c.model })
	if not gy or c.body.Position.Y - gy > RD.flewHeight + c.body.Size.Y / 2 then
		return -- in a jump or over a cliff - the next tick
	end
	regrowing[player] = true
	local okAll, errAll = pcall(function()
		local prev = c.body.Position
		local weld = st.seat:FindFirstChild("SeatWeld")
		cleanupMount(player)
		if weld then
			weld:Destroy()
		end
		hum.Sit = false
		buildCompanion(player, d, prev)
		-- while the adult mesh loads, Nest.refresh -> Movement.refresh starts its own build (buildGen) and
		-- ours is cancelled as outdated - wait for a ready adult companion (any build) up to 4 s, then into the saddle
		local c2 = companions[player]
		local waited = 0
		while not (c2 and c2.model.Parent and c2.uid == d.uid and c2.stage >= 2 and not c2.busy) and waited < 4 and player.Parent == Players and not mounted[player] do
			task.wait(0.1)
			waited += 0.1
			c2 = companions[player]
		end
		local ch2, _, hum2 = character(player)
		if c2 and c2.model.Parent and c2.uid == d.uid and c2.stage >= 2 and ch2 and hum2 and not mounted[player] and player.Parent == Players then
			-- seatOn right after lifting from the old saddle: the saddle is occupied, but after 0.1 s the rider falls out (the
			-- "stood up" from the old saddle reaches the humanoid's owner client later). Wait until stood up, seat, a check after 0.6 s, once more
			local w2 = 0
			while (hum2.SeatPart ~= nil or hum2.Sit) and w2 < 1.5 do
				task.wait(0.1)
				w2 += 0.1
			end
			task.wait(0.35)
			for _ = 1, 2 do
				if mounted[player] or not c2.model.Parent or player.Parent ~= Players then
					break
				end
				seatOn(player, c2, ch2, hum2)
				task.wait(0.6)
				local st2 = mounted[player]
				if st2 and hum2.SeatPart == st2.seat then
					break
				end
				if st2 then
					cleanupMount(player)
				end
			end
			if mounted[player] then
				if services.AntiCheat then -- a relocation into the saddle - a new honest point
					services.AntiCheat.moved(player)
				end
				if services.Analytics then
					services.Analytics.custom(player, "regrow_rider", d.stage)
				end
			end
		end
	end)
	if not okAll then
		warn("[Movement] regrow: " .. tostring(errAll))
	end
	regrowing[player] = nil
end

function Movement.mount(player: Player, uid: string): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	-- on the glowing egg raid - on foot
	if services.GlowEgg and services.GlowEgg.raidActive and services.GlowEgg.raidActive(player) then
		if services.Nest then -- on the slope the dragon waits at point D, not at the gate - the words as for rings 1-2
			local GR = Config.Glow and Config.Glow.egg and Config.Glow.egg.raid
			services.Nest.toast(player, if GR and GR.safe == "dragon" then Strings.Raid.gateWait else Strings.GlowEgg.gateWait)
		end
		return { ok = false, reason = "glow_raid" }
	end
	if services.Raid and services.Raid.footOnly and services.Raid.footOnly(player) then -- at a Gloom nest and with a ring-0 egg - on foot
		if services.Nest then
			services.Nest.toast(player, Strings.Raid.gateWait)
		end
		return { ok = false, reason = "raid_foot" }
	end
	if mounted[player] then
		return { ok = false, reason = "riding" }
	end
	if data.companion ~= uid then
		local d = data.dragons[uid]
		return { ok = false, reason = if d then "not_companion" else "no_dragon" }
	end
	local c = companions[player]
	if not c or not c.model.Parent or c.uid ~= uid then
		return { ok = false, reason = "no_dragon" }
	end
	if c.stage < 1 then
		return { ok = false, reason = "needs_juvenile" }
	end
	if c.busy then -- a relocation of a stuck companion is in progress (Movement.regroup), the body is anchored
		return { ok = false, reason = "not_ready" }
	end
	local ch, root, hum = character(player)
	if not ch or not root or not hum then
		return { ok = false, reason = "loading" }
	end
	-- the position through AntiCheat (Nest.rootPos) - a teleport to a distant companion and a mount do not "legalize" the move
	local at = if services.Nest and services.Nest.rootPos then services.Nest.rootPos(player) else root.Position
	if not at or (at - c.body.Position).Magnitude > RD.mountDistance + c.body.Size.Magnitude / 2 then
		return { ok = false, reason = "too_far" }
	end
	local stage = D.stages[c.stage + 1]
	if not seatOn(player, c, ch, hum) then
		return { ok = false, reason = "bad_request" }
	end
	if services.Quest then -- "mounted"
		services.Quest.event(player, "ride")
	end
	if services.Analytics then -- funnel 9
		services.Analytics.onboard(player, "ride_first")
	end
	if not data.onboarding.rode then
		services.PlayerData.update(player, "onboarding", function(o)
			o.rode = true
			return nil
		end)
		services.Nest.toast(player, Strings.Hints.riding)
	end
	return { ok = true, stage = c.stage, fly = stage.fly == true }
end

-- "Back to shore" - the nearest land by rings of rays (Config.World.swim), a teleport of the character onto it
function Movement.shore(player: Player): { ok: boolean, reason: string?, [string]: any }
	if mounted[player] then
		return { ok = false, reason = "riding" }
	end
	local ch, root, hum = character(player)
	if not ch or not root or not hum then
		return { ok = false, reason = "loading" }
	end
	local now = os.clock()
	if shoreAt[player] and now - shoreAt[player] < SW.shoreCooldown then
		return { ok = false, reason = "too_fast" }
	end
	shoreAt[player] = now
	local ignore: { Instance } = { ch }
	local c = companions[player]
	if c and c.model.Parent then
		table.insert(ignore, c.model)
	end
	-- the shore is searched from the honest position (AntiCheat) and only from terrain water - otherwise a client teleport + Shore = a server
	-- relocation anywhere within a radius of 600 (including the closed Frost Isle)
	local from = if services.Nest and services.Nest.rootPos then services.Nest.rootPos(player) else root.Position
	if not from then
		return { ok = false, reason = "loading" }
	end
	if services.AntiCheat and not services.AntiCheat.inWater(from :: Vector3) then
		return { ok = false, reason = "bad_request" }
	end
	local best: RaycastResult? = nil
	local bestD = math.huge
	-- pass 1: only terrain (beach, island) no higher than seaLevel + shoreMaxY - not the tops of the sea pillars (P8 probe 19:41: the player
	-- was carried onto a 36-tall pillar); pass 2 (if there is no terrain in the rings) - any land
	for pass = 1, 2 do
	for _, r in SW.shoreRings do
		for i = 1, SW.shoreRays do
			local a = (i - 1) / SW.shoreRays * math.pi * 2
			local p = Vector3.new(from.X + math.cos(a) * r, from.Y, from.Z + math.sin(a) * r)
			local hit = landBelow(p, ignore)
			if hit and pass == 1 and not (hit.Instance:IsA("Terrain") and hit.Position.Y <= SEA + (SW.shoreMaxY or 14)) then
				hit = nil
			end
			if hit then
				local d = (hit.Position - from).Magnitude
				if d < bestD then
					best, bestD = hit, d
				end
			end
		end
		if best then
			break
		end
	end
	if best then
		break
	end
	end
	if not best then
		return { ok = false, reason = "no_shore" }
	end
	local to = best.Position + Vector3.new(0, SW.shoreLift, 0)
	local face = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	root.AssemblyLinearVelocity = Vector3.zero
	ch:PivotTo(if face.Magnitude > 0.1 then CFrame.lookAt(to, to + face.Unit) else CFrame.new(to))
	if services.AntiCheat then -- a server relocation - a new honest point
		services.AntiCheat.moved(player)
	end
	pcall(function()
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end)
	return { ok = true, distance = math.floor(bestD) }
end

function Movement.setCompanion(player: Player, uid: string): { ok: boolean, reason: string? }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if data.companion == uid then
		return { ok = false, reason = "already" }
	end
	local ok, why = Dragons.setCompanion(data, uid)
	if not ok then
		return { ok = false, reason = why or "no_dragon" }
	end
	services.PlayerData.replicate(player, { "companion" })
	services.Nest.refresh(player) -- the previous companion returns to its spot, the new one leaves it; at the end Nest calls Movement.refresh
	return { ok = true }
end

-- ---------------------------------------------------------------------------------------------- the check and the rings
local function nestRate(data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) } -- 2.1: passes and the boost
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

local function ringPass(player: Player, st: Mounted, from: Vector3, to: Vector3)
	local now = os.clock()
	for _, r in rings do
		if (to - r.center).Magnitude < 60 or (from - r.center).Magnitude < 60 then
			local d0 = (from - r.center):Dot(r.axis)
			local d1 = (to - r.center):Dot(r.axis)
			if (d0 <= 0 and d1 > 0) or (d0 >= 0 and d1 < 0) then
				local t = if d0 ~= d1 then d0 / (d0 - d1) else 0
				local p = from + (to - from) * t
				if (p - r.center).Magnitude <= RINGS.radius and (not st.rings[r.index] or now - st.rings[r.index] >= RINGS.rearmSeconds) then
					st.rings[r.index] = now
					local data = services.PlayerData.get(player)
					if data then
						local coins = math.max(RINGS.rewardMin, math.floor(RINGS.rewardSeconds * nestRate(data)))
						services.Nest.addCoins(player, coins)
						services.Net.notice(player, { kind = "ring", ring = r.index, n = coins, at = r.center })
						services.Net.notice(player, { kind = "coins", n = coins, from = r.center })
						if services.Reward then -- 2.4: the daily "Fly through 5 wind rings"
							if services.Quest then -- through Quest (quest 29 "Tidal winds")
								services.Quest.event(player, "ring")
							else
								services.Reward.event(player, "ring")
							end
						end
						if not data.onboarding.ring then
							services.PlayerData.update(player, "onboarding", function(o)
								o.ring = true
								return nil
							end)
						end
					end
				end
			end
		end
	end
end

local function check()
	local now = os.clock()
	for player, st in mounted do
		local c = companions[player]
		local ch, root, hum = character(player)
		if st.stage < 2 and not regrowing[player] then -- the teen under the rider grew - re-seat onto the adult (regrowRider)
			local data = services.PlayerData.get(player)
			local d = data and data.dragons[st.uid]
			if d and (d.stage or 0) >= 2 then
				task.defer(regrowRider, player) -- after the mounted pass (the re-seat changes the table)
			end
		end
		if not c or not c.model.Parent or not ch or not hum or hum.SeatPart ~= st.seat then
			cleanupMount(player)
			continue
		end
		local pos = c.body.Position
		local dt = math.max(now - st.lastAt, 0.05)
		local delta = pos - st.lastPos
		if st.stage < 2 then
			delta = Vector3.new(delta.X, 0, delta.Z) -- mounted on the ground: a fall off a ledge is not a violation
		end
		local speed = delta.Magnitude / dt
		local cap = if st.stage >= 2 then math.max(FL.maxSpeedCheck, st.speed * RD.checkSlack) else st.speed * RD.checkSlack
		local tooHigh = pos.Y > FL.ceiling + RD.ceilingSlack
		-- the flight anti-cheat is minimal: no braking or rollbacks for speed (a dive, acceleration, a network jerk overspeed honest players);
		-- a rollback only for an obvious hack - a speed above grossMult x cap for grossStreak measurements in a row (Config.Dragon.ride.anticheat); the height
		-- ceiling - the world boundary, a soft clamp without a jerk. on = false - not even that
		local AC = RD.anticheat or { on = true, grossMult = 3, grossStreak = 2 }
		local gross = AC.on ~= false and speed > cap * (AC.grossMult or 3) and not tooHigh
		st.soft = if gross then (st.soft or 0) + 1 else 0
		if tooHigh then
			local cf = c.model:GetPivot()
			local capY = FL.ceiling + RD.ceilingSlack - 1
			c.model:PivotTo(CFrame.new(pos.X, capY, pos.Z) * (cf - cf.Position))
			local v = c.body.AssemblyLinearVelocity
			c.body.AssemblyLinearVelocity = Vector3.new(v.X, math.min(v.Y, 0), v.Z)
		elseif gross and (st.soft or 0) >= (AC.grossStreak or 2) then
			st.strikes += 1
			st.soft = 0
			c.model:PivotTo(CFrame.new(st.lastPos) * (c.body.CFrame - c.body.CFrame.Position))
			c.body.AssemblyLinearVelocity = Vector3.zero
			if st.strikes % 10 == 1 then
				warn(string.format("[Movement] %s: speed %.0f > %.0f x%.0f (strike %d)", player.Name, speed, cap, AC.grossMult or 3, st.strikes))
			end
		else
			if st.stage >= 2 then
				ringPass(player, st, st.lastPos, pos)
				if speed > FL.dailyMinSpeed and services.Reward then -- 2.4: the daily "Fly for 2 minutes" - seconds mounted on an adult in motion, in batches
					st.flyAcc = (st.flyAcc or 0) + dt
					if (st.flyAcc :: number) >= 5 then
						st.flyAcc = (st.flyAcc :: number) - 5
						local gy = groundY(pos, { ch, c.model }) -- a batch counts if in the air at the end (riding on the ground is not flight)
						if not gy or pos.Y - gy > RD.flewHeight + c.body.Size.Y / 2 then
							services.Reward.event(player, "flySec", 5)
						end
					end
				end
				local data = services.PlayerData.get(player)
				if data and services.Badges and data.onboarding.flew and not (typeof(data.badges) == "table" and data.badges.flyer) then
					-- Sky Rider also for those who first flew before the badge was created - on any flight
					local gy = groundY(pos, { ch, c.model })
					if not gy or pos.Y - gy > RD.flewHeight + c.body.Size.Y / 2 then
						services.Badges.award(player, "flyer")
					end
				end
				if data and not data.onboarding.flew then
					local gy = groundY(pos, { ch, c.model })
					if not gy or pos.Y - gy > RD.flewHeight + c.body.Size.Y / 2 then
						services.PlayerData.update(player, "onboarding", function(o)
							o.flew = true
							return nil
						end)
						if services.Quest then -- "takeoff"
							services.Quest.event(player, "fly")
						end
						if services.Analytics then -- funnel 12
							services.Analytics.onboard(player, "fly_first")
						end
					end
				end
			end
			st.lastPos = pos
		end
		st.lastAt = now
	end
	-- steam from the mouth of companions: a short breath every breathEvery s
	local LIFE = D.life
	for _, c in companions do
		if c.stage >= 1 and c.model.Parent then
			local breath = c.body:FindFirstChild("Mouth") and (c.body:FindFirstChild("Mouth") :: Instance):FindFirstChild("Breath")
			if breath and breath:IsA("ParticleEmitter") then
				if not c.breathAt then
					c.breathAt = now + math.random(LIFE.breathEvery[1], LIFE.breathEvery[2])
				elseif breath.Enabled and c.breathOff and now >= c.breathOff then
					breath.Enabled = false
					c.breathAt = now + math.random(LIFE.breathEvery[1], LIFE.breathEvery[2])
				elseif not breath.Enabled and now >= c.breathAt then
					breath.Enabled = true
					c.breathOff = now + LIFE.breathSeconds
				end
			end
		end
	end
	-- gliding with the hatchling: in the air longer than glideSeconds
	for player, c in companions do
		if c.stage == 0 then
			local _, _, hum = character(player)
			if hum and hum.FloorMaterial == Enum.Material.Air then
				airSince[player] = airSince[player] or now
				local data = services.PlayerData.get(player)
				if data and not data.onboarding.glided and now - (airSince[player] :: number) >= RD.glideSeconds then
					services.PlayerData.update(player, "onboarding", function(o)
						o.glided = true
						return nil
					end)
					if services.Quest then -- "gliding"
						services.Quest.event(player, "glide")
					end
					if services.Analytics then -- funnel 5
						services.Analytics.onboard(player, "glide_first", { seconds = math.floor(now - (airSince[player] :: number)) })
					end
				elseif data and services.Badges and data.onboarding.glided and now - (airSince[player] :: number) >= RD.glideSeconds
					and not (typeof(data.badges) == "table" and data.badges.glide) then
					services.Badges.award(player, "glide") -- Glider also for those who glided before the badge was created
				end
			else
				airSince[player] = nil
			end
		end
	end
end

-- Studio only (through ServerStorage.LoopDebug, Nest): "mount" | "dismount" | "shore" | "comp" | "regroup" (a relocation without being stuck)
function Movement.debug(player: Player, verb: string, _arg: string): any
	local data = services.PlayerData.get(player)
	if verb == "mount" and data then
		return Movement.mount(player, data.companion or "")
	elseif verb == "dismount" then
		return Movement.dismount(player)
	elseif verb == "shore" then -- a "Back to shore" check
		shoreAt[player] = nil
		return Movement.shore(player)
	elseif verb == "warp" and mounted[player] then -- relocating the mounted pair for probes ("warp 2500x80x0", minus = n)
		-- a client PivotTo is rolled back by the server speed check, so the server relocates and shifts the honest point
		local x, y, z = string.match(string.gsub(_arg, "n", "-"), "^(%-?%d+)x(%-?%d+)x(%-?%d+)$")
		local c = companions[player]
		local st = mounted[player]
		if not c or not st or not x then
			return { ok = false, reason = "bad_request" }
		end
		local to = Vector3.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0)
		pcall(function()
			c.body:SetNetworkOwner(nil)
		end)
		c.model:PivotTo(CFrame.new(to) * (c.body.CFrame - c.body.CFrame.Position))
		c.body.AssemblyLinearVelocity = Vector3.zero
		st.lastPos = to
		st.lastAt = os.clock()
		task.wait(0.15)
		pcall(function()
			c.body:SetNetworkOwner(player)
		end)
		return { ok = true, reason = string.format("%.0f,%.0f,%.0f", c.body.Position.X, c.body.Position.Y, c.body.Position.Z) }
	elseif verb == "land" then -- a landBelow probe ("land x,z")
		-- Nest passes the argument as %w: the format "120x1000", minus - the letter n ("0xn900")
		local x, z = string.match(string.gsub(_arg, "n", "-"), "^(%-?%d+)x(%-?%d+)$")
		local hit = landBelow(Vector3.new(tonumber(x) or 0, 50, tonumber(z) or 0), { player.Character :: Instance })
		return { ok = hit ~= nil, reason = if hit then string.format("%s y=%.1f %s", hit.Instance.Name, hit.Position.Y, hit.Material.Name) else "water" }
	elseif verb == "regroup" then -- a probe of the companion relocation without being stuck
		return Movement.regroup(player, "far")
	elseif verb == "dupguard" then -- how many extra models the safeguard deleted since the server start
		return { ok = true, reason = tostring(Movement.dupCount()) }
	elseif verb == "comp" then
		local c = companions[player]
		return { ok = c ~= nil, reason = if c then string.format("%s s%d at %.0f,%.0f,%.0f mounted=%s", c.uid, c.stage, c.body.Position.X, c.body.Position.Y, c.body.Position.Z, tostring(mounted[player] ~= nil)) else "none" }
	end
	return { ok = false, reason = "bad_request" }
end

function Movement.init(s: { [string]: any })
	services = s
end

-- ---------------------------------------------------------------------------------------------- the safeguard: a dragon has one model
-- whatever path built
-- the extra model (a build race on a fresh server, add. 2.16, or an unknown one), every DG.every s one remains: in Companions - only
-- the registered companion; in the nest - not the companion, present in nestOrder, once (the slot = the index in nestOrder); the Dragon tag right in
-- Workspace - an ownerless blank. The extras are deleted and written to the DupLog_v1 journal (the DataStore, once a minute) - the path will be found by the journal.
local DG = { every = 3, flush = 60, cap = 300 }
local dupBuffer: { string } = {}
local dupLogged = 0

local function dupNote(player: Player?, where: string, x: Instance, why: string)
	local line = string.format("%s v%d u%s %s %s %s", os.date("!%H:%M:%S"), game.PlaceVersion, if player then tostring(player.UserId) else "-", where, tostring(x:GetAttribute("Uid")), why)
	warn("[Dup] " .. line)
	if #dupBuffer < 50 then
		table.insert(dupBuffer, line)
	end
	dupLogged += 1
end

local function dupGuard()
	if not folder then
		return
	end
	for _, player in Players:GetPlayers() do
		local c = companions[player]
		for _, x in folder:GetChildren() do
			if x:GetAttribute("OwnerId") == player.UserId and (not c or x ~= c.model) then
				dupNote(player, "Companions", x, "not_registered")
				x:Destroy()
			end
		end
		local data = services.PlayerData.get(player)
		local nest = services.Nest and services.Nest.of(player)
		local df = nest and nest:FindFirstChild("Dragons")
		if data and df then
			local kept: { [string]: boolean } = {}
			for _, x in df:GetChildren() do
				local uid = x:GetAttribute("Uid")
				if x:IsA("Model") and typeof(uid) == "string" then
					local idx = table.find(data.nestOrder, uid)
					local why = if uid == data.companion then "companion_copy"
						elseif not idx or not data.dragons[uid] then "not_in_nest"
						elseif kept[uid] or x:GetAttribute("Slot") ~= idx then "repeat"
						else nil
					if why then
						dupNote(player, "Nest", x, why)
						x:Destroy()
					else
						kept[uid] = true
					end
				end
			end
		end
	end
	for _, x in workspace:GetChildren() do
		if x:IsA("Model") and CollectionService:HasTag(x, "Dragon") then
			dupNote(nil, "Workspace", x, "stray")
			x:Destroy()
		end
	end
end

local function dupFlush()
	if #dupBuffer == 0 or RunService:IsStudio() then
		dupBuffer = {}
		return
	end
	local batch = dupBuffer
	dupBuffer = {}
	pcall(function()
		local ds = game:GetService("DataStoreService"):GetDataStore("DupLog_v1")
		ds:UpdateAsync("dup_" .. os.date("!%Y%m%d"), function(old: any)
			local list = if type(old) == "table" then old else {}
			for _, line in batch do
				table.insert(list, line)
			end
			while #list > DG.cap do
				table.remove(list, 1)
			end
			return list
		end)
	end)
end

-- for Studio probes (LoopDebug "dupguard"): how many extra models were deleted since the server start
function Movement.dupCount(): number
	return dupLogged
end

function Movement.start()
	groups()
	local f = Instance.new("Folder")
	f.Name = "Companions"
	f.Parent = workspace
	folder = f
	for _, rg in Layout.windRings() do
		table.insert(rings, { index = rg.index, center = v3(rg.pos), axis = v3(rg.axis).Unit })
	end
	services.Net.handle("Mount", function(player: Player, uid: string)
		return Movement.mount(player, uid)
	end)
	services.Net.handle("Dismount", function(player: Player)
		return Movement.dismount(player)
	end)
	services.Net.handle("Shore", function(player: Player)
		return Movement.shore(player)
	end)
	services.Net.handle("Regroup", function(player: Player, why: string, vx: number?, vz: number?)
		return Movement.regroup(player, why, vx, vz)
	end)
	services.Net.handle("SetCompanion", function(player: Player, uid: string)
		return Movement.setCompanion(player, uid)
	end)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(ch)
			task.defer(function()
				if player.Parent ~= Players then
					return
				end
				local hum = ch:WaitForChild("Humanoid", 10)
				if hum and hum:IsA("Humanoid") then
					hum.Died:Connect(function()
						if mounted[player] then
							Movement.dismount(player, true)
						end
					end)
				end
				task.wait(0.2)
				Movement.refresh(player)
			end)
		end)
		player.CharacterRemoving:Connect(function()
			if mounted[player] then
				cleanupMount(player)
			end
			destroyCompanion(player)
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
		if p.Character then
			task.defer(Movement.refresh, p)
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		cleanupMount(p)
		destroyCompanion(p)
		buildGen[p] = nil
		regroupAt[p] = nil
		if folder then -- this player's orphans too, if any remain
			for _, x in folder:GetChildren() do
				if x:GetAttribute("OwnerId") == p.UserId then
					x:Destroy()
				end
			end
		end
		airSince[p] = nil
	end)
	task.spawn(function() -- the "a dragon has one model" safeguard (add. 2.17 item 4)
		local sinceFlush = 0
		while true do
			task.wait(DG.every)
			local ok, err = pcall(dupGuard)
			if not ok then
				warn("[Movement] dupGuard: " .. tostring(err))
			end
			sinceFlush += DG.every
			if sinceFlush >= DG.flush then
				sinceFlush = 0
				task.spawn(dupFlush)
			end
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= RD.checkTick then
			acc = 0
			local ok, err = pcall(check)
			if not ok then
				warn("[Movement] check: " .. tostring(err))
			end
		end
	end)
end

return Movement
