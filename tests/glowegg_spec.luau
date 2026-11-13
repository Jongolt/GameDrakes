--!strict
-- the golden nest and the glowing egg (Services/GlowEgg, spec 26-27) - the config Config.Glow.egg, the agreement with Config.Raid
-- the stand timer and the Hatch Now ladder (the pure core Core/Shop). The service itself (the nest appearance, Warm, goHome) is tied to
-- game/workspace and does not load in the luau CLI
-- Run from the repository root: luau tests/glowegg_spec.luau
local Config = require("../src/shared/Config")
local Shop = require("../src/shared/Core/Shop")
local GlowSeries = require("../src/shared/Core/GlowSeries")

local GE = Config.Glow.egg
local R = Config.Raid
local S = Config.Shop
local B = Config.Balance
local WALK = Config.Dragon.walkSpeed
local NOW = 1_800_000_000
Shop.setup(S) -- the SKU catalog (as in shop_spec)
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

-- 1. the egg config ------------------------------------------------------------------------------------------
check("Glow.egg exists and is on", typeof(GE) == "table" and GE.on == true)
check("the element from Config.Elements", table.find(Config.Elements, GE.element) ~= nil, GE.element)
check("the rarity from Config.Rarities", table.find(Config.Rarities, GE.rarity) ~= nil, GE.rarity)
check("hatchHours = 20 (hatches tomorrow)", GE.hatchHours == 20, GE.hatchHours)
check("hatchSeconds in the bowl 1-60 s", num(GE.hatchSeconds, 1, 60), GE.hatchSeconds)
check("pick 3-20", num(GE.pick, 3, 20), GE.pick)
check("afterRaids = 1 (the nest after the first dragon)", GE.afterRaids == 1, GE.afterRaids)
check("beam > 0", num(GE.beam, 1, 500))
check("color - three channels 0-255", typeof(GE.color) == "table" and #GE.color == 3 and num(GE.color[1], 0, 255) and num(GE.color[2], 0, 255) and num(GE.color[3], 0, 255))
check("distance - an ascending pair", typeof(GE.distance) == "table" and #GE.distance == 2 and GE.distance[1] > 0 and GE.distance[1] < GE.distance[2])

-- warming with coins (Warm the egg)
local W = GE.warm
check("warm exists and is on", typeof(W) == "table" and W.on == true)
check("warm.secondsPerHour 60-3600", num(W.secondsPerHour, 60, 3600), W.secondsPerHour)
check("warm.floor >= 100 and a multiple of 100", num(W.floor, 100, 1e7) and W.floor % 100 == 0, W.floor)
check("warm.stepHours = 1", W.stepHours == 1, W.stepHours)
check("warm.minLeft 1-3599 s (less than a step)", num(W.minLeft, 1, 3599) and W.minLeft < W.stepHours * 3600, W.minLeft)
check("warm.reach 5-60", num(W.reach, 5, 60), W.reach)
check("warmings to readiness not more than hatchHours / stepHours", math.ceil(GE.hatchHours / W.stepHours) <= 20)

-- the chase (Gloom Warden)
local CH = GE.chase
check("chase exists and is on", typeof(CH) == "table" and CH.on == true)
check("chase.count = 1 (one guard)", CH.count == 1)
check("chase: kind/name are strings", typeof(CH.kind) == "string" and typeof(CH.name) == "string")
for k, b in { scale = { 0.5, 3 }, wake = { 0.2, 5 }, catch = { 2, 15 }, lose = { 20, 500 }, maxSec = { 10, 300 }, arc = { 0.2, 5 },
	gateHold = { 0.1, 5 }, retreat = { 0.2, 10 }, returnSpeed = { 4, 40 }, minSpeed = { 4, 40 }, sleepK = { 0, 1 }, standK = { 0, 1 } } do
	check("chase." .. k .. " in [" .. b[1] .. ", " .. b[2] .. "]", num((CH :: any)[k], b[1], b[2]), (CH :: any)[k])
end
check("chase: lose farther than catch", CH.lose > CH.catch)
check("chase: spots >= count", typeof(CH.spots) == "table" and #CH.spots >= CH.count)
check("chase.share 1-8 steps", typeof(CH.share) == "table" and #CH.share >= 1 and #CH.share <= 8)

-- 3. the guard faster/slower than the thief (the thief on foot - the sortie at the nest is only on foot): the speed = max(minSpeed, share x the run)
for i, v in CH.share do
	local sp = math.max(CH.minSpeed, v * WALK)
	check("golden, attempt " .. i .. ": the guard not faster than the thief on foot", sp <= WALK, sp)
	if i > 1 then
		check("golden, attempt " .. i .. ": slower than the previous one", v < CH.share[i - 1], v)
	end
end
check("the golden one is fiercer than the first egg: the first attempt not slower", CH.share[1] >= R.first.share[1])
check("chase.minSpeed slower than the thief", CH.minSpeed < WALK)

-- the sortie: the agreement with the raid (Services/Raid dismounts within approachR, the dragon waits at point D)
local GR = GE.raid
check("raid exists", typeof(GR) == "table")
check("raid.safe = dragon", GR.safe == "dragon", GR.safe)
check("raid.needRide = true (the nest after the first ride)", GR.needRide == true)
check("raid.approachR = Raid.approachR", GR.approachR == R.approachR, GR.approachR)
check("raid.mountR = Raid.mountR", GR.mountR == R.mountR, GR.mountR)
check("raid.raidR = Raid.raidR", GR.raidR == R.raidR, GR.raidR)
check("pick closer than approachR (can be taken only on foot)", GE.pick < GR.approachR)
check("pick = Raid.grab (one taking rule)", GE.pick == R.grab)
check("gapW/outD/clearR > 0", num(GR.gapW, 1, 50) and num(GR.outD, 0.5, 30) and num(GR.clearR, 0.5, 20))

-- the spot search rings (spot)
local SP = GE.spot
check("spot.rings ascending", typeof(SP.rings) == "table" and #SP.rings >= 1 and (function()
	for i = 2, #SP.rings do
		if SP.rings[i] <= SP.rings[i - 1] then
			return false
		end
	end
	return true
end)())
for k, b in { flatR = { 1, 30 }, flatMax = { 0.1, 10 }, clearR = { 1, 40 }, eggGap = { 5, 100 } } do
	check("spot." .. k .. " in [" .. b[1] .. ", " .. b[2] .. "]", num((SP :: any)[k], b[1], b[2]), (SP :: any)[k])
end
local SL = SP.slope
check("slope exists and is on", typeof(SL) == "table" and SL.on == true)
check("slope.radii ascending, 100-400", #SL.radii >= 1 and (function()
	for i, r in SL.radii do
		if not num(r, 100, 400) or (i > 1 and r <= SL.radii[i - 1]) then
			return false
		end
	end
	return true
end)())
check("slope.arcs starts with 0, within +-90", SL.arcs[1] == 0 and (function()
	for _, a in SL.arcs do
		if not num(a, -90, 90) then
			return false
		end
	end
	return true
end)())
check("slope.nestGap >= 2 x approachR (point D is not in the dismount zone of another nest)", SL.nestGap >= 2 * R.approachR, SL.nestGap)
check("slope.relax is softer than the strict pass", SL.relax.nestGap <= SL.nestGap and SL.relax.flatMax >= SL.flatMax)
check("slope.otherGap > 0", num(SL.otherGap, 1, 200))

-- 3. the stand timer: Shop.hatchRemaining "glow" ---------------------------------------------------------
local function prof(ge: any): any
	return { glowEgg = ge, eggs = { incubating = {} }, items = { treats = 0, hatchNow = {}, growNow = {} } }
end
local H = GE.hatchHours * 3600
check("not taken (the template taken 0) - no timer", Shop.hatchRemaining(prof({ taken = 0 }), "glow", NOW) == nil)
check("glowEgg is not a table - no timer", Shop.hatchRemaining(prof(nil), "glow", NOW) == nil)
check("in the hands (readyAt 0) - no timer", Shop.hatchRemaining(prof({ taken = NOW, readyAt = 0 }), "glow", NOW) == nil)
check("at home: the remainder = hatchHours", Shop.hatchRemaining(prof({ taken = NOW, readyAt = NOW + H }), "glow", NOW) == H)
check("the term passed - 0, not negative", Shop.hatchRemaining(prof({ taken = NOW - H, readyAt = NOW - 5 }), "glow", NOW) == 0)
check("hatched - no timer", Shop.hatchRemaining(prof({ taken = NOW, readyAt = NOW + H, hatched = true }), "glow", NOW) == nil)
check("strings in the profile (JSON) - a number too", Shop.hatchRemaining(prof({ taken = tostring(NOW), readyAt = NOW + 60 }), "glow", NOW) == 60)

-- the Hatch Now ladder for the stand: the cheapest fitting step and the price
local steps, prices = S.hatchNow.steps, S.hatchNow.prices
check("ladder: one more price step than limits", #prices == #steps + 1)
for i = 2, #prices do
	check("ladder: the price of step " .. i .. " is higher", prices[i] > prices[i - 1])
	if i <= #steps then
		check("ladder: the limit of step " .. i .. " is farther", steps[i] > steps[i - 1])
	end
end
for _, case in { { 1, 1 }, { 60, 1 }, { 61, 2 }, { 300, 2 }, { 1200, 3 }, { 1201, 4 }, { 3600, 4 }, { 3601, 5 }, { H, 5 } } do
	local rem, want = case[1], case[2]
	local d = prof({ taken = NOW, readyAt = NOW + rem })
	check(("remainder %d s -> step %d (%d)"):format(rem, want, prices[want]), Shop.tierOf(rem, S) == want and Shop.tierKey("hatchNow", want, S) == "HatchNow_" .. prices[want])
	for tier = 1, #prices do
		local got = Shop.pickHatchTarget(d, tier, NOW, S, "glow")
		check(("remainder %d s, step %d: the stand %s"):format(rem, tier, if tier >= want then "is taken" else "is not taken"),
			(got == "glow") == (tier >= want), got)
	end
end
check("20 h - only the most expensive step", Shop.tierOf(H, S) == #prices)

-- 4. the double grant: "hatch now" on the stand ----------------------------------------------------------
local function ctx(slot: string?): any
	return { now = NOW, B = B, S = S, slot = slot, rate = 0 }
end
do
	local d = prof({ taken = NOW - 10, readyAt = NOW + H })
	local g1 = Shop.grant(d, "HatchNow_" .. prices[#prices], ctx("glow"))
	check("1st purchase: the stand is ready now", g1.ok and g1.applied == "slot" and g1.slot == "glow" and d.glowEgg.readyAt == NOW, g1.applied)
	local g2 = Shop.grant(d, "HatchNow_" .. prices[#prices], ctx("glow"))
	check("2nd purchase: not a second hatch but a ticket", g2.ok and g2.applied == "ticket" and d.items.hatchNow[tostring(#prices)] == 1, g2.applied)
	check("2nd purchase: the term did not go into the past", d.glowEgg.readyAt == NOW)
	check("2nd purchase: taken is untouched", d.glowEgg.taken == NOW - 10)
end
do
	local d = prof({ taken = 0 })
	local g = Shop.grant(d, "HatchNow_" .. prices[#prices], ctx("glow"))
	check("not taken: a purchase -> a ticket, glowEgg is not recreated", g.ok and g.applied == "ticket" and d.glowEgg.taken == 0 and d.glowEgg.readyAt == nil, g.applied)
end
do
	local d = prof({ taken = NOW, readyAt = NOW + 100, hatched = true })
	d.items.hatchNow["5"] = 1
	check("hatched: the ticket is not spent", Shop.useTicket(d, "hatchNow", "glow", NOW, S) == nil and d.items.hatchNow["5"] == 1 and d.glowEgg.readyAt == NOW + 100)
end
do
	local d = prof({ taken = NOW, readyAt = NOW + 30 * 60 })
	d.items.hatchNow = { ["1"] = 1, ["4"] = 1, ["5"] = 1 }
	check("ticket: 30 min - step 4 is spent, not 5 and not 1", Shop.useTicket(d, "hatchNow", "glow", NOW, S) == 4
		and d.items.hatchNow["1"] == 1 and d.items.hatchNow["4"] == 0 and d.items.hatchNow["5"] == 1 and d.glowEgg.readyAt == NOW)
	check("ticket: a repeat on a ready stand does not spend", Shop.useTicket(d, "hatchNow", "glow", NOW, S) == nil and d.items.hatchNow["5"] == 1)
end

-- the golden egg series by element (Core/GlowSeries, Config.Glow.egg.series) ------------------------------------------
do
	local SER = GE.series
	check("series: 6 elements, all from Config.Elements, no repeats", typeof(SER) == "table" and #SER == 6 and (function()
		local seen = {}
		for _, e in SER do
			if table.find(Config.Elements, e) == nil or seen[e] then
				return false
			end
			seen[e] = true
		end
		return true
	end)())
	check("series: the first is Ember, as in live before the series", SER[1] == "ember" and GE.element == "ember")
	for _, e in SER do
		check("series: the glow masks exist for " .. e, typeof(Config.Glow.masks[e]) == "number" and typeof(Config.Glow.masksElder[e]) == "number")
	end
	check("an old profile without n - egg 1, Ember", GlowSeries.index({ taken = NOW, readyAt = NOW, hatched = true }) == 1
		and GlowSeries.element({ taken = 0 }, GE) == "ember")
	check("n = 2 - Frost, n = 6 - Tide", GlowSeries.element({ n = 2 }, GE) == "frost" and GlowSeries.element({ n = 6 }, GE) == "tide")
	check("n past the series end - the default element", GlowSeries.element({ n = 9 }, GE) == GE.element)
	local empty = { carry = nil, incubating = {} }
	check("not hatched - no next one", GlowSeries.advance({ taken = NOW, readyAt = NOW + 60 }, empty, GE) == nil)
	local nx = GlowSeries.advance({ taken = NOW, readyAt = NOW, hatched = true }, empty, GE)
	check("an old profile with a hatched Ember -> egg 2 (Frost), not taken", nx ~= nil and nx.n == 2 and nx.taken == 0
		and GlowSeries.element(nx, GE) == "frost")
	check("a glowing one in the bowl - waiting for the hatch", GlowSeries.advance({ hatched = true, n = 2 },
		{ incubating = { ["1"] = { egg = { glow = true, element = "frost" }, endsAt = NOW + 3 } } }, GE) == nil)
	check("a glowing one in the hands - waiting", GlowSeries.advance({ hatched = true, n = 2 }, { carry = { glow = true }, incubating = {} }, GE) == nil)
	check("an ordinary egg in the bowl does not interfere", GlowSeries.advance({ hatched = true, n = 2 },
		{ incubating = { ["1"] = { egg = { element = "moss" }, endsAt = NOW + 300 } } }, GE) ~= nil)
	check("after Tide (6) the series is over", GlowSeries.advance({ hatched = true, n = 6 }, empty, GE) == nil)
	local steps, ge = 0, { taken = NOW, readyAt = NOW, hatched = true }
	while true do
		local n2 = GlowSeries.advance(ge, empty, GE)
		if not n2 then
			break
		end
		steps += 1
		ge = { taken = NOW, readyAt = NOW, hatched = true, n = n2.n }
	end
	check("the whole series: 5 transitions after Ember, the last is Tide", steps == 5 and GlowSeries.element(ge, GE) == "tide", steps)
end

print(("glowegg_spec: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("glowegg_spec failed")
end
