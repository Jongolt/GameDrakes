--!strict
-- Anti-cheat on the server (Config.AntiCheat). A Roblox client with a cheat program (an executor, any "level") controls
-- only its own side: calls our Remotes any way it likes, moves its character and companion (it holds network ownership), presses
-- prompts and touches from afar (fireproximityprompt, firetouchinterest, replicatesignal). The server trusts only itself:
-- position - AntiCheat.pos (Nest.rootPos): a new point is accepted if it is reachable (maxH / maxUp + the slack bank);
-- flight and hovering (in the air longer than airMax without descending by minSink), running on the ground faster than groundAvgMax on average over
-- groundWindow (jumps do not reset the window), spinning (fling) - a violation; the closed Frost Isle - a violation;
-- a violation - the character returns to the honest point (flight - to the last point on the ground), for "near" checks the
-- honest point stays, anticheat_teleport goes to analytics (every logEvery-th). No kick for movement: the network can be uneven;
-- AntiCheat.near - the "near" check for prompts and touches (they can be pressed from the other end of the map);
-- the companion (the client holds network ownership): spinning or a speed above companionMaxSpeed on foot - the speed to zero, ownership
-- to the server for companionHold s;
-- collisions: characters on foot - the Player group, they do not collide with each other or with riders (nothing to fling with);
-- foreign scripts: Script/LocalScript/ModuleScript in Workspace outside characters - deleted (backdoors from models), foreign_script;
-- rate: more egg pickups per rateWindow than rates.egg - anticheat_rate (a mark only).
-- "Ground" for flight and running: a ray down groundProbe (water counts), CanCollide parts without CanQuery (steps, rock colliders -
-- the ray does not see them) - by the box index, companions - live. Mounted and in any Seat not checked (flight - Movement.check).
-- Server relocations call AntiCheat.moved. Studio: without enforce it only counts (P8 probes move the character themselves);
-- ServerStorage.AntiCheatDebug - for the cheat_check probe.

local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local AntiCheat = {}

local AC = Config.AntiCheat
local FROST = Config.World.frostIsle

type Track = {
	root: BasePart,
	pos: Vector3, -- the last honest point
	at: number, -- os.clock() of the honest point
	h: number, -- the horizontal bank (studs)
	up: number, -- the upward bank
	born: number, -- os.clock() of the character's appearance
	settled: boolean,
	graceUntil: number,
	prev: Vector3?, -- the point before a server relocation (the client returning to it within grace is not a violation)
	seated: boolean,
	ground: Vector3?, -- the last honest point on the ground (the return point for flight)
	airAt: number?, -- since when in the air
	airY: number, -- the height at the start of the flight
	walk: { at: number, pos: Vector3 }?, -- the ground running window
	landedAt: number?, -- the moment of touching the ground after a long flight/glide - the running window waits AC.landGrace
}

local services: { [string]: any } = {}
local track: { [Player]: Track } = {}
local violations: { [Player]: number } = {} -- per session (analytics, probe)
local stats = { violations = 0, corrected = 0, observed = 0, last = "", why = {} :: { [string]: number }, scripts = 0, companion = 0 }
local rates: { [Player]: { [string]: { n: number, since: number, told: boolean } } } = {}

local function enforce(): boolean
	return AC.on and (not RunService:IsStudio() or AC.studioEnforce == true)
end

local function body(player: Player): (BasePart?, Humanoid?, Model?)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if ch and root and root:IsA("BasePart") and hum and hum.Health > 0 and ch.Parent == Workspace then
		return root, hum, ch
	end
	return nil, nil, nil
end

-- ---------------------------------------------------------------------------------------------- spawn, water, stream, ground
local spawns: { SpawnLocation } = {}
-- the HomeSpawn of the own lot (Nest.homeSpawn) is set after the first spawns pass - the player's own spawn point (RespawnLocation) is checked separately
local function spawnNear(p: Vector3, player: Player?): (boolean, Vector3?)
	if #spawns == 0 then -- once: the world is built by services at start, the spawn exists by the first character
		for _, s in Workspace:GetDescendants() do
			if s:IsA("SpawnLocation") then
				table.insert(spawns, s)
			end
		end
	end
	local best: Vector3? = nil
	local bestD = math.huge
	local own = if player then player.RespawnLocation else nil
	for _, s in if own and own.Parent then { own, table.unpack(spawns) } else spawns do
		if s.Parent then
			local d = (Vector3.new(p.X, 0, p.Z) - Vector3.new(s.Position.X, 0, s.Position.Z)).Magnitude
			if d < bestD then
				bestD = d
				best = s.Position + Vector3.new(0, 4, 0)
			end
		end
	end
	return best == nil or bestD <= AC.spawnRadius, best
end

-- terrain water in an 8-stud cube around the point (one swims only in Terrain water); failed to read - treat as water (do not bother honest players)
function AntiCheat.inWater(p: Vector3): boolean
	-- the ReadVoxels array carries a Size field (Vector3) - the pass "for _, plane in mats" tripped
	-- over it ("attempt to iterate over a Vector3 value"), check() crashed in the air and over water: flight was not caught, Back to shore broke
	local ok, found = pcall(function()
		local region = Region3.new(p - Vector3.new(4, 4, 4), p + Vector3.new(4, 4, 4)):ExpandToGrid(4)
		local mats = Workspace.Terrain:ReadVoxels(region, 4)
		local size = mats.Size
		for x = 1, size.X do
			for y = 1, size.Y do
				for z = 1, size.Z do
					if mats[x][y][z] == Enum.Material.Water then
						return true
					end
				end
			end
		end
		return false
	end)
	if not ok then
		return true
	end
	return found == true
end

local function inBox(part: BasePart, p: Vector3, margin: number, above: number): boolean
	local lp = part.CFrame:PointToObjectSpace(p)
	local s = part.Size / 2
	return math.abs(lp.X) <= s.X + margin and math.abs(lp.Z) <= s.Z + margin and lp.Y >= -s.Y - margin and lp.Y <= s.Y + above
end

local function inUpdraft(p: Vector3): boolean
	for _, u in CollectionService:GetTagged("Updraft") do
		if u:IsA("BasePart") and inBox(u, p, AC.updraftMargin, AC.updraftMargin * 2) then
			return true
		end
	end
	return false
end

-- dragons, companions, characters and mannequins - moving models (not in the collider index, the "ground" rides on them)
local function isMover(inst: Instance): boolean
	local m = inst:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:GetAttribute("Uid") ~= nil or m:GetAttribute("Companion") ~= nil or m:FindFirstChildOfClass("Humanoid") then
			return true
		end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return false
end

-- colliders the ray does not see (CanCollide and not CanQuery: steps, rock bodies) - boxes; refreshed every colliderEvery s
local colliders: { BasePart } = {}
local collidersAt = -math.huge
local function refreshColliders()
	collidersAt = os.clock()
	local out = {}
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide and not d.CanQuery and d.Anchored and not isMover(d) then
			table.insert(out, d)
		end
	end
	colliders = out
end

local GROUND_BOX = Vector3.new(AC.groundBox[1], AC.groundBox[2], AC.groundBox[3])
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = false

-- whether the character is on the ground (feet = root - 3) and not on a moving one (a dragon, a companion: the "ground" moves - running is not counted)
local function groundState(ch: Model, p: Vector3): (boolean, boolean)
	rayParams.FilterDescendantsInstances = { ch }
	-- a box wider than the character, not a ray from the center: at a cliff edge the center is already over the void while the feet are still on the rock
	local hit = Workspace:Blockcast(CFrame.new(p), GROUND_BOX, Vector3.new(0, -AC.groundProbe, 0), rayParams)
	if hit then
		if hit.Material == Enum.Material.Water then
			return true, false
		end
		return true, isMover(hit.Instance)
	end
	if os.clock() - collidersAt > AC.colliderEvery then
		refreshColliders()
	end
	local feet = p - Vector3.new(0, 3, 0)
	for _, c in colliders do
		if c.Parent and inBox(c, feet, 2, AC.groundProbe - 3) then
			return true, false
		end
	end
	local comp = Workspace:FindFirstChild("Companions")
	if comp then -- standing on a companion (own or foreign): the body moves, it is not in the index
		for _, m in comp:GetChildren() do
			if m:IsA("Model") then
				local cf, size = m:GetBoundingBox()
				local lp = cf:PointToObjectSpace(feet)
				if math.abs(lp.X) <= size.X / 2 + 2 and math.abs(lp.Z) <= size.Z / 2 + 2 and math.abs(lp.Y) <= size.Y / 2 + 4 then
					return true, true
				end
			end
		end
	end
	if AntiCheat.inWater(p) then
		return true, false
	end
	return false, false
end

-- ---------------------------------------------------------------------------------------------- violation
local function newTrack(root: BasePart, now: number): Track
	return { root = root, pos = root.Position, at = now, h = AC.slack, up = AC.slack, born = now, settled = false, graceUntil = 0, prev = nil,
		seated = false, ground = nil, airAt = nil, airY = root.Position.Y, walk = nil }
end

local function rebase(t: Track, p: Vector3, now: number)
	t.pos = p
	t.at = now
	t.h = AC.slack
	t.up = AC.slack
	t.airAt = nil
	t.walk = nil
end

local function violation(player: Player, t: Track, raw: Vector3, now: number, why: string): Vector3?
	stats.violations += 1
	stats.why[why] = (stats.why[why] or 0) + 1
	local n = (violations[player] or 0) + 1
	violations[player] = n
	stats.last = string.format("%s %s from %.0f,%.0f,%.0f to %.0f,%.0f,%.0f", player.Name, why, t.pos.X, t.pos.Y, t.pos.Z, raw.X, raw.Y, raw.Z)
	if not enforce() then -- Studio without enforce: a count only, the point is accepted
		stats.observed += 1
		rebase(t, raw, now)
		return raw
	end
	local _, _, ch = body(player)
	if ch then
		pcall(function()
			ch:PivotTo(CFrame.new(t.pos) * t.root.CFrame.Rotation)
			t.root.AssemblyLinearVelocity = Vector3.zero
			t.root.AssemblyAngularVelocity = Vector3.zero
		end)
		stats.corrected += 1
	end
	t.prev = raw -- the client will still send the old point until it accepts the return
	t.graceUntil = now + AC.grace
	t.at = now -- time outside the honest point does not accumulate slack
	t.airAt = nil
	t.walk = nil
	if n % AC.logEvery == 1 then
		warn("[AntiCheat] " .. stats.last .. " (" .. n .. ")")
		if services.Analytics then
			pcall(services.Analytics.custom, player, "anticheat_teleport", n, { why = why })
		end
	end
	return t.pos
end

-- flight, running on the ground, a closed zone: the point already passed by speed; return the violation reason and where to return to
local function moveChecks(ch: Model, t: Track, raw: Vector3, now: number): (string?, Vector3?)
	if FROST and FROST.open ~= true and raw.X > FROST.wallX then -- Frost Isle is closed: an invisible wall, but walls are passed (noclip)
		local back = t.ground or t.pos
		if back.X > FROST.wallX then
			local _, sp = spawnNear(raw)
			back = sp or Vector3.new(0, 20, 0)
		end
		return "zone", back
	end
	local grounded, onMover = groundState(ch, raw)
	local up = inUpdraft(raw)
	-- a landing after
	-- a long flight is remembered, the running window starts only after AC.landGrace
	local wasLongAir = t.airAt ~= nil and now - (t.airAt :: number) > AC.jumpGrace
	if grounded or up then
		if wasLongAir and grounded then
			t.landedAt = now
		end
		t.airAt = nil
		if grounded and not onMover then
			t.ground = raw
		end
	elseif not t.airAt then
		t.airAt = now
		t.airY = raw.Y
	else
		local d = now - (t.airAt :: number)
		if d > AC.airMax and (t.airY - raw.Y) < AC.minSink * (d - AC.jumpGrace) then
			return "fly", t.ground or t.pos
		end
	end
	-- running: windows of groundWindow s; a jump (air shorter than jumpGrace) does not reset the window, a fall and gliding do
	local longAir = t.airAt ~= nil and now - (t.airAt :: number) > AC.jumpGrace
	local landing = t.landedAt ~= nil and now - (t.landedAt :: number) < AC.landGrace -- (A1)
	if onMover or up or longAir or landing then
		t.walk = nil
	elseif not t.walk then
		t.walk = { at = now, pos = raw }
	elseif now - (t.walk :: any).at >= AC.groundWindow then
		local w = t.walk :: { at: number, pos: Vector3 }
		local avg = (Vector3.new(raw.X, 0, raw.Z) - Vector3.new(w.pos.X, 0, w.pos.Z)).Magnitude / (now - w.at)
		if avg > AC.groundAvgMax then
			return "walk", w.pos
		end
		t.walk = { at = now, pos = raw }
	end
	return nil, nil
end

-- check the player now; returns a position that can be trusted for distances (nil - do not trust: no character or it just appeared)
local function check(player: Player): Vector3?
	local root, hum, ch = body(player)
	if not root or not hum or not ch then
		track[player] = nil
		return nil
	end
	local now = os.clock()
	local t = track[player]
	if not t or t.root ~= root then
		t = newTrack(root, now)
		track[player] = t
	end
	local raw = root.Position
	if not t.settled then
		if now - t.born < AC.spawnSettle then
			return nil
		end
		t.settled = true
		local near, spawnPos = spawnNear(raw, player)
		if near or not spawnPos then
			rebase(t, raw, now)
			return raw
		end
		-- an appearance away from a known spawn - a count and a record only, no relocation (the anti-cheat stays soft)
		stats.why.spawn = (stats.why.spawn or 0) + 1
		if (violations[player] or 0) == 0 then
			warn(string.format("[AntiCheat] %s spawn far from spawns at %.0f,%.0f,%.0f (log only)", player.Name, raw.X, raw.Y, raw.Z))
		end
		rebase(t, raw, now)
		return raw
	end
	if root.AssemblyAngularVelocity.Magnitude > AC.maxSpin then -- spinning (fling): an honest character has single rad/s
		return violation(player, t, raw, now, "spin")
	end
	if hum.SeatPart then -- mounted / on a seat: the seat moves the point, flight is checked by Movement
		if not t.seated then -- mounting: the seat must be where one can honestly walk to (a teleport onto the seat is not a path)
			local d0 = raw - t.pos
			local dt0 = math.max(now - t.at, 0)
			if Vector3.new(d0.X, 0, d0.Z).Magnitude > AC.maxH * dt0 + t.h + AC.seatSlack or d0.Y > AC.maxUp * dt0 + t.up + AC.seatSlack then
				if enforce() then -- take off the seat, then violation returns to the honest point
					local seat = hum.SeatPart
					pcall(function()
						local w = seat and seat:FindFirstChild("SeatWeld")
						if w then
							w:Destroy()
						end
						hum.Sit = false
					end)
					return violation(player, t, raw, now, "seat")
				end
				violation(player, t, raw, now, "seat") -- Studio without enforce: a count only
			end
		end
		t.seated = true
		rebase(t, raw, now)
		return raw
	end
	if t.seated then -- dismount: counting from the current point (Movement places next to the dragon)
		t.seated = false
		rebase(t, raw, now)
		return raw
	end
	local dt = math.max(now - t.at, 0)
	local d = raw - t.pos
	local h = Vector3.new(d.X, 0, d.Z).Magnitude
	local up = math.max(d.Y, 0)
	local allowH = AC.maxH * dt + t.h
	local allowUp = AC.maxUp * dt + t.up
	if h <= allowH and up <= allowUp then
		t.h = math.min(AC.slack, allowH - h)
		t.up = math.min(AC.slack, allowUp - up)
		t.pos = raw
		t.at = now
		local why, back = moveChecks(ch, t, raw, now)
		if why then
			t.pos = back :: Vector3
			return violation(player, t, raw, now, why :: string)
		end
		return raw
	end
	if now < t.graceUntil then
		if t.prev and (raw - (t.prev :: Vector3)).Magnitude <= AC.bounceRadius then
			return t.pos -- the client has not accepted the relocation yet: the old point is not a violation, trust the new one
		end
	end
	return violation(player, t, raw, now, if h > allowH then "speed" else "up")
end

-- the character root position for distance checks (instead of root.Position); several services in one frame - one computation
local cache: { [Player]: { at: number, out: Vector3? } } = {}
function AntiCheat.pos(player: Player): Vector3?
	local now = os.clock()
	local c = cache[player]
	if c and now - c.at < AC.recheck then
		return c.out
	end
	local out = check(player)
	cache[player] = { at = now, out = out }
	return out
end

-- an honest position within radius of the point (prompts and touches can be pressed from the other end of the map: fireproximityprompt etc.)
function AntiCheat.near(player: Player, at: Vector3, radius: number): boolean
	local p = AntiCheat.pos(player)
	local ok = p ~= nil and (p - at).Magnitude <= radius + AC.promptSlack
	if not ok and p ~= nil then
		stats.why.far = (stats.why.far or 0) + 1 -- a press / touch from afar (a count for the probe and analysis)
	end
	return ok
end

-- the server itself relocated the character (PivotTo / CFrame): a new honest point, grace for the old one's return
function AntiCheat.moved(player: Player)
	local root = body(player)
	if not root then
		return
	end
	local now = os.clock()
	local t = track[player]
	if not t or t.root ~= root then -- a relocation before the character's first check: start from the relocation point
		t = newTrack(root, now)
		track[player] = t
	end
	t.prev = t.pos
	t.graceUntil = now + AC.grace
	t.settled = true
	t.ground = nil
	rebase(t, root.Position, now)
	cache[player] = nil
end

function AntiCheat.violations(player: Player): number
	return violations[player] or 0
end

-- action rate (a mark in analytics only): kind = "egg" ...
function AntiCheat.note(player: Player, kind: string)
	local limit = AC.rates[kind]
	if not limit then
		return
	end
	local r = rates[player]
	if not r then
		r = {}
		rates[player] = r
	end
	local now = os.clock()
	local c = r[kind]
	if not c or now - c.since > AC.rateWindow then
		c = { n = 0, since = now, told = false }
		r[kind] = c
	end
	c.n += 1
	if c.n > limit and not c.told then
		c.told = true
		stats.why["rate_" .. kind] = (stats.why["rate_" .. kind] or 0) + 1
		warn(string.format("[AntiCheat] %s rate %s %d in %.0f s", player.Name, kind, c.n, now - c.since))
		if services.Analytics then
			pcall(services.Analytics.custom, player, "anticheat_rate", c.n, { kind = kind })
		end
	end
end

-- ---------------------------------------------------------------------------------------------- companions
local held: { [BasePart]: number } = {} -- the companion body -> until when the server holds ownership
local function checkCompanions(now: number)
	local folder = Workspace:FindFirstChild("Companions")
	if not folder then
		return
	end
	for _, m in folder:GetChildren() do
		local ownerId = m:GetAttribute("OwnerId")
		local b = if m:IsA("Model") then m.PrimaryPart else nil
		-- only the companion on its own (the leash): the hatchling is welded to the character (the character assembly - not touched), mounted - the assembly with the rider
		if b and typeof(ownerId) == "number" and not b.Anchored and not held[b] and b.AssemblyRootPart == b then
			local owner = Players:GetPlayerByUserId(ownerId)
			local mounted = owner ~= nil and owner:GetAttribute("Mounted") ~= nil
			local v = b.AssemblyLinearVelocity
			local spin = b.AssemblyAngularVelocity.Magnitude > AC.companionMaxSpin
			local fast = not mounted and Vector3.new(v.X, 0, v.Z).Magnitude > AC.companionMaxSpeed -- a fall does not count
			if spin or fast then
				stats.companion += 1
				stats.why.companion = (stats.why.companion or 0) + 1
				if enforce() then
					pcall(function()
						b.AssemblyLinearVelocity = Vector3.zero
						b.AssemblyAngularVelocity = Vector3.zero
						b:SetNetworkOwner(nil)
					end)
					held[b] = now + AC.companionHold
				end
			end
		end
	end
	for b, untilAt in held do
		if now >= untilAt or not b.Parent then
			held[b] = nil
			local m = b:FindFirstAncestorWhichIsA("Model")
			local ownerId = m and m:GetAttribute("OwnerId")
			local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
			if owner and b.Parent and not b.Anchored then
				pcall(function()
					b:SetNetworkOwner(owner) -- the leash back to the owner (Movement hands ownership over the same way)
				end)
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------- collisions
local playerGroup = false
local function setupGroups()
	local ok = pcall(function()
		if not PhysicsService:IsCollisionGroupRegistered("Player") then
			PhysicsService:RegisterCollisionGroup("Player")
		end
		PhysicsService:CollisionGroupSetCollidable("Player", "Player", false)
	end)
	playerGroup = ok
	task.spawn(function() -- Rider is registered by Movement.start (service order) - wait for it
		for _ = 1, 120 do
			local okR, reg = pcall(function()
				return PhysicsService:IsCollisionGroupRegistered("Rider")
			end)
			if okR and reg then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable("Player", "Rider", false)
				end)
				return
			end
			task.wait(0.5)
		end
	end)
end

local function groupOf(ch: Model): string
	local root = ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and root.CollisionGroup == "Rider" then
		return "Rider"
	end
	return "Player"
end

local function applyGroup(ch: Model)
	if not playerGroup then
		return
	end
	for _, p in ch:GetDescendants() do
		if p:IsA("BasePart") then
			p.CollisionGroup = "Player"
		end
	end
	ch.DescendantAdded:Connect(function(p)
		if p:IsA("BasePart") then
			p.CollisionGroup = groupOf(ch) -- new parts when mounted (accessories) - also Rider
		end
	end)
end

-- the character group on foot (Movement.dismount): Player if the group exists, otherwise Default
function AntiCheat.walkGroup(): string
	return if playerGroup then "Player" else "Default"
end

-- ---------------------------------------------------------------------------------------------- foreign scripts
local function foreignScript(inst: Instance): boolean
	if not inst:IsA("LuaSourceContainer") or not inst:IsDescendantOf(Workspace) then
		return false
	end
	local m = inst:FindFirstAncestorWhichIsA("Model")
	while m do
		if m:FindFirstChildOfClass("Humanoid") then
			return false -- Animate / Health of characters and mannequins are placed by the engine
		end
		m = m:FindFirstAncestorWhichIsA("Model")
	end
	return true
end
local function scrub(inst: Instance)
	if foreignScript(inst) then
		stats.scripts += 1
		warn("[AntiCheat] foreign script removed: " .. inst:GetFullName())
		local p = Players:GetPlayers()[1]
		if services.Analytics and p then
			pcall(services.Analytics.custom, p, "foreign_script", 1, { name = string.sub(inst.Name, 1, 24) })
		end
		inst:Destroy()
	end
end

-- ---------------------------------------------------------------------------------------------- Studio debugging
local function debugHook()
	if not RunService:IsStudio() then
		return
	end
	local bf = Instance.new("BindableFunction")
	bf.Name = "AntiCheatDebug"
	-- "stats" | "enforce on|off" | "reset" | "admin prod|studio" (Admin as in the live game: Studio does not get into Admin) |
	-- "tp X Y Z" (a server relocation, like "Back to shore": PivotTo + moved) | "pos" (the root as the server sees it and the honest point) |
	-- "groups" (collision groups) | "why" (violations by reason)
	bf.OnInvoke = function(cmd: string): string
		local verb, arg = string.match(cmd or "", "^(%a+)%s*(.*)$")
		local p0 = Players:GetPlayers()[1]
		if verb == "tp" and p0 then
			local x, y, z = string.match(arg or "", "^(%-?[%d%.]+)%s+(%-?[%d%.]+)%s+(%-?[%d%.]+)$")
			local _, _, ch = body(p0)
			if not x or not ch then
				return "tp bad"
			end
			ch:PivotTo(CFrame.new(tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0))
			AntiCheat.moved(p0)
			return "tp ok"
		elseif verb == "pos" and p0 then
			local root = body(p0)
			local t = track[p0]
			return if root then string.format("raw=%.1f,%.1f,%.1f honest=%s", root.Position.X, root.Position.Y, root.Position.Z,
				if t then string.format("%.1f,%.1f,%.1f", t.pos.X, t.pos.Y, t.pos.Z) else "-") else "nobody"
		elseif verb == "groups" then
			local function c(a: string, b: string): string
				local ok, v = pcall(function()
					return PhysicsService:CollisionGroupsAreCollidable(a, b)
				end)
				return if ok then tostring(v) else "?"
			end
			local root = p0 and body(p0)
			return string.format("PP=%s PR=%s PD=%s PDef=%s RDef=%s root=%s", c("Player", "Player"), c("Player", "Rider"), c("Player", "Dragon"),
				c("Player", "Default"), c("Rider", "Default"), if root then root.CollisionGroup else "-")
		elseif verb == "why" then
			local parts = {}
			for k, v in stats.why do
				table.insert(parts, k .. "=" .. v)
			end
			table.sort(parts)
			return table.concat(parts, " ") .. " scripts=" .. stats.scripts
		elseif verb == "enforce" then
			AC.studioEnforce = arg == "on"
		elseif verb == "reset" then
			stats.violations, stats.corrected, stats.observed, stats.last, stats.companion = 0, 0, 0, "", 0
			table.clear(stats.why)
			table.clear(violations)
		elseif verb == "admin" then
			Config.Admin.studioOpen = arg ~= "prod"
		end
		local p = Players:GetPlayers()[1]
		local t = p and track[p]
		return string.format("enforce=%s violations=%d corrected=%d observed=%d player=%d admin=%s companion=%d pos=%s last=%s", tostring(enforce()),
			stats.violations, stats.corrected, stats.observed, if p then (violations[p] or 0) else -1, tostring(Config.Admin.studioOpen ~= false),
			stats.companion, if t then string.format("%.1f,%.1f,%.1f", t.pos.X, t.pos.Y, t.pos.Z) else "-", stats.last)
	end
	bf.Parent = ServerStorage
end

function AntiCheat.init(s: { [string]: any })
	services = s
	debugHook()
	setupGroups()
end

function AntiCheat.start()
	local function hook(p: Player)
		p.CharacterAdded:Connect(applyGroup)
		if p.Character then
			applyGroup(p.Character)
		end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
	Players.PlayerRemoving:Connect(function(p)
		if services.Analytics and (violations[p] or 0) > 0 then
			pcall(services.Analytics.custom, p, "anticheat_session", violations[p] or 0)
		end
		track[p] = nil
		violations[p] = nil
		rates[p] = nil
		cache[p] = nil
	end)
	-- events the server does not listen to (State and Notice - only to the client; FlightInput without a handler): without a subscription Roblox
	-- queues what is sent and spews warnings - a dummy subscription discards at once
	local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
	if remotes then
		for _, name in AC.dropEvents do
			local r = remotes:FindFirstChild(name)
			if r and (r:IsA("RemoteEvent") or r:IsA("UnreliableRemoteEvent")) then
				(r :: any).OnServerEvent:Connect(function() end)
			end
		end
	end
	if AC.scriptGuard then
		for _, d in Workspace:GetDescendants() do
			scrub(d)
		end
		Workspace.DescendantAdded:Connect(function(d)
			if d:IsA("LuaSourceContainer") then
				task.defer(scrub, d) -- after the model is inserted whole (the character is assembled in the same frame)
			end
		end)
	end
	while true do
		task.wait(AC.tick)
		if AC.on then
			for _, p in Players:GetPlayers() do
				local ok, err = pcall(check, p)
				if not ok then
					warn("[AntiCheat] " .. tostring(err))
				end
			end
			local ok, err = pcall(checkCompanions, os.clock())
			if not ok then
				warn("[AntiCheat] companions: " .. tostring(err))
			end
		end
	end
end

return AntiCheat
