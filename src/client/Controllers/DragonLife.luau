--!strict
-- "Living" dragons without a skeleton. On the client: body breathing - light vertical swaying and tilt of all anchored dragons
-- within Config.Dragon.life.viewDistance of the camera (nests, showcase);
-- the companion (not anchored) breathes through the leash target (Controllers/Companion), steam from the mouth is switched on by the server (Movement).
-- A local PivotTo of the server's anchored parts is visible only to this client and does not go over the network.
-- "Show other riders' dragons" off - models of foreign nests and
-- companions (OwnerId not own) farther than Config.Dragon.lod.othersKeep studs from the character are hidden only here
-- (LocalTransparencyModifier, labels and effects off) and do not breathe; the own nest and the own companion are always visible. The setting -
-- profile settings.otherDragons (Store); Menu changes it at once through setShowOthers.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Store = require(script.Parent:WaitForChild("Store"))

local DragonLife = {}

local LIFE = Config.Dragon.life
local LOD = Config.Dragon.lod
local bonesCtl: any = nil
local bases: { [Model]: { cf: CFrame, phase: number, height: number } } = {}
local acc = 0
local me = Players.LocalPlayer
local NS = Config.Dragon.noStand
local standAcc = 0
local slid = 0 -- how many times pushed off (Studio probes)
local standRay = RaycastParams.new()
standRay.FilterType = Enum.RaycastFilterType.Include
local showOthers = true
-- hidden foreign models: what was switched off, to restore as it was (labels, effects, light)
local hidden: { [Model]: { [Instance]: boolean } } = {}
local lodAcc = 0

local function setHidden(m: Model, hide: boolean)
	if hide == (hidden[m] ~= nil) then
		return
	end
	if hide then
		local was: { [Instance]: boolean } = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
				was[d] = (d :: any).Enabled
				;(d :: any).Enabled = false
			end
		end
		hidden[m] = was
	else
		local was = hidden[m] or {}
		hidden[m] = nil
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			end
		end
		for d, en in was do
			if d.Parent then
				(d :: any).Enabled = en
			end
		end
	end
end

local function lodPass()
	local ch = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local pos = if root and root:IsA("BasePart") then root.Position else nil
	for _, m in CollectionService:GetTagged("Dragon") do
		if m:IsA("Model") and m.Parent then
			local owner = m:GetAttribute("OwnerId")
			local other = typeof(owner) == "number" and owner ~= me.UserId
			local far = pos ~= nil and (m:GetPivot().Position - pos).Magnitude > LOD.othersKeep
			setHidden(m, other and not showOthers and far)
		end
	end
	for m in hidden do
		if not m.Parent then
			hidden[m] = nil
		end
	end
end

-- the own character stands on a solid dragon part (a ray down from the root) - a push sideways from the dragon's center and slightly up
local function dragonOf(inst: Instance): Model?
	local p: Instance? = inst
	while p and p ~= workspace do
		if p:IsA("Model") and CollectionService:HasTag(p, "Dragon") then
			return p
		end
		p = p.Parent
	end
	return nil
end

local function slideOff()
	local ch = me.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not hum or not root or not root:IsA("BasePart") or hum.Sit or hum.FloorMaterial == Enum.Material.Air then
		return
	end
	local list = CollectionService:GetTagged("Dragon")
	if #list == 0 then
		return
	end
	standRay.FilterDescendantsInstances = list
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -(hum.HipHeight + root.Size.Y / 2 + 1.5), 0), standRay)
	if not hit or not hit.Instance:IsA("BasePart") or not hit.Instance.CanCollide then
		return
	end
	local m = dragonOf(hit.Instance)
	if not m then
		return
	end
	local c = m:GetPivot().Position
	local away = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z)
	if away.Magnitude < 0.2 then
		away = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if away.Magnitude < 0.01 then
		away = Vector3.new(1, 0, 0)
	end
	root.AssemblyLinearVelocity = away.Unit * NS.push + Vector3.new(0, NS.lift, 0)
	slid += 1
end

function DragonLife.showOthers(): boolean
	return showOthers
end

function DragonLife.setShowOthers(on: boolean)
	if on == showOthers then
		return
	end
	showOthers = on
	pcall(lodPass)
end

function DragonLife.isHidden(m: Model): boolean
	return hidden[m] ~= nil
end

function DragonLife.slidCount(): number
	return slid
end

-- for Studio probes: how many foreign models are hidden right now
function DragonLife.hiddenCount(): number
	local n = 0
	for _ in hidden do
		n += 1
	end
	return n
end

local function basePivot(m: Model): { cf: CFrame, phase: number, height: number }?
	local b = bases[m]
	if b then
		return b
	end
	local body = m.PrimaryPart
	if not body or not body.Anchored then
		return nil
	end
	local _, size = m:GetBoundingBox()
	b = { cf = m:GetPivot(), phase = math.random() * math.pi * 2, height = size.Y }
	bases[m] = b
	return b
end

local function step(dt: number)
	acc += dt
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local camPos = cam.CFrame.Position
	local t = os.clock()
	for _, m in CollectionService:GetTagged("Dragon") do
		if m:IsA("Model") and m.Parent and not hidden[m] and m:GetAttribute("Companion") ~= true and not (bonesCtl and bonesCtl.isRigged(m)) then -- with bones DragonBones breathes; hidden ones (P37) do not breathe
			local b = basePivot(m)
			if b and (b.cf.Position - camPos).Magnitude <= LIFE.viewDistance then
				local w = t * LIFE.bobHz * math.pi * 2 + b.phase
				local dy = LIFE.bob * b.height / 15 * math.sin(w)
				m:PivotTo(b.cf * CFrame.new(0, dy, 0) * CFrame.Angles(math.rad(LIFE.pitchDeg) * math.sin(w * 0.5), 0, 0))
			end
		end
	end
	standAcc += dt
	if NS and standAcc >= NS.every then
		standAcc = 0
		slideOff()
	end
	lodAcc += dt
	if lodAcc >= LOD.othersEvery then
		lodAcc = 0
		lodPass()
	end
	if acc > 5 then -- drop records of vanished models
		acc = 0
		for m in bases do
			if not m.Parent then
				bases[m] = nil
			end
		end
	end
end

function DragonLife.init(_snapshot: any, loaded: any)
	bonesCtl = loaded.DragonBones
	local s = Store.get("settings")
	showOthers = not (typeof(s) == "table" and s.otherDragons == false)
end

function DragonLife.start()
	Store.on("settings", function(s: any)
		DragonLife.setShowOthers(not (typeof(s) == "table" and s.otherDragons == false))
	end)
	-- on a nest rebuild the server places a new model: the old base is forgotten together with it
	CollectionService:GetInstanceRemovedSignal("Dragon"):Connect(function(m)
		if m:IsA("Model") then
			bases[m] = nil
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			warn("[DragonLife] " .. tostring(err))
		end
	end)
end

return DragonLife
