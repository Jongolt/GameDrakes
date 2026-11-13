--!strict
-- 2.4: rewards of spec 06 §2-4, §6, §8 (10 §3: RewardService). The logic - Core/Rewards, the numbers - Config.Rewards.
-- Dailies: the day's tasks in the profile (quests.daily.ids), the day's counters from service events (Quest.event forwards here; own ones -
-- visit, playSec, flySec, grow, ring, hatchRare), closing - coins of "minutes of income" + a season point at once, all three - a Cliffs egg.
-- Gifts over time: session seconds without AFK (the player attribute GiftSec for the client timer), Claim("timeGift", minute), per session.
-- The calendar: a day on the first join of a UTC day (if the previous one is claimed), Claim("calendar", the element for the Rare hatchling).
-- Free Gift: Claim("freeGift") after joining the group (IsInGroupAsync), once; Config.Rewards.freeGift.groupId = 0 - off.
-- Weekly quests (spec 06 add. 21.10): two from Content.Updates[live].weekly (quests.weekly), the same events as the dailies, plus hatchEl_/
-- hatchSky_/hatchAt_/variant_ (Incubation) and growEl_ (Nest); closing - season points + an egg of the set's zone; the clock LiveOps.now().
-- Reward eggs - onto the nest shelf (Incubation shows them and puts them into a free incubator by itself).

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Core = Shared:WaitForChild("Core")
local Rewards = require(Core:WaitForChild("Rewards"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local Eggs = require(Core:WaitForChild("Eggs"))
local IndexCore = require(Core:WaitForChild("Index"))

local Reward = {}

local services: { [string]: any } = {}
local B = Config.Balance
local R = Config.Rewards
local TG = R.timeGifts
local W = R.weekly
local S = Strings.Rewards
local rng = Random.new()

type Session = { sec: number, active: number, lastPos: Vector3?, play: number, visited: { [number]: boolean }, freeShown: boolean, dailyShown: boolean, activeAt: number }
local sessions: { [Player]: Session } = {}
local nestBoxes: { [number]: { cf: CFrame, size: Vector3 } } = {}
local checking: { [Player]: boolean } = {} -- Free Gift: a group check in progress


local function r01(): number
	return rng:NextNumber()
end

-- the profile: the 2.4 fields on old profiles (Reconcile gives the template but not the nested keys of old tables)
local function ensure(d: any)
	d.quests = if typeof(d.quests) == "table" then d.quests else {}
	local q = d.quests
	q.daily = if typeof(q.daily) == "table" then q.daily else {}
	q.daily.date = q.daily.date or ""
	q.daily.ids = if typeof(q.daily.ids) == "table" then q.daily.ids else {}
	q.daily.counters = if typeof(q.daily.counters) == "table" then q.daily.counters else {}
	q.daily.done = if typeof(q.daily.done) == "table" then q.daily.done else {}
	q.daily.bonus = q.daily.bonus == true
	q.weekly = if typeof(q.weekly) == "table" then q.weekly else {}
	q.weekly.week = q.weekly.week or -1
	q.weekly.update = q.weekly.update or 0
	q.weekly.counters = if typeof(q.weekly.counters) == "table" then q.weekly.counters else {}
	q.weekly.done = if typeof(q.weekly.done) == "table" then q.weekly.done else {}
	d.rewards = if typeof(d.rewards) == "table" then d.rewards else {}
	local rw = d.rewards
	rw.timeGifts = if typeof(rw.timeGifts) == "table" then rw.timeGifts else {}
	rw.timeGifts.claimed = if typeof(rw.timeGifts.claimed) == "table" then rw.timeGifts.claimed else {}
	rw.calendar = if typeof(rw.calendar) == "table" then rw.calendar else {}
	rw.calendar.day = rw.calendar.day or 0
	rw.calendar.lastDate = rw.calendar.lastDate or ""
	rw.calendar.claimed = rw.calendar.claimed or 0
	rw.season = if typeof(rw.season) == "table" then rw.season else {}
	rw.season.points = rw.season.points or 0
	rw.season.claimed = if typeof(rw.season.claimed) == "table" then rw.season.claimed else {}
	rw.freeGift = if typeof(rw.freeGift) == "table" then rw.freeGift else {}
	rw.freeGift.group = rw.freeGift.group == true
end

local function nestRate(data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) }
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

-- "N minutes of income" (like the Keeper's quests: at least minMinutesReward)
local function minutesCoins(data: any, minutes: number): number
	return math.max(Config.Quests.minMinutesReward, math.floor(nestRate(data) * 60 * minutes))
end

local function giveCoins(player: Player, n: number, txType: string)
	if n > 0 then
		services.Nest.addCoins(player, n, txType)
	end
end

-- an egg onto the shelf (the shelf may overflow: the reward is not lost, they go into the incubator in turn)
-- day 1 = one dragon (PlayerData.eggsAllowed) - coins instead of an egg, returns false
local function giveEgg(player: Player, egg: any): boolean
	local data = services.PlayerData.get(player)
	if services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
		services.Nest.addCoins(player, (Config.Quests and Config.Quests.eggFallbackCoins) or 300, "Reward")
		return false
	end
	egg.foundAt = os.time()
	services.PlayerData.update(player, "eggs", function(e)
		e.shelf = e.shelf or {}
		table.insert(e.shelf, egg)
		return nil
	end)
	return true
end
local function coinsText(): string
	return Loc.text(S.gotCoins, { n = (Config.Quests and Config.Quests.eggFallbackCoins) or 300 })
end

local function maxStage(data: any): number
	local m = 0
	for _, d in (data.dragons or {}) :: { [string]: any } do
		m = math.max(m, d.stage or 0)
	end
	return m
end

-- berries: feeding n dragons; those left out - minutes of income
local function giveBerries(player: Player, data: any, n: number, txType: string): (number, number)
	local fed = if services.Nest.feedFree then services.Nest.feedFree(player, n) else 0
	local coins = 0
	if fed < n then
		coins = minutesCoins(data, R.berryFallbackMinutes * (n - fed))
		giveCoins(player, coins, txType)
	end
	return fed, coins
end

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Wood
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the Season 1 banner (06 §8, step 4): a pole and a cloth in the season color with a golden trim
local function banner(pos: Vector3, parent: Instance)
	local BN = R.season.banner
	local h = BN.height
	local post = part({ Name = "Pole", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h + 1, 0.5, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, (h + 1) / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(78, 52, 36) }, parent)
	post.CanCollide = true
	part({ Name = "Cloth", Size = Vector3.new(0.15, h * 0.55, 2.6), CFrame = CFrame.new(pos + Vector3.new(0, h * 0.62, 1.4)), Color = rgb(BN.color), Material = Enum.Material.Fabric }, parent)
	part({ Name = "Trim", Size = Vector3.new(0.2, 0.3, 2.8), CFrame = CFrame.new(pos + Vector3.new(0, h * 0.62 - h * 0.275, 1.4)), Color = rgb(BN.trim), Material = Enum.Material.Metal }, parent)
	part({ Name = "Star", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.7, CFrame = CFrame.new(pos + Vector3.new(0, h * 0.68, 1.4)), Color = rgb(BN.trim), Material = Enum.Material.Neon }, parent)
end

-- the nest decor from rewards while the nest belongs to the owner: a lantern (calendar day 5) at the Decor1 support, the Season 1 banner at Decor2
local DECOR = {
	{ flag = "lantern", name = "RewardLantern", anchor = "Decor1" },
	{ flag = "seasonBanner", name = "RewardBanner", anchor = "Decor2" },
}
local function placeDecor(player: Player, data: any)
	local nest = services.Nest.of(player)
	if not nest or typeof(data.owned) ~= "table" then
		return
	end
	for _, dc in DECOR do
		if data.owned[dc.flag] and not nest:FindFirstChild(dc.name) then
			local a = nest:FindFirstChild(dc.anchor, true)
			if a and a:IsA("Attachment") then
				local m = Instance.new("Model")
				m.Name = dc.name
				m:SetAttribute("OwnerId", player.UserId)
				if dc.flag == "lantern" and services.WorldBuilder.lantern then
					services.WorldBuilder.lantern("GiftLantern", a.WorldPosition, m, 6)
				elseif dc.flag == "seasonBanner" then
					banner(a.WorldPosition, m)
				end
				m.Parent = nest
			end
		end
	end
end

-- one reward (a gift over time or a calendar day) -> the banner text and the coins for the flight
local function grant(player: Player, data: any, rw: any, txType: string, element: string?): (any, number) -- what was granted: a Loc.text template
	local coins = 0
	local what = ""
	if rw.minutes then
		coins = minutesCoins(data, rw.minutes)
		giveCoins(player, coins, txType)
		what = Loc.text(S.gotCoins, { n = coins })
	elseif rw.berries then
		local fed, c = giveBerries(player, data, rw.berries, txType)
		coins = c
		what = if fed > 0 then Loc.text(S.berriesFed, { n = fed }) else Loc.text(S.gotCoins, { n = c })
	elseif rw.rareNest then
		-- rare nest = the table of the next zone from the egg's zone (Eggs.rarityTable) - we pass the best open one
		local gave = giveEgg(player, Eggs.roll("gift90", Rewards.bestZone(maxStage(data)), true, r01, B, Config.Elements))
		what = if gave then Loc.text(S.rareNest) else coinsText()
	elseif rw.egg then
		local egg: any = Eggs.rollGuaranteed(txType .. "_" .. rw.egg, rw.egg, rw.minRarity or "Common", r01, B, Config.Elements)
		local gave = giveEgg(player, egg)
		what = if not gave then coinsText() elseif rw.minRarity == "Epic" then Loc.text(S.epicEgg) else Loc.text(S.egg, { zone = Loc.text(Strings.Zone[rw.egg] or rw.egg) })
	elseif rw.decor then
		local flag = if rw.decor == "Banner" then "seasonBanner" else "lantern"
		services.PlayerData.update(player, "owned", function(o)
			o = if typeof(o) == "table" then o else {}
			o[flag] = true
			return o
		end)
		placeDecor(player, data)
		what = Loc.text(if rw.decor == "Banner" then S.banner else S.lantern)
	elseif rw.preset then -- a color preset: a flag like a purchase (owned.presets[id]), the player puts it on in the dragon card
		services.PlayerData.update(player, "owned", function(o)
			o = if typeof(o) == "table" then o else {}
			o.presets = if typeof(o.presets) == "table" then o.presets else {}
			o.presets[rw.preset] = true
			return o
		end)
		if services.Looks and services.Looks.autoEquip then -- looks (07 add. 2.6): put it on a suitable dragon if free
			pcall(services.Looks.autoEquip, player, rw.preset)
		end
		what = Loc.text(S.solstice)
	elseif rw.hatchling and services.PlayerData.eggsAllowed and not services.PlayerData.eggsAllowed(data) then
		-- day 1 = one dragon - the day-7 hatchling / "tomorrow" in coins for now (returns as a glowing one, package 2)
		services.Nest.addCoins(player, (Config.Quests and Config.Quests.eggFallbackCoins) or 300, "Reward")
		what = coinsText()
	elseif rw.hatchling then
		-- a seasonal one (rw.name) is fixed: no shine or size, the name at once and without the name window
		local fixed = rw.name ~= nil
		local egg = { id = txType, element = rw.element or element or Config.Elements[1], rarity = rw.hatchling,
			shiny = if fixed then false else r01() < B.variants.shiny.p, size = if fixed then "normal" else Eggs.rollSize(r01, B),
			zone = "Meadow", rareNest = false, name = rw.name }
		if services.Incubation and services.Incubation.hatchGift then
			-- after the dragon is written into the profile an error must not roll back the claim mark (otherwise a second hatchling): catch here
			local ok, err = pcall(services.Incubation.hatchGift, player, egg)
			if not ok then
				warn("[Reward] hatchGift: " .. tostring(err))
			elseif typeof(err) == "table" and err.ok == false then
				-- a refusal BEFORE the dragon is written (no nest/profile) - error, so safeGrant rolls back the claim mark
				-- before, the path was only by the day-7 button, now also the auto-claim of the "tomorrow" chain (the day-2 dragon)
				error("hatchGift refused: " .. tostring(err.reason))
			end
		end
		what = Loc.text(if rw.name then S.solsticeDragon else S.rareDragon)
	end
	return what, coins
end

local function notice(player: Player, title: any, sub: any, coins: number, color: string?) -- strings or Loc.text templates
	services.Net.notice(player, { kind = "reward", title = title, sub = sub, coins = coins, color = color })
end

-- the gift chest at every nest (06 §3): a wooden chest with golden stripes; the timer above it and the touch (the Gifts tab) -
-- on the owner's client (Gifts), here only the model with the GiftChest tag
local function buildChest(nest: Model)
	local base = nest:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") or nest:FindFirstChild("GiftChest") then
		return
	end
	local C = R.chest
	local sx, sy, sz = C.size[1], C.size[2], C.size[3]
	local at = base.CFrame * CFrame.new(C.pos[1], base.Size.Y / 2, C.pos[3]) * CFrame.Angles(0, math.rad(C.yaw), 0)
	local m = Instance.new("Model")
	m.Name = "GiftChest"
	local box = part({ Name = "Box", Size = Vector3.new(sx, sy * 0.62, sz), CFrame = at * CFrame.new(0, sy * 0.31, 0), Color = Color3.fromRGB(120, 74, 40) }, m)
	box.CanCollide = true
	box.CanQuery = true
	part({ Name = "Lid", Size = Vector3.new(sx + 0.15, sy * 0.38, sz + 0.15), CFrame = at * CFrame.new(0, sy * 0.81, 0), Color = Color3.fromRGB(140, 88, 48) }, m)
	for _, x in { -sx * 0.32, sx * 0.32 } do
		part({ Name = "Band", Size = Vector3.new(0.25, sy + 0.05, sz + 0.2), CFrame = at * CFrame.new(x, sy * 0.5, 0), Color = Color3.fromRGB(230, 180, 60), Material = Enum.Material.Metal }, m)
	end
	part({ Name = "Lock", Size = Vector3.new(0.5, 0.6, 0.2), CFrame = at * CFrame.new(0, sy * 0.62, -sz / 2 - 0.1), Color = Color3.fromRGB(240, 200, 80), Material = Enum.Material.Metal }, m)
	m.PrimaryPart = box
	CollectionService:AddTag(m, "GiftChest")
	m.Parent = nest
end

-- ---------------------------------------------------------------------------------------------- dailies
local function dailyCheck(player: Player, data: any)
	ensure(data)
	if Rewards.dailyReset(data.quests.daily, if services.LiveOps then services.LiveOps.now() else os.time(), R) then -- 2.9: the LiveOps clock (shifted in Studio - a pool B check)
		services.PlayerData.replicate(player, { "quests" })
	end
end

-- ---------------------------------------------------------------------------------------------- weekly quests (add. 21.10)
-- the live ops clock (shifted in Studio by LiveOpsDebug - the week and the season closing together with the update)
local function liveNow(): number
	return if services.LiveOps then services.LiveOps.now() else os.time()
end

-- the current week set: (the set, the update number) or nil - off (W.on) or update 1 has not started yet
local function weeklySet(): (any, number)
	if not W.on then
		return nil, 0
	end
	return Rewards.weeklySet(Content.Updates, if services.LiveOps then services.LiveOps.live() else 0)
end

-- the event badge - a closed weekly quest in the first week of the update (Badges.award does not
-- call Roblox a second time by itself, an API failure - a retry no sooner than 60 s)
local function weeklyBadge(player: Player, w: any, upd: number)
	local key = Rewards.weeklyBadge(Content.Updates, upd, w.week, W.anchor)
	if key and services.Badges and next(w.done or {}) ~= nil then
		services.Badges.award(player, key)
	end
end

-- a new week - the quests from zero; the first visit of the week (not for a newcomer) - the toast "New weekly quests" (once a week)
local function weeklyCheck(player: Player, data: any)
	local set, upd = weeklySet()
	if not set then
		return
	end
	local w = data.quests.weekly
	if Rewards.weeklyReset(w, liveNow(), W.anchor, upd) then
		services.PlayerData.replicate(player, { "quests" })
	end
	weeklyBadge(player, w, upd)
	if w.seen ~= w.week and (data.sessions or 0) > 1 then -- a newcomer learns about them in the Quests tab, the first session without reminders
		w.seen = w.week
		task.delay(W.toastDelay, function()
			if player.Parent == Players then
				services.Nest.toast(player, Strings.Weekly.open)
			end
		end)
	end
end

-- the reward at once (points + an egg), the banner - by the caller (in a chain); returns the banner title and caption
local function weeklyGrant(player: Player, set: any, i: number, week: number): (any, any)
	local def = set.quests[i]
	local pts = 0
	if liveNow() < R.season.endsAt then -- 09 §5: after the track closes points no longer accumulate, the egg stays
		pts = W.points
		services.PlayerData.update(player, "rewards", function(r)
			r.season.points += pts
			return nil
		end)
	end
	local gaveWeekly = giveEgg(player, Eggs.roll("weekly", set.egg, false, r01, B, Config.Elements))
	local zone = Loc.text(Strings.Zone[set.egg] or set.egg)
	local sub = if pts > 0 then Loc.text(Strings.Weekly.gotBoth, { n = pts, zone = zone }) else Loc.text(S.egg, { zone = zone })
	if not gaveWeekly then
		sub = coinsText()
	end
	if services.Analytics then
		services.Analytics.custom(player, "weekly_done", i, { id = def.id, week = week })
	end
	return Loc.text(Strings.Weekly.done, { title = Loc.text((Strings.Weekly.titles :: any)[def.id] or def.id) }), sub
end

-- after - how many daily banners already stand in the chain (the weekly banner goes after them, not over)
local function weeklyEvent(player: Player, data: any, name: string, n: number, after: number)
	local set, upd = weeklySet()
	if not set then
		return
	end
	local w = data.quests.weekly
	if Rewards.weeklyReset(w, liveNow(), W.anchor, upd) then
		services.PlayerData.replicate(player, { "quests" })
	end
	if not Rewards.weeklyUses(w, name, set) then
		return
	end
	local closed: { number } = {}
	services.PlayerData.update(player, "quests", function(q)
		closed = Rewards.weeklyEvent(q.weekly, name, n, set)
		return nil
	end)
	if #closed > 0 then
		weeklyBadge(player, w, upd)
	end
	for k, i in closed do
		local title, sub = weeklyGrant(player, set, i, w.week)
		task.delay((after + k - 1) * Config.Quests.chainDelay, function()
			if player.Parent == Players then
				notice(player, title, sub, 0, "daily")
			end
		end)
	end
end

-- a day event: closed groups - the reward at once; returns how many banners were put into the chain
local function dailyEvent(player: Player, data: any, name: string, n: number?): number
	if not Rewards.uses(data.quests.daily, name, R) then
		return 0
	end
	local closed: { string }, bonus = {}, false
	services.PlayerData.update(player, "quests", function(q)
		closed, bonus = Rewards.dailyEvent(q.daily, name, n or 1, R)
		return nil
	end)
	if #closed == 0 then
		return 0
	end
	for i, tier in closed do
		local idx = table.find(Rewards.TIERS, tier) or 1
		local coins = minutesCoins(data, B.daily[idx])
		giveCoins(player, coins, "Daily")
		if os.time() < R.season.endsAt then -- season points only while the track is open (09 §5)
			services.PlayerData.update(player, "rewards", function(r)
				r.season.points += R.daily.points
				return nil
			end)
		end
		local _, _, def = Rewards.dailyProgress(data.quests.daily, idx, R)
		local title = if def then (Strings.Daily.titles :: any)[def.id] or def.id else tier
		task.delay((i - 1) * Config.Quests.chainDelay, function()
			if player.Parent == Players then
				notice(player, Loc.text(Strings.Daily.done, { title = Loc.text(title) }), Loc.text(S.gotCoins, { n = coins }), coins, "daily")
			end
		end)
		if services.Analytics then
			services.Analytics.custom(player, "daily_done", idx, { tier = tier })
		end
	end
	if bonus then
		giveEgg(player, Eggs.rollGuaranteed("dailyBonus", R.daily.bonusEgg, "Common", r01, B, Config.Elements))
		if os.time() < R.season.endsAt then
			services.PlayerData.update(player, "rewards", function(r)
				r.season.points += R.daily.points
				return nil
			end)
		end
		task.delay(#closed * Config.Quests.chainDelay, function()
			if player.Parent == Players then
				notice(player, Strings.Daily.allDone, nil, 0, "daily")
			end
		end)
		if services.Analytics then
			services.Analytics.custom(player, "daily_all_done", 1)
		end
	end
	return #closed + (if bonus then 1 else 0)
end

-- a day and week event (called by Quest.event and the services); the weekly banner - after the daily banners
function Reward.event(player: Player, name: string, n: number?)
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	dailyCheck(player, data)
	local shown = dailyEvent(player, data, name, n)
	weeklyEvent(player, data, name, n or 1, shown)
end

-- ---------------------------------------------------------------------------------------------- Claim
-- the grant after the "claimed" mark: a grant error rolls the mark back
local function safeGrant(player: Player, data: any, rw: any, txType: string, element: string?, undo: () -> ()): (boolean, any, number)
	local ok, what, coins = pcall(grant, player, data, rw, txType, element)
	if not ok then
		warn("[Reward] grant " .. txType .. ": " .. tostring(what))
		undo()
		return false, "", 0
	end
	return true, what, coins
end
local function claimTimeGift(player: Player, data: any, id: string): any
	local s = sessions[player]
	local min = tonumber(id)
	local g = min and Rewards.gift(TG.list, min)
	if not s or not g or not min then
		return { ok = false, reason = "bad_request" }
	end
	local claimed = data.rewards.timeGifts.claimed
	if claimed[tostring(min)] then
		return { ok = false, reason = "already" }
	end
	if s.sec < min * 60 then
		return { ok = false, reason = "not_ready" }
	end
	services.PlayerData.update(player, "rewards", function(rw)
		rw.timeGifts.claimed[tostring(min)] = true
		return nil
	end)
	local okG, what, coins = safeGrant(player, data, g, "TimeGift", nil, function()
		services.PlayerData.update(player, "rewards", function(rw)
			rw.timeGifts.claimed[tostring(min)] = nil
			return nil
		end)
	end)
	if not okG then
		return { ok = false, reason = "bad_request" }
	end
	notice(player, (S.gift :: any)[min] or Loc.text(S.timeGift, { n = min }), what, coins, "gift")
	if services.Analytics then
		services.Analytics.custom(player, "time_gift", min)
	end
	return { ok = true }
end

local function claimCalendar(player: Player, data: any, id: string?): any
	local cal = data.rewards.calendar
	if not Rewards.calendarPending(cal) then
		return { ok = false, reason = "already" }
	end
	local n = cal.claimed + 1
	local rw = Rewards.calendarRewardFor(n, R, player.UserId, Config.Elements) -- the day-2 experiment (an element dragon from the UserId)
	local element: string? = nil
	if rw.hatchling and not rw.element then -- the element choice - only for the day-7 Rare hatchling
		local options = Rewards.choices(n, Config.Elements, R.calendar.choices)
		if not id or not table.find(options, id) then
			return { ok = false, reason = "bad_request" }
		end
		element = id
	end
	services.PlayerData.update(player, "rewards", function(r)
		r.calendar.claimed = n
		return nil
	end)
	local okG, what, coins = safeGrant(player, data, rw, "Calendar", element, function()
		services.PlayerData.update(player, "rewards", function(r)
			r.calendar.claimed = n - 1
			return nil
		end)
	end)
	if not okG then
		return { ok = false, reason = "bad_request" }
	end
	local title = (S.day :: any)[n] or Loc.text(S.calendarDay, { n = n, what = what }) -- 8-13 and 15+ - "Day N: what"
	notice(player, title, what, coins, "calendar")
	-- a new day is already on while the previous day waited for the claim: the next day at once, without a rejoin
	services.PlayerData.update(player, "rewards", function(r)
		Rewards.calendarAdvance(r.calendar, os.time())
		return nil
	end)
	if services.Analytics then
		services.Analytics.custom(player, "calendar_day", n)
	end
	return { ok = true }
end

local function inGroup(player: Player, groupId: number): boolean
	local ok, res = pcall(function()
		return (player :: any):IsInGroupAsync(groupId)
	end)
	if ok then
		return res == true
	end
	local ok2, res2 = pcall(function()
		return player:IsInGroup(groupId)
	end)
	return ok2 and res2 == true
end

local function claimFreeGift(player: Player, data: any): any
	local F = R.freeGift
	if F.groupId == 0 then
		return { ok = false, reason = "locked" }
	end
	if data.rewards.freeGift.group or checking[player] then
		return { ok = false, reason = "already" }
	end
	checking[player] = true -- IsInGroupAsync yields the thread: a second Claim meanwhile must not grant a second egg
	local member = inGroup(player, F.groupId)
	checking[player] = nil
	if player.Parent ~= Players then
		return { ok = false, reason = "loading" }
	end
	if not member then
		services.Nest.toast(player, S.notJoined)
		return { ok = false, reason = "not_ready" }
	end
	services.PlayerData.update(player, "rewards", function(r)
		r.freeGift.group = true
		return nil
	end)
	local gaveGift = giveEgg(player, Eggs.rollGuaranteed("freeGift", F.zone, F.minRarity, r01, B, Config.Elements, F.element))
	notice(player, S.welcomeTitle, if gaveGift then S.joined else coinsText(), 0, "gift")
	if services.Analytics then
		services.Analytics.custom(player, "group_joined", 1)
	end
	if Config.Combat and Config.Combat.autoForGroup then
		player:SetAttribute("AutoBreath", true) -- IsInGroup is cached per session - AUTO at once, without a rejoin
	end
	return { ok = true }
end

local function claimSeason(player: Player, data: any, id: string?): any
	local step = tonumber(id or "")
	local SE = R.season
	local rw = step and SE.rewards[step]
	if not step or not rw then
		return { ok = false, reason = "bad_request" }
	end
	local se = data.rewards.season
	if os.time() >= SE.endsAt then -- 09 §5: after the track closes the steps are not granted
		return { ok = false, reason = "locked" }
	end
	if se.claimed[tostring(step)] then
		return { ok = false, reason = "already" }
	end
	if se.points < SE.steps[step] then
		return { ok = false, reason = "not_ready" }
	end
	services.PlayerData.update(player, "rewards", function(r)
		r.season.claimed[tostring(step)] = true
		return nil
	end)
	local okG, what, coins = safeGrant(player, data, rw, "Season", nil, function()
		services.PlayerData.update(player, "rewards", function(r)
			r.season.claimed[tostring(step)] = nil
			return nil
		end)
	end)
	if not okG then
		return { ok = false, reason = "bad_request" }
	end
	notice(player, Loc.text(S.seasonDone, { n = step }), what, coins, "season")
	if services.Analytics then
		services.Analytics.custom(player, "season_step", step)
	end
	return { ok = true }
end

function Reward.claim(player: Player, kind: string, id: string?): any
	local data = services.PlayerData.get(player)
	if not data or not services.Nest.of(player) then
		return { ok = false, reason = "loading" }
	end
	ensure(data)
	if kind == "timeGift" then
		return claimTimeGift(player, data, tostring(id or ""))
	elseif kind == "calendar" then
		return claimCalendar(player, data, id)
	elseif kind == "freeGift" then
		return claimFreeGift(player, data)
	elseif kind == "season" then
		return claimSeason(player, data, id)
	end
	return { ok = false, reason = "bad_request" } -- the dailies are granted by themselves
end

-- there was input in the last afkSeconds (Weather: the Storm dragon reward is not for AFK)
function Reward.isActive(player: Player): boolean
	local s = sessions[player]
	return s ~= nil and os.clock() - s.active <= TG.afkSeconds
end

-- ---------------------------------------------------------------------------------------------- the session and the tick
local function onLoaded(player: Player, _copy: any)
	-- Loaded is a BindableEvent: the argument table arrives as a COPY of the profile, edits in it are lost - work with the live profile
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	ensure(data)
	sessions[player] = { sec = 0, active = os.clock(), lastPos = nil, play = 0, visited = {}, freeShown = false, dailyShown = false, activeAt = 0 }
	player:SetAttribute("GiftSec", 0)
	services.PlayerData.update(player, "rewards", function(rw) -- gifts over time - per session (06 §3)
		rw.timeGifts.claimed = {}
		return nil
	end)
	dailyCheck(player, data)
	weeklyCheck(player, data)
	local cal = data.rewards.calendar
	if Rewards.calendarAdvance(cal, os.time()) then
		services.PlayerData.replicate(player, { "rewards" })
	end
	-- the "open Gifts" toast is removed - a returning player's day is shown by the Gifts chain (auto-claim or "waiting in Gifts")
end

local function nestBox(i: number): { cf: CFrame, size: Vector3 }?
	local b = nestBoxes[i]
	if b then
		return b
	end
	local nest = services.WorldBuilder.getNest(i)
	if not nest then
		return nil
	end
	local base = nest:FindFirstChild("Base") -- the lotWidth x lotDepth petal pad at the nest center
	if not base or not base:IsA("BasePart") then
		return nil
	end
	b = { cf = base.CFrame, size = base.Size }
	nestBoxes[i] = b
	return b
end

local function visitCheck(player: Player, s: Session, pos: Vector3)
	for i = 1, Config.World.nests.count do
		local owner = services.Nest.ownerOf(i)
		if owner and owner ~= player and not s.visited[owner.UserId] then
			local b = nestBox(i)
			if b then
				local lp = b.cf:PointToObjectSpace(pos)
				if math.abs(lp.X) <= b.size.X / 2 and math.abs(lp.Z) <= b.size.Z / 2 then
					s.visited[owner.UserId] = true
					Reward.event(player, "visit")
				end
			end
		end
	end
end

local tickN = 0
local function tick()
	tickN += 1
	local now = os.clock()
	for player, s in sessions do
		local data = services.PlayerData.get(player)
		if not data or player.Parent ~= Players then
			continue
		end
		local pos = services.Nest.rootPos(player)
		if pos then
			if s.lastPos and (pos - s.lastPos).Magnitude >= TG.moveStuds then
				s.active = now
			end
			s.lastPos = pos
		end
		if now - s.active <= TG.afkSeconds then
			s.sec += 1
			s.play += 1
			player:SetAttribute("GiftSec", s.sec)
		end
		player:SetAttribute("GiftAfk", now - s.active > TG.afkSeconds)
		if s.play >= 30 then -- "Play 10 minutes": the day counter in batches (fewer replications)
			local n = s.play
			s.play = 0
			Reward.event(player, "playSec", n)
		end
		if pos and tickN % R.daily.visitEvery == 0 then
			visitCheck(player, s, pos)
		end
		if tickN % 10 == 0 then
			dailyCheck(player, data) -- 00:00 UTC during play
			weeklyCheck(player, data) -- Sun 19:00 UTC during play (and update 1 switching on)
			placeDecor(player, data)
		end
		local first = (data.sessions or 0) <= 1
		if first and not s.dailyShown and s.sec >= R.daily.showAfter then -- 02 §3 8:00
			s.dailyShown = true
			services.Nest.toast(player, Strings.Daily.open)
			if services.Analytics then
				services.Analytics.custom(player, "daily_panel_shown", 1)
			end
		end
		local F = R.freeGift
		if first and F.groupId ~= 0 and not s.freeShown and s.sec >= F.showAt and not data.rewards.freeGift.group then -- 02 §3 2:45
			s.freeShown = true
			services.Net.notice(player, { kind = "freeGift" })
			if services.Analytics then
				services.Analytics.custom(player, "free_gift_shown", 1)
			end
		end
	end
	-- reward decor from a foreign profile in a freed nest
	for i = 1, Config.World.nests.count do
		local nest = services.WorldBuilder.getNest(i)
		if nest then
			local owner = services.Nest.ownerOf(i)
			for _, dc in DECOR do
				local l = nest:FindFirstChild(dc.name)
				if l and (not owner or owner.UserId ~= l:GetAttribute("OwnerId")) then
					l:Destroy()
				end
			end
		end
	end
end

-- Studio only (LoopDebug "reward ..."): the state; "reward time 600" - session seconds; "reward day" - the next calendar day
-- "reward daily <event> [n]" - a day event; "reward weekly <event> [n]" / "reward weekly reset" - weekly quests;
-- "reward reset" - the dailies and the calendar anew
function Reward.debug(player: Player, arg: string): any
	local data = services.PlayerData.get(player)
	local s = sessions[player]
	if not data or not s then
		return { ok = false, reason = "loading" }
	end
	ensure(data)
	local verb, rest = string.match(arg, "^(%a*)%s*(.*)$")
	if verb == "time" then
		s.sec = tonumber(rest) or s.sec
		player:SetAttribute("GiftSec", s.sec)
	elseif verb == "day" then
		services.PlayerData.update(player, "rewards", function(r)
			r.calendar.lastDate = ""
			if r.calendar.claimed >= r.calendar.day then
				Rewards.calendarAdvance(r.calendar, os.time())
			end
			return nil
		end)
	elseif verb == "daily" then
		local ev, n = string.match(rest or "", "^(%S+)%s*(%d*)$")
		if ev then
			Reward.event(player, ev, tonumber(n) or 1)
		end
	elseif verb == "weekly" then -- "reward weekly <event> [n]" - a week event; "reward weekly reset" - the week anew
		local ev, n = string.match(rest or "", "^(%S+)%s*(%d*)$")
		if ev == "reset" then
			data.quests.weekly.week = -1
			data.quests.weekly.seen = nil
			weeklyCheck(player, data)
		elseif ev then
			weeklyEvent(player, data, ev, tonumber(n) or 1, 0)
		end
	elseif verb == "points" then
		services.PlayerData.update(player, "rewards", function(r)
			r.season.points = tonumber(rest) or r.season.points
			return nil
		end)
	elseif verb == "reset" then
		services.PlayerData.update(player, "quests", function(q)
			q.daily.date = ""
			return nil
		end)
		services.PlayerData.update(player, "rewards", function(r)
			r.calendar = { day = 0, lastDate = "", claimed = 0 }
			r.timeGifts.claimed = {}
			return nil
		end)
		dailyCheck(player, data)
		Rewards.calendarAdvance(data.rewards.calendar, os.time())
		services.PlayerData.replicate(player, { "rewards" })
	end
	local dl = data.quests.daily
	local parts = {}
	for i = 1, 3 do
		local k, n, d = Rewards.dailyProgress(dl, i, R)
		table.insert(parts, string.format("%s %d/%d%s", d and d.id or "-", k, n, if dl.done[Rewards.TIERS[i]] then "✓" else ""))
	end
	local cl = {}
	for k in data.rewards.timeGifts.claimed do
		table.insert(cl, k)
	end
	table.sort(cl)
	local cal = data.rewards.calendar
	local wk = "off"
	local wset, wupd = weeklySet()
	if wset then
		local wl = data.quests.weekly
		local wp = {}
		for i in wset.quests do
			local k, n, d = Rewards.weeklyProgress(wl, i, wset)
			table.insert(wp, string.format("%s %d/%d%s", d and d.id or "-", k, n, if wl.done[tostring(i)] then "✓" else ""))
		end
		wk = string.format("u%d w%d [%s] left=%d", wupd, wl.week, table.concat(wp, ", "), Rewards.weekLeft(liveNow(), W.anchor))
	end
	return { ok = true, reason = string.format("daily %s [%s] bonus=%s | weekly %s | gifts sec=%d claimed=%s | calendar day=%d claimed=%d | season=%d shelf=%d coins=%d",
		dl.date, table.concat(parts, ", "), tostring(dl.bonus), wk, s.sec, table.concat(cl, ","), cal.day, cal.claimed, data.rewards.season.points,
		#data.eggs.shelf, math.floor(data.coins or 0)) }
end

function Reward.init(s: { [string]: any })
	services = s
end

function Reward.start()
	services.PlayerData.Loaded:Connect(function(player: Player, data: any)
		local ok, err = pcall(onLoaded, player, data)
		if not ok then
			warn("[Reward] load: " .. tostring(err))
		end
	end)
	for _, p in Players:GetPlayers() do
		local d = services.PlayerData.get(p)
		if d and not sessions[p] then
			local ok, err = pcall(onLoaded, p, d)
			if not ok then
				warn("[Reward] load: " .. tostring(err))
			end
		end
	end
	Players.PlayerRemoving:Connect(function(p)
		local s = sessions[p]
		if s and services.Analytics then -- 06 §3: at which gift minute they leave (the length of a visit without AFK)
			services.Analytics.custom(p, "gift_minutes", math.floor(s.sec / 60))
		end
		sessions[p] = nil
		checking[p] = nil
	end)
	-- "there was input" from the client (buttons, touches, keys): no more often than activeEvery s, no arguments
	local folder = ReplicatedStorage:WaitForChild(Remotes.Folder, 30)
	local r = folder and folder:FindFirstChild("Active")
	if r and r:IsA("RemoteEvent") then
		r.OnServerEvent:Connect(function(player: Player)
			local s = sessions[player]
			local now = os.clock()
			if s and now - s.activeAt >= TG.activeEvery * 0.5 then
				s.activeAt = now
				s.active = now
			end
		end)
	end
	task.spawn(function() -- the chests: the nests are built by WorldBuilder.start (~6-8 s), the starts run in parallel
		while #services.WorldBuilder.nests < Config.World.nests.count do
			task.wait(0.5)
		end
		for i = 1, Config.World.nests.count do
			local nest = services.WorldBuilder.getNest(i)
			if nest then
				local ok, err = pcall(buildChest, nest)
				if not ok then
					warn("[Reward] chest: " .. tostring(err))
				end
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Reward] tick: " .. tostring(err))
			end
		end
	end)
end

return Reward
