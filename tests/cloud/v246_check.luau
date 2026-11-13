-- A cloud test (spec 02 add. 2.16): the release number, the card and Declutter controllers are in place, the probe hooks only in Studio.
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
return { placeVersion = game.PlaceVersion, studio = game:GetService("RunService"):IsStudio(), card = sps ~= nil and sps:FindFirstChild("DragonCard", true) ~= nil, declutter = sps ~= nil and sps:FindFirstChild("Declutter", true) ~= nil, debugDelay = workspace:GetAttribute("DebugBuildDelay"), says = Config.Quests.says and Config.Quests.says.width }
