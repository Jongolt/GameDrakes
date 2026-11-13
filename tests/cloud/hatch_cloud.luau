-- A cloud test (D5): the hatch scene in the published version - Core/HatchFx and Config.UI.hatchScene are in place,
-- the scene kind by rarity and number, in the server and client sources - holding the egg, the hatchFx event, tracking the hatchling model.
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local HatchFx = require(Shared:WaitForChild("Core"):WaitForChild("HatchFx"))
local HS = Config.UI.hatchScene
local function has(inst: Instance?, text: string): boolean
	return inst ~= nil and inst:IsA("LuaSourceContainer") and string.find((inst :: any).Source, text, 1, true) ~= nil
end
local inc = SSS:FindFirstChild("Incubation", true)
local sf = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local scene = sf and sf:FindFirstChild("HatchScene", true)
local kinds = HatchFx.kind("Common", 1) .. "," .. HatchFx.kind("Common", 2) .. "," .. HatchFx.kind("Uncommon", 3) .. "," .. HatchFx.kind("Rare", 9)
local leg = HatchFx.plan("Legendary", 5, HS)
return string.format("kinds=%s total=%.1f short=%.1f legendEnd=%.2f hold=%.1f cam=%d dof=%.2f incHold=%s fx=%s watch=%s orbit=%s",
	kinds, HS.full.total, HS.short.total, leg.fxEnd, HS.holdSeconds, #HS.camera.angles, HS.dof.far,
	tostring(has(inc, "HatchingEgg")), tostring(has(inc, "hatchFx")), tostring(has(scene, "hideWatch")), tostring(has(scene, "orbitTo")))
