--!strict
-- 2.7: the weather and the Storm dragon (spec 04 §7-8) - pure logic without Roblox API (the Weather service, the Weather client).
-- The weather: a random interval interval, the duration duration, the first not earlier than firstAfterSeconds of the server; Storm (coins x2 for everyone,
-- those who hatched - Stormborn) or Starfall (the egg spots refill at once, a fast respawn) by the weights p; 2.9 - Aurora (Frost from Summit -> Glacier).
-- The Storm dragon: by the server clock at :00 and :30 (every), duration, the warning warnSeconds; shards shards, a shared scale;
-- the result: full - an egg + minutes of income to everyone, partial - k/n of minutes.

local Weather = {}

-- which weather: a roll by the weights storm.p / starfall.p; from update aurora.update (live - how many updates are running, Core/LiveOps)
-- first Aurora with the share aurora.share, the rest is split by the storm and the starfall by weights
function Weather.pick(W: any, r01: number, live: number?): string
	local A = W.aurora
	if A and (live or 0) >= (A.update or 1) then
		if r01 < A.share then
			return "aurora"
		end
		r01 = (r01 - A.share) / (1 - A.share)
	end
	local total = W.storm.p + W.starfall.p
	return if r01 * total < W.storm.p then "storm" else "starfall"
end

-- in how many seconds the next weather (interval[1]..interval[2]); the first - not earlier than firstAfterSeconds of the server
function Weather.nextIn(W: any, serverAge: number, r01: number): number
	local wait = W.interval[1] + (W.interval[2] - W.interval[1]) * r01
	return math.max(wait, W.firstAfterSeconds - serverAge)
end

-- the Storm dragon by the clock: (seconds to the nearest start, whether it is running now, seconds to the end of the current one)
function Weather.dragonClock(t: number, SD: any): (number, boolean, number)
	local into = t % SD.every
	if into < SD.duration then
		return SD.every - into, true, SD.duration - into
	end
	return SD.every - into, false, 0
end

-- the reward by the result: coins (minutes of income x the share) and whether to give an egg (only at a full scale)
function Weather.dragonReward(k: number, n: number, ratePerSec: number, SD: any, minCoins: number): (number, boolean)
	local share = math.clamp(k / math.max(n, 1), 0, 1)
	if share <= 0 then
		return 0, false
	end
	local coins = math.max(minCoins, math.floor(ratePerSec * 60 * SD.reward.minutes * share))
	return coins, share >= 1
end

-- the shard spots: n points on a ring/glade around the center (deterministic from seed, without Random: testable)
function Weather.shardPoints(n: number, center: { number }, rMin: number, rMax: number, seed: number): { { number } }
	local out = {}
	local x = seed % 2147483647
	local function nxt(): number
		x = (x * 48271) % 2147483647
		return x / 2147483647
	end
	for i = 1, n do
		local a = (i - 1) / n * math.pi * 2 + nxt() * 0.6
		local r = rMin + (rMax - rMin) * nxt()
		table.insert(out, { center[1] + math.cos(a) * r, center[2], center[3] + math.sin(a) * r })
	end
	return out
end

-- the Storm dragon is seen and collected only by players with at least one dragon of stage
-- >= SD.minStage (an adult); without minStage - everyone. dragons - the player's records ({ [uid] = { stage } })
function Weather.eligible(dragons: { [string]: any }?, SD: any): boolean
	local min = SD and SD.minStage
	if not min then
		return true
	end
	if typeof(dragons) ~= "table" then
		return false
	end
	for _, d in dragons do
		if typeof(d) == "table" and (d.stage or 0) >= min then
			return true
		end
	end
	return false
end

-- the Storm dragon settings with chapters - the last chapter whose update is already running, on top of the base ones
function Weather.dragonChapter(SD: any, live: number?): any
	local out = table.clone(SD)
	out.chapters = nil
	out.chapter = 1
	out.scale = SD.scale or 1
	for i, c in SD.chapters or {} do
		if (live or 0) >= (c.update or math.huge) then
			for k, v in c do
				if k ~= "update" then
					out[k] = v
				end
			end
			out.chapter = i + 1
		end
	end
	return out
end

return Weather
