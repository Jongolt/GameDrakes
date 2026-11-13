--!strict
-- the dragon voices and the hatch ladder by rarity (spec 03 §10 add. 17.10). Pure logic: which file and which
-- pitch the voice has by stage and occasion, the hatch sound name by rarity, the pause until the next "life" voice at the nest.
-- The data - Content.Voices / Content.Sounds; the client - Controllers/Sounds; the check - tests/voices_spec.luau.

local Voices = {}

export type Entry = { id: number, speed: number }

local RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

-- the stage set: its own record or (Elder and older) the adult's record lower by elderSpeed; no stage - the hatchling
local function stageSet(V: any, stage: number): (any, number)
	local s = V.stages[stage]
	if s then
		return s, 1
	end
	if stage >= 3 and V.stages[2] then
		return V.stages[2], V.elderSpeed or 1
	end
	return V.stages[0], 1
end

-- r in [0, 1): which variant. The stage has no occasion (a hatchling has no roar) - its usual call voice
function Voices.pick(V: any, stage: number?, kind: string, r: number): Entry?
	if not V or not V.stages then
		return nil
	end
	local s, mul = stageSet(V, math.floor(stage or 0))
	if not s then
		return nil
	end
	local list = s[kind] or s.call
	if not list or #list == 0 then
		return nil
	end
	local i = math.clamp(math.floor(r * #list) + 1, 1, #list)
	local e = list[i]
	return { id = e.id, speed = (e.speed or 1) * mul }
end

-- the sound at the egg crack: an own step for every rarity, an unknown one - the common hatch
function Voices.hatchName(rarity: string?): string
	if typeof(rarity) == "string" and table.find(RARITIES, rarity) then
		return "hatch_" .. rarity
	end
	return "hatch"
end

-- Mythic starts before the crack (a crescendo under the egg rise), the rest - at the crack
function Voices.hatchStartsEarly(rarity: string?): boolean
	return rarity == "Mythic"
end

-- in how many seconds the next voice at the nest (r in [0, 1))
function Voices.nextIdle(V: any, r: number): number
	local e = V.idle.every
	return e[1] + (e[2] - e[1]) * r
end

Voices.RARITIES = RARITIES

return Voices
