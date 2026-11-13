--!strict
-- Night lights closer to the camera: on the own client only the max lights nearest to the camera
-- within radius glow, the rest go out locally (nothing goes to the server). The day phase - the Phase attribute of ReplicatedStorage.DayCycle,
-- lights are needed in phases with lights = true (Config.World.dayCycle.phases); the server switches them on itself (DayCycle.setLights), the client only trims.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local LightLod = {}

local NL = Config.World.nightLights
local lightPhases: { [string]: boolean } = {}
for _, ph in Config.World.dayCycle.phases do
	lightPhases[ph.id] = ph.lights == true
end

function LightLod.init(_snapshot: any) end

function LightLod.start()
	if not NL or not NL.max then
		return
	end
	task.spawn(function()
		local dc = ReplicatedStorage:WaitForChild("DayCycle", 60)
		while true do
			task.wait(NL.every or 0.5)
			local phase = dc and dc:GetAttribute("Phase")
			local on = typeof(phase) == "string" and lightPhases[phase] == true
			local cam = workspace.CurrentCamera
			local at = cam and cam.CFrame.Position or Vector3.zero
			local list: { { l: Light, d: number } } = {}
			for _, inst in CollectionService:GetTagged("NightLight") do
				if inst:IsA("Light") then
					local p = inst.Parent
					local pos = if p and p:IsA("BasePart") then p.Position elseif p and p:IsA("Attachment") then p.WorldPosition else nil
					if pos then
						table.insert(list, { l = inst, d = (pos - at).Magnitude })
					end
				end
			end
			table.sort(list, function(a, b)
				return a.d < b.d
			end)
			for i, it in list do
				local want = on and i <= NL.max and it.d <= (NL.radius or 160)
				if it.l.Enabled ~= want then
					it.l.Enabled = want
				end
			end
		end
	end)
end

return LightLod
