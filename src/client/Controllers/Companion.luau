--!strict
-- The companion nearby (1.9; 04 §5): the server builds the copy (Services/Movement) and gives network ownership to the owner; this controller
-- runs the leash - once per frame it sets the AlignPosition / AlignOrientation target (a point leash.distance behind the player, height from
-- the ground under the target, the snout along the way or toward the player) - and shows the round `Ride` / `Fly` button above a teen and older
-- (02 §2: "Ride above the dragon") while the player is within Config.Loop.promptDistance and not mounted. The Mount call - the server decides.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(script.Parent:WaitForChild("Net"))


local Companion = {}

local D = Config.Dragon
local LE = D.leash
local RG = D.regroup
local me = Players.LocalPlayer
local current: { model: Model, body: BasePart, size: Vector3, stage: number, uid: string }? = nil
local settle: Vector3? = nil -- the point where the companion stopped while the player is within the leash
local chase: Vector3? = nil -- the last leash target while catching up with the player
local stuck: { why: string, t: number, p: Vector3 }? = nil -- since when and from where the leash target is not reached
local regroupAt = -math.huge
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = true -- ground is only what one stands on (terrain, plates, steps); bushes, trees, fences, signs without collisions do not lift the dragon

local function root(): BasePart?
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function mine(m: Instance): boolean
	return m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Companion") == true
end

local function acquire()
	current = nil
	stuck = nil
	for _, m in CollectionService:GetTagged("Companion") do
		if mine(m) and m:IsA("Model") and m.PrimaryPart then
			local _, size = m:GetBoundingBox()
			current = { model = m, body = m.PrimaryPart :: BasePart, size = size, stage = (m:GetAttribute("Stage") :: number?) or 0, uid = tostring(m:GetAttribute("Uid")) }
			break
		end
	end
end

function Companion.model(): Model?
	local c = current
	return if c and c.model.Parent then c.model else nil
end

function Companion.stage(): number?
	local c = current
	return if c and c.model.Parent then c.stage else nil
end

-- ---------------------------------------------------------------------------------------------- leash
-- the ground top under the body - the maximum of the downward rays
-- at the target center and at four points +-footSpread of the body size along X/Z (with the body rotation), so the paws do not sink into plaza plates and steps
local GROUND_OFFSETS = { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local function groundTop(pos: Vector3, c: { model: Model, body: BasePart, size: Vector3 }): number?
	local ch = me.Character
	params.FilterDescendantsInstances = { ch :: Instance, c.model }
	local rot = c.body.CFrame.Rotation
	local spread = LE.footSpread or 0.35
	local center: number? = nil
	local best: number? = nil
	for i, o in GROUND_OFFSETS do
		local off = rot * Vector3.new(o[1] * c.size.X * spread, 0, o[2] * c.size.Z * spread)
		local from = Vector3.new(pos.X + off.X, pos.Y + c.size.Y, pos.Z + off.Z)
		local hit = workspace:Raycast(from, Vector3.new(0, -(c.size.Y + 80), 0), params)
		if hit then
			if i == 1 then
				center = hit.Position.Y
			end
			if best == nil or hit.Position.Y > best then
				best = hit.Position.Y
			end
		end
	end
	-- the side rays raise the support no higher than footStep above the center (a solid rock or a trunk under the wing lifted the body by 5.7)
	if center and best then
		return math.min(best, center + (LE.footStep or 1))
	end
	return best or center
end

-- the body is solid, the leash does not go around obstacles. "far" - beyond the leash
-- by more than margin, and in seconds it advanced toward the target by less than move (stuck; the speed can still be 15 - trembling in place); "high" - closer than
-- leash + margin, but the bottom above the support is higher than lift for all seconds (lying belly-down on a terrace edge); beyond the leash "high" counts only without progress
-- (on a descent the target is below the body while catching up). Then we ask the server to relocate (Movement.regroup) and send the camera look: the spot is to its side
local function stuckCheck(why: string?, P: Vector3, target: Vector3, far: boolean)
	local now = os.clock()
	if not why or (stuck and stuck.why ~= why) then
		stuck = if why then { why = why, t = now, p = P } else nil
		return
	end
	local s = stuck
	if not s then
		stuck = { why = why, t = now, p = P }
		return
	end
	if now - s.t < RG.seconds then
		return
	end
	local bad = true
	if far then -- beyond the leash (and "high" too): stuck only if not advancing toward the target; within the leash "high" - already after seconds
		local toward = Vector3.new(target.X - s.p.X, 0, target.Z - s.p.Z)
		local moved = Vector3.new(P.X - s.p.X, 0, P.Z - s.p.Z)
		bad = toward.Magnitude > 0.1 and moved:Dot(toward.Unit) < RG.move
	end
	stuck = nil
	if bad and now - regroupAt >= RG.cooldown then
		regroupAt = now
		local cam = workspace.CurrentCamera
		local look = if cam then Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) else Vector3.zero
		local v = if look.Magnitude > 0.05 then look.Unit else Vector3.zero
		task.spawn(Net.call, "Regroup", why, v.X, v.Z)
	end
end

local function follow(dt: number)
	local c = current
	local r = root()
	if not c or not c.model.Parent or not r or c.stage < 1 then
		return
	end
	if me:GetAttribute("Mounted") ~= nil then
		stuck = nil
		return
	end
	local ap = c.body:FindFirstChild("FollowPos")
	local ao = c.body:FindFirstChild("FollowRot")
	if not ap or not ap:IsA("AlignPosition") or not ao or not ao:IsA("AlignOrientation") or not ap.Enabled or c.body.Anchored then
		stuck = nil
		return
	end
	-- FollowPos with ApplyAtCenterOfMass drives the assembly's CENTER OF MASS to the target, not the body; for
	-- the elder it is ~6 studs closer to the head. A "stay where you are" target by body.Position shifted it by this offset every time -
	-- the companion crawled away from the player until the leash limit (the center of mass at leash, the body 6 farther: beyond the Fly button radius, at the entrance -
	-- into the Top Nests board). We measure the same point that the constraint drives
	local P = c.body.AssemblyCenterOfMass
	local R = r.Position
	-- no label close to the camera
	local lbl = c.body:FindFirstChild("Label")
	if lbl and lbl:IsA("BillboardGui") then
		local cam = workspace.CurrentCamera
		lbl.Enabled = cam == nil or (cam.CFrame.Position - P).Magnitude > (LE.labelHideDistance or 12)
	end
	-- on a raid for the glowing egg the server sets GlowWait = a point at the lot gate - the dragon goes there and waits,
	-- snout toward the player; while the pack chases (GlowChase) it hops once per 1.5 s: a beacon where to run. Stuck is not checked
	local waitAt = me:GetAttribute("GlowWait")
	if typeof(waitAt) == "Vector3" then
		settle, chase = nil, nil
		local wv = waitAt :: Vector3
		local wy = groundTop(wv, c)
		local bottomW = c.body.Position.Y - c.body.Size.Y / 2
		local y = if wy then wy + (LE.footClearance or 0.2) + (P.Y - bottomW) else P.Y
		if me:GetAttribute("GlowChase") == true then
			local ph = os.clock() % 1.5
			if ph < 0.5 then -- the leash did not keep up with 2.2 in 0.35 s (swing 0.8) - higher and longer
				y += 4 * math.sin(ph / 0.5 * math.pi)
			end
		end
		ap.Position = Vector3.new(wv.X, y, wv.Z)
		local toW = Vector3.new(wv.X - P.X, 0, wv.Z - P.Z)
		local faceW = if toW.Magnitude > 1 then toW else Vector3.new(R.X - P.X, 0, R.Z - P.Z)
		if faceW.Magnitude > 0.05 then
			ao.CFrame = CFrame.lookAt(Vector3.zero, faceW.Unit)
		end
		stuck = nil
		return
	end
	local leash = LE.distance + c.size.Z * 0.5
	local flat = Vector3.new(P.X - R.X, 0, P.Z - R.Z)
	local dist = flat.Magnitude
	-- the "move away if the player is close" rule is removed; nearby the dragon stands
	-- breathes (bob) and turns its snout toward the player
	if settle and (settle - P).Magnitude > 6 then
		settle = nil -- the server moved the companion (teleport, rebuild): accept the new spot, do not pull toward the old one
	end
	local target = settle or P
	local moving = false
	if dist > leash then
		target = R + flat.Unit * leash
		settle = nil
		chase = target
		moving = true
	elseif not settle then
		-- caught up - stand at the leash point, not where inertia carried it (P8: after walking the elder stopped ~4 studs
		-- closer and its nose ended up in the camera behind the player); stood without catching up (join, the player came by himself) - in place
		settle = if chase and (chase - P).Magnitude <= 6 then chase else P
		chase = nil
		target = settle :: Vector3
	end
	local gy = groundTop(target, c)
	local LIFE = D.life
	local t = os.clock()
	local rigged = c.body:FindFirstChildWhichIsA("Bone") ~= nil -- with bones it breathes with the chest (DragonBones), the body is not rocked
	local breathe = if rigged then 0 else LIFE.bob * c.size.Y / 15 * math.sin(t * LIFE.bobHz * math.pi * 2)
	-- FollowPos (ApplyAtCenterOfMass) drives the CENTER OF MASS to the target, and the center of mass is below the bounding box center
	-- (by ~1.1 for the elder), so the target for the center of mass is: ground top + footClearance + (center of mass - body bottom);
	-- the body is a MeshPart, stands straight
	local bottom = c.body.Position.Y - c.body.Size.Y / 2
	local y = (if gy then gy + (LE.footClearance or 0.2) + (P.Y - bottom) else P.Y) + breathe
	if math.abs(y - P.Y) > 2 then
		moving = moving or dist > leash
	end
	ap.Position = Vector3.new(target.X, y, target.Z)
	-- "high" and in the band leash..leash+margin (at the stair bottom the center of mass 20.9-22.5 at leash 20.5, the bottom 2-3.5 above the support)
	stuckCheck(if dist > leash + RG.margin then "far" elseif gy and P.Y - y > RG.lift then "high" else nil, P, target, dist > leash)
	local face = if moving and (target - P).Magnitude > 0.5 then Vector3.new(target.X - P.X, 0, target.Z - P.Z) else Vector3.new(R.X - P.X, 0, R.Z - P.Z)
	if face.Magnitude > 0.05 then
		ao.CFrame = CFrame.lookAt(Vector3.zero, face.Unit) * CFrame.Angles(if rigged then 0 else math.rad(LIFE.pitchDeg) * math.sin(t * LIFE.bobHz * math.pi * 2), 0, 0)
	end
end

-- ---------------------------------------------------------------------------------------------- the Ride / Fly button
-- the button moved into the HUD at the bottom center.
-- Here only "the companion is nearby": stage >= 1, not mounted, within promptDistance + a third of the size
function Companion.near(): (string?, number?)
	local c = current
	local r = root()
	if not c or not c.model.Parent or not r or c.stage < 1 or me:GetAttribute("Mounted") ~= nil then
		return nil, nil
	end
	if (c.body.Position - r.Position).Magnitude <= Config.Loop.promptDistance + c.size.Magnitude * 0.35 then
		return c.uid, c.stage
	end
	return nil, nil
end

function Companion.init(_snapshot: any, _loaded: any)
end

function Companion.start()
	acquire()
	CollectionService:GetInstanceAddedSignal("Companion"):Connect(function()
		task.defer(acquire)
	end)
	CollectionService:GetInstanceRemovedSignal("Companion"):Connect(function()
		task.defer(acquire)
	end)
	me.CharacterAdded:Connect(function()
		settle = nil
		chase = nil
		task.delay(0.5, acquire)
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(follow, dt)
		if not ok then
			warn("[Companion] " .. tostring(err))
		end
	end)
end

return Companion
