-- A cloud test (spec 02 add. 2.14): the settings of the button bypass fixes (the caption above the ring and the pile, Hatch at the incubator).
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local client = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ui = client and client:FindFirstChild("UIKit", true)
return { incubatorGui = Config.UI.incubatorGui.maxDistance, pileGui = Config.UI.pileGui.maxDistance, hatchDistance = Config.Loop.hatchDistance, uikit = ui ~= nil }
