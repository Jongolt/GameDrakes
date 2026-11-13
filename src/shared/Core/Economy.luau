--!strict
-- The nest economy (05): the dragon and nest income, feeding, offline, the slot prices, ascension. Pure logic without Roblox API;
-- the numbers come from Config.Balance (B). The mirror: the balance simulator (kept outside this repository).

local Growth = require("./Growth") -- 05 add. 2.18: the firstborn rule (timerRarity)

local Economy = {}

export type DragonLike = { rarity: string, stage: number, shiny: boolean?, size: string?, stormborn: boolean?, growAs: string?, variant: string? }

export type Mods = {
	ascension: number, -- ascension steps
	vip: boolean?,
	x2: boolean?,
	friends: number?, -- friends on the server
	indexPct: number?, -- the Index share 0..1
	weatherMult: number?, -- a storm 2
	boost: boolean?, -- the bought boost x2
}

function Economy.variantMult(d: DragonLike, B: any): number
	local v = B.variants
	local m = 1
	if d.shiny then
		m *= v.shiny.mult
	end
	if d.size == "huge" then
		m *= v.huge.mult
	elseif d.size == "big" then
		m *= v.big.mult
	end
	if d.stormborn then
		m *= v.stormborn.mult
	end
	local vd = if d.variant then v[d.variant] else nil -- 2.9: the element variant (glacier, pearl; ancient) - the multiplier from Balance.variants
	if vd and vd.mult then
		m *= vd.mult
	end
	return m
end

-- coins/s of one dragon without the nest multipliers
function Economy.dragonIncome(d: DragonLike, B: any): number
	local base = B.baseIncome[d.rarity]
	assert(base, "unknown rarity " .. tostring(d.rarity))
	local stageMult = B.stageMult[d.stage + 1]
	assert(stageMult, "unknown stage " .. tostring(d.stage))
	return base * stageMult * Economy.variantMult(d, B)
end

function Economy.friendsBonus(friends: number, B: any): number
	return math.min(math.max(friends, 0) * B.friends.perFriend, B.friends.max)
end

function Economy.indexBonus(pct: number, B: any): number
	local bonus = 0
	for _, t in B.index.thresholds do
		if pct >= t[1] then
			bonus = t[2]
		end
	end
	return bonus
end

-- The nest income = the sum of the dragons x (1 + ascension) x VIP x x2 x (1 + friends) x (1 + the index) x the weather x the boost (05 §2)
function Economy.nestRate(dragons: { DragonLike }, mods: Mods, B: any): number
	local sum = 0
	for _, d in dragons do
		sum += Economy.dragonIncome(d, B)
	end
	local rate = sum * (1 + mods.ascension)
	if mods.vip then
		rate *= B.vipMult
	end
	if mods.x2 then
		rate *= B.x2Mult
	end
	rate *= 1 + Economy.friendsBonus(mods.friends or 0, B)
	rate *= 1 + Economy.indexBonus(mods.indexPct or 0, B)
	rate *= mods.weatherMult or 1
	if mods.boost then
		rate *= B.boostMult
	end
	return rate
end

-- Offline: rate x min(away, 8 h) x 0.25; less than 10 minutes away - nothing (10 §7)
function Economy.offlineEarnings(ratePerSecond: number, secondsAway: number, B: any): number
	if secondsAway < B.offline.minAwaySeconds or ratePerSecond <= 0 then
		return 0
	end
	local seconds = math.min(secondsAway, B.offline.capHours * 3600)
	return math.floor(ratePerSecond * seconds * B.offline.share)
end

-- The feed price = 60 s of this dragon's income with ascension, not less than 50 (the sim mirror)
-- 05 add. 2.18: the firstborn until an adult is fed at the growAs price (the rule - Growth.timerRarity)
function Economy.feedPrice(d: DragonLike, ascension: number, B: any): number
	local r = Growth.timerRarity(d :: any, B)
	local base: DragonLike = if r ~= d.rarity then { rarity = r, stage = d.stage, shiny = d.shiny, size = d.size, stormborn = d.stormborn, variant = d.variant } else d
	return math.max(B.feed.priceMin, math.floor(B.feed.priceSeconds * Economy.dragonIncome(base, B) * (1 + ascension)))
end

function Economy.minutesOfIncome(rate: number, minutes: number): number
	return math.floor(rate * 60 * minutes)
end

-- The ascension ladder: 5K, then x50, x50, then x20 (05 §6); step from 1
function Economy.ascensionCost(step: number, B: any): number
	assert(step >= 1, "step from 1")
	local cost = B.ascension.base
	for i = 1, step - 1 do
		cost *= B.ascension.mult[math.min(i, #B.ascension.mult)]
	end
	return cost
end

-- The step requirement: the stage (2 Adult / 3 Elder) and the number of distinct elements among such dragons
function Economy.ascensionNeed(step: number, B: any): { stage: number, elements: number }
	local a = B.ascension
	local stage = if step >= a.elderFrom then 3 else 2
	local elements = 1
	if step >= a.threeElementsFrom then
		elements = 3
	elseif step >= a.twoElementsFrom then
		elements = 2
	end
	return { stage = stage, elements = elements }
end

-- The price of the next slot for coins by the current slot count (3 -> 2,500 ...); nil - the coin slots are over
function Economy.slotPrice(currentSlots: number, B: any): number?
	return B.slots.coins[currentSlots - B.slots.start + 1]
end

function Economy.incubatorPrice(current: number, B: any): number?
	return B.incubators.coins[current - B.incubators.start + 1]
end

function Economy.shelfPrice(current: number, B: any): number?
	return if current < B.shelf.max then B.shelf.plus2 else nil
end

function Economy.sanctuaryPrice(level: number, B: any): number?
	return B.sanctuary.plus10[level + 1]
end

-- Releasing a dragon returns 120 s of its income (less than it cost to raise: breeding for release is unprofitable)
function Economy.releaseRefund(d: DragonLike, B: any): number
	return math.floor(Economy.dragonIncome(d, B) * B.release.seconds)
end

-- The ceiling of the coin pile in the nest: 60 minutes of income
function Economy.potCap(rate: number, B: any): number
	return rate * 60 * B.potCapMinutes
end

return Economy
