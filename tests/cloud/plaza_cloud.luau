-- A cloud test: the plaza of one height (CSG on the server - here only the settings), the terrain under the plaza lowered
-- the SpawnLocation invisible and passable, the 3D hatchling baked into ReplicatedFirst.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local Island = require(RS.Shared:WaitForChild("Core"):WaitForChild("Island"))
local sp = workspace:FindFirstChildWhichIsA("SpawnLocation")
local ld = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingDragon")
local mp = ld and ld:FindFirstChildWhichIsA("MeshPart")
return { placeVersion = game.PlaceVersion, plazaBottom = Config.World.plaza.bottom, sink = Config.World.terraceTerrain.plazaSink.depth,
	plateauCenter = Island.plateau(0, 0), spawnT = sp and sp.Transparency, spawnCollide = sp and sp.CanCollide,
	loadingDragon = mp and (mp.MeshId .. " " .. mp.TextureID) or "none" }
