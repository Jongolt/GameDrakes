--!strict
-- 2.7: the weather and Storm dragon spec (spec 04 §7-8). Run from the repository root: luau tests/weather_spec.luau
local Config = require("../src/shared/Config")
local Weather = require("../src/shared/Core/Weather")

local W = Config.Balance.weather
local SD = Config.Balance.stormDragon
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

-- weather by weights 60/40
local storm = 0
for i = 0, 999 do
	if Weather.pick(W, (i + 0.5) / 1000) == "storm" then
		storm += 1
	end
end
check("weather: storm 60%, starfall 40%", storm == 600, storm)
check("weather: the first not earlier than the 10th server minute", Weather.nextIn(W, 0, 0) >= W.firstAfterSeconds and Weather.nextIn(W, 0, 0) == 600)
check("weather: then an interval of 10-20 min", Weather.nextIn(W, 3600, 0) == W.interval[1] and Weather.nextIn(W, 3600, 1) == W.interval[2])

-- the dragon on the clock at :00 and :30
local base = 1800 * 1000
local wait0, on0, left0 = Weather.dragonClock(base + 10, SD)
check("dragon: at :00:10 it is on, 170 s to the end", on0 and left0 == SD.duration - 10 and wait0 == SD.every - 10)
local wait1, on1 = Weather.dragonClock(base + 600, SD)
check("dragon: at :10 it is not on, 20 min to the start", not on1 and wait1 == 1200)

-- reward
local c1, egg1 = Weather.dragonReward(12, 12, 10, SD, 100)
check("reward: a full bar - 10 min of income and an egg", c1 == 6000 and egg1)
local c2, egg2 = Weather.dragonReward(6, 12, 10, SD, 100)
check("reward: half - 5 min, no egg", c2 == 3000 and not egg2)
local c3 = Weather.dragonReward(1, 12, 0, SD, 100)
check("reward: a floor of 100 coins with zero income", c3 == 100)
check("reward: zero shards - nothing", (Weather.dragonReward(0, 12, 10, SD, 100)) == 0)

-- shard points
local pts = Weather.shardPoints(SD.shards, { 0, 0, 0 }, 120, 260, 42)
local okR = #pts == SD.shards
for _, p in pts do
	local r = math.sqrt(p[1] * p[1] + p[3] * p[3])
	if r < 120 - 1e-6 or r > 260 + 1e-6 then
		okR = false
	end
end
check("shards: 12 points in the ring 120-260", okR)
local pts2 = Weather.shardPoints(SD.shards, { 0, 0, 0 }, 120, 260, 42)
check("shards: deterministic from the seed", pts2[5][1] == pts[5][1] and pts2[5][3] == pts[5][3])

-- chapter 2 of the Storm dragon
local c1, c2 = Weather.dragonChapter(SD, 2), Weather.dragonChapter(SD, 3)
check("chapter 1 before update 3: 12 shards, Cliffs egg, scale 1", c1.chapter == 1 and c1.shards == 12 and c1.reward.egg == "Cliffs" and c1.scale == 1)
check("chapter 2 from update 3: 16 shards, Springs egg, bigger", c2.chapter == 2 and c2.shards == 16 and c2.reward.egg == "Springs" and c2.scale > 1)
check("the chapters do not spoil the source config", SD.shards == 12 and SD.reward.egg == "Cliffs" and c2.every == SD.every and c2.duration == SD.duration)

-- the event only for players with at least one dragon of stage >= minStage (adult)
check("dragon: the stage threshold 2 (adult)", SD.minStage == 2)
check("dragon: a newcomer without dragons does not take part", not Weather.eligible({}, SD) and not Weather.eligible(nil, SD))
check("dragon: a baby and a teen do not give the right", not Weather.eligible({ d1 = { stage = 0 }, d2 = { stage = 1 } }, SD))
check("dragon: one adult (in the nest or the sanctuary) - takes part", Weather.eligible({ d1 = { stage = 0 }, d2 = { stage = 2, inNest = false } }, SD))
check("dragon: an elder - takes part", Weather.eligible({ d1 = { stage = 3 } }, SD))
check("dragon: without a threshold - everyone", Weather.eligible({}, { every = 1800 }))
check("dragon: chapter 2 inherits the threshold", Weather.dragonChapter(SD, 3).minStage == 2)

print(string.format("weather spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed checks")
end
