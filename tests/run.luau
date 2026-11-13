--!strict
-- Unit tests of the pure core (10 §10). Run from the repository root: luau tests/run.luau
-- The modules are required by relative paths; in Roblox the same files live in ReplicatedStorage/Shared.

local Config = require("../src/shared/Config")
local Format = require("../src/shared/Core/Format")
local Rarity = require("../src/shared/Core/Rarity")
local Economy = require("../src/shared/Core/Economy")
local Eggs = require("../src/shared/Core/Eggs")
local Odds = require("../src/shared/Core/Odds")
local Growth = require("../src/shared/Core/Growth")
local Dragons = require("../src/shared/Core/Dragons")
local Layout = require("../src/shared/Core/Layout")
local Island = require("../src/shared/Core/Island")
local SpringsShape = require("../src/shared/Core/SpringsShape") -- the Springs pool cascade
local DragonLook = require("../src/shared/Core/DragonLook")
local DecorLayout = require("../src/shared/Core/DecorLayout")
local Content = require("../src/shared/Content")
local Hints = require("../src/shared/Core/Hints")
local Quests = require("../src/shared/Core/Quests")
local Offline = require("../src/shared/Core/Offline")
local Experiments = require("../src/shared/Core/Experiments")
local NextUp = require("../src/shared/Core/NextUp") -- the line 'what awaits you and when'
local Rewards = require("../src/shared/Core/Rewards")
local RaidLoop = require("../src/shared/Core/RaidLoop") -- the raid rings

local B = Config.Balance
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end
local function near(a: number, b: number, eps: number): boolean
	return math.abs(a - b) <= eps
end
local function makeRng(seed: number): () -> number
	math.randomseed(seed)
	return function()
		return math.random()
	end
end
local function deepcopy(t: any): any -- 'save and load': like JSON in DataStore
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepcopy(v)
	end
	return out
end

-- Format -----------------------------------------------------------------------------------------
check("number 999", Format.number(999) == "999")
check("number 1234", Format.number(1234) == "1.23K", Format.number(1234))
check("number 1.5M", Format.number(1.5e6) == "1.5M")
check("number 100K without losing zeros", Format.number(1e5) == "100K", Format.number(1e5))
check("number 847Qa", Format.number(847e15) == "847Qa")
check("number 6.4Qi", Format.number(6.4e18) == "6.4Qi", Format.number(6.4e18))
check("negative number", Format.number(-2500) == "-2.5K")
check("1 in 1.4 (Common Meadow 70%)", Format.oneIn(0.7) == "1 in 1.4", Format.oneIn(0.7))
check("1 in 4 (Uncommon Meadow 22.5%)", Format.oneIn(0.225) == "1 in 4", Format.oneIn(0.225))
check("1 in 6 (Rare Cliffs 17%)", Format.oneIn(0.17) == "1 in 6", Format.oneIn(0.17))
check("1 in 200 (Mythic Summit)", Format.oneIn(0.005) == "1 in 200", Format.oneIn(0.005))
check("1 in 220 (Legendary Cliffs 0.45%)", Format.oneIn(0.0045) == "1 in 220", Format.oneIn(0.0045))
check("1 in 5,000", Format.oneIn(0.005 * 0.04) == "1 in 5,000", Format.oneIn(0.005 * 0.04))
check("1 in 500,000", Format.oneIn(0.005 * 0.04 * 0.01) == "1 in 500,000", Format.oneIn(0.005 * 0.04 * 0.01))
check("1 in with p=0", Format.oneIn(0) == "-")
check("clock 2:59", Format.clock(179) == "2:59", Format.clock(179))
check("clock 1:02:03", Format.clock(3723) == "1:02:03")
check("clock 0:05", Format.clock(5) == "0:05")
check("negative clock", Format.clock(-5) == "0:00")
check("title", Format.title("ember") == "Ember")
check("rate", Format.rate(72) == "72/s")

-- Rarity -----------------------------------------------------------------------------------------
local meadow = Eggs.rarityTable("Meadow", false, B)
local ch = Rarity.chances(meadow)
check("Meadow odds sum to 1", near(ch.Common + ch.Uncommon + ch.Rare + ch.Epic + ch.Legendary + ch.Mythic, 1, 1e-9))
check("Mythic on Meadow 0", ch.Mythic == 0)
local rng = makeRng(42)
local counts = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
local N = 200000
for _ = 1, N do
	counts[Rarity.roll(meadow, rng)] += 1
end
check("Common about 70%", near(counts.Common / N, 0.70, 0.01), counts.Common / N)
check("Uncommon about 22.5%", near(counts.Uncommon / N, 0.225, 0.01), counts.Uncommon / N)
check("a zero weight never drops", counts.Mythic == 0)
check("an extreme rng gives the last non-zero", Rarity.roll(meadow, function() return 0.9999999999 end) == "Legendary")
check("a negative weight is forbidden", not pcall(Rarity.roll, { { id = "x", weight = -1 } }, rng))
check("luck does not touch zero weights", Rarity.applyLuck(meadow, 2)[6].weight == 0)

-- Economy ----------------------------------------------------------------------------------------
local function inc(r: string, stage: number): number
	return Economy.dragonIncome({ rarity = r, stage = stage }, B)
end
check("Common H/J/A/E = 1/6/30/100", inc("Common", 0) == 1 and inc("Common", 1) == 6 and inc("Common", 2) == 30 and inc("Common", 3) == 100)
check("Rare A = 480", inc("Rare", 2) == 480)
check("Mythic E = 400K", inc("Mythic", 3) == 400000)
check("shiny x big = x6", Economy.variantMult({ rarity = "Common", stage = 0, shiny = true, size = "big" }, B) == 6)
check("huge shiny stormborn = x20", Economy.variantMult({ rarity = "Common", stage = 0, shiny = true, size = "huge", stormborn = true }, B) == 20)
local nest = { { rarity = "Common", stage = 0 }, { rarity = "Common", stage = 1 } }
check("nest CH + CJ = 7/s", Economy.nestRate(nest, { ascension = 0 }, B) == 7)
check("ascension I = x2", Economy.nestRate(nest, { ascension = 1 }, B) == 14)
check("VIP +10%", near(Economy.nestRate(nest, { ascension = 0, vip = true }, B), 7.7, 1e-9))
check("x2 Coins", Economy.nestRate(nest, { ascension = 0, x2 = true }, B) == 14)
check("2 friends +20%", near(Economy.nestRate(nest, { ascension = 0, friends = 2 }, B), 8.4, 1e-9))
check("friends no more than +40%", near(Economy.nestRate(nest, { ascension = 0, friends = 10 }, B), 9.8, 1e-9))
check("index 50% = +10%", near(Economy.nestRate(nest, { ascension = 0, indexPct = 0.5 }, B), 7.7, 1e-9))
check("index 24% = +0", Economy.indexBonus(0.24, B) == 0)
check("storm x2 and boost x2", Economy.nestRate(nest, { ascension = 0, weatherMult = 2, boost = true }, B) == 28)
check("offline: cap 8 h and share 0.25", Economy.offlineEarnings(10, 100 * 3600, B) == 10 * 8 * 3600 * 0.25)
check("offline: 20 minutes", Economy.offlineEarnings(10, 1200, B) == 3000)
check("offline: less than 10 minutes = 0", Economy.offlineEarnings(10, 599, B) == 0)
check("food Common baby = 60 s of income = 60", Economy.feedPrice({ rarity = "Common", stage = 0 }, 0, B) == 60)
check("food minimum 50 with income < 1/s", Economy.feedPrice({ rarity = "Common", stage = 0 }, -0.5, B) == 50)
check("food Rare adult = 60 s of income", Economy.feedPrice({ rarity = "Rare", stage = 2 }, 0, B) == 28800)
check("food takes ascension into account", Economy.feedPrice({ rarity = "Rare", stage = 2 }, 1, B) == 57600)
check("minutes of income", Economy.minutesOfIncome(72, 3) == 12960)
local ladder = { 5e3, 250e3, 12.5e6, 250e6, 5e9, 100e9, 2e12, 40e12, 800e12, 16e15, 320e15, 6.4e18 }
local ladderOk = true
for i, v in ladder do
	if not near(Economy.ascensionCost(i, B), v, v * 1e-9) then
		ladderOk = false
		print("  ascension", i, Economy.ascensionCost(i, B), "expected", v)
	end
end
check("the ascension ladder has 12 steps", ladderOk)
check("ascension I: Adult, 1 element", Economy.ascensionNeed(1, B).stage == 2 and Economy.ascensionNeed(1, B).elements == 1)
check("ascension IV: Elder", Economy.ascensionNeed(4, B).stage == 3)
check("ascension VII: 2 elements", Economy.ascensionNeed(7, B).elements == 2)
check("ascension X: 3 elements", Economy.ascensionNeed(10, B).elements == 3)
check("slots 4/5/6", Economy.slotPrice(3, B) == 2500 and Economy.slotPrice(4, B) == 15000 and Economy.slotPrice(5, B) == 60000) -- (spec 27 sec. 8)
check("the seventh slot is not sold for coins", Economy.slotPrice(6, B) == nil)
check("incubators 2/3", Economy.incubatorPrice(1, B) == 5000 and Economy.incubatorPrice(2, B) == 60000 and Economy.incubatorPrice(3, B) == nil) -- (spec 27 sec. 8)
check("shelf +2 once", Economy.shelfPrice(3, B) == 10000 and Economy.shelfPrice(5, B) == nil)
check("sanctuary steps", Economy.sanctuaryPrice(0, B) == 20000 and Economy.sanctuaryPrice(2, B) == 8e6 and Economy.sanctuaryPrice(3, B) == nil)
check("releasing a Common baby = 120", Economy.releaseRefund({ rarity = "Common", stage = 0 }, B) == 120)
check("pile cap 60 min", Economy.potCap(10, B) == 36000)

-- Eggs -------------------------------------------------------------------------------------------
local function sumw(t: { Rarity.Outcome }): number
	local s = 0
	for _, o in t do
		s += o.weight
	end
	return s
end
for _, z in B.zoneOrder do
	check("odds sum " .. z .. " = 100", near(sumw(Eggs.rarityTable(z, false, B)), 100, 1e-9))
end
check("rare nest Meadow = the Cliffs table", Eggs.rarityTable("Meadow", true, B)[1].weight == 45)
check("rare nest Summit = the boosted table, sum 100", near(sumw(Eggs.rarityTable("Summit", true, B)), 100, 1e-9) and Eggs.rarityTable("Summit", true, B)[6].weight == 1)
local et = Eggs.elementTable("Meadow", B, Config.Elements)
check("Meadow elements: 30+30+10x4 = 100", near(sumw(et), 100, 1e-9) and et[1].weight == 30 and et[3].weight == 30 and et[2].weight == 10)
local rng2 = makeRng(7)
local rc = { Common = 0, Uncommon = 0, Rare = 0, Epic = 0, Legendary = 0, Mythic = 0 }
local sizes = { normal = 0, big = 0, huge = 0 }
local shiny = 0
for i = 1, N do
	local e = Eggs.roll("p" .. i, "Cliffs", false, rng2, B, Config.Elements)
	rc[e.rarity] += 1
	sizes[e.size] += 1
	if e.shiny then
		shiny += 1
	end
end
check("Cliffs Common about 45%", near(rc.Common / N, 0.45, 0.01), rc.Common / N)
check("Cliffs Mythic drops and rarely (0.05%)", rc.Mythic > 0 and rc.Mythic / N < 0.0015, rc.Mythic)
check("Huge about 1%", near(sizes.huge / N, 0.01, 0.002), sizes.huge / N)
check("Big about 5%", near(sizes.big / N, 0.05, 0.004), sizes.big / N)
check("Shiny about 4%", near(shiny / N, 0.04, 0.004), shiny / N)
local noCommon = true
for i = 1, 20000 do
	local e = Eggs.rollGuaranteed("g" .. i, "Cliffs", "Uncommon", rng2, B, Config.Elements)
	if e.rarity == "Common" then
		noCommon = false
	end
end
check("the Uncommon+ guarantee does not give Common", noCommon)
check("the Rare guarantee with the lower ones cut", Eggs.rollGuaranteed("g", "Meadow", "Legendary", function() return 0.999 end, B, Config.Elements).rarity == "Legendary")
check("the guarantee with an element", Eggs.rollGuaranteed("g", "Meadow", "Uncommon", rng2, B, Config.Elements, "moss").element == "moss")
local egg: Eggs.Egg = { id = "e", element = "ember", rarity = "Common", shiny = false, size = "normal", zone = "Meadow", rareNest = false }
check("incubation Common 3 min", Eggs.incubationSeconds(egg, {}, B) == 180)
egg.cold = true
check("cold x1.5", Eggs.incubationSeconds(egg, {}, B) == 270)
check("Fast Incubator x0.6", Eggs.incubationSeconds(egg, { fastIncubator = true }, B) == 162)
check("first egg 3 s", Eggs.incubationSeconds(egg, { firstEgg = true }, B) == 3)
check("cools down after 90 s", Eggs.isCold(91, B) and not Eggs.isCold(90, B))

-- Odds -------------------------------------------------------------------------------------------
check("odds Common Meadow", Odds.oneIn({ zone = "Meadow", rarity = "Common" }, B) == "1 in 1.4")
check("odds Uncommon Meadow", Odds.oneIn({ zone = "Meadow", rarity = "Uncommon" }, B) == "1 in 4")
check("odds Rare Cliffs", Odds.oneIn({ zone = "Cliffs", rarity = "Rare" }, B) == "1 in 6")
check("odds Mythic Summit", Odds.oneIn({ zone = "Summit", rarity = "Mythic" }, B) == "1 in 200")
check("odds Mythic Summit shiny", Odds.oneIn({ zone = "Summit", rarity = "Mythic", shiny = true }, B) == "1 in 5,000")
check("odds Mythic Summit shiny huge", Odds.oneIn({ zone = "Summit", rarity = "Mythic", shiny = true, size = "huge" }, B) == "1 in 500,000")
check("odds Mythic Cliffs 1 in 2,000", Odds.oneIn({ zone = "Cliffs", rarity = "Mythic" }, B) == "1 in 2,000")
check("odds Mythic Springs 1 in 1,000", Odds.oneIn({ zone = "Springs", rarity = "Mythic" }, B) == "1 in 1,000")
check("odds Mythic Meadow impossible", Odds.oneIn({ zone = "Meadow", rarity = "Mythic" }, B) == "-")
check("the Meadow board without Mythic", #Odds.zoneBoard("Meadow", B) == 5 and #Odds.zoneBoard("Summit", B) == 6)

-- Growth -----------------------------------------------------------------------------------------
check("stages Common 240/600/7200/nil", Growth.stageSeconds("Common", 0, B) == 240 and Growth.stageSeconds("Common", 1, B) == 600 and Growth.stageSeconds("Common", 2, B) == 7200 and Growth.stageSeconds("Common", 3, B) == nil)
local t0 = 1_760_000_000
local d: Growth.Grower = { rarity = "Common", stage = 0 }
Growth.start(d, t0, B)
check("timer = the end moment", d.stageEndsAt == t0 + 240)
check("remaining 240", Growth.remaining(d, t0) == 240)
local ok, why = Growth.feed(d, t0, B)
check("food accepted", ok and d.fedUntil == t0 + 300)
check("food: 240 s with x2 for 300 s -> 120", d.stageEndsAt == t0 + 120, d.stageEndsAt)
ok, why = Growth.feed(d, t0 + 10, B)
check("repeated food refused", not ok and why == "already_fed")
local d2: Growth.Grower = { rarity = "Rare", stage = 1 }
Growth.start(d2, t0, B)
Growth.feed(d2, t0, B)
check("food: 2400 s -> 300 accelerated + 1800 = 2100", d2.stageEndsAt == t0 + 2100, d2.stageEndsAt)
local elder: Growth.Grower = { rarity = "Common", stage = 3 }
Growth.start(elder, t0, B)
check("elder without a timer and without food", elder.stageEndsAt == nil and not Growth.feed(elder, t0, B))
check("tick before the deadline does nothing", not Growth.tick(d, t0 + 100, B) and d.stage == 0)
check("tick at the deadline raises the stage", Growth.tick(d, t0 + 120, B) and d.stage == 1)
-- on the transition the food remainder is 180 s: 600 -> 180 accelerated (=360) + 240 = 420
check("the new timer with the food remainder", d.stageEndsAt == t0 + 120 + 420, d.stageEndsAt)
local d3: Growth.Grower = { rarity = "Common", stage = 0 }
Growth.start(d3, t0, B)
check("treat halves the remainder", Growth.treat(d3, t0 + 40, B) and d3.stageEndsAt == t0 + 40 + 100)
check("growNow completes", Growth.growNow(d3, t0 + 50) and Growth.tick(d3, t0 + 50, B) and d3.stage == 1)
-- offline: one stage per join
local d4: Growth.Grower = { rarity = "Common", stage = 0 }
Growth.start(d4, t0, B)
local later = t0 + 10 * 3600
check("offline 10 h: only one stage", Growth.tick(d4, later, B) and d4.stage == 1 and not Growth.tick(d4, later, B) and d4.stageEndsAt == later + 600)
-- the 'save -> load' round trip: the remainder is the same
local d5: Growth.Grower = { rarity = "Uncommon", stage = 1 }
Growth.start(d5, t0, B)
local saved = deepcopy(d5)
local loaded = deepcopy(saved)
check("save round trip: remainder 1200 - 100 elapsed = 1100", Growth.remaining(loaded, t0 + 100) == 1100)
check("to Elder in 3 transitions", (function()
	local x: Growth.Grower = { rarity = "Common", stage = 0 }
	Growth.start(x, t0, B)
	local t = t0
	for _ = 1, 3 do
		t = x.stageEndsAt :: number
		Growth.tick(x, t, B)
	end
	return x.stage == 3 and x.stageEndsAt == nil
end)())
local slot: Growth.Slot = {}
Growth.startIncubation(slot, t0, 180)
check("incubation 180", Growth.incubationRemaining(slot, t0) == 180 and not Growth.isReady(slot, t0))
check("party /2", Growth.party(slot, t0, false, B) and Growth.incubationRemaining(slot, t0) == 90)
check("party once", not Growth.party(slot, t0, true, B))
local slot2: Growth.Slot = {}
Growth.startIncubation(slot2, t0, 180)
check("a friend's party /3", Growth.party(slot2, t0, true, B) and Growth.incubationRemaining(slot2, t0) == 60)
check("hatchNow", Growth.hatchNow(slot2, t0) and Growth.isReady(slot2, t0))
local tier, price = Growth.priceTier(30, Config.Shop)
check("tier <= 1 min = 5", tier == 1 and price == 5)
check("tier 299 s = 9", select(2, Growth.priceTier(299, Config.Shop)) == 9)
check("tier 1200 s = 19", select(2, Growth.priceTier(1200, Config.Shop)) == 19)
check("tier 3600 s = 29", select(2, Growth.priceTier(3600, Config.Shop)) == 29)
check("tier 5000 s = 49", select(2, Growth.priceTier(5000, Config.Shop)) == 49)

-- Dragons ----------------------------------------------------------------------------------------
local inv = Dragons.newInventory()
local function mk(rarity: string, element: string?)
	return Dragons.fromEgg(inv, { element = element or "ember", rarity = rarity, shiny = false, size = "normal" }, t0, false, B)
end
local a = mk("Common")
check("name by element", a.name == "Ember" and a.uid == "d1" and a.stageEndsAt == t0 + 240)
check("the first into the nest and the companion", Dragons.add(inv, a, 3, B) == "nest" and inv.companion == "d1")
local b2 = mk("Common", "moss")
local c = mk("Uncommon", "tide")
Dragons.add(inv, b2, 3, B)
Dragons.add(inv, c, 3, B)
check("three in the nest", #inv.nestOrder == 3 and Dragons.count(inv) == 3)
local weak = mk("Common", "dusk")
check("the weakest - to the sanctuary", Dragons.add(inv, weak, 3, B) == "sanctuary" and not weak.inNest)
local strong = mk("Rare", "storm")
local whereS, evictedS = Dragons.add(inv, strong, 3, B)
check("stronger than the weakest - replaces it", whereS == "swapped" and strong.inNest and not b2.inNest and evictedS == b2)
-- the slot is decided by the potential (rarity x variants), not the current income
do
	local inv2 = Dragons.newInventory()
	local function mk2(rarity: string, element: string, stage: number?)
		local d = Dragons.fromEgg(inv2, { element = element, rarity = rarity, shiny = false, size = "normal" }, t0, false, B)
		d.stage = stage or 0
		return d
	end
	local adultCommon = mk2("Common", "ember", 2) -- 30/s now, potential 1
	local adultUncommon = mk2("Uncommon", "moss", 2) -- 120/s, potential 4
	Dragons.add(inv2, adultCommon, 2, B)
	Dragons.add(inv2, adultUncommon, 2, B)
	inv2.companion = adultUncommon.uid
	check("potential: the rarity income x variants, without the stage", Dragons.potential(adultCommon, B) == 1 and Dragons.potential(mk2("Rare", "tide"), B) == 16)
	local rareBaby = mk2("Rare", "storm") -- 16/s now, potential 16
	local w, ev = Dragons.add(inv2, rareBaby, 2, B)
	check("a Rare baby displaces a Common adult (30/s > 16/s, but potential 1 < 16)", w == "swapped" and ev == adultCommon and rareBaby.inNest and not adultCommon.inNest)
	local commonBaby = mk2("Common", "dusk")
	local w2, ev2 = Dragons.add(inv2, commonBaby, 2, B)
	check("a Common baby with a Rare baby and an Uncommon adult - to the sanctuary", w2 == "sanctuary" and ev2 == nil and not commonBaby.inNest)
	local rareBaby2 = mk2("Rare", "frost")
	local w3 = Dragons.add(inv2, rareBaby2, 2, B)
	check("equal potential: the weaker is the one that gives less now - the second Rare baby does not push out the first", w3 == "sanctuary")
	local shinyRare = Dragons.fromEgg(inv2, { element = "tide", rarity = "Rare", shiny = true, size = "normal" }, t0, false, B)
	local w4, ev4 = Dragons.add(inv2, shinyRare, 2, B)
	check("a shiny Rare (potential 32) displaces an ordinary Rare baby, does not touch the companion", w4 == "swapped" and ev4 == rareBaby and inv2.companion == adultUncommon.uid and adultUncommon.inNest)
	check("the weakest in the nest by potential", (Dragons.weakestInNest(inv2, B, nil) :: any).uid == adultUncommon.uid)
end
check("does not push out the companion", inv.companion == "d1" and a.inNest)
check("sanctuary of 2", #Dragons.sanctuaryList(inv) == 2)
check("the best - Rare", (Dragons.best(inv, B) :: any).uid == strong.uid)
local okm, whym = Dragons.moveToNest(inv, weak.uid, 3)
check("the nest is full", not okm and whym == "nest_full")
check("into the nest with 4 slots", Dragons.moveToNest(inv, weak.uid, 4) and weak.inNest)
local oks, whys = Dragons.moveToSanctuary(inv, "d1", 25)
check("the companion cannot go to the sanctuary", not oks and whys == "companion")
local okc, whyc = Dragons.setCompanion(inv, b2.uid)
check("the companion only from the nest", not okc and whyc == "not_in_nest")
check("changing the companion", Dragons.setCompanion(inv, strong.uid) and inv.companion == strong.uid)
local okr, refund, whyr = Dragons.release(inv, strong.uid, B)
check("releasing the companion is forbidden", not okr and whyr == "companion")
okr, refund = Dragons.release(inv, "d1", B)
check("releasing a Common baby = 120 coins", okr and refund == 120 and inv.dragons["d1"] == nil and not table.find(inv.nestOrder, "d1"))
check("renaming with trimming", Dragons.rename(inv, strong.uid, "  Zap  ", 20) and strong.name == "Zap")
check("a long name is refused", not Dragons.rename(inv, strong.uid, string.rep("x", 21), 20))
check("index key", Dragons.indexKey(strong) == "storm:Rare")
strong.stage = 2
c.stage = 2
check("elements at stage >= 2: two", Dragons.elementsAtStage(inv, 2) == 2)
check("stormborn from a storm", Dragons.fromEgg(inv, { element = "ember", rarity = "Common", shiny = true, size = "big" }, t0, true, B).stormborn == true)
-- 05 Add. 2.18: the firstborn grows and is fed as Common until adult; rarity, income and A->E - its own
do
	local egg = function(r: string) return { element = "frost", rarity = r, shiny = false, size = "normal" } end
	local f = Dragons.fromEgg(inv, egg("Rare"), t0, false, B, true)
	check("firstborn Rare: growAs Common", f.growAs == "Common" and f.rarity == "Rare")
	-- the firstborn timers firstDragon.growMin (Common 4/10), the food price by growAs; 1/3 min
	check("firstborn Rare: H->J by the firstborn timer 60 s", f.stageEndsAt == t0 + 60)
	check("firstborn Rare: food at the Common price (60)", Economy.feedPrice(f :: any, 0, B) == 60)
	check("firstborn Rare: its own income (16)", Economy.dragonIncome(f :: any, B) == 16)
	check("firstborn: the card bar by the firstborn timer", Growth.stageSecondsOf(f :: any, B) == 60)
	f.stage = 1
	Growth.start(f :: any, t0, B)
	check("firstborn Rare: J->A by the firstborn timer 60 s (27.10)", f.stageEndsAt == t0 + 60)
	check("firstborn Rare teen: food at the Common teen price (360)", Economy.feedPrice(f :: any, 0, B) == 360)
	f.stage = 2
	Growth.start(f :: any, t0, B)
	check("firstborn Rare adult: A->E by its own rarity 240 min", f.stageEndsAt == t0 + 240 * 60)
	check("firstborn adult: food at its own price (28800)", Economy.feedPrice(f :: any, 0, B) == 28800)
	local n = Dragons.fromEgg(inv, egg("Rare"), t0, false, B, false)
	check("not a firstborn Rare: no growAs, H->J 15 min", n.growAs == nil and n.stageEndsAt == t0 + 15 * 60)
	local c1 = Dragons.fromEgg(inv, egg("Common"), t0, false, B, true)
	check("firstborn Common: the mark is set, H->J 60 s", c1.growAs == "Common" and c1.stageEndsAt == t0 + 60)
	local c2 = Dragons.fromEgg(inv, egg("Common"), t0, false, B, false)
	check("not a firstborn Common: no mark, H->J 240 s", c2.growAs == nil and c2.stageEndsAt == t0 + 240)
	-- hatch 0:18 -> teen 1:18 without food; food x2 at 0:40 (berries at the stall): teen 0:59, adult 2:29
	local h = Dragons.fromEgg(inv, egg("Uncommon"), 18, false, B, true)
	check("firstborn: food at 0:40 - teen at 0:59", Growth.feed(h :: any, 40, B) and h.stageEndsAt == 40 + 19)
	check("firstborn: teen at 0:59", Growth.tick(h :: any, 59, B) and h.stage == 1)
	check("firstborn: adult at 1:29 (27.10: timer 60 s, fed x2)", h.stageEndsAt == 59 + 30)
	local h2 = Dragons.fromEgg(inv, egg("Uncommon"), 18, false, B, true)
	check("firstborn without food: teen at 1:18, adult at 2:18 (27.10)", Growth.tick(h2 :: any, 78, B) and h2.stage == 1 and h2.stageEndsAt == 78 + 60)
	-- the growth test group B - 3/9 min; the mark only on the firstborn. the test is off (ab.on = false) - we check the mechanism
	-- on a Config copy with ab.on = true; with the test off the B mark is not set and the B timer does not apply
	local Bab = table.clone(B)
	Bab.firstDragon = table.clone(B.firstDragon)
	Bab.firstDragon.ab = table.clone(B.firstDragon.ab)
	Bab.firstDragon.ab.on = true
	local b = Dragons.fromEgg(inv, egg("Rare"), t0, false, Bab, true, "B")
	check("group B firstborn (test on): the growGroup mark, H->J 180 s", b.growGroup == "B" and b.growAs == "Common" and b.stageEndsAt == t0 + 180)
	check("group B firstborn: the card bar 180 s", Growth.stageSecondsOf(b :: any, Bab) == 180)
	b.stage = 1
	Growth.start(b :: any, t0, Bab)
	check("group B firstborn: J->A 540 s", b.stageEndsAt == t0 + 540)
	b.stage = 2
	Growth.start(b :: any, t0, Bab)
	check("group B firstborn adult: A->E by its own rarity 240 min", b.stageEndsAt == t0 + 240 * 60)
	check("the B mark with the test off: the bar by growMin 60 s", Growth.stageSecondsOf({ rarity = "Rare", stage = 0, growAs = "Common", growGroup = "B" } :: any, B) == 60)
	local boff = Dragons.fromEgg(inv, egg("Rare"), t0, false, B, true, "B")
	check("group B with the test off: no mark, H->J 60 s", boff.growGroup == nil and boff.stageEndsAt == t0 + 60)
	local a = Dragons.fromEgg(inv, egg("Rare"), t0, false, B, true, "A")
	check("group A firstborn: no group mark, H->J 60 s", a.growGroup == nil and a.stageEndsAt == t0 + 60)
	local nb = Dragons.fromEgg(inv, egg("Rare"), t0, false, B, false, "B")
	check("not a firstborn with group B: no mark, H->J 15 min", nb.growGroup == nil and nb.stageEndsAt == t0 + 15 * 60)
end


-- ---------------------------------------------------------------------------------------------- Layout (04 §2-5, spec 1.2)
do
	local pivots = Layout.nestPivots()
	check("Layout: 6 petals", #pivots == 6, #pivots)
	local W = Config.World
	local rMid = (W.nests.rInner + W.nests.rOuter) / 2
	for _, pv in pivots do
		local r = math.sqrt(pv.center[1] ^ 2 + pv.center[3] ^ 2)
		check("Layout: the petal centre on the radius " .. pv.angleDeg, near(r, rMid, 0.01), r)
		check("Layout: the petal at the terrace height", pv.center[2] == W.terrace.y)
		-- local +Z (the ledge) faces outward from the centre: the world point z=+55 is farther from the centre than z=-55
		local far = Layout.localToWorld(pv, { 0, 0, 55 })
		local nearP = Layout.localToWorld(pv, { 0, 0, -55 })
		local rFar = math.sqrt(far[1] ^ 2 + far[3] ^ 2)
		local rNear = math.sqrt(nearP[1] ^ 2 + nearP[3] ^ 2)
		check("Layout: the ledge outside, the entrance at the plaza " .. pv.angleDeg, rFar > rNear and near(rFar, rMid + 55, 0.01) and near(rNear, rMid - 55, 0.01), rFar .. "/" .. rNear)
		-- width: local x=28 stays on the radius ~rMid (tangentially)
		local side = Layout.localToWorld(pv, { 28, 0, 0 })
		check("Layout: the width is tangential " .. pv.angleDeg, near(math.sqrt(side[1] ^ 2 + side[3] ^ 2), math.sqrt(rMid ^ 2 + 28 ^ 2), 0.01))
	end
	-- the 60 and 120 degree petals face north (their ledges at z < 0 and |z| greater than at the entrance)
	local p60 = Layout.localToWorld(pivots[2], { 0, 0, 55 })
	check("Layout: petal 60 faces north", p60[3] < 0 and p60[3] < pivots[2].center[3], p60[3])
	local p270 = Layout.localToWorld(pivots[6], { 0, 0, 55 }) -- angle 300: south-east; there is no angle 270 among the six
	check("Layout: petal 300 - the southern half", p270[3] > 0, p270[3])

	local pts = Layout.eggPoints()
	check("Layout: 30 egg points (+1 secret in the Springs grotto with the pools)", #pts == (if W.springsMesh and W.springsMesh.enabled then 31 else 30), #pts)
	local ids, zones = {}, {}
	for _, p in pts do
		check("Layout: id is unique " .. p.id, ids[p.id] == nil)
		ids[p.id] = true
		zones[p.zone] = (zones[p.zone] or 0) + 1
		check("Layout: the point inside the island " .. p.id, Layout.insideIsland(p.pos, 0), p.pos[1] .. "," .. p.pos[3])
		check("Layout: id shorter than 16 " .. p.id, #p.id <= 16)
	end
	check("Layout: Meadow 10 / Cliffs 8 / Springs 6 (+1 grotto) / Summit 6", zones.Meadow == 10 and zones.Cliffs == 8 and zones.Springs == (if W.springsMesh and W.springsMesh.enabled then 7 else 6) and zones.Summit == 6)
	for _, p in pts do
		if p.zone == "Meadow" then
			local r = math.sqrt(p.pos[1] ^ 2 + p.pos[3] ^ 2)
			check("Layout: Meadow outside the terrace " .. p.id, r >= W.terrace.radius + 20 and p.pos[2] == 0, r)
		elseif p.zone == "Summit" then
			local S = W.zones.Summit.center
			local r = math.sqrt((p.pos[1] - S[1]) ^ 2 + (p.pos[3] - S[3]) ^ 2)
			check("Layout: Summit on the ring and the platform " .. p.id, near(r, W.zones.Summit.ring, 0.01) and p.pos[2] == S[2] and r < W.mountain.topRadius, r)
		end
	end

	local rings = Layout.windRings()
	check("Layout: 8 rings", #rings == 8, #rings)
	for i = 2, #rings do
		check("Layout: the rings go up " .. i, rings[i].pos[2] > rings[i - 1].pos[2])
	end
	local S = W.zones.Summit.center
	for _, rg in rings do
		local d = math.sqrt((rg.pos[1] - S[1]) ^ 2 + (rg.pos[3] - S[3]) ^ 2)
		local mr = Layout.mountainRadius(rg.pos[2])
		check("Layout: the ring is not in the mountain " .. rg.index, rg.pos[2] >= S[2] or d >= mr + W.windRings.radius + 4, d .. " vs " .. mr)
		check("Layout: the ring inside the island " .. rg.index, Layout.insideIsland(rg.pos, 0))
	end
	check("Layout: the mountain 90 at the foot, 40 at the top", Layout.mountainRadius(0) == 90 and Layout.mountainRadius(120) == 40)
	check("Layout: the mountain foot within the island bounds", S[3] + W.mountain.baseRadius <= W.islandSize / 2)

	local st = Layout.stairs()
	check("Layout: 6 stairs", #st == 6, #st)
	for _, s2 in st do
		check("Layout: the stairs between the petals " .. s2.angleDeg, (s2.angleDeg - 30) % 60 == 0 and near(s2.length, 36, 0.5), s2.length)
	end
	check("Layout: 4 signs", #Layout.zoneSigns() == 4)
	for _, sg in Layout.zoneSigns() do
		local r = math.sqrt(sg.pos[1] ^ 2 + sg.pos[3] ^ 2)
		check("Layout: the sign outside the terrace " .. sg.zone, r >= W.terrace.radius + 20, r)
	end
	local br = W.zones.Springs.bridge
	check("Layout: the Springs bridge outside the terrace", math.abs(br.x) - 12 >= W.terrace.radius + 10, br.x)
	for _, p in pts do
		if p.zone == "Springs" then
			check("Layout: the Springs point on the platform " .. p.id, p.pos[1] <= br.x - 20 and p.pos[1] >= -W.islandSize / 2 + 30, p.pos[1])
		end
	end
end

-- ---------------------------------------------------------------------------------------------- Layout: polish 1.5
do
	local W = Config.World
	local hills = Layout.hills()
	check("Hills: the count per Config", #hills == W.hills.count, #hills)
	local pts, stairs, signs, paths = Layout.eggPoints(), Layout.stairs(), Layout.zoneSigns(), Layout.paths()
	for i, h in hills do
		check("Hills: inside the island " .. i, Layout.insideIsland({ h.x, 0, h.z }, h.r), h.x .. "," .. h.z)
		check("Hills: outside Springs and Cliffs " .. i, not (h.x - h.r < -190 and h.z > -150 and h.z < 190) and h.z - h.r >= -290) -- C2: the west is allowed outside the Springs strip
		check("Hills: outside the terrace " .. i, math.sqrt(h.x ^ 2 + h.z ^ 2) - h.r >= W.terrace.radius + 20)
		for _, p in pts do
			check("Hills: not under an egg point " .. i .. "/" .. p.id, math.sqrt((h.x - p.pos[1]) ^ 2 + (h.z - p.pos[3]) ^ 2) >= h.r + W.hills.keepFromPoints)
		end
		for _, st in stairs do
			check("Hills: not at the foot of the stairs " .. i, math.sqrt((h.x - st.bottom[1]) ^ 2 + (h.z - st.bottom[3]) ^ 2) >= h.r + W.hills.keepFromStairs)
		end
		for _, sg in signs do
			check("Hills: not under a sign " .. i, math.sqrt((h.x - sg.pos[1]) ^ 2 + (h.z - sg.pos[3]) ^ 2) >= h.r + W.hills.keepFromSigns)
		end
		for _, pa in paths do
			check("Hills: not on a path " .. i, Layout.segDist(h.x, h.z, pa.from, pa.to) >= h.r + W.hills.keepFromPaths)
		end
		check("Hills: the height at the centre = h " .. i, near(Layout.groundHeight(hills, h.x, h.z), h.h, 0.05))
		check("Hills: 0 at the foot " .. i, Layout.groundHeight({ h }, h.x + h.r, h.z) < 1e-6)
	end
	check("Hills: the hills are deterministic", Layout.hills()[1].x == hills[1].x)
	check("Hills: 0 on the plaza", Layout.groundHeight(hills, 0, 0) == 0)
	check("Paths: 4 paths", #paths == #W.paths.routes * (W.paths.parts or 1), #paths) -- each path is a polyline of parts segments
	for _, pa in paths do
		check("Paths: length > 5 " .. pa.zone, pa.length > 5, pa.length)
		check("Paths: inside the island " .. pa.zone, Layout.insideIsland(pa.from, 0) and Layout.insideIsland(pa.to, 0))
	end
	local coins = Layout.coins()
	check("Coins: perRoute x paths", #coins == W.coins.perRoute * #W.paths.routes, #coins)
	local seen = {}
	for _, c in coins do
		check("Coins: id is unique " .. c.id, seen[c.id] == nil)
		seen[c.id] = true
		check("Coins: not on a hill " .. c.id, Layout.groundHeight(hills, c.pos[1], c.pos[3]) < 0.5)
	end
	local rocks = Layout.edgeRocks()
	check("EdgeRocks: present and fewer than count", #rocks > 8 and #rocks <= W.edgeRocks.count, #rocks)
	for _, r in rocks do
		local rad = math.sqrt(r.x ^ 2 + r.z ^ 2)
		local share = rad / Island.coastRadius(math.rad(r.angleDeg)) -- C2: the share of the noisy shore radius
		check("EdgeRocks: at the shore " .. math.floor(r.angleDeg), share >= W.edgeRocks.coastFrom - 0.01 and share <= W.edgeRocks.coastTo + 0.01, share)
		for _, rangeDeg in W.edgeRocks.skipAngles do
			check("EdgeRocks: outside the gap " .. math.floor(r.angleDeg), r.angleDeg < rangeDeg[1] or r.angleDeg > rangeDeg[2])
		end
	end
	check("EdgeRocks: the gap in the west (Springs)", (function()
		for _, r in rocks do
			if r.x < -300 and math.abs(r.z) < 120 then
				return false
			end
		end
		return true
	end)())
end

-- ---------------------------------------------------------------------------------------------- DragonLook (03 §1, §7; 1.6)
do
	check("Look: the stage heights", DragonLook.height(0) == 2.5 and DragonLook.height(1) == 5 and DragonLook.height(2) == 10 and DragonLook.height(3) == 14) -- per the HTTYD video (03 Addendum 2.1)
	check("Look: Big baby x1.35", near(DragonLook.height(0, "big"), 2.5 * 1.35, 1e-9))
	check("Look: Huge teen x1.7", near(DragonLook.height(1, "huge", false), 5 * 1.7, 1e-9))
	check("Look: Huge adult in the nest x1.7", near(DragonLook.height(2, "huge", true), 10 * 1.7, 1e-9))
	check("Look: Huge adult riding - the base", DragonLook.height(2, "huge", false) == 10)
	check("Look: a bad stage fails", not pcall(DragonLook.height, 4))
	for _, el in Config.Elements do
		local pad = DragonLook.padColor(el)
		check("Look: the pad " .. el, #pad == 3 and pad[1] >= 0 and pad[1] <= 255)
		check("Look: the eyes " .. el, #DragonLook.eyeColor(el) == 3)
		for st = 0, 3 do
			local atts = DragonLook.attachments(st)
			check("Look: the eye attachments " .. el .. st, atts.EyeL ~= nil and atts.EyeR ~= nil and atts.EyeL[1] < 0 and atts.EyeR[1] > 0)
			check("Look: the snout in -Z " .. el .. st, atts.EyeL[3] < 0 and atts.TailTip[3] > 0)
			check("Look: the saddle on J/A/E, the shoulder on H " .. el .. st, if st == 0 then atts.Shoulder ~= nil else atts.Saddle ~= nil)
			for _, o in DragonLook.overlays(el, st) do
				check("Look: an overlay at a known attachment " .. el .. st .. o.name, atts[o.at] ~= nil, o.at)
				check("Look: the overlay size in fractions of the height " .. el .. st .. o.name, #o.size == 3 and o.size[2] > 0 and o.size[2] <= 0.4)
			end
		end
		check("Look: the baby body - a texture " .. el, DragonLook.bodyColor(el, 0) == nil)
	end
	check("Look: Ember without overlays (the crest is in the mesh)", #DragonLook.overlays("ember", 2) == 0)
	for _, el in { "frost", "moss", "tide", "storm", "dusk" } do
		if Config.Dragon.overlays then -- the element features are in the models, the overlays are off
			check("Look: " .. el .. " has overlays", #DragonLook.overlays(el, 2) >= 2, #DragonLook.overlays(el, 2))
		end
		check("Look: the adult body " .. el .. " - its own texture (11.10 day)", DragonLook.bodyColor(el, 2) == nil)
		check("Look: " .. el .. " has its own ids J/A/E", Content.Assets.dragons[el][2] ~= Content.Assets.dragons.ember[2] and Content.Assets.dragons[el][4] ~= Content.Assets.dragons.ember[4])
	end
	check("Look: Ember adult - a texture", DragonLook.bodyColor("ember", 2) == nil)
	if Config.Dragon.overlays then
		check("Look: the Dusk stars on the baby back", DragonLook.overlays("dusk", 0)[1].at == "Back")
	end
	if Config.Dragon.overlays then
		check("Look: the Dusk stars on the adult wings", DragonLook.overlays("dusk", 2)[1].at == "WingL")
	end
	local t1, s1 = DragonLook.label({ name = "Spark", rarity = "Rare", shiny = true, size = "huge" })
	check("Look: label HUGE Shiny Rare", t1 == "Spark" and s1 == "HUGE Shiny Rare", s1)
	local _, s2 = DragonLook.label({ name = "Ash", rarity = "Common" })
	check("names: publicNames = false - others see the element name (17.10)", (DragonLook.label({ name = "Bob", rarity = "Rare", element = "ember" }, false)) == "Ember" and (DragonLook.label({ name = "Bob", rarity = "Rare", element = "ember" }, true)) == "Bob")
	check("Look: label Common", s2 == "Common")
	check("Look: the Mythic rarity colour", DragonLook.rarityColor("Mythic")[1] == 235)
	local fL, fR = DragonLook.slotFacing(-20), DragonLook.slotFacing(20)
	check("Look: the left column faces the passage (+x) and the entrance (-z)", fL[1] > 0 and fL[2] < 0)
	check("Look: the right column faces the passage (-x) and the entrance (-z)", fR[1] < 0 and fR[2] < 0)
end

-- ---------------------------------------------------------------------------------------------- DecorLayout
do
	local W = Config.World
	-- ---------------------------------------------------------------------------------------------- Island (C2, Island 2.0)
	do
		local I2 = W.island2
		local rMin, rMax = math.huge, -math.huge
		for deg = 0, 359 do
			local r = Island.coastRadius(math.rad(deg))
			rMin, rMax = math.min(rMin, r), math.max(rMax, r)
		end
		check("Island: the shore radius within R0 +-20%", rMin >= I2.R0 * 0.8 - 0.01 and rMax <= I2.R0 * 1.2 + 0.01, rMin .. ".." .. rMax)
		check("Island: the shore is not a circle", rMax - rMin > I2.R0 * 0.15, rMax - rMin)
		local hills2 = Layout.hills()
		for _, p in Layout.eggPoints() do
			check("Island: the point on land with a margin " .. p.id, Island.onLand(p.pos[1], p.pos[3], 40), Island.landFactor(p.pos[1], p.pos[3]))
		end
		for _, pv in Layout.nestPivots() do
			local far = Layout.localToWorld(pv, { 0, 0, 55 })
			check("Island: the petal on the plateau " .. pv.index, Island.height(hills2, far[1], far[3]) >= W.terraceTerrain.wallTop - 0.01)
		end
		check("Island: the terrain under the plaza is lowered (16.10)", Island.height(hills2, 0, 0) == W.terraceTerrain.wallTop - W.terraceTerrain.plazaSink.depth and Island.height(hills2, 0, W.plaza.radius + 1) == W.terraceTerrain.wallTop)
		for _, st in Layout.stairs() do
			local h = Island.height(hills2, st.bottom[1], st.bottom[3])
			check("Island: the stairs foot at the ground " .. st.index, h >= -0.5 and h <= 3, h)
			local mid = { (st.top[1] + st.bottom[1]) / 2, 0, (st.top[3] + st.bottom[3]) / 2 }
			local hm = Island.height(hills2, mid[1], mid[3])
			check("Island: the steps above the terrain " .. st.index, hm <= W.terrace.y / 2 and hm >= W.terrace.y / 2 - 3, hm)
		end
		for _, p in Layout.eggPoints() do
			if p.zone == "Springs" then
				local h, wl = Island.height(hills2, p.pos[1], p.pos[3])
				if W.springsMesh and W.springsMesh.enabled then -- the point on the basin rim, the terrain does not hide it
					check("Island: the Springs point on the rim/in the grotto " .. p.id, h <= p.pos[2] + 1.3 and wl == nil and (p.secret or SpringsShape.basinAt(p.pos[1], p.pos[3], 0.2) ~= nil), h)
				else
					check("Island: the Springs point on the platform " .. p.id, math.abs(h - I2.springs.y) < 0.01 and wl == nil, h)
				end
			elseif p.zone == "Summit" then
				local h = Island.height(hills2, p.pos[1], p.pos[3])
				check("Island: the Summit point at the top " .. p.id, math.abs(h - I2.summit.top) < 0.01, h)
			elseif p.zone == "Meadow" then
				local h = Island.height(hills2, p.pos[1], p.pos[3])
				check("Island: the Meadow point on the ground " .. p.id, h >= -0.01 and h <= 10, h)
			elseif p.zone == "Cliffs" then
				local h = Island.height(hills2, p.pos[1], p.pos[3])
				check("Island: the Cliffs platform in front of the face " .. p.id, h < p.pos[2] - 10, h)
				local behind = Island.height(hills2, p.pos[1], p.pos[3] - 30)
				check("Island: the ridge behind the platform is higher than it " .. p.id, behind > p.pos[2], behind)
			end
		end
		local lag = I2.springs.lagoon[1]
		local hl, wll = Island.height(hills2, lag.x, lag.z)
		if W.springsMesh and W.springsMesh.enabled then
			-- under the basins a pit below the bottom, no terrain water; the hill in Luau = the generator hill (the rim does not sink into the slope)
			for _, b in SpringsShape.basins do
				local hb, wb = Island.height(hills2, b.x, b.z)
				check("Island: under the basin a pit below the bottom " .. b.name, hb < b.floor - 0.5 and wb == nil, hb)
				local hmax = -99
				for i = 1, #b.rin do
					local a = math.rad((i - 1) * b.step)
					local r = b.rin[i] + SpringsShape.lip + 0.6
					hmax = math.max(hmax, (Island.height(hills2, b.x + r * math.cos(a), b.z - r * math.sin(a))))
				end
				check("Island: the rim above the slope " .. b.name, b.water >= hmax + 0.5, b.water - hmax)
			end
		else
			check("Island: the lagoon under water", hl < 0 and wll == I2.springs.waterLevel, hl)
		end
		local hc, wlc = Island.height(hills2, I2.springs.channel.x, 0)
		check("Island: the channel under water", hc < 0 and wlc == I2.springs.channel.waterLevel, hc)
		local hs, wls = Island.height(hills2, 0, I2.R0 * 1.3)
		check("Island: the sea beyond the shore", hs < I2.seaLevel and wls == I2.seaLevel, hs)
		for _, pa in Layout.paths() do
			local worst = 0
			local t = 0
			local prev = Island.height(hills2, pa.from[1], pa.from[3])
			while t <= pa.length do
				local k = t / pa.length
				local x, z = pa.from[1] + (pa.to[1] - pa.from[1]) * k, pa.from[3] + (pa.to[3] - pa.from[3]) * k
				local h = Island.height(hills2, x, z)
				worst = math.max(worst, math.abs(h - prev))
				prev = h
				t += 4
			end
			check("Island: the path without drops " .. pa.zone, worst <= 4, worst) -- up to 45 degrees per 4 studs (the mountain foot at meadow_8)
		end
		for _, sg in Layout.zoneSigns() do
			local h = Island.height(hills2, sg.pos[1], sg.pos[3])
			check("Island: the sign on the ground " .. sg.zone, h >= -0.5 and h <= 8, h)
		end
		local chunks = Island.chunks()
		check("Island: 200-500 terrain chunks", #chunks >= 200 and #chunks <= 500, #chunks)
		local sl = Island.material(0, I2.cliffs.zFace - 5, 50, 7, nil)
		check("Island: a steep slope - stone", sl == (Config.World.island2.steepMaterial or "Limestone"), sl) -- Rock
		check("Island: a glade - grass", Island.material(0, 250, 2, 0.1, nil) == "Grass")
		local bx, bz = 0, -Island.coastRadius(math.rad(90)) * 0.95 -- a point at 0.95 of the shore radius to the north
		check("Island: a beach - pebbles", Island.material(bx, bz, -1, 0.1, nil) == "Sand", Island.landFactor(bx, bz))
		check("Island: deterministic", Island.coastRadius(1.0) == Island.coastRadius(1.0))
		-- C3: zone islands
		for _, ex in I2.extra do
			local hc = Island.height(hills2, ex.x, ex.z)
			check("Island: zone island " .. ex.id .. " land at the centre", hc >= 0, hc)
			local hp = Island.height(hills2, ex.x + ex.peak.dx, ex.z + ex.peak.dz)
			check("Island: peak " .. ex.id, math.abs(hp - ex.peak.top) < 0.01, hp)
			local hs2, wl2 = Island.height(hills2, (ex.x + I2.R0 * 1.2) / 2, ex.z)
			check("Island: the strait to " .. ex.id .. " - sea", hs2 < I2.seaLevel and wl2 == I2.seaLevel, hs2)
			check("Island: material " .. ex.id .. " snow", Island.material(ex.x, ex.z, 2, 0.1, nil) == ex.top)
			check("Island: the main island is not affected " .. ex.id, Island.extraAt(0, 250) == nil)
		end
	end

	local items = DecorLayout.items()
	check("Decor: 1000-3000 items (C2 x1.8 + stone; 12.10 natural pass +~400)", #items >= 1000 and #items <= 3000, #items)
	check("Decor: deterministic", DecorLayout.items()[5].x == items[5].x)
	local kinds = DecorLayout.kinds()
	check("Decor: 25+ mesh kinds", #kinds >= 25, #kinds)
	for _, k in kinds do
		check("Decor: the height is set " .. k, W.decor.height[k] ~= nil)
		check("Decor: the asset id is in DecorAssets " .. k, Content.Assets.decor[k] ~= nil)
	end
	local pts, paths = Layout.eggPoints(), Layout.paths()
	local trees = 0
	for _, it in items do
		check("Decor: the height is sane " .. it.kind, it.h >= 0.2 and it.h <= (if it.granite and it.sea then 120 elseif it.sea then 60 elseif it.granite or it.kind == "cs_baobab" then 60 elseif string.sub(it.kind, 1, 6) == "ctree_" or string.sub(it.kind, 1, 3) == "cs_" then 50 else 40), it.h) -- C2: sea pillar chunks up to 55; C4: conifers up to 46; C7: the baobab landmark up to 60; the backdrop cliffs up to 120, their pines up to 60
		if it.y == nil then -- on the ground: the height from the table, not on a path, not on a point, not on the terrace
			if not it.granite then -- C2: stone by island2.rocks, its own heights
				check("Decor: the height within the bounds " .. it.kind, it.h >= W.decor.height[it.kind][1] - 1e-6 and it.h <= W.decor.height[it.kind][2] + 1e-6)
			end
			for _, pa in paths do
				if it.kind ~= W.decor.pathStones.kind then
					check("Decor: not on a path " .. it.kind, Layout.segDist(it.x, it.z, pa.from, pa.to) >= W.paths.width / 2 - 0.01)
				end
			end
			for _, p in pts do
				check("Decor: not on an egg point " .. it.kind, math.sqrt((it.x - p.pos[1]) ^ 2 + (it.z - p.pos[3]) ^ 2) >= 4.9)
			end
			check("Decor: outside the terrace " .. it.kind, math.sqrt(it.x ^ 2 + it.z ^ 2) >= W.terrace.radius + 9)
			if not it.sea then
				check("Decor: inside the island " .. it.kind, Layout.insideIsland({ it.x, 0, it.z }, 0) or Island.extraAt(it.x, it.z) ~= nil) -- C7: snowy spruces on Frost Isle
			end
		end
		local isCsTree = string.sub(it.kind, 1, 3) == "cs_" and W.decor.height[it.kind] ~= nil and W.decor.height[it.kind][1] >= 14 and it.kind ~= "cs_vines" -- C7: the cs_ undergrowth and buildings are not trees
		if string.sub(it.kind, 1, 5) == "tree_" or string.sub(it.kind, 1, 6) == "ptree_" or string.sub(it.kind, 1, 6) == "ctree_" or isCsTree then -- own and Creator Store conifers
			trees += 1
		end
	end
	-- a comment at the end of a line 'ate' the bones fields (hubDist and others became nil, DragonBones crashed on P8) - the keys are in place
	for _, k in { "minBones", "retryEvery", "retryMax", "axisX", "hubX", "hubDist", "wingX", "legY", "wingTipY", "flyAbove", "breathDeg", "breathShift", "lookDistance", "yawMax", "pitchMax", "lookSpeed", "idleYawDeg", "tailDeg", "tailHz", "tailFlyDeg", "wingIdleDeg", "wingIdleHz", "wingFlapDeg", "wingLag", "wingGain", "wingDown", "wingSweepDeg", "wingDepthMax", "legTuckDeg", "stepHz", "stepDeg" } do
		check("Config: Dragon.bones." .. k, (Config.Dragon.bones :: any)[k] ~= nil)
	end
	for _, k in { "showAfter", "pollSeconds", "shoreRings", "shoreRays", "shoreAbove", "shoreCooldown", "shoreLift", "shoreMaxY" } do
		check("Config: World.swim." .. k, (Config.World.swim :: any)[k] ~= nil)
	end
	-- Quests: 15 quests, fields, readiness and progress
	local QuestsCore = require("../src/shared/Core/Quests")
local Strings = require("../src/shared/Strings")
	check("Quests: 15 quests", QuestsCore.Total == 15)
	for i, q in QuestsCore.List do
		check("Quests: fields " .. i, q.id == i and #q.title > 0 and #q.text > 0 and q.count >= 1 and (q.reward.coins or q.reward.minutes or q.reward.egg) ~= nil)
		check("Quests: the reward label " .. i, #QuestsCore.rewardText(q, Strings.Quests :: any) > 0)
	end
	local qs = { keeper = { step = 1 }, counters = {} }
	check("Quests: step 1 not ready", not QuestsCore.ready(qs, QuestsCore.get(1) :: any))
	qs.counters.hatch = 1
	check("Quests: step 1 ready", QuestsCore.ready(qs, QuestsCore.get(1) :: any))
	local k9, n9, q9 = QuestsCore.progress({ keeper = { step = 9 }, counters = { eggFound = 3 } })
	check("Quests: progress 3/5", k9 == 3 and n9 == 5 and q9 ~= nil and (q9 :: any).id == 9)
	local kEnd, _, qEnd = QuestsCore.progress({ keeper = { step = 16 }, counters = {} })
	check("Quests: after 15 - empty", qEnd == nil and kEnd == 0)
	check("Quests: Config.Quests keys", Config.Quests.minMinutesReward ~= nil and Config.Quests.chainDelay ~= nil and Config.Quests.panelY ~= nil)
	-- Index: 36 keys, sets, percentages, thresholds
	local IndexCore = require("../src/shared/Core/Index")
	IndexCore.setup(Config.Elements, Config.Rarities)
	check("Index: 36 keys", #IndexCore.keys() == 36 and IndexCore.total() == 36)
	local ix = { ["ember:Common"] = true, ["moss:Common"] = true, keeper = true }
	check("Index: the count without the Keeper", IndexCore.count(ix) == 2)
	local sets = IndexCore.sets()
	check("Index: 7 sets, Meadow of 10", #sets == 7 and sets[1].id == "meadow" and #sets[1].keys == 10)
	local mk, mn = IndexCore.setProgress(ix, sets[1])
	check("Index: Meadow 3/10", mk == 3 and mn == 10)
	local full = {}
	for _, k in sets[2].keys do full[k] = true end
	check("Index: the element set is complete", IndexCore.setComplete(full, sets[2]) and #IndexCore.claimable(full, {}) == 1 and #IndexCore.claimable(full, { [sets[2].id] = 1 }) == 0)
	local b0, bNext, bAt = IndexCore.tier(0.1, B.index.thresholds)
	check("Index: threshold 10% -> 0, then 5% at 25%", b0 == 0 and bNext == 0.05 and bAt == 0.25)
	local b1, bNext1 = IndexCore.tier(1, B.index.thresholds)
	check("Index: 100% -> 25%, nothing further", b1 == 0.25 and bNext1 == nil)
	check("Index: Economy.indexBonus 50% = 10%", near(Economy.indexBonus(0.5, B), 0.10, 1e-9))
	check("Index: Config.Index keys", Config.Index.store ~= nil and Config.Index.minSetReward ~= nil)
	-- Analytics: the config keys and the cohort
	check("Analytics: Config.Analytics keys", Config.Analytics.enabled ~= nil and Config.Analytics.d0 ~= nil and Config.Analytics.deviceEvery ~= nil)
	check("Analytics: d0 in 2026", Config.Analytics.d0 > os.time({ year = 2026, month = 1, day = 1 }))
	check("Decor: 300-900 trees (with the forest wall, C2; C4 without palms; C7: +70 Frost Isle spruces, +19 giants; 13.10 evening: +pines of the 36 pillars and the backdrop)", trees >= 300 and trees <= 900, trees)
	local leafy = DecorLayout.leafyPatches()
	check("Decor: LeafyGrass patches", #leafy == W.leafyPatches.count, #leafy)
end

-- ---------------------------------------------------------------------------------------------- DayCycle (P16)
do
	local DC = Config.World.dayCycle
	local total = 0
	local ids = {}
	for i, ph in DC.phases do
		total += ph.seconds
		ids[ph.id] = true
		check("DayCycle: phase " .. ph.id .. " >= 45 s", ph.seconds >= 45, ph.seconds) -- sunset 45 s
		check("DayCycle: ClockTime grows " .. ph.id, ph.clock[2] > ph.clock[1])
		-- C1: Realistic/Future lighting - Ambient is only the shadow, readability comes from OutdoorAmbient (the sky).
		-- Threshold: the shadow is not black (>= 60 per channel), the sky does not go dark (OutdoorAmbient >= 80) - the night stays readable.
		check("DayCycle: the shadow is not black " .. ph.id, ph.ambient[1] >= 60 and ph.ambient[2] >= 60 and ph.ambient[3] >= 60, table.concat(ph.ambient, ","))
		check("DayCycle: the sky light does not go out " .. ph.id, ph.outdoor[1] >= 80 and ph.outdoor[2] >= 80 and ph.outdoor[3] >= 80, table.concat(ph.outdoor, ","))
		local nxt = DC.phases[(i % #DC.phases) + 1]
		check("DayCycle: the phases join by the clock " .. ph.id, math.abs((ph.clock[2] % 24) - (nxt.clock[1] % 24)) < 0.01, (ph.clock[2] % 24) .. " vs " .. (nxt.clock[1] % 24))
	end
	check("DayCycle: the cycle 6-9 minutes", total >= 360 and total <= 540, total)
	-- bright day is more than half the cycle, the phase from the world time
	local dayS = 0
	for _, ph in DC.phases do
		if ph.id == "day" then
			dayS = ph.seconds
		end
	end
	check("DayCycle: day >= 50% of the cycle (25.10)", dayS / total >= 0.5, dayS / total)
	check("DayCycle: the phase from the world time is on (25.10)", DC.worldClock == true)
	check("DayCycle: four phases", ids.dawn and ids.day and ids.dusk and ids.night)
	check("DayCycle: the start phase exists", ids[DC.startPhase] == true)
end

-- Hints (1.8 part 2) ------------------------------------------------------------------------------
do
	local HC = Config.Hints
	local function snap(over: { [string]: any }): any
		local s = { tableFree = 3, carry = false, ringReady = nil, ringFree = 1, dragons = 0, incubating = 0, pot = 0, coins = 0, feedPrice = nil, eggNear = true, coinsDone = false, eggDone = false, fedDone = false }
		for k, v in over do
			s[k] = if v == "none" then nil else v
		end
		return s
	end
	local g = Hints.goal(snap({}), HC)
	check("hint: start - to the table", g ~= nil and g.kind == "table")
	g = Hints.goal(snap({ carry = true }), HC)
	check("hint: egg in the hands - to incubator 1", g ~= nil and g.kind == "incubator" and g.slot == 1)
	-- 0 dragons, the table empty, a nest nearby - raidFirst
	g = Hints.goal(snap({ tableFree = 0, raidNear = true }), HC)
	check("hint: a newcomer without the table - the first raid (raidFirst)", g ~= nil and g.kind == "raidFirst", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true }), HC)
	check("hint: has a dragon, coins collected - a raid (raid)", g ~= nil and g.kind == "raid", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, pot = 9 }), HC)
	check("hint: pile 9 and not collected yet - coins first (once)", g ~= nil and g.kind == "pile", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, carry = true, carryRaid = 0 }), HC)
	check("hint: a ring 0 raid egg in the hands - run home", g ~= nil and g.kind == "raidHome", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, carry = true, carryRaid = 1, companionStage = 1 }), HC)
	check("hint: a ring 1 egg in the hands, has a teen - to the dragon", g ~= nil and g.kind == "raidDragon", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, carry = true, carryRaid = 1, mounted = true }), HC)
	check("hint: riding with a raid egg - home riding", g ~= nil and g.kind == "raidRide", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, ringReady = 1, raidNear = true, nearHome = false, dragons = 1, coinsDone = true }), HC)
	check("hint: a ready egg at home, the player is far away on a raid - do not call to hatch", g ~= nil and g.kind == "raid", g and g.kind)
	check("raid: ring 0 is open without dragons (the first egg by a raid)", RaidLoop.open(Config.Raid, 0, {}, 0) == true and RaidLoop.farthestOpen(Config.Raid, {}, 0) == 0)
	g = Hints.goal(snap({ carry = true, ringFree = "none" }), HC)
	check("hint: egg in the hands, no slot - nothing", g == nil)
	-- a glowing egg in the hands - always home (without a free bowl, riding in flight, and with a ready bowl)
	for _, over in { { carry = true, carryGlow = true, ringFree = "none" }, { carry = true, carryGlow = true, mounted = true, flying = true },
		{ carry = true, carryGlow = true, ringReady = 1 }, { carry = true, carryGlow = true, glowEgg = true } } do
		g = Hints.goal(snap(over), HC)
		check("hint: a glowing egg in the hands - home", g ~= nil and g.kind == "glowHome", g and g.kind)
	end
	g = Hints.goal(snap({ carry = true, glowEgg = true }), HC)
	check("hint: an ordinary egg in the hands, there is a golden nest - to it (the ordinary one goes to the shelf)", g ~= nil and g.kind == "glowEgg", g and g.kind)
	-- the golden nest on the slope - with the egg to the dragon, home riding; the second dragon - glowing: the ring raids wait
	g = Hints.goal(snap({ carry = true, carryGlow = true, glowDragon = true, companionStage = 1 }), HC)
	check("hint: a glowing egg in the hands on the slope, has a teen - to the dragon", g ~= nil and g.kind == "raidDragon", g and g.kind)
	g = Hints.goal(snap({ carry = true, carryGlow = true, glowDragon = true, mounted = true }), HC)
	check("hint: riding with a glowing egg - home riding", g ~= nil and g.kind == "raidRide", g and g.kind)
	g = Hints.goal(snap({ carry = true, carryGlow = true, glowDragon = true, companionStage = 0 }), HC)
	check("hint: a glowing egg in the hands, the dragon is a baby - home on foot", g ~= nil and g.kind == "glowHome", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, glowPending = true }), HC)
	check("hint: has a dragon, the golden one not stolen yet - do not call to the ring nests", g == nil or g.kind ~= "raid", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidWait = true, dragons = 1, coinsDone = true, glowPending = true }), HC)
	check("hint: the golden one not stolen - do not call 'next egg in' either", g == nil or g.kind ~= "raidWait", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 0, glowPending = true }), HC)
	check("hint: 0 dragons - the first raid even with glowPending", g ~= nil and g.kind == "raidFirst", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, glowPending = true, glowEgg = true }), HC)
	check("hint: the golden nest appeared - to it", g ~= nil and g.kind == "glowEgg", g and g.kind)
	-- the series golden nest 2-6 does not
	-- take away the daily raids - while there is a limit today (glowLater), to the Gloom nest; the limit is over - to the golden one
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 2, coinsDone = true, glowEgg = true, glowLater = true }), HC)
	check("series: a veteran, golden nest #2+ stands, daily raids exist - to the Gloom nest", g ~= nil and g.kind == "raid", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 2, coinsDone = true, glowEgg = true, glowLater = false, glowPending = true }), HC)
	check("series: the daily limit is over - to the golden nest", g ~= nil and g.kind == "glowEgg", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, mounted = true, glowPending = true }), HC)
	check("hint: riding, the golden one not stolen - do not call the raid", g == nil or g.kind ~= "raid", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, companionStage = 1, glowPending = true }), HC)
	check("hint: a teen nearby, the golden one not stolen - ride first (opens the slope)", g ~= nil and g.kind == "ride", g and g.kind)
	-- the one-dragon day - there is always a target
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 0, glideDone = true }), HC)
	-- the ledge once, then the stall; the pile - only a big one (dayPileMin)
	check("day 1: baby, the ledge done - to the stall, not to the updraft again", g ~= nil and g.kind == "stall", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 0, glideDone = true, pot = HC.pileMin }), HC)
	check("day 1: a small pile (pileMin) no longer calls - the stall", g ~= nil and g.kind == "stall", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 0, glideDone = true, pot = HC.dayPileMin }), HC)
	check("day 1: a big pile (dayPileMin) does not call the arrow either - the stall (31.10: the arrow darted home / stall)", g ~= nil and g.kind == "stall", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 1, rodeDone = true, glowPedestal = true, warmPrice = 1000, coins = 1200 }), HC)
	check("day 1: teen, enough coins to warm - warm the egg (warm)", g ~= nil and g.kind == "warm", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 1, rodeDone = true, glowPedestal = true, warmPrice = 1000, coins = 100 }), HC)
	check("day 1: teen, few coins - to the stand to save up (warm)", g ~= nil and g.kind == "warm", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 1, rodeDone = true }), HC)
	check("day 1: teen, no golden one yet - to the stall (stall)", g ~= nil and g.kind == "stall", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 2, rodeDone = true, flewDone = true }), HC)
	check("day 1: adult on the ground - take off (fly)", g ~= nil and g.kind == "fly", g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = false, oneDragonDay = true, glowPending = true, companionStage = 1, rodeDone = true, mounted = true, glowPedestal = true, warmPrice = 1000, coins = 0 }), HC)
	check("day 1: riding idle - to the stand", g ~= nil and g.kind == "warm", g and g.kind)
	check("the Gloom glows purple (sec. 23): Neon shell, glowing smoke, outline", Config.Combat.visibility.shell == true and Config.Combat.visibility.smokeLight >= 0.5 and Config.Combat.visibility.highlight == true)
	check("flight protection - minimal (sec. 22): rollback only when faster than x3 and two samples in a row", Config.Dragon.ride.anticheat.grossMult >= 3 and Config.Dragon.ride.anticheat.grossStreak >= 2)
	check("the sky fight from the third day of play (sec. 22), the flight ceiling above the islets", Config.Combat.skyFromDay >= 3 and Config.Dragon.flight.ceiling + Config.Dragon.ride.ceilingSlack > Config.World.islets.ring.yMax)
	check("quiet for windows (sec. 21): stands 3 s, strict 60 s, then soft", Config.Quiet.idleFor >= 2 and Config.Quiet.strictFor >= 30 and Config.Quiet.speed > 0)
	check("Keeper day 1: 'second egg', 'two in the nest', 'hunter', Index are skipped; berries, riding, flight - not",
		Quests.dayOneSkip({ id = 3, title = "", text = "", event = "eggInc", count = 2, reward = {} }) and Quests.dayOneSkip({ id = 6, title = "", text = "", event = "hatch", count = 2, reward = {} })
		and Quests.dayOneSkip({ id = 9, title = "", text = "", event = "eggFound", count = 5, reward = {} }) and Quests.dayOneSkip({ id = 15, title = "", text = "", event = "index", count = 10, reward = {} })
		and not Quests.dayOneSkip({ id = 4, title = "", text = "", event = "feed", count = 1, reward = {} }) and not Quests.dayOneSkip({ id = 1, title = "", text = "", event = "hatch", count = 1, reward = {} })
		and not Quests.dayOneSkip({ id = 8, title = "", text = "", event = "fly", count = 1, reward = {} }))
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, glowPending = false }), HC)
	check("hint: without firstEggOnly, the golden one at home - the ring raids again (the core logic)", g ~= nil and g.kind == "raid", g and g.kind)
	-- day 1 = one dragon: with a dragon neither to the nests nor to free eggs
	g = Hints.goal(snap({ tableFree = 0, raidNear = true, dragons = 1, coinsDone = true, glowPending = true, oneDragonDay = true, eggNear = true }), HC)
	check("hint: the one-dragon day - do not lead to a free egg", g == nil or (g.kind ~= "egg" and g.kind ~= "raid"), g and g.kind)
	g = Hints.goal(snap({ tableFree = 0, dragons = 1, coinsDone = true, eggNear = true, oneDragonDay = true, feedPrice = 10, coins = 100 }), HC)
	check("hint: the one-dragon day - feed (once) instead of an egg", g ~= nil and g.kind == "feed", g and g.kind)
	-- bustle on a quiet server - rider bots and walkers; at least three plots remain for newcomers, there are enough names
	local AA = Config.Admin
	check("bots: auto on a quiet server (<= 2 live), 3 riders, no more than Config.Admin.bots.max and no more than half the plots, off in Studio",
		AA.auto.on == true and AA.auto.maxPlayers == 2 and AA.auto.count <= AA.bots.max and AA.auto.count <= Config.World.nests.count - 3 and AA.auto.studio == false)
	check("bots: no fewer names than bots and walkers", #AA.names >= AA.bots.max + AA.walkers.count and AA.walkers.count >= 1 and AA.walkers.count <= 4)
	check("walkers: the point rings inside the square (r < 50), the animations are set", AA.walkers.ring[2] < Config.World.plaza.radius and AA.walkers.anims.idle > 0 and AA.walkers.anims.walk > 0)
	check("bot avatars: the seed without the owner, recent players off (owner 29.10)", #AA.avatarSeed >= 1 and table.find(AA.avatarSeed, Config.AdminUserIds[1]) == nil and AA.avatarRecent == false)
	check("bot avatars: enough catalog outfits for different combinations (shirts >= 8, pants >= 4, caps >= 10)", #AA.avatarParts.shirts >= 8 and #AA.avatarParts.pants >= 4 and #AA.avatarParts.hats >= 10)
	check("the demo raid: the warden slower than the bot, the bot runs like a player (16), the scene no more often than once per 30 s", AA.demo.on == true and AA.demo.share < 1 and AA.demo.run == 16 and AA.demo.every >= 30 and AA.demo.sneak < AA.demo.run)
	check("raid: day 1 = only the first egg, rings 1-2 off (sec. 16)", Config.Raid.firstEggOnly == true
		and RaidLoop.open(Config.Raid, 1, { rode = true, flew = true }, 3) == false and RaidLoop.open(Config.Raid, 2, { rode = true, flew = true }, 3) == false
		and RaidLoop.open(Config.Raid, 0, {}, 0) == true)
	check("golden nest: after the first raid egg and the first ride, on the slope, the raid as rings 1-2 (29.10 sec. 15)",
		Config.Glow.egg.afterRaids == 1 and Config.Glow.egg.raid.needRide == true and Config.Glow.egg.raid.safe == "dragon"
		and Config.Glow.egg.spot.slope.on == true and Config.Glow.egg.spot.plaza == false and Config.Glow.egg.spot.slope.nestGap >= Config.Raid.approachR * 2 + 2
		and Config.Glow.egg.spot.slope.relax.nestGap >= Config.Raid.approachR + 10)
	g = Hints.goal(snap({ ringReady = 1, carry = true }), HC)
	check("hint: a ready egg matters most", g ~= nil and g.kind == "hatch" and g.slot == 1)
	g = Hints.goal(snap({ tableFree = 2, incubating = 1, ringFree = "none" }), HC)
	check("hint: an egg is warming - do not lead to the table", g == nil)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin }), HC)
	check("hint: the pile has filled up - to the pile", g ~= nil and g.kind == "pile")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0 }), HC)
	check("hint: has a dragon and a free incubator - for an egg", g ~= nil and g.kind == "egg")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, ringFree = "none", incubating = 1, feedPrice = 50, coins = 60 }), HC)
	check("hint: the incubator is occupied, enough coins - feed", g ~= nil and g.kind == "feed")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, ringFree = "none", incubating = 1, feedPrice = 50, coins = 10 }), HC)
	check("hint: few coins - nothing", g == nil)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, eggNear = false, feedPrice = 50, coins = 60 }), HC)
	check("hint: no eggs nearby - feed", g ~= nil and g.kind == "feed")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin, coinsDone = true }), HC)
	check("hint: already collected the pile - do not lead to the pile (next - for an egg)", g ~= nil and g.kind == "egg")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, eggDone = true, feedPrice = 50, coins = 60 }), HC)
	check("hint: already found an egg - feed", g ~= nil and g.kind == "feed")
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, eggDone = true, fedDone = true, feedPrice = 50, coins = 60 }), HC)
	check("hint: everything done once - no hints (except the arrow to an egg)", g == nil or g.kind == "egg") -- nothing to do - to the nearest egg
	-- baby on the shoulder, has not glided - to the ledge updraft; the pile matters more; after gliding - an egg
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, companionStage = 0 }), HC)
	check("hint: baby on the shoulder, has not glided - to the updraft (glide)", g ~= nil and g.kind == "glide", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin, companionStage = 0 }), HC)
	check("hint: gliding before the first pile (31.10: after the hatch one target - the ledge)", g ~= nil and g.kind == "glide", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin, companionStage = 0, glideDone = true }), HC)
	check("hint: the ledge done - the first pile", g ~= nil and g.kind == "pile", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, companionStage = 0, glideDone = true }), HC)
	check("hint: already glided - for an egg", g ~= nil and g.kind == "egg", g and g.kind)
	-- the dragon grew up in the nest, no companion, has not ridden - 'take it'; with a companion - the usual ride; after the ride - no
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, eggDone = true, fedDone = true, nestRideable = true, companionMissing = true }), HC)
	check("hint: a teen in the nest, no companion - take it (companion)", g ~= nil and g.kind == "companion", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, eggDone = true, fedDone = true, nestRideable = true, companionMissing = false }), HC)
	check("hint: the companion attribute is nil, but the profile has a companion (respawn) - no TAKE target", g == nil or g.kind == "egg", g and g.kind) -- nothing to do - the arrow to the nearest egg
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, eggDone = true, fedDone = true, nestRideable = true, companionMissing = true, rodeDone = true }), HC)
	check("hint: has already ridden - do not pull toward the dragon in the nest", g == nil or g.kind == "egg", g and g.kind) -- nothing to do - the arrow to the nearest egg
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, coinsDone = true, eggDone = true, fedDone = true, nestRideable = true, companionStage = 1 }), HC)
	check("hint: a teen companion nearby - riding matters more than the dragon in the nest", g ~= nil and g.kind == "ride", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin, nestRideable = true, companionMissing = true }), HC)
	check("hint: the pile before 'take the dragon'", g ~= nil and g.kind == "pile", g and g.kind)
	-- timer: 10 s of the same target, once per step
	-- 1.9: riding and flight
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, eggDone = true, fedDone = true, companionStage = 1 }), HC)
	check("a teen nearby -> ride", g ~= nil and g.kind == "ride", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, eggDone = true, fedDone = true, companionStage = 1, rodeDone = true }), HC)
	check("already rode -> no step", g == nil or g.kind == "egg", g and g.kind) -- nothing to do - the arrow to the nearest egg
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, eggDone = true, fedDone = true, companionStage = 2, rodeDone = true }), HC)
	check("an adult nearby, has not flown -> ride", g ~= nil and g.kind == "ride", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = HC.pileMin, companionStage = 1 }), HC)
	check("the pile matters more than riding", g ~= nil and g.kind == "pile", g and g.kind)
	g = Hints.goal(snap({ tableFree = 2, dragons = 1, pot = 0, companionStage = 1, feedPrice = 50, coins = 60 }), HC)
	check("riding matters more than food", g ~= nil and g.kind == "ride", g and g.kind)
	g = Hints.goal(snap({ ringReady = 1, dragons = 1, companionStage = 2, mounted = true }), HC)
	check("riding an adult, has not flown -> fly (the ready egg waits)", g ~= nil and g.kind == "fly", g and g.kind)
	g = Hints.goal(snap({ ringReady = 1, dragons = 1, companionStage = 1, mounted = true }), HC)
	check("riding a teen -> no step", g == nil, g and g.kind)
	g = Hints.goal(snap({ dragons = 1, companionStage = 2, mounted = true, flying = true }), HC)
	check("in the air -> ring", g ~= nil and g.kind == "ring", g and g.kind)
	g = Hints.goal(snap({ dragons = 1, companionStage = 2, mounted = true, flying = true, ringDone = true }), HC)
	check("the ring was already done -> no step", g == nil, g and g.kind)

	local t = Hints.newTimer()
	check("timer: the first tick does not show", Hints.tick(t, { kind = "table" }, 0, 10) == false)
	check("timer: 5 s - too early", Hints.tick(t, { kind = "table" }, 5, 10) == false)
	check("timer: 10 s - show", Hints.tick(t, { kind = "table" }, 10, 10) == true)
	check("timer: the same step is not shown a second time", Hints.tick(t, { kind = "table" }, 30, 10) == false)
	check("timer: a target change resets the countdown", Hints.tick(t, { kind = "pile" }, 31, 10) == false and Hints.tick(t, { kind = "pile" }, 40, 10) == false)
	check("timer: a new target is shown after 10 s", Hints.tick(t, { kind = "pile" }, 41, 10) == true)
	check("timer: a nil target is not shown", Hints.tick(t, nil, 60, 10) == false and Hints.tick(t, nil, 80, 10) == false)
	check("coin icons: 10 coins - 1", Hints.coinIcons(10, 10) == 1)
	check("coin icons: 692 - 10", Hints.coinIcons(692, 10) == 10)
	check("coin icons: 35 - 4", Hints.coinIcons(35, 10) == 4)
end

-- Offline (2.5): the 'while you were away' summary -------------------------------------------------
do
	local now = 1_800_000_000
	local function nest(d: { [string]: any }?, inc: { [any]: any }?): any
		local dr = d or { rarity = "Common", stage = 0, name = "Moss", stageEndsAt = now + 600 }
		return { dragons = { d1 = dr }, nestOrder = { "d1" }, eggs = { shelf = {}, incubating = inc or {} } }
	end
	local m0 = { ascension = 0 }
	check("offline: the first join (lastSeen 0) - no card", Offline.summary(nest(), 0, now, m0, B) == nil)
	check("offline: 5 minutes - no card", Offline.summary(nest(), now - 300, now, m0, B) == nil)
	local s1 = Offline.summary(nest(), now - 3600, now, m0, B)
	check("offline: an hour, Common baby 1/s -> 900 coins (25%)", s1 ~= nil and s1.coins == 900 and s1.eggs == 0 and #s1.grew == 0, s1 and s1.coins)
	local s10 = Offline.summary(nest(), now - 36000, now, m0, B)
	check("offline: 10 h trimmed to 8 h -> 7 200", s10 ~= nil and s10.coins == 7200, s10 and s10.coins)
	local sv = Offline.summary(nest(), now - 3600, now, { ascension = 0, vip = true }, B)
	check("offline: VIP +10% and outside the game -> 990", sv ~= nil and sv.coins == 990, sv and sv.coins)
	local sb = Offline.summary(nest(), now - 3600, now, { ascension = 0, boost = true, friends = 3, weatherMult = 2 }, B)
	check("offline: boost, friends, weather - online only -> 900", sb ~= nil and sb.coins == 900, sb and sb.coins)
	local se = Offline.summary(nest(nil, { [1] = { endsAt = now - 5 }, [2] = { endsAt = now + 100 } }), now - 3600, now, m0, B)
	check("offline: 1 egg of 2 ready", se ~= nil and se.eggs == 1, se and se.eggs)
	local dg = { rarity = "Common", stage = 0, name = "Moss", stageEndsAt = now - 10 }
	local sg = Offline.summary(nest(dg), now - 3600, now, m0, B)
	check("offline: the timer ran out -> 'Moss grew to Juvenile' (stage 1)", sg ~= nil and #sg.grew == 1 and sg.grew[1].stage == 1 and sg.grew[1].name == "Moss" and sg.grew[1].uid == "d1")
	check("offline: the rate before growth (baby 1/s, not teen 6/s)", sg ~= nil and sg.coins == 900, sg and sg.coins)
	check("offline: growth no further than one stage (Growth.tick from now)", Growth.tick(dg, now, B) and dg.stage == 1 and (dg.stageEndsAt or 0) > now and not Growth.tick(dg, now, B))
	local se3 = Offline.summary(nest({ rarity = "Common", stage = 3, name = "Old", stageEndsAt = nil }), now - 3600, now, m0, B)
	check("offline: the elder does not grow, there is income", se3 ~= nil and #se3.grew == 0 and se3.coins > 0)
	check("offline: without dragons and eggs - nil", Offline.summary({ dragons = {}, nestOrder = {}, eggs = { incubating = {} } }, now - 3600, now, m0, B) == nil)
	local mg = Offline.merge({ coins = 500, seconds = 1, eggs = 2, grew = { { uid = "x", name = "Old", stage = 2 } } }, s1)
	check("offline: unclaimed coins are added to the new ones, the lines are fresh", mg.coins == 1400 and mg.eggs == 0 and #mg.grew == 0)
	local mn = Offline.merge({ coins = 500, eggs = 1, grew = { { uid = "x", name = "Old", stage = 2 } } }, nil)
	check("offline: a short visit - only the unclaimed coins", mn.coins == 500 and mn.eggs == 0 and #mn.grew == 0 and Offline.hasNews(mn))
	check("offline: an empty record - no card", not Offline.hasNews(Offline.empty()) and not Offline.hasNews(nil))
end

-- Experiments: A/B of the egg labels by UserId parity ----------------------------------------
do
	local EM = Config.World.eggMarks
	check("A/B: odd UserId - with a label", Experiments.eggLabels(12345, EM) and Experiments.tag(12345, EM) == "on")
	check("A/B: even UserId - without a label", not Experiments.eggLabels(12346, EM) and Experiments.tag(12346, EM) == "off")
	check("A/B: the Studio player (-1) - with a label", Experiments.eggLabels(-1, EM))
	check("A/B: off - everyone has a label", Experiments.eggLabels(12346, { abByUserId = false }))
	local on = 0
	for id = 1000, 1999 do
		if Experiments.eggLabels(id, EM) then
			on += 1
		end
	end
	check("A/B: the groups are equal", on == 500, on)
	-- firstborn growth 2/6 (A) and 3/9 (B) by the second UserId bit, from D0; the cells with the egg labels are equal
	local AB = Config.Balance.firstDragon.ab
	local d0 = AB.from
	-- the test is off; the mechanism is checked on a copy with on = true
	check("growth A/B: off since 24.10, group B 3/9 stays in the config", AB.on == false and d0 == Config.Analytics.d0 and AB.growMinB[1] == 3 and AB.growMinB[2] == 9)
	check("growth A/B: with the test off everyone is A", Experiments.growGroup(6, AB, d0) == "A" and Experiments.growGroup(7, AB, d0) == "A")
	local ABon = table.clone(AB)
	ABon.on = true
	check("growth A/B: before D0 everyone is A", Experiments.growGroup(6, ABon, d0 - 1) == "A" and Experiments.growGroup(7, ABon, d0 - 1) == "A")
	check("growth A/B: from D0 the second bit 1 - B", Experiments.growGroup(6, ABon, d0) == "B" and Experiments.growGroup(7, ABon, d0) == "B")
	check("growth A/B: from D0 the second bit 0 - A", Experiments.growGroup(4, ABon, d0) == "A" and Experiments.growGroup(5, ABon, d0) == "A")
	check("growth A/B: off - A", Experiments.growGroup(6, { on = false, from = 0 }, d0) == "A" and Experiments.growGroup(6, nil, d0) == "A")
	check("growth A/B: force (Studio) beats the date", Experiments.growGroup(4, { on = true, from = d0 + 999, force = "B" }, d0) == "B")
	local cells = { ["onA"] = 0, ["onB"] = 0, ["offA"] = 0, ["offB"] = 0 }
	for id = 1000, 1999 do
		local k = Experiments.tag(id, EM) .. Experiments.growGroup(id, ABon, d0)
		cells[k] += 1
	end
	check("growth A/B: independent of the egg labels - four cells of 250", cells.onA == 250 and cells.onB == 250 and cells.offA == 250 and cells.offB == 250, cells.onA, cells.onB, cells.offA, cells.offB)
	-- the NEXT line - the nearest timer (growth in the nest, an egg in an incubator), the next update, the remainder
	local now = 1000
	local data = { nestOrder = { "d1", "d2", "d3" }, dragons = {
		d1 = { name = "Frost", stage = 1, stageEndsAt = now + 300 }, d2 = { name = "Moss", stage = 0, stageEndsAt = now + 120 },
		d3 = { name = "Old", stage = 3, stageEndsAt = nil }, d9 = { name = "Away", stage = 0, stageEndsAt = now + 10 } },
		eggs = { incubating = { ["1"] = { endsAt = now + 200 }, ["2"] = { endsAt = now - 5 } } } }
	local t = NextUp.timer(data, now)
	check("NEXT: the nearest growth in the nest (not the sanctuary, not Elder)", t ~= nil and t.kind == "grow" and t.name == "Moss" and t.stage == 1 and t.at == now + 120)
	check("NEXT: not a firstborn - no first (25.10)", t ~= nil and not t.first)
	data.dragons.d2.growAs = "Common"
	local tf = NextUp.timer(data, now)
	check("NEXT: a firstborn (growAs) - first = true (25.10, B2)", tf ~= nil and tf.first == true and tf.name == "Moss")
	data.dragons.d2.growAs = nil
	data.dragons.d2.stageEndsAt = now + 400
	local t2 = NextUp.timer(data, now)
	check("NEXT: an egg before growth - the egg (a ready one does not count)", t2 ~= nil and t2.kind == "hatch" and t2.at == now + 200)
	check("NEXT: an empty profile - nothing", NextUp.timer({}, now) == nil and NextUp.timer({ dragons = {}, nestOrder = {}, eggs = { incubating = {} } }, now) == nil)
	local U = Content.Updates
	local u0 = NextUp.update(U, U[1].activeFrom - 100, nil)
	check("NEXT: the next update Aurora with an RSVP event", u0 ~= nil and u0.title == "Aurora" and u0.eventId == "9116981376158139036" and u0.at == U[1].activeFrom)
	local u1 = NextUp.update(U, U[1].activeFrom, nil)
	-- the Cinder/Pearl Tide/Nightfall events are created (tools/create_events.py) - every update has its own eventId
	check("NEXT: Aurora started - the next is Cinder with its own event", u1 ~= nil and u1.title == "Cinder" and u1.eventId == "3547330492254782090")
	local u2 = NextUp.update(U, U[2].activeFrom, nil)
	local u3 = NextUp.update(U, U[3].activeFrom, nil)
	check("NEXT: after Cinder - Pearl Tide, after Pearl Tide - Nightfall, each has an event", u2 ~= nil and u2.title == "Pearl Tide" and u2.eventId == "334786214311887441"
		and u3 ~= nil and u3.title == "Nightfall" and u3.eventId == "2959087820024709740")
	check("NEXT: an update further than within is not shown", NextUp.update(U, U[1].activeFrom - 15 * 86400, 14 * 86400) == nil and NextUp.update(U, U[1].activeFrom - 86400, 14 * 86400) ~= nil)
	check("NEXT: after the last update - nothing", NextUp.update(U, U[#U].activeFrom + 1, nil) == nil)
	check("NEXT: a remainder from a day - days and hours", NextUp.left(18 * 86400 + 3 * 3600 + 59, "{d}d {h}h") == "18d 3h")
	check("NEXT: a remainder less than a day - hours:minutes:seconds", NextUp.left(3 * 3600 + 5 * 60 + 7, "{d}d {h}h") == "3:05:07" and NextUp.left(200, "{d}d {h}h") == "3:20")
	check("egg labels: only Meadow, up close", EM.labelDistance.Meadow == 28 and EM.labelDistance.Cliffs == nil and EM.labelDistance.Springs == nil and EM.labelDistance.Summit == nil)
end

-- Rewards (2.4): dailies, time gifts, calendar, zones, season -----------------------
do
	local R = Config.Rewards
	local t0 = os.time({ year = 2026, month = 11, day = 6, hour = 12 })
	check("rewards: UTC date", Rewards.dateKey(t0) == "2026-11-06", Rewards.dateKey(t0))
	check("rewards: until the reset", Rewards.toReset(Rewards.dayIndex(t0) * 86400 + 3600) == 82800)
	local p1 = Rewards.dailyPicks(Rewards.dayIndex(t0), R)
	local p2 = Rewards.dailyPicks(Rewards.dayIndex(t0), R)
	check("dailies: 3 quests, deterministic", #p1 == 3 and p1[1] == p2[1] and p1[2] == p2[2] and p1[3] == p2[3])
	local seen: { [string]: number } = {}
	local offPicked, sameNext = false, 0
	local prev: { string }? = nil
	for day = 20000, 20399 do
		local ids = Rewards.dailyPicks(day, R)
		for i, id in ids do
			local d, tier = Rewards.def(R, id)
			check("dailies: id from its own group " .. id, d ~= nil and tier == Rewards.TIERS[i])
			if d and d.off then
				offPicked = true
			end
			seen[id] = (seen[id] or 0) + 1
		end
		if prev and prev[1] == ids[1] and prev[2] == ids[2] and prev[3] == ids[3] then
			sameNext += 1
		end
		prev = ids
	end
	check("dailies: no disabled ones in the pool, shards and Hatch Party drop (16.10 evening-4: 2.6, 2.7 built)", not offPicked and (seen.shards6 or 0) > 0 and (seen.party1 or 0) > 0)
	local all = true
	for _, tier in Rewards.TIERS do
		for _, d in Rewards.pool(R, tier) do
			if (seen[d.id] or 0) < 400 / #Rewards.pool(R, tier) * 0.6 then
				all = false
				print("  drops rarely " .. d.id .. " " .. tostring(seen[d.id]))
			end
		end
	end
	check("dailies: all enabled quests drop about equally", all)
	check("dailies: neighbouring days are not entirely the same", sameNext < 40, sameNext)
	local daily: any = { date = "", done = {}, bonus = false }
	check("dailies: the first reset", Rewards.dailyReset(daily, t0, R) and daily.date == "2026-11-06" and #daily.ids == 3)
	check("dailies: the same day - no reset", not Rewards.dailyReset(daily, t0 + 3600, R))
	daily.ids = { "eggs3", "hatch2", "summitEgg" }
	local c0, b0 = Rewards.dailyEvent(daily, "ring", 1, R)
	check("dailies: a foreign event does not accumulate", #c0 == 0 and not b0 and daily.counters.ring == nil)
	Rewards.dailyEvent(daily, "eggFound", 2, R)
	local c1 = Rewards.dailyEvent(daily, "eggFound", 1, R)
	check("dailies: Easy done on the 3rd egg", #c1 == 1 and c1[1] == "easy" and daily.done.easy)
	local c2 = Rewards.dailyEvent(daily, "eggFound", 1, R)
	check("dailies: not done again", #c2 == 0)
	Rewards.dailyEvent(daily, "hatch", 2, R)
	local c3, b3 = Rewards.dailyEvent(daily, "eggInc_Summit", 1, R)
	check("dailies: all three - the bonus once", #c3 == 1 and b3 and daily.bonus)
	local _, b4 = Rewards.dailyEvent(daily, "eggInc_Summit", 1, R)
	check("dailies: the bonus does not repeat", not b4)
	local k, n = Rewards.dailyProgress(daily, 1, R)
	check("dailies: progress no greater than the goal", k == 3 and n == 3)
	check("dailies: a new day - everything anew", Rewards.dailyReset(daily, t0 + 86400, R) and not daily.bonus and next(daily.done) == nil and next(daily.counters) == nil)

	local L = R.timeGifts.list
	local m, left = Rewards.nextGift(L, 0, {})
	check("gifts: the first at minute 5", m == 5 and left == 300)
	local ready = Rewards.readyGifts(L, 11 * 60, {})
	check("gifts: at minute 11 the 5 and 10 are ready", #ready == 2 and ready[1] == 5 and ready[2] == 10)
	local m2, left2 = Rewards.nextGift(L, 11 * 60, { ["5"] = true })
	check("gifts: the next 15 in 4 min", m2 == 15 and left2 == 240)
	check("gifts: after the 90th - no next one", Rewards.nextGift(L, 91 * 60, {}) == nil)
	check("gifts: minute 15 - berries x2, minute 90 - rare nest", (Rewards.gift(L, 15) :: any).berries == 2 and (Rewards.gift(L, 90) :: any).rareNest == true)

	local cal: any = { day = 0, lastDate = "" }
	check("calendar: the first join - day 1", Rewards.calendarAdvance(cal, t0) and cal.day == 1 and Rewards.calendarPending(cal))
	check("calendar: the second join on the same day - no", not Rewards.calendarAdvance(cal, t0 + 600))
	check("calendar: not claimed - the next day does not come (nothing is lost)", not Rewards.calendarAdvance(cal, t0 + 86400) and cal.day == 1)
	cal.claimed = 1
	check("calendar: claimed - day 2 tomorrow", Rewards.calendarAdvance(cal, t0 + 86400) and cal.day == 2)
	cal.claimed = 2
	check("calendar: a skipped week - just day 3", Rewards.calendarAdvance(cal, t0 + 9 * 86400) and cal.day == 3)
	local CR = Rewards.calendarReward
	check("calendar: 1 and 8 - coins 10 min, 2 and 9 - Cliffs, 3 and 10 - berries (20.10)", CR(1, R).minutes == 10 and CR(8, R).minutes == 10 and CR(2, R).egg == "Cliffs" and CR(9, R).egg == "Cliffs" and CR(3, R).berries == 3 and CR(10, R).berries == 3)
	check("calendar: 7 - a Rare baby, 13 as 6, 14 - Epic Summit", CR(7, R).hatchling == "Rare" and CR(13, R).egg == "Springs" and CR(14, R).egg == "Summit" and CR(14, R).minRarity == "Epic")
	check("calendar: then the cycle 1-7 (15 = 1, 21 = Rare baby, 28 = Rare baby)", CR(15, R).minutes == 10 and CR(21, R).hatchling == "Rare" and CR(28, R).hatchling == "Rare")
	check("calendar: the slot in the strip", Rewards.calendarSlot(1) == 1 and Rewards.calendarSlot(7) == 7 and Rewards.calendarSlot(8) == 1 and Rewards.calendarSlot(14) == 7 and Rewards.calendarSlot(15) == 1)
	local ch = Rewards.choices(7, Config.Elements, 3)
	check("calendar: 3 different elements to choose from", #ch == 3 and ch[1] ~= ch[2] and ch[2] ~= ch[3] and ch[1] ~= ch[3], table.concat(ch, ","))
	check("zones: the best open one and the next", Rewards.bestZone(0) == "Cliffs" and Rewards.bestZone(1) == "Springs" and Rewards.bestZone(3) == "Summit"
		and Rewards.nextZone("Cliffs", B.zoneOrder) == "Springs" and Rewards.nextZone("Summit", B.zoneOrder) == "Summit")
	local sc = Rewards.seasonClaimable(15, { ["1"] = true }, R.season.steps)
	check("season: 15 points, the 1st claimed - 2 and 3 available", #sc == 2 and sc[1] == 2 and sc[2] == 3)
	check("season: 10 steps and 10 rewards, the last - Solstice Dusk Legendary", #R.season.rewards == #R.season.steps and R.season.rewards[10].element == "dusk"
		and R.season.rewards[10].hatchling == "Legendary" and R.season.rewards[7].preset == "solstice" and R.season.rewards[4].decor == "Banner")
	check("season: steps", Rewards.seasonStep(0, R.season.steps) == 0 and Rewards.seasonStep(4, R.season.steps) == 1 and Rewards.seasonStep(91, R.season.steps) == 9 and Rewards.seasonStep(200, R.season.steps) == 10)
end

-- weekly quests - the week Sun 19:00 UTC, the set of the last update, reset, completion
do
	local WK = Config.Rewards.weekly
	local U = Content.Updates
	check("week: the switch and 5 points", WK.on == true and WK.points == 5, WK.points)
	check("week: the anchor - Sunday 19:00 UTC", os.date("!%w %H:%M", WK.anchor) == "0 19:00", os.date("!%w %H:%M", WK.anchor))
	local okBound = true
	for i, u in U do
		if Rewards.weekIndex(u.activeFrom, WK.anchor) ~= Rewards.weekIndex(u.activeFrom - 1, WK.anchor) + 1 or Rewards.weekLeft(u.activeFrom, WK.anchor) ~= 604800 then
			okBound = false
		end
		if i > 1 and Rewards.weekIndex(u.activeFrom, WK.anchor) ~= Rewards.weekIndex(U[i - 1].activeFrom, WK.anchor) + 1 then
			okBound = false
		end
	end
	check("week: all 4 updates start a week, consecutively", okBound)
	check("week: 08.11 19:00 = week 2966, 7 days until the reset", Rewards.weekIndex(1794164400, WK.anchor) == 2966 and Rewards.weekLeft(1794164400 + 3600, WK.anchor) == 604800 - 3600)
	check("week: before 08.11 (live 0) no set", Rewards.weeklySet(U, 0) == nil)
	local s1, n1 = Rewards.weeklySet(U, 1)
	local s4, n4 = Rewards.weeklySet(U, 4)
	check("week: live 1 - Aurora, Summit; live 4 - Nightfall", s1 ~= nil and n1 == 1 and s1.egg == "Summit" and s4 ~= nil and n4 == 4 and s4.quests[2].id == "duskHatch")
	local s9, n9 = Rewards.weeklySet(U, 9)
	check("week: beyond the last update - its set", s9 == s4 and n9 == 4)
	local fake = { { activeFrom = 0, weekly = U[1].weekly }, { activeFrom = 1 } }
	local sf, nf = Rewards.weeklySet(fake, 2)
	check("week: an update without a set - the previous set", sf == U[1].weekly and nf == 1)
	local w: any = { week = -1, update = 0, counters = {}, done = {} }
	local t = 1794164400 + 600
	check("week: the first join - reset", Rewards.weeklyReset(w, t, WK.anchor, 1) and w.week == 2966 and w.update == 1)
	check("week: the same week - no reset", not Rewards.weeklyReset(w, t + 86400, WK.anchor, 1))
	local set = s1 :: any
	check("week: a foreign event does not accumulate", #Rewards.weeklyEvent(w, "hatch", 1, set) == 0 and w.counters.hatch == nil)
	local c1 = Rewards.weeklyEvent(w, "hatchSky_aurora", 1, set)
	check("week: 1/2 - not done", #c1 == 0 and Rewards.weeklyProgress(w, 1, set) == 1)
	local c2 = Rewards.weeklyEvent(w, "hatchSky_aurora", 1, set)
	check("week: 2/2 - quest 1 done", #c2 == 1 and c2[1] == 1 and w.done["1"] == true)
	check("week: a done quest does not accumulate and is not done again", not Rewards.weeklyUses(w, "hatchSky_aurora", set) and #Rewards.weeklyEvent(w, "hatchSky_aurora", 1, set) == 0)
	local c3 = Rewards.weeklyEvent(w, "variant_glacier", 1, set)
	check("week: Glacier - quest 2", #c3 == 1 and c3[1] == 2)
	check("week: the next Sun 19:00 - everything from zero", Rewards.weeklyReset(w, 1794769200, WK.anchor, 2) and w.week == 2967 and next(w.done) == nil and next(w.counters) == nil)
	check("week: a week without an update (the same set) - also a reset", Rewards.weeklyReset(w, 1794769200 + 604800, WK.anchor, 2) and w.week == 2968)
	local k, n = Rewards.weeklyProgress(w, 3, set)
	check("week: no such quest - 0/1", k == 0 and n == 1)
	check("week: there are weeks after the season closes (29.11 - 06.12), points only until 04.12", Rewards.weekIndex(Config.Rewards.season.endsAt, WK.anchor) == Rewards.weekIndex(U[4].activeFrom, WK.anchor))
	-- the event badge - only the first week of its update
	check("badge: Aurora week - aurora2026", Rewards.weeklyBadge(U, 1, 2966, WK.anchor) == "aurora2026")
	check("badge: Nightfall week - nightfall2026, the next (repeat) - none", Rewards.weeklyBadge(U, 4, 2969, WK.anchor) == "nightfall2026" and Rewards.weeklyBadge(U, 4, 2970, WK.anchor) == nil)
	check("badge: a foreign week and no update - none", Rewards.weeklyBadge(U, 1, 2967, WK.anchor) == nil and Rewards.weeklyBadge(U, 9, 2966, WK.anchor) == nil)
end

-- the raid rings
do
	local R = Config.Raid
	local pts = RaidLoop.ring0Points(R, Config.World)
	check("raid: three ring 0 nests", #pts == 3 and pts[1].angleDeg == 30 and pts[2].angleDeg == 150 and pts[3].angleDeg == 270)
	local okR = true
	for _, p in pts do
		local r = math.sqrt(p.x * p.x + p.z * p.z)
		if math.abs(r - math.sqrt(47 ^ 2 + 7 ^ 2)) > 0.5 then
			okR = false
		end
	end
	check("raid: ring 0 at r 47 (+7 sideways)", okR)
	local p1 = pts[1]
	check("raid: nest 30 deg - 23.5 +-2 from the plot 1 gate (60, 0) and 37.4 +-2 from the plot 2 gate (30, -52)", math.abs(math.sqrt((p1.x - 60) ^ 2 + p1.z ^ 2) - 23.5) < 2 and math.abs(math.sqrt((p1.x - 30) ^ 2 + (p1.z + 52) ^ 2) - 37.4) < 2)
	local p3 = pts[3]
	check("raid: nest 270 deg - 82 +-3 from the plot 1 gate (the second raid)", math.abs(math.sqrt((p3.x - 60) ^ 2 + p3.z ^ 2) - 82) < 3)
	check("raid: the zone ring - meadow 1, springs 2; cliffs (points on the wall) and summit - free eggs", RaidLoop.ringOfZone(R, "Meadow") == 1 and RaidLoop.ringOfZone(R, "Cliffs") == nil and RaidLoop.ringOfZone(R, "Springs") == 2 and RaidLoop.ringOfZone(R, "Summit") == nil)
	local fp = RaidLoop.footPoints(R)
	check("raid: 8 nests at the foot of the cliffs in front of the boulders (z -276, ring 2, zone Cliffs)", #fp == 8 and fp[1].ring == 2 and fp[1].z == -276 and fp[8].x == 140 and fp[1].id == "cliffs_foot_1")
	check("raid: ring 0 is always open (the first egg by a raid)", RaidLoop.open(R, 0, {}, 0) and RaidLoop.open(R, 0, {}, 1))
	-- the ring 0 nest farthest from the plot 1 gate (60, 0) - wedge 150
	-- a run of ~100 studs; the near one (wedge 30) - 24
	local far, farD, nearD = nil, -1, math.huge
	for _, q in pts do
		local dd = math.sqrt((q.x - 60) ^ 2 + q.z ^ 2)
		if dd > farD then far, farD = q, dd end
		nearD = math.min(nearD, dd)
	end
	check("first egg: the far nest - wedge 150, 95-110 studs from the gate; the near one 22-26 (not shown to a newcomer)", far ~= nil and far.angleDeg == 150 and farD >= 95 and farD <= 110 and nearD >= 22 and nearD <= 26 and Config.Raid.firstFar == true, string.format("%s %.0f / %.0f", far and far.angleDeg or "-", farD, nearD))
	check("fence: the wall is low - the dragon does not catch on it on takeoff (29.10 evening)", Config.World.nests.wallHeight <= 4)
	check("spawning in the own pen is on (sec. 26)", Config.Loop.spawnHome == true)
	-- in the live config rings 1-2 are off (open "off") - the opening logic is checked on a copy with rode / flew
	local Rr = table.clone(R)
	Rr.rings = { R.rings[1], table.clone(R.rings[2]), table.clone(R.rings[3]) }
	Rr.rings[2].open, Rr.rings[3].open = "rode", "flew"
	check("raid: ring 1 - after riding, 2 - after flying (config copy)", not RaidLoop.open(Rr, 1, {}, 1) and RaidLoop.open(Rr, 1, { rode = true }, 1) and not RaidLoop.open(Rr, 2, { rode = true }, 1) and RaidLoop.open(Rr, 2, { flew = true }, 1))
	check("raid: the farthest open one (config copy)", RaidLoop.farthestOpen(Rr, {}, 0) == 0 and RaidLoop.farthestOpen(Rr, {}, 1) == 0 and RaidLoop.farthestOpen(Rr, { rode = true }, 1) == 1 and RaidLoop.farthestOpen(Rr, { rode = true, flew = true }, 1) == 2)
	check("raid: in the live config rings 1-2 are off - nothing beyond ring 0 is open", RaidLoop.farthestOpen(R, { rode = true, flew = true }, 3) == 0)
	local g0 = RaidLoop.ringCfg(R, 0).guard
	check("raid: the warden speed by attempt 0.85 -> 0.70, then not lower", RaidLoop.share(g0, 0) == 0.85 and RaidLoop.share(g0, 3) == 0.7 and RaidLoop.share(g0, 9) == 0.7)
	local n = 0
	for i = 1, 400 do
		if RaidLoop.rarity({ Common = 85, Uncommon = 15 }, function() return (i - 0.5) / 400 end, Config.Rarities) == "Common" then
			n += 1
		end
	end
	check("raid: ring 0 rarity - Common 85 %", n == 340)
	local dx, dz = RaidLoop.waitPoint(210.3, 152.8, 174.2, 100.6, 35)
	check("raid: the dragon waits 35 from the nest toward home", math.abs(math.sqrt((dx - 210.3) ^ 2 + (dz - 152.8) ^ 2) - 35) < 0.01 and dx < 210.3 and dz < 152.8)
	check("raid: Rare hatch 480 s (31.10 dailies 3-15 min), the table as before", RaidLoop.hatchSeconds(R, "Rare") == 480 and RaidLoop.hatchSeconds(R, "None") == nil)
	check("prices: the 4th slot 2 500, the 5th 15 000; the third bowl 60 000", B.slots.coins[1] == 2500 and B.slots.coins[2] == 15000 and B.incubators.coins[2] == 60000)
end

print(string.format("core tests: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed tests")
end
