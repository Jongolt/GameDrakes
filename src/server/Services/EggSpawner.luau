--!strict
-- Eggs on the island (1.7; 10 §3, 02 §2): 30 spots, the outcome is rolled on appearance (Core/Eggs.roll, rare nest 10%), the egg model
-- of the element with a Pick up button, a pickup into the basket (one egg in hand; foundAt - a 90 s warmth bar), a new egg at the spot after
-- 6-10 min (Config.Balance.eggPoints.respawn). The egg in hand is visible behind the back.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Eggs = require(Core:WaitForChild("Eggs"))
local RaidLoop = require(Core:WaitForChild("RaidLoop")) -- the spots of the raid ring zones - Gloom nests, not free eggs

local EggSpawner = {}
EggSpawner.fastUntil = 0 -- 2.7: until this time (os.time) the respawn is from B.weather.starfall.respawn

local B = Config.Balance
local LP = Config.Loop
local EM = Config.World.eggMarks
local services: { [string]: any } = {}
local rng = Random.new()
local function r01(): number
	return rng:NextNumber()
end

-- a light shine of the island egg - sparks from the surface, visible from a medium distance, no text
local function sparkle(body: BasePart)
	local S = EM.sparkle
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Sparkle"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	pe.Rate = S.rate
	pe.Lifetime = NumberRange.new(S.lifetime[1], S.lifetime[2])
	pe.Speed = NumberRange.new(S.speed[1], S.speed[2])
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, S.size), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(Color3.fromRGB(S.color[1], S.color[2], S.color[3]))
	pe.LightEmission = S.lightEmission
	pe.Rotation = NumberRange.new(0, 360)
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Parent = body
end

local function bottomTo(model: Model, pos: Vector3)
	local cf, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + (pos - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
end

-- the egg in hand: a small model behind the back (until the client 1.8)
-- the egg in hand for any character (the demo raid bot too, Services/Crowd)
function EggSpawner.showCarryOn(ch: Model?, egg: any?)
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not ch or not root then
		return
	end
	local old = ch:FindFirstChild("CarriedEgg")
	if old then
		old:Destroy()
	end
	if not egg then
		return
	end
	local m = services.WorldBuilder.makeEgg(egg.element, 1.6)
	m.Name = "CarriedEgg"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
		end
	end
	local body = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if not body then
		m:Destroy()
		return
	end
	m:PivotTo(root.CFrame * CFrame.new(0, 1.4, 1.3))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			local w = Instance.new("WeldConstraint")
			w.Part0 = body
			w.Part1 = d
			w.Parent = d
		end
	end
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = body
	w.Parent = body
	m.Parent = ch
end

function EggSpawner.showCarry(player: Player, egg: any?)
	EggSpawner.showCarryOn(player.Character, egg)
end

local spawnAt: (id: string) -> ()
local pickers: { [string]: (Player) -> { ok: boolean, reason: string? } } = {} -- spot -> the pickup of its current egg

local function onPick(player: Player, id: string, egg: any, model: Model): { ok: boolean, reason: string? }
	local data = services.PlayerData.get(player)
	if not data or not model.Parent then
		return { ok = false, reason = "no_egg" }
	end
	if data.eggs.carry then
		services.Nest.toast(player, Strings.Loop.basketFull)
		return { ok = false, reason = "already" }
	end
	if services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
		return { ok = false, reason = "one_dragon" } -- day 1 = one dragon; such a player does not even see the egg (the client Hints)
	end
	pickers[id] = nil
	if services.AntiCheat then -- the pickup rate (a mark only)
		services.AntiCheat.note(player, "egg")
	end
	if egg.rareNest and services.Social then -- 2.6 (08 §3): who took the rare nest - a toast to everyone
		services.Social.rareTaken(player, os.time() - ((model:GetAttribute("SpawnedAt") :: number?) or os.time()))
	end
	model:Destroy()
	local carry = table.clone(egg)
	carry.foundAt = os.time()
	services.PlayerData.update(player, { "eggs", "onboarding" }, function(e, d)
		e.carry = carry
		d.onboarding.eggFound = true -- the "find an egg" step once (Hints)
		return nil
	end)
	EggSpawner.showCarry(player, carry)
	if services.Quest then -- "eggs found"
		services.Quest.event(player, "eggFound")
	end
	if services.Analytics then -- funnel 2
		services.Analytics.onboard(player, "egg_first_pick", { element = egg.element })
	end
	services.Net.notice(player, { kind = "egg", element = egg.element, rarity = egg.rarity, zone = egg.zone })
	local anchor = services.WorldBuilder.getEggPoint(id)
	if anchor and anchor:GetAttribute("Secret") and not (data.secrets and data.secrets[id]) then -- the first discovery of the grotto
		services.PlayerData.update(player, { "secrets" }, function(sx, d)
			if sx then
				sx[id] = os.time()
			else
				d.secrets = { [id] = os.time() }
			end
			return nil
		end)
		services.Nest.toast(player, Strings.World.secretFound)
		if services.Analytics then
			services.Analytics.onboard(player, "secret_found", { point = id })
		end
	end
	-- 2.7 (04 §4): during a starfall and 3 minutes after - a fast respawn (Weather sets EggSpawner.fastUntil)
	local R = if os.time() < EggSpawner.fastUntil then B.weather.starfall.respawn else B.eggPoints.respawn
	local gen = anchor and anchor:GetAttribute("Gen")
	task.delay(rng:NextNumber(R[1], R[2]), function()
		-- the starfall may have already placed a new egg (the generation changed) - do not pull it from under the nose
		local a = services.WorldBuilder.getEggPoint(id)
		if a and a:GetAttribute("Gen") == gen and not a:FindFirstChild("Egg") then
			spawnAt(id)
		end
	end)
	return { ok = true }
end

-- a spot in a raid ring zone (meadow, cliffs, baths) - a Gloom nest of Services/Raid is there; free eggs only in zones
-- without raids (the summit - until package 2) and in the secret grotto
local function raidPoint(anchor: BasePart): boolean
	local R = Config.Raid
	if not R or not R.on or anchor:GetAttribute("Secret") then
		return false
	end
	local ring = RaidLoop.ringOfZone(R, tostring(anchor:GetAttribute("Zone") or "Meadow"))
	local rc = ring and RaidLoop.ringCfg(R, ring)
	return rc ~= nil and rc.open ~= "off" -- a switched-off ring - the spots are free eggs again
end
EggSpawner.raidPoint = raidPoint

spawnAt = function(id: string)
	local anchor = services.WorldBuilder.getEggPoint(id)
	if not anchor then
		return
	end
	if raidPoint(anchor) then
		return
	end
	for _, c in anchor:GetChildren() do
		if c:IsA("Model") or c:IsA("BillboardGui") then
			c:Destroy() -- the WorldBuilder placeholder or an old egg
		end
	end
	anchor:SetAttribute("Gen", ((anchor:GetAttribute("Gen") :: number?) or 0) + 1)
	local zone = anchor:GetAttribute("Zone") or "Meadow"
	local egg = Eggs.roll(id, zone, rng:NextNumber() < B.rareNestP, r01, B, Config.Elements)
	-- above the grass and the label "<Zone> egg" (02 §2, 1:00-1:40)
	local model = services.WorldBuilder.makeEgg(egg.element, if egg.size == "huge" then 5.2 elseif egg.size == "big" then 4.4 else 3.8)
	model.Name = "Egg"
	bottomTo(model, anchor.Position + Vector3.new(0, if zone == "Cliffs" then 0.5 else 1.2, 0))
	model.Parent = anchor
	model:SetAttribute("Rarity", egg.rarity)
	model:SetAttribute("Element", egg.element)
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	-- the label only for zones from eggMarks.labelDistance (Meadow, up close); the client of the A/B group "no
	-- label" dims it by the EggLabel tag (WorldUI); the secret grotto has no label
	local labelDist = EM.labelDistance[zone]
	if body and labelDist and services.WorldBuilder.label and not anchor:GetAttribute("Secret") then
		local g = services.WorldBuilder.label(body, Loc.text(Strings.Hatch.eggAt, { zone = Loc.text(Strings.Zone[zone] or zone) }), nil, 3.2, 110, labelDist)
		CollectionService:AddTag(g, "EggLabel")
	end
	if body and not anchor:GetAttribute("Secret") then -- the secret grotto without hints: sparks through the waterfall would give the cache away
		sparkle(body)
	end
	model:SetAttribute("SpawnedAt", os.time())
	if egg.rareNest and services.Social and not anchor:GetAttribute("Secret") then -- 2.6 (08 §3): a race without PvP - a banner to everyone and a golden shimmer
		services.Social.rareSpawned(zone, model)
	end
	if body then
		local pr = Instance.new("ProximityPrompt")
		pr.ActionText = Strings.Loop.pick
		Loc.tag(pr, "ObjectText", Strings.Loop.eggObject, { rarity = Loc.text(Strings.Rarity[egg.rarity] or egg.rarity) })
		pr.HoldDuration = LP.holdSeconds
		pr.MaxActivationDistance = LP.promptDistance
		pr.RequiresLineOfSight = false
		pr.Parent = body
		pr.Triggered:Connect(function(player)
			-- the prompt is pressed from the other end of the map (fireproximityprompt) - the server checks by itself that the player is near
			if services.AntiCheat and not services.AntiCheat.near(player, body.Position, LP.promptDistance) then
				return
			end
			onPick(player, id, egg, model)
		end)
	end
	pickers[id] = function(player: Player)
		return onPick(player, id, egg, model)
	end
end

-- 2.7 (04 §4 Starfall): all empty spots are refilled at once (spots with a lying egg are not touched)
function EggSpawner.refillAll()
	for id, anchor in services.WorldBuilder.eggPoints do
		if not anchor:FindFirstChild("Egg") then
			local ok, err = pcall(spawnAt, id)
			if not ok then
				warn("[EggSpawner] refill " .. id .. ": " .. tostring(err))
			end
		end
	end
end

-- the newcomer's table in the nest: three eggs TableEgg1..3 (WorldBuilder), only the owner takes; the first egg hatches in 3 s -
-- a hatch <= 0:20 from joining. ONE egg is taken from the table
-- per account - after the pickup the other two vanish for this player and cannot be taken (onboarding.table not empty = the table is closed; old
-- profiles with one or two taken - too)
local TABLE_EL = { "ember", "frost", "moss" }

-- with Raid.firstEggByRaid there is no table
local function noTable(): boolean
	local R = Config.Raid
	return R ~= nil and R.on == true and R.firstEggByRaid == true
end

local function tableDone(data: any): boolean
	if noTable() then
		return true
	end
	local t = data and data.onboarding and data.onboarding.table
	return typeof(t) == "table" and next(t) ~= nil
end

local function tableEgg(nest: Model, k: number): Model?
	local t = nest:FindFirstChild("EggTable")
	return t and t:FindFirstChild("TableEgg" .. k) :: Model?
end

-- the two untaken eggs
-- fade over LP.tableFade, not in the same frame as the taken one - visible that one was taken. The Fading attribute: the client hint
-- (Hints.tableEggs) does not count a fading egg as free; setVisible cancels an unfinished fade
local fading: { [Model]: { Tween } } = {}

local function stopFade(m: Model)
	local list = fading[m]
	if list then
		fading[m] = nil
		for _, tw in list do
			tw:Cancel()
		end
	end
	m:SetAttribute("Fading", nil)
end

local function setVisible(m: Model, on: boolean)
	stopFade(m)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseT") == nil then
				d:SetAttribute("BaseT", d.Transparency)
			end
			d.Transparency = if on then d:GetAttribute("BaseT") :: number else 1
		end
	end
end

local function fadeOut(m: Model, seconds: number)
	stopFade(m)
	m:SetAttribute("Fading", true)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local list: { Tween } = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			if d:GetAttribute("BaseT") == nil then
				d:SetAttribute("BaseT", d.Transparency)
			end
			if d.Transparency < 1 then
				local tw = TweenService:Create(d, info, { Transparency = 1 })
				tw:Play()
				table.insert(list, tw)
			end
		end
	end
	fading[m] = list
	task.delay(seconds + 0.1, function()
		if fading[m] == list then -- not cancelled: push to 1 and remove the mark
			setVisible(m, false)
		end
	end)
end

function EggSpawner.tableEggs(player: Player)
	local nest, idx = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not idx or not data then
		return
	end
	local done = tableDone(data)
	for k = 1, 3 do
		local m = tableEgg(nest, k)
		if m and not (done and fading[m]) then -- do not interrupt a fading one (Nest.refresh / a purchase in the same 0.5 s)
			setVisible(m, not done)
		end
	end
end

function EggSpawner.resetTable(nest: Model)
	for k = 1, 3 do -- a free nest has no eggs
		local m = tableEgg(nest, k)
		if m then
			setVisible(m, false)
		end
	end
end

-- take egg k from the table of the own nest (02 §2: the egg jumps into the hands by itself when you come close)
function EggSpawner.pickTable(player: Player, k: number): { ok: boolean, reason: string? }
	local data = services.PlayerData.get(player)
	if not data or not services.Nest.of(player) then
		return { ok = false, reason = "loading" }
	end
	if k < 1 or k > 3 or tableDone(data) then -- after the first pickup the table is closed (also for LoopDebug "table 2")
		return { ok = false, reason = "no_egg" }
	end
	if data.eggs.carry then
		return { ok = false, reason = "already" }
	end
	local egg = Eggs.roll("table" .. k, "Meadow", false, r01, B, { TABLE_EL[k] })
	egg.foundAt = os.time()
	services.PlayerData.update(player, { "eggs", "onboarding" }, function(e, d)
		e.carry = egg
		d.onboarding.table = d.onboarding.table or {}
		d.onboarding.table[tostring(k)] = true
		return nil
	end)
	EggSpawner.showCarry(player, egg)
	local nest = services.Nest.of(player)
	for j = 1, 3 do -- the taken one - at once (it is already in hand), the other two fade
		local m = nest and tableEgg(nest, j)
		if m then
			if j == k then
				setVisible(m, false)
			else
				fadeOut(m, LP.tableFade or 0.5)
			end
		end
	end
	if services.Analytics then -- the newcomer's first egg - from the table; otherwise step 2 was set by a glade egg after step 3
		services.Analytics.onboard(player, "egg_first_pick", { element = egg.element })
	end
	services.Net.notice(player, { kind = "egg", element = egg.element, rarity = egg.rarity, first = data.onboarding.firstHatch ~= true })
	return { ok = true }
end

function EggSpawner.init(s: { [string]: any })
	services = s
end

function EggSpawner.start()
	while #services.WorldBuilder.nests < Config.World.nests.count do -- the nests are built by WorldBuilder.start (~6 s), the starts run in parallel
		task.wait(0.25)
	end
	for i = 1, Config.World.nests.count do
		local nest = services.WorldBuilder.getNest(i)
		if nest and not services.Nest.ownerOf(i) then
			EggSpawner.resetTable(nest)
		end
	end
	-- the newcomer's table: "just walk up" (02 §1); a 0.25 s tick
	task.spawn(function()
		while true do
			task.wait(0.25)
			for i = 1, Config.World.nests.count do
				local owner = services.Nest.ownerOf(i)
				local nest = services.WorldBuilder.getNest(i)
				local data = owner and services.PlayerData.get(owner)
				local pos = owner and services.Nest.rootPos(owner)
				if owner and nest and data and pos and not data.eggs.carry and not tableDone(data) then
					for k = 1, 3 do
						local m = tableEgg(nest, k)
						if m and (Vector3.new(m:GetPivot().Position.X, 0, m:GetPivot().Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude <= LP.pickRadius then
							EggSpawner.pickTable(owner, k)
							break
						end
					end
				end
			end
		end
	end)
	-- the island eggs: the Pick up button and the PickEgg call (client) with a distance check
	services.Net.handle("PickEgg", function(player: Player, pointId: string)
		local anchor = services.WorldBuilder.getEggPoint(pointId)
		local model = anchor and anchor:FindFirstChild("Egg")
		local pos = services.Nest.rootPos(player)
		if not anchor or not model or not pos or (anchor.Position - pos).Magnitude > LP.pickDistance then
			return { ok = false, reason = "too_far" }
		end
		local fn = pickers[pointId]
		return if fn then fn(player) else { ok = false, reason = "no_egg" }
	end)
	while next(services.WorldBuilder.eggPoints) == nil do
		task.wait(0.25)
	end
	task.wait(1) -- the spots are built in a batch
	for id in services.WorldBuilder.eggPoints do
		local ok, err = pcall(spawnAt, id)
		if not ok then
			warn("[EggSpawner] " .. id .. ": " .. tostring(err))
		end
	end
	-- the egg in hand after the character respawns
	local function hook(p: Player)
		p.CharacterAdded:Connect(function()
			task.wait(0.5)
			local data = services.PlayerData.get(p)
			if data and data.eggs and data.eggs.carry then
				EggSpawner.showCarry(p, data.eggs.carry)
			end
		end)
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in Players:GetPlayers() do
		hook(p)
	end
end

return EggSpawner
