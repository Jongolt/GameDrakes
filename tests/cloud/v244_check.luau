-- A cloud test (spec 02 add. 2.15): the day plate in the Roblox row, the Keeper's callout, Declutter in the client scripts.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local P = Config.UI.phaseBanner
return { phaseTop = P.top, phaseSize = P.width .. "x" .. P.height, says = Config.Quests.says and Config.Quests.says.width, declutter = Config.UI.declutter and Config.UI.declutter.clear, declutterCtl = sps ~= nil and sps:FindFirstChild("Declutter", true) ~= nil }
