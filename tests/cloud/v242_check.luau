-- A cloud test: the strings and settings of a set of UI fixes in the published version.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Strings = require(Shared:WaitForChild("Strings"))
local Config = require(Shared:WaitForChild("Config"))
return { hatchGo = Strings.Hints.hatchGo, tooYoung = Strings.Hints.tooYoung, bubblePx = Config.Quests.bubblePx and table.concat(Config.Quests.bubblePx, "x"), bubbleDistance = Config.Quests.bubbleDistance }
