--!strict
-- Combat ("Sky guardians"): every player has two Gloom arenas - the meadow under the ledge of their nest (stages 1-5, the guardian
-- Gloom Warden) and the sky above it at the islet height (6-10, the guardian Storm Gloom, flight only). A wave lives while its owner is near.
-- A breath hit (Remote Breath, the enemy id) is computed by the server: cooldown, range, muting (a Gloom touch, the guardian's pulse),
-- the power from the profile (Core/Combat.power). Dispersed Gloom - a flash of light on the clients (CombatFx), coins per wave, an egg and
-- a badge for the guardian; foreign damage to a wave is credited to the helper with a share of the reward. Gloom models - parts in code (no store ones).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Core = Shared:WaitForChild("Core")
local CombatCore = require(Core:WaitForChild("Combat"))
local Economy = require(Core:WaitForChild("Economy"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Eggs = require(Core:WaitForChild("Eggs"))
local IndexCore = require(Core:WaitForChild("Index"))
local Growth = require(Core:WaitForChild("Growth"))

local Combat = {}

local C = Config.Combat
local B = Config.Balance
local G = C.guardianFx

type Enemy = {
	id: string,
	model: Model,
	body: BasePart,
	hp: number,
	maxHp: number,
	owner: Player,
	wave: any,
	guardian: boolean,
	home: Vector3, -- the point in the wave formation (the drift returns to it)
	radius: number,
	kind: string, -- shardling | hound | warden (Config.Combat.models)
	attackAt: number, -- os.clock() of the next attack
	busyUntil: number, -- the hound's dash: the drift stands still
	rush: boolean?, -- runs toward the player at hunt.rush speed until it gets close
	-- moves every frame (movePacks), not a breath target
	-- wakeAt - when it will move; lift - the body center above the player's root; parts - the visible parts and their transparency (melts at the end)
	chase: boolean?,
	wakeAt: number?,
	lift: number?,
	parts: { [BasePart]: number }?,
	hover: number?, -- guards - the height above the ground, holds on slopes
}
type Wave = {
	arena: string,
	stage: number,
	replay: boolean,
	center: Vector3,
	enemies: { [string]: Enemy },
	left: number,
	hpTotal: number,
	dealt: { [Player]: number },
	startedAt: number,
	deadline: number?,
	serverEnd: number?, -- workspace:GetServerTimeNow() of the guardian timer end (the client compares with its own GetServerTimeNow)
	pulses: number,
	warned: number,
	near: boolean?, -- it reached the player (ambush / hunt) - counts toward the waves and the fight seconds even without a hit
	onEnd: ((string, Vector3?) -> ())?, -- "caught" (the capture point) / "lost" / "home" - Services/GlowEgg
	over: number?, -- os.clock() of the end - the Gloom floats back to the nest and melts
	nest: Model?, -- the nest owner's lot (the own lot - the chase is over)
}
type PState = {
	waves: { [string]: Wave? },
	nextAt: { [string]: number },
	farSince: { [string]: number? },
	lastHit: number,
	muteUntil: number,
	touchAt: number?, -- the last Gloom touch (Config.Combat.enemy.touchEvery)
	joinedAt: number, -- os.clock() of the state's appearance (the player's join)
	ambushed: boolean?, -- the first ambush after the hatch already happened in this session
	progKey: string?, -- the progress "fingerprint" (progressKey) and when it last changed
	progAt: number?,
	boredAt: number?, -- os.clock() of the last boredom ambush
	busyAt: number?, -- os.clock() when the client reported "menu/scene" (UiBusy); nil - free
	lastEnd: number?, -- os.clock() of the end of the player's last wave (cleared or gone)
	huntAt: number?, -- when the announced wave appears (after the warning)
	huntArena: string?,
	-- the menu closing, the past waves { start, end }, the first ride / the first flight in this
	-- session (the moment the onboarding flag flips), the start of the last replay, the reason of the last hunt decision (combat info)
	busyEnd: number?,
	hist: { { number } },
	rodeAt: number?,
	flewAt: number?,
	rodeWas: boolean?,
	flewWas: boolean?,
	huntWhy: string?,
}

local services: { [string]: any } = {}
local states: { [Player]: PState } = {}
local enemies: { [string]: Enemy } = {}
local nextId = 0
local folder: Folder? = nil
local ready = true -- the enemy models are loaded (Combat.start)
local fx: RemoteEvent? = nil
local rng = Random.new()
local why: { [string]: number } = {} -- the hit counter: accepted and the refusal reasons (combat info for P8 probes)
local function count(k: string)
	why[k] = (why[k] or 0) + 1
end
local function r01(): number
	return rng:NextNumber()
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function state(player: Player): PState
	local s = states[player]
	if not s then
		s = { waves = {}, nextAt = { meadow = 0, sky = 0 }, farSince = {}, lastHit = 0, muteUntil = 0, joinedAt = os.clock(), hist = {} }
		states[player] = s
	end
	return s
end

local function root(player: Player): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function fire(payload: { [string]: any }, only: Player?)
	local r = fx
	if not r then
		return
	end
	if only then
		if only.Parent == Players then
			r:FireClient(only, payload)
		end
	else
		r:FireAllClients(payload)
	end
end

local function combatData(data: any): any
	local c = data.combat
	if typeof(c) ~= "table" then
		c = { stage = 0, guardians = 0, firstAt = 0 }
		data.combat = c
	end
	c.stage = tonumber(c.stage) or 0
	c.guardians = tonumber(c.guardians) or 0
	c.firstAt = tonumber(c.firstAt) or 0
	c.waves = tonumber(c.waves) or 0
	c.fightSec = tonumber(c.fightSec) or 0
	return c
end

-- the player's wave ended (cleared, the guardian left, removed) - into the pacing history and the profile counters combat.waves /
-- fightSec (measuring the fight share of the session, zones_scan). A far untouched arena wave (relocated to the player) does not count
local function waveEnded(player: Player, w: any)
	local s = states[player]
	if not s or not (w.near or next(w.dealt) ~= nil) then
		return
	end
	local now = os.clock()
	table.insert(s.hist, { w.startedAt, now })
	local keep = math.max(C.hunt.cap.window, C.hunt.share.window)
	while #s.hist > 0 and s.hist[1][2] < now - keep do
		table.remove(s.hist, 1)
	end
	local PD = services.PlayerData
	if player.Parent == Players and PD then
		PD.update(player, "combat", function(c: any, d: any)
			c = combatData(d)
			c.waves += 1
			c.fightSec += math.floor(now - w.startedAt + 0.5)
			return c
		end)
	end
end

local function nestRate(data: any): number
	local mods = if services.Shop and services.Shop.rateMods then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) }
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

-- ---------------------------------------------------------------------------------------------- Gloom models
local function ball(parent: Instance, name: string, d: number, color: Color3, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(d, d, d)
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true -- the client aim and the target highlight
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function smoke(parent: BasePart, size: number, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = "Smoke"
	local VS = C.visibility
	e.Color = ColorSequence.new(rgb((VS and VS.shellColor) or C.enemy.smoke), rgb(C.enemy.color))
	e.LightEmission = (VS and VS.smokeLight) or 0.1 -- the Gloom smoke glows purple
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.45), NumberSequenceKeypoint.new(1, size * 0.9) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = rate
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Parent = parent
end

-- Gloom: a dark ball in smoke, two yellow eyes looking outward; the guardian - larger, horns of stone and a ring of boulders
local function buildFallback(id: string, at: Vector3, d: number, guardian: boolean, name: string?): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "Gloom_" .. id
	local body = ball(m, "Body", d, rgb(C.enemy.color), Enum.Material.SmoothPlastic, 0.12)
	body.CFrame = CFrame.new(at)
	local core = ball(m, "Core", d * 0.55, rgb(C.enemy.smoke), Enum.Material.Neon, 0.55)
	core.CFrame = body.CFrame
	for _, side in { -1, 1 } do
		local eye = ball(m, "Eye", d * 0.16, rgb(C.enemy.eyes), Enum.Material.Neon, 0)
		eye.CFrame = body.CFrame * CFrame.new(side * d * 0.17, d * 0.08, -d * 0.44)
	end
	if guardian then
		for _, side in { -1, 1 } do
			local horn = Instance.new("WedgePart")
			horn.Name = "Horn"
			horn.Size = Vector3.new(d * 0.12, d * 0.45, d * 0.25)
			horn.Color = Color3.fromRGB(58, 52, 66)
			horn.Material = Enum.Material.Slate
			horn.Anchored = true
			horn.CanCollide = false
			horn.CanTouch = false
			horn.CastShadow = false
			horn.CFrame = body.CFrame * CFrame.new(side * d * 0.3, d * 0.5, 0) * CFrame.Angles(0, 0, side * -0.35)
			horn.Parent = m
		end
		for k = 1, 6 do
			local a = (k - 1) * math.pi / 3
			local rock = Instance.new("Part")
			rock.Name = "Rock"
			rock.Size = Vector3.new(d * 0.16, d * 0.13, d * 0.15)
			rock.Color = Color3.fromRGB(74, 66, 84)
			rock.Material = Enum.Material.Slate
			rock.Anchored = true
			rock.CanCollide = false
			rock.CanTouch = false
			rock.CastShadow = false
			rock.CFrame = body.CFrame * CFrame.new(math.cos(a) * d * 0.85, math.sin(a * 2) * d * 0.12, math.sin(a) * d * 0.85) * CFrame.Angles(a, a * 0.7, 0)
			rock.Parent = m
		end
		m:SetAttribute("Guardian", true)
		m:SetAttribute("GuardianName", name or "")
	end
	smoke(body, d, if guardian then 40 else 12)
	m.PrimaryPart = body
	return m, body
end

-- the 3D model of the kind (ModelLibrary: normalized to 1 stud, anchored, no scripts) + an invisible target Body in the center
-- purple light and smoke from below; no model (id 0 or a load failure) - the fallback figure
local function buildEnemy(id: string, at: Vector3, d: number, guardian: boolean, name: string?, kind: string, scale: number?): (Model, BasePart)
	local spec = (C.models :: any)[kind]
	local mesh: Model? = nil
	if spec and (spec.id or 0) > 0 and services.ModelLibrary then
		-- only from the ready cache - a hung load does not hold the combat tick of the whole server
		local ok, res = pcall(services.ModelLibrary.peek, spec.id)
		mesh = if ok then res else nil
		if not mesh then
			warn("[Combat] model " .. kind .. " " .. tostring(spec.id) .. " did not load - the fallback figure")
		end
	end
	if not mesh then
		return buildFallback(id, at, d, guardian, name)
	end
	local m = mesh :: Model
	m.Name = "Gloom_" .. id
	local okS, errS = pcall(function()
		-- ModelLibrary returns a model 1 stud tall (scale s0 = 1 / the original height); ScaleTo sets the scale from the original file
		-- so the needed height = the current scale x height
		m:ScaleTo(m:GetScale() * spec.height * (scale or 1)) -- scale - the large chase Gloom (Config.Glow.egg.chase)
	end)
	if not okS then
		warn("[Combat] ScaleTo " .. kind .. ": " .. tostring(errS))
	end
	m:PivotTo(CFrame.new(at))
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.CanQuery = false
			p.CastShadow = false
		end
	end
	-- a neon purple shell over the mesh
	-- (a copy of every part slightly larger, Neon, semi-transparent) - a dark creature in a purple glow, the shape and the texture stay
	local VS = C.visibility
	if VS and VS.shell ~= false then
		local shellColor = rgb(VS.shellColor or spec.glow)
		local shells: { BasePart } = {}
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Name ~= "Body" then
				local s = p:Clone()
				for _, ch in s:GetChildren() do
					if not ch:IsA("SpecialMesh") then
						ch:Destroy()
					end
				end
				s.Name = "Glow_" .. p.Name
				s.Material = Enum.Material.Neon
				s.Color = shellColor
				s.Transparency = VS.shellTransparency or 0.45
				s.Size = p.Size * (VS.shellScale or 1.06)
				s.CFrame = p.CFrame
				s.CanCollide = false
				s.CanQuery = false
				s.CanTouch = false
				s.CastShadow = false
				s.Anchored = p.Anchored
				table.insert(shells, s)
			end
		end
		for _, s in shells do
			s.Parent = m
		end
	end
	local body = ball(m, "Body", d, Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, 1)
	body.CFrame = CFrame.new(at)
	local light = Instance.new("PointLight")
	light.Color = rgb(spec.glow)
	-- the light three times brighter and wider
	-- plus a Highlight outline - visible both in the dark and through the grass (Config.Combat.visibility)
	local V = C.visibility or { lightMult = 3, rangeMult = 3, highlight = true }
	light.Range = spec.height * (scale or 1) * 1.6 * (V.rangeMult or 3)
	light.Brightness = 1.4 * (V.lightMult or 3)
	light.Parent = body
	if V.highlight ~= false then
		local hl = Instance.new("Highlight")
		hl.Name = "GloomGlow"
		hl.FillColor = rgb(spec.glow)
		hl.FillTransparency = V.fillTransparency or 0.75
		hl.OutlineColor = Color3.fromRGB(215, 170, 255)
		hl.OutlineTransparency = V.outlineTransparency or 0.1
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = m
		hl.Parent = m
	end
	smoke(body, d * 0.6, if guardian then 30 else 8)
	m.PrimaryPart = body
	if guardian then
		m:SetAttribute("Guardian", true)
		m:SetAttribute("GuardianName", name or "")
	end
	return m, body
end

-- ---------------------------------------------------------------------------------------------- arenas and waves
local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	if folder then
		table.insert(skip, folder)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), params)
	return if hit then hit.Position.Y else 0
end

local function arenaCenter(player: Player, arena: string): Vector3?
	if not services.Nest then
		return nil
	end
	local _, index = services.Nest.of(player)
	if not index then
		return nil
	end
	local x, z, y = CombatCore.arenaXZ(C, Config.World.nests, index, arena)
	if arena == "meadow" then
		return Vector3.new(x, groundY(x, z), z)
	end
	return Vector3.new(x, y or C.arena.skyY, z)
end

local function serverCount(): number
	local n = 0
	for _ in enemies do
		n += 1
	end
	return n
end

local function removeEnemy(e: Enemy)
	enemies[e.id] = nil
	e.wave.enemies[e.id] = nil
	if e.model.Parent then
		e.model:Destroy()
	end
end

local function dropWave(player: Player, arena: string, leaving: boolean?)
	local s = states[player]
	local w = s and s.waves[arena]
	if not s or not w then
		return
	end
	for _, e in w.enemies do
		removeEnemy(e)
	end
	s.waves[arena] = nil
	s.lastEnd = os.clock()
	if not leaving then -- the player is leaving: the profile is already being saved, the counters are not touched
		waveEnded(player, w)
	end
	if arena == "meadow" or arena == "sky" or arena == "glow" then
		player:SetAttribute("Gloom_" .. arena, nil)
	end
end

local function publishWave(player: Player, w: Wave?)
	-- attributes for the client (the stage bar, the hint target): the number, the remainder, the replay, the guardian deadline
	if not w then
		return
	end
	-- "stage|left|replay|guardian timer end (server time)"
	player:SetAttribute("Gloom_" .. w.arena, string.format("%d|%d|%d|%s", w.stage, w.left, if w.replay then 1 else 0,
		if w.serverEnd then string.format("%.1f", w.serverEnd) else ""))
end

-- the height of a hunt ring point - the ground by a ray from the player's level (+30 down), not from 400 (roofs, ledges, rocks)
-- a point more than 8 studs above the player (a rock, a ledge) - at the player's level, 10+ below (a cliff) - no lower than the player - 10
local function ringY(center: Vector3, x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	if folder then
		table.insert(skip, folder)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, center.Y + 30, z), Vector3.new(0, -80, 0), params)
	local gy = if hit then hit.Position.Y else center.Y
	if gy > center.Y + 8 then
		return center.Y
	end
	return math.max(gy, center.Y - 10)
end

-- the ground under the point by a ray from 40 above the support, no ceiling (a ceiling put points into the slope); a cliff higher than 25 - at the support level
local function groundAt(ref: Vector3, x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	if folder then
		table.insert(skip, folder)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, ref.Y + 40, z), Vector3.new(0, -100, 0), params)
	if not hit or hit.Position.Y > ref.Y + 25 then
		return ref.Y
	end
	return hit.Position.Y
end

local countOverride: number? = nil -- the glowing egg guards - their own enemy count (Combat.guardEgg)

local function spawnWave(player: Player, arena: string, stage: number, replay: boolean, center: Vector3, ring: { number }?): Wave?
	local def = CombatCore.stage(C, stage)
	if not def or not folder then
		return nil
	end
	local count = if def.guardian then 1 else (countOverride or def.n or 1)
	if serverCount() + count > C.enemy.maxPerServer then
		return nil
	end
	local now = os.clock()
	local w: Wave = {
		arena = arena, stage = stage, replay = replay, center = center, enemies = {}, left = 0,
		hpTotal = CombatCore.waveHp(def), dealt = {}, startedAt = now,
		deadline = if def.guardian then now + (def.seconds or 120) else nil,
		serverEnd = if def.guardian then workspace:GetServerTimeNow() + (def.seconds or 120) else nil, pulses = 0, warned = 0,
	}
	for k = 1, count do
		nextId += 1
		local id = tostring(nextId)
		local pos: Vector3
		local d: number
		if def.guardian then
			d = G.size
			local base = center
			if ring then -- the guardian comes out not onto the player but at the ring edge
				local a = r01() * math.pi * 2
				local x, z = center.X + math.cos(a) * ring[1], center.Z + math.sin(a) * ring[1]
				base = Vector3.new(x, if arena == "meadow" then ringY(center, x, z) else center.Y, z)
			end
			pos = base + Vector3.new(0, if arena == "meadow" then d * 0.5 + C.arena.hover[2] else 0, 0)
		else
			d = if stage <= 2 then C.enemy.size[1] else C.enemy.size[2]
			local a = (k - 1) / count * math.pi * 2 + r01() * 0.6
			-- a ring of ring studs around the player
			local r = if ring then ring[1] + r01() * (ring[2] - ring[1]) else C.arena.spread * (0.45 + r01() * 0.55)
			-- the golden nest guards (glow) stand on the meadow ground, like the meadow wave - above the ground under each point (not +-6 from the center:
			-- on a slope that put them in the ground or in the air)
			local ground = arena == "meadow" or arena == "glow"
			local h = if ground then C.arena.hover[1] + r01() * (C.arena.hover[2] - C.arena.hover[1]) else (r01() - 0.5) * 12
			local x, z = center.X + math.cos(a) * r, center.Z + math.sin(a) * r
			local y0 = if arena == "glow" then groundAt(center, x, z) elseif ring and arena == "meadow" then ringY(center, x, z) else center.Y
			pos = Vector3.new(x, y0 + h, z)
		end
		local kind = (def :: any).kind or (if def.guardian then "warden" else "shardling")
		local m, body = buildEnemy(id, pos, d, def.guardian == true, def.name, kind)
		m:SetAttribute("Kind", kind)
		m:SetAttribute("Id", id)
		m:SetAttribute("OwnerId", player.UserId)
		m:SetAttribute("Stage", stage)
		m:SetAttribute("Hp", def.hp)
		m:SetAttribute("MaxHp", def.hp)
		m:SetAttribute("Arena", arena)
		CollectionService:AddTag(m, "Gloom")
		m.Parent = folder
		local A = if stage > C.attack.calmStages then (C.attack :: any)[kind] else nil -- stages 1-2 only hover
		local e: Enemy = { id = id, model = m, body = body, hp = def.hp, maxHp = def.hp, owner = player, wave = w,
			guardian = def.guardian == true, home = pos, radius = d / 2, kind = kind,
			attackAt = now + (if A then A.every[1] + r01() * (A.every[2] - A.every[1]) else 1e9), busyUntil = 0,
			rush = if ring and not def.guardian then true else nil,
			hover = if arena == "glow" and not def.guardian then pos.Y - groundAt(center, pos.X, pos.Z) else nil }
		enemies[id] = e
		w.enemies[id] = e
		w.left += 1
	end
	if def.guardian then
		fire({ k = "guardian", owner = player.UserId, stage = stage, name = def.name, seconds = def.seconds, arena = arena })
	end
	return w
end

-- ---------------------------------------------------------------------------------------------- rewards
local function giveEgg(player: Player, egg: any)
	egg.foundAt = os.time()
	services.PlayerData.update(player, "eggs", function(e)
		e.shelf = e.shelf or {}
		table.insert(e.shelf, egg)
		return nil
	end)
end

-- the companion's damage now and if fed, whether a newcomer (the first session, has not flown yet);
-- the power is computed every tick; a corrupted companion record (an assert in Economy) does not crash the tick - damage 1 and one warn
local powerWarned = false
local function huntCtx(data: any): (number, number, boolean)
	local now = os.time()
	local ok, dmg, dmgFed = pcall(function()
		return CombatCore.damage(CombatCore.power(data, now, C, B)), CombatCore.damage(CombatCore.power(data, now, C, B, true))
	end)
	if not ok then
		if not powerWarned then
			powerWarned = true
			warn("[Combat] companion power: " .. tostring(dmg))
		end
		dmg, dmgFed = 1, 2
	end
	local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
	return dmg, dmgFed, (tonumber(data.sessions) or 0) <= 1 and not onb.flew
end

-- the hint after a win if the next wave of this arena is beyond the dragon's power (Core/Combat.huntStage): feed / grow / storm / sky
-- "fly to the sky" - only for an adult companion, for a hatchling and a teen - "grow"
local function weakHint(player: Player, data: any, cleared: number, arena: string): string?
	local dmg, dmgFed, newbie = huntCtx(data)
	local _, _, weak = CombatCore.huntStage(C, cleared, arena, dmg, dmgFed, newbie)
	if weak == "sky" and (tonumber(player:GetAttribute("CompanionStage")) or 0) < 2 then
		weak = "grow"
	end
	if weak == "feed" then -- it grows anyway before the feeding pays off: "grow" (NextUp shows the growth timer)
		local d = if typeof(data.dragons) == "table" and typeof(data.companion) == "string" then data.dragons[data.companion] else nil
		local rem = if typeof(d) == "table" then Growth.remaining(d :: any, os.time()) else nil
		if rem and rem <= C.hunt.growHint then
			weak = "grow"
		end
	end
	return weak
end

local function clearWave(player: Player, w: Wave)
	local data = services.PlayerData.get(player)
	local s = states[player]
	if s then
		s.waves[w.arena] = nil
		s.nextAt[w.arena] = os.clock() + C.arena.nextDelay
		s.lastEnd = os.clock()
	end
	waveEnded(player, w)
	player:SetAttribute("Gloom_" .. w.arena, nil)
	if not data then
		return
	end
	local def = CombatCore.stage(C, w.stage)
	local first = false
	if not w.replay then
		services.PlayerData.update(player, "combat", function(c: any, d: any)
			c = combatData(d)
			if w.stage > c.stage then
				c.stage = w.stage
				first = true
			end
			if def and def.guardian and first then
				c.guardians += 1
			end
			return c
		end)
	end
	local coins, egg = CombatCore.reward(C, w.stage, nestRate(data), w.replay or not first, Config.Quests.minMinutesReward)
	if coins > 0 and services.Nest then
		services.Nest.addCoins(player, coins, "Combat")
	end
	local gotEgg = false
	if egg and services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
		-- day 1 = one dragon - coins instead of an egg
		local extra = (Config.Quests and Config.Quests.eggFallbackCoins) or 300
		coins += extra
		if services.Nest then
			services.Nest.addCoins(player, extra, "Combat")
		end
		egg = nil
	end
	if egg then
		giveEgg(player, Eggs.rollGuaranteed("combat" .. w.stage, egg.egg, egg.minRarity or "Common", r01, B, Config.Elements))
		gotEgg = true
	end
	-- what next if the next wave is beyond the power; a win over the meadow guardian - its own banner skyOpen
	local guardianFirst = first and def ~= nil and def.guardian == true
	local okW, weak = pcall(weakHint, player, data, combatData(data).stage, w.arena)
	fire({ k = "clear", stage = w.stage, arena = w.arena, coins = coins, egg = gotEgg, guardian = def ~= nil and def.guardian == true,
		replay = w.replay or not first, next = if okW and not guardianFirst then weak else nil }, player)
	if first then
		if services.Analytics then
			services.Analytics.custom(player, "combat_stage", w.stage, { arena = w.arena })
			if w.stage == 5 then
				services.Analytics.onboard(player, "gloom_guardian_first")
			elseif w.stage == 10 then
				services.Analytics.onboard(player, "storm_guardian_first")
			end
		end
		if services.Badges and def and def.guardian then
			services.Badges.award(player, if w.stage == 5 then "gloom" else "warden")
		end
	end
	-- helpers: a share of the owner's coins if the damage >= helperMinShare of the wave's health
	for helper, dealt in w.dealt do
		if helper ~= player and helper.Parent == Players then
			local h = CombatCore.helperCoins(C, coins, dealt, w.hpTotal)
			if h > 0 and services.Nest then
				services.Nest.addCoins(helper, h, "CombatHelp")
				fire({ k = "help", coins = h, owner = player.UserId }, helper)
			end
		end
	end
end

local function failGuardian(player: Player, w: Wave)
	for _, e in w.enemies do
		removeEnemy(e)
	end
	local s = states[player]
	if s then
		s.waves[w.arena] = nil
		s.nextAt[w.arena] = os.clock() + G.retry
		s.lastEnd = os.clock() -- the hunt does not bring the guardian back 2 s later (the "retreats -> coming" loop)
	end
	waveEnded(player, w)
	player:SetAttribute("Gloom_" .. w.arena, nil)
	-- the guardian returns only if the dragon is strong enough - then instead of "in 60 s" the line "feed / grow"
	local data = services.PlayerData.get(player)
	local okW, weak = if data then pcall(weakHint, player, data, combatData(data).stage, w.arena) else false, nil
	fire({ k = "fail", stage = w.stage, arena = w.arena, retry = G.retry, next = if okW then weak else nil }, player)
	if services.Analytics then
		services.Analytics.custom(player, "guardian_fail", w.stage)
	end
end

-- ---------------------------------------------------------------------------------------------- hit
-- a hit rejected for a reason the player can fix (the dragon is not near, too small, the enemy is
-- far) - a short hint, no more often than once per 3 s; the cooldown and the stun are not hinted (they are visible anyway)
local missAt: { [Player]: number } = {}
local function miss(player: Player, why: string)
	local now = os.clock()
	if now - (missAt[player] or -math.huge) >= 3 then
		missAt[player] = now
		fire({ k = "miss", why = why }, player)
	end
end

local function onBreath(player: Player, id: any)
	if not C.on or typeof(id) ~= "string" or #id > 16 then
		return
	end
	local s = state(player)
	local now = os.clock()
	if now - s.lastHit < C.breath.serverCooldown then
		count("cooldown")
		return
	end
	if now < s.muteUntil then
		count("muted")
		return
	end
	local e = enemies[id]
	local r = root(player)
	if not e or e.hp <= 0 or not r or not e.model.Parent then
		count("target")
		return
	end
	if e.chase then -- one runs from the chase, does not hit it (the client does not target it - tag GloomChase)
		count("chase")
		return
	end
	if (e.body.Position - r.Position).Magnitude > C.breath.serverRange + e.radius then
		count("range")
		miss(player, "range")
		return
	end
	if not services.Movement or not services.Movement.companionOf(player) then
		count("nocompanion")
		miss(player, "nocompanion")
		return -- nobody to hit with: the companion is not in the world
	end
	local data = services.PlayerData.get(player)
	if not data then
		count("nodata")
		return
	end
	local power = CombatCore.power(data, os.time(), C, B)
	if power <= 0 then
		count("nopower")
		miss(player, "nopower")
		return
	end
	count("ok")
	s.lastHit = now
	local dmg = CombatCore.damage(power)
	local before = e.hp
	e.hp = math.max(0, e.hp - dmg)
	local w = e.wave
	w.dealt[player] = (w.dealt[player] or 0) + (before - e.hp)
	e.model:SetAttribute("Hp", e.hp)
	if not e.guardian and e.hp > 0 then -- recoil: the Gloom flies back from the hit (visible that it landed)
		local away = Vector3.new(e.body.Position.X - r.Position.X, 0, e.body.Position.Z - r.Position.Z)
		if away.Magnitude > 1e-3 then
			e.model:PivotTo(e.model:GetPivot() + away.Unit * C.attack.knockback)
		end
	end
	local comp = data.dragons and data.companion and data.dragons[data.companion]
	local el = if comp then comp.element else "ember"
	fire({ k = "hit", id = id, dmg = dmg, by = player.UserId, el = el })
	local c = combatData(data)
	if c.firstAt == 0 then
		services.PlayerData.update(player, "combat", function(cc: any, d: any)
			cc = combatData(d)
			cc.firstAt = os.time()
			return cc
		end)
		if services.Analytics then
			services.Analytics.onboard(player, "attack_first")
		end
	end
	if e.hp <= 0 then
		local pos = e.body.Position
		fire({ k = "purify", id = id, el = el, pos = pos, guardian = e.guardian })
		removeEnemy(e)
		w.left -= 1
		local owner = e.owner
		if w.left <= 0 and owner.Parent == Players then
			clearWave(owner, w)
		else
			publishWave(owner, w)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- the tick: appearance, drift, touch, pulse
local function nearestPlayer(pos: Vector3, maxD: number): (Player?, BasePart?)
	local best, bestRoot, bd = nil, nil, maxD
	for _, p in Players:GetPlayers() do
		local r = root(p)
		if r then
			local d = (r.Position - pos).Magnitude
			if d < bd then
				best, bestRoot, bd = p, r, d
			end
		end
	end
	return best, bestRoot
end

-- the player's progress - hatched, placed an egg
-- the dragon grew, an onboarding or Keeper step, a cleared stage. Coins do not count (they drip by themselves). No changes for bored.after s - bored
local function progressKey(data: any): string
	local n, st = 0, 0
	for _, d in (if typeof(data.dragons) == "table" then data.dragons else {}) :: any do
		n += 1
		st += tonumber(d.stage) or 0
	end
	-- incubating is a dictionary by slot ("1", "2"...), # is always 0 - count by iterating; onboarding - stage too
	local function count(t: any): number
		local c = 0
		for _ in (if typeof(t) == "table" then t else {}) :: any do
			c += 1
		end
		return c
	end
	local eggs = if typeof(data.eggs) == "table" then data.eggs else {}
	local inc = count(eggs.incubating)
	local shelf = count(eggs.shelf)
	local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
	local ob = 0
	for _, v in onb :: any do
		if v == true then
			ob += 1
		end
	end
	local q = data.quests and data.quests.keeper and data.quests.keeper.step or 0
	return string.format("%d|%d|%d|%d|%d|%s|%s|%d", n, st, inc, shelf, ob, tostring(onb.stage), tostring(q), combatData(data).stage)
end

-- the ambush point in front of the player: on the ground - not in the water and not by the spawn plaza; in the sky - at his height
local function ambushPoint(r: BasePart, sky: boolean, ahead: number): Vector3?
	local look = Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
	local p = r.Position + (if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis) * ahead
	if sky then
		return p
	end
	local pad = workspace:FindFirstChildWhichIsA("SpawnLocation")
	if pad and Vector3.new(pad.Position.X - p.X, 0, pad.Position.Z - p.Z).Magnitude < C.bored.spawnClear then
		return nil
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { r.Parent :: Instance }
	local hit = workspace:Raycast(Vector3.new(p.X, r.Position.Y + 30, p.Z), Vector3.new(0, -400, 0), params)
	if not hit or hit.Material == Enum.Material.Water then
		return nil
	end
	-- the ground under the point from the player's level (a ray from 400 finds the stall roof, the ledge top) - the strike point height
	return Vector3.new(p.X, hit.Position.Y, p.Z)
end

-- a task in hand - the hunt waits (no longer than hunt.gapMax): carrying an egg, an incubator egg is ready or
-- about to be, the companion is about to grow, the "mount" / "take off" step and the first seconds after the first ride / the first flight
local function holdOf(data: any, s: PState, now: number): string?
	local HD = C.hunt.hold
	local t = os.time()
	local eggs = if typeof(data.eggs) == "table" then data.eggs else {}
	if eggs.carry ~= nil then
		return "carry"
	end
	if s.waves.glow then -- a fight for the glowing egg is on - the hunt waits (the chase - the egg in hand, "carry" above)
		return "glow"
	end
	for _, rec in (if typeof(eggs.incubating) == "table" then eggs.incubating else {}) :: any do
		if typeof(rec) == "table" and tonumber(rec.endsAt) and rec.endsAt - t < HD.hatch then
			return "hatch"
		end
	end
	local d = if typeof(data.dragons) == "table" and typeof(data.companion) == "string" then data.dragons[data.companion] else nil
	if typeof(d) == "table" then
		local rem = Growth.remaining(d :: any, t)
		if rem and rem < HD.grow then
			return "grow"
		end
		local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
		local st = tonumber(d.stage) or 0
		if st >= 1 and not onb.rode then
			return "ride"
		end
		if st >= 2 and not onb.flew then
			return "fly"
		end
	end
	if s.rodeAt and now - s.rodeAt < HD.ride then
		return "ride"
	end
	if s.flewAt and now - s.flewAt < HD.fly then
		return "fly"
	end
	return nil
end

local function tickPlayer(player: Player, now: number)
	if not ready then
		return -- the models are still loading (seconds after the server start)
	end
	if services.Raid and services.Raid.active and services.Raid.active() then
		return -- the egg raid is the core of the game; hunts, ambushes and arena waves are off (combat waves 0% among the hits)
	end
	local data = services.PlayerData.get(player)
	local r = root(player)
	if not data or not r then
		return
	end
	local s = state(player)
	local cleared = combatData(data).stage
	-- the first wave comes by itself - ambush.afterHatch s after the companion's hatch (and not earlier than afterJoin s
	-- after joining) a stage-1 Gloom grows in front of the player wherever he is; then the stages go on the meadow arena as before.
	-- A usual stage-1 wave on the arena below the ledge is out of sight and reach; such a wave (nobody hit, farther than ambush.near) relocates to the player
	local A = C.ambush
	local busy = s.busyAt ~= nil and now - s.busyAt < C.busyMax -- the client's menu/scene (UiBusy); a forgotten flag expires
	local mw = s.waves.meadow
	local movable = mw ~= nil and mw.stage == 1 and next(mw.dealt) == nil
		and Vector3.new(mw.center.X - r.Position.X, 0, mw.center.Z - r.Position.Z).Magnitude > A.near
	if A and cleared == 0 and (not mw or movable) and not s.ambushed and not busy and player:GetAttribute("CompanionStage") ~= nil
		and now - s.joinedAt >= A.afterJoin then
		local d = if typeof(data.dragons) == "table" and data.companion then data.dragons[data.companion] else nil
		local hatchedAt = if typeof(d) == "table" then tonumber(d.hatchedAt) else nil
		-- the spot - like the boredom ambush (not by the spawn plaza, not in the water); no spot - try on the next tick
		local at = if hatchedAt and os.time() - hatchedAt >= A.afterHatch then ambushPoint(r, false, A.ahead) else nil
		if at then
			s.ambushed = true
			if mw then
				dropWave(player, "meadow")
			end
			local nw = spawnWave(player, "meadow", 1, false, at)
			if nw then
				nw.near = true
				s.waves.meadow = nw
				publishWave(player, nw)
				if services.Analytics then
					pcall(services.Analytics.custom, player, "ambush", 1, { kind = "first" })
				end
			end
		end
	end
	-- the boredom ambush - bored.after s without progress, no own wave, no more often than bored.every: the Gloom comes to
	-- the player by itself (on the ground - in front of him, mounted high above the ground - in the sky around him; sky stages only after guardian I)
	local key = progressKey(data)
	if key ~= s.progKey then
		s.progKey = key
		s.progAt = now
	end
	local BD = C.bored
	-- THE HUNT - the wave comes to the player by itself (in a pause, Core/Combat.huntReady, Config.Combat.hunt); not in a menu/scene,
	-- not by the spawn plaza, not in the water; flying mounted - the sky (after guardian I), otherwise a skip until landing. For hunt.warn s -
	-- "The Gloom is coming!" and tense music (the client), then the enemies in a ring of hunt.ring around run toward the player.
	-- An untouched far arena wave (under the ledge) relocates to the player
	local H = C.hunt
	local lw = s.waves.meadow
	local lwFar = lw ~= nil and next(lw.dealt) == nil
		and Vector3.new(lw.center.X - r.Position.X, 0, lw.center.Z - r.Position.Z).Magnitude > A.near
	-- the moments of the first ride and the first flight in this session - the onboarding flag flips (the profile schema does not change)
	local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
	if s.rodeWas == nil then
		s.rodeWas, s.flewWas = onb.rode == true, onb.flew == true
	end
	if onb.rode and not s.rodeWas then
		s.rodeWas, s.rodeAt = true, now
	end
	if onb.flew and not s.flewWas then
		s.flewWas, s.flewAt = true, now
	end
	-- (spec 26 v2; P8 frames: the hunt wave "Stage 2/10" came in the middle of a raid and the run home - foreign creatures around, "who is chasing"):
	-- while a raid (GlowWait) or a chasing pack (GlowChase) is on - the hunt does not come, an untouched meadow/sky wave leaves
	local raid = player:GetAttribute("GlowWait") ~= nil or player:GetAttribute("GlowChase") == true
	if raid then
		for _, ar in { "meadow", "sky" } do
			local wv = s.waves[ar]
			if wv and next(wv.dealt) == nil then
				dropWave(player, ar)
			end
		end
		if s.huntAt then
			fire({ k = "incoming", cancel = true }, player)
			s.huntAt = nil
		end
		s.huntWhy = "glow"
		lw = s.waves.meadow
	end
	if not raid and H and H.on and (cleared > 0 or s.ambushed) and player:GetAttribute("CompanionStage") ~= nil and (not lw or lwFar)
		and not s.waves.sky then
		if busy then
			if s.huntAt then
				fire({ k = "incoming", cancel = true }, player) -- the music and Fight on the client do not hang for nothing
			end
			s.huntAt = nil -- a menu opened: the announced wave waits for the next time
			s.huntWhy = "busy"
		elseif s.huntAt == nil then
			-- the wave comes in a pause -
			-- silence gapMin after the previous one, due by idle or by gapMax, a task in hand waits, the stage by power, the wave ceiling
			local flying = player:GetAttribute("Mounted") ~= nil and r.Position.Y - groundY(r.Position.X, r.Position.Z) > BD.flyHeight
			local arena = if flying then "sky" else "meadow"
			local dmg, dmgFed, newbie = huntCtx(data)
			local stage, replay = CombatCore.huntStage(C, cleared, arena, dmg, dmgFed, newbie)
			-- no hunt in the sky until profile day Config.Combat.skyFromDay (air combat later, to not overload a newcomer)
			if flying and stage then
				local day = math.floor((os.time() - (tonumber(data.createdAt) or os.time())) / 86400) + 1
				if day < (C.skyFromDay or 3) then
					stage = nil
				end
			end
			if not stage then
				s.huntWhy = "none"
			else
				local _, doneRep = CombatCore.waveFor(C, cleared, arena)
				local okR, why = CombatCore.huntReady({
					now = now, joinedAt = s.joinedAt, lastEnd = s.lastEnd, progAt = s.progAt, busyEnd = s.busyEnd, newbie = newbie,
					busy = false, afk = services.Reward ~= nil and not services.Reward.isActive(player),
					-- during a storm the hunt waits
					hold = holdOf(data, s, now) or (if services.Weather and services.Weather.inStorm and services.Weather.inStorm(player) then "storm" else nil),
					hist = s.hist,
					-- a replay after the guardian / the whole sky - no more often than replayGap; a "beyond the power" replay - no more often than gapMax
					replayGap = if not replay then nil elseif doneRep then H.replayGap else H.gapMax[if newbie then "new" else "old"],
				}, H)
				s.huntWhy = why
				-- a lost guardian - a retry break (the arena's nextAt), not again in 2 s
				if okR and now >= (s.nextAt[arena] or 0) and ambushPoint(r, arena == "sky", 0) then
					s.huntAt = now + H.warn
					s.huntArena = arena
					fire({ k = "incoming", seconds = H.warn, arena = arena }, player)
				end
			end
		elseif now >= s.huntAt then
			local arena = s.huntArena or "meadow"
			s.huntAt = nil
			-- during the 2 s warning the player could mount or take off - recheck the arena, no match - cancel
			local flyingNow = player:GetAttribute("Mounted") ~= nil and r.Position.Y - groundY(r.Position.X, r.Position.Z) > BD.flyHeight
			local dmg, dmgFed, newbie = huntCtx(data)
			local stage, replay = CombatCore.huntStage(C, cleared, arena, dmg, dmgFed, newbie)
			local at = if stage and flyingNow == (arena == "sky") then ambushPoint(r, arena == "sky", 0) else nil
			if not at then
				fire({ k = "incoming", cancel = true }, player)
			end
			if stage and at then
				if lw then
					dropWave(player, "meadow")
				end
				local nw = spawnWave(player, arena, stage, replay, at, H.ring)
				if nw then
					nw.near = true
					s.waves[arena] = nw
					publishWave(player, nw)
					if services.Analytics then
						pcall(services.Analytics.custom, player, "ambush", stage, { kind = "hunt", arena = arena, replay = replay })
					end
				end
			end
		end
	end
	for _, arena in { "meadow", "sky" } do
		local w = s.waves[arena]
		local center = if w then w.center else nil
		local stage, replay = CombatCore.waveFor(C, cleared, arena)
		if not stage then
			if w then
				dropWave(player, arena)
			end
			continue
		end
		if not center then
			center = arenaCenter(player, arena)
		end
		if not center then
			continue
		end
		local flat = Vector3.new(r.Position.X - center.X, 0, r.Position.Z - center.Z).Magnitude
		local near = flat <= C.arena.activeDistance
		if arena == "sky" then
			near = near and r.Position.Y >= center.Y - 40
		end
		if near then
			s.farSince[arena] = nil
			-- with the hunt the arena places no new waves (the hunt brings them) - no wave under the ledge with the menu open,
			-- no two guardian banners; without the hunt - as before, but not in a menu
			if not w and now >= s.nextAt[arena] and not (C.hunt and C.hunt.on) and not busy then
				local nw = spawnWave(player, arena, stage, replay, center)
				if nw then
					s.waves[arena] = nw
					publishWave(player, nw)
				end
			end
		elseif w then
			local since = s.farSince[arena]
			if not since then
				s.farSince[arena] = now
			elseif now - since > C.arena.idleDespawn then
				dropWave(player, arena) -- it comes back as a fresh wave of the same stage
			end
		end
	end
end

-- a player with an open menu / scene (UiBusy) - not attacked, the guardian's touch and pulse do not mute (the fight waits behind the menu)
local function isBusy(p: Player?, now: number): boolean
	local ps = p and states[p]
	return ps ~= nil and ps.busyAt ~= nil and now - ps.busyAt < C.busyMax
end

local function tickEnemies(now: number, dt: number)
	local E = C.enemy
	for _, e in enemies do
		if not e.model.Parent or e.chase then -- the pack moves every frame (movePacks)
			continue
		end
		local w = e.wave
		if e.guardian then
			-- the pulse: a warning warn s before the strike, the strike - breath muting for everyone within the radius
			local t = now - w.startedAt
			local warnN = CombatCore.pulseCount(t + G.warn, G)
			if warnN > w.warned then
				w.warned = warnN
				fire({ k = "warn", id = e.id, pos = e.body.Position, radius = G.radius, seconds = G.warn, sky = w.arena == "sky" })
			end
			local n = CombatCore.pulseCount(t, G)
			if n > w.pulses then
				w.pulses = n
				for _, p in Players:GetPlayers() do
					local pr = root(p)
					if pr then
						local v = pr.Position - e.body.Position
						local d = if w.arena == "meadow" then Vector3.new(v.X, 0, v.Z).Magnitude else v.Magnitude
						if d <= G.radius and not isBusy(p, now) then
							local ps = state(p)
							ps.muteUntil = math.max(ps.muteUntil, now + G.stun)
							fire({ k = "stun", seconds = G.stun }, p)
						end
					end
				end
			end
			if w.deadline and now > w.deadline and e.hp > 0 and e.owner.Parent == Players then
				failGuardian(e.owner, w)
			end
			continue
		end
		-- an attack: the hound - a dash to the player's point after the warning, the shard-thrower - a slow clot (dodged - a miss)
		local A = (C.attack :: any)[e.kind]
		if A and now >= e.attackAt and now >= e.busyUntil and isBusy(e.owner, now) then
			e.attackAt = now + 1 -- the owner is in a menu: the attack is postponed
		elseif A and now >= e.attackAt and now >= e.busyUntil then
			-- attacks only the wave's owner (a passer-by without a dragon does not get hit by foreign hounds)
			local tr = root(e.owner)
			local tp = if tr and (tr.Position - e.body.Position).Magnitude <= A.range then e.owner else nil
			tr = if tp then tr else nil
			e.attackAt = now + A.every[1] + r01() * (A.every[2] - A.every[1])
			if tp and tr then
				local from = e.body.Position
				local to = Vector3.new(tr.Position.X, tr.Position.Y, tr.Position.Z)
				if e.kind == "hound" then
					e.busyUntil = now + A.warn + A.dash + 0.4
					fire({ k = "lunge", id = e.id, from = from, to = to, warn = A.warn, dash = A.dash })
					local ee, AA = e, A
					task.delay(A.warn, function()
						if not ee.model.Parent then
							return
						end
						local start = ee.model:GetPivot()
						local land = CFrame.lookAt(to, to + (to - from) * Vector3.new(1, 0, 1)) -- the strike position
						for i = 1, 4 do
							if not ee.model.Parent then
								return
							end
							ee.model:PivotTo(start:Lerp(land, i / 4))
							task.wait(AA.dash / 4)
						end
						local hr = root(ee.owner) local hp = if hr and (hr.Position - to).Magnitude <= AA.hitRadius then ee.owner else nil
						if hp and hr then
							local ps = state(hp)
							ps.muteUntil = math.max(ps.muteUntil, os.clock() + AA.mute)
							fire({ k = "struck", by = ee.id, seconds = AA.mute }, hp)
						end
					end)
				else
					local dist = (to - from).Magnitude
					local fly = dist / A.speed
					fire({ k = "orb", id = e.id, from = from, to = to, seconds = fly + A.warn, warn = A.warn })
					local ee, AA = e, A
					task.delay(A.warn + fly, function()
						local hr = root(ee.owner) local hp = if hr and (hr.Position - to).Magnitude <= AA.hitRadius then ee.owner else nil
						if hp and hr then
							local ps = state(hp)
							ps.muteUntil = math.max(ps.muteUntil, os.clock() + AA.mute)
							fire({ k = "struck", by = "orb", seconds = AA.mute }, hp)
						end
					end)
				end
			end
		end
		if now < e.busyUntil then
			continue
		end
		-- small Gloom: drift toward the nearest player within the arena, otherwise toward its own point; a touch - the breath goes out
		local pos = e.body.Position
		local target = e.home
		-- drift and touch - only toward the wave's owner (a foreign hunt ring does not choke a neighbor)
		local pr = root(e.owner)
		local p: Player? = if pr and (pr.Position - pos).Magnitude <= C.arena.spread * 2.5 then e.owner else nil
		pr = if p then pr else nil
		if pr and (pr.Position - w.center).Magnitude < C.arena.spread * 3 then
			-- toward the player but not point-blank: a point standoff away from him on the Gloom's side (they circle, touch only if the player flies in himself)
			local away = Vector3.new(pos.X - pr.Position.X, 0, pos.Z - pr.Position.Z)
			local dir = if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis
			local p2 = pr.Position + dir * E.standoff
			target = Vector3.new(p2.X, e.home.Y + (pr.Position.Y - w.center.Y) * (if w.arena == "sky" then 1 else 0), p2.Z)
			if e.hover then -- the egg guards follow the player above the ground (meadow slopes), not at the spawn point height
				target = Vector3.new(p2.X, groundAt(pr.Position, p2.X, p2.Z) + e.hover, p2.Z)
			end
		end
		local v = target - pos
		-- from the ring edge they run to the player fast (visible where they come from), once close - the usual drift
		if e.rush and pr and (pr.Position - pos).Magnitude <= E.standoff + 4 then
			e.rush = nil
		end
		local step = (if e.rush then C.hunt.rush else E.speed) * dt
		local newPos = if v.Magnitude > step then pos + v.Unit * step else target
		if p and pr and (pr.Position - newPos).Magnitude < E.touch then
			local ps = state(p)
			if w.stage > C.attack.calmStages and not isBusy(p, now) and now >= ps.muteUntil and now - (ps.touchAt or 0) >= E.touchEvery then
				ps.touchAt = now
				ps.muteUntil = now + E.touchMute
				fire({ k = "touch", id = e.id, seconds = E.touchMute }, p)
			end
			local away = Vector3.new(newPos.X - pr.Position.X, 0, newPos.Z - pr.Position.Z)
			newPos += (if away.Magnitude > 1e-3 then away.Unit else Vector3.xAxis) * 6
		end
		local face = if pr then Vector3.new(pr.Position.X, newPos.Y, pr.Position.Z) else nil
		local look = if face and (face - newPos).Magnitude > 0.1 then CFrame.lookAt(newPos, face) else CFrame.new(newPos)
		e.model:PivotTo(look)
	end
end

-- ---------------------------------------------------------------------------------------------- players
local function onPlayer(player: Player)
	state(player)
	if C.autoForGroup then
		task.spawn(function()
			local gid = Config.Rewards.freeGift.groupId
			if gid == 0 then
				return
			end
			-- both group checks failed - warn and a retry after 30 / 60 / 120 s, not a silent "no AUTO"
			for attempt = 1, 4 do
				local ok, res = pcall(function()
					return (player :: any):IsInGroupAsync(gid)
				end)
				if not ok then
					ok, res = pcall(function()
						return player:IsInGroup(gid)
					end)
				end
				if player.Parent ~= Players then
					return
				end
				if ok then
					player:SetAttribute("AutoBreath", res == true)
					return
				end
				warn("[Combat] group check for AUTO (" .. player.Name .. ", attempt " .. attempt .. "): " .. tostring(res))
				task.wait(30 * 2 ^ (attempt - 1))
			end
		end)
	end
end

-- Admin/P8 probes: the combat stage ("stage N") and a mute reset
function Combat.debug(player: Player, verb: string, arg: string): any
	if verb == "stage" then
		local n = math.clamp(tonumber(arg) or 0, 0, #C.stages)
		dropWave(player, "meadow")
		dropWave(player, "sky")
		services.PlayerData.update(player, "combat", function(c: any, d: any)
			c = combatData(d)
			c.stage = n
			return c
		end)
		state(player).nextAt = { meadow = 0, sky = 0 }
		return { ok = true, reason = tostring(n) }
	elseif verb == "clear" then -- the own wave cleared as a victory - the reward, lastEnd, the pacing history
		local s = state(player)
		for _, arena in { "meadow", "sky", "glow" } do -- and the glowing egg guards (the P8 chase probe)
			local w = s.waves[arena]
			if w then
				for _, e in w.enemies do
					removeEnemy(e)
				end
				w.left = 0
				clearWave(player, w)
				return { ok = true, reason = arena .. ":" .. tostring(w.stage) }
			end
		end
		return { ok = false, reason = "nowave" }
	elseif verb == "info" then
		local s = state(player)
		local out = {}
		for arena, w in s.waves do
			local list = {}
			for id, e in (w :: Wave).enemies do
				table.insert(list, { id = id, hp = e.hp, pos = { math.floor(e.body.Position.X), math.floor(e.body.Position.Y), math.floor(e.body.Position.Z) } })
			end
			out[arena] = { stage = (w :: Wave).stage, left = (w :: Wave).left, replay = (w :: Wave).replay, enemies = list }
		end
		local data = services.PlayerData.get(player)
		local cd = if data then combatData(data) else nil
		-- JSON without spaces in reason: LoopDebug (P8 probes) prints reply.ok/reply.reason on one line
		return { ok = true, reason = game:GetService("HttpService"):JSONEncode({ waves = out, power = if data then CombatCore.power(data, os.time(), C, B) else 0,
			total = serverCount(), stage = if cd then cd.stage else -1, hits = why, coins = if data then data.coins else 0,
			-- hunt debugging - how many seconds ago the client reported "menu" (-1 - free), until the announced wave, since the end of the previous one
			busy = if s.busyAt then math.floor(os.clock() - s.busyAt) else -1, huntIn = if s.huntAt then math.floor(s.huntAt - os.clock()) else -1,
			sinceEnd = if s.lastEnd then math.floor(os.clock() - s.lastEnd) else -1,
			-- why the hunt waits / came (Core/Combat.huntReady), waves in 5 min, the fight share in 3 min, the profile counters
			why = s.huntWhy or "", waves5 = CombatCore.wavesIn(s.hist, os.clock(), C.hunt.cap.window),
			share3 = math.floor(CombatCore.fightShare(s.hist, os.clock(), C.hunt.share.window) * 100 + 0.5),
			wavesAll = if cd then cd.waves else 0, fightSec = if cd then cd.fightSec else 0,
			shelf = if data and data.eggs and data.eggs.shelf then #data.eggs.shelf else 0 }) }
	end
	return { ok = false, reason = "bad_request" }
end

-- THE GUARDS
-- of the glowing egg - a sky Gloom wave around the egg (the same enemies and movement as in the live sky fight), Config.Glow.egg.guards enemies, without
-- stage progression (replay). Cleared - Services/GlowEgg opens the egg. The player is far - the guards leave (they return on approach).
function Combat.guardEgg(player: Player, center: Vector3, stage: number?): boolean
	local s = state(player)
	if s.waves.glow then
		return true
	end
	local G = Config.Glow and Config.Glow.egg
	countOverride = G and G.guards or 3
	-- the nest is on the meadow - meadow Gloom of the needed power (stage), otherwise sky Gloom
	local ok, w = pcall(spawnWave, player, "glow", stage or CombatCore.firstSky(C), true, center)
	countOverride = nil
	if not ok or not w then
		return false
	end
	s.waves.glow = w
	publishWave(player, w)
	return true
end

function Combat.eggGuarded(player: Player): boolean
	local s = states[player]
	return s ~= nil and s.waves.glow ~= nil
end

function Combat.dropEggGuard(player: Player)
	if states[player] and states[player].waves.glow then
		dropWave(player, "glow")
	end
end

-- THE PACK - three Gloom Hounds (Config.Glow.egg.chase) sleep
-- in a crescent behind the golden nest on the side away from home (placePack); approaching does not wake them. Took the egg (wakePack) - "Zz" -> "!", they stand up, after wake s
-- they run IN A COLUMN: the leader toward the thief at share of the thief's top speed (by attempt: the first passable, every capture - slower),
-- the two others along the leader's trail gaps studs behind. Only the leader catches (closer than catch). The thief in his lot - the leader stops at the line for gateHold
-- s, the pack goes back to the nest and melts; caught or fell behind - the pack returns to its spots and sleeps again. Movement every frame (Heartbeat), not a breath
-- target (tag GloomChase), the Awake attribute - for the thief's music.
local CH = Config.Glow and Config.Glow.egg and Config.Glow.egg.chase

-- the pack is generalized - a string key: the personal pack of the golden nest "glow:<uid>" (the old
-- placePack/wakePack API is kept) and the shared Gloom nests of Services/Raid "raid:<id>" (placePackAt/wakePackAt). The numbers and the finish are in the
-- pack itself: safe(thief) -> (true, the stop point) is decided by the pack's owner (the lot line or the own dragon), fade - after the finish it melts (the golden
-- nest) or returns to the spots and sleeps again (a shared nest, the egg appears there again)
type PackCfg = { kind: string, scale: number, name: string, count: number, spots: { { number } }, sleepK: number, standK: number,
	wake: number, catch: number, lose: number, maxSec: number, gateHold: number, retreat: number, returnSpeed: number, minSpeed: number,
	gaps: { number }, fade: boolean }

type Pack = {
	key: string,
	state: string, -- sleep | wake | chase | gate | return | leave
	since: number,
	hounds: { Enemy },
	spots: { Vector3 }, -- the resting spots (ground)
	nest: Vector3,
	cfg: PackCfg,
	h: number, -- the guardian model height (studs)
	owner: Player?, -- the thief: from waking until the end of the chase
	fixedOwner: Player?, -- a personal pack (the golden nest): the owner's OwnerId even while asleep
	share: number,
	trail: { Vector3 }, -- the leader's trail (points every 0.1 s)
	trailAt: number,
	onEnd: ((string, Vector3?, any) -> ())?,
	safe: ((Player) -> (boolean, Vector3?))?,
	gateAt: Vector3?,
	arrivedAt: number?,
	minGap: number,
	startedAt: number,
	wakeOnce: number?, -- the wake delay of this chase (a newcomer's first egg - longer), otherwise cfg.wake
}
local packs: { [string]: Pack } = {}

local function glowKey(player: Player): string
	return "glow:" .. player.UserId
end

local function topSpeed(player: Player, r: BasePart): number
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local top = if hum then hum.WalkSpeed else Config.Dragon.walkSpeed
	if player:GetAttribute("Mounted") ~= nil then
		local def = Config.Dragon.stages[(tonumber(player:GetAttribute("CompanionStage")) or 1) + 1]
		top = math.max(top, if def then def.speed or 0 else 0)
	end
	-- the instantaneous speed (dashes, server teleports) gave the leader 14.5 instead of 12.8; on a raid the thief is on foot - walking only
	return top
end

local function heightOf(kind: string, scale: number): number
	local spec = (C.models :: any)[kind]
	return (if spec then spec.height else 5) * scale
end

local function mark(e: Enemy, text: string, color: Color3)
	local bb = e.body:FindFirstChild("Mark")
	local t = bb and bb:FindFirstChild("T")
	if t and t:IsA("TextLabel") then
		t.Text = text
		t.TextColor3 = color
	end
end

local function setPackOwner(pk: Pack, owner: Player?)
	local prev = pk.owner
	if prev and prev ~= owner and prev.Parent == Players then
		prev:SetAttribute("GlowChase", nil)
	end
	pk.owner = owner
	local shown = owner or pk.fixedOwner
	for _, e in pk.hounds do
		e.owner = owner :: any
		if e.model.Parent then
			e.model:SetAttribute("OwnerId", if shown then shown.UserId else 0)
		end
	end
end

local function dropPackAt(key: string)
	local pk = packs[key]
	packs[key] = nil
	if pk then
		for _, e in pk.hounds do
			removeEnemy(e)
		end
		local o = pk.owner
		if o and o.Parent == Players then
			o:SetAttribute("GlowChase", nil)
		end
	end
end

local function dropPack(player: Player)
	dropPackAt(glowKey(player))
end

local function endPack(pk: Pack, why: string, at: Vector3?)
	if pk.state ~= "chase" and pk.state ~= "wake" then
		return
	end
	local info = { tries = 0, sec = math.floor((os.clock() - pk.startedAt) * 10 + 0.5) / 10, gap = math.floor(pk.minGap + 0.5) }
	pk.state = if why == "home" then "gate" else "return"
	pk.since = os.clock()
	local o = pk.owner
	if o and o.Parent == Players then
		o:SetAttribute("GlowChase", nil)
	end
	for _, e in pk.hounds do
		e.model:SetAttribute("Awake", nil)
	end
	local cb = pk.onEnd
	pk.onEnd = nil
	if cb then
		task.spawn(function() -- the callback writes the profile - not within the Heartbeat frame
			local ok, err = pcall(cb, why, at, info)
			if not ok then
				warn("[Combat] pack " .. why .. ": " .. tostring(err))
			end
		end)
	end
end

-- a body step toward the goal (along the ground: the center at k of the height h above the floor), facing the way or toward face
local function stepHound(e: Enemy, goal: Vector3, speed: number, dt: number, k: number, face: Vector3?, h: number): number
	local pos = e.body.Position
	local flat = Vector3.new(goal.X - pos.X, 0, goal.Z - pos.Z)
	local d = flat.Magnitude
	local step = speed * dt
	local np = if d > step then pos + flat.Unit * step else Vector3.new(goal.X, pos.Y, goal.Z)
	local y = groundAt(pos, np.X, np.Z) + h * k
	local ny = pos.Y + math.clamp(y - pos.Y, -20 * dt, 20 * dt) -- up-down smoothly (standing up, steps)
	np = Vector3.new(np.X, ny, np.Z)
	local look = face or (if d > 0.2 then np + flat.Unit else nil)
	e.model:PivotTo(if look and (Vector3.new(look.X, np.Y, look.Z) - np).Magnitude > 0.1 then CFrame.lookAt(np, Vector3.new(look.X, np.Y, look.Z)) else e.model:GetPivot().Rotation + np)
	return d
end

-- the point on the leader's trail dist studs behind its head
local function trailPoint(pk: Pack, lead: Vector3, dist: number): Vector3
	local left = dist
	local prev = lead
	for i = #pk.trail, 1, -1 do
		local q = pk.trail[i]
		local seg = Vector3.new(prev.X - q.X, 0, prev.Z - q.Z).Magnitude
		if seg >= left then
			return prev:Lerp(q, left / math.max(seg, 1e-3))
		end
		left -= seg
		prev = q
	end
	return prev
end

local function lieDown(pk: Pack)
	for i, e in pk.hounds do
		e.model:PivotTo(CFrame.lookAt(e.body.Position, Vector3.new(pk.nest.X, e.body.Position.Y, pk.nest.Z)))
		stepHound(e, pk.spots[i], 0, 1, pk.cfg.sleepK, pk.nest, pk.h) -- lie down (the center at sleepK of the height)
		mark(e, "Zz", Color3.fromRGB(200, 210, 255))
	end
	pk.state, pk.since = "sleep", os.clock()
	setPackOwner(pk, nil)
end

local function movePacks(now: number, dt: number)
	for key, pk in packs do
		local lead = pk.hounds[1]
		if not lead or not lead.model.Parent then
			dropPackAt(key)
			continue
		end
		local cfg = pk.cfg
		local owner = pk.owner
		local r = if owner and owner.Parent == Players then root(owner) else nil
		local t = now - pk.since
		if pk.state == "sleep" then
			continue -- they lie on the anchor
		elseif pk.state == "demo" then
			continue -- the bot's demo raid - the pack's movement is driven by Services/Crowd (Combat.demoStep)
		elseif pk.state == "wake" then
			for _, e in pk.hounds do -- they stand up (the center sleepK -> standK of the height), look at the thief
				stepHound(e, e.body.Position, 0, dt, cfg.standK, if r then r.Position else nil, pk.h)
			end
			if t >= (pk.wakeOnce or cfg.wake) then
				pk.state, pk.since = "chase", now
				pk.trail, pk.trailAt = { lead.body.Position }, now
			end
		elseif pk.state == "chase" then
			if not owner or not r then
				endPack(pk, "lost", nil) -- the thief left the server / no character
				continue
			end
			local rp = r.Position
			if pk.safe then
				local ok, stopAt = pk.safe(owner)
				if ok then
					pk.gateAt = stopAt or rp
					endPack(pk, "home", nil)
					continue
				end
			end
			local speed = math.max(cfg.minSpeed, pk.share * topSpeed(owner, r))
			local gap = stepHound(lead, rp, speed, dt, cfg.standK, nil, pk.h)
			pk.minGap = math.min(pk.minGap, gap)
			if now - pk.trailAt >= 0.1 then
				pk.trailAt = now
				table.insert(pk.trail, lead.body.Position)
				if #pk.trail > 300 then
					table.remove(pk.trail, 1)
				end
			end
			for i = 2, #pk.hounds do -- in a column along the leader's trail, not overtaking it
				local e = pk.hounds[i]
				local tp = trailPoint(pk, lead.body.Position, cfg.gaps[i - 1] or 6 * (i - 1))
				local far = (Vector3.new(tp.X, 0, tp.Z) - Vector3.new(e.body.Position.X, 0, e.body.Position.Z)).Magnitude
				stepHound(e, tp, speed * (if far > 3 then 1.25 else 1), dt, cfg.standK, nil, pk.h)
			end
			-- the capture ignores the menu -
			-- as in Steal An Egg, an open menu does not save you from the chase
			if gap <= cfg.catch then
				endPack(pk, "caught", rp)
			elseif gap > cfg.lose or now - pk.startedAt > cfg.maxSec then
				endPack(pk, "lost", nil)
			end
		elseif pk.state == "gate" then
			-- the leader reaches the finish point (the lot line / dragonStop from the dragon) and stands for gateHold s facing the thief; the rest behind it
			local at = pk.gateAt or lead.body.Position
			local d = stepHound(lead, at, cfg.minSpeed * 1.3, dt, cfg.standK, if r then r.Position else nil, pk.h)
			if d < 1 and not pk.arrivedAt then
				pk.arrivedAt = now -- stand gateHold s from arriving at the line, not from the end of the chase
			end
			if pk.arrivedAt and now - pk.arrivedAt > cfg.gateHold then
				if cfg.fade then
					pk.state, pk.since = "leave", now
					for _, e in pk.hounds do
						local parts: { [BasePart]: number } = {}
						for _, p in e.model:GetDescendants() do
							if p:IsA("BasePart") and p ~= e.body then
								parts[p] = p.Transparency
							end
						end
						e.parts = parts
					end
				else
					pk.state, pk.since = "return", now
					pk.arrivedAt = nil
				end
			end
		elseif pk.state == "return" then
			-- caught, fell behind or the finish at a shared nest: to the spots and sleep again
			local all = true
			for i, e in pk.hounds do
				local d = stepHound(e, pk.spots[i], cfg.returnSpeed, dt, cfg.standK, nil, pk.h)
				if d > 0.5 then
					all = false
				end
			end
			-- (P8 dailyraid_check: after a successful raid the guardian walked 8 s (88 studs) from the lot line ~100 studs away and fell asleep on the thief's
			-- path - the next theft was caught the moment it woke): 14 s for the return; did not make it - a teleport to the spot, then sleep
			if all or t > 14 then
				if not all then
					for i, e in pk.hounds do
						stepHound(e, pk.spots[i], 1e4, 1, cfg.standK, nil, pk.h)
					end
				end
				lieDown(pk)
			end
		elseif pk.state == "leave" then
			local f = math.clamp(t / cfg.retreat, 0, 1)
			for _, e in pk.hounds do
				stepHound(e, pk.nest, cfg.returnSpeed, dt, cfg.standK, nil, pk.h)
				for p, base in e.parts or {} do
					p.Transparency = base + (1 - base) * f
				end
			end
			if f >= 1 then
				dropPackAt(key)
			end
		end
	end
end

local function packCfg(o: any?): PackCfg
	local d = (o or {}) :: any
	local base = (CH or {}) :: any
	local function pick(name: string, fallback: any): any
		local v = d[name]
		if v == nil then
			v = base[name]
		end
		if v == nil then
			v = fallback
		end
		return v
	end
	return {
		kind = pick("kind", "hound"), scale = pick("scale", 1), name = pick("name", "Gloom Hound"), count = pick("count", 1),
		spots = pick("spots", { { 5, 0 } }), sleepK = pick("sleepK", 0.4), standK = pick("standK", 0.5), wake = pick("wake", 1),
		catch = pick("catch", 6), lose = pick("lose", 100), maxSec = pick("maxSec", 60), gateHold = pick("gateHold", 0.8),
		retreat = pick("retreat", 2.5), returnSpeed = pick("returnSpeed", 11), minSpeed = pick("minSpeed", 11), gaps = pick("gaps", { 6, 12 }),
		fade = if d.fade ~= nil then d.fade == true else true,
	}
end

-- the pack at the nest nest: resting spots behind the nest on the side away from gate (gate - the "home" reference: the lot gate or the island center);
-- opts - the pack numbers (PackCfg, default Config.Glow.egg.chase); the key key - "glow:<uid>" or "raid:<id>"
-- whether the player has a wave or an announced hunt - the storm (Weather) does not start over a fight
function Combat.fighting(player: Player): boolean
	local s = states[player]
	return s ~= nil and (s.waves.meadow ~= nil or s.waves.sky ~= nil or s.huntAt ~= nil)
end

function Combat.placePackAt(key: string, nest: Vector3, gate: Vector3, opts: any?): boolean
	if not C.on or not CH or not CH.on or not folder then
		return false
	end
	if packs[key] then
		dropPackAt(key)
	end
	local cfg = packCfg(opts)
	if serverCount() + cfg.count > C.enemy.maxPerServer then
		return false
	end
	local h = heightOf(cfg.kind, cfg.scale)
	local u = Vector3.new(gate.X - nest.X, 0, gate.Z - nest.Z)
	u = if u.Magnitude > 0.1 then u.Unit else Vector3.xAxis
	local v = Vector3.new(-u.Z, 0, u.X)
	local spots: { Vector3 } = {}
	for i, off in cfg.spots do -- { back from the nest, sideways }
		local q = nest - u * off[1] + v * off[2]
		spots[i] = Vector3.new(q.X, groundAt(nest, q.X, q.Z), q.Z)
	end
	local hounds: { Enemy } = {}
	local w: Wave = { arena = "glowchase", stage = 0, replay = true, center = nest, enemies = {}, left = cfg.count, hpTotal = 0, dealt = {},
		startedAt = os.clock(), pulses = 0, warned = 0 }
	for i = 1, cfg.count do
		nextId += 1
		local id = tostring(nextId)
		local at = (spots[i] or spots[1]) + Vector3.new(0, h * cfg.sleepK, 0)
		local m, body = buildEnemy(id, at, C.enemy.size[2] * cfg.scale, false, nil, cfg.kind, cfg.scale)
		m:PivotTo(CFrame.lookAt(at, Vector3.new(nest.X, at.Y, nest.Z)))
		m:SetAttribute("Kind", cfg.kind)
		m:SetAttribute("Id", id)
		m:SetAttribute("OwnerId", 0)
		m:SetAttribute("Arena", "glowchase")
		m:SetAttribute("Chase", true)
		m:SetAttribute("PackKey", key)
		CollectionService:AddTag(m, "GloomChase")
		local bb = Instance.new("BillboardGui") -- the guardian's name and "Zz" / "!" above each
		bb.Name = "Mark"
		bb.Size = UDim2.fromOffset(120, 56)
		bb.StudsOffsetWorldSpace = Vector3.new(0, h * 0.75 + 1, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.MaxDistance = 90
		local t = Instance.new("TextLabel")
		t.Name = "T"
		t.Size = UDim2.new(1, 0, 0.62, 0)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.Text = "Zz"
		t.TextColor3 = Color3.fromRGB(200, 210, 255)
		t.TextStrokeTransparency = 0.2
		t.Parent = bb
		local n = Instance.new("TextLabel")
		n.Name = "N"
		n.Position = UDim2.fromScale(0, 0.62)
		n.Size = UDim2.new(1, 0, 0.38, 0)
		n.BackgroundTransparency = 1
		n.TextScaled = true
		n.Font = Enum.Font.FredokaOne
		n.Text = cfg.name
		n.TextColor3 = Color3.fromRGB(190, 150, 240)
		n.TextStrokeTransparency = 0.3
		n.Parent = bb
		bb.Parent = body
		m.Parent = folder
		local e: Enemy = { id = id, model = m, body = body, hp = 1, maxHp = 1, owner = (nil :: any), wave = w, guardian = false, home = at,
			radius = body.Size.X / 2, kind = cfg.kind, attackAt = math.huge, busyUntil = 0, chase = true }
		enemies[id] = e
		w.enemies[id] = e
		hounds[i] = e
	end
	packs[key] = { key = key, state = "sleep", since = os.clock(), hounds = hounds, spots = spots, nest = nest, cfg = cfg, h = h, owner = nil, fixedOwner = nil, wakeOnce = nil,
		share = 1, trail = {}, trailAt = 0, onEnd = nil, safe = nil, gateAt = nil, minGap = math.huge, startedAt = os.clock() }
	return true
end

-- the thief thief took the egg: the guardian wakes ("!"), after wake s - the chase; share - the share of the thief's speed (by attempt); safe(thief) -> (finish?,
-- the stop point) every frame; onEnd(why, at, info) once: home | caught | lost
function Combat.wakePackAt(key: string, thief: Player, share: number, onEnd: (string, Vector3?, any) -> (), safe: ((Player) -> (boolean, Vector3?))?, wake: number?): boolean
	local pk = packs[key]
	if not pk or pk.state ~= "sleep" then
		return false
	end
	pk.state, pk.since, pk.startedAt = "wake", os.clock(), os.clock()
	pk.wakeOnce = wake
	pk.share, pk.onEnd, pk.safe, pk.minGap, pk.gateAt, pk.arrivedAt = share, onEnd, safe, math.huge, nil, nil
	setPackOwner(pk, thief)
	thief:SetAttribute("GlowChase", true)
	for _, e in pk.hounds do
		mark(e, "!", Color3.fromRGB(255, 80, 60))
		e.model:SetAttribute("Awake", true)
	end
	return true
end

-- the Gloom models are loaded - place guardians only with the real model, not the fallback figure
function Combat.modelsReady(): boolean
	return ready
end

-- sleep | wake | chase | gate | return | leave | nil (no pack)
-- THE DEMO RAID of a bot (Services/Crowd) at
-- a separate copy nest: the pack sleeps like a real one; demoBegin - "!", it stands up; demoStep - the leader runs to a point (as in the chase, standK);
-- demoEnd - it stood a while, "Zz" is removed by the "return" tick: to the spot and sleep. The tick does not touch a pack in the "demo" state
function Combat.demoBegin(key: string): boolean
	local pk = packs[key]
	if not pk or pk.state ~= "sleep" then
		return false
	end
	pk.state, pk.since = "demo", os.clock()
	for _, e in pk.hounds do
		mark(e, "!", Color3.fromRGB(255, 80, 60))
	end
	return true
end

function Combat.demoStep(key: string, target: Vector3, speed: number, dt: number, face: Vector3?): number?
	local pk = packs[key]
	local lead = pk and pk.hounds[1]
	if not pk or pk.state ~= "demo" or not lead or not lead.model.Parent then
		return nil
	end
	local d = stepHound(lead, target, speed, dt, pk.cfg.standK, face, pk.h)
	for i = 2, #pk.hounds do
		stepHound(pk.hounds[i], lead.body.Position, speed, dt, pk.cfg.standK, nil, pk.h)
	end
	return d
end

function Combat.demoEnd(key: string)
	local pk = packs[key]
	if not pk or pk.state ~= "demo" then
		return
	end
	pk.state, pk.since, pk.arrivedAt = "return", os.clock(), nil
end

function Combat.packStateAt(key: string): string?
	local pk = packs[key]
	return pk and pk.state
end

function Combat.packOwnerAt(key: string): Player?
	local pk = packs[key]
	return pk and pk.owner
end

function Combat.dropPackAt(key: string)
	dropPackAt(key)
end

-- the chase is no longer needed (the egg left the hands not by a capture) - the guardian goes back to sleep, the callback is not called
function Combat.calmPackAt(key: string)
	local pk = packs[key]
	if pk and (pk.state == "chase" or pk.state == "wake") then
		pk.onEnd = nil
		endPack(pk, "lost", nil)
	end
end

-- Services/GlowEgg (spec 26 v2): the personal pack at the golden nest; home - the lot model (the finish - its boundary), melts after the finish
function Combat.placePack(player: Player, nest: Vector3, gate: Vector3, home: Model?): boolean
	local ok = Combat.placePackAt(glowKey(player), nest, gate, { fade = true })
	local pk = packs[glowKey(player)]
	if ok and pk then
		pk.fixedOwner = player
		setPackOwner(pk, nil)
		pk.safe = function(thief: Player): (boolean, Vector3?)
			local r = root(thief)
			if home and home.Parent and r and services.Incubation and services.Incubation.inLot(home, r.Position) then
				return true, r.Position
			end
			return false, nil
		end
	end
	return ok
end

-- safe - its own finish (the thief mounted the dragon, as on rings 1-2), otherwise the lot line from
-- placePack; wake - its own pause before the chase
function Combat.wakePack(player: Player, share: number, onEnd: (string, Vector3?, any) -> (), safe: ((Player) -> (boolean, Vector3?))?, wake: number?): boolean
	local pk = packs[glowKey(player)]
	return Combat.wakePackAt(glowKey(player), player, share, onEnd, safe or (pk and pk.safe), wake)
end

function Combat.packState(player: Player): string?
	return Combat.packStateAt(glowKey(player))
end

function Combat.dropPack(player: Player)
	dropPackAt(glowKey(player))
end

function Combat.calmPack(player: Player)
	Combat.calmPackAt(glowKey(player))
end

function Combat.init(s: { [string]: any })
	services = s
end

function Combat.start()
	if not C.on then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Gloom"
	f.Parent = workspace
	folder = f
	-- the enemy models - in advance: InsertService:LoadAsset waits seconds, and inside the tick it would hold the whole fight (the newcomer's first
	-- wave did not appear while the model loaded)
	-- the models load in parallel; the fight switches on when all are loaded, but no later than preloadTimeout s
	-- (a hung LoadAsset does not switch the fight off on the server forever; not loaded - the fallback figure and a warn)
	ready = false
	local list: { { kind: string, spec: any } } = {}
	for kind, spec in C.models :: any do
		if (spec.id or 0) > 0 and services.ModelLibrary then
			table.insert(list, { kind = kind, spec = spec })
		end
	end
	local left = #list -- the count before the launch (a load without a yield must not set ready before the rest)
	for _, it in list do
		local kind, spec = it.kind, it.spec
		do
			task.spawn(function()
				local ok, err = pcall(services.ModelLibrary.load, spec.id)
				if not ok then
					warn("[Combat] preload " .. kind .. ": " .. tostring(err))
				end
				left -= 1
				if left == 0 then
					ready = true
				end
			end)
		end
	end
	if left == 0 then
		ready = true
	end
	task.delay(C.preloadTimeout or 20, function()
		if not ready then
			warn("[Combat] the model preload did not finish within " .. tostring(C.preloadTimeout or 20) .. " s - the fight is on, unloaded ones use the fallback figure")
			ready = true
		end
	end)
	local remotes = ReplicatedStorage:WaitForChild(Remotes.Folder)
	fx = remotes:WaitForChild("CombatFx") :: RemoteEvent
	local breath = remotes:WaitForChild("Breath") :: RemoteEvent
	local per = Config.RateLimit.Breath or 5
	local lastCall: { [Player]: number } = {}
	breath.OnServerEvent:Connect(function(player: Player, id: any)
		local t = os.clock()
		if lastCall[player] and t - lastCall[player] < 1 / per then
			count("rate")
			return
		end
		lastCall[player] = t
		local ok, err = pcall(onBreath, player, id)
		if not ok then
			warn("[Combat] breath: " .. tostring(err))
		end
	end)
	-- the client reports "a menu is open / a scene is playing" (HUD.setVisible) - ambushes wait; no more often than 4/s
	local busyRemote = remotes:WaitForChild("UiBusy") :: RemoteEvent
	busyRemote.OnServerEvent:Connect(function(player: Player, v: any)
		local t = os.clock()
		if typeof(v) ~= "boolean" then
			return
		end
		-- the 0.25 s filter could drop exactly "menu open" - the assignment is cheap, the last value applies
		local ps = state(player)
		if not v and ps.busyAt then
			ps.busyEnd = t -- the hunt does not come earlier than hunt.afterBusy s after the menu / scene closes
		end
		ps.busyAt = if v then t else nil
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
	Players.PlayerRemoving:Connect(function(p)
		dropWave(p, "meadow", true)
		dropWave(p, "sky", true)
		dropWave(p, "glow", true) -- the glowing egg guards and pack do not stay in the world after leaving
		dropPack(p)
		for key, pk in packs do -- a shared guardian chased one who left - back to sleep
			if pk.owner == p then
				Combat.calmPackAt(key)
			end
		end
		states[p] = nil
		missAt[p] = nil
		lastCall[p] = nil
		for _, e in enemies do
			e.wave.dealt[p] = nil
		end
	end)
	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(C.enemy.tick)
			local now = os.clock()
			local dt = math.min(now - last, 0.5)
			last = now
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(tickPlayer, p, now)
				if not ok then
					warn("[Combat] tick " .. p.Name .. ": " .. tostring(err))
				end
			end
			local ok, err = pcall(tickEnemies, now, dt)
			if not ok then
				warn("[Combat] enemies: " .. tostring(err))
			end
		end
	end)
	-- every frame, only for those who have a pack; an error - a warn once per 10 s, not every frame
	if CH and CH.on then
		local warnedAt = -math.huge
		RunService.Heartbeat:Connect(function(dt: number)
			local ok, err = pcall(movePacks, os.clock(), math.min(dt, 0.1))
			if not ok and os.clock() - warnedAt > 10 then
				warnedAt = os.clock()
				warn("[Combat] chase: " .. tostring(err))
			end
		end)
	end
end

return Combat
