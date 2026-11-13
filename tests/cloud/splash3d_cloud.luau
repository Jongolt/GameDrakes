-- A cloud test: the splash 3D hatchling - the setting and the model id in the published version (the copy itself is put into ReplicatedStorage
-- by the server at the start - Luau Execution does not run the place scripts).
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local Content = require(RS.Shared:WaitForChild("Content"))
local L = Config.UI.splashDragon
return { placeVersion = game.PlaceVersion, element = L.element, stage = L.stage, size = L.size, wait = L.wait, assetId = Content.Assets.dragons[L.element][L.stage + 1] }
