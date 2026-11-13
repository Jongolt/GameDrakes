-- A cloud test: the distant decor (DecorLod), the second Perf test, Reset by holding - in the published version.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
local L = Config.World.decor.lod
return { placeVersion = game.PlaceVersion, lodOn = L.on, lodLevel = L.level, normal = #L.levels.normal, strong = #L.levels.strong,
	modes = table.concat(Config.Admin.perf.test.modes, ","), resetHold = Config.Admin.resetHold, resetLabel = Strings.Menu.reset,
	decorLodController = ctl ~= nil and ctl:FindFirstChild("DecorLod") ~= nil }
