--!strict
-- The player's dragons (10 §6): the records, the nest (slots) and the sanctuary, auto-best in the nest, the companion, the release. Pure logic;
-- now is passed from outside, the numbers from Config.Balance (B).

local Economy = require("./Economy")
local Growth = require("./Growth")

local Dragons = {}

export type Dragon = {
	uid: string,
	element: string,
	rarity: string,
	stage: number,
	stageEndsAt: number?,
	fedUntil: number?,
	glow: boolean?, -- from a glowing egg - glows (Controllers/Glow)
	shiny: boolean,
	size: string,
	stormborn: boolean,
	variant: string?,
	name: string,
	hatchedAt: number,
	inNest: boolean,
	preset: string?,
	growAs: string?, -- 05 add. 2.18: the firstborn grows and is fed by this rarity until an adult
	growGroup: string?, -- the firstborn growth test group ("B" - 3/9 min; no field - 2/6), Config.Balance.firstDragon.ab
}

export type Inventory = {
	dragons: { [string]: Dragon },
	nestOrder: { string },
	companion: string?,
	nextUid: number,
}

function Dragons.newInventory(): Inventory
	return { dragons = {}, nestOrder = {}, companion = nil, nextUid = 1 }
end

local function titleCase(s: string): string
	return (s:gsub("^%l", string.upper))
end

-- The dragon record from an egg; stormborn - whether a storm is on at the moment of the hatch. The first stage timer starts from now.
-- first - the account's first hatch: grows by the firstborn timers and is fed at the growAs price until an adult (the mark
-- also for Common).
-- group - the firstborn growth test group (Core/Experiments.growGroup); "B" sets the growGroup mark, "A" and nil - no mark
function Dragons.fromEgg(inv: Inventory, egg: { element: string, rarity: string, shiny: boolean, size: string }, now: number, stormborn: boolean, B: any, first: boolean?, group: string?): Dragon
	local d: Dragon = {
		uid = "d" .. inv.nextUid,
		element = egg.element,
		rarity = egg.rarity,
		stage = 0,
		stageEndsAt = nil,
		fedUntil = nil,
		shiny = egg.shiny,
		glow = if (egg :: any).glow == true then true else nil,
		size = egg.size,
		stormborn = stormborn,
		variant = nil,
		name = if (egg :: any).glow == true then "Glowing " .. titleCase(egg.element) else titleCase(egg.element),
		hatchedAt = now,
		inNest = false,
		preset = nil,
		growAs = nil,
		growGroup = nil,
	}
	inv.nextUid += 1
	local F = B.firstDragon
	if first and F then -- the mark is set for Common too - the firstborn timers F.growMin go by it (Growth.stageSecondsOf)
		d.growAs = F.growAs
		if group == "B" and F.ab and F.ab.on and F.ab.growMinB then -- with the test off the mark is not set
			d.growGroup = "B"
		end
	end
	Growth.start(d, now, B)
	return d
end

function Dragons.income(d: Dragon, B: any): number
	return Economy.dragonIncome(d :: any, B)
end

function Dragons.nestList(inv: Inventory): { Dragon }
	local out: { Dragon } = {}
	for _, uid in inv.nestOrder do
		local d = inv.dragons[uid]
		if d then
			table.insert(out, d)
		end
	end
	return out
end

function Dragons.sanctuaryList(inv: Inventory): { Dragon }
	local out: { Dragon } = {}
	for _, d in inv.dragons do
		if not d.inNest then
			table.insert(out, d)
		end
	end
	table.sort(out, function(a: Dragon, b: Dragon): boolean
		return a.uid < b.uid
	end)
	return out
end

function Dragons.count(inv: Inventory): number
	local n = 0
	for _ in inv.dragons do
		n += 1
	end
	return n
end

-- the slot in the nest is decided by the potential - the rarity income x the variants, without the stage: a Rare hatchling (16) is worth more
-- than an adult Common (1, although now it gives 30/s) - after an hour of growth it will give 480. At equal potential the weaker is the one giving less now.
function Dragons.potential(d: Dragon, B: any): number
	local base = B.baseIncome[d.rarity]
	assert(base, "unknown rarity " .. tostring(d.rarity))
	return base * Economy.variantMult(d :: any, B)
end

-- a is weaker than b: a lower potential, at an equal one - a lower current income
local function weakerThan(a: Dragon, b: Dragon, B: any): boolean
	local pa, pb = Dragons.potential(a, B), Dragons.potential(b, B)
	if pa ~= pb then
		return pa < pb
	end
	return Economy.dragonIncome(a :: any, B) < Economy.dragonIncome(b :: any, B)
end

-- The weakest in the nest (by potential); excludeUid - whom not to touch (the companion at an auto swap)
function Dragons.weakestInNest(inv: Inventory, B: any, excludeUid: string?): Dragon?
	local worst: Dragon? = nil
	for _, d in Dragons.nestList(inv) do
		if d.uid ~= excludeUid and (worst == nil or weakerThan(d, worst :: Dragon, B)) then
			worst = d
		end
	end
	return worst
end

function Dragons.best(inv: Inventory, B: any): Dragon?
	local best, bestIncome = nil, -1
	for _, d in Dragons.nestList(inv) do
		local inc = Economy.dragonIncome(d :: any, B)
		if inc > bestIncome then
			best, bestIncome = d, inc
		end
	end
	return best
end

-- Add a dragon: into the nest if there is a slot; otherwise, if it is stronger (the potential, see weakerThan) than the weakest in the nest, -
-- it replaces it (the weak one goes to the sanctuary); otherwise into the sanctuary. Returns "nest" | "swapped" | "sanctuary" and the displaced one (at swapped).
function Dragons.add(inv: Inventory, d: Dragon, slots: number, B: any): (string, Dragon?)
	inv.dragons[d.uid] = d
	if #inv.nestOrder < slots then
		d.inNest = true
		table.insert(inv.nestOrder, d.uid)
		if inv.companion == nil then
			inv.companion = d.uid
		end
		return "nest", nil
	end
	local weak = Dragons.weakestInNest(inv, B, inv.companion)
	if weak and weakerThan(weak, d, B) then
		weak.inNest = false
		local i = table.find(inv.nestOrder, weak.uid)
		if i then
			table.remove(inv.nestOrder, i)
		end
		d.inNest = true
		table.insert(inv.nestOrder, d.uid)
		return "swapped", weak
	end
	d.inNest = false
	return "sanctuary", nil
end

function Dragons.moveToNest(inv: Inventory, uid: string, slots: number): (boolean, string?)
	local d = inv.dragons[uid]
	if not d then
		return false, "no_dragon"
	end
	if d.inNest then
		return false, "already"
	end
	if #inv.nestOrder >= slots then
		return false, "nest_full"
	end
	d.inNest = true
	table.insert(inv.nestOrder, uid)
	return true, nil
end

function Dragons.moveToSanctuary(inv: Inventory, uid: string, sanctuaryCap: number): (boolean, string?)
	local d = inv.dragons[uid]
	if not d then
		return false, "no_dragon"
	end
	if not d.inNest then
		return false, "already"
	end
	if uid == inv.companion then
		return false, "companion"
	end
	if #Dragons.sanctuaryList(inv) >= sanctuaryCap then
		return false, "sanctuary_full"
	end
	d.inNest = false
	local i = table.find(inv.nestOrder, uid)
	if i then
		table.remove(inv.nestOrder, i)
	end
	return true, nil
end

function Dragons.setCompanion(inv: Inventory, uid: string): (boolean, string?)
	local d = inv.dragons[uid]
	if not d then
		return false, "no_dragon"
	end
	if not d.inNest then
		return false, "not_in_nest"
	end
	inv.companion = uid
	return true, nil
end

-- The release: not the companion; returns coins = 120 s of income (05 §1). The Index entry stays with the caller.
function Dragons.release(inv: Inventory, uid: string, B: any): (boolean, number, string?)
	local d = inv.dragons[uid]
	if not d then
		return false, 0, "no_dragon"
	end
	if uid == inv.companion then
		return false, 0, "companion"
	end
	local refund = Economy.releaseRefund(d :: any, B)
	inv.dragons[uid] = nil
	local i = table.find(inv.nestOrder, uid)
	if i then
		table.remove(inv.nestOrder, i)
	end
	return true, refund, nil
end

function Dragons.rename(inv: Inventory, uid: string, name: string, maxLen: number): (boolean, string?)
	local d = inv.dragons[uid]
	if not d then
		return false, "no_dragon"
	end
	local trimmed = name:gsub("^%s+", ""):gsub("%s+$", "")
	if #trimmed == 0 or #trimmed > maxLen then
		return false, "bad_name"
	end
	d.name = trimmed
	return true, nil
end

-- the Index key: element:rarity
function Dragons.indexKey(d: { element: string, rarity: string }): string
	return d.element .. ":" .. d.rarity
end

-- Distinct elements among the nest dragons of stage >= minStage (for the ascension requirements)
function Dragons.elementsAtStage(inv: Inventory, minStage: number): number
	local seen = {}
	local n = 0
	for _, d in Dragons.nestList(inv) do
		if d.stage >= minStage and not seen[d.element] then
			seen[d.element] = true
			n += 1
		end
	end
	return n
end

return Dragons
