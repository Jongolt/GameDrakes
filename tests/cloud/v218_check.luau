-- A cloud test (spec 05 add. 2.18 + the performance pass): the firstborn rule in the published core, the decor light,
-- the detail field of the measurement. Run: python3 cloud_test.py v218_check [--version N]
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Core = Shared:WaitForChild("Core")
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local B = Config.Balance
local inv = { dragons = {}, nestOrder = {}, nextUid = 1 }
local f = Dragons.fromEgg(inv :: any, { element = "frost", rarity = "Rare", shiny = false, size = "normal" }, 1000, false, B, true)
local n = Dragons.fromEgg(inv :: any, { element = "frost", rarity = "Rare", shiny = false, size = "normal" }, 1000, false, B, false)
local args = Remotes.List.Perf.args
return {
	placeVersion = game.PlaceVersion,
	firstGrowAs = f.growAs, firstSecs = (f.stageEndsAt or 0) - 1000, firstFeed = Economy.feedPrice(f :: any, 0, B),
	otherGrowAs = tostring(n.growAs), otherSecs = (n.stageEndsAt or 0) - 1000,
	lightsPerModel = Config.World.decor.lightsPerModel, perfDetailArg = args[#args].name,
}
