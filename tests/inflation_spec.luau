--!strict
-- (the Black Deck teardown: new content - "a small inflation, not x2-x3"; spec 05). Run from the repository root:
-- luau tests/inflation_spec.luau
-- Checks: (1) exactly Config.Balance.inflation.rarities rarities, none above Mythic; (2) the multiplier of every update variant
-- (Content.Variants with update) not above maxEventVariantMult and not above shiny; (3) the income ceiling of one dragon (Mythic, Elder, shiny,
-- huge, stormborn, the best available variant) after every update grows not more than ceilingGrowthMax relative to the previous;
-- (4) the dragons of the week (the shop catalog) and of the season (Content.Season) - of an existing rarity and element, without an own income multiplier;
-- (5) the income of a dragon of the week not above an ordinary dragon of the same rarity and stage.
local Config = require("../src/shared/Config")
local Content = require("../src/shared/Content")
local Economy = require("../src/shared/Core/Economy")
local ShopCore = require("../src/shared/Core/Shop")

ShopCore.setup(Config.Shop) -- the catalog is built from Config.Shop (as in Services/Shop)

local B = Config.Balance
local I = B.inflation
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

check("the inflation threshold is set", I ~= nil and I.maxEventVariantMult ~= nil and I.ceilingGrowthMax ~= nil and I.rarities ~= nil)

-- (1) the rarities
check("rarities " .. tostring(I.rarities), #Config.Rarities == I.rarities, #Config.Rarities)
check("Mythic is the top rarity", Config.Rarities[#Config.Rarities] == "Mythic", Config.Rarities[#Config.Rarities])
for _, r in Config.Rarities do
	check("the income is set: " .. r, B.baseIncome[r] ~= nil)
end
for r in B.baseIncome do
	check("the income only for the rarities from the list: " .. r, table.find(Config.Rarities, r) ~= nil)
end

-- (2) the update variants
for id, v in Content.Variants do
	if v.update then
		local m = B.variants[id] and B.variants[id].mult
		check("variant " .. id .. ": the multiplier is set", m ~= nil)
		if m then
			check("variant " .. id .. " <= " .. I.maxEventVariantMult, m <= I.maxEventVariantMult, m)
			check("variant " .. id .. " <= shiny", m <= B.variants.shiny.mult, m)
		end
	end
end

-- (3) the income ceiling by update: 0 - before the first update
local function ceiling(u: number): number
	local best = 1
	for id, vd in B.variants do
		if vd.mult and id ~= "shiny" and id ~= "huge" and id ~= "big" and id ~= "stormborn" then
			local cv = Content.Variants[id]
			local from = if cv then (cv.update or 0) else 0 -- ancient and the variants without a Content entry - from D0
			if from <= u and vd.mult > best then
				best = vd.mult
			end
		end
	end
	local d = { rarity = "Mythic", stage = 3, shiny = true, size = "huge", stormborn = true }
	return Economy.dragonIncome(d :: any, B) * best
end
local prev = ceiling(0)
for u = 1, #Content.Updates do
	local c = ceiling(u)
	check(string.format("income ceiling: update %d (%s) x%.2f <= x%.2f", u, Content.Updates[u].id, c / prev, I.ceilingGrowthMax),
		c / prev <= I.ceilingGrowthMax, c / prev)
	prev = c
end

-- (4) the dragons of the week and the season
local weekly = 0
for _, sku in ShopCore.catalog() do
	if sku.class == "dragonWeek" then
		weekly += 1
		check("week " .. sku.key .. ": the rarity from the list", table.find(Config.Rarities, sku.rarity or "") ~= nil, sku.rarity)
		check("week " .. sku.key .. ": the element from the list", table.find(Config.Elements, sku.element or "") ~= nil, sku.element)
		check("week " .. sku.key .. ": without an own multiplier", (sku :: any).mult == nil and (sku :: any).variant == nil)
		-- (5) the income as an ordinary one of the same rarity
		for stage = 0, 3 do
			local week = Economy.dragonIncome({ rarity = sku.rarity, stage = stage, shiny = false, size = "normal" } :: any, B)
			local plain = Economy.dragonIncome({ rarity = sku.rarity, stage = stage } :: any, B)
			check("week " .. sku.key .. " stage " .. stage .. ": the income as an ordinary one", week == plain, week)
		end
	end
end
check("the dragons of the week are found in the catalog", weekly > 0, weekly)
for i, r in Content.Season.rewards do
	if r.kind == "dragon" then
		check("season, reward " .. i .. ": the rarity from the list", table.find(Config.Rarities, r.rarity or "") ~= nil, r.rarity)
		check("season, reward " .. i .. ": the element from the list", table.find(Config.Elements, r.element or "") ~= nil, r.element)
		check("season, reward " .. i .. ": without an own multiplier", r.mult == nil and r.variant == nil)
	end
end

print(string.format("inflation_spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("inflation_spec: there are failures")
end
