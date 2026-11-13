--!strict
-- A weighted roll. Pure logic: the random number is passed from outside (rng() -> [0, 1)), so that in Roblox we substitute
-- Random.new():NextNumber() and in the tests a deterministic function. A weight of 0 is allowed (the outcome is closed in this zone).
-- applyLuck is kept for the free weather modifiers (there is no luck for Robux, 07 §1 item 4).

local Rarity = {}

export type Outcome = { id: string, weight: number }

local function totalWeight(outcomes: { Outcome }): number
	local sum = 0
	for _, o in outcomes do
		assert(o.weight >= 0, "outcome weight must be >= 0: " .. o.id)
		sum += o.weight
	end
	assert(sum > 0, "the sum of weights must be > 0")
	return sum
end

-- The weights with luck: the weight of an outcome with chance p is multiplied by luck^(-log10 p). A new array, the input is not changed.
function Rarity.applyLuck(outcomes: { Outcome }, luck: number): { Outcome }
	assert(luck >= 1, "luck cannot be less than 1")
	local sum = totalWeight(outcomes)
	local out: { Outcome } = {}
	for i, o in outcomes do
		if o.weight == 0 then
			out[i] = { id = o.id, weight = 0 }
		else
			local p = o.weight / sum
			out[i] = { id = o.id, weight = o.weight * luck ^ (-math.log10(p)) }
		end
	end
	return out
end

-- The chances as shares (to show the player)
function Rarity.chances(outcomes: { Outcome }, luck: number?): { [string]: number }
	local list = if luck and luck > 1 then Rarity.applyLuck(outcomes, luck) else outcomes
	local sum = totalWeight(list)
	local res = {}
	for _, o in list do
		res[o.id] = o.weight / sum
	end
	return res
end

function Rarity.roll(outcomes: { Outcome }, rng: () -> number, luck: number?): string
	local list = if luck and luck > 1 then Rarity.applyLuck(outcomes, luck) else outcomes
	local sum = totalWeight(list)
	local x = rng() * sum
	local last = list[1].id
	for _, o in list do
		if o.weight > 0 then
			last = o.id
			x -= o.weight
			if x < 0 then
				return o.id
			end
		end
	end
	return last -- protection against rounding error: the last outcome with a non-zero weight
end

return Rarity
