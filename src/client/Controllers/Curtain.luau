--!strict
-- The water curtain of the Springs. The server builds the curtain in the arch
-- (WorldBuilder.buildSpringsCurtain, a folder tagged SpringsCurtain: jets Strip1..N, a barrier in the Curtain group - cannot pass on foot,
-- riders pass). On the own client: a companion of stage >= NeedsStage and the player closer than partNear to the arch - the jets part toward the pillars
-- and melt (the "grow a dragon" key is clear without text); otherwise the curtain is closed. Visual only - the server changes nothing.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Curtain = {}

local SM = Config.World.springsMesh
local GC = SM and SM.gate
local opened: { [Instance]: boolean } = {}

local function setOpen(f: Instance, open: boolean)
	if opened[f] == open then
		return
	end
	opened[f] = open
	local center = f:GetAttribute("Center")
	local cz = if typeof(center) == "Vector3" then center.Z else 0
	local info = TweenInfo.new(if open then 1.1 else 0.8, Enum.EasingStyle.Sine)
	for _, h in f:GetChildren() do
		if h:IsA("BasePart") and string.sub(h.Name, 1, 5) == "Strip" then
			local baseZ = h:GetAttribute("BaseZ")
			if typeof(baseZ) == "number" then
				local side = if baseZ >= cz then 1 else -1
				local z = if open then cz + side * (math.abs(baseZ - cz) + 3.2) else baseZ
				TweenService:Create(h, info, { CFrame = CFrame.new(h.Position.X, h.Position.Y, z) }):Play()
			end
			for _, b in h:GetChildren() do
				if b:IsA("Beam") then
					local w0, w1 = b:GetAttribute("W0"), b:GetAttribute("W1")
					if typeof(w0) == "number" and typeof(w1) == "number" then
						local k = if open then 0.35 else 1
						TweenService:Create(b, info, { Width0 = w0 * k, Width1 = w1 * k }):Play()
					end
				end
			end
		end
	end
end

function Curtain.init(_controllers: { [string]: any }) end

function Curtain.start()
	if not GC then
		return
	end
	task.spawn(function()
		local me = Players.LocalPlayer
		while true do
			task.wait(0.25)
			local ch = me.Character
			local root = ch and ch:FindFirstChild("HumanoidRootPart")
			local stage = me:GetAttribute("CompanionStage")
			for _, f in CollectionService:GetTagged("SpringsCurtain") do
				local need = f:GetAttribute("NeedsStage")
				local center = f:GetAttribute("Center")
				local near = root and root:IsA("BasePart") and typeof(center) == "Vector3" and (root.Position - center).Magnitude < (GC.partNear or 32)
				setOpen(f, near == true and typeof(stage) == "number" and typeof(need) == "number" and stage >= need)
			end
		end
	end)
end

return Curtain
