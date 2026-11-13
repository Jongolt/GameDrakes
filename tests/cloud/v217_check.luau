-- A cloud test (spec 02 add. 2.17): signs instead of buttons in the world, the Feed All distance, the splash summary strings.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
return { placeVersion = game.PlaceVersion, worldActionButtons = Config.UI.worldActionButtons, feedDistance = Config.Loop.feedDistance, eggsReady = Strings.Loading.eggsReady }
