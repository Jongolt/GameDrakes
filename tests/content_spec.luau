--!strict
-- 2.9: the specification of the content and live operations (spec 09 §2-3). Run from the repository root:
-- luau tests/content_spec.luau
-- Checks: the updates by date (Sun 19:00 UTC, in order, after D0), the variants (the element, the condition, the multiplier in the balance, the mesh ids
-- or 0), the codes of the week, errands 16-20 (open only with update 1), the daily pool B (from the day after update 1), Aurora in
-- the weather (30% from update 1), the zone odds sums = 100, the stop words in the English texts.
local Config = require("../src/shared/Config")
local Content = require("../src/shared/Content")
local Strings = require("../src/shared/Strings")
local LiveOps = require("../src/shared/Core/LiveOps")
local Quests = require("../src/shared/Core/Quests")
local Rewards = require("../src/shared/Core/Rewards")
local Weather = require("../src/shared/Core/Weather")
local Economy = require("../src/shared/Core/Economy")

local B = Config.Balance
local R = Config.Rewards
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

local U = Content.Updates
local D0 = 1792713600 -- 2026-10-23 00:00 UTC (Config.Analytics.d0 in UTC)

-- the updates: 4 of them, Sun 19:00 UTC, a week apart, after D0, each has an event text
check("updates: four", #U == 4, #U)
for i, u in U do
	local d = os.date("!*t", u.activeFrom) :: any
	check("update " .. i .. ": Sunday 19:00 UTC", d.wday == 1 and d.hour == 19 and d.min == 0 and d.sec == 0, os.date("!%c", u.activeFrom))
	check("update " .. i .. ": after D0", u.activeFrom > D0)
	check("update " .. i .. ": the event text and the name", typeof(u.eventText) == "string" and #u.eventText > 10 and typeof(u.title) == "string")
	if i > 1 then
		check("update " .. i .. ": 7 days after the previous one", u.activeFrom - U[i - 1].activeFrom == 7 * 86400)
	end
end
check("update 1 - Aurora 08.11", U[1].id == "aurora" and os.date("!%Y-%m-%d", U[1].activeFrom) == "2026-11-08")
check("update 1: the pool B day - the day after", U[1].dailyFrom == os.date("!%Y-%m-%d", U[1].activeFrom + 86400))

-- live by dates
check("live: D0 - 0", LiveOps.live(U, D0) == 0)
check("live: a second before Aurora - 0", LiveOps.live(U, U[1].activeFrom - 1) == 0)
check("live: Aurora - 1", LiveOps.live(U, U[1].activeFrom) == 1)
check("live: after Nightfall - 4", LiveOps.live(U, U[4].activeFrom + 86400) == 4)

-- the variants: the element exists, the update exists, the multiplier in the balance, 4 mesh ids (0 - none yet)
for id, v in Content.Variants :: { [string]: any } do
	check("variant " .. id .. ": the element", Content.Elements[v.element] ~= nil, v.element)
	check("variant " .. id .. ": the update", U[v.update] ~= nil and table.find(U[v.update].variants or {}, id) ~= nil)
	check("variant " .. id .. ": the multiplier in Balance.variants", B.variants[id] ~= nil and (B.variants[id].mult or 0) > 1)
	check("variant " .. id .. ": the zone and the weather of the condition", (v.condition.zone == nil or B.zones[v.condition.zone] ~= nil) and (v.condition.weather == nil or v.condition.weather == "aurora" or v.condition.weather == "storm" or v.condition.weather == "starfall"))
	local okIds = #v.stages == 4
	for _, a in v.stages do
		okIds = okIds and typeof(a) == "number" and a >= 0
	end
	check("variant " .. id .. ": 4 mesh ids (0 - none)", okIds)
	if v.update == 1 then -- a variant of the first update must have its own meshes by D0 (3 weeks before 08.11 - without "later")
		local all = true
		for _, x in v.stages do
			all = all and x > 0
		end
		check("variant " .. id .. ": the meshes of all 4 stages are uploaded", all)
	end
end
local frostSummit = { element = "frost", zone = "Summit" }
check("Glacier: Frost from Summit in Aurora at update 1", LiveOps.variantFor(Content.Variants, frostSummit, "aurora", 1) == "glacier")
check("Glacier: before the update - no", LiveOps.variantFor(Content.Variants, frostSummit, "aurora", 0) == nil)
check("Glacier: not Aurora - no", LiveOps.variantFor(Content.Variants, frostSummit, "storm", 1) == nil and LiveOps.variantFor(Content.Variants, frostSummit, "", 1) == nil)
check("Glacier: Frost from Cliffs - no", LiveOps.variantFor(Content.Variants, { element = "frost", zone = "Cliffs" }, "aurora", 1) == nil)
check("Glacier: Ember from Summit - no", LiveOps.variantFor(Content.Variants, { element = "ember", zone = "Summit" }, "aurora", 1) == nil)
check("Pearl: only from update 3", LiveOps.variantFor(Content.Variants, { element = "tide", zone = "Springs" }, "starfall", 2) == nil
	and LiveOps.variantFor(Content.Variants, { element = "tide", zone = "Springs" }, "starfall", 3) == "pearl")
local d = { rarity = "Rare", stage = 2 }
local g = { rarity = "Rare", stage = 2, variant = "glacier" }
check("Glacier: income x1.5", math.abs(Economy.dragonIncome(g :: any, B) / Economy.dragonIncome(d :: any, B) - 1.5) < 1e-9)

-- the codes of the week
for name, c in Content.Codes :: { [string]: any } do
	check("code " .. name .. ": uppercase without spaces", LiveOps.normCode(name) == name and #name <= Config.LiveOps.codeMax)
	check("code " .. name .. ": the reward", c.minutes > 0)
	if c.update then
		check("code " .. name .. ": the update and the window", U[c.update] ~= nil and c.from == nil and c.days >= 1)
		check("code " .. name .. ": listed in the update", U[c.update].code == name)
	else -- the page code and the goal codes - their own start date, the term is optional
		check("code " .. name .. ": the start date", typeof(c.from) == "number" and c.from > 1790000000 and (c.days == nil or c.days >= 1))
	end
end
-- a code without an update - with from, without days perpetual; the goal step in Config is among the codes
local CF = { PAGE = { from = 1000, days = 2, minutes = 5 }, GOAL = { from = 1000, minutes = 5 } }
check("page code: before from - bad_code", select(2, LiveOps.codeCheck(CF :: any, U, "PAGE", 999, {})) == "bad_code")
check("page code: within the window - works", (LiveOps.codeCheck(CF :: any, U, "PAGE", 1000, {})) ~= nil)
check("page code: after days - expired", select(2, LiveOps.codeCheck(CF :: any, U, "PAGE", 1000 + 2 * 86400, {})) == "expired")
check("goal code: without a term - works even a year later", (LiveOps.codeCheck(CF :: any, U, "GOAL", 1000 + 365 * 86400, {})) ~= nil)
check("goal code: the second time - already", select(2, LiveOps.codeCheck(CF :: any, U, "GOAL", 2000, { GOAL = 1 })) == "already")
check("code: update without such an update - bad_code", select(2, LiveOps.codeCheck({ X = { update = 99, days = 1, minutes = 1 } } :: any, U, "X", 2e9, {})) == "bad_code")
check("like goal: the step code exists", (Content.Codes :: any)[tostring(Config.LiveOps.likeGoal) .. "LIKES"] ~= nil)
local A0 = U[1].activeFrom
check("code: before the update - does not work", select(2, LiveOps.codeCheck(Content.Codes, U, "AURORA", A0 - 60, {})) == "bad_code")
check("code: within the window - works", (LiveOps.codeCheck(Content.Codes, U, "AURORA", A0 + 3600, {})) ~= nil)
check("code: the case and spaces", LiveOps.normCode(" aur ora ") == "AURORA")
check("code: the second time - already", select(2, LiveOps.codeCheck(Content.Codes, U, "AURORA", A0 + 3600, { AURORA = 1 })) == "already")
check("code: 7 days later - expired", select(2, LiveOps.codeCheck(Content.Codes, U, "AURORA", A0 + 7 * 86400, {})) == "expired")
check("code: a foreign one - bad_code", select(2, LiveOps.codeCheck(Content.Codes, U, "FREE", A0 + 3600, {})) == "bad_code")

-- errands 16-20
check("errands: 15 at D0, 20 with Aurora", Quests.total(0) == 15 and Quests.total(1) == 20 and Quests.Total == 15)
check("errands: the 16th is closed before the update", Quests.get(16, 0) == nil and Quests.get(16, 1) ~= nil and Quests.get(15, 0) ~= nil)
local st: any = { keeper = { step = 16 }, counters = { scroll1 = 0 } }
local _, _, q0 = Quests.progress(st, 0)
local _, _, q1 = Quests.progress(st, 1)
check("errands: at the 16th before the update - 'all done', after - Lost notes", q0 == nil and q1 ~= nil and (q1 :: any).title == "Lost notes")
check("errands: 15 notes and 15 scroll spots (17.10: chapters 2 and 4)", #Content.Notes == 15 and #Config.LiveOps.scrolls.points == 15)
-- errands 21-35 by update, scrolls 6-10 and 11-15, the fresh count of chapter 3
do
	local ups = { [21] = 2, [26] = 3, [31] = 4 }
	for id = 21, 35 do
		local q = Quests.List[id]
		local want = if id <= 25 then 2 elseif id <= 30 then 3 else 4
		check("errand " .. id .. ": exists, update " .. want, q ~= nil and q.id == id and q.update == want, q and q.update)
	end
	for n = 6, 15 do
		local found = nil
		for _, q in Quests.List do
			if q.event == "scroll" .. n then
				found = q
			end
		end
		local sp = Config.LiveOps.scrolls.points[n]
		check("scroll " .. n .. ": its own errand and a spot of the same update", found ~= nil and sp ~= nil and (sp.update or 1) == found.update, found and found.id)
	end
	check("before update 2 errands 16-20: 20; with update 4: 35", Quests.total(1) == 20 and Quests.total(4) == 35)
	local st2: any = { keeper = { step = 28 }, counters = { shard = 40 } }
	Quests.markBase(st2, 3)
	local q28 = Quests.List[28]
	check("fresh: the old 40 shards do not count toward 'A bigger storm'", not Quests.ready(st2, q28) and Quests.count(st2, q28) == 0)
	st2.counters.shard = 56
	check("fresh: +16 after receiving - ready", Quests.ready(st2, q28))
	Quests.markBase(st2, 3)
	check("fresh: a repeated markBase does not shift the base", st2.keeper.base["28"] == 40)
	local st3: any = { keeper = { step = 28 }, counters = { shard = 40 } }
	Quests.markBase(st3, 2)
	check("fresh: before update 3 there is no base (the errand is closed)", st3.keeper.base == nil)
	for _, u in Content.Updates do
		for _, qid in u.quests or {} do
			check("Updates." .. u.id .. ": errand " .. qid .. " of the same update", Quests.List[qid] ~= nil and Content.Updates[Quests.List[qid].update] == u)
		end
	end
	local _ = ups
end
for i = 16, 20 do
	local q = Quests.List[i]
	check("errand " .. i .. ": the event scroll" .. (i - 15) .. ", update 1", q.event == "scroll" .. (i - 15) and q.update == 1 and q.count == 1)
	check("errand " .. i .. ": the text up to 70 characters", #q.text <= 70, #q.text)
end
check("errand 20: the finale - a Cliffs egg", Quests.List[20].reward.egg == "Cliffs")
for i, q in Quests.List do
	check("errand " .. i .. ": the number in order", q.id == i)
end

-- the daily pool B: from the day after Aurora, all tasks have a text
local dayB = math.floor((A0 + 86400) / 86400)
local function hasB(day: number): boolean
	for _, tier in Rewards.TIERS do
		for _, x in Rewards.pool(R, tier, day) do
			if x.from then
				return true
			end
		end
	end
	return false
end
check("pool B: on the Aurora day not yet", not hasB(dayB - 1))
check("pool B: on the next day yes", hasB(dayB))
for _, tier in Rewards.TIERS do
	for _, x in R.daily.pool[tier] do
		check("daily " .. x.id .. ": the text", typeof((Strings.Daily.titles :: any)[x.id]) == "string")
		check("daily " .. x.id .. ": the pool B date = Updates[1].dailyFrom", x.from == nil or x.from == U[1].dailyFrom)
	end
end
local seen: { [string]: boolean } = {}
for day = dayB, dayB + 200 do
	for _, id in Rewards.dailyPicks(day, R) do
		seen[id] = true
	end
end
check("pool B: the B tasks come up", seen.eggs5 == true and seen.weatherHatch == true and seen.rings15 == true)

-- the weather: Aurora 30% from update 1, before - none
local W = B.weather
local n = { storm = 0, starfall = 0, aurora = 0 }
for i = 0, 9999 do
	local k = Weather.pick(W, (i + 0.5) / 10000, 1)
	n[k] += 1
end
check("weather: Aurora 30% from update 1", n.aurora == 3000, n.aurora)
check("weather: the storm 42%, the starfall 28%", n.storm == 4200 and n.starfall == 2800, n.storm .. "/" .. n.starfall)
local any0 = false
for i = 0, 999 do
	if Weather.pick(W, (i + 0.5) / 1000, 0) == "aurora" then
		any0 = true
	end
end
check("weather: before the update there is no Aurora", not any0)
check("weather: the Aurora strings", typeof(Strings.Weather.aurora) == "string" and typeof(Strings.Weather.timerAurora) == "string")

-- the zone odds = 100
for zone, list in B.zones :: { [string]: { number } } do
	local sum = 0
	for _, p in list do
		sum += p
	end
	check("odds of zone " .. zone .. " = 100", math.abs(sum - 100) < 1e-6, sum)
end

-- the stop words in the English texts of the updates, notes and errands (12 compliance: no "free robux", links, calls to action)
local STOP = { "robux", "free", "http", "www", "discord", "giveaway", "subscribe", "—" }
local texts: { string } = {}
for _, u in U do
	table.insert(texts, u.eventText)
end
for _, s in Content.Notes do
	table.insert(texts, s)
end
for i = 16, 20 do
	table.insert(texts, Quests.List[i].title)
	table.insert(texts, Quests.List[i].text)
end
for _, s in Strings.LiveOps do
	table.insert(texts, s)
end
for _, s in texts do
	local low = string.lower(s)
	for _, w in STOP do
		check("stop word '" .. w .. "' absent: " .. string.sub(s, 1, 30), string.find(low, w, 1, true) == nil)
	end
end

-- the pressure stop list (Strings.Shop.banned) and external links - in ALL strings of Strings, Content
-- the errands; "Free Gift" is allowed (the group reward, without Robux), so "free" is not searched here
do
	local BAN = table.clone(Strings.Shop.banned)
	for _, w in { "http", "www.", "discord", ".com", "parents", "—" } do
		table.insert(BAN, w)
	end
	local seen, n = {}, 0
	local function walk(t: any, path: string)
		if typeof(t) == "string" then
			n += 1
			local low = string.lower(t)
			for _, w in BAN do
				if string.find(low, w, 1, true) then
					check("stop word '" .. w .. "' in " .. path, false, string.sub(t, 1, 60))
				end
			end
		elseif typeof(t) == "table" and not seen[t] then
			seen[t] = true
			for k, v in t do
				if k ~= "banned" then
					walk(v, path .. "." .. tostring(k))
				end
			end
		end
	end
	walk(Strings, "Strings")
	walk(Content.Notes, "Notes")
	walk(Content.Updates, "Updates")
	walk(Content.Badges, "Badges")
	for _, q in Quests.List do
		walk(q.title, "Quest" .. q.id)
		walk(q.text, "Quest" .. q.id)
	end
	check("stop list: strings checked > 500", n > 500, n)
end

-- the tasks of the week - every update has 2 tasks, the event is one of those the services send (and becomes
-- possible not later than its update), the egg zone, the text, the reward
do
	local plain = { shard = true, hatch = true, feed = true, eggFound = true, grow = true, ring = true, flySec = true, playSec = true, party = true, visit = true }
	local weatherFrom = { storm = 0, starfall = 0, aurora = B.weather.aurora.update }
	local phases: { [string]: boolean } = {}
	for _, ph in Config.World.dayCycle.phases do
		phases[ph.id] = true
	end
	local function known(ev: string, n: number): (boolean, string?)
		if plain[ev] then
			return true
		end
		local kind, arg = string.match(ev, "^(%a+)_(%a+)$")
		if kind == "hatchEl" or kind == "growEl" then
			return table.find(Config.Elements, arg) ~= nil
		elseif kind == "hatchSky" then
			return weatherFrom[arg :: string] ~= nil and weatherFrom[arg :: string] <= n, "the weather earlier than its update"
		elseif kind == "hatchAt" then
			return phases[arg :: string] == true
		elseif kind == "variant" then
			local v = Content.Variants[arg :: string]
			return v ~= nil and (v.update or 0) <= n, "the variant earlier than its update"
		end
		return false
	end
	local ids: { [string]: boolean } = {}
	for n, u in U do
		local wk = u.weekly
		check("week " .. n .. ": two tasks and the egg zone", typeof(wk) == "table" and #wk.quests == 2 and Strings.Zone[wk.egg] ~= nil, wk and wk.egg)
		for _, q in (wk and wk.quests or {}) do
			local ok, why = known(q.event, n)
			check("week " .. n .. " " .. q.id .. ": the event " .. q.event, ok, why)
			check("week " .. n .. " " .. q.id .. ": the count and the text", q.count >= 1 and typeof((Strings.Weekly.titles :: any)[q.id]) == "string")
			check("week " .. n .. " " .. q.id .. ": the id once", not ids[q.id])
			ids[q.id] = true
		end
	end
	for id in Strings.Weekly.titles :: any do
		check("week: the text " .. id .. " has a task", ids[id] == true)
	end
	check("week: the reward 5 points, the switch exists", R.weekly.points == 5 and typeof(R.weekly.on) == "boolean")
	-- every update has the badge "<Title> 2026" in Content.Badges, the keys differ
	local bkeys: { [string]: boolean } = {}
	for n, u in U do
		local b = u.badge and (Content.Badges :: any)[u.badge]
		check("badge " .. n .. ": exists, named '" .. u.title .. " 2026', created (id > 0)", b ~= nil and b.name == u.title .. " 2026" and typeof(b.id) == "number" and b.id > 0, u.badge)
		check("badge " .. n .. ": the key once", u.badge ~= nil and not bkeys[u.badge])
		bkeys[u.badge or ""] = true
	end
	check("badge: the strings with {badge}", string.find(Strings.Weekly.badge, "{badge}", 1, true) ~= nil and string.find(Strings.Weekly.badgeDone, "{badge}", 1, true) ~= nil)
end

-- Update Party only before a real update
do
	local LO = Config.LiveOps
	check("party: Sun 08.11 18:45 (Aurora) - 15 min", LiveOps.partyLeft(U, U[1].activeFrom - 900, LO) == 900)
	check("party: Sun 08.11 19:00 - no longer", LiveOps.partyLeft(U, U[1].activeFrom, LO) == 0)
	check("party: Sun 01.11 18:45 without an update - no", LiveOps.partyLeft(U, U[1].activeFrom - 7 * 86400 - 900, LO) == 0)
	check("party: Sun 06.12 18:45 (no updates after Nightfall) - no", LiveOps.partyLeft(U, U[4].activeFrom + 7 * 86400 - 900, LO) == 0)
	check("party: Sat 07.11 18:45 - no", LiveOps.partyLeft(U, U[1].activeFrom - 86400 - 900, LO) == 0)
	check("party: D0 = 23.10 (Friday)", os.date("!%Y-%m-%d %w", Config.Analytics.d0) == "2026-10-23 5", os.date("!%Y-%m-%d %w", Config.Analytics.d0))
end

print(string.format("content and live operations: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed tests")
end
