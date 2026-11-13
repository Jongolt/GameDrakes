--!strict
-- Admin debugging: the Admin(cmd) call only from the game owner (CreatorType User), admins or in Studio; in production
-- everything is switched off by Config.Admin.enabled. Commands: reset - the profile from the template and the nest anew (Nest.reapply); time N | time +N -
-- fast-forward the timers by N s; give N - coins; give egg [zone] - an egg into the hands (Meadow, Cliffs, Springs, Summit); bots N (0..5) - N
-- free nests are taken by bots: 3-5 dragons per nest, the sign "Bot k's Nest", a mannequin rider on an adult circling above the island
-- (a load test: 6 nests x 3-5 dragons + riders; 0 - remove); perf - the last measurement line.
-- A live player outranks a bot: no free nests - Nest.assign takes a bot's nest (yieldBot).
-- The admin client FPS measurement (Remote Perf from Controllers/Perf every Config.Admin.perf.every s): the lines accumulate and once a minute
-- go to the DataStore PerfLog_v1 (key perf_YYYYMMDD, no more than perf.cap lines; also on server close). Read: python3 cloud_test.py
-- perflog_read. At the end of a line - the day phase and memory by kind from the client (Controllers/Perf detail).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Validate = require(Shared:WaitForChild("Validate"))
local Core = Shared:WaitForChild("Core")
local Economy = require(Core:WaitForChild("Economy"))
local Eggs = require(Core:WaitForChild("Eggs"))

local Admin = {}

local A = Config.Admin
local AB = A.bots
local B = Config.Balance
local services: { [string]: any } = {}
local rng = Random.new()

type Bot = {
	k: number, idx: number, nest: Model, ownerId: number, name: string, alive: boolean,
	flier: Model?, body: BasePart?, rider: Model?, r: number, h: number, w: number, phase: number,
}
local bots: { Bot } = {}
local botFolder: Folder? = nil
local manual = false -- an admin set the bot count by command - the auto mode stays silent on this server

local function allowed(player: Player): boolean
	if RunService:IsStudio() and A.studioOpen ~= false then -- the cheat_check probe sets studioOpen = false (as in the live game)
		return true
	end
	if not A.enabled then
		return false
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId == player.UserId
	end
	return table.find(Config.AdminUserIds, player.UserId) ~= nil -- the game belongs to a group - admins come from the Config list
end
Admin.allowed = allowed

-- ---------------------------------------------------------------------------------------------- bots (FPS measurement)
local function pickStage(): number
	local total = 0
	for _, w in AB.stageWeights do
		total += w
	end
	local x = rng:NextNumber() * total
	for i, w in AB.stageWeights do
		x -= w
		if x <= 0 then
			return i - 1
		end
	end
	return 2
end

local function anyElement(): string
	return Config.Elements[rng:NextInteger(1, #Config.Elements)]
end

-- the point of the bot's circle at time t: radius r, height h with bobbing, looking along the tangent
local function pathCFrame(b: Bot, t: number): CFrame
	local a = b.phase + b.w * t
	local y = b.h + AB.bob * math.sin(t * 2 * math.pi / AB.bobSeconds + b.phase)
	local pos = Vector3.new(math.cos(a) * b.r, y, math.sin(a) * b.r)
	local dir = Vector3.new(-math.sin(a), 0, math.cos(a)) * (if b.w >= 0 then 1 else -1)
	return CFrame.lookAt(pos, pos + dir)
end

local function clearBot(b: Bot)
	b.alive = false
	local nest = b.nest
	for s = 1, 10 do
		services.DragonVisuals.clearSlot(nest, s)
	end
	nest:SetAttribute("Bot", nil)
	nest:SetAttribute("OwnerId", nil)
	nest:SetAttribute("OwnerName", nil)
	nest:SetAttribute("Rate", nil)
	services.Nest.setSign(nest, Loc.text(Strings.World.freeNest, { n = b.idx }))
	local pile = nest:FindFirstChild("CoinPile")
	if pile then
		pile:SetAttribute("Pot", nil)
	end
	if b.rider then
		b.rider:Destroy()
	end
	if b.flier then
		b.flier:Destroy()
	end
end

local function syncCount()
	workspace:SetAttribute("Bots", #bots)
end

-- give a bot's nest to a live player (Nest.assign, no free ones): remove the last bot at once, without waiting
function Admin.yieldBot(): number?
	local b = table.remove(bots)
	if not b then
		return nil
	end
	clearBot(b)
	syncCount()
	return b.idx
end

local function addRider(b: Bot, m: Model)
	local seat = m:FindFirstChild("Saddle", true)
	if not seat or not seat:IsA("Seat") then
		return
	end
	-- the rider is an avatar from the Services/Crowd pool
	-- that nobody wears right now (AvatarKey)
	local desc: HumanoidDescription? = nil
	local akey: string? = nil
	if services.Crowd and services.Crowd.describe then
		local okD, d, k = pcall(services.Crowd.describe)
		if okD then
			desc, akey = d, k
		end
	end
	local ok, dummy = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc or Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or typeof(dummy) ~= "Instance" or not dummy:IsA("Model") then
		warn("[Admin] bot rider: " .. tostring(dummy))
		return
	end
	if not b.alive or not m.Parent then
		dummy:Destroy()
		return
	end
	local rider = dummy :: Model
	rider.Name = b.name
	if akey then
		rider:SetAttribute("AvatarKey", akey)
	end
	for _, p in rider:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
		end
	end
	local hum = rider:FindFirstChildOfClass("Humanoid")
	rider:PivotTo(seat.CFrame + Vector3.new(0, 3, 0))
	rider.Parent = botFolder
	services.Movement.rigFlierRider(rider)
	if hum then
		seat:Sit(hum)
	end
	b.rider = rider
end

local function addFlier(b: Bot)
	local el = anyElement()
	local d = { uid = "bf" .. b.k, element = el, rarity = "Rare", stage = 2, name = Content.Elements[el].name }
	local m: Model = services.DragonVisuals.build(d, false)
	if not b.alive then
		m:Destroy()
		return
	end
	local body = m.PrimaryPart
	if not body then
		m:Destroy()
		return
	end
	m.Name = "BotFlier"
	m:SetAttribute("Uid", d.uid)
	m:SetAttribute("OwnerId", b.ownerId)
	m:SetAttribute("Bot", b.k)
	local at = pathCFrame(b, os.clock())
	m:PivotTo(at)
	m.Parent = botFolder
	services.Movement.rigFlier(m, body, at)
	local ap = body:FindFirstChild("FollowPos")
	if ap and ap:IsA("AlignPosition") then
		ap.MaxVelocity = AB.speed[2] * 2
	end
	b.flier = m
	b.body = body
	if AB.rider then
		addRider(b, m)
	end
end

local function addBot(k: number): boolean
	local wb = services.WorldBuilder
	local idx: number? = nil
	for i = Config.World.nests.count, 1, -1 do -- from the end: the first nests stay for live players
		local n = wb.getNest(i)
		if n and services.Nest.ownerOf(i) == nil and not n:GetAttribute("Bot") then
			idx = i
			break
		end
	end
	if not idx then
		return false
	end
	local nest = wb.getNest(idx) :: Model
	local names = A.names
	local name = if typeof(names) == "table" and #names > 0 then names[((k - 1) % #names) + 1] else services.Nest.fmt(Strings.Menu.botName, { n = k })
	local r = rng:NextNumber(AB.radius[1], AB.radius[2])
	local b: Bot = {
		k = k, idx = idx, nest = nest, ownerId = -k, name = name, alive = true, flier = nil, body = nil, rider = nil,
		r = r, h = rng:NextNumber(AB.height[1], AB.height[2]), w = rng:NextNumber(AB.speed[1], AB.speed[2]) / r * (if rng:NextNumber() < 0.5 then -1 else 1),
		phase = rng:NextNumber() * 2 * math.pi,
	}
	nest:SetAttribute("Bot", k)
	nest:SetAttribute("OwnerId", b.ownerId) -- not a real UserId: clients see a foreign nest
	nest:SetAttribute("OwnerName", name)
	services.Nest.setSign(nest, Loc.text(Strings.Loop.yourNest, { player = name }))
	table.insert(bots, b)
	syncCount()
	task.spawn(function()
		local now = os.time()
		local rate = 0
		for s = 1, rng:NextInteger(AB.dragons[1], AB.dragons[2]) do
			local el = anyElement()
			local d = { uid = "b" .. k .. "_" .. s, element = el, rarity = Config.Rarities[rng:NextInteger(1, 4)], stage = pickStage(), name = Content.Elements[el].name, fedUntil = now + 86400 }
			local ok, err = pcall(function()
				local m = services.DragonVisuals.build(d, true)
				if not b.alive then
					m:Destroy()
					return
				end
				m:SetAttribute("Uid", d.uid)
				m:SetAttribute("OwnerId", b.ownerId)
				services.DragonVisuals.placeInSlot(nest, s, m)
				services.Nest.syncModel(m, d, { ascension = 0 }, now)
				rate += Economy.dragonIncome(d :: any, B)
			end)
			if not ok then
				warn("[Admin] bot dragon: " .. tostring(err))
			end
		end
		if not b.alive then
			return
		end
		nest:SetAttribute("Rate", rate)
		local pile = nest:FindFirstChild("CoinPile")
		if pile then
			pile:SetAttribute("Pot", AB.pot)
		end
		local ok, err = pcall(addFlier, b)
		if not ok then
			warn("[Admin] bot flier: " .. tostring(err))
		end
	end)
	return true
end

function Admin.bots(n: number): number
	n = math.clamp(math.floor(n), 0, AB.max)
	while #bots > n do
		clearBot(table.remove(bots) :: Bot)
	end
	local k = 0
	while #bots < n do
		k += 1
		local used = false
		for _, b in bots do
			if b.k == k then
				used = true
			end
		end
		if not used and not addBot(k) then
			break -- no free nests
		end
	end
	syncCount()
	return #bots
end

local function flyTick()
	local t = os.clock()
	for _, b in bots do
		local body = b.body
		if b.alive and body and body.Parent then
			local cf = pathCFrame(b, t)
			local ap = body:FindFirstChild("FollowPos")
			local ao = body:FindFirstChild("FollowRot")
			if ap and ap:IsA("AlignPosition") then
				ap.Position = cf.Position
			end
			if ao and ao:IsA("AlignOrientation") then
				ao.CFrame = cf.Rotation
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------- FPS measurement
local perfBuf: { string } = {}
local perfLast: { [Player]: number } = {}
local lastLine = ""
local PERF_DEF = (Remotes.List :: any).Perf

local function onPerf(player: Player, ...: any)
	if not A.perf.on or not allowed(player) then
		return
	end
	local now = os.clock()
	if perfLast[player] and now - perfLast[player] < A.perf.every * 0.5 then
		return
	end
	local args = table.pack(...)
	args.n = nil
	if not Validate.args(args :: any, PERF_DEF.args) then
		return
	end
	perfLast[player] = now
	local fps, low, mem, dragons, screen, info = ...
	lastLine = string.format("%s v%d u%d fps%.0f low%.0f mem%.0f dr%d bots%d pl%d %s %s", os.date("!%H:%M:%S"), game.PlaceVersion, player.UserId, fps, low, mem, dragons, #bots, #Players:GetPlayers(), screen, if type(info) == "string" then info else "")
	if #perfBuf < 100 then
		table.insert(perfBuf, lastLine)
	end
	if RunService:IsStudio() then
		print("[Perf] " .. lastLine)
	end
end

local function perfFlush()
	if #perfBuf == 0 or RunService:IsStudio() then
		perfBuf = {}
		return
	end
	local batch = perfBuf
	perfBuf = {}
	pcall(function()
		local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
		ds:UpdateAsync("perf_" .. os.date("!%Y%m%d"), function(old: any)
			local list = if type(old) == "table" then old else {}
			for _, line in batch do
				table.insert(list, line)
			end
			while #list > A.perf.cap do
				table.remove(list, 1)
			end
			return list
		end)
	end)
end

-- ---------------------------------------------------------------------------------------------- commands
function Admin.run(player: Player, cmd: string): { ok: boolean, reason: string?, [string]: any }
	if not allowed(player) then
		return { ok = false, reason = "forbidden" }
	end
	local verb, rest = string.match(cmd, "^/?(%a+)%s*(.-)%s*$")
	rest = rest or ""
	local n = tonumber((string.gsub(rest :: string, "^%+", ""))) or 0
	if verb == "bots" then -- before the player's data: bots need no profile
		manual = true -- the manual count outranks the auto mode
		return { ok = true, bots = Admin.bots(n) }
	elseif verb == "perf" then
		return { ok = true, reason = lastLine }
	end
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if verb == "reset" then
		if not services.PlayerData.reset(player) then
			return { ok = false, reason = "loading" }
		end
		services.Nest.reapply(player)
		services.Nest.toast(player, Strings.Menu.resetDone)
		return { ok = true }
	elseif verb == "time" then
		for _, rec in data.eggs.incubating do
			rec.endsAt -= n
		end
		for _, d in data.dragons do
			if d.stageEndsAt then
				d.stageEndsAt -= n
			end
		end
		services.PlayerData.replicate(player, { "eggs", "dragons" })
		return { ok = true }
	elseif verb == "give" then
		local what, zoneArg, rarArg = string.match(rest :: string, "^(%a+)%s*(%a*)%s*(%a*)")
		if what == "egg" then
			if data.eggs.carry then
				return { ok = false, reason = "already" }
			end
			local zone = "Meadow"
			for z in Strings.Zone do
				if string.lower(z) == string.lower(zoneArg or "") then
					zone = z
				end
			end
			local egg = Eggs.roll("admin", zone, false, function()
				return rng:NextNumber()
			end, B, Config.Elements)
			local carry: any = table.clone(egg :: any)
			carry.foundAt = os.time()
			for _, r in Eggs.RARITIES do -- "give egg Meadow Legendary" - a given rarity for the hatch scene probe
				if rarArg and string.lower(r) == string.lower(rarArg) then
					carry.rarity = r
				end
			end
			services.PlayerData.update(player, "eggs", function(e)
				e.carry = carry
				return nil
			end)
			services.EggSpawner.showCarry(player, carry)
			services.Net.notice(player, { kind = "egg", element = carry.element, rarity = carry.rarity, zone = carry.zone })
			return { ok = true }
		end
		services.Nest.addCoins(player, n)
		return { ok = true }
	end
	return { ok = false, reason = "bad_request" }
end

function Admin.init(s: { [string]: any })
	services = s
end

function Admin.start()
	local f = Instance.new("Folder")
	f.Name = "Bots" -- not in the Workspace root: the duplicate safeguard (Movement.dupGuard) touches only the root and the players' nests
	f.Parent = workspace
	botFolder = f
	syncCount()
	services.Net.handle("Admin", function(player: Player, cmd: string)
		return Admin.run(player, cmd)
	end)
	local r = ReplicatedStorage:WaitForChild(Remotes.Folder):FindFirstChild("Perf")
	if r and r:IsA("RemoteEvent") then
		r.OnServerEvent:Connect(onPerf)
	end
	Players.PlayerRemoving:Connect(function(p)
		perfLast[p] = nil
	end)
	game:BindToClose(function() -- the last measurement lines (after "Test bots: off") were lost on server close
		perfFlush()
	end)
	-- auto bots on a quiet server - one per check (lots from the end), it got crowded - they leave one by one
	local AU = A.auto
	if AU and AU.on and (not RunService:IsStudio() or AU.studio) then
		task.spawn(function()
			while true do
				task.wait(AU.checkEvery or 12)
				if manual then
					continue
				end
				local real = #Players:GetPlayers()
				local want = if real >= 1 and real <= (AU.maxPlayers or 2) then math.min(AU.count or 3, AB.max) else 0
				if #bots < want then
					Admin.bots(#bots + 1)
				elseif #bots > want then
					Admin.bots(#bots - 1)
				end
			end
		end)
	end
	task.spawn(function()
		local acc = 0
		while true do
			task.wait(1 / AB.tickHz)
			if #bots > 0 then
				local ok, err = pcall(flyTick)
				if not ok then
					warn("[Admin] flyTick: " .. tostring(err))
				end
			end
			acc += 1 / AB.tickHz
			if acc >= A.perf.flush then
				acc = 0
				task.spawn(perfFlush)
			end
		end
	end)
end

return Admin
