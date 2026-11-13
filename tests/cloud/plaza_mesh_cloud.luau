-- A cloud test (spec 04 add. 2.8): the Old Ash plaza as a mesh - the settings in the published version, the PlazaShape outline, the grass at
-- the rim (Island.material), the mesh asset loads by the place server (InsertService, as in the live game): the nodes and SurfaceAppearance.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local Core = RS.Shared:WaitForChild("Core")
local PS = require(Core:WaitForChild("PlazaShape"))
local Island = require(Core:WaitForChild("Island"))
local PM = Config.World.plazaMesh
local out = { placeVersion = game.PlaceVersion, enabled = PM and PM.enabled, assetId = PM and PM.assetId, importYaw = PM and PM.importYaw,
	radii = #PS.radii, circleTop = PS.circleTop }
local rc = PS.radius(0)
out.matInside = Island.material(rc - 6, 0, 18, 0, nil)
out.matRim = Island.material(rc - 1, 0, 18, 0, nil)
local ok, c = pcall(function()
	return game:GetService("InsertService"):LoadAsset(PM.assetId)
end)
out.loadOk = ok
if ok and c then
	local n, sa, known = 0, 0, 0
	for _, d in c:GetDescendants() do
		if d:IsA("MeshPart") then
			n += 1
			if d:FindFirstChildOfClass("SurfaceAppearance") then
				sa += 1
			end
			if (PS.nodes :: any)[d.Name] then
				known += 1
			end
		end
	end
	out.meshParts, out.withSA, out.known = n, sa, known
	c:Destroy()
else
	out.loadErr = tostring(c)
end
return out
