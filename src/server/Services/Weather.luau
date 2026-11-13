--!strict
-- 2.7: the weather and the Storm dragon (spec 04 §7-8, 08 §7). The logic - Core/Weather, the numbers - Config.Balance.weather,
-- Config.Balance.stormDragon and Config.Weather (the look), the texts - Strings.Weather. The state for the client - the attributes of the folder
-- ReplicatedStorage.WeatherState: Kind (storm | starfall | aurora | ""), EndsAt, Dragon (bool), DragonEndsAt, DragonAt (the next start),
-- Shards, ShardsTotal. The client (Controllers/Weather) draws the rain, flashes, stars, the timer and the shard scale.
-- A storm: income x2 for everyone (Nest takes Weather.coinsMult), those who hatched - Stormborn (Incubation takes Weather.isStorm).
-- A starfall: all egg spots refill at once, 3 minutes of fast respawn (EggSpawner.refillAll / fastUntil).
-- The Storm dragon: at :00 and :30 by the server clock a dark elder silhouette x3 flies 3 circles above the island and drops 12 shards;
-- a shared count; at the end everyone on the server gets coins k/12 x 10 min of income, at 12/12 - a Cliffs egg too. No penalties and no PvP.
-- the event only for players with at least one dragon of stage >= stormDragon.minStage
-- (an adult): the banner 60 s ahead, the shard toasts, participation and the reward - for them; a newcomer (the event came at 6:33, before the first adult) is shown
-- nothing and his shard pickup does not count (the client hides the scale, the silhouette and the shards by the same rule Core/Weather.eligible).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local WeatherCore = require(Core:WaitForChild("Weather"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local Eggs = require(Core:WaitForChild("Eggs"))

local Weather = {}

local services: { [string]: any } = {}
local B = Config.Balance
local W = B.weather
local SD = WeatherCore.dragonChapter(B.stormDragon, 0) -- the chapter by the running updates - recomputed at the start of every appearance
local WV = Config.Weather
local T = Strings.Weather
local rng = Random.new()
local startedAt = os.time()
local folder: Folder? = nil
local kind = ""
local kindEnds = 0
local shards: { BasePart } = {}
local shardCount = 0
local dragonModel: Model? = nil
local participants: { [Player]: boolean } = {} -- were present at the dragon's start or picked up a shard
local stormUntil = 0 -- while the storm dragon runs (os.clock)


local function set(name: string, v: any)
	if folder then
		folder:SetAttribute(name, v)
	end
end

function Weather.isStorm(): boolean
	return kind == "storm" and os.time() < kindEnds
end

-- 2.9: the weather now ("" - clear): storm | starfall | aurora (element variants by weather - Incubation, Core/LiveOps)
function Weather.current(): string
	return if kind ~= "" and os.time() < kindEnds then kind else ""
end

local function startText(k: string): string
	return if k == "storm" then T.storm elseif k == "aurora" then T.aurora else T.starfall
end

-- Update Party (09 §1, P8): Sunday 18:30-19:00 UTC - x2 coins for everyone and a countdown to the update; only if an update starts
-- at 19:00 (Core/LiveOps.partyLeft); the clock - LiveOps.now() (shifted in Studio by LiveOpsDebug)
local LO = Config.LiveOps
local LiveOpsCore = require(Shared:WaitForChild("Core"):WaitForChild("LiveOps"))
local function clock(): number
	return if services.LiveOps then services.LiveOps.now() else os.time()
end
function Weather.partyLeft(t: number): number
	return LiveOpsCore.partyLeft(Content.Updates, t, LO)
end

-- the nest income multiplier (Economy mods.weatherMult): a storm x2, an Update Party x2
function Weather.coinsMult(): number
	local m = if Weather.isStorm() then W.storm.coinsMult else 1
	if Weather.partyLeft(clock()) > 0 then
		m *= LO.partyCoinsMult
	end
	return m
end

local function announce(text: string, sub: string?)
	services.Net.noticeAll({ kind = "announce", text = text, sub = sub })
end

-- the right to the Storm dragon (Core/Weather.eligible: there is a dragon of stage >= SD.minStage)
local function eligible(p: Player): boolean
	local data = services.PlayerData and services.PlayerData.get(p)
	return WeatherCore.eligible(data and data.dragons, SD)
end

local function noticeEligible(payload: { [string]: any })
	for _, p in Players:GetPlayers() do
		if eligible(p) then
			services.Net.notice(p, payload)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- weather
local function weatherOnce()
	do
		local wait = WeatherCore.nextIn(W, os.time() - startedAt, rng:NextNumber())
		set("NextAt", os.time() + math.floor(wait))
		task.wait(wait)
		-- during the Storm dragon no weather starts (one event at a time)
		while folder and folder:GetAttribute("Dragon") do
			task.wait(5)
		end
		kind = WeatherCore.pick(W, rng:NextNumber(), if services.LiveOps then services.LiveOps.live() else 0) -- 2.9: Aurora from update 1
		kindEnds = os.time() + W.duration
		set("Kind", kind)
		set("EndsAt", kindEnds)
		announce(startText(kind))
		if kind == "starfall" and services.EggSpawner then
			services.EggSpawner.fastUntil = os.time() + W.starfall.fastSeconds
			if services.EggSpawner.refillAll then
				pcall(services.EggSpawner.refillAll)
			end
		end
		for _, p in Players:GetPlayers() do
			if services.Analytics then
				services.Analytics.custom(p, "weather", 1, { kind = kind })
			end
			break
		end
		task.wait(W.duration)
		set("Kind", "")
		kind = ""
		services.Net.noticeAll({ kind = "toast", text = T.over })
	end
end

-- one error does not switch the weather off for the whole server: pcall on every iteration
local function runWeather()
	while true do
		local ok, err = pcall(weatherOnce)
		if not ok then
			kind = ""
			set("Kind", "")
			warn("[Weather] weather: " .. tostring(err))
			task.wait(30)
		end
	end
end

-- ---------------------------------------------------------------------------------------------- the Storm dragon
local function groundAt(x: number, z: number): Vector3?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	params.IgnoreWater = false
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -500, 0), params)
	if not hit or hit.Material == Enum.Material.Water then
		return nil
	end
	return hit.Position
end

local function silhouette(): Model?
	local ids = Content.Assets.dragons.storm
	local id = ids and ids[4] or 0
	local m: Model? = if services.ModelLibrary then services.ModelLibrary.get(id) else nil
	if not m then
		-- the fallback silhouette: the body and the wings from primitives
		local f = Instance.new("Model")
		local body = Instance.new("Part")
		body.Size = Vector3.new(6, 5, 18)
		body.Parent = f
		for _, x in { -1, 1 } do
			local wing = Instance.new("Part")
			wing.Size = Vector3.new(16, 0.6, 9)
			wing.CFrame = CFrame.new(x * 10, 1, 0)
			wing.Parent = f
		end
		f.PrimaryPart = body
		m = f
	end
	local model = m :: Model
	local _, size = model:GetBoundingBox()
	if size.Y > 0 then
		model:ScaleTo(model:GetScale() * WV.dragon.height * (SD.scale or 1) / size.Y) -- chapter 2 is larger
	end
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") or d:IsA("BillboardGui") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			if d:IsA("MeshPart") then -- the v4b texture lives in TextureID - the color does not repaint it
				pcall(function()
					(d :: any).TextureID = ""
				end)
			end
			d.Color = Color3.fromRGB(WV.dragon.color[1], WV.dragon.color[2], WV.dragon.color[3])
			d.Material = Enum.Material.SmoothPlastic
		end
	end
	model.Name = "StormDragon"
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	return model
end

local function dropShard(pos: Vector3)
	local p = Instance.new("Part")
	p.Name = "StormShard"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.one * WV.shard.size
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(WV.shard.color[1], WV.shard.color[2], WV.shard.color[3])
	p.CFrame = CFrame.new(pos + Vector3.new(0, WV.shard.size / 2 + 0.6, 0))
	p.Parent = workspace -- no PointLight: the 04 §9 budget (<= 12 lights), the neon glows anyway
	table.insert(shards, p)
end

local function pickShards()
	for i = #shards, 1, -1 do
		local s = shards[i]
		for _, pl in Players:GetPlayers() do
			local pos = services.Nest.rootPos(pl)
			if pos and (pos - s.Position).Magnitude <= WV.shard.pickRadius and eligible(pl) then -- without an adult the shard is not taken
				table.remove(shards, i)
				s:Destroy()
				shardCount += 1
				set("Shards", shardCount)
				participants[pl] = true
				local last = shardCount >= SD.shards
				noticeEligible({ kind = "toast", text = Loc.text(if last then T.lastShard else T.shardPicked, { name = pl.DisplayName, k = shardCount, n = SD.shards }) })
				if services.Reward then -- 06 §2 Hard: «Collect 6 Storm shards»
					if services.Quest then -- through Quest (quest 28 "A bigger storm"; Quest forwards to Reward)
						services.Quest.event(pl, "shard")
					else
						services.Reward.event(pl, "shard")
					end
				end
				break
			end
		end
	end
end

-- whether the player takes part in the running storm (Combat: the hunt waits)
function Weather.inStorm(p: Player): boolean
	return participants[p] == true and os.clock() < stormUntil
end

local function rewardAll()
	for _, p in Players:GetPlayers() do
		local data = services.PlayerData.get(p)
		local active = participants[p] and (not services.Reward or not services.Reward.isActive or services.Reward.isActive(p))
		if data and active then
			local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0 }
			local rate = Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
			local coins, egg = WeatherCore.dragonReward(shardCount, SD.shards, rate, SD, Config.Quests.minMinutesReward)
			if egg and services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
				coins += (Config.Quests and Config.Quests.eggFallbackCoins) or 300 -- day 1 = one dragon
				egg = nil
			end
			if coins > 0 then
				services.Nest.addCoins(p, coins, "StormDragon")
			end
			if egg then
				local e: any = Eggs.rollGuaranteed("stormDragon", SD.reward.egg, "Common", function()
					return rng:NextNumber()
				end, B, Config.Elements)
				e.foundAt = os.time()
				services.PlayerData.update(p, "eggs", function(eg)
					eg.shelf = eg.shelf or {}
					table.insert(eg.shelf, e)
					return nil
				end)
			end
			services.Net.notice(p, { kind = "reward", title = Loc.text(T.dragonDone, { k = shardCount, n = SD.shards }),
				sub = if egg then Loc.text(T.dragonRewardEgg, { coins = coins }) elseif coins > 0 then Loc.text(T.dragonReward, { coins = coins }) else nil,
				coins = coins, color = "storm" })
			if services.Analytics then
				services.Analytics.custom(p, "storm_dragon", shardCount)
			end
		end
	end
end

-- one event: the silhouette, the shards in a circle, the scale, the reward (by the clock from runDragon or from Studio debugging)
local dragonBusy = false
local function dragonEvent()
	if dragonBusy then
		return
	end
	dragonBusy = true
	SD = WeatherCore.dragonChapter(B.stormDragon, if services.LiveOps then services.LiveOps.live() else 0)
	do
		shardCount = 0
		set("Shards", 0)
		set("ShardsTotal", SD.shards)
		set("Dragon", true)
		set("DragonEndsAt", os.time() + SD.duration)
		local center = Vector3.new(Config.World.keeper.x, 0, Config.World.keeper.z)
		local pts = WeatherCore.shardPoints(SD.shards * 3, { center.X, 0, center.Z }, WV.shardRing[1], WV.shardRing[2], os.time())
		local drops: { Vector3 } = {}
		for _, p in pts do
			if #drops >= SD.shards then
				break
			end
			local g = groundAt(p[1], p[3])
			if g then
				table.insert(drops, g)
			end
		end
		-- the silhouette flies ON THE CLIENTS (a PivotTo in the server Heartbeat would replicate the whole model 60 times a second, with
		-- jerks): the server puts the template into WeatherState and the start time, Controllers/Weather clones it and drives it around by itself
		local m = silhouette()
		dragonModel = m
		if m then
			m.Name = "StormDragonModel"
			m.Parent = folder
		end
		set("DragonStartAt", workspace:GetServerTimeNow())
		participants = {}
		stormUntil = os.clock() + SD.duration
		for _, p in Players:GetPlayers() do -- 04 §8: the reward to those who were present at the start and were not AFK
			-- those currently fighting the Gloom are not called into the storm (picking up a shard makes them a participant, as before)
			if eligible(p) and not (services.Combat and services.Combat.fighting and services.Combat.fighting(p)) then -- without an adult - not a participant (becomes one if he raises an adult and picks up a shard)
				participants[p] = true
			end
		end
		local t0 = os.clock()
		local dropAt = SD.duration * 0.15
		local dropEvery = (SD.duration * 0.55) / math.max(#drops, 1)
		local dropped = 0
		local tEnd = os.clock() + SD.duration
		while os.clock() < tEnd do
			task.wait(0.25)
			local t = os.clock() - t0
			while dropped < #drops and t >= dropAt + dropped * dropEvery do
				dropped += 1
				dropShard(drops[dropped])
			end
			pcall(pickShards)
		end
		if m then
			m:Destroy()
		end
		dragonModel = nil
		for _, s in shards do
			s:Destroy()
		end
		shards = {}
		set("Dragon", false)
		pcall(rewardAll)
	end
	dragonBusy = false
end

local function dragonOnce()
	do
		local wait, on, _left = WeatherCore.dragonClock(os.time(), SD)
		if on then -- the server started in the middle of an event: wait for the end of the window (review: we waited until the half-hour boundary and landed in the window again - there was never a dragon)
			task.wait(_left + 1)
			return
		end
		set("DragonAt", os.time() + wait)
		if wait > SD.warnSeconds then
			task.wait(wait - SD.warnSeconds)
		end
		if #Players:GetPlayers() > 0 then
			noticeEligible({ kind = "announce", text = T.stormDragonComing }) -- the banner only to players with an adult
		end
		task.wait(math.min(wait, SD.warnSeconds))
		if #Players:GetPlayers() > 0 then
			local ok, err = pcall(dragonEvent)
			if not ok then
				dragonBusy = false
				set("Dragon", false)
				warn("[Weather] dragon event: " .. tostring(err))
			end
		end
	end
end

local function runDragon()
	while true do
		local ok, err = pcall(dragonOnce)
		if not ok then
			warn("[Weather] dragon: " .. tostring(err))
			task.wait(30)
		end
	end
end

-- Studio only: ServerStorage.WeatherDebug:Invoke("storm" | "starfall" | "aurora" | "dragon" | "shard" | "state")
local function debugCmd(cmd: string): string
	if cmd == "storm" or cmd == "starfall" or cmd == "aurora" then
		kind = cmd
		kindEnds = os.time() + W.duration
		set("Kind", kind)
		set("EndsAt", kindEnds)
		announce(startText(kind))
		if kind == "starfall" and services.EggSpawner and services.EggSpawner.refillAll then
			services.EggSpawner.fastUntil = os.time() + W.starfall.fastSeconds
			services.EggSpawner.refillAll()
		end
	elseif cmd == "dragon" then
		task.spawn(dragonEvent)
		task.wait(0.5)
	elseif cmd == "shard" then -- a shard under the first player's feet
		local p = Players:GetPlayers()[1]
		local pos = p and services.Nest.rootPos(p)
		if pos and folder and folder:GetAttribute("Dragon") then
			dropShard(pos - Vector3.new(0, 2.5, 0))
		end
	end
	local p1 = Players:GetPlayers()[1]
	return string.format("kind=%s storm=%s mult=%s dragon=%s shards=%d/%d left=%d model=%s eligible=%s participant=%s", kind, tostring(Weather.isStorm()), tostring(Weather.coinsMult()),
		tostring(folder and folder:GetAttribute("Dragon")), shardCount, SD.shards, #shards, tostring(dragonModel ~= nil and dragonModel.Parent ~= nil),
		tostring(p1 ~= nil and eligible(p1)), tostring(p1 ~= nil and participants[p1] == true))
end

function Weather.init(s: { [string]: any })
	services = s
	local f = Instance.new("Folder")
	f.Name = "WeatherState"
	f:SetAttribute("Kind", "")
	f:SetAttribute("Dragon", false)
	f.Parent = ReplicatedStorage
	folder = f
	if RunService:IsStudio() then
		local bf = Instance.new("BindableFunction")
		bf.Name = "WeatherDebug"
		bf.OnInvoke = debugCmd
		bf.Parent = game:GetService("ServerStorage")
	end
end

function Weather.start()
	task.spawn(function() -- Update Party: the PartyEndsAt attribute for the client, a banner at the start
		local was = false
		while true do
			local left = Weather.partyLeft(clock())
			set("PartyEndsAt", if left > 0 then os.time() + left else 0)
			if left > 0 and not was then
				announce(T.updateParty, nil)
			end
			was = left > 0
			task.wait(5)
		end
	end)
	task.spawn(function()
		local ok, err = pcall(runWeather)
		if not ok then
			warn("[Weather] weather: " .. tostring(err))
		end
	end)
	task.spawn(function()
		local ok, err = pcall(runDragon)
		if not ok then
			warn("[Weather] dragon: " .. tostring(err))
		end
	end)
end

return Weather
