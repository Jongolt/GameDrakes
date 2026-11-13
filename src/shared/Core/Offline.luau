--!strict
-- 2.5 (spec 05 §8, 10 §7, 06 §9): the "while you were away" summary at the entry. Pure logic without Roblox API.
-- The coins = the nest rate BEFORE the growth x min(away, 8 h) x 0.25 (Economy.offlineEarnings). The offline rate includes ascension, VIP,
-- x2 and the Index; friends on the server, the weather and the bought boost - online only (the boost is spent in seconds in the game).
-- The eggs - how many are ready in the incubators (the hatch by a tap, the scene). The growth - whose stage timer ran out: the first Nest sweep
-- (Growth.tick) raises exactly one stage and starts the timer from now - "not farther than the next stage".
-- Less than minAwaySeconds (10 min), the first entry (lastSeen = 0) or nothing to say - nil.

local Economy = require("./Economy")

local Offline = {}

export type Grew = { uid: string, name: string, stage: number } -- stage - the new stage
export type Summary = { seconds: number, coins: number, eggs: number, grew: { Grew } }

-- the income modifiers outside the game: a copy of the online set without friends, the weather and the boost
function Offline.mods(mods: { [string]: any }): { [string]: any }
	local m = table.clone(mods)
	m.friends = nil
	m.weatherMult = nil
	m.boost = nil
	return m
end

function Offline.summary(data: any, lastSeen: number, now: number, mods: { [string]: any }, B: any): Summary?
	local seconds = now - lastSeen
	if lastSeen <= 0 or seconds < B.offline.minAwaySeconds then
		return nil
	end
	local list = {}
	local grew: { Grew } = {}
	for _, uid in data.nestOrder or {} do
		local d = data.dragons and data.dragons[uid]
		if type(d) == "table" then
			table.insert(list, d)
			if type(d.stageEndsAt) == "number" and d.stageEndsAt <= now and (d.stage or 0) < 3 then
				table.insert(grew, { uid = tostring(uid), name = tostring(d.name or ""), stage = (d.stage or 0) + 1 })
			end
		end
	end
	local coins = Economy.offlineEarnings(Economy.nestRate(list :: any, Offline.mods(mods) :: any, B), seconds, B)
	local eggs = 0
	for _, rec in (data.eggs and data.eggs.incubating) or {} do
		if type(rec) == "table" and type(rec.endsAt) == "number" and rec.endsAt <= now then
			eggs += 1
		end
	end
	if coins <= 0 and eggs == 0 and #grew == 0 then
		return nil
	end
	return { seconds = seconds, coins = coins, eggs = eggs, grew = grew }
end

-- an empty profile record (ProfileStore: without nil and holes)
function Offline.empty(): { coins: number, seconds: number, eggs: number, grew: { Grew } }
	return { coins = 0, seconds = 0, eggs = 0, grew = {} }
end

-- the profile record at the entry: a new summary + the coins not claimed last time (the growth and egg lines - only fresh ones)
function Offline.merge(prev: any, s: Summary?): { coins: number, seconds: number, eggs: number, grew: { Grew } }
	local carry = if type(prev) == "table" and type(prev.coins) == "number" then math.max(0, math.floor(prev.coins)) else 0
	if not s then
		local e = Offline.empty()
		e.coins = carry
		return e
	end
	return { coins = s.coins + carry, seconds = s.seconds, eggs = s.eggs, grew = s.grew }
end

-- whether to show the card
function Offline.hasNews(a: any): boolean
	return type(a) == "table" and ((tonumber(a.coins) or 0) > 0 or (tonumber(a.eggs) or 0) > 0 or (type(a.grew) == "table" and #a.grew > 0))
end

return Offline
