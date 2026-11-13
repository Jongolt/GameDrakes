-- A cloud test (spec 04 add. 2.7 + 2.9): in the published version the Springs baths are on, the mesh asset loads by the place
-- server, the Springs egg spots on the rims, meadow_6 moved, the gate - the curtain (the settings).
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local Core = RS.Shared:WaitForChild("Core")
local SS = require(Core:WaitForChild("SpringsShape"))
local Layout = require(Core:WaitForChild("Layout"))
local SM = Config.World.springsMesh
local out = { placeVersion = game.PlaceVersion, enabled = SM and SM.enabled, assetId = SM and SM.assetId, basins = #SS.basins, gate = SM and SM.gate and SM.gate.needsStage }
local nS, m6 = 0, nil
for _, p in Layout.eggPoints() do
	if p.zone == "Springs" then
		nS += 1
	elseif p.id == "meadow_6" then
		m6 = p.pos[1] .. "," .. p.pos[3]
	end
end
out.springsPoints, out.meadow6 = nS, m6
local ok, c = pcall(function()
	return game:GetService("InsertService"):LoadAsset(SM.assetId)
end)
out.loadOk = ok
if ok and c then
	local n, known = 0, 0
	for _, d in c:GetDescendants() do
		if d:IsA("MeshPart") then
			n += 1
			if (SS.nodes :: any)[d.Name] then
				known += 1
			end
		end
	end
	out.meshParts, out.known = n, known
	c:Destroy()
end
return out
