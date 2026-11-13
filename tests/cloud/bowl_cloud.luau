-- A cloud test: the incubator bowl, the badges, Ascended in the published version - the modules and numbers are in place, the bowl mesh
-- loads via InsertService (3 nodes), the ids of 5 badges, the Ascension tints, placeRadius.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Shape = require(Shared:WaitForChild("Core"):WaitForChild("IncubatorShape"))
local LooksCore = require(Shared:WaitForChild("Core"):WaitForChild("Looks"))
local IM = Config.World.incubatorMesh
local ok, c = pcall(function()
	return game:GetService("InsertService"):LoadAsset(IM.assetId)
end)
local nodes = {}
if ok and c then
	for _, d in c:GetDescendants() do
		if d:IsA("MeshPart") then
			table.insert(nodes, d.Name)
		end
	end
	table.sort(nodes)
end
local badges = 0
for _, b in Content.Badges do
	if (b.id or 0) > 0 then
		badges += 1
	end
end
return string.format("mesh=%s nodes=%s eggY=%.2f wall=%d sparkZone=%.1f place=%.1f badges=%d tints=%d tint7=%s tag=%s",
	tostring(ok), table.concat(nodes, ","), Shape.eggY, IM.wallHeight, IM.sparkZone, Config.Loop.placeRadius, badges,
	#Config.Looks.ascTints, tostring(LooksCore.ascTint({ ascension = 7 }, Config.Looks)), Strings.Looks.ascendedTag)
