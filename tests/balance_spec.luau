--!strict
-- The balance specification: Config.Balance against the balance model (kept outside this repository).
-- Run from the repository root: luau tests/balance_spec.luau. The numbers below are copied from balance_out by hand;
-- when the simulator is recomputed, update both sides.

local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Core/Economy")
local Odds = require("../src/shared/Core/Odds")
local Growth = require("../src/shared/Core/Growth")
local B = Config.Balance

local failed = 0
local function expect(name: string, got: any, want: any)
	if got ~= want then
		failed += 1
		print("MISMATCH " .. name .. ": Config " .. tostring(got) .. ", balance_out " .. tostring(want))
	end
end

-- §1 the income coins/s by rarity x stage
local income = {
	Common = { 1, 6, 30, 100 }, Uncommon = { 4, 24, 120, 400 }, Rare = { 16, 96, 480, 1600 },
	Epic = { 80, 480, 2400, 8000 }, Legendary = { 500, 3000, 15000, 50000 }, Mythic = { 4000, 24000, 120000, 400000 },
}
for r, row in income do
	for stage = 0, 3 do
		expect(r .. " stage " .. stage, Economy.dragonIncome({ rarity = r, stage = stage }, B), row[stage + 1])
	end
end
-- §1 the incubation (min) and the growth H->J, J->A, A->E (min)
local timers = {
	Common = { 3, 4, 10, 120 }, Uncommon = { 6, 8, 20, 180 }, Rare = { 15, 15, 40, 240 },
	Epic = { 45, 30, 90, 360 }, Legendary = { 120, 60, 180, 480 }, Mythic = { 360, 120, 360, 480 },
}
for r, row in timers do
	expect(r .. " incubation", B.incubateMin[r], row[1])
	for stage = 0, 2 do
		expect(r .. " growth " .. stage, Growth.stageSeconds(r, stage, B), row[stage + 2] * 60)
	end
end
-- §1 the account's first dragon (05 add. 2.18): own timers H->J, J->A, feeding at the Common price, A->E by its own rarity
expect("firstborn H->J min (24.10: 1)", B.firstDragon.growMin[1], 1)
expect("firstborn J->A min (27.10: 1 - flight before the 3rd minute)", B.firstDragon.growMin[2], 1)
expect("firstborn H->J s", Growth.stageSecondsOf({ rarity = "Rare", stage = 0, growAs = "Common" }, B), 60)
expect("firstborn J->A s", Growth.stageSecondsOf({ rarity = "Rare", stage = 1, growAs = "Common" }, B), 60)
expect("firstborn A->E by its own rarity", Growth.stageSecondsOf({ rarity = "Rare", stage = 2, growAs = "Common" }, B), 240 * 60)
expect("firstborn feeding by Common", Economy.feedPrice({ rarity = "Rare", stage = 0, growAs = "Common" }, 0, B), 60)
-- §2 the odds by zone and "1 in N" for Mythic
local zones = {
	Meadow = { 70, 22.5, 7, 0.45, 0.05, 0 }, Cliffs = { 45, 33, 17, 4.5, 0.45, 0.05 },
	Springs = { 22, 35, 30, 11, 1.9, 0.1 }, Summit = { 8, 27, 40, 20, 4.5, 0.5 },
}
for z, row in zones do
	for i, v in row do
		expect(z .. " " .. Config.Rarities[i], B.zones[z][i], v)
	end
end
expect("Mythic Cliffs", Odds.oneIn({ zone = "Cliffs", rarity = "Mythic" }, B), "1 in 2,000")
expect("Mythic Springs", Odds.oneIn({ zone = "Springs", rarity = "Mythic" }, B), "1 in 1,000")
expect("Mythic Summit", Odds.oneIn({ zone = "Summit", rarity = "Mythic" }, B), "1 in 200")
-- the variants
expect("Shiny p", B.variants.shiny.p, 0.04)
expect("Shiny mult", B.variants.shiny.mult, 2)
expect("Big p", B.variants.big.p, 0.05)
expect("Big mult", B.variants.big.mult, 3)
expect("Huge p", B.variants.huge.p, 0.01)
expect("Huge mult", B.variants.huge.mult, 5)
expect("Ancient p", B.variants.ancient.p, 0.000001)
expect("Ancient mult", B.variants.ancient.mult, 10)
-- 05 §5 the slots
expect("incubator 2", Economy.incubatorPrice(1, B), 5000)
expect("incubator 3", Economy.incubatorPrice(2, B), 250000)
expect("slot 4", Economy.slotPrice(3, B), 2500)
expect("slot 5", Economy.slotPrice(4, B), 60000)
expect("slot 6", Economy.slotPrice(5, B), 1500000)
expect("feed x", B.feed.x, 2)
expect("feed seconds", B.feed.seconds, 300)
expect("feed price s", B.feed.priceSeconds, 60)
expect("feed minimum", B.feed.priceMin, 50)
-- 05 §6 ascension
expect("ascension I", Economy.ascensionCost(1, B), 5000)
expect("ascension II", Economy.ascensionCost(2, B), 250000)
expect("ascension III", Economy.ascensionCost(3, B), 12500000)
expect("ascension IV", Economy.ascensionCost(4, B), 250000000)
-- §6 the Hatch Now ladder by the remainder (the middles of the bands)
for _, pair in { { 30, 5 }, { 180, 9 }, { 750, 19 }, { 2400, 29 }, { 16200, 49 } } do
	expect("Hatch Now at a remainder of " .. pair[1], select(2, Growth.priceTier(pair[1], Config.Shop)), pair[2])
end
-- offline
expect("offline share", B.offline.share, 0.25)
expect("offline cap h", B.offline.capHours, 8)
expect("rare nest p", B.rareNestP, 0.10)

if failed > 0 then
	error("balance_spec: mismatches " .. failed)
end
print("balance_spec: Config matches balance_out.md")
