--!strict
-- pure logic of the raid rings without Roblox API (tests tests/run.luau).
-- The rings by distance from the own plot: 0 - the plaza rim (on foot), 1 - the meadow (riding), 2 - the cliffs and baths (by flight);
-- the summit and the islets - package 2. The numbers - Config.Raid (cfg), the world layout - Config.World (W).

local Layout = require("./Layout")

local RaidLoop = {}

export type Pt = { id: string, ring: number, angleDeg: number, x: number, z: number }

-- the ring settings by number (rings - an array, ring - a field)
function RaidLoop.ringCfg(cfg: any, ring: number): any
	for _, rc in cfg.rings do
		if rc.ring == ring then
			return rc
		end
	end
	return nil
end

-- the ring of an egg spot by its zone; nil - a zone without raids (the free EggSpawner eggs stay there)
function RaidLoop.ringOfZone(cfg: any, zone: string): number?
	for _, rc in cfg.rings do
		if rc.zones then
			for _, z in rc.zones do
				if z == zone then
					return rc.ring
				end
			end
		end
	end
	return nil
end

-- the three shared ring 0 nests: the plaza rim, the odd wedges between the plots (the angles spots.angles), the radius spots.r, the shift side
-- sideways from the wedge axis (the path to the stairs goes along the axis). The angle as in Layout.dir: 0 = east, 90 = north
function RaidLoop.ring0Points(cfg: any, W: any): { Pt }
	local rc = RaidLoop.ringCfg(cfg, 0)
	local out: { Pt } = {}
	if not rc or not rc.spots then
		return out
	end
	local S = rc.spots
	for i, a in S.angles do
		local d = Layout.dir(a)
		local v = Layout.dir(a - 90) -- sideways (clockwise), the same for all three
		table.insert(out, { id = "plaza_" .. i, ring = 0, angleDeg = a, x = d[1] * S.r + v[1] * S.side, z = d[3] * S.r + v[3] * S.side })
	end
	return out
end

-- the nests at the foot of the cliffs (ring 2, foot): in front of the foot boulders, along x with a step; the spot is refined by a measurement (Services/Raid)
function RaidLoop.footPoints(cfg: any): { Pt }
	local out: { Pt } = {}
	for _, rc in cfg.rings do
		local f = rc.foot
		if f then
			for i, x in f.xs do
				table.insert(out, { id = string.lower(f.zone) .. "_foot_" .. i, ring = rc.ring, angleDeg = 0, x = x, z = f.z })
			end
		end
	end
	return out
end

-- whether the ring is open: hatch - there is at least one dragon, rode / flew - the onboarding flags
function RaidLoop.open(cfg: any, ring: number, onb: any, dragons: number): boolean
	local rc = RaidLoop.ringCfg(cfg, ring)
	if not rc then
		return false
	end
	if rc.open == "always" then
		return true -- ring 0 - the first egg and the first dragon are obtained by a raid
	end
	if rc.open == "hatch" then
		return dragons >= 1
	end
	return typeof(onb) == "table" and onb[rc.open] == true
end

-- the farthest open ring (the arrow leads there); -1 - nothing is open
function RaidLoop.farthestOpen(cfg: any, onb: any, dragons: number): number
	local best = -1
	for _, rc in cfg.rings do
		if RaidLoop.open(cfg, rc.ring, onb, dragons) and rc.ring > best then
			best = rc.ring
		end
	end
	return best
end

-- the share of the thief's speed for the guard by the attempt number (1 - the first; every catch slower down to the last step)
function RaidLoop.share(guard: any, tries: number): number
	local sh = guard.share
	return sh[math.clamp(tries + 1, 1, #sh)]
end

-- the rarity from the weight table { Common = 85, Uncommon = 15 } (the order order - Config.Rarities)
function RaidLoop.rarity(weights: { [string]: number }, r01: () -> number, order: { string }): string
	local sum = 0
	for _, r in order do
		sum += weights[r] or 0
	end
	local x = r01() * sum
	local last = order[1]
	for _, r in order do
		local v = weights[r] or 0
		if v > 0 then
			last = r
			if x < v then
				return r
			end
			x -= v
		end
	end
	return last
end

-- point D where the dragon waits: approachR studs from the nest toward home (the gate of the own plot)
function RaidLoop.waitPoint(nx: number, nz: number, hx: number, hz: number, approachR: number): (number, number)
	local dx, dz = hx - nx, hz - nz
	local len = math.sqrt(dx * dx + dz * dz)
	if len < 1e-3 then
		return nx + approachR, nz
	end
	return nx + dx / len * approachR, nz + dz / len * approachR
end

function RaidLoop.hatchSeconds(cfg: any, rarity: string): number?
	local t = cfg.hatchSeconds
	return if typeof(t) == "table" then t[rarity] else nil
end

-- how many eggs were already carried home today (rd = data.raid; another day - 0)
function RaidLoop.dayDone(rd: any, day: string): number
	if typeof(rd) ~= "table" or rd.day ~= day then
		return 0
	end
	return math.max(0, math.floor(tonumber(rd.dayN) or 0))
end

-- how many raid eggs are left today for a player with a dragon; nil - there are no daily raids (daily is off)
function RaidLoop.dayLeft(daily: any, rd: any, day: string): number?
	if typeof(daily) ~= "table" or (tonumber(daily.eggs) or 0) <= 0 then
		return nil
	end
	return math.max(0, daily.eggs - RaidLoop.dayDone(rd, day))
end

-- the guard of the k-th egg of the day (k from 1): the share of the thief's speed share[k] (past the last one - the last), after every catch softer by relief,
-- not below floor; wakes after wake[k]
function RaidLoop.dayShare(daily: any, k: number, tries: number): number
	local sh = daily.share
	local base = sh[math.clamp(k, 1, #sh)]
	return math.max(daily.floor or 0, base - (daily.relief or 0) * math.max(0, tries))
end

function RaidLoop.dayWake(daily: any, k: number): number
	local w = daily.wake
	return w[math.clamp(k, 1, #w)]
end

return RaidLoop
