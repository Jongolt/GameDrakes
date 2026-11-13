--!strict
-- The world layout (04 §2-5, spec 1.2): pure math without Roblox API, to check with the luau CLI tests.
-- The axes: X to the right, Z forward from the spawn (north = -Z, where Cliffs is; south = +Z, where Summit is), Y up.
-- The petal angle th sets the direction dir(th) = (cos th, 0, -sin th): 0 = east, 90 = north, 180 = west, 270 = south.
-- The petals at angles 60 and 120 face north (Cliffs) - as in the map 04 §2.

local Config = require("./../Config")
local Island = require("./Island") -- C2: the shore outline and the terrain height
local SpringsShape = require("./SpringsShape") -- the egg spots on the bath rims

local Layout = {}

export type Vec = { number } -- {x, y, z}
export type NestPivot = { index: number, angleDeg: number, center: Vec, yawDeg: number }
export type EggPoint = { id: string, zone: string, pos: Vec, secret: boolean? } -- secret: without a caption and hints (the Springs grotto)
export type Stairs = { index: number, angleDeg: number, top: Vec, bottom: Vec, length: number }

local W = Config.World

local function dir(angleDeg: number): Vec
	local a = math.rad(angleDeg)
	return { math.cos(a), 0, -math.sin(a) }
end
Layout.dir = dir

-- The rotation around Y at which the local +Z axis (from the plaza to the ledge) looks along dir(th).
-- For CFrame.Angles(0, yaw, 0): RightVector = (cos yaw, 0, -sin yaw), the local +Z (back) = (sin yaw, 0, cos yaw).
local function yawFor(angleDeg: number): number
	local d = dir(angleDeg)
	return math.deg(math.atan2(d[1], d[3]))
end
Layout.yawFor = yawFor

-- From the petal's local coordinates (x the width, y the height, z from the plaza to the ledge) to the world
function Layout.localToWorld(pivot: NestPivot, p: Vec): Vec
	local yaw = math.rad(pivot.yawDeg)
	local rx, rz = math.cos(yaw), -math.sin(yaw) -- RightVector
	local bx, bz = math.sin(yaw), math.cos(yaw) -- the local +Z
	return {
		pivot.center[1] + p[1] * rx + p[3] * bx,
		pivot.center[2] + p[2],
		pivot.center[3] + p[1] * rz + p[3] * bz,
	}
end

-- 6 petals: the center at radius (rInner + rOuter) / 2 at the terrace height
function Layout.nestPivots(): { NestPivot }
	local out = {}
	local n = W.nests
	local rMid = (n.rInner + n.rOuter) / 2
	for i = 1, n.count do
		local angle = (i - 1) * n.angleStep
		local d = dir(angle)
		table.insert(out, {
			index = i,
			angleDeg = angle,
			center = { d[1] * rMid, W.terrace.y, d[3] * rMid },
			yawDeg = yawFor(angle),
		})
	end
	return out
end

-- The stairs between the petals (the terrace wedges): the angle th + 30, from the terrace edge down onto the glade, a 30-degree slope
function Layout.stairs(): { Stairs }
	local out = {}
	local n = W.nests
	local drop = W.terrace.y
	local run = drop / math.tan(math.rad(30))
	for i = 1, n.count do
		local angle = (i - 1) * n.angleStep + n.angleStep / 2
		local d = dir(angle)
		local r0 = W.terrace.radius
		table.insert(out, {
			index = i,
			angleDeg = angle,
			top = { d[1] * r0, drop, d[3] * r0 },
			bottom = { d[1] * (r0 + run), 0, d[3] * (r0 + run) },
			length = math.sqrt(run * run + drop * drop),
		})
	end
	return out
end

-- 30 egg spots (04 §4)
function Layout.eggPoints(): { EggPoint }
	local out = {}
	local Z = W.zones
	local m = Z.Meadow
	for i = 1, m.points do
		local angle = (i - 1) * m.ring.angles
		local r = m.ring.radii[((i - 1) % #m.ring.radii) + 1]
		local d = dir(angle)
		local mv = m.move and m.move[i] -- a ring spot inside a closed zone (meadow_6 was in Springs) - moved
		table.insert(out, { id = "meadow_" .. i, zone = "Meadow", pos = if mv then { mv[1], m.y, mv[2] } else { d[1] * r, m.y, d[3] * r } })
	end
	local c = Z.Cliffs
	for i = 1, c.points do
		table.insert(out, {
			id = "cliffs_" .. i,
			zone = "Cliffs",
			pos = { c.xFrom + (i - 1) * c.xStep, c.y[((i - 1) % #c.y) + 1], c.z },
		})
	end
	local s = Z.Springs
	local k = 0
	if W.springsMesh and W.springsMesh.enabled then -- 6 spots on the bowl rims (the bath generator)
		for _, p in SpringsShape.points do
			k += 1
			table.insert(out, { id = "springs_" .. k, zone = "Springs", pos = { p[1], p[2], p[3] } })
		end
		local G = SpringsShape.grotto -- the 31st spot - secret, in the grotto behind the waterfall
		if G then
			k += 1
			table.insert(out, { id = "springs_" .. k, zone = "Springs", pos = { G.egg[1], G.egg[2], G.egg[3] }, secret = true })
		end
	else
		for _, z in s.zs do
			for _, x in s.xs do
				k += 1
				table.insert(out, { id = "springs_" .. k, zone = "Springs", pos = { x, s.y, z } })
			end
		end
	end
	local t = Z.Summit
	for i = 1, t.points do
		local a = math.rad((i - 1) * (360 / t.points))
		table.insert(out, {
			id = "summit_" .. i,
			zone = "Summit",
			pos = { t.center[1] + math.cos(a) * t.ring, t.center[2], t.center[3] + math.sin(a) * t.ring },
		})
	end
	return out
end

-- The wind rings (04 §5.1): the position and the axis direction (toward the next ring)
function Layout.windRings(): { { index: number, pos: Vec, axis: Vec } }
	local out = {}
	local ps = W.windRings.positions
	for i, p in ps do
		local nxt = ps[math.min(i + 1, #ps)]
		local prev = ps[math.max(i - 1, 1)]
		local ax = { nxt[1] - prev[1], nxt[2] - prev[2], nxt[3] - prev[3] }
		local len = math.sqrt(ax[1] ^ 2 + ax[2] ^ 2 + ax[3] ^ 2)
		if len < 1e-6 then
			ax = { 0, 0, 1 }
		else
			ax = { ax[1] / len, ax[2] / len, ax[3] / len }
		end
		table.insert(out, { index = i, pos = { p[1], p[2], p[3] }, axis = ax })
	end
	return out
end

-- The Summit mountain radius at height y (the truncated cone 04 §2)
function Layout.mountainRadius(y: number): number
	local h = W.zones.Summit.center[2]
	local t = math.clamp(y / h, 0, 1)
	return W.mountain.baseRadius + (W.mountain.topRadius - W.mountain.baseRadius) * t
end

-- The zone signs: the position and the yaw. The front side (SurfaceGui Front) = LookVector = (-sin yaw, 0, -cos yaw): yaw 0 -> north
-- 90 -> west, 180 -> south, 270 -> east. The text is assembled by WorldBuilder.
function Layout.zoneSigns(): { { zone: string, pos: Vec, yawDeg: number } }
	local S = W.zones.Summit.center
	return {
		-- at the south-eastern stairs (330): the southern one runs into the foot of the Summit mountain; facing the terrace
		{ zone = "Meadow", pos = { dir(330)[1] * (W.terrace.radius + 44), 0, dir(330)[3] * (W.terrace.radius + 44) }, yawDeg = 60 },
		{ zone = "Cliffs", pos = { 0, 0, W.zones.Cliffs.z + 45 }, yawDeg = 180 }, -- at the foot; Front (LookVector) to the south, toward those coming from the terrace
		{ zone = "Springs", pos = { W.zones.Springs.bridge.x + 16, 0, W.zones.Springs.bridge.z + 10 }, yawDeg = 270 }, -- at the bridge; Front to the east, toward those coming from the glade
		{ zone = "Summit", pos = { 0, 0, S[3] - W.mountain.baseRadius - 10 }, yawDeg = 0 }, -- at the mountain foot; Front to the north, toward those coming from the terrace
	}
end

-- The island bounds (for the tests): everything playable must lie inside the noisy shore outline (C2: Island.coastRadius)
function Layout.insideIsland(p: Vec, margin: number?): boolean
	return Island.onLand(p[1], p[3], margin)
end

-- The full surface height (the beach, the hills, the plateau, the ridge, the peak, Springs) - for the decor and the coins (C2)
function Layout.terrainHeight(hills: { Hill }, x: number, z: number): number
	local h = Island.height(hills, x, z)
	return h
end

-- ---------------------------------------------------------------------------------------------- polish 1.5
-- A deterministic generator (LCG) without Roblox API: the server and the tests compute the same layout
local function rng(seed: number): () -> number
	local state = seed % 2147483648
	return function(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end
Layout.rng = rng

-- the rng above loses precision (state x 1103515245 > 2^53) and cycles after ~hundreds of steps (the pillar chains repeated
-- heights and coordinates). A precise Park-Miller generator (the product < 2^53), the period 2^31-2. The old one is kept: the whole
-- existing layout (the hills, the egg spots, the decor) depends on it; moving the whole world over - a separate pass.
local function rng2(seed: number): () -> number
	local state = (math.floor(math.abs(seed)) % 2147483646) + 1
	return function(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
end
Layout.rng2 = rng2

local function dist2(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- the distance from a point to the segment a-b in the XZ plane
local function segDist(px: number, pz: number, a: Vec, b: Vec): number
	local dx, dz = b[1] - a[1], b[3] - a[3]
	local len2 = dx * dx + dz * dz
	local t = 0
	if len2 > 1e-9 then
		t = math.clamp(((px - a[1]) * dx + (pz - a[3]) * dz) / len2, 0, 1)
	end
	return dist2(px, pz, a[1] + dx * t, a[3] + dz * t)
end
Layout.segDist = segDist

export type Path = { zone: string, from: Vec, to: Vec, length: number }
export type Hill = { x: number, z: number, r: number, h: number }
export type EdgeRock = { x: number, z: number, angleDeg: number, w: number, h: number, d: number, yawDeg: number }

-- The path targets: the zone sign or an egg spot by id; for Springs - the eastern end of the bridge (the sign stands beyond the bridge)
function Layout.pathTargets(): { [string]: Vec }
	local out: { [string]: Vec } = {}
	for _, sg in Layout.zoneSigns() do
		out[sg.zone] = sg.pos
	end
	for _, p in Layout.eggPoints() do
		out[p.id] = p.pos
	end
	local br = W.zones.Springs.bridge
	out.Springs = { br.x + 26, 0, br.z } -- C2: the path end before the channel rim (|x + 212| > 12)
	return out
end

-- The paths (craft/04 §7.4, §7.6): from the stair foot to the zone target, in a straight line; they start beyond the foot, end before the target
function Layout.paths(): { Path }
	local targets = Layout.pathTargets()
	local byAngle: { [number]: Stairs } = {}
	for _, s in Layout.stairs() do
		byAngle[s.angleDeg] = s
	end
	local out = {}
	local parts = W.paths.parts or 1 -- a polyline with a bend instead of a straight strip
	for ri, r in W.paths.routes do
		local s = byAngle[r.stairs]
		local t = targets[r.to]
		if s and t then
			local dx, dz = t[1] - s.bottom[1], t[3] - s.bottom[3]
			local len = math.sqrt(dx * dx + dz * dz)
			if len > 20 then
				local ux, uz = dx / len, dz / len
				local from = { s.bottom[1] + ux * 2, 0, s.bottom[3] + uz * 2 }
				local to = { t[1] - ux * 8, 0, t[3] - uz * 8 }
				local amp = math.min(W.paths.curve or 0, len * 0.1) * (if ri % 2 == 0 then 1 else -1)
				local prev = from
				for k = 1, parts do
					local f = k / parts
					local off = if k == parts then 0 else amp * math.sin(math.pi * f) + math.abs(amp) * 0.3 * math.sin(3 * math.pi * f + ri)
					local p = { from[1] + (to[1] - from[1]) * f - uz * off, 0, from[3] + (to[3] - from[3]) * f + ux * off }
					local sl = math.sqrt((p[1] - prev[1]) ^ 2 + (p[3] - prev[3]) ^ 2)
					table.insert(out, { zone = r.to, from = prev, to = p, length = sl, route = ri, part = k })
					prev = p
				end
			end
		end
	end
	return out
end

-- Whether a hill of radius r can be placed at (x, z): outside Springs/the channel, the Cliffs and mountain feet, away from the egg spots,
-- the stairs, the signs, the paths and other hills
local function hillAllowed(x: number, z: number, r: number, pts: { EggPoint }, stairs: { Stairs }, signs: { any }, paths: { Path }, hills: { Hill }): boolean
	local H = W.hills
	if (x - r < -190 and z > -150 and z < 190) or z - r < -290 then
		return false -- the Springs area with the channel, the Cliffs ridge foot
	end
	if not Island.onLand(x, z, r + 40) then
		return false -- C2: not on the beach and not in the sea
	end
	local S = W.zones.Summit.center
	if dist2(x, z, S[1], S[3]) < W.mountain.baseRadius + r + 16 then
		return false
	end
	if dist2(x, z, 0, 0) - r < W.terrace.radius + 24 then
		return false
	end
	for _, p in pts do
		if dist2(x, z, p.pos[1], p.pos[3]) < r + H.keepFromPoints then
			return false
		end
	end
	for _, s in stairs do
		if dist2(x, z, s.bottom[1], s.bottom[3]) < r + H.keepFromStairs then
			return false
		end
	end
	for _, sg in signs do
		if dist2(x, z, sg.pos[1], sg.pos[3]) < r + H.keepFromSigns then
			return false
		end
	end
	for _, pa in paths do
		if segDist(x, z, pa.from, pa.to) < r + H.keepFromPaths then
			return false
		end
	end
	for _, h in hills do
		if dist2(x, z, h.x, h.z) < r + h.r - 6 then
			return false
		end
	end
	return true
end

-- The glade hills: a cosine hump of radius r and height h (gentle: the slope at the foot is zero)
function Layout.hills(): { Hill }
	local H = W.hills
	local g = rng(H.seed)
	local pts, stairs, signs, paths = Layout.eggPoints(), Layout.stairs(), Layout.zoneSigns(), Layout.paths()
	local out: { Hill } = {}
	local tries = 0
	while #out < H.count and tries < 600 do
		tries += 1
		local a = g() * math.pi * 2
		local rad = H.rMin + g() * (Island.coastRadius(-a) * H.coastShare - H.rMin) -- C2: up to a share of the shore radius in this direction
		local x, z = math.cos(a) * rad, math.sin(a) * rad
		local r = H.radius[1] + g() * (H.radius[2] - H.radius[1])
		local h = H.height[1] + g() * (H.height[2] - H.height[1])
		if hillAllowed(x, z, r, pts, stairs, signs, paths, out) then
			table.insert(out, { x = x, z = z, r = r, h = h })
		end
	end
	return out
end

-- The ground height above y = 0 at point (x, z) with the hills (hills - the result of Layout.hills(), to avoid recomputing)
function Layout.groundHeight(hills: { Hill }, x: number, z: number): number
	local best = 0
	for _, h in hills do
		local d = dist2(x, z, h.x, h.z)
		if d < h.r then
			best = math.max(best, h.h * 0.5 * (1 + math.cos(math.pi * d / h.r)))
		end
	end
	return best
end

-- The slab rocks along the island edge (craft/04 §7.4 item 1): a ring at radius rMin..rMax with gaps (skipAngles, dir degrees)
function Layout.edgeRocks(): { EdgeRock }
	local E = W.edgeRocks
	local g = rng(E.seed)
	local out: { EdgeRock } = {}
	for i = 1, E.count do
		local angle = (i - 1) * (360 / E.count) + (g() - 0.5) * 8
		angle = angle % 360
		local skip = false
		for _, rangeDeg in E.skipAngles do
			if angle >= rangeDeg[1] and angle <= rangeDeg[2] then
				skip = true
			end
		end
		if not skip then
			local rad = Island.coastRadius(math.rad(angle)) * (E.coastFrom + g() * (E.coastTo - E.coastFrom)) -- C2: at the noisy shore
			local d = dir(angle)
			table.insert(out, {
				x = d[1] * rad,
				z = d[3] * rad,
				angleDeg = angle,
				w = E.size[1] + g() * (E.size[2] - E.size[1]),
				h = E.height[1] + g() * (E.height[2] - E.height[1]),
				d = 10 + g() * 10,
				yawDeg = yawFor(angle) + (g() - 0.5) * 30,
			})
		end
	end
	return out
end

-- The coins on the paths (craft/04 §7.4 item 3): perRoute pieces, evenly along the path length
-- the floating islands - a ring and tiers around the Summit peak, three sizes, the gaps between
-- them not less than minGap; they do not hang on the plaza side (above the nests). Without ring - the old positions islets.positions
function Layout.islets(): { { x: number, y: number, z: number, r: number, tier: number, i: number } }
	local I = W.islets
	local R = I.ring
	local out = {}
	if not R then
		for i, p in I.positions do
			table.insert(out, { x = p[1], y = p[2], z = p[3], r = (I.radius[1] + I.radius[2]) / 2, tier = 2, i = i })
		end
		return out
	end
	local g = rng(R.seed)
	local S = W.zones.Summit.center
	local toPlaza = math.atan2(-S[3], -S[1])
	for tier = #R.tiers, 1, -1 do -- the big ones first: otherwise the gaps filter out the large ones and only the small ones remain
		local T = R.tiers[tier]
		for _ = 1, T.n do
			for _ = 1, 80 do
				local a = g() * math.pi * 2
				local da = math.abs(((a - toPlaza + math.pi) % (2 * math.pi)) - math.pi)
				local r = T.r[1] + g() * (T.r[2] - T.r[1])
				local d = R.rMin + g() * (R.rMax - R.rMin)
				local y = R.yMin + g() * (R.yMax - R.yMin)
				local x, z = S[1] + math.cos(a) * d, S[3] + math.sin(a) * d
				local ok = da > math.rad(R.skipToPlaza)
				if ok then
					for _, o in out do
						if math.sqrt((x - o.x) ^ 2 + (z - o.z) ^ 2 + ((y - o.y) * 0.6) ^ 2) - r - o.r < R.minGap then
							ok = false
							break
						end
					end
				end
				if ok then
					table.insert(out, { x = x, y = y, z = z, r = r, tier = tier, i = #out + 1 })
					break
				end
			end
		end
	end
	local SI = W.springsMesh and W.springsMesh.enabled and SpringsShape.islet -- the islet above the top of the cascade
	if SI then
		table.insert(out, { x = SI.x, y = SI.y, z = SI.z, r = SI.r, tier = SI.tier, i = #out + 1 })
	end
	return out
end

function Layout.coins(): { { id: string, zone: string, pos: Vec } }
	local out = {}
	local n = W.coins.perRoute
	for _, pa in Layout.paths() do
		local k = pa.part or 1 -- the path is a polyline; a coin in the middle of the first n segments
		if k <= n then
			table.insert(out, {
				id = string.lower(pa.zone) .. "_coin" .. k,
				zone = pa.zone,
				pos = { (pa.from[1] + pa.to[1]) / 2, 0, (pa.from[3] + pa.to[3]) / 2 },
			})
		end
	end
	return out
end

return Layout
