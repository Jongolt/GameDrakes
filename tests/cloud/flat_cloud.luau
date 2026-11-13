-- A cloud test: the flicker at the nest - the terrace plateau at 16.0 (the grass at 18.0), the plaza without tall grass, the floor arrows removed.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local Island = require(RS.Shared:WaitForChild("Core"):WaitForChild("Island"))
local W = Config.World
return { placeVersion = game.PlaceVersion, wallTop = W.terraceTerrain.wallTop, terraceY = W.terrace.y, groundArrows = W.groundArrows,
	plazaGroundMargin = W.island2.plazaGroundMargin, plazaMat = Island.material(10, 10, 16, 0, nil), lotMat = Island.material(115, 0, 16, 0, nil),
	terraceMat = Island.material(100, 60, 16, 0, nil) }
