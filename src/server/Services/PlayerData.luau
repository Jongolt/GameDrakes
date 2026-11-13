--!strict
-- Player data (10 §3, §5, §6; craft/01 §2, §6): ProfileStore (session locking, autosave 120 s), the v2 template,
-- migrations by schemaVersion, the single writer update(), private keys, replication of changed keys to the client through
-- State (in a batch once per frame), playing on the template without saving when loading fails, waiting for the profile for receipts, the profile
-- mail (offline gifts), error plaques. Nobody else changes profile.Data directly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local ProfileStore = require(ServerScriptService:WaitForChild("Vendor"):WaitForChild("ProfileStore"))

local PlayerData = {}

-- keys that do not go to the client
local PRIVATE = { purchases = true, purchaseLog = true, giftsReceived = true, analytics = true, policy = true, pendingGift = true, pendingPick = true, codes = true, invite = true }

-- the v2 profile template (10 §6); ProfileStore rules: no nil values, no holes in arrays, keys are strings or numbers
local TEMPLATE = {
	schemaVersion = Config.SchemaVersion,
	createdAt = 0,
	lastSeen = 0,
	sessions = 0,
	playSeconds = 0,
	source = "other",
	device = "unknown",
	loadSeconds = 0, -- seconds from the client start to the character's appearance (the last join)
	coins = 0,
	pot = 0,
	ascension = 0,
	dragons = {}, -- Core/Dragons.Inventory lives right in the profile: dragons, nestOrder, companion, nextUid
	nestOrder = {},
	nextUid = 1,
	sanctuaryCap = Config.Balance.sanctuary.start,
	slots = { coins = Config.Balance.slots.start },
	incubators = Config.Balance.incubators.start,
	shelfCap = Config.Balance.shelf.start,
	eggs = { shelf = {}, incubating = {} }, -- carry = the egg in hand (the key appears on a pickup)
	items = { treats = 0, hatchNow = {}, growNow = {} },
	owned = {},
	boost = { secondsLeft = 0 },
	quests = { keeper = { step = 1, progress = {} }, daily = { date = "", ids = {}, counters = {}, done = {}, bonus = false }, counters = {} }, -- 2.4: daily.ids - the day's tasks, counters - the day's counters
	rewards = {
		timeGifts = { claimed = {} }, -- 2.4: [minute] = true, per session (Reward clears on join)
		calendar = { day = 0, lastDate = "", claimed = 0 }, -- 2.4: claimed - the last claimed day
		season = { points = 0, claimed = {} },
		freeGift = { group = false },
		indexClaimed = {},
	},
	index = {},
	badges = {},
	secrets = {}, -- the discovered secret spots [id] = os.time() of the first discovery (the Springs grotto)
	purchases = {},
	purchaseLog = {},
	giftsReceived = {},
	away = { coins = 0, seconds = 0, eggs = 0, grew = {} }, -- 2.5: the "while you were away" summary until Collect is pressed (Core/Offline)
	pendingGift = {}, -- 2.1: [Gift product number] = the recipient's UserId until the receipt arrives (07 §5 item 1)
	pendingPick = nil, -- the Starter Pack elements chosen before the receipt (a list), so a receipt from another server grants them
	onboarding = { stage = "spawn", hints = {} },
	settings = { otherDragons = true }, -- P37: show other players' dragons (Settings); old profiles get the key through Reconcile
	-- looks (07 add. 2.6): the nest look - "" (by priority royal > gilded > lagoon), "classic" or a skin id; the color preset - dragons[uid].preset
	looks = { nestSkin = "" },
	raid = { home = 0 }, -- raid eggs brought home (Services/Raid); the golden nest - after Glow.egg.afterRaids
	glowEgg = { taken = 0 }, -- the glowing egg (Services/GlowEgg) - taken (unix) or 0
	migr = {}, -- one-time data conversions (spareEggs: the egg stock -> coins, the list of taken eggs for a return)
	combat = { stage = 0, guardians = 0, firstAt = 0, waves = 0, fightSec = 0 }, -- Gloom stages passed, guardians, the time of the first hit (Reconcile adds for old ones); waves and fight seconds in total (combat pacing, zones_scan)
	codes = {}, -- 2.9 (09 §1): the entered codes of the week [CODE] = os.time()
	invite = { by = 0, sec = 0, got = "", at = 0 }, -- came by the invite of by (UserId), seconds in the game without AFK since, the reward (rarity, once)
	analytics = { purchasesCount = 0 },
	policy = {},
}
PlayerData.Template = TEMPLATE

local function deepcopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepcopy(v)
	end
	return out
end

-- migrations: [version] = a function version -> version + 1 (pure; PlayerData.migrate is checked by a test)
local MIGRATIONS: { [number]: (any) -> any } = {
	[1] = function(data: any): any
		-- v1 (engine 0.5, another game) has no data in Profile_v2; a skeleton for the future
		return data
	end,
}

-- by the new rule (Raid.firstEggOnly) a player with
-- a dragon gets no more eggs - coins instead of an egg; the same rate is applied to the shelf stock of old profiles, once.
-- By rarity (Config.Quests.spareEggCoins), the bowls are not touched, the taken eggs lie in data.migr.spareEggs.eggs for a return on a complaint.
-- A toast on join (after 8 s, when the client is ready) and the analytics event migr_spare_eggs (n, coins)
local servicesRef: any = nil -- the services for the migration toast/analytics (init)
local function convertSpareEggs(player: Player, data: any)
	local R = Config.Raid
	if not (R and R.on and R.firstEggOnly) or not (Config.Quests and Config.Quests.spareEggsToCoins) then
		return -- off for now (Config.Quests.spareEggsToCoins)
	end
	if typeof(data.migr) ~= "table" then
		data.migr = {}
	end
	if data.migr.spareEggs ~= nil then
		return
	end
	local dragons = if typeof(data.nestOrder) == "table" then #data.nestOrder else 0
	local eggs = data.eggs
	local shelf = if typeof(eggs) == "table" and typeof(eggs.shelf) == "table" then eggs.shelf else nil
	if dragons < 1 or not shelf or #shelf == 0 then
		return
	end
	local prices = (Config.Quests and Config.Quests.spareEggCoins) or {}
	local fallback = (Config.Quests and Config.Quests.eggFallbackCoins) or 300
	local coins = 0
	for _, e in shelf do
		local rarity = if typeof(e) == "table" then e.rarity else nil
		coins += tonumber(prices[rarity]) or fallback
	end
	local n = #shelf
	data.migr.spareEggs = { at = os.time(), n = n, coins = coins, eggs = shelf }
	eggs.shelf = {}
	data.coins = (tonumber(data.coins) or 0) + coins
	task.delay(8, function()
		if player.Parent ~= Players then
			return
		end
		if servicesRef and servicesRef.Net then
			servicesRef.Net.notice(player, { kind = "toast", text = Loc.text(Strings.Migr.spareEggs, { n = n, coins = coins }) })
		end
		if servicesRef and servicesRef.Analytics then
			pcall(servicesRef.Analytics.custom, player, "migr_spare_eggs", n, { coins = coins })
		end
	end)
end

function PlayerData.migrate(data: any): any
	local v = data.schemaVersion or 1
	while v < Config.SchemaVersion do
		local m = MIGRATIONS[v]
		if not m then
			error("no migration from version " .. v)
		end
		data = m(data)
		v += 1
		data.schemaVersion = v
	end
	return data
end

-- ---------------------------------------------------------------------------------------------- the service state
local store: any = nil
local profiles: { [Player]: any } = {} -- active ProfileStore profiles
local fallback: { [Player]: any } = {} -- data on the template when loading fails (not saved)
local dirty: { [Player]: { [string]: boolean } } = {}
local joinSeen: { [Player]: number } = {} -- 2.5: lastSeen at the profile load (offline income)
local stateRemote: RemoteEvent? = nil
local noticeRemote: RemoteEvent? = nil
local loadedEvent = Instance.new("BindableEvent")
local messageHandlers: { (Player, any) -> boolean } = {}

PlayerData.Loaded = loadedEvent.Event -- (player, data) after the profile or the template is loaded

local function publicCopy(data: any): any
	local out = {}
	for k, v in data do
		if not PRIVATE[k] then
			out[k] = v
		end
	end
	return out
end

local function notify(player: Player, payload: any)
	if noticeRemote and player.Parent == Players then
		noticeRemote:FireClient(player, payload)
	end
end

function PlayerData.get(player: Player): any?
	local p = profiles[player]
	if p then
		return p.Data
	end
	return fallback[player]
end

function PlayerData.profile(player: Player): any?
	return profiles[player]
end

function PlayerData.canSave(player: Player): boolean
	local p = profiles[player]
	return p ~= nil and p:IsActive()
end

-- The single writer: fn(value, data) changes the value in place or returns a new one; keys - a string or a list.
-- The changed keys go to the client in a batch at the end of the frame (private ones do not).
function PlayerData.update(player: Player, keys: string | { string }, fn: (any, any) -> any?): boolean
	local data = PlayerData.get(player)
	if not data then
		return false
	end
	local list: { string } = if type(keys) == "string" then { keys :: string } else keys :: { string }
	local result = fn(data[list[1]], data)
	if result ~= nil then
		data[list[1]] = result
	end
	PlayerData.replicate(player, list)
	return true
end

function PlayerData.replicate(player: Player, keys: { string })
	local d = dirty[player]
	if not d then
		d = {}
		dirty[player] = d
	end
	for _, k in keys do
		if not PRIVATE[k] then
			d[k] = true
		end
	end
end

local function flush()
	for player, keys in dirty do
		local data = PlayerData.get(player)
		if data and stateRemote and player.Parent == Players then
			local patch = {}
			local any = false
			for k in keys do
				patch[k] = data[k]
				any = true
			end
			if any then
				stateRemote:FireClient(player, { patch = patch })
			end
		end
		dirty[player] = nil
	end
end

function PlayerData.sendFull(player: Player)
	local data = PlayerData.get(player)
	if data and stateRemote then
		stateRemote:FireClient(player, { full = true, data = publicCopy(data), canSave = PlayerData.canSave(player) })
	end
end

-- Wait for the profile (up to seconds) or the player leaving; for ProcessReceipt (07 §4). Returns the profile or nil.
function PlayerData.waitProfileOrLeave(player: Player, seconds: number): any?
	local deadline = os.clock() + seconds
	while player.Parent == Players and os.clock() < deadline do
		local p = profiles[player]
		if p then
			return p
		end
		if fallback[player] then
			return nil -- loading refused: saving is not allowed
		end
		task.wait(0.5)
	end
	return profiles[player]
end

function PlayerData.save(player: Player): boolean
	local p = profiles[player]
	if p and p:IsActive() then
		p:Save()
		return true
	end
	return false
end

-- the first day gives no more dragons: one lock on all egg sources
-- (Gloom nests, free eggs, combat rewards, the Keeper, gifts, the storm): with a dragon eggs are not given, coins instead of an egg
-- (Config.Quests.eggFallbackCoins). Switched off by Config.Raid.firstEggOnly
function PlayerData.eggsAllowed(data: any): boolean
	local R = Config.Raid
	if not (R and R.on and R.firstEggOnly) then
		return true
	end
	local n = if typeof(data) == "table" and typeof(data.nestOrder) == "table" then #data.nestOrder else 0
	return n < 1
end

-- A profile reset in place: all keys - by the template, createdAt and sessions anew
-- the profile.Data table stays the same (ProfileStore saves it on the next autosave/leave)
function PlayerData.reset(player: Player): boolean
	local data = PlayerData.get(player)
	if not data then
		return false
	end
	for k in data do
		data[k] = nil
	end
	for k, v in deepcopy(TEMPLATE) do
		data[k] = v
	end
	data.createdAt = os.time()
	data.lastSeen = os.time()
	data.sessions = 1
	PlayerData.sendFull(player)
	return true
end

-- 2.5: the profile's lastSeen at the load moment (the end of the previous session); 0 - the first join or the template
function PlayerData.joinLastSeen(player: Player): number
	return joinSeen[player] or 0
end

-- Profile mail handlers (gifts to an offline recipient): fn(player, message) -> true if the message was handled
function PlayerData.onMessage(fn: (Player, any) -> boolean)
	table.insert(messageHandlers, fn)
end

-- 2.1: a letter into a profile by key (UserId as a string) regardless of whether it has a session (ProfileStore:MessageAsync, up to 1,000
-- in the queue); true = written reliably. The recipient processes it through the onMessage handlers on join / the next autosave.
function PlayerData.message(profileKey: string, message: any): boolean
	if not store then
		return false
	end
	return store:MessageAsync(profileKey, message) == true
end

-- ---------------------------------------------------------------------------------------------- join and leave
local function onPlayerAdded(player: Player)
	local profile = store:StartSessionAsync(tostring(player.UserId), {
		Cancel = function()
			return player.Parent ~= Players
		end,
	})
	if player.Parent ~= Players then
		if profile then
			profile:EndSession()
		end
		return
	end
	if profile == nil then
		-- loading refused: play on the template, save nothing and sell nothing; the main thing - not to write the template over the progress
		local data = deepcopy(TEMPLATE)
		fallback[player] = data
		warn("[PlayerData] the profile did not load, the player is on the template without saving: " .. player.Name)
		PlayerData.sendFull(player)
		notify(player, { kind = "dataError", text = Strings.Loading.dataError })
		loadedEvent:Fire(player, data)
		return
	end
	profile:AddUserId(player.UserId)
	-- Studio only: without the API ProfileStore keeps the profile in
	-- memory until the game stops, so the probe puts the profile dumped on leaving (LoopDebug "dump") into ServerStorage.StudioSeed
	-- (a StringValue, JSON) in edit mode - on join it replaces the empty profile. Does not fire in the live game (IsStudio).
	if RunService:IsStudio() then
		local seed = ServerStorage:FindFirstChild("StudioSeed")
		if seed and seed:IsA("StringValue") and seed.Value ~= "" then
			local ok, decoded = pcall(function()
				return HttpService:JSONDecode(seed.Value)
			end)
			if ok and type(decoded) == "table" then
				profile.Data = decoded
			else
				warn("[PlayerData] StudioSeed not read: " .. tostring(decoded))
			end
		end
	end
	PlayerData.migrate(profile.Data)
	profile:Reconcile()
	joinSeen[player] = profile.Data.lastSeen -- 2.5: before the one-second loop below overwrites lastSeen
	profile.OnSessionEnd:Connect(function()
		profiles[player] = nil
		dirty[player] = nil
		if player.Parent == Players then
			player:Kick(Strings.Loading.sessionElsewhere)
		end
	end)
	profiles[player] = profile
	local data = profile.Data
	convertSpareEggs(player, data)
	if data.createdAt == 0 then
		data.createdAt = os.time()
	end
	data.sessions += 1
	profile:MessageHandler(function(message: any, processed: () -> ())
		for _, h in messageHandlers do
			local ok, handled = pcall(h, player, message)
			if ok and handled then
				processed()
				return
			end
		end
		-- nobody took it - it stays in the queue until the next session (the gift service appears in stage 2)
	end)
	PlayerData.sendFull(player)
	loadedEvent:Fire(player, data)
end

-- a data snapshot on leaving before EndSession (Notify - the notification queue); the handler must not yield
local leaving: { (Player, any) -> () } = {}
function PlayerData.onLeaving(fn: (Player, any) -> ())
	table.insert(leaving, fn)
end

local function onPlayerRemoving(player: Player)
	local profile = profiles[player]
	if profile then
		profile.Data.lastSeen = os.time()
		for _, fn in leaving do
			local ok, err = pcall(fn, player, profile.Data)
			if not ok then
				warn("[PlayerData] leaving hook: " .. tostring(err))
			end
		end
		profile:EndSession()
	end
	profiles[player] = nil
	fallback[player] = nil
	dirty[player] = nil
	joinSeen[player] = nil
end

-- ---------------------------------------------------------------------------------------------- init / start
function PlayerData.init(services: { [string]: any })
	servicesRef = services
	ProfileStore.SetConstant("AUTO_SAVE_PERIOD", Config.AutoSaveSeconds)
	-- P37: the Settings toggles are stored in the profile; the key and the type are checked by Net against the Remotes.Setting schema
	if services.Net then
		services.Net.handle("Setting", function(player: Player, key: string, on: boolean)
			local ok = PlayerData.update(player, "settings", function(s: any)
				if type(s) ~= "table" then
					return { [key] = on }
				end
				s[key] = on
				return nil
			end)
			return if ok then { ok = true } else { ok = false, reason = "loading" }
		end)
	end
	store = ProfileStore.New(Config.ProfileStoreName, TEMPLATE)
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	stateRemote = remotes:WaitForChild("State") :: RemoteEvent
	noticeRemote = remotes:WaitForChild("Notice") :: RemoteEvent
	ProfileStore.OnCriticalToggle:Connect(function(isCritical: boolean)
		for player in profiles do
			notify(player, { kind = "saveError", on = isCritical, text = Strings.Loading.saveError })
		end
	end)
end

function PlayerData.start()
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	RunService.Heartbeat:Connect(flush)
	task.spawn(function() -- once a second: the play time and lastSeen (the offline income is counted from it)
		while true do
			task.wait(1)
			local now = os.time()
			for _, profile in profiles do
				if profile:IsActive() then
					profile.Data.playSeconds += 1
					profile.Data.lastSeen = now
				end
			end
		end
	end)
end

return PlayerData
