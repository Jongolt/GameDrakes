--!strict
-- The mesh decor layout (craft/02 §3-4; 04 §1): pure math without Roblox API. Deterministic (Layout.rng),
-- so the server and the tests see the same thing. Every item: the kind (the Kenney mesh name), x/z, y (nil = on the ground with the hills,
-- a number = an absolute height), the rotation, the height in studs, the palette shade number. The constraints: not on the paths, egg spots,
-- signs, stair feet, the terrace, the Springs area, the Cliffs and mountain feet.

local Config = require("./../Config")
local Layout = require("./Layout")
local Island = require("./Island") -- C2: the noisy shore
local SpringsShape = require("./SpringsShape") -- the bath bowls - the decor goes around

local DecorLayout = {}

export type Item = { kind: string, x: number, z: number, y: number?, yaw: number, h: number, tint: number, collide: boolean?, granite: boolean?, sea: boolean?, top: boolean?, flip: boolean?, widthTo: number?, snapDown: boolean?, ax: number?, az: number? } -- top: y = the model top; flip - upside down; widthTo - stretch along X/Z (the island bodies)

local W = Config.World
local D = W.decor
local I2 = W.island2

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- the shared obstacles (computed once)
local function obstacles()
	return {
		points = Layout.eggPoints(),
		stairs = Layout.stairs(),
		signs = Layout.zoneSigns(),
		paths = Layout.paths(),
		summit = W.zones.Summit.center,
	}
end

-- whether the spot on the glade is free for an item with a margin of margin
local function free(o: any, x: number, z: number, margin: number): boolean
	if (x - margin < -190 and z > -140 and z < 180) or z - margin < -290 then
		return false -- Springs with the channel (a strip along z), the Cliffs foot; C2: the west outside the Springs strip is open (before, the whole west was empty)
	end
	if dist(x, z, 0, 0) - margin < W.terrace.radius + 10 then
		return false
	end
	if dist(x, z, o.summit[1], o.summit[3]) - margin < W.mountain.baseRadius + 10 then
		return false
	end
	if Island.landFactor(x, z) > I2.beach.start - 0.01 then
		return false -- C2: not on the beach and not in the sea
	end
	for _, p in o.points do
		if dist(x, z, p.pos[1], p.pos[3]) < margin + 8 then
			return false
		end
	end
	for _, s in o.stairs do
		if dist(x, z, s.bottom[1], s.bottom[3]) < margin + 16 then
			return false
		end
	end
	for _, sg in o.signs do
		if dist(x, z, sg.pos[1], sg.pos[3]) < margin + 12 then
			return false
		end
	end
	for _, pa in o.paths do
		if Layout.segDist(x, z, pa.from, pa.to) < W.paths.width / 2 + margin + 1 then
			return false
		end
	end
	return true
end
DecorLayout.free = free

local function offPaths(o: any, x: number, z: number, margin: number): boolean
	for _, pa in o.paths do
		if Layout.segDist(x, z, pa.from, pa.to) < W.paths.width / 2 + margin then
			return false
		end
	end
	return true
end

local function pick<T>(g: () -> number, list: { T }): T
	return list[math.floor(g() * #list) + 1] or list[1]
end

-- the tree kind: the accents (autumn, blossom) by shares, otherwise from the kinds list
local function treeKind(g: () -> number, kinds: { string }): string
	local r = g()
	local acc = 0
	for _, a in D.accents do
		acc += a.share
		if r < acc then
			return a.kind
		end
	end
	return pick(g, kinds)
end

-- C7: in the lowlands at the water some trees are broadleaves (the choice by coordinate, without calling the generator - the layout does not shift)
local function treeListAt(x: number, z: number, kinds: { string }): { string }
	local LW = D.lowland
	if LW and Island.landFactor(x, z) >= LW.from and (math.floor(math.abs(x * 7.31 + z * 3.17)) % 100) / 100 < LW.share then
		return LW.kinds
	end
	return kinds
end

local function heightOf(g: () -> number, kind: string): number
	local r = D.height[kind]
	assert(r, "no height for " .. kind)
	return r[1] + g() * (r[2] - r[1])
end

local function spotMeadow(g: () -> number, o: any, margin: number, rMin: number?, rMax: number?): (number?, number?)
	for _ = 1, 40 do
		local a = g() * math.pi * 2
		local lo = rMin or W.terrace.radius + 30
		local hi = rMax or Island.coastRadius(-a) * (I2.beach.start - 0.04) -- C2: up to the beach in this direction
		local r = lo + g() * (hi - lo)
		local x, z = math.cos(a) * r, math.sin(a) * r
		if free(o, x, z, margin) then
			return x, z
		end
	end
	return nil, nil
end

function DecorLayout.items(): { Item }
	local g = Layout.rng2(D.seed)
	local o = obstacles()
	local out: { Item } = {}
	local function add(kind: string, x: number, z: number, y: number?, collide: boolean?)
		table.insert(out, { kind = kind, x = x, z = z, y = y, yaw = g() * 360, h = heightOf(g, kind), tint = math.floor(g() * 1000), collide = collide })
	end
	local trees: { { number } } = {} -- for the mushrooms and the distances

	-- the groves: a center + 5-9 trees of two kinds, bushes, logs
	for _ = 1, D.groves.count do
		local cx, cz = spotMeadow(g, o, 24)
		if cx and cz then
			local rad = D.groves.radius[1] + g() * (D.groves.radius[2] - D.groves.radius[1])
			local list = treeListAt(cx, cz, D.treeKinds) -- C7: a grove in a lowland - broadleaf
			local kinds = { pick(g, list), pick(g, list) }
			local n = D.groves.trees[1] + math.floor(g() * (D.groves.trees[2] - D.groves.trees[1] + 1))
			local placed = 0
			for _ = 1, n * 4 do
				if placed >= n then
					break
				end
				local a, r = g() * math.pi * 2, math.sqrt(g()) * rad
				local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
				local okSpacing = true
				for _, t in trees do
					if dist(x, z, t[1], t[2]) < D.groves.spacing then
						okSpacing = false
						break
					end
				end
				if okSpacing and free(o, x, z, 4) then
					add(treeKind(g, kinds), x, z, nil, true)
					table.insert(trees, { x, z })
					placed += 1
				end
			end
			local nb = D.bushes.perGrove[1] + math.floor(g() * (D.bushes.perGrove[2] - D.bushes.perGrove[1] + 1))
			for _ = 1, nb do
				local a, r = g() * math.pi * 2, g() * rad
				local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
				if free(o, x, z, 2) then
					add(pick(g, D.bushes.kinds), x, z)
				end
			end
		end
	end
	-- single trees
	for _ = 1, D.singles do
		local x, z = spotMeadow(g, o, 6)
		if x and z then
			local okSpacing = true
			for _, t in trees do
				if dist(x, z, t[1], t[2]) < D.groves.spacing then
					okSpacing = false
				end
			end
			if okSpacing then
				add(treeKind(g, treeListAt(x, z, D.treeKinds)), x, z, nil, true)
				table.insert(trees, { x, z })
			end
		end
	end
	-- scattered bushes
	for _ = 1, D.bushes.scattered do
		local x, z = spotMeadow(g, o, 2)
		if x and z then
			add(pick(g, D.bushes.kinds), x, z)
		end
	end
	-- the grass: along the paths, around the glade egg spots, scattered
	local meadowPoints = {}
	for _, p in o.points do
		if p.zone == "Meadow" then
			table.insert(meadowPoints, p)
		end
	end
	for i = 1, D.grass.count do
		local u = i / D.grass.count
		local x, z
		if u < D.grass.nearPaths and #o.paths > 0 then
			local pa = pick(g, o.paths)
			local t = g()
			local px, pz = pa.from[1] + (pa.to[1] - pa.from[1]) * t, pa.from[3] + (pa.to[3] - pa.from[3]) * t
			local dx, dz = pa.to[1] - pa.from[1], pa.to[3] - pa.from[3]
			local len = math.sqrt(dx * dx + dz * dz)
			local nx, nz = -dz / len, dx / len
			local side = if g() < 0.5 then 1 else -1
			local off = W.paths.width / 2 + 1.5 + g() * 5
			x, z = px + nx * off * side, pz + nz * off * side
			if not free(o, x, z, -0.5) then
				x = nil
			end
		elseif u < D.grass.nearPaths + D.grass.nearPoints and #meadowPoints > 0 then
			local p = pick(g, meadowPoints)
			local a, r = g() * math.pi * 2, 5 + g() * 7
			x, z = p.pos[1] + math.cos(a) * r, p.pos[3] + math.sin(a) * r
			if dist(x, z, 0, 0) < W.terrace.radius + 10 or not offPaths(o, x, z, 0.5) then
				x = nil
			end
		else
			x, z = spotMeadow(g, o, 0)
		end
		if x and z then
			add(pick(g, D.grass.kinds), x, z)
		end
	end
	-- flower patches
	for _ = 1, D.flowers.patches do
		local cx, cz = spotMeadow(g, o, 8)
		if cx and cz then
			local rad = D.flowers.radius[1] + g() * (D.flowers.radius[2] - D.flowers.radius[1])
			local kind = pick(g, D.flowers.kinds)
			local n = D.flowers.perPatch[1] + math.floor(g() * (D.flowers.perPatch[2] - D.flowers.perPatch[1] + 1))
			for _ = 1, n do
				local a, r = g() * math.pi * 2, math.sqrt(g()) * rad
				local x, z = cx + math.cos(a) * r, cz + math.sin(a) * r
				if free(o, x, z, 0) then
					add(if g() < 0.8 then kind else pick(g, D.flowers.kinds), x, z)
				end
			end
		end
	end
	-- mushrooms at the trees
	for _ = 1, D.mushrooms.count do
		if #trees > 0 then
			local t = pick(g, trees)
			local a, r = g() * math.pi * 2, 3 + g() * 3
			local x, z = t[1] + math.cos(a) * r, t[2] + math.sin(a) * r
			if free(o, x, z, 0) then
				add(pick(g, D.mushrooms.kinds), x, z)
			end
		end
	end
	-- rocks on the glade, logs and stumps
	for _ = 1, D.rocks.count do
		local x, z = spotMeadow(g, o, 4)
		if x and z then
			local kind = pick(g, D.rocks.kinds)
			add(kind, x, z, nil, D.height[kind][2] >= D.collideHeight)
		end
	end
	for _ = 1, D.logs.count do
		local x, z = spotMeadow(g, o, 3)
		if x and z then
			add(pick(g, D.logs.kinds), x, z)
		end
	end
	-- boulders at the foot of the mountain and the Cliffs rock
	local S = W.zones.Summit.center
	for i = 1, D.stones.summit do
		local a = (i - 1) / D.stones.summit * math.pi * 2 + g() * 0.4
		local r = W.mountain.baseRadius + 6 + g() * 8
		local x, z = S[1] + math.cos(a) * r, S[3] + math.sin(a) * r
		if Island.onLand(x, z, 12) and dist(x, z, 0, 0) > W.terrace.radius + 12 and offPaths(o, x, z, 3) then
			add(pick(g, D.stones.kinds), x, z, nil, true)
		end
	end
	local cz = W.zones.Cliffs.z
	for _ = 1, D.stones.cliffsFoot do
		local x, z = -200 + g() * 400, cz + 12 + g() * 28
		if (free(o, x, z, 2) or z < -280) and offPaths(o, x, z, 3) then
			add(pick(g, D.stones.kinds), x, z, nil, true)
		end
	end
	-- the shore: palms, driftwood, flat stones (outside the rock gaps, Springs and the mountain)
	local function shoreAngleOk(angleDeg: number): boolean
		for _, rangeDeg in W.edgeRocks.skipAngles do
			if angleDeg >= rangeDeg[1] and angleDeg <= rangeDeg[2] then
				return false
			end
		end
		return true
	end
	local function shoreSpot(): (number?, number?)
		for _ = 1, 30 do
			local angle = g() * 360
			if shoreAngleOk(angle) then
				local r = Island.coastRadius(math.rad(angle)) * (D.shore.coastFrom + g() * (D.shore.coastTo - D.shore.coastFrom)) -- C2: the beach strip at the noisy shore
				local d = Layout.dir(angle)
				return d[1] * r, d[3] * r
			end
		end
		return nil, nil
	end
	for _ = 1, D.shore.palms do
		local x, z = shoreSpot()
		if x and z then
			add(pick(g, D.shore.palmKinds), x, z, nil, true) -- C2: on the ground (the beach slopes gently into the water)
		end
	end
	for _ = 1, D.shore.driftwood do
		local x, z = shoreSpot()
		if x and z then
			add(D.shore.driftKind or "log", x, z, nil)
		end
	end
	for _ = 1, D.shore.flatStones do
		local x, z = shoreSpot()
		if x and z then
			add("stone_smallFlatB", x, z, nil)
		end
	end
	-- the forest wall along the glade perimeter (the painted trees), outside the Cliffs / Springs / Summit gaps and off the paths
	do
		local FB = D.forestBelt
		local placed = 0
		local tries = 0
		while placed < FB.count and tries < FB.count * 6 do
			tries += 1
			local angle = g() * 360
			local okAngle = true
			for _, rangeDeg in FB.skipAngles do
				if angle >= rangeDeg[1] and angle <= rangeDeg[2] then
					okAngle = false
				end
			end
			if okAngle then
				local rad = Island.coastRadius(math.rad(angle)) * (FB.coastFrom + g() * (FB.coastTo - FB.coastFrom)) -- C2: the forest strip at the shore
				local d = Layout.dir(angle)
				local x, z = d[1] * rad, d[3] * rad
				local okSpacing = Island.onLand(x, z, 10)
				if okSpacing then
					for _, t in trees do
						if dist(x, z, t[1], t[2]) < FB.spacing then
							okSpacing = false
							break
						end
					end
				end
				if okSpacing and free(o, x, z, 2) then
					add(treeKind(g, treeListAt(x, z, D.treeKinds)), x, z, nil, true)
					table.insert(trees, { x, z })
					placed += 1
				end
			end
		end
	end
	-- the terrace foot: boulders and bushes along the ring (the flat terrace wall hides), past the stairs
	do
		local TF = D.terraceFoot
		local function footSpot(margin: number): (number?, number?)
			for _ = 1, 30 do
				local angle = g() * 360
				local nearStairs = false
				for _, st in o.stairs do
					local da = math.abs(((angle - st.angleDeg + 180) % 360) - 180)
					if da < 7 then
						nearStairs = true
					end
				end
				if not nearStairs then
					local rad = TF.rMin + g() * (TF.rMax - TF.rMin)
					local d = Layout.dir(angle)
					local x, z = d[1] * rad, d[3] * rad
					if offPaths(o, x, z, margin) then
						return x, z
					end
				end
			end
			return nil, nil
		end
		for _ = 1, TF.boulders do
			local x, z = footSpot(3)
			if x and z then
				table.insert(out, { kind = pick(g, TF.kinds or D.stones.kinds), x = x, z = z, y = -0.5, yaw = g() * 360, h = 3 + g() * 4, tint = math.floor(g() * 1000), collide = true })
			end
		end
		for _ = 1, TF.bushes do
			local x, z = footSpot(1)
			if x and z then
				table.insert(out, { kind = pick(g, D.bushes.kinds), x = x, z = z, y = -0.2, yaw = g() * 360, h = 2.5 + g() * 2.5, tint = math.floor(g() * 1000) })
			end
		end
	end
	-- pines on the top of the Cliffs rock
	for _ = 1, D.cliffTop.pines do
		local x, z = -190 + g() * 380, cz - 66 + g() * 50
		add(pick(g, D.cliffTop.kinds), x, z, D.cliffTop.y, true) -- C4: y nil = by the ridge terrain
	end
	-- C4: the undergrowth - ferns at the trees and in the forest shade, bushes over the glade, heather at the ridge foot and on the slopes
	do
		local U = D.undergrowth
		if U then
			for _ = 1, U.ferns do
				local x, z
				if g() < U.nearTrees and #trees > 0 then
					local t = trees[math.floor(g() * #trees) + 1]
					local a, rr = g() * math.pi * 2, 3 + g() * 7
					x, z = t[1] + math.cos(a) * rr, t[2] + math.sin(a) * rr
					if not free(o, x, z, 1) then
						x = nil
					end
				else
					x, z = spotMeadow(g, o, 1)
				end
				if x and z then
					add(pick(g, U.fernKinds), x, z)
				end
			end
			for _ = 1, U.shrubs do
				local x, z = spotMeadow(g, o, 2)
				if x and z then
					add(pick(g, U.shrubKinds), x, z)
				end
			end
			for _ = 1, U.heather do
				local x, z
				if g() < 0.5 then
					x, z = -200 + g() * 400, cz + 14 + g() * 40 -- the ridge foot
					if not (free(o, x, z, 1) or z < -280) or not offPaths(o, x, z, 2) then
						x = nil
					end
				else
					x, z = spotMeadow(g, o, 1, W.terrace.radius + 32, W.terrace.radius + 70) -- the plateau slope and foot
				end
				if x and z then
					add(pick(g, U.heatherKinds), x, z)
				end
			end
		end
	end
	-- rocks along the island edge: a cluster of 2-4 boulders around every position of Layout.edgeRocks (at the water, partly in the sand)
	for _, r in Layout.edgeRocks() do
		local n = D.edge.perSpot[1] + math.floor(g() * (D.edge.perSpot[2] - D.edge.perSpot[1] + 1))
		for k = 1, n do
			local kind = pick(g, D.edge.kinds)
			local a, rr = g() * math.pi * 2, if k == 1 then 0 else g() * D.edge.spread
			local h = D.edge.height[1] + g() * (D.edge.height[2] - D.edge.height[1])
			if k > 1 then
				h *= 0.5 + g() * 0.4
			end
			table.insert(out, { kind = kind, x = r.x + math.cos(a) * rr, z = r.z + math.sin(a) * rr, y = -D.edge.sink, yaw = g() * 360, h = h, tint = math.floor(g() * 1000), collide = true })
		end
	end
	-- the Springs area: boulders around the pond, bushes, palms, flowers (the pond water at y 4, the area y 4)
	do
		local Sp = W.zones.Springs
		local sx = (Sp.xs[1] + Sp.xs[#Sp.xs]) / 2
		local pz = (Sp.zs[1] + Sp.zs[#Sp.zs]) / 2
		local ptsS = {}
		for _, p in o.points do
			if p.zone == "Springs" then
				table.insert(ptsS, p)
			end
		end
		local SMesh = W.springsMesh and W.springsMesh.enabled
		local function springsFree(x: number, z: number, margin: number): boolean
			if x < Sp.xs[1] - 55 or x > Sp.xs[#Sp.xs] + 40 or z < Sp.zs[1] - 90 or z > Sp.zs[#Sp.zs] + 90 then
				return false
			end
			if SMesh then -- the bath bowls and the spillways
				if SpringsShape.basinAt(x, z, 1.5 + margin) then
					return false
				end
				for _, c in SpringsShape.cascades do
					if Layout.segDist(x, z, c.top, c.bottom) < 3 + margin then
						return false
					end
				end
			elseif dist(x, z, sx, pz) < 20 + margin then
				return false -- the pond
			end
			for _, p in ptsS do
				if dist(x, z, p.pos[1], p.pos[3]) < 6 + margin then
					return false
				end
			end
			if math.abs(x - (Sp.bridge.x - 13)) < 10 and math.abs(z - Sp.bridge.z) < 12 then
				return false -- the gate and the bridge
			end
			return true
		end
		for i = 1, D.springs.stones do
			local a = (i - 1) / D.springs.stones * math.pi * 2 + g() * 0.3
			local rr = 21 + g() * 5
			local x, z = sx + math.cos(a) * rr, pz + math.sin(a) * rr
			local kind = pick(g, D.stones.kinds)
			if SMesh then -- boulders at the bowl rims outside, by the hill terrain
				local b = SpringsShape.basins[((i - 1) % #SpringsShape.basins) + 1]
				for _ = 1, 12 do
					local aa = g() * 360
					local r2 = SpringsShape.rin(b, aa) + SpringsShape.lip + 1.6 + g() * 1.8
					x, z = b.x + r2 * math.cos(math.rad(aa)), b.z - r2 * math.sin(math.rad(aa))
					if springsFree(x, z, 0) then
						break
					end
				end
				if springsFree(x, z, 0) then
					-- the ground height explicitly (there are no hills in Springs): boulders 2-5 studs, like the previous ones at the pond, lower than the sign ones
					table.insert(out, { kind = kind, x = x, z = z, y = (Island.height({}, x, z)) - 0.5, yaw = g() * 360, h = 2 + g() * 3, tint = math.floor(g() * 1000) })
				end
			else
				table.insert(out, { kind = kind, x = x, z = z, y = D.springs.y - 0.5, yaw = g() * 360, h = 2 + g() * 3, tint = math.floor(g() * 1000) })
			end
		end
		for _ = 1, D.springs.bushes do
			for _ = 1, 20 do
				local x, z = Sp.xs[1] - 40 + g() * 120, Sp.zs[1] - 70 + g() * 200
				if springsFree(x, z, 2) then
					table.insert(out, { kind = pick(g, D.bushes.kinds), x = x, z = z, y = if SMesh then (Island.height({}, x, z)) - 0.2 else D.springs.y - 0.2, yaw = g() * 360, h = 2.5 + g() * 2, tint = math.floor(g() * 1000) })
					break
				end
			end
		end
		for _ = 1, D.springs.palms do
			for _ = 1, 20 do
				local x, z = Sp.xs[1] - 40 + g() * 120, Sp.zs[1] - 70 + g() * 200
				if springsFree(x, z, 6) then
					table.insert(out, { kind = pick(g, D.shore.palmKinds), x = x, z = z, y = if SMesh then (Island.height({}, x, z)) - 0.2 else D.springs.y - 0.2, yaw = g() * 360, h = 14 + g() * 6, tint = math.floor(g() * 1000), collide = true })
					break
				end
			end
		end
		for _ = 1, D.springs.flowers do
			for _ = 1, 20 do
				local x, z = Sp.xs[1] - 40 + g() * 120, Sp.zs[1] - 70 + g() * 200
				if springsFree(x, z, 0) then
					table.insert(out, { kind = pick(g, D.flowers.kinds), x = x, z = z, y = if SMesh then (Island.height({}, x, z)) - 0.1 else D.springs.y - 0.1, yaw = g() * 360, h = 1.2 + g() * 0.7, tint = math.floor(g() * 1000) })
					break
				end
			end
		end
	end
	-- the terrace gardens: the wedges between the petals (the width grows toward the edge), around the stairs (angle th + 30)
	do
		local TG = D.terraceGardens
		local n = W.nests
		for i = 1, n.count do
			local angle = (i - 1) * n.angleStep + n.angleStep / 2 -- the stairs axis
			local function wedgeSpot(margin: number): (number?, number?)
				for _ = 1, 30 do
					local da = (g() - 0.5) * 2 * 24 -- +-24 degrees from the axis
					local r = 120 + g() * 44
					local d = Layout.dir(angle + da)
					local x, z = d[1] * r, d[3] * r
					-- half the petal width 28 from the neighboring petal's axis: the point must be farther than 28 + margin from both petal axes
					local okLot = true
					for _, k in { -1, 1 } do
						local dl = Layout.dir(angle + k * n.angleStep / 2)
						local along = x * dl[1] + z * dl[3]
						local across = math.abs(x * (-dl[3]) + z * dl[1])
						if along > 0 and across < 28 + 3 + margin then
							okLot = false
						end
					end
					local ds = Layout.dir(angle)
					local acrossStairs = math.abs(x * (-ds[3]) + z * ds[1])
					if okLot and acrossStairs > 7 + margin then
						return x, z
					end
				end
				return nil, nil
			end
			for _ = 1, TG.trees do
				local x, z = wedgeSpot(3)
				if x and z then
					table.insert(out, { kind = pick(g, D.treeKinds), x = x, z = z, y = W.terrace.y, yaw = g() * 360, h = TG.treeHeight[1] + g() * (TG.treeHeight[2] - TG.treeHeight[1]), tint = math.floor(g() * 1000), collide = true })
				end
			end
			for _ = 1, TG.bushes do
				local x, z = wedgeSpot(1)
				if x and z then
					table.insert(out, { kind = pick(g, D.bushes.kinds), x = x, z = z, y = W.terrace.y, yaw = g() * 360, h = 2.2 + g() * 1.6, tint = math.floor(g() * 1000) })
				end
			end
			for _ = 1, TG.flowers do
				local x, z = wedgeSpot(0)
				if x and z then
					table.insert(out, { kind = pick(g, D.flowers.kinds), x = x, z = z, y = W.terrace.y, yaw = g() * 360, h = 1.2 + g() * 0.6, tint = math.floor(g() * 1000) })
				end
			end
			for _ = 1, TG.rocks do
				local x, z = wedgeSpot(2)
				if x and z then
					-- the same rock, now solid as a whole (Decor.prepare)
					table.insert(out, { kind = "rock_largeA", x = x, z = z, y = W.terrace.y, yaw = g() * 360, h = 2 + g() * 1.5, tint = math.floor(g() * 1000), collide = true })
				end
			end
		end
	end
	-- slab stones along the paths
	for _, pa in o.paths do
		local dx, dz = pa.to[1] - pa.from[1], pa.to[3] - pa.from[3]
		local len = math.sqrt(dx * dx + dz * dz)
		local t = 4
		local side = 1
		while t < len - 4 do
			local px, pz = pa.from[1] + dx / len * t, pa.from[3] + dz / len * t
			local nx, nz = -dz / len, dx / len
			table.insert(out, { kind = D.pathStones.kind, x = px + nx * side * 1.2, z = pz + nz * side * 1.2, yaw = g() * 360, h = heightOf(g, D.pathStones.kind), tint = 0 })
			side = -side
			t += D.pathStones.step
		end
	end
	-- lily pads in the Springs pond (the water at y 4)
	local Sp = W.zones.Springs
	local sx = (Sp.xs[1] + Sp.xs[#Sp.xs]) / 2
	local pz = (Sp.zs[1] + Sp.zs[#Sp.zs]) / 2
	local LG = W.springsMesh and W.springsMesh.enabled and SpringsShape.basins[1] -- lily pads on the water of the lagoon bowl
	for _ = 1, D.lilies.count do
		local a, r = g() * math.pi * 2, math.sqrt(g()) * 13
		if LG then
			r = math.sqrt(g()) * (LG.rin[1] - 4)
			table.insert(out, { kind = D.lilies.kind, x = LG.x + math.cos(a) * r, z = LG.z + math.sin(a) * r, y = LG.water + 0.05, yaw = g() * 360, h = heightOf(g, D.lilies.kind), tint = math.floor(g() * 1000) })
		else
			table.insert(out, { kind = D.lilies.kind, x = sx + math.cos(a) * r, z = pz + math.sin(a) * r, y = 4.05, yaw = g() * 360, h = heightOf(g, D.lilies.kind), tint = math.floor(g() * 1000) })
		end
	end
	-- the body - a stack of rocks
	-- downward, each narrower (taller than wide), rocks along the rim, vines around (more on the big ones), greenery and 0-3 trees of different kinds
	-- on the cap. The cap as terrain (WorldBuilder.buildIslets), the cap top at y + 1. An own generator - the layout does not shift
	do
		local IR = W.islets.rocks
		local gi = Layout.rng2(91)
		local function rr(a: number, b: number): number
			return a + gi() * (b - a)
		end
		for _, isl in Layout.islets() do
			local r, cx, cy, cz = isl.r, isl.x, isl.y, isl.z
			local capBottom = cy - 5
			-- the body - a big Poly Haven rock with
			-- the texture upside down, stretched to the island width; the tail - 1-2 smaller rocks, also upside down
			local bodyH = r * rr(IR.bodyH[1], IR.bodyH[2])
			table.insert(out, { kind = pick(gi, IR.bodyKinds), x = cx, z = cz, y = capBottom + 2.5, yaw = gi() * 360, h = bodyH, tint = 0, collide = true, granite = true, flip = true, top = true, widthTo = r * 2.05 }) -- the body is solid
			local tipTop, tipW = capBottom + 2.5 - bodyH * 0.55, r * 1.1
			for k = 1, 1 + (if isl.tier >= 2 then 1 else 0) do
				local th = bodyH * (if k == 1 then 0.75 else 0.5)
				table.insert(out, { kind = pick(gi, IR.bodyKinds), x = cx + (gi() - 0.5) * r * 0.3, z = cz + (gi() - 0.5) * r * 0.3, y = tipTop, yaw = gi() * 360, h = th, tint = 0, collide = true, granite = true, flip = true, top = true, widthTo = tipW })
				tipTop -= th * 0.6
				tipW *= 0.6
			end
			local nv = IR.vinesBase + isl.tier * IR.vinesPerTier
			local v0 = gi() * math.pi * 2
			for k = 1, nv do
				local a = v0 + k * math.pi * 2 / nv + (gi() - 0.5) * 0.3
				local hv = math.min(IR.vinesMax, r * rr(0.8, 1.6) + 6)
				table.insert(out, { kind = "cs_vines", x = cx + math.cos(a) * r * 0.92, z = cz + math.sin(a) * r * 0.92, y = cy + 1 - hv, yaw = math.deg(a) + 90, h = hv, tint = math.floor(gi() * 1000), collide = false })
			end
			for _ = 1, math.floor(2 + r * IR.greenPerR) do
				local a, d = gi() * math.pi * 2, math.sqrt(gi()) * r * 0.8
				local kind = pick(gi, IR.green)
				table.insert(out, { kind = kind, x = cx + math.cos(a) * d, z = cz + math.sin(a) * d, y = cy + 0.8, yaw = gi() * 360, h = heightOf(gi, kind), tint = math.floor(gi() * 1000) })
			end
			local T = IR.trees[isl.tier]
			for _ = 1, T.n[1] + math.floor(gi() * (T.n[2] - T.n[1] + 1)) do
				local a, d = gi() * math.pi * 2, math.sqrt(gi()) * r * 0.5
				table.insert(out, { kind = pick(gi, T.kinds), x = cx + math.cos(a) * d, z = cz + math.sin(a) * d, y = cy + 0.8, yaw = gi() * 360, h = rr(T.h[1], T.h[2]), tint = math.floor(gi() * 1000), collide = false })
			end
		end
	end
	-- C2: stone as meshes with granite (the phone draws the terrain in flat color, the meshes - with a texture): boulders along the shore, the Cliffs ridge
	-- facade, the terrace slope, the sea pillars with pines. The numbers - Config.World.island2.rocks; y nil = on the ground, a number = absolute.
	do
		local R = I2.rocks
		local gr = Layout.rng2(R.seed)
		local WD = W.zones.Cliffs.wind
		local function addRock(kind: string, x: number, z: number, y: number?, h: number, sea: boolean?)
			for _, pt in o.points do -- not on an egg spot (the Cliffs platforms too)
				if dist(x, z, pt.pos[1], pt.pos[3]) < 12 then
					return
				end
			end
			-- not in the updraft pillar; the same two
			-- random numbers as for the placed rock (the rotation, the shade) - the rest of the world layout does not shift
			if dist(x, z, WD.x, W.zones.Cliffs.z + WD.dz) < WD.size / 2 + WD.clear + h * 0.5 then
				local _ = gr()
				local _ = gr()
				return
			end
			table.insert(out, { kind = kind, x = x, z = z, y = y, yaw = gr() * 360, h = h, tint = math.floor(gr() * 1000), collide = true, granite = true, sea = sea })
		end
		local function range(r: { number }): number
			return r[1] + gr() * (r[2] - r[1])
		end
		local function angleSkipped(angleDeg: number, skips: { { number } }): boolean
			for _, rangeDeg in skips do
				if angleDeg >= rangeDeg[1] and angleDeg <= rangeDeg[2] then
					return true
				end
			end
			return false
		end
		-- the shore: at the water, half-grown into the beach (past the Springs channel mouth)
		for _ = 1, R.coast.count do
			local angle = gr() * 360
			if not angleSkipped(angle, W.edgeRocks.skipAngles) then
				local rad = Island.coastRadius(math.rad(angle)) * (R.coast.from + gr() * (R.coast.to - R.coast.from))
				local d = Layout.dir(angle)
				addRock(pick(gr, R.coast.kinds), d[1] * rad, d[3] * rad, nil, range(R.coast.height))
			end
		end
		-- the Cliffs ridge facade: rows of boulders along the facade, half in the rock; the egg platforms stay in front of them
		local C = I2.cliffs
		for i = 1, R.cliffs.count do
			local x = -C.halfWidth + gr() * C.halfWidth * 2
			local row = (i - 1) % R.cliffs.rows
			local h = range(R.cliffs.height)
			local zFace = C.zFace + C.faceNoise * Island.noise(x / 60 + 0.4)
			addRock(pick(gr, R.cliffs.kinds), x, zFace + 2 + gr() * 10, row * R.cliffs.rowStep + (gr() - 0.5) * R.cliffs.rowJitter - 2, h)
		end
		-- the back slope of the ridge (toward the sea): boulders by the terrain, so that a flat wall is not read from the water
		for _ = 1, R.cliffs.back do
			local x = -C.halfWidth + gr() * C.halfWidth * 2
			local z = C.zFace - C.depth - gr() * C.backSlope
			addRock(pick(gr, R.cliffs.kinds), x, z, nil, range(R.cliffs.backHeight))
		end
		-- the ridge ends - boulders by the terrain on both sides
		for side = -1, 1, 2 do
			for _ = 1, (R.cliffs.ends or 0) do
				local x = side * (C.halfWidth - 10 + gr() * (C.edgeSoft + 30))
				local z = C.zFace + 8 - gr() * (C.depth + C.backSlope)
				addRock(pick(gr, R.cliffs.kinds), x, z, nil, range(R.cliffs.backHeight) * 1.15)
			end
		end
		-- the facade cladding
		-- with big boulders on a grid (the phone draws the terrain in flat color, the meshes - with a texture). The boulder is sunk into the slope,
		-- outward by protrude of its height - the egg platforms stay in front of the wall. An own generator: the rest of the layout does not shift
		local CL = R.cliffs.clad
		if CL then
			local gc = Layout.rng2(CL.seed)
			local function faceZ(x: number, y: number): number? -- the z of the facade surface at height y (a bisection by Island.ridge)
				local zf = C.zFace + C.faceNoise * Island.noise(x / 60 + 0.4)
				local lo, hi = zf - C.faceWidth - 2, zf + 2
				if (Island.ridge(x, lo) or 0) < y then
					return nil
				end
				for _ = 1, 14 do
					local mid = (lo + hi) / 2
					if (Island.ridge(x, mid) or 0) >= y then
						lo = mid
					else
						hi = mid
					end
				end
				return lo
			end
			local x = -C.halfWidth - C.edgeSoft * 0.5
			while x <= C.halfWidth + C.edgeSoft * 0.5 do
				for _, row in CL.rows do
					local h = CL.height[1] + gc() * (CL.height[2] - CL.height[1])
					local xx = x + (gc() - 0.5) * CL.jitter
					local base = row + (gc() - 0.5) * CL.rowJitter
					local yaw = gc() * 360
					local kind = pick(gc, CL.kinds)
					local tint = math.floor(gc() * 1000)
					local zs = faceZ(xx, base + h * 0.5)
					if zs then
						table.insert(out, { kind = kind, x = xx, z = zs + h * (CL.protrude - 0.5), y = base, yaw = yaw, h = h, tint = tint, collide = true, granite = true })
					end
				end
				x += CL.step
			end
		end
		-- the terrace slope: past the stair sectors
		for _ = 1, R.terrace.count do
			local angle = gr() * 360
			local nearStairs = false
			for _, st in o.stairs do
				local da = math.abs(((angle - st.angleDeg + 180) % 360) - 180)
				if da < R.terrace.stairsClear then
					nearStairs = true
				end
			end
			if not nearStairs then
				local rad = R.terrace.rFrom + gr() * (R.terrace.rTo - R.terrace.rFrom)
				local d = Layout.dir(angle)
				local x, z = d[1] * rad, d[3] * rad
				local nearSign = false -- a rock of 11.5 stood on the Springs sign (r 200)
				for _, sg in o.signs do
					if dist(x, z, sg.pos[1], sg.pos[3]) < 14 then
						nearSign = true
					end
				end
				if offPaths(o, x, z, 2) and not nearSign then
					addRock(pick(gr, R.terrace.kinds), x, z, nil, range(R.terrace.height))
				end
			end
		end
		-- ledges on the slopes of the Summit peak (pass 1 C2: a smooth cone)
		local SC = W.zones.Summit.center
		for _ = 1, R.summit.count do
			local a = gr() * math.pi * 2
			local rad = R.summit.rFrom + gr() * (R.summit.rTo - R.summit.rFrom)
			local x, z = SC[1] + math.cos(a) * rad, SC[3] + math.sin(a) * rad
			local okPts = true
			for _, pt in o.points do
				if dist(x, z, pt.pos[1], pt.pos[3]) < 14 then
					okPts = false
				end
			end
			if okPts and offPaths(o, x, z, 4) then
				addRock(pick(gr, R.summit.kinds), x, z, nil, range(R.summit.height))
			end
		end
		-- the sea pillars: 3-4 boulders on top of each other from the bottom, pines on top (flight routes and the backdrop, craft/04 §7.10)
		local S = R.stacks
		local gs = Layout.rng2(R.seed + 7) -- a precise generator for the pillars (see Layout.rng2)
		local function rangeS(r: { number }): number
			return r[1] + gs() * (r[2] - r[1])
		end
		local placed = 0
		local tries = 0
		-- chains of chain pillars with a step of chainStep studs along the shore, the radius share is shared
		-- per chain with a spread of ±3 % (the pillars stand as an uneven ridge, like HTTYD series 14)
		local function oneStack(cx: number, cz: number)
			do
				local total = rangeS(S.total)
				local n = S.pieces[1] + math.floor(gs() * (S.pieces[2] - S.pieces[1] + 1))
				local piece = total / (1 + (n - 1) * S.overlap)
				local y = I2.beach.seabed + 2
				local topY = y
				for k = 1, n do
					local hk = piece * (1 - (S.taper or 0.1) * (k - 1))
					if k == 1 then -- a wide base, narrower pieces above (pass 1 C2: the pillars equally thin)
						addRock(pick(gs, S.baseKinds), cx + (gs() - 0.5) * S.jitter, cz + (gs() - 0.5) * S.jitter, y, hk * S.baseScale, true)
						y += hk * S.baseScale * S.overlap
						topY = y
						continue
					end
					addRock(pick(gs, S.kinds), cx + (gs() - 0.5) * S.jitter, cz + (gs() - 0.5) * S.jitter, y, hk, true)
					topY = y + hk * 0.92
					y += hk * S.overlap
				end
				-- snapDown - Decor lowers the pine onto the rock by a ray, otherwise to the pillar axis
				for _ = 1, 1 + math.floor(gs() * 2) do
					table.insert(out, { kind = pick(gs, S.pines), x = cx + (gs() - 0.5) * 8, z = cz + (gs() - 0.5) * 8, y = topY - 1.5, snapDown = true, ax = cx, az = cz, yaw = gs() * 360, h = rangeS(S.pineHeight), tint = math.floor(gs() * 1000), collide = false, sea = true })
				end
				placed += 1
			end
		end
		local chainN = S.chain or { 1, 1 }
		local stepR = S.chainStep or { 24, 24 }
		-- the chain centers evenly around the circle (the pillars around the whole shore, not in a heap) with a spread of ±chainJitter degrees
		local nChains = math.ceil(S.count / ((chainN[1] + chainN[2]) / 2))
		local chainIdx = 0
		while placed < S.count and tries < S.count * 5 do
			tries += 1
			local angle0 = ((chainIdx % nChains) + 0.5) * (360 / nChains) + (gs() - 0.5) * 2 * (S.chainJitter or 15)
			chainIdx += 1
			if not angleSkipped(angle0 % 360, S.skipAngles) then
				local f = S.from + gs() * (S.to - S.from)
				local n = chainN[1] + math.floor(gs() * (chainN[2] - chainN[1] + 1))
				local angle = angle0
				for _ = 1, n do
					if placed >= S.count or angleSkipped(angle, S.skipAngles) then
						break
					end
					local rad = Island.coastRadius(math.rad(angle)) * (f + (gs() - 0.5) * 0.06)
					local d = Layout.dir(angle)
					oneStack(d[1] * rad, d[3] * rad)
					angle += math.deg(rangeS(stepR) / math.max(rad, 1)) -- the step along the shore in degrees of arc
				end
			end
		end
	end
	-- C7: the glade giants and the landmark baobabs
	-- the old oak at the lagoon, the Frost Isle snow firs, the pier with a boat and the cattails in the Springs lagoon, the crystals in the ridge shade, the vines
	-- from the islets and the ridge, the camps with a campfire on the terrace wedges, the lamp posts along the paths. An own generator (D.c7.seed).
	do
		local C = D.c7
		if C then
			local gc = Layout.rng2(C.seed)
			local function addC(kind: string, x: number, z: number, y: number?, collide: boolean?, h: number?, yaw: number?, top: boolean?)
				local r = D.height[kind]
				assert(r, "no height for " .. kind)
				table.insert(out, { kind = kind, x = x, z = z, y = y, yaw = yaw or gc() * 360, h = h or (r[1] + gc() * (r[2] - r[1])), tint = math.floor(gc() * 1000), collide = collide, top = top })
			end
			local function farFrom(list: { { number } }, x: number, z: number, d: number): boolean
				for _, t in list do
					if dist(x, z, t[1], t[2]) < d then
						return false
					end
				end
				return true
			end
			local function nearPoint(x: number, z: number, d: number): boolean
				for _, p in o.points do
					if dist(x, z, p.pos[1], p.pos[3]) < d then
						return true
					end
				end
				return false
			end
			-- the glade giants (the baobabs - a ring at the terrace foot)
			for _, b in C.bigTrees do
				for _ = 1, b.count do
					for _ = 1, 25 do
						local x, z = spotMeadow(gc, o, b.margin, b.rMin, b.rMax)
						if x and z and farFrom(trees, x, z, b.spacing) then
							addC(b.kind, x, z, nil, true)
							table.insert(trees, { x, z })
							break
						end
					end
				end
			end
			for _, f in C.fixed do
				addC(f.kind, f.x, f.z, nil, true)
			end
			-- the snow firs: Frost Isle only, past the steep peak
			local ex = I2.extra and I2.extra[1]
			if ex and C.snowFirs then
				local SF = C.snowFirs
				local firs: { { number } } = {}
				local tries = 0
				while #firs < SF.count and tries < SF.count * 10 do
					tries += 1
					local a, r = gc() * math.pi * 2, math.sqrt(gc()) * ex.R0
					local x, z = ex.x + math.cos(a) * r, ex.z + math.sin(a) * r
					local okSpot = Island.extraLandFactor(ex, x, z) < I2.beach.start - 0.04
						and dist(x, z, ex.x + ex.peak.dx, ex.z + ex.peak.dz) > SF.peakClear
						and farFrom(firs, x, z, SF.spacing) and not nearPoint(x, z, 10)
					if okSpot then
						addC(SF.kind, x, z, nil, true)
						table.insert(firs, { x, z })
					end
				end
			end
			-- the pier into the Springs lagoon: h = the length, yaw = the direction from the shore to the water, y = the deck top
			local P = C.pier
			if P then
				local dx, dz = P.to[1] - P.from[1], P.to[2] - P.from[2]
				local len = math.sqrt(dx * dx + dz * dz)
				addC("cs_pier", (P.from[1] + P.to[1]) / 2, (P.from[2] + P.to[2]) / 2, (if W.springsMesh and W.springsMesh.enabled then SpringsShape.basins[1].water else I2.springs.waterLevel) + P.deck, false, len, math.deg(math.atan2(dz, dx)), true)
			end
			if C.boat then
				addC("cs_boat", C.boat.x, C.boat.z, (if W.springsMesh and W.springsMesh.enabled then SpringsShape.basins[1].water else I2.springs.waterLevel) - C.boat.sink, false)
			end
			-- the cattails along the rim of the lagoon circles (not in the water of the neighboring circle, not at the pier)
			local CT = C.cattails
			for _, L in I2.springs.lagoon do
				for _ = 1, math.floor(L.r * CT.perR) do
					local a = gc() * math.pi * 2
					local rr = L.r - CT.inset - gc() * CT.band
					local x, z = L.x + math.cos(a) * rr, L.z + math.sin(a) * rr
					local okSpot = not P or Layout.segDist(x, z, { P.from[1], 0, P.from[2] }, { P.to[1], 0, P.to[2] }) > 5
					for _, L2 in I2.springs.lagoon do
						if L2 ~= L and dist(x, z, L2.x, L2.z) < L2.r - 6 then
							okSpot = false
						end
					end
					if okSpot and not nearPoint(x, z, 6) then
						addC(pick(gc, CT.kinds), x, z)
					end
				end
			end
			-- the crystals in the shade of the Cliffs ridge (at the facade foot); lit - the share glowShare
			local cz = W.zones.Cliffs.z
			for _ = 1, C.crystals.count do
				for _ = 1, 20 do
					local x, z = -200 + gc() * 400, cz + 12 + gc() * 26
					if (free(o, x, z, 2) or z < -280) and offPaths(o, x, z, 3) and not nearPoint(x, z, 10) then
						addC(if gc() < C.crystals.glowShare then C.crystals.kinds[2] else C.crystals.kinds[1], x, z)
						break
					end
				end
			end
			-- the vines from the Cliffs ridge edge (the island vines - in the islands block)
			local SMG = W.springsMesh and W.springsMesh.enabled and W.springsMesh.gate
			if SMG then -- the rocks at the water curtain arch - the path goes into the arch between the rocks
				for _, r in SMG.rocks or {} do
					addC(r[1], r[2], r[3], nil, true, r[4], r[5])
				end
			end
			if C.bridge and W.zones.Springs.bridgeModel and not SMG then -- with the baths the crossing - the mesh stones
				local B2 = W.zones.Springs.bridge
				addC("cs_bridge", B2.x, B2.z, C.bridge.top, false, C.bridge.length, 0, true)
			end
			-- the Summit top - rocks along the edge and bushes in the center (y by the terrain; past the egg spots)
			local ST = C.summitTop
			if ST then
				local SC2 = W.zones.Summit.center
				for k = 1, ST.rocks + ST.bushes do
					for _ = 1, 10 do
						local isRock = k <= ST.rocks
						local R = if isRock then ST.rockR else ST.bushR
						local a, d = gc() * math.pi * 2, R[1] + gc() * (R[2] - R[1])
						local x, z = SC2[1] + math.cos(a) * d, SC2[3] + math.sin(a) * d
						if not nearPoint(x, z, 7) then
							addC(if isRock then pick(gc, { "ph_rock1_0", "ph_rock2_2", "ph_rock1_3" }) else pick(gc, { "under_shrub", "cs_bush", "under_fern" }), x, z, nil, isRock)
							break
						end
					end
				end
			end
			-- greenery and trees on the slopes of the Summit mountain (past the egg spots on the top)
			local SG = C.summitGreen
			if SG then
				local SC = W.zones.Summit.center
				for k = 1, SG.plants + SG.trees do
					for _ = 1, 12 do
						local a, d = gc() * math.pi * 2, SG.rFrom + gc() * (SG.rTo - SG.rFrom)
						local x, z = SC[1] + math.cos(a) * d, SC[3] + math.sin(a) * d
						if not nearPoint(x, z, 12) and offPaths(o, x, z, 2) then
							if k <= SG.trees then
								addC(pick(gc, SG.treeKinds), x, z, nil, true) -- the height by the kind table
							else
								addC(pick(gc, SG.plantKinds), x, z)
							end
							break
						end
					end
				end
			end
			-- silhouettes on the horizon - tall rock pillars of 3 rocks with pines, past Frost Isle
			local BD = C.backdrop
			if BD then
				local placedB = 0
				for k = 1, BD.count * 3 do
					if placedB >= BD.count then
						break
					end
					local angle = (k - 1) * (360 / BD.count) + 20 + gc() * 18
					local da = math.abs(((angle + 180) % 360) - 180)
					if da > BD.skipDeg then
						local d = Layout.dir(angle)
						local rad = BD.rMin + gc() * (BD.rMax - BD.rMin)
						local bx, bz = d[1] * rad, d[3] * rad
						local w = BD.base[1] + gc() * (BD.base[2] - BD.base[1])
						local y = I2.beach.seabed
						for p = 1, 3 do
							local hp = w * (if p == 1 then 1.0 elseif p == 2 then 0.85 else 0.7)
							table.insert(out, { kind = pick(gc, BD.kinds), x = bx + (gc() - 0.5) * w * 0.15, z = bz + (gc() - 0.5) * w * 0.15, y = y, yaw = gc() * 360, h = hp, tint = 0, collide = false, granite = true, sea = true, widthTo = w * (1.1 - p * 0.2) })
							y += hp * 0.78
						end
						for _ = 1, 2 + math.floor(gc() * 2) do -- the spread within the top rock + snapDown onto the rock
							table.insert(out, { kind = pick(gc, BD.pines), x = bx + (gc() - 0.5) * w * 0.24, z = bz + (gc() - 0.5) * w * 0.24, y = y + 2, snapDown = true, ax = bx, az = bz, yaw = gc() * 360, h = 34 + gc() * 18, tint = math.floor(gc() * 1000), collide = false, sea = true })
						end
						placedB += 1
					end
				end
				-- 2 silhouette islands - a ridge of pieces rocks across the ray, higher in the middle, pines on top
				local IS = BD.isles
				if IS then
					for i = 1, IS.count do
						local angle = IS.angles[((i - 1) % #IS.angles) + 1] + (gc() - 0.5) * 10
						local d = Layout.dir(angle)
						local rad = IS.rMin + gc() * (IS.rMax - IS.rMin)
						local cx, cz = d[1] * rad, d[3] * rad
						local w = IS.base[1] + gc() * (IS.base[2] - IS.base[1])
						local tx, tz = -d[3], d[1] -- across the ray (the ridge is seen from the island by its wide side)
						local n = IS.pieces
						for p = 1, n do
							local u = (p - (n + 1) / 2) / ((n - 1) / 2) -- -1..1
							local wp = w * (0.55 + 0.45 * (1 - u * u))
							local hp = w * (0.18 + 0.15 * (1 - u * u)) * (0.9 + gc() * 0.2) -- the ridge 40-116 studs (test: the sea granite up to 120)
							local px = cx + tx * u * w * 0.75 + (gc() - 0.5) * w * 0.1
							local pz = cz + tz * u * w * 0.75 + (gc() - 0.5) * w * 0.1
							table.insert(out, { kind = pick(gc, BD.kinds), x = px, z = pz, y = I2.beach.seabed, yaw = angle + 90 + (gc() - 0.5) * 30, h = hp, tint = 0, collide = false, granite = true, sea = true, widthTo = wp })
							for _ = 1, math.max(1, math.floor(IS.pines / n + gc())) do
								table.insert(out, { kind = pick(gc, BD.pines), x = px + (gc() - 0.5) * wp * 0.3, z = pz + (gc() - 0.5) * wp * 0.3, y = I2.beach.seabed + hp * 0.78, snapDown = true, ax = px, az = pz, yaw = gc() * 360, h = 36 + gc() * 20, tint = math.floor(gc() * 1000), collide = false, sea = true })
							end
						end
					end
				end
			end
			-- the banks of the Springs brook - cattails, ferns, pebbles (past the bridge)
			local CB = C.creekBanks
			if CB then
				local ch = I2.springs.channel
				local bz = W.zones.Springs.bridge.z
				local zz = ch.z1 + 6
				while zz < ch.z2 - 6 do
					if math.abs(zz - bz) > 16 then
						for side = -1, 1, 2 do
							local x = Island.channelX(zz) + side * (Island.channelHalf(zz) + 1.2 + gc() * 2.5)
							local roll = gc()
							local kind = if roll < 0.7 then "cs_cattail" elseif roll < 0.85 then "under_fern" else "ph_rock1_2"
							addC(kind, x, zz + (gc() - 0.5) * 4, nil, false)
						end
					end
					zz += CB.step
				end
			end
			local CL = I2.cliffs
			for _ = 1, C.vines.cliffs do
				for _ = 1, 20 do -- past the egg platforms on the facade (y 40-60)
					local x = -CL.halfWidth * 0.8 + gc() * CL.halfWidth * 1.6
					local zFace = CL.zFace + CL.faceNoise * Island.noise(x / 60 + 0.4)
					if not nearPoint(x, zFace, 14) then
						local h = 18 + gc() * 8
						addC("cs_vines", x, zFace + 2.5, CL.height - h + 1, false, h, 0)
						break
					end
				end
			end
			-- the camps on the terrace wedges: a campfire, a woodpile, 2 stumps; the wedge garden around is cleared
			local n = W.nests
			for i = 1, n.count do
				local angle = (i - 1) * n.angleStep + n.angleStep / 2
				local d, pp = Layout.dir(angle), Layout.dir(angle + 90)
				local fx = d[1] * C.camp.r + pp[1] * C.camp.across
				local fz = d[3] * C.camp.r + pp[3] * C.camp.across
				for j = #out, 1, -1 do
					local it = out[j]
					if it.y == W.terrace.y and dist(it.x, it.z, fx, fz) < C.camp.clear then
						table.remove(out, j)
					end
				end
				addC("cs_campfire", fx, fz, W.terrace.y, false)
				addC("cs_logstack", fx + d[1] * 6 + pp[1] * 4, fz + d[3] * 6 + pp[3] * 4, W.terrace.y, true, nil, angle + 90)
				for k = 1, 2 do
					local a = math.rad(angle + 150 + k * 70)
					addC(if k == 1 then "cs_stump" else "cs_stump2", fx + math.cos(a) * 4.5, fz - math.sin(a) * 4.5, W.terrace.y, true, 1.6 + gc() * 0.4)
				end
			end
			-- the lamp posts along the paths, alternating on both sides
			local placedL = 0
			for _, pa in o.paths do
				local dx, dz = pa.to[1] - pa.from[1], pa.to[3] - pa.from[3]
				local len = math.sqrt(dx * dx + dz * dz)
				local t, side = C.lights.step / 2, 1
				while t < len - 8 and placedL < C.lights.max do
					local nx, nz = -dz / len, dx / len
					local off = W.paths.width / 2 + C.lights.offset
					local x = pa.from[1] + dx / len * t + nx * off * side
					local z = pa.from[3] + dz / len * t + nz * off * side
					if free(o, x, z, 0) then
						addC("cs_streetlight", x, z, nil, true)
						placedL += 1
					end
					side, t = -side, t + C.lights.step
				end
			end
		end
	end
	-- a rock out of the sea under the Frost Isle sign (Config.World.gates.frost.sign; without the generator - the layout does not shift)
	local FS = W.gates and W.gates.frost and W.gates.frost.sign
	if FS then
		local sx = W.frostIsle.wallX - FS.back
		for i, r in FS.rocks do
			table.insert(out, { kind = r[4], x = sx + r[1], z = r[2], y = FS.rockY, yaw = r[5], h = r[3], tint = i, collide = true })
		end
	end
	return out
end

-- All the mesh kinds the layout uses (to check that each has an asset id and a height)
function DecorLayout.kinds(): { string }
	local seen: { [string]: boolean } = {}
	local out = {}
	for _, it in DecorLayout.items() do
		if not seen[it.kind] then
			seen[it.kind] = true
			table.insert(out, it.kind)
		end
	end
	table.sort(out)
	return out
end

-- LeafyGrass patches on the glade (the terrain material variety)
function DecorLayout.leafyPatches(): { { x: number, z: number, r: number } }
	local L = W.leafyPatches
	local g = Layout.rng2(L.seed)
	local o = obstacles()
	local out = {}
	local tries = 0
	while #out < L.count and tries < 200 do
		tries += 1
		local x, z = spotMeadow(g, o, 0)
		if x and z then
			table.insert(out, { x = x, z = z, r = L.radius[1] + g() * (L.radius[2] - L.radius[1]) })
		end
	end
	return out
end

return DecorLayout
