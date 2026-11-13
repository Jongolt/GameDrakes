-- A cloud test: the cladding of the Cliffs facade with mossy boulders (Config.World.island2.rocks.cliffs.clad) and the DecorLayout
-- layout in the published version: how many cladding boulders (large, at the facade) the layout produces.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS.Shared.Config)
local DecorLayout = require(RS.Shared.Core.DecorLayout)
local CL = Config.World.island2.rocks.cliffs.clad
local n = 0
for _, it in DecorLayout.items() do
	if it.h and it.h >= CL.height[1] and it.y and it.z < -320 and it.z > -360 and it.granite then
		n += 1
	end
end
return { placeVersion = game.PlaceVersion, clad = CL and string.format("step %d rows %d height %d-%d protrude %.2f", CL.step, #CL.rows, CL.height[1], CL.height[2], CL.protrude) or "none", cladRocks = n }
