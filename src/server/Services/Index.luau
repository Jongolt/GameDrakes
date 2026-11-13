--!strict
-- the dragon Index on the server (spec 03 §5, 06 §7). A new entry on a hatch -> Notice {kind="index"}
-- (a toast); the first hatch gifts the Keeper's entry "keeper" (02 §2, 0:18: "Meadow set 2/10"); Claim("index", set id) - the set
-- reward in minutes of nest income (at least Config.Index.minSetReward); the "Ancient worldwide" counter in the DataStore (Config.Index.store),
-- the value every readEvery s into the attribute ReplicatedStorage.AncientWorldwide (in Studio without the API - no attribute, the client shows ?).
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local IndexCore = require(Core:WaitForChild("Index"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))

local Index = {}

local services: { [string]: any } = {}
local B = Config.Balance
local IX = Config.Index

IndexCore.setup(Config.Elements, Config.Rarities)

-- open entries without the Keeper's entry (quest 15 "Ten pages")
function Index.countOf(data: any): number
	return IndexCore.count(data and data.index)
end

-- the Index bonus to the income: the share of open entries (for Economy.nestRate mods.indexPct)
function Index.pctOf(data: any): number
	return IndexCore.pct(data and data.index)
end

local function nestRate(data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = Index.pctOf(data) } -- 2.1: passes and the boost
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

-- after a hatch: a new entry? (called by Incubation; key is already written into data.index)
function Index.onHatched(player: Player, data: any, key: string, wasNew: boolean, ancient: boolean?, keeperNew: boolean?)
	local n = IndexCore.count(data.index)
	if wasNew then
		services.Net.notice(player, { kind = "index", key = key, count = n, total = IndexCore.total() })
		if services.Analytics then
			services.Analytics.custom(player, "index_entry_new", n, { key = key })
		end
	end
	if keeperNew then
		local meadow = IndexCore.set("meadow")
		local k, total = IndexCore.setProgress(data.index, meadow :: any)
		services.Nest.toast(player, Loc.text(Strings.Index.meadowSet, { n = k }))
		services.PlayerData.replicate(player, { "index" })
	end
	if ancient then
		task.spawn(function()
			pcall(function()
				DataStoreService:GetDataStore(IX.store):IncrementAsync(IX.ancientKey, 1)
			end)
		end)
	end
end

-- the Keeper's entry at the first hatch
function Index.giftKeeper(data: any): boolean
	if data.index.keeper then
		return false
	end
	data.index.keeper = true
	return true
end

function Index.claim(player: Player, id: string): { ok: boolean, reason: string?, coins: number? }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local set = IndexCore.set(id)
	if not set then
		return { ok = false, reason = "bad_request" }
	end
	if not IndexCore.setComplete(data.index, set) then
		return { ok = false, reason = "not_ready" }
	end
	data.rewards = data.rewards or {}
	data.rewards.indexClaimed = data.rewards.indexClaimed or {}
	if data.rewards.indexClaimed[id] then
		return { ok = false, reason = "already" }
	end
	local coins = math.max(IX.minSetReward, math.floor(nestRate(data) * 60 * set.minutes))
	services.PlayerData.update(player, { "coins", "rewards" }, function(_, d)
		d.coins = (d.coins or 0) + coins
		d.rewards.indexClaimed[id] = os.time()
		return nil
	end)
	if services.Analytics then
		services.Analytics.coins(player, "Source", coins, data.coins or 0, "Index", id)
	end
	return { ok = true, coins = coins }
end

local function readAncient()
	local ok, v = pcall(function()
		return DataStoreService:GetDataStore(IX.store):GetAsync(IX.ancientKey)
	end)
	if ok then
		ReplicatedStorage:SetAttribute("AncientWorldwide", tonumber(v) or 0)
	end
end

-- Studio only (LoopDebug "index [element]"): the state; with an element - open all its rarities (a Claim check)
function Index.debug(player: Player, arg: string): any
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if arg ~= "" and table.find(Config.Elements, arg) then
		services.PlayerData.update(player, "index", function(ix)
			for _, r in Config.Rarities do
				ix[IndexCore.key(arg, r)] = true
			end
			return nil
		end)
	end
	local claimed = {}
	for k in (data.rewards and data.rewards.indexClaimed or {}) :: { [string]: any } do
		table.insert(claimed, k)
	end
	table.sort(claimed)
	return { ok = true, reason = string.format("index %d/%d pct=%.2f claimed=%s claimable=%d anc=%s", IndexCore.count(data.index), IndexCore.total(), Index.pctOf(data), table.concat(claimed, ","), #IndexCore.claimable(data.index, data.rewards and data.rewards.indexClaimed), tostring(ReplicatedStorage:GetAttribute("AncientWorldwide"))) }
end

function Index.init(s: { [string]: any })
	services = s
end

function Index.start()
	services.Net.handle("Claim", function(player: Player, kind: string, id: string?)
		if kind == "index" then
			return Index.claim(player, tostring(id or ""))
		elseif kind == "away" and services.Nest then -- 2.5: Collect on the "while you were away" card
			return services.Nest.claimAway(player)
		elseif kind == "keeper" and services.Quest then -- 2.8: the element of the Rare egg of quest 15
			return services.Quest.claimPick(player, tostring(id or ""))
		elseif services.Reward then -- 2.4: timeGift / calendar / freeGift (the dailies are granted by themselves)
			return services.Reward.claim(player, kind, id)
		end
		return { ok = false, reason = "bad_request" }
	end)
	task.spawn(function()
		while true do
			readAncient()
			task.wait(IX.readEvery)
		end
	end)
end

return Index
