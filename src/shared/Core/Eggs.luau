--!strict
-- The eggs (03, 04 §4, 05 §3): the rarity tables by zone, the rare nest, the elements, the variants, the outcome roll at the spawn,
-- the incubation time. Pure logic; the randomness from outside (rng() -> [0, 1)); the numbers from Config.Balance (B).

local Rarity = require("./Rarity")

local Eggs = {}

export type Egg = {
	id: string,
	element: string,
	rarity: string,
	shiny: boolean,
	size: string, -- "normal" | "big" | "huge"
	zone: string,
	rareNest: boolean,
	foundAt: number?, -- the pickup moment (unix) - for the warmth bar
	cold: boolean?, -- got cold in the hands: the incubation x1.5
	glow: boolean?, -- a glowing egg (Services/GlowEgg) - a glowing dragon comes from it
}

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
Eggs.RARITIES = RARITIES

function Eggs.rarityIndex(r: string): number
	return table.find(RARITIES, r) or 0
end

local function weights(list: { number }): { Rarity.Outcome }
	local out = {}
	for i, w in list do
		table.insert(out, { id = RARITIES[i], weight = w })
	end
	return out
end

-- The rarity table: the zone, at a rare nest - the next zone (Summit -> summitRareNest)
function Eggs.rarityTable(zone: string, rareNest: boolean, B: any): { Rarity.Outcome }
	local z = zone
	if rareNest then
		local i = table.find(B.zoneOrder, zone)
		assert(i, "unknown zone " .. zone)
		if i == #B.zoneOrder then
			return weights(B.summitRareNest)
		end
		z = B.zoneOrder[i + 1]
	end
	local list = B.zones[z]
	assert(list, "unknown zone " .. z)
	return weights(list)
end

-- The element table: the two home ones at 30%, the rest at 10%
function Eggs.elementTable(zone: string, B: any, elements: { string }): { Rarity.Outcome }
	local home = B.homeElements[zone]
	assert(home, "no home elements for " .. zone)
	local out = {}
	for _, e in elements do
		local w = if table.find(home, e) then B.homeElementP else B.otherElementP
		table.insert(out, { id = e, weight = w })
	end
	return out
end

-- The size: one roll, Huge is checked first
function Eggs.rollSize(rng: () -> number, B: any): string
	local x = rng()
	if x < B.variants.huge.p then
		return "huge"
	elseif x < B.variants.huge.p + B.variants.big.p then
		return "big"
	end
	return "normal"
end

-- The egg outcome is fixed at the spawn on the spot (04 §4): the element, the rarity, the variants
function Eggs.roll(id: string, zone: string, rareNest: boolean, rng: () -> number, B: any, elements: { string }): Egg
	return {
		id = id,
		element = Rarity.roll(Eggs.elementTable(zone, B, elements), rng),
		rarity = Rarity.roll(Eggs.rarityTable(zone, rareNest, B), rng),
		shiny = rng() < B.variants.shiny.p,
		size = Eggs.rollSize(rng, B),
		zone = zone,
		rareNest = rareNest,
	}
end

-- A guaranteed egg: the rarities below minRarity are cut out of the zone table (Free Gift, the calendar, Keeper 15)
function Eggs.rollGuaranteed(id: string, zone: string, minRarity: string, rng: () -> number, B: any, elements: { string }, element: string?): Egg
	local minIdx = Eggs.rarityIndex(minRarity)
	assert(minIdx > 0, "unknown rarity " .. minRarity)
	local table_ = Eggs.rarityTable(zone, false, B)
	local cut = {}
	for i, o in table_ do
		table.insert(cut, { id = o.id, weight = if i >= minIdx then o.weight else 0 })
	end
	local sum = 0
	for _, o in cut do
		sum += o.weight
	end
	if sum <= 0 then
		cut = { { id = minRarity, weight = 1 } }
	end
	return {
		id = id,
		element = element or Rarity.roll(Eggs.elementTable(zone, B, elements), rng),
		rarity = Rarity.roll(cut, rng),
		shiny = rng() < B.variants.shiny.p,
		size = Eggs.rollSize(rng, B),
		zone = zone,
		rareNest = false,
	}
end

-- Whether the egg got cold: in the hands longer than warmSeconds (on the shelf it does not cool - the server clears foundAt when placing on the shelf)
function Eggs.isCold(carriedSeconds: number, B: any): boolean
	return carriedSeconds > B.egg.warmSeconds
end

export type IncubationMods = { fastIncubator: boolean?, firstEgg: boolean? }

-- The incubation duration in seconds: the table x cold 1.5 x Fast Incubator 0.6; the newcomer's first egg - 3 s
function Eggs.incubationSeconds(egg: Egg, mods: IncubationMods, B: any): number
	if mods.firstEgg then
		return B.egg.firstHatchSeconds
	end
	local minutes = B.incubateMin[egg.rarity]
	assert(minutes, "unknown rarity " .. egg.rarity)
	local s = minutes * 60
	if egg.cold then
		s *= B.egg.coldMult
	end
	if mods.fastIncubator then
		s *= B.fastIncubatorMult
	end
	return math.floor(s + 0.5)
end

return Eggs
