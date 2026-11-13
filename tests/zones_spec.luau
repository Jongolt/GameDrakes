-- Core/Zones - the zone of an island point and the profile record (the visit map). Run: luau tests/zones_spec.luau
local Config = require("../src/shared/Config")
local Zones = require("../src/shared/Core/Zones")

local W = Config.World
local ok, fail = 0, 0
local function eq(name: string, got: any, want: any)
	if got == want then
		ok += 1
	else
		fail += 1
		print("FAIL " .. name .. ": " .. tostring(got) .. " ~= " .. tostring(want))
	end
end
local walk = { flying = false, gliding = false, swimming = false, ownNest = false }
local function at(x: number, y: number, z: number, ctx: any?): string
	return Zones.of(x, y, z, ctx or walk, W)
end

eq("square", at(0, 18, -30), "plaza")
eq("Old Ash", at(W.keeper.x, W.keeper.y, W.keeper.z), "plaza")
eq("someone else's nest", at(120, 18, 0), "terrace")
eq("own nest", at(120, 18, 0, { flying = false, gliding = false, swimming = false, ownNest = true }), "nest")
eq("meadow under the ledge", at(220, 2, 30), "meadow")
eq("meadow egg r 260", at(0, 1, 260), "meadow")
eq("Cliffs", at(0, 50, -330), "cliffs")
eq("Springs", at(-300, 4, 20), "springs")
local sc = W.zones.Summit.center
eq("Summit", at(sc[1], sc[2], sc[3]), "summit")
eq("islet", at(200, 130, -150), "islets")
eq("shore", at(380, 1, 0), "shore")
eq("Frost Isle", at(W.frostIsle.x, 5, 0), "far")
eq("flight", at(220, 60, 30, { flying = true, gliding = false, swimming = false, ownNest = false }), "sky")
eq("glider", at(200, 25, 0, { flying = false, gliding = true, swimming = false, ownNest = false }), "glide")
eq("water", at(380, -2, 0, { flying = false, gliding = false, swimming = true, ownNest = false }), "water")
for _, z in Zones.LIST do
	eq("in the list " .. z, table.find(Zones.LIST, z) ~= nil, true)
end

local z = Zones.record(nil, "plaza", 10, 5)
z = Zones.record(z, "plaza", 10, 15)
z = Zones.record(z, "nest", 10, 25)
eq("square seconds", z.s.plaza, 20)
eq("the first square visit", z.f.plaza, 5)
eq("the first nest visit", z.f.nest, 25)
eq("the last zone", z.last, "nest")
eq("the last time", z.lastAt, 25)
local bad = Zones.record({ s = 5, f = "x" }, "meadow", 10, 40)
eq("a broken record is repaired", bad.s.meadow, 10)

-- boredom by zone and the progress fingerprint
local zb = Zones.record(nil, "meadow", 10, 30, false, 5)
zb = Zones.record(zb, "meadow", 10, 40, true, 25)
eq("meadow boredom", zb.b.meadow, 10)
eq("meadow seconds", zb.s.meadow, 20)
eq("idle at the last mark", zb.idle, 25)
local d1 = { dragons = { d1 = { stage = 0 } }, eggs = { incubating = {}, shelf = {} }, onboarding = { firstHatch = true }, coins = 5 }
local k1 = Zones.progressKey(d1)
d1.coins = 500
eq("coins are not progress", Zones.progressKey(d1), k1)
d1.dragons.d1.stage = 1
eq("growth is progress", Zones.progressKey(d1) ~= k1, true)
eq("an empty profile does not crash", type(Zones.progressKey({})), "string")
-- an egg in an incubator (a dict by slot) and a change of the onboarding stage - progress; the Summit slope and shoulder - summit
local d2 = { dragons = {}, eggs = { incubating = {}, shelf = {} }, onboarding = { stage = "spawn" } }
local k2 = Zones.progressKey(d2)
d2.eggs.incubating["1"] = { egg = "x", endsAt = 1 }
eq("an egg in an incubator - progress", Zones.progressKey(d2) ~= k2, true)
local k3 = Zones.progressKey(d2)
d2.onboarding.stage = "hatched"
eq("an onboarding step - progress", Zones.progressKey(d2) ~= k3, true)
eq("Summit slope", at(sc[1] + 95, 60, sc[3]), "summit")
eq("Summit shoulder high up", at(sc[1] - 100, 85, sc[3]), "summit")
eq("Summit foot by the sea", at(sc[1], 5, sc[3] + 80), "shore")

print(string.format("zones_spec: %d ok, %d fail", ok, fail))
if fail > 0 then
	error("zones_spec failed")
end
