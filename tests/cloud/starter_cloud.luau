-- A cloud test: in the published version the Starter Pack by country - Config.Shop.starter.fixedRarity, the odds ShopCore.starterOdds
-- (the sum 100), the variant without randomness at an empty ctx and random at randomStarter. Read only (grant on a copy of the profile in memory).
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ShopCore = require(Shared:WaitForChild("Core"):WaitForChild("Shop"))
local Strings = require(Shared:WaitForChild("Strings"))
ShopCore.setup(Config.Shop) -- the catalog (in the live game the Shop server builds it)
local o = ShopCore.starterOdds(Config.Balance, Config.Shop)
local sum, parts = 0, {}
for _, r in o.rarity do
	sum += r.pct
	table.insert(parts, string.format("%s %.2f", r.id, r.pct))
end
local function grant(random: boolean)
	local d: any = { coins = 0, eggs = { shelf = {}, incubating = {} }, incubators = 1, owned = {}, items = {}, purchases = {} }
	local g = ShopCore.grant(d, "StarterPack_49", { now = os.time(), B = Config.Balance, S = Config.Shop, elements = Config.Elements, pick = { "frost", "storm" },
		randomStarter = random, rng = function() return 0.00001 end } :: any)
	local t = { "ok=" .. tostring(g.ok), "reason=" .. tostring(g.reason), "random=" .. tostring(g.random) }
	for _, e in d.eggs.shelf do
		table.insert(t, string.format("%s/%s/%s/%s", tostring(e.rarity), tostring(e.shiny), tostring(e.size), tostring(e.element)))
	end
	return table.concat(t, " ")
end
return { placeVersion = game.PlaceVersion, fixedRarity = Config.Shop.starter.fixedRarity, odds = table.concat(parts, ", "), sum = sum,
	fixed = grant(false), random = grant(true), lineFixed = Strings.Shop.lines.StarterPack_49_fixed, oddsTpl = Strings.Shop.starterOdds }
