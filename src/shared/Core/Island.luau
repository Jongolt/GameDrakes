--!strict
-- Island 2.0 (C2; spec 04 addenda 1.8, 2.0, 2.1): the land shape and the terrain height by pure math, without
-- Roblox API (checked by the luau CLI tests). Not a single regular figure: the shore by a noisy polar outline, the beach, the terrace
-- plateau with gentle slopes and cutouts for the stairs, the Cliffs ridge with an uneven top, the Summit peak with shoulders, the Springs area
-- with a lagoon and a channel. WorldBuilder writes the terrain in WriteVoxels chunks by Island.height, Decor places items by the same height.
-- All the numbers - Config.World.island2. The angle of a point (x, z): theta = atan2(-z, x), like Layout.dir (0 = east, 90 = north).

local Config = require("./../Config")
local PlazaShape = require("./PlazaShape") -- the outline of the Old Ash clay glade
local SpringsShape = require("./SpringsShape") -- the hill and the Springs bath bowls

local Island = {}

local W = Config.World
local I = W.island2

export type Hill = { x: number, z: number, r: number, h: number }

local function smoothstep(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end
Island.smoothstep = smoothstep

local function dist(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- noise by angle: a sum of harmonics with phases from seed (deterministic), the result in [-1, 1]
local phases: { number } = {}
do
	local state = I.noiseSeed % 2147483648
	for _ = 1, #I.harmonics do
		state = (state * 1103515245 + 12345) % 2147483648
		table.insert(phases, state / 2147483648 * math.pi * 2)
	end
end
local ampSum = 0
for _, k in I.harmonics do
	ampSum += 1 / k
end

function Island.noise(theta: number): number
	local s = 0
	for i, k in I.harmonics do
		s += math.sin(k * theta + phases[i]) / k
	end
	return s / ampSum
end

-- noise with its own phases (the zone islands, C3)
local phaseCache: { [number]: { number } } = {}
local function phasesFor(seed: number): { number }
	local ph = phaseCache[seed]
	if ph then
		return ph
	end
	ph = {}
	local state = seed % 2147483648
	for _ = 1, #I.harmonics do
		state = (state * 1103515245 + 12345) % 2147483648
		table.insert(ph, state / 2147483648 * math.pi * 2)
	end
	phaseCache[seed] = ph
	return ph
end
function Island.noiseSeeded(seed: number, theta: number): number
	local ph = phasesFor(seed)
	local s = 0
	for i, k in I.harmonics do
		s += math.sin(k * theta + ph[i]) / k
	end
	return s / ampSum
end

-- the zone islands (C3): a share of the shore radius, the same beach profile; hills by the island seed; a peak with noise
local extraHills: { [string]: { Hill } } = {}
local function extraHillsFor(ex: any): { Hill }
	local hs = extraHills[ex.id]
	if hs then
		return hs
	end
	hs = {}
	local H = ex.hills
	local state = H.seed % 2147483648
	local function g(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	local tries = 0
	while #hs < H.count and tries < 400 do
		tries += 1
		local a = g() * math.pi * 2
		local rad = g() * ex.R0 * 0.8
		local x, z = ex.x + math.cos(a) * rad, ex.z + math.sin(a) * rad
		local r = H.radius[1] + g() * (H.radius[2] - H.radius[1])
		local h = H.height[1] + g() * (H.height[2] - H.height[1])
		local ok = true
		for _, o in hs do
			if dist(x, z, o.x, o.z) < r + o.r - 8 then
				ok = false
			end
		end
		if ok then
			table.insert(hs, { x = x, z = z, r = r, h = h })
		end
	end
	extraHills[ex.id] = hs
	return hs
end

function Island.extraLandFactor(ex: any, x: number, z: number): number
	local dx, dz = x - ex.x, z - ex.z
	local r = math.sqrt(dx * dx + dz * dz)
	return r / (ex.R0 * (1 + ex.noiseAmp * Island.noiseSeeded(ex.noiseSeed, math.atan2(-dz, dx))))
end

-- the height of a zone island at a point (nil = the point is outside its influence)
function Island.extraHeight(ex: any, x: number, z: number): number?
	local d = Island.extraLandFactor(ex, x, z)
	local B = I.beach
	if d > B.seabedAt then
		return nil
	end
	local h
	if d <= B.start then
		h = 0
	elseif d <= 1 then
		h = B.depth * (d - B.start) / (1 - B.start)
	else
		h = B.depth + (B.seabed - B.depth) * smoothstep((d - 1) / (B.seabedAt - 1))
	end
	if h >= 0 then
		local hh = 0
		for _, hl in extraHillsFor(ex) do
			local dd = dist(x, z, hl.x, hl.z)
			if dd < hl.r then
				hh = math.max(hh, hl.h * 0.5 * (1 + math.cos(math.pi * dd / hl.r)))
			end
		end
		h += hh
		local P = ex.peak
		if P then
			local pr = dist(x, z, ex.x + P.dx, ex.z + P.dz)
			if pr < P.baseRadius then
				local t = math.clamp((pr - P.topRadius) / (P.baseRadius - P.topRadius), 0, 1)
				local ph = P.top * (1 - t) ^ P.concave
				if pr > P.topRadius then
					ph += P.noise * Island.noiseSeeded(ex.noiseSeed + 7, math.atan2(-(z - ex.z - P.dz), x - ex.x - P.dx) * 3 + pr / 20) * math.min(1, (pr - P.topRadius) / 20) * math.clamp(ph / 40, 0, 1)
				end
				h = math.max(h, ph)
			end
		end
	end
	return h
end

-- which zone island covers the point (for the material)
function Island.extraAt(x: number, z: number): any?
	for _, ex in I.extra or {} do
		if Island.extraLandFactor(ex, x, z) <= I.beach.seabedAt then
			return ex
		end
	end
	return nil
end

-- the land radius in direction theta (radians)
function Island.coastRadius(theta: number): number
	return I.R0 * (1 + I.noiseAmp * Island.noise(theta))
end

function Island.thetaOf(x: number, z: number): number
	return math.atan2(-z, x)
end

-- the share of the land radius: < 1 land, 1 the shoreline, > 1 the sea
function Island.landFactor(x: number, z: number): number
	local r = math.sqrt(x * x + z * z)
	return r / Island.coastRadius(math.atan2(-z, x))
end

function Island.onLand(x: number, z: number, margin: number?): boolean
	local r = math.sqrt(x * x + z * z)
	return r <= Island.coastRadius(math.atan2(-z, x)) - (margin or 0)
end

-- the base profile: the glade 0, the beach gently down to beach.depth at the shoreline, then the bottom down to seabed
function Island.baseHeight(x: number, z: number): number
	local d = Island.landFactor(x, z)
	local B = I.beach
	if d <= B.start then
		return 0
	end
	if d <= 1 then
		return B.depth * (d - B.start) / (1 - B.start)
	end
	if d <= B.seabedAt then
		return B.depth + (B.seabed - B.depth) * smoothstep((d - 1) / (B.seabedAt - 1))
	end
	return B.seabed
end

-- the glade hills (cosine humps, like Layout.groundHeight)
local function hillsHeight(hills: { Hill }, x: number, z: number): number
	local best = 0
	for _, h in hills do
		local dx, dz = x - h.x, z - h.z
		if math.abs(dx) < h.r and math.abs(dz) < h.r then
			local d = math.sqrt(dx * dx + dz * dz)
			if d < h.r then
				best = math.max(best, h.h * 0.5 * (1 + math.cos(math.pi * d / h.r)))
			end
		end
	end
	return best
end

-- the terrace plateau: inside r <= radius + rimInner the height wallTop (the top is covered by the plaza and petal parts), the grass rim up to
-- radius + outset, then a gentle slope of width slopeWidth with a jittering start; in the sector of every stair - the step profile
local stairsAngles: { number } = {}
for i = 1, W.nests.count do
	table.insert(stairsAngles, (i - 1) * W.nests.angleStep + W.nests.angleStep / 2)
end

function Island.plateau(x: number, z: number): number?
	local T = I.terrace
	local TR = W.terraceTerrain
	local r = math.sqrt(x * x + z * z)
	local rIn = W.terrace.radius + TR.rimInner
	local rRim = W.terrace.radius + TR.outset
	local top = TR.wallTop + TR.capHeight
	if r > rRim + T.slopeWidth + T.noise + 2 then
		return nil
	end
	if TR.plazaSink and r <= W.plaza.radius - TR.plazaSink.inset then -- under the plaza stone the terrain is lower (no layer flush with it)
		return TR.wallTop - TR.plazaSink.depth
	end
	if r <= rIn then
		return TR.wallTop
	end
	local thetaDeg = math.deg(math.atan2(-z, x)) % 360
	local halfSector = math.deg(math.atan((W.stairs.width / 2 + T.stairsMargin) / math.max(r, 1)))
	for _, a in stairsAngles do
		local da = math.abs(((thetaDeg - a + 180) % 360) - 180)
		if da < halfSector then
			local run = W.terrace.y / math.tan(math.rad(W.stairs.slopeDeg))
			local t = (r - W.terrace.radius) / run
			return math.max(0, W.terrace.y * (1 - t) - T.stairsSink)
		end
	end
	if r <= rRim then
		return top
	end
	local theta = math.atan2(-z, x)
	local edge = rRim + T.noise * 0.5 * (1 + Island.noise(theta * 2 + 0.9))
	if r <= edge then
		return top
	end
	return top * (1 - smoothstep((r - edge) / T.slopeWidth))
end

-- the Cliffs ridge: a steep facade at zFace (with jitter along x), an uneven top, soft ends, a descent to the sea behind the ridge
function Island.ridge(x: number, z: number): number?
	local C = I.cliffs
	local ax = math.abs(x)
	if ax > C.halfWidth + C.edgeSoft then
		return nil
	end
	local zFace = C.zFace + C.faceNoise * Island.noise(x / 60 + 0.4)
	if z > zFace + 2 then
		return nil
	end
	local e = smoothstep((C.halfWidth + C.edgeSoft - ax) / C.edgeSoft)
	local H = (C.height + C.topNoise * Island.noise(x / 45 + 2.1)) * e
	local h = H * smoothstep((zFace - z) / C.faceWidth)
	local back = C.zFace - C.depth
	if z < back then
		h *= 1 - smoothstep((back - z) / C.backSlope)
	end
	-- beyond the shoreline the ridge drops into the water
	local lf = Island.landFactor(x, z)
	if lf > 0.97 then
		h *= 1 - smoothstep((lf - 0.97) / 0.06)
		if h < 1 then
			return nil
		end
	end
	return h
end

-- the Summit peak: a flat top topRadius at height top, a cone down to baseRadius, shoulder cones with an offset, noise on the slopes
function Island.summit(x: number, z: number): number?
	local S = I.summit
	local c = W.zones.Summit.center
	local dx, dz = x - c[1], z - c[3]
	local r = math.sqrt(dx * dx + dz * dz)
	local h = 0
	if r < S.baseRadius then
		local t = math.clamp((r - S.topRadius) / (S.baseRadius - S.topRadius), 0, 1)
		h = S.top * (1 - t) ^ S.concave
	end
	for _, sh in S.shoulders do
		local rr = dist(x, z, c[1] + sh.dx, c[3] + sh.dz)
		if rr < sh.r then
			h = math.max(h, sh.h * (1 - rr / sh.r) ^ 1.2)
		end
	end
	if h <= 0 then
		return nil
	end
	if r > S.topRadius then
		-- an uneven peak (pass 1 C2: the even cone read as a "truncated cone"): noise by angle and radius + terrace ledges
		local k = math.min(1, (r - S.topRadius) / 20) * math.clamp(h / S.noiseFullAt, 0, 1) -- at the foot the noise fades (the path to meadow_8)
		local theta = math.atan2(-dz, dx)
		h += S.noise * (Island.noise(theta * 2 + r / 25) + 0.6 * Island.noise(theta * 5 + 1.3 + r / 40)) * k
		if S.ledge > 0 then -- the ledges: the phase jitters by angle so the steps are not concentric (pass 3 C2: "a wedding cake")
			local phase = S.ledgePhase * Island.noise(theta * 3 + 0.7)
			h -= S.ledge * 0.5 * (1 - math.cos(2 * math.pi * (h + phase) / S.ledgePeriod)) * k
		end
		h = math.max(h, 0)
	end
	return h
end

-- the Springs area (y = springs.y) with a soft edge, a lagoon of several circles (the water waterLevel) and a channel to the glade (the water 0).
-- Returns the height and the water level (nil = no water) or nil outside the area and the channel.
-- the channel axis with bends - a brook; straight at the bridge (fade), a variable width
function Island.channelX(z: number): number
	local ch = I.springs.channel
	local m = ch.meander
	if not m then
		return ch.x
	end
	local fade = smoothstep((math.abs(z - W.zones.Springs.bridge.z) - m.straight) / m.fadeLen)
	local u = (z - ch.z1) / m.period * math.pi * 2
	return ch.x + m.amp * fade * (math.sin(u) + 0.35 * math.sin(u * 2.65 + 1.1))
end

function Island.channelHalf(z: number): number
	local ch = I.springs.channel
	local m = ch.meander
	if not m then
		return ch.half
	end
	return ch.half * (1 + m.widthVar * math.sin(z / 53 + 1.3))
end

function Island.springs(x: number, z: number): (number?, number?)
	local S = I.springs
	local ch = S.channel
	if z >= ch.z1 and z <= ch.z2 then
		local cx, hh = Island.channelX(z), Island.channelHalf(z)
		local dd = math.abs(x - cx)
		if dd <= hh + ch.rim then
			if dd <= hh then
				return ch.depth, ch.waterLevel
			end
			return ch.depth + (0 - ch.depth) * smoothstep((dd - hh) / ch.rim), nil
		end
	end
	local b = S.box
	if x < b.x1 or x > b.x2 or z < b.z1 or z > b.z2 then
		return nil, nil
	end
	local edge = math.min(x - b.x1, b.x2 - x, z - b.z1, b.z2 - z)
	if S.edgeNoise then -- the area edge is uneven, not a rectangle
		edge += S.edgeNoise * Island.noiseSeeded(77, math.atan2(z - (b.z1 + b.z2) / 2, x - (b.x1 + b.x2) / 2)) -- noise in -1..1
	end
	local base = S.y * smoothstep(edge / S.edgeSoft)
	local SM = W.springsMesh
	if SM and SM.enabled then
		-- the hill under the bath cascade; under the bowl bottoms a pit (the bottom and the rim are the mesh), no terrain water - the bowl water is a part
		local h = base + SpringsShape.hill(x, z)
		local bsn = SpringsShape.basinAt(x, z, 0)
		if bsn then
			local dx, dz = x - bsn.x, z - bsn.z
			local rin = SpringsShape.rin(bsn, math.deg(math.atan2(-dz, dx)))
			local pit = bsn.floor - 4 -- the terrain is drawn ~2 above the computation (a pitfall): the pit at 4 - the surface 2 under the bottom
			local t = math.clamp((math.sqrt(dx * dx + dz * dz) - rin) / SpringsShape.lip, 0, 1)
			h = math.min(h, pit + (h - pit) * t)
		end
		-- the chute under the spillway: the terrain is drawn ~2 above the computation and hid the water ribbon going from the rim to the lower bowl along
		-- the slope; along the segment the spillway is lowered by chute below the straight line "top - bottom" (toward the chute edges - down to zero)
		for _, c in SpringsShape.cascades do
			local ax, az, bx, bz = c.top[1], c.top[3], c.bottom[1], c.bottom[3]
			local dx, dz = bx - ax, bz - az
			local t = ((x - ax) * dx + (z - az) * dz) / math.max(dx * dx + dz * dz, 1e-6)
			if t > -0.05 and t < 1.05 then
				local tc = math.clamp(t, 0, 1)
				local d = dist(x, z, ax + tc * dx, az + tc * dz)
				local half = c.width * 0.6
				if d < half then
					local ly = c.top[2] + (c.bottom[2] - c.top[2]) * tc
					local k = 1 - smoothstep((d - half * 0.55) / (half * 0.45))
					h = math.min(h, ly - (SM.chute or 2.8) * k + 99 * (1 - k))
				end
			end
		end
		return h, nil
	end
	local best, wl = base, nil
	for _, L in S.lagoon do
		local d = dist(x, z, L.x, L.z)
		if d < L.r then
			local hh = base + (S.lagoonDepth - base) * smoothstep((L.r - d) / S.lagoonRim)
			if hh < best then
				best = hh
			end
			if hh < S.waterLevel then
				wl = S.waterLevel
			end
		end
	end
	return best, wl
end

-- the final surface height and the water level above it (nil = land without water)
function Island.height(hills: { Hill }, x: number, z: number): (number, number?)
	local sh, swl = Island.springs(x, z)
	if sh then
		return sh, swl
	end
	local base = Island.baseHeight(x, z)
	local h = base
	if base >= 0 then
		h = base + hillsHeight(hills, x, z)
	end
	local p = Island.plateau(x, z)
	if p and p > h then
		h = p
	end
	local rg = Island.ridge(x, z)
	if rg and rg > h then
		h = rg
	end
	local s = Island.summit(x, z)
	if s and s > h then
		h = s
	end
	for _, ex in I.extra or {} do -- C3: the zone islands
		local eh = Island.extraHeight(ex, x, z)
		if eh and eh > h then
			h = eh
		end
	end
	return h, if h < I.seaLevel then I.seaLevel else nil
end

-- the top layer material: the lagoon/sea bottom sand (pebbles), a steep slope stone (granite), the top ground, Springs pebbles,
-- the beach pebbles, otherwise grass
function Island.material(x: number, z: number, h: number, slope: number, wl: number?): string
	local ex = Island.extraAt(x, z)
	if ex then -- C3: a zone island (Frost Isle: snow, ice on the steep, snow on the beach)
		if wl ~= nil and h < wl then
			return ex.beach
		end
		if slope > I.rockSlope then
			return ex.steep
		end
		return ex.top
	end
	if wl ~= nil and h < wl then
		return "Sand"
	end
	if slope > I.rockSlope then
		return I.steepMaterial or "Limestone" -- Rock (Limestone on the phone - smooth gray "concrete")
	end
	if I.nestGround then -- the nest petal rectangles on the terrace - a different cover, without Decoration grass
		local PM = W.plazaMesh
		if PM and PM.enabled then
			if PlazaShape.inside(x, z, PM.grassIn) then -- under the clay without grass; at the rim the grass grows through the edge
				return I.nestGround
			end
		elseif I.plazaGroundMargin and x * x + z * z <= (W.plaza.radius + I.plazaGroundMargin) ^ 2 then -- and the plaza circle
			return I.nestGround
		end
		local N = W.nests
		for i = 1, N.count do
			local a = math.rad((i - 1) * N.angleStep)
			local dx, dz = math.cos(a), -math.sin(a)
			local along = x * dx + z * dz
			local across = math.abs(-x * dz + z * dx)
			if along >= N.rInner and along <= N.rOuter and across <= N.lotWidth / 2 then
				return I.nestGround
			end
		end
	end
	local c = W.zones.Summit.center
	if h > I.summit.top - 8 and dist(x, z, c[1], c[3]) < I.summit.topRadius + 6 then
		return I.summit.topMaterial or "Ground" -- grass (dark ground reads as a flat black circle)
	end
	local SP = I.springs
	local b = SP.box
	local SMM = W.springsMesh
	if SMM and SMM.enabled and SMM.apron and x >= b.x1 and x <= b.x2 and z >= b.z1 and z <= b.z2 then
		-- white travertine (Salt) around the bowls and as spillway paths between them - "a white staircase" visible from afar
		if SpringsShape.basinAt(x, z, SMM.apron.around) then
			return "Salt"
		end
		for _, c in SpringsShape.cascades do
			local ax, az, bx, bz = c.top[1], c.top[3], c.bottom[1], c.bottom[3]
			local dx, dz = bx - ax, bz - az
			local t = math.clamp(((x - ax) * dx + (z - az) * dz) / math.max(dx * dx + dz * dz, 1e-6), 0, 1)
			if dist(x, z, ax + t * dx, az + t * dz) < c.width * SMM.apron.flow then
				return "Salt"
			end
		end
	end
	if x >= b.x1 and x <= b.x2 and z >= b.z1 and z <= b.z2 then
		-- pebbles only at the water of the lagoon and the channel, grass beyond (pass 1 C2: the whole area read as a gray parking lot)
		local SM = W.springsMesh
		local sandNear = if SM and SM.enabled then SM.sandNear or SP.sandNear else SP.sandNear -- the bath hill - grass
		-- at the brook pebbles only in a narrow strip at the water
		local near = math.abs(x - Island.channelX(z)) - Island.channelHalf(z) < sandNear
		for _, L in SP.lagoon do
			if dist(x, z, L.x, L.z) - L.r < sandNear then
				near = true
			end
		end
		return if near then "Sand" else "Grass"
	end
	if Island.landFactor(x, z) > I.beach.sandFrom then
		return "Sand"
	end
	return "Grass"
end

-- the chunks for WriteVoxels: squares chunk x chunk covering the land with a margin
local function gridChunks(cx: number, cz: number, half: number, out: { any })
	local n = math.ceil(half * 2 / I.chunk)
	local sx, sz = cx - n * I.chunk / 2, cz - n * I.chunk / 2
	for ix = 0, n - 1 do
		for iz = 0, n - 1 do
			table.insert(out, { x1 = sx + ix * I.chunk, z1 = sz + iz * I.chunk, x2 = sx + (ix + 1) * I.chunk, z2 = sz + (iz + 1) * I.chunk })
		end
	end
end

function Island.chunks(): { { x1: number, z1: number, x2: number, z2: number } }
	local out = {}
	gridChunks(0, 0, I.R0 * (1 + I.noiseAmp) + I.margin, out)
	for _, ex in I.extra or {} do -- C3: the grid of every zone island (does not intersect the main one: the strait >= 300)
		gridChunks(ex.x, ex.z, ex.R0 * (1 + ex.noiseAmp) * I.beach.seabedAt + I.margin, out)
	end
	return out
end

return Island
