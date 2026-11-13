--!strict
-- the dragon Index (spec 03 §5, 06 §7). 36 entries = element x rarity (Config.Elements x Config.Rarities)
-- the key `Dragons.indexKey` = "element:Rarity"; the Keeper's entry "keeper" (Old Ash's gift at the first hatch, 02 §2 0:18) belongs
-- only to the Meadow set. The sets: Meadow (10 entries) and 6 element sets (all rarities); the set reward - minutes of the nest income.
-- The Index percentage (36 entries) gives an income bonus by the thresholds Config.Balance.index.thresholds (Economy.indexBonus).
local Index = {}

export type Set = { id: string, name: string, keys: { string }, minutes: number }

local ELEMENTS: { string } = { "ember", "frost", "moss", "tide", "storm", "dusk" }
local RARITIES: { string } = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

function Index.setup(elements: { string }, rarities: { string })
	ELEMENTS = elements
	RARITIES = rarities
end

function Index.elements(): { string }
	return ELEMENTS
end

function Index.rarities(): { string }
	return RARITIES
end

function Index.key(element: string, rarity: string): string
	return element .. ":" .. rarity
end

-- all 36 keys by element rows
function Index.keys(): { string }
	local out = {}
	for _, el in ELEMENTS do
		for _, r in RARITIES do
			table.insert(out, Index.key(el, r))
		end
	end
	return out
end

function Index.total(): number
	return #ELEMENTS * #RARITIES
end

-- entries unlocked (without the Keeper's entry)
function Index.count(index: { [string]: any }?): number
	local n = 0
	for _, k in Index.keys() do
		if index and index[k] then
			n += 1
		end
	end
	return n
end

function Index.pct(index: { [string]: any }?): number
	return Index.count(index) / Index.total()
end

local function titleCase(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- the sets: Meadow (6 Common + Ember/Moss/Tide Uncommon + the Keeper's entry) and by element
function Index.sets(): { Set }
	local out: { Set } = {}
	local meadow = {}
	for _, el in ELEMENTS do
		table.insert(meadow, Index.key(el, RARITIES[1]))
	end
	for _, el in { "ember", "moss", "tide" } do
		table.insert(meadow, Index.key(el, RARITIES[2] or RARITIES[1]))
	end
	table.insert(meadow, "keeper")
	table.insert(out, { id = "meadow", name = "Meadow set", keys = meadow, minutes = 5 })
	for _, el in ELEMENTS do
		local keys = {}
		for _, r in RARITIES do
			table.insert(keys, Index.key(el, r))
		end
		table.insert(out, { id = el, name = titleCase(el) .. " set", keys = keys, minutes = 30 })
	end
	return out
end

function Index.set(id: string): Set?
	for _, s in Index.sets() do
		if s.id == id then
			return s
		end
	end
	return nil
end

function Index.setProgress(index: { [string]: any }?, s: Set): (number, number)
	local k = 0
	for _, key in s.keys do
		if index and index[key] then
			k += 1
		end
	end
	return k, #s.keys
end

function Index.setComplete(index: { [string]: any }?, s: Set): boolean
	local k, n = Index.setProgress(index, s)
	return k >= n
end

-- the sets that are complete and not yet claimed
function Index.claimable(index: { [string]: any }?, claimed: { [string]: any }?): { Set }
	local out = {}
	for _, s in Index.sets() do
		if Index.setComplete(index, s) and not (claimed and claimed[s.id]) then
			table.insert(out, s)
		end
	end
	return out
end

-- the current bonus threshold and the next: (the bonus now, the next bonus, the share for it) by thresholds { {share, bonus} }
function Index.tier(pct: number, thresholds: { { number } }): (number, number?, number?)
	local now = 0
	for _, t in thresholds do
		if pct >= t[1] then
			now = t[2]
		elseif pct < t[1] then
			return now, t[2], t[1]
		end
	end
	return now, nil, nil
end

function Index.display(element: string): string
	return titleCase(element)
end

return Index
