--!strict
-- THE SHARED GLOOM NESTS.
-- Ring 0 - three spots on the plaza rim in the odd wedges between the lots (Core/RaidLoop.ring0Points; on foot from the first dragon),
-- ring 1 - all meadow egg spots (mounted, after the first ride), ring 2 - the cliffs and baths spots (by flight, after the first flight);
-- the summit and the islets - package 2 (spec 21). At every nest sleeps ONE guardian (Combat.placePackAt): approaching does not wake it, taking the egg (closer
-- than grab) - "!", after wake s it chases along the trail at share[attempt] of the thief's run; catches closer than catch - "CAUGHT", the egg in an arc back
-- into the nest, take again - when the guardian lay down and the thief walked rearm away. The chase finish: ring 0 - the gate of the own lot (the egg into the bowl by itself,
-- Incubation.flyHome; the bowls busy - onto the shelf); rings 1-2 - the own dragon waits approachR from the nest on the home side (point D,
-- the GlowWait attribute - the client Companion): ran closer than mountR - mounted by itself (Movement.mount), the guardian stops at dragonStop from the dragon and
-- goes to sleep, "SAFE!", home by air, at the lot the egg into the bowl. Raid eggs hatch fast (Config.Raid.hatchSeconds).
-- The raid: closer than approachR to a nest with an egg - on foot only (dismount, no saddle); with a ring-0 egg - on foot all the way home.
-- The profile: data.raid.home - eggs brought home (the GlowEgg golden nest after Glow.egg.afterRaids). Analytics raid_take / raid_home /
-- raid_caught / raid_safe / raid_lost (the ring, the attempt, seconds, the smallest gap).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Eggs = require(Core:WaitForChild("Eggs"))
local RaidLoop = require(Core:WaitForChild("RaidLoop"))

local Raid = {}

local R = Config.Raid
local B = Config.Balance
local TICK = 0.2

type RNest = { id: string, ring: number, pos: Vector3, zone: string, key: string, gateRef: Vector3, model: Model?, eggModel: Model?,
	egg: any?, readyAt: number, holder: Player?, rearm: { [Player]: boolean }, tries: { [Player]: number } }
type Run = { nest: RNest, ring: number, egg: any, startedAt: number, safe: boolean, tries: number, gateToast: boolean, daily: number? }

local services: { [string]: any } = {}
local nests: { RNest } = {}
local byKey: { [string]: RNest } = {}
local runs: { [Player]: Run } = {}
local waits: { [Player]: { [string]: Vector3 } } = {} -- GlowWait sources: raid / glow
local ctx: { [Player]: RNest? } = {} -- the raid nest (closer than raidR) until the player leaves it
local toastAt: { [Player]: number } = {}
local seen: { [Player]: boolean } = {} -- the first tick of the player's session has already passed (a raid egg in hand without a run - an orphan)
local folder: Folder? = nil
local debugOff = false
local rng = Random.new()
local function r01(): number
	return rng:NextNumber()
end

local function root(p: Player): BasePart?
	local ch = p.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function flat(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

local function analytics(p: Player, name: string, value: number, extra: { [string]: any }?)
	if services.Analytics then
		pcall(services.Analytics.custom, p, name, value, extra)
	end
	-- before the first dragon the raid events go into the profile analytics.r1: a count by kind (take
	-- caught, home, lost, safe...), the first theft (t1) and the last event (last, lastT) in playSeconds; in place / moving and the closeness to the
	-- nest are written by Services/Analytics; read by tools/zones_scan.py
	local data = services.PlayerData.get(p)
	local nOrder = if typeof(data) == "table" and typeof(data.nestOrder) == "table" then #data.nestOrder else -1
	-- the daily raids of the first two sessions too - analytics.rd
	local key = if nOrder == 0 then "r1" elseif nOrder > 0 and (tonumber(data.sessions) or 99) <= 2 then "rd" else nil
	if key and string.sub(name, 1, 5) == "raid_" then
		local ev = string.sub(name, 6)
		local t = math.floor(tonumber(data.playSeconds) or 0)
		pcall(services.PlayerData.update, p, "analytics", function(a: any)
			a = if typeof(a) == "table" then a else {}
			local r1 = if typeof(a[key]) == "table" then a[key] else {}
			r1[ev] = (tonumber(r1[ev]) or 0) + 1
			if ev == "take" and not r1.t1 then
				r1.t1 = t
			end
			r1.last, r1.lastT = ev, t
			a[key] = r1
			return a
		end)
	end
end

local function notice(p: Player, payload: { [string]: any })
	payload.kind = "raid"
	services.Net.notice(p, payload)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function homeNest(p: Player): Model?
	return services.Nest and services.Nest.of(p) or nil
end

local function gateOf(p: Player): any
	return if services.GlowEgg and services.GlowEgg.gateOf then services.GlowEgg.gateOf(p) else nil
end

local function inLot(p: Player): boolean
	local home = homeNest(p)
	local r = root(p)
	return home ~= nil and r ~= nil and services.Incubation.inLot(home, r.Position)
end

local function ringCfg(ring: number): any
	return RaidLoop.ringCfg(R, ring)
end

local function dragonsOf(data: any): number
	return if typeof(data.nestOrder) == "table" then #data.nestOrder else 0
end

-- the UTC day of daily raids
local function today(): string
	return os.date("!%Y-%m-%d") :: string
end

-- raid eggs left today for a player with a dragon; nil - no dragons (the first egg) or no daily raids
local function dayLeft(data: any): number?
	if dragonsOf(data) < 1 then
		return nil
	end
	return RaidLoop.dayLeft(R.daily, data.raid, today())
end

-- the Gloom nests give an egg: without dragons - the first one; on the one-dragon day (firstEggOnly) with a dragon - until the daily limit runs out
-- the raid radius at the nest (dismount, no saddle, the dragon waits at the gate): approachR for a newcomer; with a dragon on daily raids - dismountR
-- (the nest is on the plaza rim - riding past along the plaza does not dismount, only coming right up to the egg)
local function nearR(data: any, ring: number): number
	if ring == 0 and R.daily and R.daily.dismountR and dragonsOf(data) >= 1 then
		return R.daily.dismountR
	end
	return R.approachR
end

-- there is room at home - a free bowl or the shelf is not full; otherwise a raid egg
-- is not given (other egg sources give coins with a full shelf, the raid put it onto the shelf beyond the room - the egg vanished from view)
local function homeRoom(data: any): boolean
	local e = data.eggs
	if typeof(e) ~= "table" then
		return true
	end
	local busy = 0
	for _ in (if typeof(e.incubating) == "table" then e.incubating else {}) :: any do
		busy += 1
	end
	if busy < (tonumber(data.incubators) or 1) then
		return true
	end
	local shelf = if typeof(e.shelf) == "table" then #e.shelf else 0
	return shelf < (tonumber(data.shelfCap) or B.shelf.start)
end

local function mayRaid(data: any): boolean
	if not R.firstEggOnly or dragonsOf(data) < 1 then
		return true
	end
	local left = dayLeft(data)
	return left ~= nil and left > 0
end

-- ---------------------------------------------------------------------------------------------- the nest and the egg
local function buildNest(n: RNest)
	local m = Instance.new("Model")
	m.Name = "RaidNest_" .. n.id
	m.PrimaryPart = services.GlowEgg.nestModel(m, n.pos, 3.2, true) -- a dark woven nest (like the golden one, the Gloom palette)
	m:SetAttribute("Ring", n.ring)
	m:SetAttribute("NestId", n.id)
	m:SetAttribute("HasEgg", false)
	m:SetAttribute("ReadyAt", 0)
	m:SetAttribute("At", n.pos)
	CollectionService:AddTag(m, "RaidNest")
	m.Parent = folder
	n.model = m
end

-- the egg in the nest: the element model, light and sparks in the rarity color (visible from afar), the label "<rarity> egg"
local function showEgg(n: RNest)
	if n.eggModel then
		n.eggModel:Destroy()
		n.eggModel = nil
	end
	local m = n.model
	if not m then
		return
	end
	local egg = n.egg
	if not egg then
		m:SetAttribute("HasEgg", false)
		m:SetAttribute("Rarity", nil)
		return
	end
	local okE, em = pcall(function()
		return services.WorldBuilder.makeEgg(egg.element, 3)
	end)
	if not okE or not em then
		warn("[Raid] makeEgg: " .. tostring(em))
		return
	end
	em.Name = "Egg"
	local cf, size = em:GetBoundingBox()
	em:PivotTo(em:GetPivot() + (n.pos + Vector3.new(0, 0.8, 0) - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
	for _, d in em:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	local body = em.PrimaryPart or em:FindFirstChildWhichIsA("BasePart", true)
	local col = rgb((Content.RarityColors :: any)[egg.rarity] or { 255, 255, 255 })
	if body then
		local l = Instance.new("PointLight")
		l.Color = col
		l.Range = R.eggGlow.range
		l.Brightness = R.eggGlow.brightness
		l.Shadows = false
		l.Parent = body
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = 8
		pe.Lifetime = NumberRange.new(0.8, 1.4)
		pe.Speed = NumberRange.new(1, 3)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new(0.4, 0)
		pe.Color = ColorSequence.new(col)
		pe.LightEmission = 1
		pe.Parent = body
		if services.WorldBuilder.label then
			local okL, g = pcall(services.WorldBuilder.label, body, Loc.text(Strings.Raid.eggLabel, { rarity = Loc.text(Strings.Rarity[egg.rarity] or egg.rarity) }), nil, 3.6, 120, R.labelDistance)
			if okL and g then
				local tl = (g :: Instance):FindFirstChildWhichIsA("TextLabel")
				if tl then
					tl.TextColor3 = col
				end
			end
		end
	end
	em.Parent = m
	n.eggModel = em
	m:SetAttribute("HasEgg", true)
	m:SetAttribute("Rarity", egg.rarity)
end

local function rollEgg(n: RNest)
	local rc = ringCfg(n.ring)
	local egg: any
	if rc and rc.rarity then -- ring 0: its own table (Common 85 / Uncommon 15)
		local rarity = RaidLoop.rarity(rc.rarity, r01, Config.Rarities)
		egg = Eggs.rollGuaranteed("raid_" .. n.id, rc.zone or n.zone, rarity, r01, B, Config.Elements)
		egg.rarity = rarity
	else -- rings 1-2: the table of the spot's zone (meadow / cliffs / baths)
		egg = Eggs.roll("raid_" .. n.id, n.zone, false, r01, B, Config.Elements)
	end
	egg.raid = n.ring
	egg.nestId = n.id
	egg.rareNest = false
	egg.foundAt = os.time()
	n.egg = egg
	showEgg(n)
end

-- the guardian sleeps at the nest (none - place again; combat still loading - a retry on the tick)
local function syncGuard(n: RNest)
	if not services.Combat or not services.Combat.placePackAt then
		return
	end
	if services.Combat.packStateAt(n.key) ~= nil then
		return
	end
	if services.Combat.modelsReady and not services.Combat.modelsReady() then
		return -- the Gloom models are still loading (the server's first seconds): a guardian with the real model, not a ball
	end
	local rc = ringCfg(n.ring)
	local g = rc and rc.guard
	if not g then
		return
	end
	services.Combat.placePackAt(n.key, n.pos, n.gateRef, { kind = g.kind, scale = g.scale, name = g.name, count = 1, spots = { { g.lair or 5, 0 } },
		wake = g.wake, catch = g.catch, lose = g.lose, maxSec = g.maxSec, gateHold = R.gateHold, returnSpeed = R.returnSpeed, minSpeed = R.minSpeed,
		retreat = 2.5, fade = false })
end

-- ---------------------------------------------------------------------------------------------- waiting for the dragon (GlowWait)
-- one attribute per player is shared by Services/GlowEgg (the golden nest, src "glow") and the raids (src "raid")
function Raid.wait(p: Player, src: string, v: Vector3?)
	local w = waits[p]
	if not w then
		w = {}
		waits[p] = w
	end
	w[src] = v
	local want = w.raid or w.glow
	if p:GetAttribute("GlowWait") ~= want then
		p:SetAttribute("GlowWait", want)
	end
end

-- point D: approachR from the nest toward the own lot gate - the first level and empty spot (the GlowEgg.probe measurement) among
-- the candidates: straight toward home, at +-30 / +-60 deg, at 35 / 30 / 25 (no closer than approachR - 10: otherwise the finish at the dragon does not count);
-- nothing found - the computed point on the ground. at the cliffs and baths the straight line home runs into boulders
local function waitPoint(p: Player, n: RNest): Vector3
	local g = gateOf(p)
	local hx, hz = 0, 0
	if g then
		hx, hz = g.S.X, g.S.Z
	end
	local base = math.atan2(hz - n.pos.Z, hx - n.pos.X)
	local probe = services.GlowEgg and services.GlowEgg.probe
	if probe then
		for _, dist in { R.approachR, R.approachR - 5, R.approachR - 10 } do
			for _, da in { 0, 30, -30, 60, -60 } do
				local a = base + math.rad(da)
				local x, z = n.pos.X + math.cos(a) * dist, n.pos.Z + math.sin(a) * dist
				local at, dh = probe(x, z, true)
				if at and dh <= (R.waitFlatMax or 2.5) then
					return at :: Vector3
				end
			end
		end
	end
	local x, z = RaidLoop.waitPoint(n.pos.X, n.pos.Z, hx, hz, R.approachR)
	return Vector3.new(x, n.pos.Y, z)
end

-- ---------------------------------------------------------------------------------------------- the raid
-- the egg of this raid in hand (by fields, not by table identity: the profile may be copied)
local function holdsEgg(data: any, run: Run): boolean
	local c = data and data.eggs and data.eggs.carry
	return typeof(c) == "table" and c.raid ~= nil and c.nestId == run.nest.id
end

local function clearRun(p: Player)
	local run = runs[p]
	runs[p] = nil
	if run then
		run.nest.holder = nil
	end
end

local function dropCarry(p: Player, egg: any)
	services.PlayerData.update(p, "eggs", function(e: any)
		if e.carry == egg or (typeof(e.carry) == "table" and e.carry.raid ~= nil and e.carry.nestId == egg.nestId) then
			e.carry = nil
		end
		return nil
	end)
	if services.EggSpawner then
		services.EggSpawner.showCarry(p, nil)
	end
end

-- the egg at home: into a free bowl in an arc, the bowls busy - onto the shelf; the nest refills after respawn
local function onHome(p: Player, run: Run, already: boolean)
	local n = run.nest
	local data = services.PlayerData.get(p)
	local sec = math.floor((os.clock() - run.startedAt) * 10 + 0.5) / 10
	local toShelf = false
	if not already and data and holdsEgg(data, run) then
		local flew = services.Incubation.flyHome and services.Incubation.flyHome(p)
		if not flew then
			services.PlayerData.update(p, "eggs", function(e: any)
				if typeof(e.carry) == "table" and e.carry.raid ~= nil and e.carry.nestId == run.nest.id then
					e.shelf = e.shelf or {}
					table.insert(e.shelf, e.carry)
					e.carry = nil
					toShelf = true
				end
				return nil
			end)
			if toShelf then
				if services.EggSpawner then
					services.EggSpawner.showCarry(p, nil)
				end
				if services.Incubation.syncShelfOf then
					pcall(services.Incubation.syncShelfOf, p)
				end
			end
		end
	end
	local left: number? = nil
	services.PlayerData.update(p, "raid", function(rd: any)
		rd = if typeof(rd) == "table" then rd else {}
		rd.home = (tonumber(rd.home) or 0) + 1
		if run.daily then -- a daily raid - the day counter (the day changed during the run - count in the new one)
			local day = today()
			rd.dayN = RaidLoop.dayDone(rd, day) + 1
			rd.day = day
			left = RaidLoop.dayLeft(R.daily, rd, day)
		end
		return rd
	end)
	n.tries[p] = nil
	n.rearm[p] = nil
	clearRun(p)
	local rc = ringCfg(n.ring)
	n.readyAt = os.clock() + (rc and rc.respawn or 60)
	notice(p, { ev = "home", ring = n.ring, rarity = run.egg.rarity, t = RaidLoop.hatchSeconds(R, run.egg.rarity) or 0, shelf = toShelf, left = left,
		daily = run.daily, of = if run.daily and R.daily then R.daily.eggs else nil })
	analytics(p, "raid_home", sec, { ring = n.ring, tries = run.tries, rarity = run.egg.rarity, safe = run.safe, daily = run.daily })
end

local function onCaught(p: Player, run: Run, at: Vector3?, info: any)
	local n = run.nest
	run.tries += 1
	n.tries[p] = run.tries
	n.rearm[p] = true
	dropCarry(p, run.egg)
	local egg = run.egg
	clearRun(p)
	n.holder = p -- the egg flies back: the nest is busy until it arrives
	if n.model then
		n.model:SetAttribute("Returning", true) -- the client hint does not jump to another nest
	end
	local to = n.pos + Vector3.new(0, 1.6, 0)
	notice(p, { ev = "caught", from = at, to = to, seconds = R.arc })
	analytics(p, "raid_caught", typeof(info) == "table" and info.sec or 0, { ring = n.ring, tries = run.tries, gap = typeof(info) == "table" and info.gap or -1 })
	task.delay(R.arc, function()
		if n.model then
			n.model:SetAttribute("Returning", nil)
		end
		if n.holder == p and not runs[p] then
			n.holder = nil
			n.egg = egg
			showEgg(n)
		end
	end)
end

local function onChaseEnd(p: Player, why: string, at: Vector3?, info: any)
	local run = runs[p]
	if not run or p.Parent ~= Players then
		return
	end
	local data = services.PlayerData.get(p)
	if not data or not holdsEgg(data, run) then
		return -- the egg is already home / left the hands (the tick sorts it out)
	end
	if why == "caught" then
		onCaught(p, run, at, info)
	elseif why == "lost" then
		notice(p, { ev = "escaped" })
		analytics(p, "raid_lost", typeof(info) == "table" and info.sec or 0, { ring = run.ring, tries = run.tries })
	elseif why == "home" then
		if inLot(p) then
			onHome(p, run, false)
		else
			-- rings 1-2: reached the own dragon - the guardian stopped, "SAFE!", home by air
			run.safe = true
			Raid.wait(p, "raid", nil)
			notice(p, { ev = "safe", ring = run.ring, rarity = run.egg.rarity, t = RaidLoop.hatchSeconds(R, run.egg.rarity) or 0 })
			analytics(p, "raid_safe", typeof(info) == "table" and info.sec or 0, { ring = run.ring, tries = run.tries, gap = typeof(info) == "table" and info.gap or -1 })
		end
	end
end

-- rings 1-2: the own dragon is the finish only if it stands no closer than approachR - 10 to the nest (otherwise one dismounts right at the nest, takes it and mounts
-- again in place - "SAFE" without a chase); while it is closer - running to it cannot mount, it goes to point D by itself
local function dragonFar(p: Player, n: RNest): boolean
	local c = services.Movement and services.Movement.companionOf and services.Movement.companionOf(p)
	local body = c and c.PrimaryPart
	return body ~= nil and flat(body.Position, n.pos) >= R.approachR - 10
end

-- the golden nest on the slope (Services/GlowEgg) follows the same rules as rings 1-2 - point D and "the dragon is not at
-- the nest" for any spot pos
function Raid.waitPointFor(p: Player, pos: Vector3): Vector3
	return waitPoint(p, { pos = pos } :: any)
end

function Raid.dragonFarFrom(p: Player, pos: Vector3): boolean
	return dragonFar(p, { pos = pos } :: any)
end

-- the chase finish (every frame from Combat): ring 0 - the own lot line; rings 1-2 - the thief mounted the own dragon (or is at home)
local function safeFor(run: Run): (Player) -> (boolean, Vector3?)
	return function(thief: Player): (boolean, Vector3?)
		local r = root(thief)
		if not r then
			return false, nil
		end
		if inLot(thief) then
			return true, r.Position
		end
		if run.ring >= 1 and thief:GetAttribute("Mounted") ~= nil and dragonFar(thief, run.nest) then
			local c = services.Movement and services.Movement.companionOf and services.Movement.companionOf(thief)
			local dp = if c and c.PrimaryPart then c.PrimaryPart.Position else r.Position
			local toNest = Vector3.new(run.nest.pos.X - dp.X, 0, run.nest.pos.Z - dp.Z)
			local u = if toNest.Magnitude > 0.1 then toNest.Unit else Vector3.xAxis
			return true, dp + u * R.dragonStop
		end
		return false, nil
	end
end

local function startRun(p: Player, n: RNest, data: any)
	local egg = n.egg
	if not egg then
		return
	end
	-- a regular egg in hand (the table, a gift) - onto the shelf at home by itself (as at the golden nest), the raid egg - into the hands
	if data.eggs.carry ~= nil then
		local held = data.eggs.carry
		services.PlayerData.update(p, "eggs", function(e: any)
			e.shelf = e.shelf or {}
			table.insert(e.shelf, held)
			e.carry = nil
			return nil
		end)
		if services.Incubation.syncShelfOf then
			pcall(services.Incubation.syncShelfOf, p)
		end
		notice(p, { ev = "toShelf" })
	end
	n.egg = nil
	n.holder = p
	showEgg(n)
	egg.foundAt = os.time()
	services.PlayerData.update(p, "eggs", function(e: any)
		e.carry = egg
		return nil
	end)
	if services.EggSpawner then
		services.EggSpawner.showCarry(p, egg)
	end
	local tries = n.tries[p] or 0
	local daily: number? = nil
	if R.firstEggOnly and R.daily and dragonsOf(data) >= 1 then
		daily = RaidLoop.dayDone(data.raid, today()) + 1 -- which egg of today this is (1..daily.eggs)
	end
	local run: Run = { nest = n, ring = n.ring, egg = egg, startedAt = os.clock(), safe = false, tries = tries, gateToast = false, daily = daily }
	runs[p] = run
	local rc = ringCfg(n.ring)
	local chased = false
	if services.Combat and services.Combat.wakePackAt and rc then
		-- the first dragon is obtained by a raid - the guardian of the first egg (no dragons yet) is softer: R.first.share by attempts
		-- wakes after R.first.wake
		local first = dragonsOf(data) == 0 and R.first ~= nil
		-- a daily raid - the guardian of the k-th egg of the day is faster (Config.Raid.daily)
		local dk = run.daily
		local share = if first then RaidLoop.share(R.first, tries) elseif dk then RaidLoop.dayShare(R.daily, dk, tries) else RaidLoop.share(rc.guard, tries)
		local wake = if first then R.first.wake elseif dk then RaidLoop.dayWake(R.daily, dk) else nil
		local ok, res = pcall(services.Combat.wakePackAt, n.key, p, share, function(why: string, at: Vector3?, info: any)
			onChaseEnd(p, why, at, info)
		end, safeFor(run), wake)
		chased = ok and res == true
		if not ok then
			warn("[Raid] wakePackAt: " .. tostring(res))
		end
	end
	local g = gateOf(p)
	local home = homeNest(p)
	local inc = home and home:FindFirstChild("Incubators")
	local i1 = inc and inc:FindFirstChild("Incubator1")
	local d: Vector3? = nil
	if n.ring >= 1 then
		local w = waits[p]
		d = w and w.raid or waitPoint(p, n)
	end
	notice(p, { ev = "take", ring = n.ring, rarity = egg.rarity, element = egg.element, chase = chased, safe = if n.ring >= 1 then "dragon" else "lot",
		from = n.pos, out = if g then g.O else nil, gate = if g then g.S else nil, a = if g then g.A else nil, b = if g then g.B else nil,
		-- the path end - 6 studs into the lot along the gate axis; the egg flies into the bowl by itself
		home = if g then g.S + (g.S - g.O) * 1.2 else (if i1 and i1:IsA("BasePart") then i1.Position else nil), d = d, t = RaidLoop.hatchSeconds(R, egg.rarity) or 0 })
	analytics(p, "raid_take", 1, { ring = n.ring, rarity = egg.rarity, tries = tries, first = dragonsOf(data) == 0, daily = daily })
end

local function endRun(p: Player, why: string)
	local run = runs[p]
	if not run then
		return
	end
	local n = run.nest
	if why == "placed" then
		onHome(p, run, true) -- the egg landed in the bowl by "just walk up" / from the shelf - that is home
		return
	end
	clearRun(p)
	if services.Combat and services.Combat.calmPackAt then
		services.Combat.calmPackAt(n.key)
	end
	local rc = ringCfg(n.ring)
	n.readyAt = os.clock() + (rc and rc.respawn or 60)
	Raid.wait(p, "raid", nil)
end

-- ---------------------------------------------------------------------------------------------- the raid: the dragon waits, on foot at the nest
local function nearestNest(pos: Vector3, data: any, withEgg: boolean, only: RNest?): (RNest?, number)
	local best: RNest? = nil
	local bd = math.huge
	local onb = data.onboarding
	local dragons = dragonsOf(data)
	for _, n in nests do
		if only and n ~= only and n.ring == only.ring then
			continue -- the own ring-0 nest (nestFor) - riding past foreign ones does not dismount
		end
		if (not withEgg or (n.egg ~= nil and n.holder == nil)) and RaidLoop.open(R, n.ring, onb, dragons) then
			local d = flat(pos, n.pos)
			if d < bd then
				best, bd = n, d
			end
		end
	end
	return best, bd
end

-- the saddle is not allowed: with a ring-0 egg (on foot home) and at a nest with an egg without an egg in hand (sneak up on foot)
function Raid.footOnly(p: Player): boolean
	local run = runs[p]
	if run then
		if run.ring == 0 then
			return not inLot(p)
		end
		return not run.safe and not dragonFar(p, run.nest) -- the dragon is still at the nest: first to point D
	end
	local n = ctx[p]
	local r = root(p)
	local data = services.PlayerData.get(p)
	if n and r and data and n.egg and n.holder == nil and not inLot(p) and flat(r.Position, n.pos) <= nearR(data, n.ring) then
		return true
	end
	return false
end

-- a newcomer gets the egg only from the ring-0 nest farthest from his
-- gate (the wedge +-150 deg from the lot axis, ~100 studs of running across the plaza); the near ones are empty for him (the client hides the eggs)
function Raid.firstNestFor(p: Player): RNest?
	local g = gateOf(p)
	if not g then
		return nil
	end
	local best: RNest? = nil
	local bestD = -1
	for _, n in nests do
		if n.ring == 0 then
			local d = flat(g.S, n.pos)
			if d > bestD then
				best, bestD = n, d
			end
		end
	end
	return best
end

-- the player's nest - for a newcomer (the first egg) and with a dragon on daily raids the same one, the farthest (run across two lots)
-- the other ring-0 nests give him no eggs and do not dismount him on the way past
local function nestFor(p: Player, data: any): RNest?
	if not R.firstEggByRaid or R.firstFar == false then
		return nil
	end
	if dragonsOf(data) == 0 or (R.firstEggOnly and mayRaid(data)) then
		return Raid.firstNestFor(p)
	end
	return nil
end

-- where the shared nests stand (GlowEgg.spotFor: the golden nest no closer than 25 to them)
function Raid.nestPositions(): { Vector3 }
	local out = {}
	for _, n in nests do
		table.insert(out, n.pos)
	end
	return out
end

-- "the raid is the core of the game" (Combat: hunts, ambushes and waves are off). With firstEggOnly the raid is only the first egg,
-- the Gloom fight runs again as live
function Raid.active(): boolean
	return R ~= nil and R.on == true and not R.firstEggOnly and not debugOff
end

function Raid.busy(p: Player): boolean
	return runs[p] ~= nil
end

local function raidTick()
	for _, p in Players:GetPlayers() do
		local r = root(p)
		local data = r and services.PlayerData.get(p)
		if not r or not data then
			ctx[p] = nil
			Raid.wait(p, "raid", nil)
			continue
		end
		local run = runs[p]
		local home = inLot(p)
		-- the golden egg in hand - the raid is driven by GlowEgg (point D at the golden nest, the finish at the dragon); the ring
		-- nests nearby neither dismount the player nor call the dragon
		local carryGlow = typeof(data.eggs) == "table" and typeof(data.eggs.carry) == "table" and data.eggs.carry.glow == true
		if carryGlow and not run then
			ctx[p] = nil
			Raid.wait(p, "raid", nil)
			continue
		end
		-- a player with a dragon on the one-dragon day is not owed nest
		-- eggs - the nests neither dismount him nor call the dragon
		-- with a dragon - while the daily limit remains (Config.Raid.daily), then as before
		if not run and not mayRaid(data) then
			ctx[p] = nil
			Raid.wait(p, "raid", nil)
			continue
		end
		local n: RNest? = nil
		if run then
			n = run.nest
		else
			-- the raid nest: with the egg or with the egg flying back (holder) - after CAUGHT the dragon does not rush from point D to the player
			local cur = ctx[p]
			if cur and (cur.egg ~= nil or cur.holder ~= nil) and flat(r.Position, cur.pos) <= R.raidR then
				n = cur -- hold on to the current nest until we leave its zone
			else
				local nn, d = nearestNest(r.Position, data, true, nestFor(p, data))
				n = if nn and d <= R.raidR then nn else nil
			end
		end
		ctx[p] = n
		if not n or home then
			Raid.wait(p, "raid", nil)
			continue
		end
		local dN = flat(r.Position, n.pos)
		-- a raid = a raid egg in hand or on foot at a nest (closer than approachR) that has an egg or one flying back; just walking past
		-- a nest on the plaza - the dragon stays nearby as always
		local nr = nearR(data, n.ring)
		local near = run ~= nil or (dN <= nr and (n.egg ~= nil or n.holder ~= nil))
		local want: Vector3? = nil
		if not near then
			want = nil
		elseif n.ring == 0 then
			local g = gateOf(p)
			want = if g then g.W else nil
		elseif not (run and run.safe) then
			local w = waits[p]
			want = if w and w.raid and (run ~= nil or flat(w.raid, n.pos) < R.approachR + 2) then w.raid else waitPoint(p, n)
		end
		Raid.wait(p, "raid", want)
		-- on foot: with a ring-0 egg or closer than approachR to a nest with an egg; mounted - dismount (one toast per nest)
		-- dN - in the plane, a flyover above the nest at height dismounted in the air;
		-- the dismount only near the nest's ground (no farther than 8 in height)
		local lowNear = dN <= nr and math.abs(r.Position.Y - n.pos.Y) < 8
		local foot = (run ~= nil and run.ring == 0) or (run == nil and lowNear)
		if foot and p:GetAttribute("Mounted") ~= nil and services.Movement and services.Movement.dismount then
			local ok, rep = pcall(services.Movement.dismount, p)
			if ok and rep and rep.ok then
				if os.clock() - (toastAt[p] or 0) > 8 then
					toastAt[p] = os.clock()
					notice(p, { ev = "gate", ring = n.ring })
				end
				analytics(p, "raid_dismount", 1, { ring = n.ring })
			end
		end
		-- rings 1-2 with the egg: reached the own dragon - mounted by itself (the chase finish is decided by the guardian by Mounted)
		if run and run.ring >= 1 and not run.safe and p:GetAttribute("Mounted") == nil and services.Movement and services.Movement.mount and dragonFar(p, run.nest) then
			local c = services.Movement.companionOf and services.Movement.companionOf(p)
			local body = c and c.PrimaryPart
			if body and (body.Position - r.Position).Magnitude <= R.mountR + body.Size.Magnitude / 2 and typeof(data.companion) == "string" then
				local ok, rep = pcall(services.Movement.mount, p, data.companion)
				if ok and rep and rep.ok then
					analytics(p, "raid_automount", 1, { ring = run.ring })
				end
			end
		end
	end
end

local function tick()
	local now = os.clock()
	for _, n in nests do
		local okG, errG = pcall(syncGuard, n)
		if not okG then
			warn("[Raid] guard " .. n.id .. ": " .. tostring(errG))
		end
		if n.egg == nil and n.holder == nil and now >= n.readyAt then
			local okE, errE = pcall(rollEgg, n)
			if not okE then
				warn("[Raid] egg " .. n.id .. ": " .. tostring(errE))
				n.readyAt = now + 5
			end
		end
		local m = n.model
		if m then
			local ra = if n.egg == nil and n.holder == nil then workspace:GetServerTimeNow() + math.max(0, n.readyAt - now) else 0
			if math.abs((tonumber(m:GetAttribute("ReadyAt")) or 0) - ra) > 0.6 then
				m:SetAttribute("ReadyAt", ra)
			end
		end
	end
	-- running raids: the egg at home (just walk up / the shelf), left the hands, the player left
	for p, run in runs do
		local data = services.PlayerData.get(p)
		if p.Parent ~= Players or not data then
			endRun(p, "left")
		elseif not holdsEgg(data, run) then
			endRun(p, "placed")
		elseif inLot(p) then
			onHome(p, run, false)
		end
	end
	-- grab: closer than grab to the egg of an open ring's nest (not mounted - the raid tick dismounts at the nest)
	if debugOff then
		return
	end
	for _, p in Players:GetPlayers() do
		local data = services.PlayerData.get(p)
		if not data then
			continue
		end
		-- left the game with a raid egg in hand - the run was removed, the profile kept the egg; on join - out of the hands (the nest
		-- refills by itself). Only in the first tick of the session: later a carry without a run can be legitimate (the egg flies into the bowl, Incubation.flyHome)
		if not seen[p] then
			seen[p] = true
			local c = data.eggs and data.eggs.carry
			if typeof(c) == "table" and c.raid ~= nil and not runs[p] then
				dropCarry(p, c)
				analytics(p, "raid_orphan", 1, { ring = c.raid })
			end
		end
		local dragons = dragonsOf(data)
		-- the assigned nest - the FirstNest attribute (the client hides the other eggs); on daily raids too
		-- RaidLeft - raid eggs left today (the client: the arrow, the label "1/4 today", the nest eggs are visible while > 0)
		local firstNest: RNest? = nestFor(p, data)
		local fid = if firstNest then firstNest.id else nil
		if p:GetAttribute("FirstNest") ~= fid then
			p:SetAttribute("FirstNest", fid)
		end
		local left = if R.firstEggOnly then dayLeft(data) else nil
		if p:GetAttribute("RaidLeft") ~= left then
			p:SetAttribute("RaidLeft", left)
		end
		if runs[p] then
			continue
		end
		local r = root(p)
		if not r or p:GetAttribute("Mounted") ~= nil then
			continue
		end
		if typeof(data.eggs.carry) == "table" and data.eggs.carry.glow == true then
			continue -- the golden egg is in hand (GlowEgg): home first, the raid does not take it onto the shelf
		end
		local onb = data.onboarding
		if not mayRaid(data) then
			continue -- (section 16): with a dragon - only while the daily limit remains; the egg in the nest is invisible to him (the client) and not taken
		end
		for _, n in nests do
			if n.egg and n.holder == nil and RaidLoop.open(R, n.ring, onb, dragons) then
				if firstNest and n ~= firstNest then
					continue -- the first egg - only from the far nest (across two lots)
				end
				local d = flat(r.Position, n.pos)
				if n.rearm[p] and d > R.rearm then
					n.rearm[p] = nil -- walked away after the capture - allowed again
				end
				local st = services.Combat and services.Combat.packStateAt and services.Combat.packStateAt(n.key)
				if not n.rearm[p] and d <= R.grab and math.abs(r.Position.Y - n.pos.Y) < 8 and (st == "sleep" or st == nil) then
					if dragons >= 1 and not homeRoom(data) then
						if os.clock() - (toastAt[p] or 0) > 8 then
							toastAt[p] = os.clock()
							notice(p, { ev = "noRoom" })
						end
						break
					end
					local ok, err = pcall(startRun, p, n, data)
					if not ok then
						warn("[Raid] take " .. n.id .. ": " .. tostring(err))
					end
					break
				end
			end
		end
	end
end

-- Studio only (LoopDebug "raid ...", P8 probes): the state, a teleport to a ring egg / home, a reset
function Raid.debug(p: Player, verb: string, arg: string): string
	local function moveTo(at: Vector3): string
		if p:GetAttribute("Mounted") ~= nil and services.Movement then
			local function q(v: number): string
				return (string.gsub(tostring(math.floor(v + 0.5)), "%-", "n"))
			end
			return tostring((services.Movement.debug(p, "warp", q(at.X) .. "x" .. q(at.Y) .. "x" .. q(at.Z)) or {}).ok)
		end
		local ch = p.Character
		if ch then
			ch:PivotTo(CFrame.new(at))
			return "true"
		end
		return "false"
	end
	if verb == "off" or verb == "on" then
		debugOff = verb == "off"
		return "raid " .. verb
	elseif verb == "go" then
		local ring = tonumber(arg) or 0
		local r = root(p)
		local best: RNest? = nil
		local bd = math.huge
		for _, n in nests do
			if n.ring == ring and n.egg and n.holder == nil then
				local d = if r then flat(r.Position, n.pos) else 0
				if d < bd then
					best, bd = n, d
				end
			end
		end
		if best then
			local g = gateOf(p)
			local u = if g then Vector3.new(g.S.X - best.pos.X, 0, g.S.Z - best.pos.Z) else Vector3.new(-best.pos.X, 0, -best.pos.Z)
			u = if u.Magnitude > 0.1 then u.Unit else Vector3.xAxis
			local dist = if ring >= 1 then R.approachR - 5 else 6
			local q = best.pos + u * dist
			local at = if services.GlowEgg and services.GlowEgg.probe then (services.GlowEgg.probe(q.X, q.Z, true)) else nil
			return "go " .. best.id .. " " .. moveTo((if at then at :: Vector3 else q) + Vector3.new(0, 3, 0))
		end
		return "no egg in ring " .. tostring(ring)
	elseif verb == "home" then
		local g = gateOf(p)
		if g then
			return "home " .. moveTo(g.Pd + Vector3.new(0, 3, 0)) -- into the lot (right on the line inLot does not count)
		end
		return "no home"
	elseif verb == "reset" then
		endRun(p, "left")
		for _, n in nests do
			n.tries[p] = nil
			n.rearm[p] = nil
			if n.egg == nil and n.holder == nil then
				n.readyAt = 0
			end
		end
		services.PlayerData.update(p, "raid", function()
			return { home = 0 }
		end)
		return "reset"
	end
	local run = runs[p]
	local eggs = {}
	for _, n in nests do
		table.insert(eggs, n.id .. "=" .. (if n.egg then n.egg.rarity elseif n.holder then "held" else string.format("%.0fs", math.max(0, n.readyAt - os.clock()))) .. "/" .. tostring(services.Combat and services.Combat.packStateAt and services.Combat.packStateAt(n.key)))
	end
	local d = services.PlayerData.get(p)
	return string.format("run=%s ring=%s safe=%s tries=%s wait=%s foot=%s home=%s | %s", tostring(run ~= nil), run and tostring(run.ring) or "-",
		tostring(run and run.safe), tostring(run and run.tries), tostring(p:GetAttribute("GlowWait")), tostring(Raid.footOnly(p)),
		tostring(d and typeof(d.raid) == "table" and d.raid.home or 0), table.concat(eggs, " "))
end

function Raid.init(s: { [string]: any })
	services = s
end

function Raid.start()
	if not R or not R.on then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "RaidNests"
	f.Parent = workspace
	folder = f
	while #services.WorldBuilder.nests < Config.World.nests.count or next(services.WorldBuilder.eggPoints) == nil do
		task.wait(0.25)
	end
	task.wait(1.5) -- the spots and the plaza are built in a batch; GlowEgg.probe measures the plaza floor
	local centre = Vector3.new(0, Config.World.terrace.y, 0)
	for _, pt in RaidLoop.ring0Points(R, Config.World) do -- ring 0: the plaza rim, the spot by measurement (level, empty around)
		local at: Vector3? = nil
		for _, off in { { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 }, { 5, 5 }, { -5, -5 } } do
			local q, dh = services.GlowEgg.probe(pt.x + off[1], pt.z + off[2], true)
			if q and dh <= 1.5 then
				at = q
				break
			end
		end
		if not at then
			warn("[Raid] ring 0: no level spot found at " .. pt.id .. " - placing by computation")
			at = Vector3.new(pt.x, Config.World.terrace.y, pt.z)
		end
		-- the guardian's resting spot: ring 0 - INWARD, toward the plaza center (thieves come from the lots, from outside): placePackAt puts the spot on the side away from
		-- gateRef, so the reference is a point outside the nest. with the spot outside a thief 3 studs from the nest was 4.8 from
		-- the guardian - CAUGHT in the very first frame of the chase
		local pp = at :: Vector3
		local outward = Vector3.new(pp.X, 0, pp.Z)
		outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.xAxis
		local n: RNest = { id = pt.id, ring = 0, pos = pp, zone = "Meadow", key = "raid:" .. pt.id, gateRef = pp + outward * 20, readyAt = 0, rearm = {}, tries = {} }
		buildNest(n)
		table.insert(nests, n)
		byKey[n.key] = n
	end
	for id, anchor in services.WorldBuilder.eggPoints do -- rings 1-2: the egg spots of the meadow and the baths
		if anchor:IsA("BasePart") and services.EggSpawner and services.EggSpawner.raidPoint and services.EggSpawner.raidPoint(anchor) then
			local zone = tostring(anchor:GetAttribute("Zone") or "Meadow")
			local ring = RaidLoop.ringOfZone(R, zone)
			local rcz = ring and RaidLoop.ringCfg(R, ring)
			if ring and rcz and rcz.open ~= "off" then -- a switched-off ring - no nests, the spots stay free eggs
				local pos: Vector3? = anchor.Position
				if zone == "Springs" then -- the bath rims - a nest only on a level and empty spot (measurement), otherwise a spot without a nest
					pos = nil
					for _, off in { { 0, 0 }, { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } } do
						local q, dh = services.GlowEgg.probe(anchor.Position.X + off[1], anchor.Position.Z + off[2], true)
						if q and dh <= (R.springsFlatMax or 2.5) then
							pos = q
							break
						end
					end
					if not pos then
						warn("[Raid] baths: no level spot at point " .. id .. " - not placing a nest")
					end
				end
				if pos then
					for _, c in anchor:GetChildren() do
						if c:IsA("Model") or c:IsA("BillboardGui") then
							c:Destroy() -- the WorldBuilder placeholder
						end
					end
					local n: RNest = { id = id, ring = ring, pos = pos :: Vector3, zone = zone, key = "raid:" .. id, gateRef = Vector3.new(0, (pos :: Vector3).Y, 0), readyAt = 0, rearm = {}, tries = {} }
					buildNest(n)
					table.insert(nests, n)
					byKey[n.key] = n
				end
			end
		end
	end
	-- the cliff nests - at the foot, in front of the boulders, the spot by measurement
	for _, pt in RaidLoop.footPoints(R) do
		local rc = RaidLoop.ringCfg(R, pt.ring)
		if rc and rc.open == "off" then
			continue -- the ring is off
		end
		local f = rc and rc.foot
		local at: Vector3? = nil
		if f then
			for _, off in f.offsets do
				local q, dh = services.GlowEgg.probe(pt.x + off[1], pt.z + off[2], false)
				if q and dh <= (f.flatMax or 2) then
					at = q
					break
				end
			end
		end
		if at and f then
			local n: RNest = { id = pt.id, ring = pt.ring, pos = at :: Vector3, zone = f.zone, key = "raid:" .. pt.id, gateRef = Vector3.new(0, (at :: Vector3).Y, 0), readyAt = 0, rearm = {}, tries = {} }
			buildNest(n)
			table.insert(nests, n)
			byKey[n.key] = n
		else
			warn("[Raid] the cliff foot: no level spot at " .. pt.id .. " - not placing a nest")
		end
	end
	table.sort(nests, function(a, b)
		return a.id < b.id
	end)
	Players.PlayerRemoving:Connect(function(p)
		if runs[p] then
			endRun(p, "left")
		end
		waits[p], ctx[p], toastAt[p], seen[p] = nil, nil, nil, nil
		for _, n in nests do
			n.tries[p], n.rearm[p] = nil, nil
		end
	end)
	task.spawn(function()
		while true do
			task.wait(TICK)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Raid] tick: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		local warnedAt = -math.huge
		while true do
			task.wait(TICK)
			local ok, err = pcall(raidTick)
			if not ok and os.clock() - warnedAt > 10 then
				warnedAt = os.clock()
				warn("[Raid] wait: " .. tostring(err))
			end
		end
	end)
end

return Raid
