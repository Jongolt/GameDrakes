--!strict
-- Gliding with the hatchling on the shoulder (1.9; 04 §5, 02 §2 0:50-1:00): the character in Freefall, falling, more than
-- Config.Dragon.glide.minHeight studs below it, a stage-0 companion (the CompanionStage attribute) -> LinearVelocity on the HumanoidRootPart:
-- forward glide.forward along the camera look, down glide.down; AlignOrientation keeps the character facing the way. Removed on
-- touching the ground (FloorMaterial), when seated or on death. The toast "Gliding! Steer with the camera" once per session, a sound.
-- The onboarding step glided is set by the server (Movement: Freefall with the hatchling longer than glideSeconds).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Glide = {}

local G = Config.Dragon.glide
local me = Players.LocalPlayer
local banners: any = nil
local gliding = false
local toldOnce = false
local lv: LinearVelocity? = nil
local ao: AlignOrientation? = nil
local att: Attachment? = nil
local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude

local function parts(): (BasePart?, Humanoid?)
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	if r and r:IsA("BasePart") and h and h.Health > 0 then
		return r, h
	end
	return nil, nil
end

local function heightAbove(r: BasePart): number
	local ch = me.Character
	local comps = workspace:FindFirstChild("Companions")
	params.FilterDescendantsInstances = { ch :: Instance, comps :: Instance }
	local hit = workspace:Raycast(r.Position, Vector3.new(0, -500, 0), params)
	local down = if hit then r.Position.Y - hit.Position.Y else 500
	-- at a steep edge a ray straight down hits the edge itself within 1-3 studs -
	-- also measure where the character will be in G.lookAhead s (by the horizontal speed), take the larger height
	local v = r.AssemblyLinearVelocity
	local hv = Vector3.new(v.X, 0, v.Z)
	if G.lookAhead and hv.Magnitude > 2 then
		local hit2 = workspace:Raycast(r.Position + hv * G.lookAhead, Vector3.new(0, -500, 0), params)
		return math.max(down, if hit2 then r.Position.Y - hit2.Position.Y else 500)
	end
	return down
end

local function stop()
	if not gliding then
		return
	end
	gliding = false
	me:SetAttribute("Gliding", nil)
	for _, i in { lv, ao, att } do
		if i then
			i:Destroy()
		end
	end
	lv, ao, att = nil, nil, nil
end

local function start(r: BasePart)
	gliding = true
	me:SetAttribute("Gliding", true)
	local a = Instance.new("Attachment")
	a.Name = "GlideAtt"
	a.Parent = r
	att = a
	local v = Instance.new("LinearVelocity")
	v.Name = "Glide"
	v.Attachment0 = a
	v.RelativeTo = Enum.ActuatorRelativeTo.World
	v.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	v.MaxForce = math.huge
	v.VectorVelocity = Vector3.new(0, -G.down, 0)
	v.Parent = r
	lv = v
	local o = Instance.new("AlignOrientation")
	o.Name = "GlideRot"
	o.Mode = Enum.OrientationAlignmentMode.OneAttachment
	o.Attachment0 = a
	o.RigidityEnabled = true
	o.CFrame = CFrame.lookAt(Vector3.zero, Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z))
	o.Parent = r
	ao = o
	Sounds.play("glide")
	if not toldOnce and banners then
		toldOnce = true
		banners.toast(Strings.Hints.gliding)
	end
end

local function step()
	local r, hum = parts()
	if not r or not hum then
		stop()
		return
	end
	if gliding then
		if hum.FloorMaterial ~= Enum.Material.Air or hum.Sit or me:GetAttribute("Mounted") ~= nil then
			stop()
			return
		end
		local cam = workspace.CurrentCamera
		local look = if cam then Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z) else Vector3.zero
		if look.Magnitude < 0.05 then
			look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
		end
		look = look.Unit
		if lv then
			-- in an updraft (the Updraft attribute from Controllers/Updraft) gliding rises
			lv.VectorVelocity = look * G.forward + Vector3.new(0, if me:GetAttribute("Updraft") then (G.updraftRise or 0) else -G.down, 0)
		end
		if ao then
			ao.CFrame = CFrame.lookAt(Vector3.zero, look)
		end
		return
	end
	if me:GetAttribute("CompanionStage") ~= 0 or me:GetAttribute("Mounted") ~= nil then
		return
	end
	if hum:GetState() ~= Enum.HumanoidStateType.Freefall or hum.FloorMaterial ~= Enum.Material.Air then
		return
	end
	if r.AssemblyLinearVelocity.Y > -4 then
		return
	end
	if heightAbove(r) < G.minHeight then
		return
	end
	start(r)
end

function Glide.isGliding(): boolean
	return gliding
end

function Glide.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
end

function Glide.start()
	me.CharacterAdded:Connect(stop)
	me.CharacterRemoving:Connect(stop)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			stop()
			warn("[Glide] " .. tostring(err))
		end
	end)
end

return Glide
