--!strict
-- the quests of the Keeper Old Ash (spec 06 §1, addendum 1.3; craft/04 §7.10 series 7 and §7.12: the quest
-- panel, "Done!"). Services send events (hatch, glide, eggInc, eggInc_<Zone>, feed, ride, fly, eggFound, elder, index, ascension)
-- -> the counters quests.counters always accumulate -> the steps close in order when the counter >= the goal (Core/Quests) -> the reward
-- (coins / minutes of nest income / an egg onto the shelf, with a full shelf - coins) -> Notice {kind="quest"} to the client with a pause
-- chainDelay between steps closed in a row. The progress is in the profile (quests.keeper.step), steps are not skipped.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Content = require(Shared:WaitForChild("Content"))
local Core = Shared:WaitForChild("Core")
local Quests = require(Core:WaitForChild("Quests"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local Eggs = require(Core:WaitForChild("Eggs"))
local IndexCore = require(Core:WaitForChild("Index"))
local Rewards = require(Core:WaitForChild("Rewards")) -- 2.8: the elements to choose from

local Quest = {}

local services: { [string]: any } = {}
local B = Config.Balance
local Q = Config.Quests
local rng = Random.new()

-- 2.9: how many updates run (quests 16+ open with update 1, Services/LiveOps)
local function live(): number
	return if services.LiveOps then services.LiveOps.live() else 0
end

local function ensure(data: any): Quests.State
	local qd = data.quests
	if typeof(qd) ~= "table" then
		qd = { keeper = { step = 1, progress = {} }, daily = { date = "", done = {}, bonus = false }, counters = {} }
		data.quests = qd
	end
	qd.keeper = qd.keeper or { step = 1, progress = {} }
	qd.keeper.step = qd.keeper.step or 1
	qd.counters = qd.counters or {}
	return qd
end

local function nestRate(data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) } -- 2.1: passes and the boost
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

-- the step reward: coins into the profile, an egg onto the shelf (if there is room, otherwise coins); returns (coins, the egg zone)
local function grant(data: any, q: Quests.Quest): (number, string?)
	local coins = q.reward.coins or 0
	if q.reward.minutes then
		coins += math.max(Q.minMinutesReward, math.floor(nestRate(data) * 60 * q.reward.minutes))
	end
	local eggZone: string? = nil
	if q.reward.egg and services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
		coins += Q.eggFallbackCoins -- day 1 = one dragon - coins instead of an egg
	elseif q.reward.egg and q.reward.minRarity == "Rare" then -- 2.8 (06 §1 item 15): a Rare egg with the element chosen from 3 - waits for the choice in Quests
		data.quests.keeper.pick = Rewards.choices(q.id + (data.nextUid or 1), Config.Elements, Config.Rewards.calendar.choices)
		eggZone = q.reward.egg
	elseif q.reward.egg then
		local shelf = data.eggs.shelf
		if #shelf < (data.shelfCap or B.shelf.start) then
			local egg: any = Eggs.rollGuaranteed("q" .. q.id, q.reward.egg, q.reward.minRarity or "Common", function()
				return rng:NextNumber()
			end, B, Config.Elements)
			egg.foundAt = os.time()
			table.insert(shelf, egg)
			eggZone = q.reward.egg
		else
			coins += Q.eggFallbackCoins
		end
	end
	data.coins = (data.coins or 0) + coins
	return coins, eggZone
end

-- close all consecutive steps whose counters are reached; notifications with a pause
function Quest.advance(player: Player)
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	local done: { { q: Quests.Quest, coins: number, eggZone: string? } } = {}
	services.PlayerData.update(player, { "quests", "coins", "eggs" }, function(_, d)
		local qd = ensure(d)
		while true do
			Quests.markBase(qd, live()) -- a fresh step counts from this moment
			local q = Quests.get(qd.keeper.step, live())
			-- the steps about a second egg / more dragons / found eggs / the Index are unreachable -
			-- skipped without a reward
			if q and Config.Raid and Config.Raid.on and Config.Raid.firstEggOnly and Quests.dayOneSkip(q) then
				qd.keeper.step += 1
				continue
			end
			if not q or not Quests.ready(qd, q) then
				break
			end
			local coins, eggZone = grant(d, q)
			table.insert(done, { q = q, coins = coins, eggZone = eggZone })
			qd.keeper.step += 1
		end
		return nil
	end)
	if #done > 0 and services.Analytics then -- the economy (Source Quest) and quest_done
		local d2 = services.PlayerData.get(player)
		for _, rec in done do
			services.Analytics.coins(player, "Source", rec.coins, (d2 and d2.coins) or 0, "Quest")
			services.Analytics.custom(player, "quest_done", rec.q.id)
		end
	end
	for i, rec in done do
		task.delay((i - 1) * Q.chainDelay, function()
			if player.Parent == Players then
				services.Net.notice(player, { kind = "quest", step = rec.q.id, title = rec.q.title, coins = rec.coins, eggZone = rec.eggZone, next = rec.q.id + 1 })
			end
		end)
		if rec.q.reward.minRarity == "Rare" then -- 2.8: the element choice waits in the Quests tab - say so
			task.delay(i * Q.chainDelay + 2, function()
				if player.Parent == Players then
					services.Nest.toast(player, Strings.Quests.pickEgg)
				end
			end)
		end
	end
end

-- 2.8 (06 §1 item 15): the element choice of the Keeper's Rare egg (Claim "keeper", the element from quests.keeper.pick)
function Quest.claimPick(player: Player, element: string): { ok: boolean, reason: string? }
	local data = services.PlayerData.get(player)
	local pick = data and data.quests and data.quests.keeper and data.quests.keeper.pick
	if typeof(pick) ~= "table" or #pick == 0 then
		return { ok = false, reason = "already" }
	end
	if not table.find(pick, element) then
		return { ok = false, reason = "bad_request" }
	end
	local egg: any = Eggs.rollGuaranteed("q15", "Meadow", "Rare", function()
		return rng:NextNumber()
	end, B, Config.Elements, element)
	egg.foundAt = os.time()
	local allowed = not services.PlayerData.eggsAllowed or services.PlayerData.eggsAllowed(services.PlayerData.get(player))
	services.PlayerData.update(player, { "quests", "eggs" }, function(qd, d)
		qd.keeper.pick = nil
		if allowed then
			table.insert(d.eggs.shelf, egg) -- the reward is not lost: onto the shelf even beyond the cap (like the 2.4 rewards)
		end
		return nil
	end)
	if not allowed then -- an old profile with a pending choice - coins instead of the Rare egg
		services.Nest.addCoins(player, Q.eggFallbackCoins)
	end
	services.Net.notice(player, { kind = "reward", title = Strings.Quests.rewardRare, sub = (Content.Elements[element] or { name = element }).name, coins = 0, color = "daily" })
	return { ok = true }
end

-- an event: the counter += n (default 1)
function Quest.event(player: Player, name: string, n: number?)
	if not services.PlayerData.get(player) then
		return
	end
	services.PlayerData.update(player, "quests", function(_, d)
		local qd = ensure(d)
		qd.counters[name] = (qd.counters[name] or 0) + (n or 1)
		return nil
	end)
	Quest.advance(player)
	if services.Reward then -- 2.4: the same events accumulate the daily tasks (eggFound, feed, hatch, eggInc_<Zone>)
		services.Reward.event(player, name, n)
	end
	if services.Badges then -- 2.8 (06 §5): the first hatch, gliding, riding, flight, ascension, an elder
		services.Badges.event(player, name)
	end
	if services.Analytics and services.Analytics.action then -- the returning player's first action (hatch, feed, eggFound, glide, ...)
		services.Analytics.action(player, name)
	end
end

-- the counter at least value (the Index: the number of entries; a sync on join)
function Quest.set(player: Player, name: string, value: number)
	if not services.PlayerData.get(player) then
		return
	end
	services.PlayerData.update(player, "quests", function(_, d)
		local qd = ensure(d)
		if (qd.counters[name] or 0) < value then
			qd.counters[name] = value
		end
		return nil
	end)
	Quest.advance(player)
	if name == "index" and services.Badges and value >= math.ceil(Config.Balance.index.total * 0.25) then -- 2.8: the Collector badge (25% of the Index)
		services.Badges.award(player, "index25")
	end
end

-- on join: the floor of the counters from the profile (dragons, the Index, ascension, an elder) - for profiles before 1.10 and in case of a missed event
function Quest.sync(player: Player, data: any)
	local dragons, index, elder, grownFirst = 0, 0, 0, false
	for _, d in (data.dragons or {}) :: { [string]: any } do
		dragons += 1
		if (d.stage or 0) >= 3 then
			elder = 1
		end
		if d.growAs and (d.stage or 0) >= 1 then -- the firstborn already grew out of the hatchling stage
			grownFirst = true
		end
	end
	-- the firstborn grew while the player never glided - step 2 "Wings of a hatchling" is closed on join
	-- like Nest.tick on growth (without the Glider badge and without onboarding.glided): profiles that grew before the release would otherwise stay at step 2
	local glide = if grownFirst and not (data.onboarding and data.onboarding.glided) then 1 else 0
	for _ in (data.index or {}) :: { [string]: any } do
		index += 1
	end
	local floors = { hatch = dragons, index = index, ascension = data.ascension or 0, elder = elder, glide = glide }
	services.PlayerData.update(player, "quests", function(_, d)
		local qd = ensure(d)
		for k, v in floors do
			if (qd.counters[k] or 0) < v then
				qd.counters[k] = v
			end
		end
		return nil
	end)
	Quest.advance(player)
end

-- Studio only (LoopDebug "quest [event|reset]"): the state, a manual event, a chain reset
function Quest.debug(player: Player, arg: string): any
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if arg == "pick" then -- 2.8: as if quest 15 is closed - the element choice of the Rare egg
		services.PlayerData.update(player, "quests", function(_, d)
			ensure(d).keeper.pick = Rewards.choices(15, Config.Elements, Config.Rewards.calendar.choices)
			return nil
		end)
		return { ok = true, reason = "pick " .. table.concat(data.quests.keeper.pick, ",") }
	end
	if arg == "reset" then
		services.PlayerData.update(player, "quests", function(_, d)
			local qd = ensure(d)
			qd.keeper.step = 1
			qd.counters = {}
			return nil
		end)
		return { ok = true, reason = "reset" }
	elseif arg ~= "" then
		Quest.event(player, arg)
	end
	local qd = ensure(data)
	local k, n, q = Quests.progress(qd, live())
	local parts = {}
	for key, v in qd.counters do
		table.insert(parts, key .. "=" .. tostring(v))
	end
	table.sort(parts)
	return { ok = true, reason = string.format("step %d (%s) %d/%d coins=%d shelf=%d | %s", qd.keeper.step, if q then q.title else "all done", k, n, math.floor(data.coins or 0), #data.eggs.shelf, table.concat(parts, " ")) }
end

function Quest.init(s: { [string]: any })
	services = s
end

function Quest.start()
	services.PlayerData.Loaded:Connect(function(player: Player, data: any)
		Quest.sync(player, data)
	end)
	for _, p in Players:GetPlayers() do
		local d = services.PlayerData.get(p)
		if d then
			Quest.sync(p, d)
		end
	end
end

return Quest
