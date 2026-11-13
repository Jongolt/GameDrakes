--!strict
-- the egg raid (spec 27) and the one-dragon day - config Config.Raid, the pure core Core/RaidLoop, Core/Quests.dayOneSkip.
-- The services (Services/Raid, PlayerData.eggsAllowed) depend on game/workspace and the luau CLI does not load them
-- Run from the repository root: luau tests/raid_spec.luau
local Config = require("../src/shared/Config")
local RaidLoop = require("../src/shared/Core/RaidLoop")
local Quests = require("../src/shared/Core/Quests")

local R = Config.Raid
local WALK = Config.Dragon.walkSpeed
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end
local function num(v: any, lo: number, hi: number): boolean
	return typeof(v) == "number" and v == v and v >= lo and v <= hi
end

-- 1. raid config: the keys are in place, the numbers within sane bounds -------------------------------------------
check("Raid exists and is on", typeof(R) == "table" and R.on == true)
for _, k in { "firstEggByRaid", "firstEggOnly", "firstFar" } do
	check("Raid." .. k .. " - boolean", typeof(R[k]) == "boolean", R[k])
end
local bounds: { [string]: { number } } = {
	grab = { 3, 20 }, approachR = { 15, 80 }, raidR = { 40, 200 }, rearm = { 5, 60 }, mountR = { 4, 30 }, dragonStop = { 2, 20 },
	gateHold = { 0.1, 5 }, returnSpeed = { 4, 40 }, minSpeed = { 4, 40 }, arc = { 0.2, 5 }, labelDistance = { 20, 400 },
	springsFlatMax = { 0.5, 10 }, waitFlatMax = { 0.5, 10 },
}
for k, b in bounds do
	check("Raid." .. k .. " in [" .. b[1] .. ", " .. b[2] .. "]", num(R[k], b[1], b[2]), R[k])
end
check("Raid.eggGlow range/brightness > 0", typeof(R.eggGlow) == "table" and num(R.eggGlow.range, 1, 200) and num(R.eggGlow.brightness, 0.1, 20))
check("taking the egg is closer than the 'on foot only' zone", R.grab < R.approachR)
check("mounting the dragon is closer than where it waits from the nest", R.mountR < R.approachR)
check("take again - only after stepping farther away than the grab distance", R.rearm > R.grab)
check("the sortie zone is wider than the dismount zone", R.raidR > R.approachR)
check("the warden minSpeed and returnSpeed are not faster than the thief on foot", R.minSpeed < WALK and R.returnSpeed <= WALK)

-- hatching of raid eggs: all rarities, fast, ascending
local prev = 0
for _, rar in Config.Rarities do
	local s = RaidLoop.hatchSeconds(R, rar)
	check("hatchSeconds." .. rar .. " set, 1 s - 2 h", s ~= nil and num(s, 1, 7200), s)
	check("hatchSeconds." .. rar .. " not less than the previous rarity", (s or 0) >= prev, s)
	prev = s or prev
end
check("hatchSeconds: no extra keys", (function()
	for k in R.hatchSeconds do
		if not table.find(Config.Rarities, k) then
			return false
		end
	end
	return true
end)())

-- rings: numbers 0..2 once each, each has a warden with a full set of numbers
local seen: { [number]: boolean } = {}
for _, rc in R.rings do
	local tag = "ring " .. tostring(rc.ring)
	check(tag .. ": number 0-2 and not repeated", num(rc.ring, 0, 2) and not seen[rc.ring], rc.ring)
	seen[rc.ring] = true
	check(tag .. ": open is known", table.find({ "always", "hatch", "rode", "flew", "off" }, rc.open) ~= nil, rc.open)
	check(tag .. ": safe lot|dragon", rc.safe == "lot" or rc.safe == "dragon", rc.safe)
	check(tag .. ": respawn 5-600 s", num(rc.respawn, 5, 600), rc.respawn)
	local g = rc.guard
	check(tag .. ": has a warden", typeof(g) == "table")
	if typeof(g) == "table" then
		check(tag .. ": kind/name are strings", typeof(g.kind) == "string" and typeof(g.name) == "string")
		check(tag .. ": scale 0,5-3", num(g.scale, 0.5, 3), g.scale)
		check(tag .. ": wake 0.2-5 s", num(g.wake, 0.2, 5), g.wake)
		check(tag .. ": catch 2-15", num(g.catch, 2, 15), g.catch)
		check(tag .. ": lose is farther than catch and grab", num(g.lose, 20, 500) and g.lose > g.catch and g.lose > R.grab, g.lose)
		check(tag .. ": maxSec 10-300", num(g.maxSec, 10, 300), g.maxSec)
		check(tag .. ": lair 1-20", num(g.lair, 1, 20), g.lair)
		check(tag .. ": share - 1-8 steps", typeof(g.share) == "table" and #g.share >= 1 and #g.share <= 8)
		for i, v in g.share do
			check(tag .. ": share[" .. i .. "] 0,3-1,2", num(v, 0.3, 1.2), v)
			if i > 1 then
				check(tag .. ": share[" .. i .. "] not faster than the previous attempt", v <= g.share[i - 1], v)
			end
		end
	end
	if rc.rarity then
		local sum = 0
		for rar, w in rc.rarity do
			check(tag .. ": rarity " .. rar .. " is known, weight > 0", table.find(Config.Rarities, rar) ~= nil and num(w, 0.001, 1000))
			sum += w
		end
		check(tag .. ": rarity weights > 0 in total", sum > 0)
	end
end
check("rings 0, 1, 2 are all described", seen[0] == true and seen[1] == true and seen[2] == true)
local rc0 = RaidLoop.ringCfg(R, 0)
check("ring 0: spots (3 angles, r, side)", rc0 ~= nil and typeof(rc0.spots) == "table" and #rc0.spots.angles == 3 and num(rc0.spots.r, 20, 120) and num(rc0.spots.side, 0, 30))
check("ring 0: safe = lot (run to the own plot)", rc0 ~= nil and rc0.safe == "lot")
-- daily raids - ring 0 is more varied (Common/Uncommon/Rare), nothing above Rare
check("ring 0: only Common/Uncommon/Rare", rc0 ~= nil and rc0.rarity ~= nil and (function()
	for rar in (rc0 :: any).rarity do
		if rar ~= "Common" and rar ~= "Uncommon" and rar ~= "Rare" then
			return false
		end
	end
	return true
end)())
check("a ring with an unknown number - nil", RaidLoop.ringCfg(R, 7) == nil)

-- the three ring 0 nests do not stick together and are not in the square centre
local pts = RaidLoop.ring0Points(R, Config.World)
check("ring 0: three nests", #pts == 3, #pts)
for i = 1, #pts do
	for j = i + 1, #pts do
		local d = math.sqrt((pts[i].x - pts[j].x) ^ 2 + (pts[i].z - pts[j].z) ^ 2)
		check("ring 0: nests " .. i .. "-" .. j .. " farther than 30 from each other", d > 30, d)
	end
	check("ring 0: nest " .. i .. " on the edge (r 30-120)", num(math.sqrt(pts[i].x ^ 2 + pts[i].z ^ 2), 30, 120))
end

-- the dragon wait point exactly approachR from the nest toward home (and with coinciding points - no division by 0)
local wx, wz = RaidLoop.waitPoint(100, 50, 0, 0, R.approachR)
check("point D at approachR from the nest", math.abs(math.sqrt((wx - 100) ^ 2 + (wz - 50) ^ 2) - R.approachR) < 1e-6)
check("point D closer to home than the nest", wx * wx + wz * wz < 100 * 100 + 50 * 50)
local sx, sz = RaidLoop.waitPoint(5, 5, 5, 5, R.approachR)
check("point D with home = nest - finite", sx == sx and sz == sz and math.abs(sx - 5 - R.approachR) < 1e-6 and sz == 5)

-- 3. the warden faster/slower than the thief: speed = max(minSpeed, share x the thief run) (Combat.chase: pk.share * topSpeed)
local function guardSpeed(share: number): number
	return math.max(R.minSpeed, share * WALK)
end
check("first egg: Raid.first exists (share, wake)", typeof(R.first) == "table" and typeof(R.first.share) == "table" and num(R.first.wake, 0.2, 5))
for tries = 0, 6 do
	local s = RaidLoop.share(R.first, tries)
	check("first egg, attempt " .. tries + 1 .. ": the warden is slower than the thief on foot", guardSpeed(s) < WALK, guardSpeed(s))
	if tries > 0 then
		check("first egg, attempt " .. tries + 1 .. ": not faster than the previous one", s <= RaidLoop.share(R.first, tries - 1))
	end
end
check("first egg: the last step holds", RaidLoop.share(R.first, 99) == R.first.share[#R.first.share])
check("first egg: share of attempt 0 = the first step", RaidLoop.share(R.first, 0) == R.first.share[1])
check("the first egg is softer than the ring 0 warden (first attempt)", RaidLoop.share(R.first, 0) <= RaidLoop.share((rc0 :: any).guard, 0))
for tries = 0, 4 do
	check("ring 0, attempt " .. tries + 1 .. ": the warden is slower than the thief on foot", guardSpeed(RaidLoop.share((rc0 :: any).guard, tries)) < WALK)
end
check("share with a negative attempt - the first step (clamp)", RaidLoop.share(R.first, -5) == R.first.share[1])

-- 2. the one-dragon day: what is open ----------------------------------------------------------------------
check("firstEggByRaid: the first egg - by a raid", R.firstEggByRaid == true)
check("firstEggOnly: day 1 = one dragon", R.firstEggOnly == true)
check("ring 0 is open without dragons and without onboarding", RaidLoop.open(R, 0, nil, 0) and RaidLoop.open(R, 0, {}, 0))
check("ring 0 - the farthest open one for a newcomer", RaidLoop.farthestOpen(R, {}, 0) == 0)
for _, ring in { 1, 2 } do
	check("ring " .. ring .. " is off on day 1", RaidLoop.ringCfg(R, ring).open == "off")
	for _, onb in { {}, { rode = true }, { flew = true }, { rode = true, flew = true } } do
		check("ring " .. ring .. " is closed with any onboarding/dragons", not RaidLoop.open(R, ring, onb, 5))
	end
end
check("an unknown ring is closed", not RaidLoop.open(R, 9, {}, 0) and RaidLoop.farthestOpen({ rings = {} }, {}, 0) == -1)
-- coins instead of an egg
check("eggFallbackCoins = 300", Config.Quests.eggFallbackCoins == 300, Config.Quests.eggFallbackCoins)
-- Keeper quests that ask for a second egg / more dragons / found eggs / the Index are skipped; the rest are not
local skipped, kept = 0, 0
for _, q in Quests.List do
	local skip = Quests.dayOneSkip(q)
	local wantsMore = ((q.event == "eggInc" or q.event == "hatch") and q.count >= 2)
		or q.event == "eggFound" or q.event == "index" or q.event == "eggInc_Cliffs" or q.event == "eggInc_Springs"
	check("dayOneSkip: quest " .. q.id .. " (" .. q.event .. " x" .. q.count .. ")", skip == wantsMore)
	if skip then
		skipped += 1
	else
		kept += 1
	end
end
check("dayOneSkip: the first hatch is not skipped", not Quests.dayOneSkip(Quests.List[1]))
check("dayOneSkip: 'A second egg' is skipped", Quests.dayOneSkip(Quests.List[3]))
check("dayOneSkip: something is skipped and something remains", skipped > 0 and kept > 0, skipped .. "/" .. kept)

-- the ring 0 egg rarity: by weights, only from the table
local cnt: { [string]: number } = {}
local N = 1000
for i = 1, N do
	local rar = RaidLoop.rarity((rc0 :: any).rarity, function()
		return (i - 0.5) / N
	end, Config.Rarities)
	cnt[rar] = (cnt[rar] or 0) + 1
end
check("ring 0: rarities only from the table", (cnt.Common or 0) + (cnt.Uncommon or 0) + (cnt.Rare or 0) == N)
local wC, wU, wR = (rc0 :: any).rarity.Common, (rc0 :: any).rarity.Uncommon or 0, (rc0 :: any).rarity.Rare or 0
check("ring 0: the Common share by weights (+-1 %)", math.abs((cnt.Common or 0) / N - wC / (wC + wU + wR)) < 0.01, cnt.Common)
check("ring 0: the Rare share by weights (+-1 %)", math.abs((cnt.Rare or 0) / N - wR / (wC + wU + wR)) < 0.01, cnt.Rare)

-- daily raids Config.Raid.daily
local D = R.daily
check("daily: set, eggs 1..10", typeof(D) == "table" and num(D.eggs, 1, 10))
check("daily: share and wake per egg, length = eggs", #D.share == D.eggs and #D.wake == D.eggs)
local up, wdown = true, true
for k = 2, D.eggs do
	up = up and D.share[k] > D.share[k - 1]
	wdown = wdown and D.wake[k] <= D.wake[k - 1]
end
check("daily: the warden of each next egg is faster", up)
check("daily: and wakes up no later", wdown)
check("daily: the first daily is softer than the thief (after the golden one - a win)", D.share[1] < 1)
check("daily: relief > 0, floor < share[1]", num(D.relief, 0.01, 0.2) and D.floor < D.share[1])
check("daily: dismountR < approachR and > grab", num(D.dismountR, R.grab + 1, R.approachR - 1))
check("daily: the last egg is not hopeless (share <= 1.25)", D.share[D.eggs] <= 1.25)
check("dayDone: another day - 0", RaidLoop.dayDone({ day = "2026-10-30", dayN = 3 }, "2026-10-31") == 0)
check("dayDone: the same day - the counter", RaidLoop.dayDone({ day = "2026-10-31", dayN = 3 }, "2026-10-31") == 3)
check("dayDone: nil / garbage - 0", RaidLoop.dayDone(nil, "2026-10-31") == 0 and RaidLoop.dayDone({ day = "2026-10-31", dayN = "x" }, "2026-10-31") == 0)
check("dayLeft: a new day - the full limit", RaidLoop.dayLeft(D, { home = 9 }, "2026-10-31") == D.eggs)
check("dayLeft: not less than 0", RaidLoop.dayLeft(D, { day = "2026-10-31", dayN = D.eggs + 3 }, "2026-10-31") == 0)
check("dayLeft: off - nil", RaidLoop.dayLeft(nil, {}, "2026-10-31") == nil and RaidLoop.dayLeft({ eggs = 0 }, {}, "2026-10-31") == nil)
check("dayShare: the first attempt = share[k]", RaidLoop.dayShare(D, 3, 0) == D.share[3])
check("dayShare: a capture is softer by relief", math.abs(RaidLoop.dayShare(D, 3, 1) - (D.share[3] - D.relief)) < 1e-9)
check("dayShare: not below floor", RaidLoop.dayShare(D, 1, 50) == D.floor)
check("dayShare: k out of range - the extremes", RaidLoop.dayShare(D, 99, 0) == D.share[D.eggs] and RaidLoop.dayShare(D, 0, 0) == D.share[1])
check("dayWake: per egg, out of range - the last", RaidLoop.dayWake(D, 1) == D.wake[1] and RaidLoop.dayWake(D, 99) == D.wake[D.eggs])
check("hatchSeconds: dailies 3-15 min (Common..Legendary)", RaidLoop.hatchSeconds(R, "Common") == 180 and RaidLoop.hatchSeconds(R, "Legendary") == 900)
check("rarity: r01 = 0.9999 does not go beyond the table", RaidLoop.rarity({ Common = 1 }, function()
	return 0.9999
end, Config.Rarities) == "Common")

print(("raid_spec: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("raid_spec failed")
end
