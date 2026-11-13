--!strict
-- the dragon power, the stage table, the arena waves, the rewards, the auto aim, the guard pulse.
-- Run from the repository root: luau tests/combat_spec.luau
local Config = require("../src/shared/Config")
local Combat = require("../src/shared/Core/Combat")
local Economy = require("../src/shared/Core/Economy")

local C = Config.Combat
local B = Config.Balance
local passed, failed = 0, 0
local function check(name: string, cond: boolean)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name)
	end
end
local function near(a: number, b: number): boolean
	return math.abs(a - b) < 1e-6
end

local NOW = 1000
local function dragon(rarity: string, stage: number, fed: boolean?): any
	return { uid = "x", element = "ember", rarity = rarity, stage = stage, shiny = false, size = "normal", stormborn = false,
		fedUntil = if fed then NOW + 10 else nil }
end

-- the power: the income scale (spec 19 §2)
local function data1(d: any, extra: { any }?, asc: number?): any
	local dragons = { a = d }
	local order = { "a" }
	for i, e in extra or {} do
		local k = "e" .. i
		dragons[k] = e
		table.insert(order, k)
	end
	return { dragons = dragons, nestOrder = order, companion = "a", ascension = asc or 0 }
end
check("power: a Common hatchling = 1", near(Combat.power(data1(dragon("Common", 0)), NOW, C, B), 1))
check("power: a Common teen = 6", near(Combat.power(data1(dragon("Common", 1)), NOW, C, B), 6))
check("power: a Common adult = 30", near(Combat.power(data1(dragon("Common", 2)), NOW, C, B), 30))
check("power: a fed teen x2 = 12", near(Combat.power(data1(dragon("Common", 1, true)), NOW, C, B), 12))
check("power: the feed ran out - no x2", near(Combat.power(data1(dragon("Common", 1, false)), NOW, C, B), 6))
check("power: Ascension I doubles", near(Combat.power(data1(dragon("Common", 2), nil, 1), NOW, C, B), 60))
check("power: the other nest dragons +10%", near(Combat.power(data1(dragon("Common", 2), { dragon("Uncommon", 2) }), NOW, C, B), 30 + 12))
check("power: without a companion 0", Combat.power({ dragons = {}, nestOrder = {}, ascension = 0 }, NOW, C, B) == 0)
check("power: a companion with a foreign uid 0", Combat.power({ dragons = {}, nestOrder = {}, companion = "zz", ascension = 0 }, NOW, C, B) == 0)
check("damage: not less than 1 and an integer", Combat.damage(0.2) == 1 and Combat.damage(6.4) == 6 and Combat.damage(29.6) == 30)

-- the stage table
check("10 stages", Combat.stageCount(C) == 10)
check("guards at 5 and 10", (C.stages[5].guardian == true) and (C.stages[10].guardian == true))
check("the sky from the 6th", Combat.firstSky(C) == 6)
for k, s in C.stages do
	check("stage " .. k .. ": hp > 0 and n for an ordinary one", s.hp > 0 and (s.guardian == true or (s.n or 0) >= 1))
	check("stage " .. k .. ": not more than 9 enemies", (s.n or 1) <= 9)
	if s.guardian then
		check("guard " .. k .. ": a timer and a name", (s.seconds or 0) > 0 and typeof(s.name) == "string")
	end
end
-- the first dragon's time by spec 19 §3 (2 hits/s)
local function seconds(k: number, power: number): number
	return Combat.waveHp(C.stages[k]) / (power * 2)
end
check("spec: stage 1 with a hatchling <= 5 s", seconds(1, 1) <= 5)
check("spec: stage 3 with a hatchling <= 40 s", seconds(3, 1) <= 40)
check("spec: guard I with a teen within the timer", seconds(5, 6) <= C.stages[5].seconds)
check("spec: guard I cannot be taken with a hatchling", seconds(5, 1) > C.stages[5].seconds)
check("spec: guard II cannot be taken with a fed Common adult", seconds(10, 60) > C.stages[10].seconds)
check("spec: guard II is taken with a fed Uncommon adult", seconds(10, 240) <= C.stages[10].seconds)

-- the arena waves
local function wave(cleared: number, arena: string): (number?, boolean)
	return Combat.waveFor(C, cleared, arena)
end
local w, r = wave(0, "meadow")
check("meadow: a newcomer - stage 1", w == 1 and r == false)
w, r = wave(4, "meadow")
check("meadow: after the 4th - the guard", w == 5 and r == false)
w, r = wave(5, "meadow")
check("meadow: after the guard - a replay of the 4th", w == 4 and r == true)
w = wave(4, "sky")
check("sky: closed until the meadow guard", w == nil)
w, r = wave(5, "sky")
check("sky: after the meadow guard - the 6th", w == 6 and r == false)
w, r = wave(9, "sky")
check("sky: after the 9th - guard II", w == 10 and r == false)
w, r = wave(10, "sky")
check("sky: all passed - a replay of the 9th", w == 9 and r == true)

-- the rewards
local c1, e1 = Combat.reward(C, 1, 5, false, 100)
check("reward 1: 20 coins, no egg", c1 == 20 and e1 == nil)
local c4r = Combat.reward(C, 4, 5, true, 100)
check("reward 4 replay: half", c4r == 75)
local c5, e5 = Combat.reward(C, 5, 10, false, 100)
check("guard I: 5 minutes of income and a Cliffs egg", c5 == math.max(Economy.minutesOfIncome(10, 5), 100) and e5 ~= nil and e5.egg == "Cliffs")
local _, e5r = Combat.reward(C, 5, 10, true, 100)
check("guard I replay: no egg", e5r == nil)
local _, e10 = Combat.reward(C, 10, 10, false, 100)
check("guard II: a Rare+ egg", e10 ~= nil and e10.minRarity == "Rare")
local c6 = Combat.reward(C, 6, 1000, false, 100)
check("stage 6: 3 minutes of income", c6 == 3 * 60 * 1000)
check("helper: a share at damage >= 10%", Combat.helperCoins(C, 100, 10, 100) == 25 and Combat.helperCoins(C, 100, 9, 100) == 0)

-- the aim
local function v(x: number, y: number, z: number): any
	return { x = x, y = y, z = z }
end
local list = { { id = "behind", pos = v(0, 0, -5) }, { id = "front", pos = v(0, 0, 20) }, { id = "far", pos = v(0, 0, 80) } }
check("aim: in the cone ahead, although behind is closer", Combat.pick(v(0, 0, 0), v(0, 0, 1), list, C) == "front")
check("aim: looking back - the nearest behind", Combat.pick(v(0, 0, 0), v(0, 0, -1), list, C) == "behind")
check("aim: nobody within the radius", Combat.pick(v(0, 0, 0), v(0, 0, 1), { { id = "far", pos = v(0, 0, 80) } }, C) == nil)
check("aim: to the side outside the cone - the nearest within the radius", Combat.pick(v(0, 0, 0), v(0, 0, 1), { { id = "side", pos = v(30, 0, 0) } }, C) == "side")

-- the guard pulse
local G = C.guardianFx
check("pulse: idle at the start", Combat.pulsePhase(0.5, G) == "idle")
check("pulse: warn before the hit", Combat.pulsePhase(G.pulseEvery - 0.5, G) == "warn")
check("pulse: the hit count", Combat.pulseCount(G.pulseEvery * 2 + 0.1, G) == 2 and Combat.pulseCount(1, G) == 0)

-- the arenas along the nest axis
local Layout = require("../src/shared/Core/Layout")
local Island = require("../src/shared/Core/Island")
for i, pv in Layout.nestPivots() do
	local ax, az = Combat.arenaXZ(C, Config.World.nests, i, "meadow")
	local px, pz = pv.center[1], pv.center[3]
	local pl, al = math.sqrt(px * px + pz * pz), math.sqrt(ax * ax + az * az)
	local cosA = (ax * px + az * pz) / (pl * al)
	local sh = C.arena.shift[i]
	check("arena " .. i .. " at the own nest (the axis or a shift)", al > Config.World.terrace.radius and (cosA > 0.999 or (sh ~= nil and math.abs(cosA - math.cos(math.rad(sh.angle))) < 1e-3)))
	-- the meadow without water under the Gloom - the brook bed (Island.channelX) and the Springs baths not closer than the wave spread + 10
	local gap = math.abs(ax - Island.channelX(az)) - Island.channelHalf(az)
	check("arena " .. i .. " not at the brook bed", gap > C.arena.spread + 10)
	check("arena " .. i .. " not in Springs and on land", Island.springs(ax, az) == nil and Island.onLand(ax, az, 10))
end
-- the arenas of different nests do not overlap
for i = 1, 6 do
	for j = i + 1, 6 do
		local x1_, z1_ = Combat.arenaXZ(C, Config.World.nests, i, "meadow")
		local x2_, z2_ = Combat.arenaXZ(C, Config.World.nests, j, "meadow")
		check("arenas " .. i .. " and " .. j .. " apart", math.sqrt((x1_ - x2_) ^ 2 + (z1_ - z2_) ^ 2) > C.arena.spread * 3)
	end
end
local _, _, ySky = Combat.arenaXZ(C, Config.World.nests, 2, "sky")
check("the sky at the islet height", ySky == C.arena.skyY and ySky >= Config.World.islets.ring.yMin)

-- Config
check("the button not smaller than a finger", C.ui.buttonPx >= 56 and C.ui.minPx >= 44)
check("the server cuts more often than the client", C.breath.serverCooldown < C.breath.cooldown and Config.RateLimit.Breath >= 1 / C.breath.cooldown)
check("the server forgives farther than the aim", C.breath.serverRange > C.breath.range)

-- a stage replay is not a farm: not more than replayCapSeconds of the nest income, not less than replayMinCoins
local R = C.rewards
local rich = 15000 -- coins/s of a very strong nest
local c9r = Combat.reward(C, 9, rich, true, 100)
check("the sky replay not more than the ceiling", c9r <= math.floor(rich * R.replayCapSeconds))
local c9 = Combat.reward(C, 9, rich, false, 100)
check("the first pass without the ceiling", c9 > c9r)
local poor = Combat.reward(C, 4, 0.01, true, 0)
check("the replay not less than replayMinCoins", poor >= R.replayMinCoins)

-- the stage by power and the pause before the hunt
local H = C.hunt
check("expected seconds: the hounds of st. 3 with a hatchling 37.5 s", near(Combat.expectSec(C.stages[3], 1, H), 37.5))
local function hs(cleared: number, arena: string, dmg: number, dmgFed: number, newbie: boolean): (number?, boolean, string?)
	return Combat.huntStage(C, cleared, arena, dmg, dmgFed, newbie)
end
local k, rp, wk = hs(0, "meadow", 1, 2, true)
check("hatchling: stage 1 - yes", k == 1 and not rp and wk == nil)
k, rp, wk = hs(2, "meadow", 1, 2, true)
check("hatchling after st. 2: the hounds are beyond its power, a replay of 2 and 'feed' (fed 19 s)", k == 2 and rp and wk == "feed")
k, rp, wk = hs(2, "meadow", 6, 12, true)
check("teen after st. 2: the hounds of st. 3", k == 3 and not rp and wk == nil)
k, rp, wk = hs(4, "meadow", 6, 12, true)
check("hungry teen: the guard waits, a replay of 4 and 'feed'", k == 4 and rp and wk == "feed")
k, rp, wk = hs(4, "meadow", 12, 12, true)
check("fed teen: the guard (700 / 24 = 29 s)", k == 5 and not rp and wk == nil)
k, rp, wk = hs(4, "meadow", 2, 2, true)
check("fed hatchling at the guard: 'grow', a replay of the strongest feasible one (st. 3)", k == 3 and rp and wk == "grow")
k, rp, wk = hs(5, "meadow", 6, 12, false)
check("after the guard on the ground: a replay of 4 and 'to the sky'", k == 4 and rp and wk == "sky")
k, rp, wk = hs(5, "meadow", 1, 1, false)
check("after the guard with a hatchling: a short replay (replayMaxSec 30: st. 2, not st. 3 37.5 s)", k == 2 and rp)
k, rp, wk = hs(4, "sky", 30, 60, false)
check("the sky before the meadow guard - empty", k == nil and not rp and wk == nil)
k, rp, wk = hs(5, "sky", 30, 60, false)
check("adult: the sky st. 6", k == 6 and not rp)
k, rp, wk = hs(9, "sky", 60, 60, false)
check("Storm Gloom not today: a short replay (st. 7, 17 s) and 'storm'", k == 7 and rp and wk == "storm")
k, rp, wk = hs(8, "sky", 60, 60, false)
check("Fable review: a fed adult Common takes st. 9 (90 s <= 100)", k == 9 and not rp and wk == nil)
k, rp, wk = hs(8, "sky", 30, 60, false)
check("hungry adult at st. 9 - 'feed', a short replay (st. 6, 15 s; st. 7 hungry 35 s)", k == 6 and rp and wk == "feed")
k, rp, wk = hs(5, "sky", 1, 2, false)
check("the sky is beyond the power and nothing to replay - empty and a hint", k == nil and not rp and wk == "grow")

local T = 10000
local function sig(t: { [string]: any }): any
	local base = { now = T, joinedAt = T - 600, lastEnd = nil, progAt = nil, busyEnd = nil, newbie = true, busy = false, afk = false,
		hold = nil, hist = {}, replayGap = nil }
	for kk, v in t do
		base[kk] = v
	end
	return base
end
local function ready(t: { [string]: any }): (boolean, string)
	return Combat.huntReady(sig(t), H)
end
local ok, why = ready({ busy = true })
check("menu - no", not ok and why == "busy")
ok, why = ready({ afk = true })
check("AFK - no", not ok and why == "afk")
ok, why = ready({ joinedAt = T - 10 })
check("right after the entry - no", not ok and why == "join")
ok, why = ready({ busyEnd = T - 3, lastEnd = T - 100 })
check("3 s after the menu - no", not ok and why == "menu")
ok, why = ready({ lastEnd = T - 10 })
check("newcomer: 10 s after a wave - quiet", not ok and why == "gap")
ok, why = ready({ lastEnd = T - 35, progAt = T - 5 })
check("newcomer: 35 s, but just progressed - waiting for a pause", not ok and why == "wait")
ok, why = ready({ lastEnd = T - 35, progAt = T - 20 })
check("newcomer: 35 s and a pause of 20 s - it is time", ok and why == "idle")
ok, why = ready({ lastEnd = T - 40, hold = "carry" })
check("carrying an egg - waiting", not ok and why == "hold")
ok, why = ready({ lastEnd = T - 61, hold = "carry", progAt = T - 1 })
check("gapMax 60 s - the fight finds you itself even with a task", ok and why == "max")
ok, why = ready({ newbie = false, lastEnd = T - 21 })
check("experienced: 21 s and a pause - it is time", ok and why == "idle")
ok, why = ready({ newbie = false, lastEnd = T - 15 })
check("experienced: 15 s - quiet", not ok and why == "gap")
local six = {}
for i = 1, 6 do
	table.insert(six, { T - 290 + (i - 1) * 45, T - 285 + (i - 1) * 45 })
end
ok, why = ready({ lastEnd = T - 70, hist = six })
check("newcomer: 6 waves in 5 min - the cap", not ok and why == "cap")
check("fight share: 90 s of 180", near(Combat.fightShare({ { T - 100, T - 10 } }, T, 180), 0.5))
ok, why = ready({ lastEnd = T - 40, hist = { { T - 150, T - 40 } } })
check("fight share > 50 % - double quiet (60 s)", not ok and why == "gap")
ok, why = ready({ lastEnd = T - 60, replayGap = 90 })
check("a replay after the guard - not more often than 90 s", not ok and why == "gap")
ok, why = ready({ lastEnd = T - 95, replayGap = 90 })
check("a replay after the guard - in a pause", ok and why == "replay")
ok, why = ready({ lastEnd = T - 120, replayGap = 90, hold = "carry" })
check("a replay does not disturb the task after gapMax", not ok and why == "hold")
ok, why = ready({ lastEnd = T - 181, replayGap = 90, hold = "fly" })
check("Fable review: a task holds the replay not longer than 2 x the interval", ok and why == "replay")
ok, why = ready({ lastEnd = T - 200, replayGap = 60, progAt = T - 3 })
check("a replay only in a pause", not ok and why == "wait")
ok, why = ready({ joinedAt = T - 25 })
check("the entry is like a wave end: 25 s of quiet is not enough for a newcomer", not ok and why == "gap")
ok, why = ready({ joinedAt = T - 35 })
check("the entry 35 s ago without progress - it is time", ok and why == "idle")

-- a run: a newcomer stands idle for 5 minutes, every wave 10 s - between waves >= gapMin, waves <= the cap
do
	local hist, lastEnd, t, waveEnd = {}, nil :: number?, 0, nil :: number?
	local minGap, n = math.huge, 0
	while t <= 300 do
		if waveEnd and t >= waveEnd then
			table.insert(hist, { waveEnd - 10, waveEnd })
			if lastEnd then
				minGap = math.min(minGap, (waveEnd - 10) - lastEnd)
			end
			lastEnd, waveEnd = waveEnd, nil
		end
		if not waveEnd then
			local go = Combat.huntReady({ now = t, joinedAt = -40, lastEnd = lastEnd, newbie = true, busy = false, afk = false, hist = hist }, H)
			if go then
				n += 1
				waveEnd = t + H.warn + 10
			end
		end
		t += 1
	end
	check("newcomer run: waves in 5 min <= " .. H.cap.new, n <= H.cap.new)
	check("newcomer run: the quiet between waves >= gapMin", minGap >= H.gapMin.new)
end

print(string.format("combat_spec: %d ok, %d fail", passed, failed))
if failed > 0 then
	error("combat_spec failed")
end
