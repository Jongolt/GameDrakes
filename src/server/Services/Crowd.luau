--!strict
-- WALKERS on the plaza, so a newcomer does not join an empty place: on a quiet server (live players <= Config.Admin.auto.maxPlayers) walkers.count R15 humanoids without an outfit,
-- with a name above the head (Config.Admin.names), walk between plaza points (the Keeper's stall, the board, the circle at Old Ash, the plate edge) with pauses;
-- the standard Roblox animations (idle / walk) are loaded on the server - without Animate (a LocalScript does not run on an NPC). They are NPCs: not in the player list,
-- no chat, they take no nests (nests belong to the rider bots of Services/Admin). It got crowded - they leave. In Studio - only if
-- Config.Admin.auto.studio. The folder workspace.Crowd (not the root: Movement.dupGuard touches only the root and the players' nests)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Crowd = {}

local A = Config.Admin
local AU = A and A.auto
local WK = A and A.walkers
local services: { [string]: any } = {}
local rng = Random.new()
local folder: Folder? = nil

type Walker = { model: Model, hum: Humanoid, idle: AnimationTrack?, walk: AnimationTrack?, alive: boolean, last: number?, busy: boolean? }
local walkers: { Walker } = {}
local points: { Vector3 } = {}
-- the demo raid (Config.Admin.demo): a copy nest, the Combat pack "demo:1", the gate of the nearest lot
local DM = A and A.demo
local DEMO_KEY = "demo:1"
local demo: { nest: Model?, at: Vector3?, egg: Model?, gate: { O: Vector3, S: Vector3, I: Vector3 }?, lastAt: number, pack: { at: Vector3, ref: Vector3, opts: any }? } = { nest = nil, at = nil, egg = nil, gate = nil, lastAt = 0, pack = nil }

local function groundY(x: number, z: number): number?
	local pr = RaycastParams.new()
	pr.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	if folder then
		table.insert(skip, folder)
	end
	local bf = workspace:FindFirstChild("Bots")
	if bf then
		table.insert(skip, bf)
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	pr.FilterDescendantsInstances = skip
	local h = workspace:Raycast(Vector3.new(x, Config.World.terrace.y + 30, z), Vector3.new(0, -60, 0), pr)
	return if h then h.Position.Y else nil
end

-- plaza points: the stall and the board (slightly toward the center), the circle at the Keeper, two rings of plates under the six corners
local function buildPoints()
	points = {}
	local W = Config.World
	-- a point qualifies if the floor is at plaza level (not on the counter / a rock) and
	-- no closer than 9 to the stall, the Keeper and the board
	local props: { Vector3 } = { Vector3.new(W.stall.x, 0, W.stall.z), Vector3.new(W.keeper.x, 0, W.keeper.z + 4) }
	local bp = Config.Social and Config.Social.board and Config.Social.board.pos
	if bp then
		table.insert(props, Vector3.new(bp[1], 0, bp[3]))
	end
	local function add(x: number, z: number)
		local y = groundY(x, z)
		if not y or y > W.terrace.y + 1.5 then
			return
		end
		for _, pr in props do
			if (Vector3.new(x, 0, z) - pr).Magnitude < 9 then
				return
			end
		end
		table.insert(points, Vector3.new(x, y, z))
	end
	add(W.stall.x, W.stall.z + 14)
	add(W.stall.x + 12, W.stall.z + 10)
	add(W.stall.x - 12, W.stall.z + 10)
	if bp then
		add(bp[1] + 10, bp[3] + 10)
	end
	add(W.keeper.x + 12, W.keeper.z + 14)
	add(W.keeper.x - 12, W.keeper.z + 14)
	for _, rr in (WK and WK.ring) or { 30, 42 } do
		for k = 0, 5 do
			local a = math.rad(k * 60 + 30)
			add(math.cos(a) * rr, math.sin(a) * rr)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- avatars
-- the looks by UserId (Players:GetHumanoidDescriptionFromUserId, cached) from the pool: Config.Admin.avatarSeed + recent live players of this place (session >= 2 min,
-- DataStore "CrowdAvatars", up to 40; in Studio without the DataStore). The name above the head stays NPC. Failed - the fallback looks (skin color)
local pool: { number } = {}
local descCache: { [number]: HumanoidDescription } = {}
local lastPick: number? = nil
local joinedAt: { [Player]: number } = {}

local function addToPool(id: number)
	if typeof(id) == "number" and id > 0 and not table.find(pool, id) then
		table.insert(pool, id)
	end
end

local function loadPool()
	for _, id in (A.avatarSeed or {}) :: { number } do
		addToPool(id)
	end
	if RunService:IsStudio() or A.avatarRecent ~= true then
		return -- do not take the avatars of live players
	end
	local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, "CrowdAvatars")
	if not ok then
		return
	end
	local ok2, list = pcall((ds :: any).GetAsync, ds, "recent")
	if ok2 and typeof(list) == "table" then
		for _, id in list :: { number } do
			addToPool(id)
		end
	end
end

local function remember(id: number)
	if A.avatarRecent ~= true then
		return -- do not take the avatars of live players
	end
	addToPool(id)
	if RunService:IsStudio() then
		return
	end
	task.spawn(function()
		local ok, ds = pcall(DataStoreService.GetDataStore, DataStoreService, "CrowdAvatars")
		if not ok then
			return
		end
		pcall((ds :: any).UpdateAsync, ds, "recent", function(old: any)
			local list: { number } = if typeof(old) == "table" then old else {}
			for i = #list, 1, -1 do
				if list[i] == id then
					table.remove(list, i)
				end
			end
			table.insert(list, id)
			while #list > 40 do
				table.remove(list, 1)
			end
			return list
		end)
	end)
end

-- which looks are on the bots right now (walkers and riders): the AvatarKey attribute of the models
local function keysInUse(): { [string]: boolean }
	local used: { [string]: boolean } = {}
	for _, fname in { "Crowd", "Bots" } do
		local f = workspace:FindFirstChild(fname)
		if f then
			for _, m in f:GetChildren() do
				local k = m:GetAttribute("AvatarKey")
				if typeof(k) == "string" then
					used[k] = true
				end
			end
		end
	end
	return used
end

-- a random outfit from free catalog items (Config.Admin.avatarParts), the combination does not repeat ones already worn - the walkers must differ
local function outfit(used: { [string]: boolean }): (HumanoidDescription?, string?)
	local P = A.avatarParts
	if not P or not P.shirts or #P.shirts == 0 then
		return nil, nil
	end
	for _ = 1, 12 do
		local shirt = P.shirts[rng:NextInteger(1, #P.shirts)]
		local pants = if P.pants and #P.pants > 0 then P.pants[rng:NextInteger(1, #P.pants)] else 0
		local hair = if P.hair and #P.hair > 0 then P.hair[rng:NextInteger(1, #P.hair)] else 0
		local hat = if P.hats and #P.hats > 0 and rng:NextNumber() < 0.75 then P.hats[rng:NextInteger(1, #P.hats)] else 0 -- there is no free hair in the catalog - caps/hoods more often
		local key = string.format("o:%d-%d-%d-%d", shirt, pants, hair, hat)
		if not used[key] then
			local d = Instance.new("HumanoidDescription")
			d.Shirt = shirt
			if pants > 0 then
				d.Pants = pants
			end
			if hair > 0 then
				d.HairAccessory = tostring(hair)
			end
			if hat > 0 then
				d.HatAccessory = tostring(hat)
			end
			local skins = P.skins or { { 234, 184, 146 } }
			local c = skins[rng:NextInteger(1, #skins)]
			local skin = Color3.fromRGB(c[1], c[2], c[3])
			d.HeadColor, d.TorsoColor, d.LeftArmColor, d.RightArmColor, d.LeftLegColor, d.RightLegColor = skin, skin, skin, skin, skin, skin
			local sc = rng:NextNumber(0.95, 1.05)
			d.HeightScale = sc
			d.WidthScale = sc
			return d, key
		end
	end
	return nil, nil
end

-- the looks for a new bot: first a real avatar from the pool that nobody wears right now; then an outfit from the catalog;
-- the avatar of the game owner and of the players currently on the server is never worn by a bot
local function forbidden(id: number): boolean
	if table.find(Config.AdminUserIds, id) ~= nil then
		return true
	end
	for _, p in Players:GetPlayers() do
		if p.UserId == id then
			return true
		end
	end
	return false
end

function Crowd.describe(): (HumanoidDescription?, string?)
	local used = keysInUse()
	local free: { number } = {}
	for _, id in pool do
		if not used["u:" .. tostring(id)] and not forbidden(id) then
			table.insert(free, id)
		end
	end
	for _ = 1, math.min(4, #free) do
		local id = free[rng:NextInteger(1, #free)]
		local d = descCache[id]
		if not d then
			local ok, res = pcall(Players.GetHumanoidDescriptionFromUserId, Players, id)
			if ok and typeof(res) == "Instance" and res:IsA("HumanoidDescription") then
				d = res
				descCache[id] = d
			else
				warn("[Crowd] avatar " .. tostring(id) .. ": " .. tostring(res))
			end
		end
		if d then
			lastPick = id
			return d:Clone(), "u:" .. tostring(id)
		end
	end
	return outfit(used)
end

local function loadAnim(hum: Humanoid, id: number): AnimationTrack?
	local animator = hum:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = hum
	local anim = Instance.new("Animation")
	anim.AnimationId = "rbxassetid://" .. tostring(id)
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	return if ok then track else nil
end

local function makeWalker(i: number): Walker?
	local desc, akey = Crowd.describe()
	if not desc then -- the fallback looks: without an avatar (no network / the pool is empty)
		desc = Instance.new("HumanoidDescription")
		local palette = { Color3.fromRGB(234, 184, 146), Color3.fromRGB(196, 140, 100), Color3.fromRGB(120, 80, 60), Color3.fromRGB(245, 205, 170) }
		local skin = palette[rng:NextInteger(1, #palette)]
		desc.HeadColor, desc.TorsoColor, desc.LeftArmColor, desc.RightArmColor, desc.LeftLegColor, desc.RightLegColor = skin, skin, skin, skin, skin, skin
	end
	local ok, m = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(m) ~= "Instance" or not m:IsA("Model") then
		warn("[Crowd] walker: " .. tostring(m))
		return nil
	end
	local model = m :: Model
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		model:Destroy()
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy() -- Animate (a LocalScript) does not run on an NPC - we load the animations ourselves
		elseif d:IsA("BasePart") then
			d.CanQuery = false
		end
	end
	local names = A.names
	local name = if typeof(names) == "table" and #names > 0 then names[((i + 2) % #names) + 1] else "Apprentice"
	model.Name = "Walker_" .. tostring(i)
	if akey then
		model:SetAttribute("AvatarKey", akey)
	end
	hum.DisplayName = name
	hum.NameDisplayDistance = 70
	hum.HealthDisplayDistance = 0
	hum.WalkSpeed = (WK and WK.speed) or 11
	hum.BreakJointsOnDeath = false
	local p0 = points[rng:NextInteger(1, #points)]
	model:PivotTo(CFrame.new(p0 + Vector3.new(0, 3.2, 0)))
	model.Parent = folder
	local w: Walker = { model = model, hum = hum, idle = nil, walk = nil, alive = true, last = nil }
	if WK and WK.anims then
		w.idle = loadAnim(hum, WK.anims.idle)
		w.walk = loadAnim(hum, WK.anims.walk)
	end
	task.spawn(function()
		while w.alive and model.Parent do
			if w.busy then -- this walker runs the demo raid
				task.wait(0.5)
				continue
			end
			-- a pause in place
			if w.walk then
				w.walk:Stop(0.2)
			end
			if w.idle and not w.idle.IsPlaying then
				w.idle:Play(0.2)
			end
			local pz = (WK and WK.pause) or { 2, 6 }
			task.wait(rng:NextNumber(pz[1], pz[2]))
			if not (w.alive and model.Parent) then
				break
			end
			if w.busy then
				continue -- the demo raid started during the pause - do not start the walk
			end
			-- to a random point (not the same one)
			local k = rng:NextInteger(1, #points)
			if k == w.last and #points > 1 then
				k = (k % #points) + 1
			end
			w.last = k
			local target = points[k]
			if w.idle then
				w.idle:Stop(0.2)
			end
			if w.walk and not w.walk.IsPlaying then
				w.walk:Play(0.2)
			end
			hum:MoveTo(target)
			local reached = false
			local conn = hum.MoveToFinished:Connect(function(ok2: boolean)
				reached = ok2
			end)
			local t0 = os.clock()
			local timeout = (WK and WK.moveTimeout) or 12
			while w.alive and model.Parent and os.clock() - t0 < timeout do
				if w.busy then
					break -- the raid scene took the walker mid-walk - do not wait for the old point
				end
				local root = model.PrimaryPart
				if reached or (root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude < 3) then
					break
				end
				task.wait(0.25)
			end
			conn:Disconnect()
			if w.alive and model.Parent and not w.busy and os.clock() - t0 >= timeout then -- do not teleport in the middle of the scene
				model:PivotTo(CFrame.new(target + Vector3.new(0, 3.2, 0))) -- stuck - a teleport (the plaza is open, rare)
			end
		end
	end)
	return w
end

local function clearWalker(w: Walker)
	w.alive = false
	if w.model then
		w.model:Destroy()
	end
end

-- ---------------------------------------------------------------------------------------------- the demo raid
local function flat(a: Vector3, b: Vector3): number
	return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
end

-- the lot gate (like GlowEgg.gateFor): S - the gate center on the front face, O - outside, I - inside
local function gateOfNest(nest: Model): { O: Vector3, S: Vector3, I: Vector3 }?
	local base = nest:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return nil
	end
	local cf, sz = base.CFrame, base.Size
	local hd, top = sz.Z / 2, sz.Y / 2
	local zf = -hd
	local f1, f2 = cf:PointToWorldSpace(Vector3.new(0, top, -hd)), cf:PointToWorldSpace(Vector3.new(0, top, hd))
	if Vector3.new(f2.X, 0, f2.Z).Magnitude < Vector3.new(f1.X, 0, f1.Z).Magnitude then
		zf = hd
	end
	local inward = if zf < 0 then 1 else -1
	local S = cf:PointToWorldSpace(Vector3.new(0, top, zf))
	return { S = S, O = cf:PointToWorldSpace(Vector3.new(0, top, zf - inward * 6)), I = cf:PointToWorldSpace(Vector3.new(0, top, zf + inward * 7)) }
end

-- the copy nest: a free odd wedge closest to the spawn point, r as for ring-0 nests, the floor measured, no closer than 25 to the Raid nests
local function buildDemoNest(): boolean
	local R = Config.Raid
	local rc = R and R.rings and R.rings[1]
	local rr = (rc and rc.spots and rc.spots.r) or 47
	local spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	local sp = if spawn then (spawn :: BasePart).Position else Vector3.zero
	local raidNests: { Vector3 } = if services.Raid and services.Raid.nestPositions then services.Raid.nestPositions() else {}
	local best: Vector3? = nil
	local bestD = math.huge
	for k = 0, 5 do
		local a = math.rad(30 + k * 60)
		for _, off in { 0, 6, -6 } do
			local a2 = a + math.rad(off)
			local x, z = math.cos(a2) * rr, math.sin(a2) * rr
			local ok = true
			for _, rp in raidNests do
				if flat(Vector3.new(x, 0, z), rp) < 25 then
					ok = false
					break
				end
			end
			if ok and services.GlowEgg and services.GlowEgg.probe then
				local at, dh = services.GlowEgg.probe(x, z, true)
				if at and dh <= 1.5 then
					local d = flat(at, sp)
					if d >= 16 and d < bestD then
						best, bestD = at, d
					end
				end
			end
		end
	end
	if not best then
		warn("[Crowd] no room for the demo raid nest")
		return false
	end
	local at = best :: Vector3
	local m = Instance.new("Model")
	m.Name = "DemoNest"
	local base = services.GlowEgg.nestModel(m, at, 3.0, true)
	m.PrimaryPart = base
	m:SetAttribute("At", at)
	m.Parent = folder
	demo.nest, demo.at = m, at
	-- the gate: the nearest lot whose owner is not a live player (a bot or free); none - the nearest
	local wb = services.WorldBuilder
	local pickNest: Model? = nil
	local pickD = math.huge
	local anyNest: Model? = nil
	local anyD = math.huge
	for i = 1, Config.World.nests.count do
		local n = wb.getNest(i)
		if n then
			local g = gateOfNest(n)
			if g then
				local d = flat(g.S, at)
				if d < anyD then
					anyNest, anyD = n, d
				end
				if services.Nest.ownerOf(i) == nil and d < pickD then
					pickNest, pickD = n, d
				end
			end
		end
	end
	local target = pickNest or anyNest
	demo.gate = if target then gateOfNest(target) else nil
	if not demo.gate then
		return false
	end
	-- a pack like at ring 0 (the spots inward, toward the plaza center: the reference is a point outside)
	local outward = Vector3.new(at.X, 0, at.Z)
	outward = if outward.Magnitude > 0.1 then outward.Unit else Vector3.xAxis
	local rc0 = rc and rc.guard
	local opts = if rc0 then { kind = rc0.kind, scale = rc0.scale, name = rc0.name, count = 1, wake = rc0.wake } else nil
	demo.pack = { at = at, ref = at + outward * 20, opts = opts } -- place again if the pack was removed
	if services.Combat and services.Combat.placePackAt then
		local ok, err = pcall(services.Combat.placePackAt, DEMO_KEY, at, at + outward * 20, opts)
		if not ok then
			warn("[Crowd] demo pack: " .. tostring(err))
		end
	end
	return true
end

local function demoEgg(show: boolean)
	if demo.egg then
		demo.egg:Destroy()
		demo.egg = nil
	end
	if not show or not demo.nest or not demo.at then
		return
	end
	local ok, em = pcall(function()
		return services.WorldBuilder.makeEgg("ember", 3)
	end)
	if not ok or typeof(em) ~= "Instance" then
		return
	end
	local egg = em :: Model
	egg.Name = "Egg"
	local cf, size = egg:GetBoundingBox()
	local at = demo.at :: Vector3
	egg:PivotTo(egg:GetPivot() + (at + Vector3.new(0, 0.8, 0) - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
	for _, d in egg:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
		end
	end
	egg.Parent = demo.nest
	demo.egg = egg
end

local function moveTo(w: Walker, target: Vector3, speed: number, timeout: number): boolean
	w.hum.WalkSpeed = speed
	if w.idle then
		w.idle:Stop(0.2)
	end
	if w.walk and not w.walk.IsPlaying then
		w.walk:Play(0.2)
	end
	w.hum:MoveTo(target)
	local t0 = os.clock()
	while w.alive and w.model.Parent and os.clock() - t0 < timeout do
		local root = w.model.PrimaryPart
		if root and flat(root.Position, target) < 2.5 then
			return true
		end
		task.wait(0.1)
	end
	return false
end

-- one scene: approach, sneak, grab, "!", a run to the gate, the guardian at the line, home to sleep
local function demoScene(w: Walker)
	local at, g = demo.at, demo.gate
	if not at or not g or not services.Combat or not services.Combat.demoBegin then
		return
	end
	if services.Combat.packStateAt(DEMO_KEY) ~= "sleep" then
		return
	end
	w.busy = true
	local done = false
	local ok, err = pcall(function()
		local u = Vector3.new(g.O.X - at.X, 0, g.O.Z - at.Z)
		u = if u.Magnitude > 0.1 then u.Unit else Vector3.xAxis
		-- 1. approach the edge of the guardian zone
		if not moveTo(w, at + u * (DM.near or 14), (WK and WK.speed) or 11, 14) then
			return
		end
		-- 2. the egg shows, the bot sneaks
		demoEgg(true)
		task.wait((DM.eggBefore or 3) * 0.3)
		if not moveTo(w, at + u * (DM.pick or 3), DM.sneak or 7, 8) then
			demoEgg(false)
			return
		end
		task.wait(0.4)
		-- 3. grabbed: the egg from the nest into the hands, "!", the guardian stands up
		demoEgg(false)
		services.EggSpawner.showCarryOn(w.model, { element = "ember", rarity = "Common" })
		if not services.Combat.demoBegin(DEMO_KEY) then
			return
		end
		local root = w.model.PrimaryPart
		local t0 = os.clock()
		while os.clock() - t0 < (DM.wake or 0.9) do
			task.wait(0.05)
			if root then
				services.Combat.demoStep(DEMO_KEY, services.Combat.packStateAt(DEMO_KEY) and (root.Position) or at, 0, 0.05, root.Position)
			end
		end
		-- 4. the run to the gate: the bot 16, the guardian share x 16 along its trail; the bot enters the lot
		w.hum.WalkSpeed = DM.run or 16
		w.hum:MoveTo(g.O)
		local speed = (DM.share or 0.9) * (DM.run or 16)
		local last = os.clock()
		local stage = 1
		local deadline = os.clock() + 12
		while os.clock() < deadline do
			task.wait(0.05)
			local now = os.clock()
			local dt = now - last
			last = now
			root = w.model.PrimaryPart
			if not root then
				break
			end
			services.Combat.demoStep(DEMO_KEY, root.Position, speed, dt, nil)
			if stage == 1 and flat(root.Position, g.O) < 2.5 then
				stage = 2
				w.hum:MoveTo(g.I)
			elseif stage == 2 and flat(root.Position, g.I) < 2.5 then
				break
			end
		end
		-- 5. the guardian at the line: to O (outside the gate), facing the bot, stand a while, go to sleep
		t0 = os.clock()
		while os.clock() - t0 < 3 do
			task.wait(0.05)
			root = w.model.PrimaryPart
			local d = services.Combat.demoStep(DEMO_KEY, g.O, speed, 0.05, if root then root.Position else nil)
			if d ~= nil and d < 1 then
				break
			end
		end
		task.wait(DM.hold or 0.8)
		services.Combat.demoEnd(DEMO_KEY)
		-- the egg "into the bowl": disappears from the hands, the bot returns to its walk
		task.wait(0.6)
		services.EggSpawner.showCarryOn(w.model, nil)
		w.hum.WalkSpeed = (WK and WK.speed) or 11
		task.wait(1.5)
		done = true
	end)
	if not ok then
		warn("[Crowd] demo: " .. tostring(err))
		pcall(services.EggSpawner.showCarryOn, w.model, nil)
		pcall(services.Combat.demoEnd, DEMO_KEY)
		demoEgg(false)
	end
	w.hum.WalkSpeed = (WK and WK.speed) or 11
	w.busy = nil
	-- the every pause - from the end of the scene; a broken scene (did not make it) - a retry in 5 s, not after every
	demo.lastAt = if done then os.clock() else os.clock() - (DM.every or 50) + 5
end

local function demoTick()
	if not (DM and DM.on) or #walkers == 0 or not demo.at then
		return
	end
	if os.clock() - demo.lastAt < (DM.every or 50) then
		return
	end
	-- the demo nest pack was removed (the enemy limit, the model vanished) - place it again, otherwise the demo does not run
	-- until the server restarts (demoScene exits at packStateAt ~= "sleep")
	local pk = demo.pack
	if pk and services.Combat and services.Combat.packStateAt and services.Combat.packStateAt(DEMO_KEY) == nil then
		pcall(services.Combat.placePackAt, DEMO_KEY, pk.at, pk.ref, pk.opts)
		return -- the guardian is placed by the combat tick; the scene - next time
	end
	-- someone alive near the nest or the spawn point - otherwise nobody sees the scene
	local seen = false
	for _, p in Players:GetPlayers() do
		local ch = p.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") and flat(r.Position, demo.at :: Vector3) <= (DM.seeR or 120) then
			seen = true
			break
		end
	end
	if not seen then
		return
	end
	local w = walkers[1]
	if not w or w.busy or not w.alive then
		return
	end
	demo.lastAt = os.clock()
	task.spawn(demoScene, w)
end

function Crowd.count(): number
	return #walkers
end

function Crowd.set(n: number)
	n = math.max(0, math.floor(n))
	while #walkers > n do
		clearWalker(table.remove(walkers) :: Walker)
	end
	while #walkers < n do
		local w = makeWalker(#walkers + 1)
		if not w then
			break
		end
		table.insert(walkers, w)
	end
	workspace:SetAttribute("Walkers", #walkers)
end

function Crowd.init(s: { [string]: any })
	services = s
end

function Crowd.start()
	if not (WK and WK.on and AU and AU.on) then
		return
	end
	if RunService:IsStudio() and not AU.studio then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Crowd"
	f.Parent = workspace
	folder = f
	loadPool()
	Players.PlayerAdded:Connect(function(p)
		joinedAt[p] = os.time()
	end)
	for _, p in Players:GetPlayers() do
		joinedAt[p] = joinedAt[p] or os.time()
	end
	Players.PlayerRemoving:Connect(function(p)
		local t0 = joinedAt[p]
		joinedAt[p] = nil
		if t0 and os.time() - t0 >= 120 and p.UserId > 0 then
			remember(p.UserId) -- a recent live player - into the avatar pool
		end
	end)
	task.spawn(function()
		while #services.WorldBuilder.nests < Config.World.nests.count do
			task.wait(0.25)
		end
		task.wait(3) -- the plaza and the plates are built in a batch
		buildPoints()
		if #points < 4 then
			warn("[Crowd] few plaza points: " .. tostring(#points))
			return
		end
		if DM and DM.on then
			local okN, errN = pcall(buildDemoNest)
			if not okN then
				warn("[Crowd] demo nest: " .. tostring(errN))
			end
		end
		task.spawn(function()
			while true do
				task.wait(2)
				local ok, err = pcall(demoTick)
				if not ok then
					warn("[Crowd] demoTick: " .. tostring(err))
				end
			end
		end)
		while true do
			local real = #Players:GetPlayers()
			local want = if real >= 1 and real <= (AU.maxPlayers or 2) then (WK.count or 2) else 0
			if #walkers ~= want then
				local ok, err = pcall(Crowd.set, want)
				if not ok then
					warn("[Crowd] set: " .. tostring(err))
				end
			end
			task.wait(AU.checkEvery or 12)
		end
	end)
end

return Crowd
