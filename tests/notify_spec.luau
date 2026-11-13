--!strict
-- the "calendar day is ready" notification - the queue entry, the time, the captions. Run from the repository root:
-- luau tests/notify_spec.luau
local Config = require("../src/shared/Config")
local Notify = require("../src/shared/Core/Notify")
local Rewards = require("../src/shared/Core/Rewards")

local N, R = Config.Notify, Config.Rewards
local passed, failed = 0, 0
local function check(name: string, cond: boolean)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name)
	end
end

local DAY = 86400
local base = 1792972800 -- the base time (UTC)
check("Config: on, store, afterHours", N.on == true and N.store == "NotifyQueue_v1" and N.afterHours >= 12 and N.afterHours <= 23)
check("Config: the banner timings", R.tomorrowBanner.afterSeconds <= 180 and R.tomorrowBanner.minSession < R.tomorrowBanner.afterSeconds)

-- the time: after midnight UTC and not earlier than afterHours
local left = base + 2 * 3600 -- left at 02:00 UTC (the US evening)
local due = Notify.due(left, 20)
check("02:00 (the US evening) -> midnight UTC + 5 min (19:05 in New York)", due == base + DAY + 300)
check("not earlier than the next midnight", due >= base + DAY)
local late = base + 23 * 3600 + 30 * 60 -- 23:30 UTC
check("23:30 -> 20 h later (the next day)", Notify.due(late, 20) == late + 20 * 3600)
local day = base + 14 * 3600 -- 14:00 UTC
check("14:00 -> 20 h later", Notify.due(day, 20) == day + 20 * 3600)
local early = base + 30 * 60 -- 00:30 UTC: midnight in 23.5 h
check("00:30 -> the next midnight + 5 min", Notify.due(early, 20) == base + DAY + 300)
for h = 0, 23 do
	local l = base + h * 3600 + 17
	local d = Notify.due(l, N.afterHours)
	check("hour " .. h .. ": within (midnight, +24 h]", d > (l // DAY + 1) * DAY and d - l <= DAY + 300)
end

-- the calendar reward captions: all days 1-14 give a non-empty English word without templates
for n = 1, 15 do
	local w = Notify.giftWord(Rewards.calendarReward(n, R))
	check("day " .. n .. ": the caption", #w > 2 and not string.find(w, "[{}]") and w ~= "a gift")
end
check("day 2 = a Cliffs egg", Notify.giftWord(Rewards.calendarReward(2, R)) == "a Cliffs egg")
check("day 14 = Epic Summit", Notify.giftWord(Rewards.calendarReward(14, R)) == "an Epic Summit egg")
check("garbage -> a gift", Notify.giftWord(nil) == "a gift" and Notify.giftWord({}) == "a gift")

-- the day 2 gift experiment (Config.Rewards.calendar.d2ab): "B" - a Rare dragon of the element from the UserId, "A" - a Cliffs egg
local Experiments = require("../src/shared/Core/Experiments")
local EL = Config.Elements
local D2live = R.calendar.d2ab
check("d2ab in Config: on, Rare, a dragon to everyone (force B, owner 26.10)", D2live ~= nil and D2live.on == true and D2live.rarity == "Rare" and D2live.force == "B")
check("in the live Config day 2 is a dragon for any UserId", Rewards.calendarRewardFor(2, R, 1, EL).hatchling == "Rare" and Rewards.calendarRewardFor(2, R, 4, EL).hatchling == "Rare")
local D2 = { on = true, rarity = "Rare" } -- the split mechanism (if force is removed) is checked on a copy without force
local R2 = { calendar = { days = R.calendar.days, day14 = R.calendar.day14, d2ab = D2, choices = R.calendar.choices } }
local nB, perEl = 0, {}
for uid = 1000, 1999 do
	local g = Experiments.d2Group(uid, D2)
	local rw = Rewards.calendarRewardFor(2, R2, uid, EL)
	if g == "B" then
		nB += 1
		perEl[rw.element or "?"] = (perEl[rw.element or "?"] or 0) + 1
		check("B " .. uid .. ": a Rare dragon with an element", rw.hatchling == "Rare" and table.find(EL, rw.element) ~= nil)
	else
		check("A " .. uid .. ": a Cliffs egg", rw.egg == "Cliffs" and rw.hatchling == nil)
	end
	check("days 1 and 3 are not touched " .. uid, Rewards.calendarRewardFor(1, R, uid, EL).minutes == 10 and Rewards.calendarRewardFor(3, R, uid, EL).berries == 3)
	check("day 9 (the repeat of day 2) - as it was " .. uid, Rewards.calendarRewardFor(9, R, uid, EL).egg == "Cliffs")
	check("the element is stable " .. uid, Experiments.d2Element(uid, EL) == Experiments.d2Element(uid, EL))
end
check("B about half (450-550 of 1000)", nB >= 450 and nB <= 550, tostring(nB))
local cnt = 0
for _, k in perEl do
	cnt += 1
	check("the elements roughly equal", k >= 50 and k <= 120)
end
check("all 6 elements occur", cnt == #EL)
-- independence from the firstborn growth groups (the second bit) and the egg captions (the parity)
local same, total = 0, 0
for uid = 5000, 5999 do
	total += 1
	if (Experiments.d2Group(uid, D2) == "B") == (math.floor(uid / 2) % 2 == 1) then
		same += 1
	end
end
check("d2 does not coincide with the growth group bit (~50% matches)", same > 400 and same < 600, tostring(same))
-- independence from the egg captions (the UserId parity)
local sameP = 0
for uid = 7000, 7999 do
	if (Experiments.d2Group(uid, D2) == "B") == (uid % 2 == 0) then
		sameP += 1
	end
end
check("d2 does not coincide with the parity (~50%)", sameP > 400 and sameP < 600, tostring(sameP))
check("force A - an egg to everyone", Experiments.d2Group(4, { on = true, force = "A" }) == "A")
-- the day titles (Strings.Rewards.day[n]) name what is granted
local Strings = require("../src/shared/Strings")
local function kind(rw: any): string
	if rw.minutes then return "coins" elseif rw.berries then return "berr" elseif rw.egg and rw.minRarity == "Epic" then return "Epic"
	elseif rw.egg then return "egg" elseif rw.decor then return string.lower(rw.decor) elseif rw.hatchling then return "dragon" end
	return "?"
end
for n, title in Strings.Rewards.day do
	local want = kind(Rewards.calendarReward(n, R))
	check("the title of day " .. n .. " about '" .. want .. "'", string.find(string.lower(title), string.lower(want), 1, true) ~= nil, title)
	check("day 2 without its own title (A and B differ)", n ~= 2)
end
check("disabled - A for everyone", Experiments.d2Group(4, { on = false }) == "A" and Experiments.d2Group(4, nil) == "A")
check("force B - a dragon to everyone", Experiments.d2Group(1, { on = true, force = "B" }) == "B" and Rewards.calendarRewardFor(2, { calendar = { days = R.calendar.days, day14 = R.calendar.day14, d2ab = { on = true, force = "B", rarity = "Rare" } } }, 1, EL).hatchling == "Rare")
local uidB = 4 -- the third bit = 1 -> B
check("uid 4 - group B", Experiments.d2Group(uidB, D2) == "B")
local wB = Notify.giftWord(Rewards.calendarRewardFor(2, R, uidB, EL))
check("caption B: a Rare <Element> baby dragon", string.find(wB, "^a Rare %u%l+ baby dragon$") ~= nil, wB)
check("text B <= 99 with a long name", #("Abcdefghijklmnopqrst is waiting at your nest! Day 2 gift: " .. wB) <= 99)

-- the dragon name: the companion, otherwise the most senior
local dr = { ["1"] = { name = "Ember", stage = 1 }, ["2"] = { name = "Frosty", stage = 3 }, ["3"] = { name = "Moss", stage = 3 } }
check("the companion matters more than the stage", Notify.dragonName(dr, "1") == "Ember")
check("without a companion - the most senior, at a tie the smaller uid", Notify.dragonName(dr, nil) == "Frosty")
check("a companion without a record - the most senior", Notify.dragonName(dr, "9") == "Frosty")
check("empty - nil", Notify.dragonName({}, nil) == nil and Notify.dragonName(nil, nil) == nil)
check("an empty name is skipped", Notify.dragonName({ a = { name = "", stage = 5 }, b = { name = "Bo", stage = 0 } }, nil) == "Bo")

-- the queue entry
local function data(day: number, claimed: number, dragons: any): any
	return { rewards = { calendar = { day = day, claimed = claimed, lastDate = "" } }, dragons = dragons, companion = nil }
end
local e = Notify.entry(data(1, 1, dr), left, R2, N)
check("claimed day 1 -> tomorrow day 2", e ~= nil and e.day == 2 and e.gift == "a Cliffs egg" and e.dragon == "Frosty" and e.due == due and e.left == left)
local eB = Notify.entry(data(1, 1, dr), left, R, N, uidB, EL)
check("the queue entry of group B: the day 2 dragon", eB ~= nil and eB.day == 2 and string.find(eB.gift, "baby dragon") ~= nil)
local eA = Notify.entry(data(1, 1, dr), left, R2, N, 1, EL)
check("the queue entry of group A (without force): an egg", eA ~= nil and eA.gift == "a Cliffs egg")
local eNoEl = Notify.entry(data(1, 1, dr), left, R, N, uidB, nil)
check("userId without the element list - the reward without the experiment (an egg): Services/Notify passes both", eNoEl ~= nil and eNoEl.gift == "a Cliffs egg")
local eAll = Notify.entry(data(1, 1, dr), left, R, N, 1, EL)
check("the live Config: the queue entry of any player - the day 2 dragon", eAll ~= nil and string.find(eAll.gift, "baby dragon") ~= nil)
local p = Notify.entry(data(1, 0, dr), left, R, N)
check("did not claim day 1 -> day 1 waits", p ~= nil and p.day == 1 and string.find(p.gift, "minutes") ~= nil)
check("the calendar is not started -> none", Notify.entry(data(0, 0, dr), left, R, N) == nil)
check("no dragons -> none", Notify.entry(data(1, 1, {}), left, R, N) == nil)
check("garbage -> none", Notify.entry(nil, left, R, N) == nil and Notify.entry({}, left, R, N) == nil)
-- the notification text (the Creator Hub template) fits in 99 characters with the parameters
local template = "{dragon} is waiting at your nest! Day {day} gift: {gift}"
check("the template <= 99", #template <= 99)
for n = 1, 14 do
	local text = string.format("%s is waiting at your nest! Day %d gift: %s", "Abcdefghijklmnopqrst", n, Notify.giftWord(Rewards.calendarReward(n, R)))
	check("the text of day " .. n .. " with a long name <= 120", #text <= 120)
end

print(string.format("notify_spec: %d ok, %d fail", passed, failed))
if failed > 0 then
	error("notify_spec failed")
end
