-- A cloud test: the "Perf test" experiment in the published version - the modes, the duration, the button strings, the controller.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
local T = Config.Admin.perf.test
return { placeVersion = game.PlaceVersion, modes = table.concat(T.modes, ","), seconds = T.seconds, far = T.far,
	button = Strings.Menu.perfTest, start = Strings.Menu.perfStart, perfController = ctl ~= nil and ctl:FindFirstChild("Perf") ~= nil,
	firstDragon = Config.Balance.firstDragon.growAs }
