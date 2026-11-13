--!strict
-- THE GLOWING EGG: the first day - a regular dragon from a regular egg; then find and STEAL the coveted egg; the glowing dragon hatches the next day.
-- After the first flight (onboarding.flew) - a personal egg in a golden nest. Took it - the egg in hand (data.eggs.carry with glow).
-- At home (the own lot) - the egg onto the pedestal by the nest (it takes no bowl) with a timer, readyAt = in hatchHours h.
-- Ready and the owner at home with a free bowl - the egg into the bowl (Incubation, hatchSeconds), a hatch as usual -> a glow dragon ->
-- the Glow attribute -> Controllers/Glow. One at a time: data.glowEgg = { taken, readyAt, hatched, n }; a series by element (n, Core/GlowSeries).
-- There is no guard fight. A PACK sleeps at the golden nest (Combat.placePack), approaching does not wake it;
-- took the egg - the pack wakes and chases (Combat.wakePack, the speed by attempt); caught - the egg flies in an arc back into the nest (it stands
-- empty while the egg is in hand), the pack sleeps again, take again - once it lay down and the thief walked away; at home - the egg onto the pedestal. THE RAID ON FOOT: outside
-- the own lot near the nest (or with the egg) riding is not allowed - dismount; the own dragon waits at the lot gate (the GlowWait attribute - the client
-- Companion). The egg left the hands not at home (a reset, debugging) - back into the nest.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Core = Shared:WaitForChild("Core")
local Layout = require(Core:WaitForChild("Layout"))
local Zones = require(Core:WaitForChild("Zones"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local GlowSeries = require(Core:WaitForChild("GlowSeries")) -- golden eggs as a series by element
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))

local GlowEgg = {}

local GE = Config.Glow and Config.Glow.egg
local services: { [string]: any } = {}
local eggs: { [Player]: Model } = {}
local pedestals: { [Player]: Model } = {}
local guarded: { [Player]: boolean } = {} -- the guards were placed in this visit (their disappearance = a win or leaving)
local unlocked: { [Player]: boolean } = {}
local announced: { [Player]: boolean } = {}
local returnAt: { [Player]: number } = {} -- os.clock() when the caught egg lands back in the nest
-- the returned egg can be taken again only once the thief walked farther than pick + 6 from the nest (standing nearby - the server in the
-- same tick handed the egg over again, and "CAUGHT" went in a loop every 2.5 s)
local rearm: { [Player]: boolean } = {}
local rearmAt: { [Player]: number } = {} -- when the rearm was set (removed after GE.rearmSeconds)
-- after dismounting at the nest the egg is handed over only when the player himself stepped toward it
-- (settleStep studs horizontally from the dismount point) or walked farther than pick+6; not lifted by time (otherwise a player who lands
-- at the nest takes the egg by himself and gets caught standing)
local settle: { [Player]: { at: Vector3, t: number, toasted: boolean? } } = {}
local tries: { [Player]: number } = {} -- captures in this visit - the pack is slower with each one (Config.Glow.egg.chase.share)
-- the gate of the own lot by the nest - S (the path entry point at the lot edge), W (where the dragon waits), the lot edge
-- A-B (the SAFE line); nestAt - where the golden nest stands (also after the taking, until the egg is home)
local gates: { [Player]: { S: Vector3, O: Vector3, A: Vector3, B: Vector3, W: Vector3, Pd: Vector3 } } = {}
local nestAt: { [Player]: Vector3 } = {}
local raidOn: { [Player]: boolean } = {}
-- the golden nest on the slope, steal only on foot - a raid like on rings 1-2 (Services/Raid): dPoints - point D where the dragon waits (35 toward home); safeAt - the thief reached the dragon and mounted (SAFE!),
-- then home by air, the pedestal at the lot. The mode - Config.Glow.egg.raid.safe == "dragon"
local dPoints: { [Player]: Vector3 } = {}
local safeAt: { [Player]: boolean } = {}
local function dragonMode(): boolean
	return GE.raid.safe == "dragon"
end
-- under the golden nest a clearing without grass
-- (Grass -> LeafyGrass), the original voxels - back when the nest is removed
local clearings: { [Model]: { region: Region3, mats: any, occ: any } } = {}
local folder: Folder? = nil

local function root(p: Player): BasePart?
	local ch = p.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

-- the golden nest - ON THE GROUND, on the meadow, a trip from the own nest (distance studs). The spot is found by MEASUREMENT - rings around the meadow points, flat terrain ground (8 rays at
-- radius flatR, a drop no more than flatMax), not water, no rock or decor around (clearR), no closer than eggGap to any egg spot, no closer than 30 to a foreign
-- golden nest; among the suitable - flatter and closer to the middle of distance. None - the old spot by the egg spot
local function groundHit(x: number, z: number): RaycastResult?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	for _, n in { "GlowEggs", "Gloom" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(skip, pl.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	return workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
end

-- the site: a point on the ground (the meadow terrain; on the plaza - the slab floor mesh, floorOk), not water, the height drop around the circle, whether it is empty around
-- (floor parts hit by the rays are not an obstacle)
local function probeSpot(x: number, z: number, floorOk: boolean?): (Vector3?, number)
	local SP = GE.spot
	local floor: { Instance } = {}
	local function okHit(h: RaycastResult?): boolean
		if not h or h.Material == Enum.Material.Water then
			return false
		end
		if h.Instance ~= workspace.Terrain then
			if not floorOk then
				return false
			end
			table.insert(floor, h.Instance)
		end
		return true
	end
	local c = groundHit(x, z)
	if not okHit(c) then
		return nil, math.huge
	end
	local cc = c :: RaycastResult
	local lo, hi = cc.Position.Y, cc.Position.Y
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local h = groundHit(x + math.cos(a) * SP.flatR, z + math.sin(a) * SP.flatR)
		if not okHit(h) then
			return nil, math.huge
		end
		local hh = h :: RaycastResult
		lo, hi = math.min(lo, hh.Position.Y), math.max(hi, hh.Position.Y)
	end
	c = cc
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = table.clone(floor)
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(skip, pl.Character)
		end
	end
	op.FilterDescendantsInstances = skip
	for _, part in workspace:GetPartBoundsInRadius(c.Position + Vector3.new(0, 4, 0), SP.clearR, op) do
		-- neighboring plaza floor slabs (Clay, Circle, Trail - the top flush with the floor) - not an obstacle; a top higher than the floor by 1.2+
		local cf, sz = part.CFrame, part.Size
		local top = cf.Position.Y + math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
		if part.Transparency < 1 and sz.Magnitude > 1.5 and top > c.Position.Y + 1.2 then
			return nil, math.huge -- a rock, a trunk, a fence, a stall post, a sign, the stream at the ledge
		end
	end
	return c.Position, hi - lo
end

-- decor (tag Decor) - trees with CanQuery off, the probeSpot parts check
-- does not see them; circles by the model's bounding box (the crown no wider than 14), once per server. Undergrowth lower than 3 and narrower than 4 studs is not an obstacle
local decorObs: { { x: number, z: number, r: number } }? = nil
local function decorClearance(x: number, z: number): number
	if not decorObs then
		local list = {}
		for _, m in CollectionService:GetTagged("Decor") do
			if m:IsA("Model") and m.Parent then
				local ok, cf, size = pcall(function()
					return m:GetBoundingBox()
				end)
				if ok and (size.Y > 3 or math.max(size.X, size.Z) > 4) then
					table.insert(list, { x = cf.Position.X, z = cf.Position.Z, r = math.min(math.max(size.X, size.Z) / 2, 14) })
				end
			end
		end
		decorObs = list
	end
	local obs = decorObs :: { { x: number, z: number, r: number } }
	if #obs < 300 then
		decorObs = nil -- the decor is still being built (the server just came up) - recompute next time
	end
	local best = math.huge
	for _, o in obs do
		local d = math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r
		if d < best then
			best = d
		end
	end
	return best
end

local function spotFor(p: Player): Vector3?
	local nest = services.Nest and services.Nest.of(p)
	if not nest then
		return nil
	end
	local np = nest:GetPivot().Position
	local SP = GE.spot
	local pts = Layout.eggPoints()
	local others: { Vector3 } = {}
	if folder then
		for _, m in (folder :: Folder):GetChildren() do
			if m:IsA("Model") and m:GetAttribute("OwnerId") ~= p.UserId then
				table.insert(others, m:GetPivot().Position)
			end
		end
	end
	local function flat(a: Vector3, b: Vector3): number
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end
	-- the golden nest on the plaza (where players walk the most): on its
	-- side opposite the own lot (there is no chase in the own lot - that is "home"; the run home through the crowded plaza ~100 studs);
	-- a flat floor, within clearR no stall or rock, no closer than spawnGap to the spawn point, no closer than 25 to a foreign golden one. None - the meadow (below).
	-- THE FOOT OF THE TERRACE SLOPE on the meadow in front of the own lot (Config.Glow.egg.spot.slope): radii
	-- from the world center beyond the terrace wall (170) and the slope rocks (182-204), angles from the own lot axis; the "meadow" zone, flat, empty, no closer than
	-- nestGap to the ring-1 Gloom nests (their dismount zone 35 - two nests do not compete for the dragon), no closer than otherGap to a foreign golden one
	local SL = SP.slope
	local function slopeSpot(nestGap: number, flatMax: number, decorGap: number): Vector3?
		local lotAngle = math.atan2(np.Z, np.X)
		local raidNests: { Vector3 } = if services.Raid and services.Raid.nestPositions then services.Raid.nestPositions() else {}
		local ctx = { flying = false, gliding = false, swimming = false, ownNest = false }
		local sBest: Vector3? = nil
		local sScore = math.huge
		for _, da in SL.arcs do
			for _, rr in SL.radii do
				local a = lotAngle + math.rad(da)
				local qx, qz = math.cos(a) * rr, math.sin(a) * rr
				local q = Vector3.new(qx, 0, qz)
				local ok = true
				for _, rp in raidNests do
					if flat(q, rp) < nestGap then
						ok = false
						break
					end
				end
				if ok then
					for _, e2 in pts do
						if flat(q, Vector3.new(e2.pos[1], 0, e2.pos[3])) < SP.eggGap then
							ok = false
							break
						end
					end
				end
				if ok then
					for _, o in others do
						if flat(q, o) < SL.otherGap then
							ok = false
							break
						end
					end
				end
				local clr = if ok then decorClearance(qx, qz) else -1
				if ok and clr >= decorGap then
					local at, dh = probeSpot(qx, qz)
					if at and dh <= flatMax and Zones.of(at.X, at.Y, at.Z, ctx, Config.World) == "meadow" then
						-- an open spot matters more - the margin from decor (up to 24 studs), then flatter and closer to the own lot axis
						local score = dh * 10 + math.abs(da) / 15 - math.min(clr, 24) / 3
						if score < sScore then
							sBest, sScore = at, score
						end
					end
				end
			end
		end
		return sBest
	end
	if SL and SL.on then
		local sBest = slopeSpot(SL.nestGap, SL.flatMax, SL.decorGap or 0)
		if not sBest and SL.relax then -- a second softer pass: closer to the ring-1 nests (Raid does not touch while the golden egg is in hand), not as flat
			sBest = slopeSpot(SL.relax.nestGap, SL.relax.flatMax, SL.relax.decorGap or 0)
			if sBest then
				warn("[GlowEgg] the golden nest on the slope - by the soft pass (relax)")
			end
		end
		if sBest then
			return sBest
		end
		warn("[GlowEgg] no spot for the golden nest found on the slope")
	end
	if SP.plaza then
		local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
		-- the plaza edge at the angle plazaArc to the own lot - the way home along the edge, Old Ash, the stall, the board - farther than hubGap
		-- (opposite the own lot the way home goes through the crowded center)
		local lotAngle = math.atan2(np.Z, np.X) -- the plaza center at the origin (Core/Zones)
		local W = Config.World
		local hub: { Vector3 } = { Vector3.new(W.keeper.x, 0, W.keeper.z), Vector3.new(W.stall.x, 0, W.stall.z) }
		local bp = Config.Social and Config.Social.board and Config.Social.board.pos
		if bp then
			table.insert(hub, Vector3.new(bp[1], 0, bp[3]))
		end
		local pBest: Vector3? = nil
		local pScore = math.huge
		for ai, da in SP.plazaArc do
			for ri, rr in SP.plazaR do
				local a = lotAngle + math.rad(da)
				local qx, qz = math.cos(a) * rr, math.sin(a) * rr
				local q = Vector3.new(qx, 0, qz)
				local ok = not spawn or flat(q, (spawn :: BasePart).Position) >= SP.spawnGap
				for _, hp in hub do
					if flat(q, hp) < SP.hubGap then
						ok = false
					end
				end
				if ok then
					for _, o in others do
						if flat(q, o) < 25 then
							ok = false
							break
						end
					end
				end
				if ok and services.Raid and services.Raid.nestPositions then -- not next to the shared raid nests (ring 0 at the rim)
					for _, rp in services.Raid.nestPositions() do
						if flat(q, rp) < 25 then
							ok = false
							break
						end
					end
				end
				if ok then
					for _, e2 in pts do
						if flat(q, Vector3.new(e2.pos[1], 0, e2.pos[3])) < SP.eggGap then
							ok = false
							break
						end
					end
				end
				if ok then
					local at, dh = probeSpot(qx, qz, true)
					if at and dh <= SP.flatMax then
						local score = dh * 10 + ai + ri -- flatter, closer to the opposite side and to the first radius
						if score < pScore then
							pBest, pScore = at, score
						end
					end
				end
			end
		end
		if pBest then
			return pBest
		end
		warn("[GlowEgg] no spot for the golden nest found on the plaza - onto the meadow")
	end
	local mid = (GE.distance[1] + GE.distance[2]) / 2
	local best: Vector3? = nil
	local bs = math.huge
	local fallback: Vector3? = nil
	local fs = -math.huge
	for _, e in pts do
		if e.zone == "Meadow" and not e.secret then
			local c = Vector3.new(e.pos[1], e.pos[2], e.pos[3])
			local dc = flat(c, np)
			if dc >= GE.distance[1] and dc <= GE.distance[2] and -math.abs(dc - GE.distance[2]) > fs then
				fallback, fs = c + (Vector3.new(np.X, 0, np.Z) - Vector3.new(c.X, 0, c.Z)).Unit * 12, -math.abs(dc - GE.distance[2])
			end
			if dc >= GE.distance[1] - 60 and dc <= GE.distance[2] + 60 then
				for _, rr in SP.rings do
					for k = 0, 11 do
						local a = k / 12 * math.pi * 2
						local qx, qz = c.X + math.cos(a) * rr, c.Z + math.sin(a) * rr
						local q = Vector3.new(qx, c.Y, qz)
						local dq = flat(q, np)
						local ok = dq >= GE.distance[1] and dq <= GE.distance[2]
						if ok then
							for _, e2 in pts do
								if flat(q, Vector3.new(e2.pos[1], 0, e2.pos[3])) < SP.eggGap then
									ok = false
									break
								end
							end
						end
						if ok then
							for _, o in others do
								if flat(q, o) < 30 then
									ok = false
									break
								end
							end
						end
						if ok then
							local at, dh = probeSpot(qx, qz)
							if at and dh <= SP.flatMax then
								local score = dh * 10 + math.abs(dq - mid) / 20
								if score < bs then
									best, bs = at, score
								end
							end
						end
					end
				end
			end
		end
	end
	if best then
		return best
	end
	if not fallback then
		return nil
	end
	local b = fallback :: Vector3
	warn("[GlowEgg] no flat spot for the golden nest found - by the egg spot")
	local hit = groundHit(b.X, b.Z)
	return if hit then hit.Position else b
end

-- THE GOLDEN NEST - a bowl of woven branches (rings of thin branches at different angles),
-- a warm golden light, golden sparks rise, little lights circle above the egg. The same nest on the islet and at home.
local GOLD = Color3.fromRGB(255, 200, 80)
local GOLD_DARK = Color3.fromRGB(200, 140, 40)
local rng = Random.new(28)
-- the same woven nest in a dark palette - the shared Gloom nests (Services/Raid)
local DARK = { gold = Color3.fromRGB(120, 80, 170), dark = Color3.fromRGB(46, 30, 66), light = Color3.fromRGB(150, 80, 230), sparks = Color3.fromRGB(170, 110, 240), motes = Color3.fromRGB(200, 160, 255), rate = 12 }
local function goldenNest(parent: Model, at: Vector3, radius: number, pal: any?): BasePart
	local GOLD, GOLD_DARK = GOLD, GOLD_DARK
	if pal then
		GOLD, GOLD_DARK = pal.gold, pal.dark
	end
	for ring = 1, 4 do
		local r = radius * (0.55 + ring * 0.13)
		local y = 0.25 + ring * 0.38
		local n = 9 + ring * 3
		for k = 1, n do
			local a = (k + rng:NextNumber() * 0.6) / n * math.pi * 2
			local twig = Instance.new("Part")
			twig.Name = "Twig"
			twig.Shape = Enum.PartType.Cylinder
			local len = r * 0.9 + rng:NextNumber() * 1.2
			twig.Size = Vector3.new(len, 0.32 + rng:NextNumber() * 0.12, 0.32 + rng:NextNumber() * 0.12)
			local pos = at + Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
			-- a branch tangent to the ring, tilted up-down - the weave
			twig.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), (rng:NextNumber() - 0.5) * 0.7, math.cos(a)))
				* CFrame.Angles(0, math.rad(90), 0)
			twig.Material = if (k + ring) % 3 == 0 then Enum.Material.Foil else Enum.Material.Wood
			twig.Color = if (k + ring) % 3 == 0 then GOLD else GOLD_DARK:Lerp(GOLD, rng:NextNumber() * 0.5)
			twig.Anchored = true
			twig.CanCollide = false
			twig.CanQuery = false
			twig.CastShadow = false
			twig.Parent = parent
		end
	end
	local core = Instance.new("Part")
	core.Name = "NestCore"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(0.6, radius * 1.4, radius * 1.4)
	core.CFrame = CFrame.new(at + Vector3.new(0, 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	core.Material = Enum.Material.Wood
	core.Color = GOLD_DARK
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Parent = parent
	local light = Instance.new("PointLight")
	light.Color = if pal then pal.light else GOLD
	light.Range = if pal then 24 else 26 -- the dark nest is visible from afar too
	light.Brightness = if pal then 1.8 else 3
	light.Parent = core
	local up = Instance.new("ParticleEmitter") -- golden sparks upward: visible from afar
	up.Name = "GoldSparks"
	up.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	up.Rate = if pal then pal.rate else 26
	up.Lifetime = NumberRange.new(2.5, 4)
	up.Speed = NumberRange.new(3, 6)
	up.SpreadAngle = Vector2.new(18, 18)
	up.Acceleration = Vector3.new(0, 1.5, 0)
	up.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	up.Color = ColorSequence.new(if pal then pal.sparks else GOLD)
	up.LightEmission = 1
	up.EmissionDirection = Enum.NormalId.Top
	up.Parent = core
	local motes = Instance.new("ParticleEmitter") -- little lights circle above the egg
	motes.Name = "GoldMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Rate = 10
	motes.Lifetime = NumberRange.new(1.5, 2.5)
	motes.Speed = NumberRange.new(0.5, 1.5)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.RotSpeed = NumberRange.new(-120, 120)
	motes.Size = NumberSequence.new(0.5, 0)
	motes.Color = ColorSequence.new(if pal then pal.motes else Color3.fromRGB(255, 235, 170))
	motes.LightEmission = 1
	motes.Shape = Enum.ParticleEmitterShape.Sphere
	motes.Parent = core
	return core
end

-- the egg in the golden nest m (the point at - the nest attribute); taken - the egg is removed, the nest stands empty (the GlowEgg tag removed)
local function putEgg(m: Model)
	local at = m:GetAttribute("At")
	if typeof(at) ~= "Vector3" then
		return
	end
	local el = m:GetAttribute("Element") or GE.element -- the element of the series egg (build)
	local okE, em = pcall(function()
		return services.WorldBuilder.makeEgg(el, 3)
	end)
	if okE and em then
		em.Name = "Egg"
		local cf, size = em:GetBoundingBox()
		em:PivotTo(em:GetPivot() + (at + Vector3.new(0, 0.8, 0) - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
		for _, d in em:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		em.Parent = m
	elseif not okE then
		warn("[GlowEgg] makeEgg: " .. tostring(em))
	end
	m:SetAttribute("Empty", nil)
	CollectionService:AddTag(m, "GlowEgg")
end

local function clearGrass(m: Model, at: Vector3)
	local T = workspace.Terrain
	local ok, err = pcall(function()
		-- short grass LeafyGrass (it has no tall Decoration
		-- blades), a smaller patch
		local region = Region3.new(at - Vector3.new(4, 6, 4), at + Vector3.new(4, 3, 4)):ExpandToGrid(4)
		local mats, occ = T:ReadVoxels(region, 4)
		clearings[m] = { region = region, mats = mats, occ = occ }
		T:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
	end)
	if not ok then
		warn("[GlowEgg] clearing: " .. tostring(err))
	end
end

local function dropNest(m: Model)
	local c = clearings[m]
	clearings[m] = nil
	if c then
		local ok, err = pcall(function()
			workspace.Terrain:WriteVoxels(c.region, 4, c.mats, c.occ)
		end)
		if not ok then
			warn("[GlowEgg] grass back: " .. tostring(err))
		end
	end
	m:Destroy()
end

-- the lot has a fence with an invisible wall along
-- the perimeter and ONE gate of width gapW in the middle of the front edge (WorldBuilder: z = -lotDepth/2, gap 12). The scene gate is this gap:
-- S - the gate center, O - a point outside on the plaza, A-B - the gate edges (the SAFE line); Pd - the pedestal and W - where the dragon waits: inside
-- the lot by the entrance, by MEASUREMENT among candidates (homeSpots) - within clearR no fence (and its wall), bowls, table, shelf, pile or sign
local HOME_SPOTS = { { -8, -47 }, { -9, -42 }, { 8, -47 }, { 9, -42 }, { -6, -40 }, { 6, -40 }, { -10, -37 }, { 10, -37 } } -- local: x, z

local function clearAt(base: BasePart, wp: Vector3, r: number, skip: { Instance }): boolean
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = skip
	for _, part in workspace:GetPartBoundsInRadius(wp + Vector3.new(0, 2.5, 0), r, op) do
		if part ~= base then
			local cf, sz = part.CFrame, part.Size
			local top = cf.Position.Y + math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
			if top > wp.Y + 0.6 and (part.Transparency < 1 or part.CanCollide) then
				return false -- a post, a rail, a fence wall, a bowl, a table, a shelf, a lantern
			end
		end
	end
	return true
end

local function gateFor(p: Player): { S: Vector3, O: Vector3, A: Vector3, B: Vector3, W: Vector3, Pd: Vector3 }?
	local nest = services.Nest and services.Nest.of(p)
	local base = nest and nest:FindFirstChild("Base")
	if not nest or not base or not base:IsA("BasePart") then
		return nil
	end
	local cf, sz = base.CFrame, base.Size
	local hd, top = sz.Z / 2, sz.Y / 2
	-- the front edge - the Z face closer to the plaza center (0, 0)
	local zf = -hd
	local f1, f2 = cf:PointToWorldSpace(Vector3.new(0, top, -hd)), cf:PointToWorldSpace(Vector3.new(0, top, hd))
	if Vector3.new(f2.X, 0, f2.Z).Magnitude < Vector3.new(f1.X, 0, f1.Z).Magnitude then
		zf = hd
	end
	local inward = if zf < 0 then 1 else -1
	local gw = GE.raid.gapW / 2
	local L = function(x: number, z: number): Vector3
		return cf:PointToWorldSpace(Vector3.new(x, top, z))
	end
	local skip: { Instance } = {}
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(skip, pl.Character)
		end
	end
	for _, n in { "Gloom", "GlowEggs" } do
		local f = workspace:FindFirstChild(n)
		if f then
			table.insert(skip, f)
		end
	end
	local pick: { Vector3 } = {}
	for _, c in HOME_SPOTS do
		local z = zf + inward * (hd + c[2]) -- c[2] from -hd inward
		local wp = L(c[1], z)
		if clearAt(base, wp, GE.raid.clearR, skip) then
			table.insert(pick, wp)
		end
	end
	local Pd = pick[1] or L(-8, zf + inward * 8)
	local W = pick[2] or L(8, zf + inward * 8)
	-- the dragon - on the other side of the path from the pedestal, if there is such a spot
	for i = 2, #pick do
		local a, b = cf:PointToObjectSpace(Pd), cf:PointToObjectSpace(pick[i])
		if a.X * b.X < 0 then
			W = pick[i]
			break
		end
	end
	return { S = L(0, zf), O = L(0, zf - inward * GE.raid.outD), A = L(-gw, zf), B = L(gw, zf), W = W, Pd = Pd }
end

local function homeOf(p: Player): { S: Vector3, O: Vector3, A: Vector3, B: Vector3, W: Vector3, Pd: Vector3 }?
	local g = gates[p]
	if not g then
		g = gateFor(p) :: any
		gates[p] = g :: any
	end
	return g
end

-- the element of the player's current golden egg (Core/GlowSeries: data.glowEgg.n -> Config.Glow.egg.series)
local function elementOf(p: Player): string
	local data = services.PlayerData.get(p)
	return GlowSeries.element(data and data.glowEgg, GE)
end

local function build(p: Player, at: Vector3): Model
	local m = Instance.new("Model")
	m.Name = "GlowEgg_" .. p.UserId
	clearGrass(m, at)
	m.PrimaryPart = goldenNest(m, at, 3.2)
	m:SetAttribute("OwnerId", p.UserId)
	m:SetAttribute("At", at)
	m:SetAttribute("Element", elementOf(p))
	putEgg(m)
	m.Parent = folder
	nestAt[p] = at
	gates[p] = nil -- the gate and the pedestal spot - anew, by measurement (the lot may have changed)
	local g = homeOf(p)
	if services.Combat and services.Combat.placePack then -- the pack sleeps behind the nest on the side away from the gate
		local ok, err = pcall(services.Combat.placePack, p, at, if g then g.S else at + Vector3.xAxis, services.Nest and services.Nest.of(p))
		if not ok then
			warn("[GlowEgg] placePack: " .. tostring(err))
		end
	end
	return m
end

local function takeOut(m: Model)
	local egg = m:FindFirstChild("Egg")
	if egg then
		egg:Destroy()
	end
	m:SetAttribute("Empty", true)
	CollectionService:RemoveTag(m, "GlowEgg")
end

local function taken(data: any): boolean
	return typeof(data.glowEgg) == "table" and (tonumber(data.glowEgg.taken) or 0) > 0
end

local function newEgg(element: string): any
	return { id = "glow_" .. element, element = element, rarity = GE.rarity, shiny = false, size = "normal", zone = "Summit",
		rareNest = false, glow = true, foundAt = os.time() }
end

-- the pedestal by the nest: a stone post, on it the glowing egg and the timer "Hatches in ..." (the client counts by the ReadyAt attribute)
local function buildPedestal(p: Player, readyAt: number): Model?
	local nest = services.Nest and services.Nest.of(p)
	local inc = nest and nest:FindFirstChild("Incubators")
	local i1 = inc and inc:FindFirstChild("Incubator1")
	if not nest or not i1 then
		return nil
	end
	local hs = homeOf(p)
	local base = if hs then CFrame.new(hs.Pd) else (i1 :: any):GetPivot() * CFrame.new(0, 0, -9) -- not on the fence
	local m = Instance.new("Model")
	m.Name = "GlowPedestal_" .. p.UserId
	local stone = goldenNest(m, base.Position, 2.6) -- the own golden nest at home (not a stone pedestal)
	local okE, em = pcall(function()
		return services.WorldBuilder.makeEgg(elementOf(p), 2.4)
	end)
	if okE and em then
		local cf, size = em:GetBoundingBox()
		local top = base.Position + Vector3.new(0, 0.8, 0)
		em:PivotTo(em:GetPivot() + (top - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
		for _, d in em:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
			end
		end
		em.Parent = m
	end
	m.PrimaryPart = stone
	m:SetAttribute("OwnerId", p.UserId)
	m:SetAttribute("ReadyAt", readyAt)
	CollectionService:AddTag(m, "GlowPedestal")
	m.Parent = folder
	return m
end

-- WARMING the egg with coins - an hour off the timer for the price = the pen income over warm.secondsPerHour s
-- (20 h x 360 s = ~2 h of play), at least floor, a multiple of 100; the price - the pedestal's WarmPrice attribute (the client Glow). Robux - HatchNow with the goal "glow"
local function warmPrice(data: any): number
	local W = GE.warm
	local mods = if services.Shop and services.Shop.rateMods then services.Shop.rateMods(data) else { ascension = data.ascension or 0 }
	local okR, rate = pcall(Economy.nestRate, Dragons.nestList(data) :: any, mods :: any, Config.Balance)
	local perSec = if okR and typeof(rate) == "number" then rate else 0
	local raw = perSec * (W.secondsPerHour or 360)
	return math.max(W.floor or 1000, math.floor(raw / 100 + 0.5) * 100)
end

function GlowEgg.warm(p: Player): { ok: boolean, reason: string?, [string]: any }
	local W = GE.warm
	if not (W and W.on) then
		return { ok = false, reason = "locked" }
	end
	local data = services.PlayerData.get(p)
	local ge = data and data.glowEgg
	local now = os.time()
	if not data or typeof(ge) ~= "table" or (tonumber(ge.taken) or 0) == 0 or (tonumber(ge.readyAt) or 0) == 0 or ge.hatched then
		return { ok = false, reason = "no_target" }
	end
	local left = ge.readyAt - now
	if left < (W.minLeft or 60) then
		return { ok = false, reason = "no_target" }
	end
	local pd = pedestals[p]
	local r = root(p)
	if not pd or not pd.Parent or not pd.PrimaryPart or not r or (pd.PrimaryPart.Position - r.Position).Magnitude > (W.reach or 26) then
		return { ok = false, reason = "too_far" }
	end
	local price = warmPrice(data)
	local coins = math.floor(data.coins or 0)
	if coins < price then
		return { ok = false, reason = "not_enough", need = price - coins }
	end
	if not services.Nest.spend(p, price, "GlowWarm", "hour") then
		return { ok = false, reason = "not_enough", need = price - coins }
	end
	local cut = math.min(left, (W.stepHours or 1) * 3600)
	services.PlayerData.update(p, "glowEgg", function(g: any)
		g.readyAt = math.max(now, g.readyAt - cut)
		return g
	end)
	local d2 = services.PlayerData.get(p)
	local readyAt = if d2 and typeof(d2.glowEgg) == "table" then tonumber(d2.glowEgg.readyAt) or now else now
	pd:SetAttribute("ReadyAt", readyAt)
	local l2 = math.max(0, readyAt - now)
	services.Net.notice(p, { kind = "toast", text = Loc.text(Strings.GlowEgg.warmed, { t = string.format("%d:%02d:%02d", l2 // 3600, l2 % 3600 // 60, l2 % 60) }) })
	if services.Analytics then
		pcall(services.Analytics.custom, p, "glow_warm", price, { left = l2 })
	end
	return { ok = true, readyAt = readyAt, price = price }
end

-- after "hatch now" from the shop (Shop afterGrant) - the pedestal learns the new deadline; then the tick: into the bowl
function GlowEgg.resync(p: Player)
	local data = services.PlayerData.get(p)
	local pd = pedestals[p]
	if data and typeof(data.glowEgg) == "table" and pd and pd.Parent then
		pd:SetAttribute("ReadyAt", tonumber(data.glowEgg.readyAt) or 0)
	end
end

-- the egg back into the golden nest - the profile (not in hand, not taken), the nest waits arc s and has the egg again; from - where
-- the arc flies from (the capture point), nil - without an arc (the egg left the hands not by a capture)
local function sendBack(p: Player, from: Vector3?)
	safeAt[p] = nil
	p:SetAttribute("GlowRaid", nil)
	services.PlayerData.update(p, { "eggs", "glowEgg" }, function(e: any, dd: any)
		if typeof(e.carry) == "table" and e.carry.glow == true then
			e.carry = nil
		end
		dd.glowEgg = { taken = 0, n = GlowSeries.index(dd.glowEgg) } -- the series egg number is kept
		return nil
	end)
	if services.EggSpawner then
		services.EggSpawner.showCarry(p, nil)
	end
	local m = eggs[p]
	if from and m and m.Parent then
		local arc = GE.chase and GE.chase.arc or 1
		rearm[p] = true
		rearmAt[p] = os.clock()
		returnAt[p] = os.clock() + arc * 0.6 -- the service tick is 1 s: the egg lands in the nest when the arc arrives
		services.Net.notice(p, { kind = "glowEgg", ev = "caught", from = from, to = m:GetPivot().Position + Vector3.new(0, 1.6, 0),
			seconds = arc })
	end
end

-- at home: the egg from the hands onto the pedestal until tomorrow (readyAt), the raid is over - the dragon follows the player again; "SAFE!" on the client. Called by the nest tick
-- (entered the lot) and by the pack (Combat: the thief crossed the line - at once, not a second later on the tick)
local function goHome(p: Player)
	local data = services.PlayerData.get(p)
	local carry = data and data.eggs and data.eggs.carry
	local ge = data and data.glowEgg
	if not (typeof(carry) == "table" and carry.glow == true) or not (typeof(ge) == "table" and (tonumber(ge.readyAt) or 0) == 0) then
		return
	end
	local readyAt = os.time() + math.floor(GE.hatchHours * 3600)
	services.PlayerData.update(p, { "eggs", "glowEgg" }, function(e: any, d: any)
		e.carry = nil
		d.glowEgg.readyAt = readyAt
		return nil
	end)
	if services.EggSpawner then
		services.EggSpawner.showCarry(p, nil)
	end
	nestAt[p] = nil -- the raid is over: the dragon follows the player again (the pack stopped at the line by itself and melts)
	dPoints[p], safeAt[p] = nil, nil
	p:SetAttribute("GlowRaid", nil)
	services.Net.notice(p, { kind = "glowEgg", ev = "home", readyAt = readyAt })
	if services.Analytics then
		pcall(services.Analytics.custom, p, "glow_egg_home", 1)
	end
end

local function onChaseEnd(p: Player, why: string, at: Vector3?, info: any)
	if p.Parent ~= Players then
		return
	end
	if why == "caught" then
		tries[p] = (tries[p] or 0) + 1
	end
	if services.Analytics then -- the chase duration, the smallest gap to the leader, the attempt
		pcall(services.Analytics.custom, p, "glow_chase_" .. why, typeof(info) == "table" and info.sec or 0,
			{ gap = typeof(info) == "table" and info.gap or -1, tries = tries[p] or 0 })
	end
	local data = services.PlayerData.get(p)
	local carry = data and data.eggs and data.eggs.carry
	if not (typeof(carry) == "table" and carry.glow == true) then
		return -- already at home (the pedestal) or the egg left the hands
	end
	if why == "caught" then
		sendBack(p, at)
	elseif why == "lost" then
		services.Net.notice(p, { kind = "glowEgg", ev = "escaped" })
	elseif why == "home" then
		local r = root(p)
		local nest = services.Nest and services.Nest.of(p)
		if dragonMode() and not (r and nest and services.Incubation.inLot(nest, r.Position)) then
			-- reached the own dragon and mounted - the guardian stopped at dragonStop, "SAFE!", home by air; the pedestal - once
			-- the player rode into the lot (the nest tick: carryGlow and inLot -> goHome)
			safeAt[p] = true
			if services.Raid and services.Raid.wait then
				services.Raid.wait(p, "glow", nil)
			else
				p:SetAttribute("GlowWait", nil)
			end
			services.Net.notice(p, { kind = "glowEgg", ev = "safe" })
			if services.Analytics then
				pcall(services.Analytics.custom, p, "glow_safe", typeof(info) == "table" and info.sec or 0,
					{ gap = typeof(info) == "table" and info.gap or -1, tries = tries[p] or 0 })
			end
		else
			goHome(p) -- the pack sees the line every frame - "SAFE!" and the pedestal at once, not a nest tick later
		end
	end
end

-- the shared Gloom nests - the same woven nest in a dark palette; the lot gate (the gap) and the spot probe
function GlowEgg.nestModel(parent: Model, at: Vector3, radius: number, dark: boolean?): BasePart
	return goldenNest(parent, at, radius, if dark then DARK else nil)
end

function GlowEgg.gateOf(p: Player): { S: Vector3, O: Vector3, A: Vector3, B: Vector3, W: Vector3, Pd: Vector3 }?
	return homeOf(p)
end

function GlowEgg.probe(x: number, z: number, floorOk: boolean?): (Vector3?, number)
	return probeSpot(x, z, floorOk)
end

-- the gate anew by measurement (the lot may have changed)
function GlowEgg.forgetGate(p: Player)
	gates[p] = nil
end

-- a raid - outside the own lot closer than raidR to the nest or with the egg in hand outside the lot (Movement.mount asks)
function GlowEgg.raidActive(p: Player): boolean
	return raidOn[p] == true
end

-- every 0.2 s: a raid - mounted, dismount (one toast), the dragon waits at the gate (GlowWait = W); at home or far without the egg - follows the player again
local gateToast: { [Player]: boolean } = {}
-- the GlowWait attribute is shared by the golden nest and the shared nests of Services/Raid - through Raid.wait (source "glow")
local function setWait(p: Player, want: Vector3?)
	if services.Raid and services.Raid.wait then
		services.Raid.wait(p, "glow", want)
	elseif p:GetAttribute("GlowWait") ~= want then
		p:SetAttribute("GlowWait", want)
	end
end
-- the profile no longer
-- grants the golden nest (Reset Progress in the same session: 0 dragons) - the nest, its guardian and the raid are removed; otherwise the client
-- sees its GlowEgg and leads to it instead of the first raid egg. With the series a veteran's nest stands almost always - before, a reset was clean
local function forget(p: Player)
	local m = eggs[p]
	if m then
		dropNest(m)
		eggs[p] = nil
	end
	if services.Combat and services.Combat.dropPack then
		services.Combat.dropPack(p)
	end
	announced[p], guarded[p], unlocked[p], returnAt[p], rearm[p], tries[p], rearmAt[p] = nil, nil, nil, nil, nil, nil, nil
	settle[p], nestAt[p], dPoints[p], safeAt[p], gates[p] = nil, nil, nil, nil, nil
	p:SetAttribute("GlowRaid", nil)
	setWait(p, nil)
end

local function raidTick()
	for _, p in Players:GetPlayers() do
		local at = nestAt[p]
		local r = root(p)
		local nest = services.Nest and services.Nest.of(p)
		local data = services.PlayerData.get(p)
		if not at or not r or not nest or not data then
			raidOn[p] = nil
			setWait(p, nil)
			continue
		end
		local carry = data.eggs and data.eggs.carry
		local carryGlow = typeof(carry) == "table" and carry.glow == true
		local home = services.Incubation.inLot(nest, r.Position)
		local dN = (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(at.X, 0, at.Z)).Magnitude
		local on = not home and (dN <= GE.raid.raidR or carryGlow) and (eggs[p] ~= nil or carryGlow)
		local foot: boolean
		local want: Vector3? = nil
		if dragonMode() then
			-- like rings 1-2 (Raid.raidTick): at the nest with the egg (approachR) - dismount, the dragon to point D; with the egg in hand -
			-- run to the dragon: the saddle only when it is no closer than approachR - 10 to the nest (otherwise dismounted at the nest, took it and mounted in place - no
			-- chase); closer than mountR to it - mounted by itself; mounted = SAFE (the finish is decided by the guardian, safeFn at the taking), then the dragon with the player, home by air
			-- by the plane a flyover above the nest dismounted in the air - only near the ground
			-- (P8 day1_walkthrough day x2: on an Elder dragon the rider sits higher than 10 above the nest - the dismount never came, G3 "riding",
			-- the raid did not start): mounted and not in flight - a tolerance by the dragon's body height; in flight (Flying) still no dismount
			local dy = math.abs(r.Position.Y - at.Y)
			local nearY = dy < 10
			if not nearY and p:GetAttribute("Mounted") ~= nil and services.Movement and services.Movement.companionOf then
				-- the Flying attribute is set by the client, the server does not see it - the ground sign is taken by a ray down from the dragon's body
				local c = services.Movement.companionOf(p)
				local body = c and c.PrimaryPart
				if body then
					local rp = RaycastParams.new()
					rp.FilterType = Enum.RaycastFilterType.Exclude
					rp.FilterDescendantsInstances = { c, p.Character or c }
					local hit = workspace:Raycast(body.Position, Vector3.new(0, -(body.Size.Y + 12), 0), rp)
					local grounded = hit ~= nil and (body.Position.Y - hit.Position.Y) <= body.Size.Y / 2 + 4
					nearY = grounded and dy < 10 + body.Size.Y
				end
			end
			local sneaking = on and not carryGlow and dN <= GE.raid.approachR and nearY
			local far = services.Raid ~= nil and services.Raid.dragonFarFrom ~= nil and services.Raid.dragonFarFrom(p, at) == true
			local running = on and carryGlow and not safeAt[p]
			foot = sneaking or (running and not far)
			raidOn[p] = foot or nil -- before the dismount below: Movement.mount looks at raidActive in the same tick
			if (sneaking or running) and services.Raid and services.Raid.waitPointFor then
				local d = dPoints[p]
				if not d then
					d = services.Raid.waitPointFor(p, at)
					dPoints[p] = d
				end
				want = d
			end
			if running and far and p:GetAttribute("Mounted") == nil and services.Movement and services.Movement.mount and services.Movement.companionOf then
				local c = services.Movement.companionOf(p)
				local body = c and c.PrimaryPart
				-- on an Elder Size.Magnitude/2 is tens of studs (the thief would "mount" right at the nest in the first frame
				-- of the chase - SAFE without a run): the saddle radius no more than mountR + 8 and only when the thief himself ran approachR - 10 from the nest
				local runOff = dN >= GE.raid.approachR - 10
				if body and runOff and (body.Position - r.Position).Magnitude <= (GE.raid.mountR or 12) + math.min(body.Size.Magnitude / 2, 8) and typeof(data.companion) == "string" then
					local ok, rep = pcall(services.Movement.mount, p, data.companion)
					if ok and rep and rep.ok and services.Analytics then
						pcall(services.Analytics.custom, p, "glow_automount", 1)
					end
				end
			end
		else
			-- the dismount and the saddle ban - only right at the nest (approachR) or with the egg in hand; otherwise a player who is not
			-- after the egg would get off the dragon on every ride onto the plaza. The dragon waits at the gate in the whole raidR zone
			foot = on and (carryGlow or dN <= GE.raid.approachR)
			local g = gates[p]
			want = if on and g then g.W else nil
		end
		raidOn[p] = foot or nil
		setWait(p, want)
		if foot and p:GetAttribute("Mounted") ~= nil and services.Movement and services.Movement.dismount then
			local ok, rep = pcall(services.Movement.dismount, p)
			if ok and rep and rep.ok then
				settle[p] = { at = r.Position, t = os.clock() } -- the egg - after the own step toward it, not from the saddle
				if not gateToast[p] then
					gateToast[p] = true
					services.Net.notice(p, { kind = "glowEgg", ev = "gate", mode = GE.raid.safe })
				end
				if services.Analytics then
					pcall(services.Analytics.custom, p, "glow_gate_dismount", 1)
				end
			end
		end
	end
end

local fresh: { [Player]: boolean } = {} -- the first tick of the player's session has already passed
local function tick()
	local now = os.time()
	for _, p in Players:GetPlayers() do
		local data = services.PlayerData.get(p)
		if not data then
			continue
		end
		local first = not fresh[p]
		fresh[p] = true
		local ge = if typeof(data.glowEgg) == "table" then data.glowEgg else {}
		local r = root(p)
		local nest = services.Nest and services.Nest.of(p)
		-- 3) taken: carrying home -> the pedestal; on the pedestal -> tomorrow into the bowl
		if taken(data) then
			local carry = data.eggs.carry
			local carryGlow = typeof(carry) == "table" and carry.glow == true
			local waiting = (tonumber(ge.readyAt) or 0) == 0
			-- while the egg is in hand the golden nest stands empty - the Gloom caught up, the egg flies back into it; at home - remove
			local m = eggs[p]
			if m and not (carryGlow and waiting) then
				dropNest(m)
				eggs[p] = nil
			end
			if not carryGlow and services.Combat and services.Combat.calmPack then
				services.Combat.calmPack(p) -- the egg left the hands not by a capture - the pack goes back to sleep
			end
			if ge.hatched then
				-- the glowing dragon hatched (no egg in hand or in a bowl) - the next golden egg of the series; the nest
				-- appears on the next tick, the "spawn" banner - again (announced)
				local nx = GlowSeries.advance(ge, data.eggs, GE)
				if nx then
					services.PlayerData.update(p, "glowEgg", function()
						return nx
					end)
					-- a new egg = a new visit: the captures, the banner, the guards - from zero (as when the player leaves)
					announced[p], guarded[p], unlocked[p], returnAt[p], rearm[p], tries[p], rearmAt[p] = nil, nil, nil, nil, nil, nil, nil
					if services.Analytics then
						pcall(services.Analytics.custom, p, "glow_series_next", nx.n)
					end
				end
				continue
			end
			if waiting and not carryGlow then
				-- the egg left the hands without reaching home (a reset, debugging, overwritten in hand) - back into the golden nest, not gone forever
				sendBack(p, nil)
				continue
			end
			-- left the game during a chase with the golden egg - Combat removed the pack, the profile kept the egg in hand; on join
			-- it goes back into the golden nest (otherwise leaving = bypassing the guardian; "already home" is no exception - joining puts you in your pen, HomeSpawn)
			if waiting and carryGlow and first then
				sendBack(p, nil)
				if services.Analytics then
					pcall(services.Analytics.custom, p, "glow_orphan", 1)
				end
				continue
			end
			if waiting then
				if carryGlow and r and nest and services.Incubation.inLot(nest, r.Position) then
					goHome(p)
				end
				continue
			end
			if not pedestals[p] or not pedestals[p].Parent then
				pedestals[p] = buildPedestal(p, ge.readyAt) :: any
			end
			local pd = pedestals[p]
			if pd then -- the deadline and the warming price on the pedestal (the client reads the attributes)
				if pd:GetAttribute("ReadyAt") ~= ge.readyAt then
					pd:SetAttribute("ReadyAt", ge.readyAt)
				end
				if GE.warm and GE.warm.on then
					local wp = warmPrice(data)
					if pd:GetAttribute("WarmPrice") ~= wp then
						pd:SetAttribute("WarmPrice", wp)
					end
				end
			end
			if now >= ge.readyAt and data.eggs.carry == nil and r and nest and services.Incubation.inLot(nest, r.Position) then
				-- ready: into a free bowl (a regular hatch, hatchSeconds)
				for slot = 1, (data.incubators or 1) do
					if not data.eggs.incubating[tostring(slot)] then
						services.PlayerData.update(p, "eggs", function(e: any)
							e.carry = newEgg(elementOf(p))
							return nil
						end)
						local rep = services.Incubation.place(p, slot)
						if rep and rep.ok then
							services.PlayerData.update(p, "glowEgg", function(g: any)
								g.hatched = true
								return g
							end)
							if pedestals[p] then
								pedestals[p]:Destroy()
								pedestals[p] = nil
							end
							services.Net.notice(p, { kind = "glowEgg", ev = "ready" })
						else
							services.PlayerData.update(p, "eggs", function(e: any)
								e.carry = nil
								return nil
							end)
						end
						break
					end
				end
			end
			continue
		end
		-- a profile without
		-- a taken egg - there must be no pedestal
		if pedestals[p] then
			pedestals[p]:Destroy()
			pedestals[p] = nil
		end
		-- the nest - after the first won skirmish;
		-- with raids there are no combat stages - after afterRaids raid eggs brought home (data.raid.home)
		local cs = if typeof(data.combat) == "table" then tonumber(data.combat.stage) or 0 else 0
		local homes = if typeof(data.raid) == "table" then tonumber(data.raid.home) or 0 else 0
		local need = if Config.Raid and Config.Raid.on then (GE.afterRaids or 6) else 1
		-- for old profiles (dragons from the table, raid.home 0) - by having a dragon; to the slope - by air (needRide: the first ride)
		local dragons = if typeof(data.nestOrder) == "table" then #data.nestOrder else 0
		local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
		if cs < 1 and homes < need and dragons < 1 then
			if eggs[p] then
				forget(p) -- a progress reset - a newcomer has no golden nest
			end
			continue
		end
		-- the "mount" arrow is gone
		-- (his word), the ride might never happen - the nest appears as soon as the companion grew into a teen (it can be mounted)
		if dragonMode() and GE.raid.needRide and onb.rode ~= true and (tonumber(p:GetAttribute("CompanionStage")) or 0) < 1 then
			if eggs[p] then
				forget(p)
			end
			continue
		end
		-- 1) the egg on the islet
		local m = eggs[p]
		if not m or not m.Parent then
			local at = spotFor(p)
			if not at then
				continue
			end
			m = build(p, at)
			eggs[p] = m
			if not announced[p] then
				announced[p] = true
				services.Net.notice(p, { kind = "glowEgg", ev = "spawn", pos = at })
				if services.Analytics then
					pcall(services.Analytics.custom, p, "glow_egg_spawn", 1)
				end
			end
		end
		local mm = m :: Model
		if mm:GetAttribute("Empty") then -- the caught egg is still flying back - then it is in the nest again
			if os.clock() < (returnAt[p] or 0) then
				continue
			end
			returnAt[p] = nil
			putEgg(mm)
		end
		local d = if r then (r.Position - mm:GetPivot().Position).Magnitude else math.huge
		-- 2) the pack: sleeps at the nest (vanished - place again); approaching does not wake it (spec 26 v2, Steal An Egg)
		local ps = if services.Combat and services.Combat.packState then services.Combat.packState(p) else "sleep"
		if ps == nil and services.Combat and services.Combat.placePack then
			local g = gates[p]
			pcall(services.Combat.placePack, p, mm:GetAttribute("At") or mm:GetPivot().Position, if g then g.S else mm:GetPivot().Position, nest)
			ps = services.Combat.packState(p)
		end
		-- (P8 day1_walkthrough: at the golden nest rearm=true even before the first attempt - a player at the egg would stand "with no answer"):
		-- also lifted by time - the egg returns in arc s, the guardian falls asleep in ~5 s, then the retry is honest
		if rearm[p] and (d > GE.pick + 6 or os.clock() - (rearmAt[p] or 0) > (GE.rearmSeconds or 8)) then
			rearm[p] = nil -- walked away after the capture (or rearmSeconds passed) - allowed again
			if d <= GE.pick + 6 and r then
				settle[p] = { at = r.Position, t = os.clock() } -- still standing at the nest - the next egg only after the own step
			end
		end
		local st = settle[p]
		if st then
			-- not lifted by time - one standing at the nest does not get the egg until he himself steps settleStep along the ground
			-- (a player who landed from the sky would otherwise get the egg by himself and a capture with no answer). Humanoid.MoveDirection is not visible to the server
			-- (md=0 at speed 16) - the player's input cannot be checked here, only the displacement
			local own = r ~= nil and (Vector3.new(r.Position.X, 0, r.Position.Z) - Vector3.new(st.at.X, 0, st.at.Z)).Magnitude >= (GE.settleStep or 4)
			if d > GE.pick + 6 or own then
				settle[p] = nil -- stepped by himself (or walked away) - the egg can be taken
			elseif d <= GE.pick and not st.toasted and os.clock() - st.t > 3 then
				st.toasted = true -- standing at the egg without a step - hint, do not stay silent
				services.Net.notice(p, { kind = "toast", text = Loc.text(Strings.GlowEgg.stepUp) })
			end
		end
		local carryRaid = typeof(data.eggs.carry) == "table" and data.eggs.carry.raid ~= nil -- a raid egg in hand - home first
		-- not given when mounted
		-- no guardian (placePack hit the server enemy limit) - the egg is not given without a chase, wait for the tick
		if not rearm[p] and not settle[p] and ps == "sleep" and d <= GE.pick and not carryRaid and p:GetAttribute("Mounted") == nil then
			if data.eggs.carry ~= nil then
				-- a regular egg
				-- goes onto the shelf at home by itself (like rewards - not lost, it does not cool on the shelf), the glowing one - into the hands
				local held = data.eggs.carry
				services.PlayerData.update(p, "eggs", function(e: any)
					e.shelf = e.shelf or {}
					table.insert(e.shelf, held)
					e.carry = nil
					return nil
				end)
				if services.EggSpawner then
					services.EggSpawner.showCarry(p, nil)
				end
				if services.Incubation and services.Incubation.syncShelfOf then
					pcall(services.Incubation.syncShelfOf, p)
				end
				services.Net.notice(p, { kind = "glowEgg", ev = "toShelf" })
			end
			local egg = newEgg(elementOf(p))
			services.PlayerData.update(p, { "eggs", "glowEgg" }, function(e: any, dd: any)
				e.carry = egg
				dd.glowEgg = { taken = os.time(), readyAt = 0, n = GlowSeries.index(dd.glowEgg) } -- the series egg number is kept
				return nil
			end)
			if services.EggSpawner then
				services.EggSpawner.showCarry(p, egg)
			end
			takeOut(mm) -- the nest stays (caught - the egg returns into it)
			local chased = false
			if services.Combat and services.Combat.wakePack then
				local sh = GE.chase.share
				local share = sh[math.min((tries[p] or 0) + 1, #sh)]
				local safeFn: ((Player) -> (boolean, Vector3?))? = nil
				if dragonMode() then
					-- the chase finish as on rings 1-2 (Raid.safeFor): at home, or mounted the dragon standing away from the nest
					local nestPos: Vector3 = (mm:GetAttribute("At") :: Vector3?) or mm:GetPivot().Position
					safeFn = function(thief: Player): (boolean, Vector3?)
						local tr = root(thief)
						if not tr then
							return false, nil
						end
						local tn = services.Nest and services.Nest.of(thief)
						if tn and services.Incubation.inLot(tn, tr.Position) then
							return true, tr.Position
						end
						if thief:GetAttribute("Mounted") ~= nil and services.Raid and services.Raid.dragonFarFrom and services.Raid.dragonFarFrom(thief, nestPos) then
							local c = services.Movement and services.Movement.companionOf and services.Movement.companionOf(thief)
							local dp: Vector3 = if c and c.PrimaryPart then c.PrimaryPart.Position else tr.Position
							local toNest = Vector3.new(nestPos.X - dp.X, 0, nestPos.Z - dp.Z)
							local u = if toNest.Magnitude > 0.1 then toNest.Unit else Vector3.xAxis
							return true, dp + u * ((Config.Raid and Config.Raid.dragonStop) or 8)
						end
						return false, nil
					end
				end
				local ok, res = pcall(services.Combat.wakePack, p, share, function(why: string, at: Vector3?, info: any)
					onChaseEnd(p, why, at, info)
				end, safeFn, nil)
				chased = ok and res == true
				if not ok then
					warn("[GlowEgg] wakePack: " .. tostring(res))
				end
			end
			local g = gates[p]
			local dPt = dPoints[p]
			if dragonMode() then
				safeAt[p] = nil
				p:SetAttribute("GlowRaid", "dragon") -- Controllers/Hints: with the egg - to the dragon, mounted - home
				if not dPt and services.Raid and services.Raid.waitPointFor then
					dPt = services.Raid.waitPointFor(p, mm:GetAttribute("At") or mm:GetPivot().Position)
					dPoints[p] = dPt
				end
			end
			services.Net.notice(p, { kind = "glowEgg", ev = "take", element = egg.element, chase = chased, from = mm:GetPivot().Position,
				safe = GE.raid.safe or "lot", d = dPt, -- "dragon" - the path to point D and the SAFE ring at the dragon
				out = if g then g.O else nil, gate = if g then g.S else nil, home = if g then g.Pd else nil, a = if g then g.A else nil,
				mid = if g then g.S + (g.S - g.O) * 1.2 else nil, -- the path through the gate center, then to the pedestal (a dash at the gate post)
				b = if g then g.B else nil })
			if services.Analytics then
				pcall(services.Analytics.custom, p, "glow_egg_take", 1)
			end
		end
	end
end

-- Studio only (LoopDebug "glow ..."): ready - the egg on the pedestal is ready now; reset - anew
function GlowEgg.debug(p: Player, verb: string): string
	if verb == "ready" then
		services.PlayerData.update(p, "glowEgg", function(g: any)
			g = if typeof(g) == "table" then g else {}
			g.readyAt = os.time() - 1
			return g
		end)
		return "ready"
	elseif verb == "done" then -- the current egg "hatched" - on the next tick the nest of the next series egg
		services.PlayerData.update(p, "glowEgg", function(g: any)
			g = if typeof(g) == "table" then g else {}
			return { taken = os.time(), readyAt = os.time(), hatched = true, n = GlowSeries.index(g) }
		end)
		local m = eggs[p]
		if m then
			dropNest(m)
			eggs[p] = nil
		end
		if services.Combat and services.Combat.dropPack then
			services.Combat.dropPack(p)
		end
		return "done n=" .. tostring(GlowSeries.index(services.PlayerData.get(p).glowEgg))
	elseif verb == "reset" then
		services.PlayerData.update(p, "glowEgg", function()
			return { taken = 0 }
		end)
		unlocked[p], guarded[p], announced[p], returnAt[p], rearm[p], tries[p], rearmAt[p] = nil, nil, nil, nil, nil, nil, nil
		settle[p] = nil
		dPoints[p], safeAt[p] = nil, nil
		p:SetAttribute("GlowRaid", nil)
		if services.Combat and services.Combat.dropPack then
			services.Combat.dropPack(p)
		end
		return "reset"
	end
	local d = services.PlayerData.get(p)
	return game:GetService("HttpService"):JSONEncode(d and d.glowEgg or {}) .. " pack=" .. tostring(services.Combat and services.Combat.packState and services.Combat.packState(p))
		.. " tries=" .. tostring(tries[p] or 0) .. " raid=" .. tostring(raidOn[p] == true) .. " rearm=" .. tostring(rearm[p] == true)
end

function GlowEgg.init(s: { [string]: any })
	services = s
end

function GlowEgg.start()
	if not GE or not GE.on then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "GlowEggs"
	f.Parent = workspace
	folder = f
	Players.PlayerRemoving:Connect(function(p)
		for _, t in { eggs, pedestals } do
			local m = (t :: any)[p]
			if m then
				dropNest(m) -- the golden nest: the grass back too
			end
			(t :: any)[p] = nil
		end
		announced[p], guarded[p], unlocked[p], returnAt[p], rearm[p], tries[p], rearmAt[p] = nil, nil, nil, nil, nil, nil, nil
		settle[p], fresh[p] = nil, nil
		gates[p], nestAt[p], raidOn[p], gateToast[p] = nil, nil, nil, nil
		dPoints[p], safeAt[p] = nil, nil
	end)
	services.Net.handle("GlowWarm", function(p: Player)
		return GlowEgg.warm(p)
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[GlowEgg] tick: " .. tostring(err))
			end
		end
	end)
	task.spawn(function() -- the raid on foot (dismount at the gate, the dragon waits) - more often than the nest tick
		local warnedAt = -math.huge
		while true do
			task.wait(0.2)
			local ok, err = pcall(raidTick)
			if not ok and os.clock() - warnedAt > 10 then
				warnedAt = os.clock()
				warn("[GlowEgg] raid: " .. tostring(err))
			end
		end
	end)
end

return GlowEgg
