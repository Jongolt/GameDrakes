--!strict
-- 2.4: the rewards of spec 06 §2-4, §6, §8 - pure logic without Roblox API (the Reward service, the Gifts client and the Quests tab).
-- Daily: the pool by UTC date (the same tasks for everyone on this day), the day counters, the tier marks and the "all three" bonus.
-- The tasks of the week (add. 21.10): two from Content.Updates[live].weekly, the reset Sun 19:00 UTC.
-- The gifts for time: session minutes without AFK, claim one at a time. The calendar: the day counts at the first entry in a UTC day if
-- the previous day's reward is claimed (a skip takes nothing away), 8-13 like 1-6, 14 - an Epic egg, then the cycle 1-7.

local Experiments = require("./Experiments")

local Rewards = {}

Rewards.TIERS = { "easy", "medium", "hard" }

export type DailyDef = { id: string, event: string, count: number, off: boolean?, from: string? }
export type Daily = { date: string, ids: { string }, counters: { [string]: number }, done: { [string]: boolean }, bonus: boolean }
export type Calendar = { day: number, lastDate: string, claimed: number }
export type Reward = { minutes: number?, coins: number?, berries: number?, egg: string?, minRarity: string?, rareNest: boolean?, decor: string?, hatchling: string?, element: string? }
export type Gift = { min: number, minutes: number?, berries: number?, egg: string?, rareNest: boolean? }

-- the UTC date "YYYY-MM-DD" and the day number since the epoch
function Rewards.dateKey(t: number): string
	return os.date("!%Y-%m-%d", math.floor(t)) :: string
end

function Rewards.dayIndex(t: number): number
	return math.floor(t / 86400)
end

-- seconds to 00:00 UTC
function Rewards.toReset(t: number): number
	return 86400 - math.floor(t) % 86400
end

-- ---------------------------------------------------------------------------------------------- daily (§2)
-- 2.9: a task with from (a UTC date "YYYY-MM-DD", pool B of update 1) enters the pool from that day; day = nil - only without from
function Rewards.pool(R: any, tier: string, day: number?): { DailyDef }
	local out = {}
	local today = if day then Rewards.dateKey(day * 86400) else nil
	for _, d in (R.daily.pool[tier] or {}) :: { DailyDef } do
		if not d.off and (d.from == nil or (today ~= nil and today >= d.from)) then
			table.insert(out, d)
		end
	end
	return out
end

-- the tasks of the day: one from each group, deterministic from the day number (Knuth's hash, the groups have different salt)
function Rewards.dailyPicks(day: number, R: any): { string }
	local ids = {}
	for i, tier in Rewards.TIERS do
		local pool = Rewards.pool(R, tier, day)
		if #pool > 0 then
			local h = ((day * 2654435761) + i * 40503 * 7919) % 4294967296
			h = (h // 65536 + h * 31) % 4294967296 -- shuffle the low bits: neighboring days do not go in a cycle
			table.insert(ids, pool[(h % #pool) + 1].id)
		else
			table.insert(ids, "")
		end
	end
	return ids
end

-- the task description by id (and its group)
function Rewards.def(R: any, id: string): (DailyDef?, string?)
	for _, tier in Rewards.TIERS do
		for _, d in (R.daily.pool[tier] or {}) :: { DailyDef } do
			if d.id == id then
				return d, tier
			end
		end
	end
	return nil, nil
end

-- a new day: zero the counters and the marks; true - reset
function Rewards.dailyReset(daily: Daily, t: number, R: any): boolean
	local today = Rewards.dateKey(t)
	if daily.date == today and #(daily.ids or {}) == #Rewards.TIERS then
		return false
	end
	daily.date = today
	daily.ids = Rewards.dailyPicks(Rewards.dayIndex(t), R)
	daily.counters = {}
	daily.done = {}
	daily.bonus = false
	return true
end

-- the progress of the task of group tier: (k, n, def)
function Rewards.dailyProgress(daily: Daily, tierIdx: number, R: any): (number, number, DailyDef?)
	local d = Rewards.def(R, (daily.ids or {})[tierIdx] or "")
	if not d then
		return 0, 1, nil
	end
	return math.min((daily.counters or {})[d.event] or 0, d.count), d.count, d
end

-- whether some NOT closed task of the day needs the event (the closed ones do not accumulate - fewer replications)
function Rewards.uses(daily: Daily, event: string, R: any): boolean
	for i, id in daily.ids or {} do
		local d = Rewards.def(R, id)
		if d and d.event == event and not (daily.done or {})[Rewards.TIERS[i]] then
			return true
		end
	end
	return false
end

-- a day event: the counter += n if a task of the day needs the event; returns the groups closed now and whether the bonus is closed
function Rewards.dailyEvent(daily: Daily, event: string, n: number, R: any): ({ string }, boolean)
	local closed: { string } = {}
	if not Rewards.uses(daily, event, R) then
		return closed, false
	end
	daily.counters = daily.counters or {}
	daily.counters[event] = (daily.counters[event] or 0) + n
	daily.done = daily.done or {}
	for i, tier in Rewards.TIERS do
		local k, cnt, d = Rewards.dailyProgress(daily, i, R)
		if d and not daily.done[tier] and k >= cnt then
			daily.done[tier] = true
			table.insert(closed, tier)
		end
	end
	local bonusNow = false
	if not daily.bonus and #closed > 0 then
		local all = true
		for _, tier in Rewards.TIERS do
			if not daily.done[tier] then
				all = false
			end
		end
		if all then
			daily.bonus = true
			bonusNow = true
		end
	end
	return closed, bonusNow
end

-- ---------------------------------------------------------------------------------------------- the gifts for time (§3)
-- the next unclaimed gift not reached yet: (the minute, seconds to it) or nil
function Rewards.nextGift(list: { Gift }, sec: number, claimed: { [string]: boolean }): (number?, number)
	for _, g in list do
		if not claimed[tostring(g.min)] and g.min * 60 > sec then
			return g.min, g.min * 60 - sec
		end
	end
	return nil, 0
end

-- ready to claim (the minute has come, not claimed)
function Rewards.readyGifts(list: { Gift }, sec: number, claimed: { [string]: boolean }): { number }
	local out = {}
	for _, g in list do
		if not claimed[tostring(g.min)] and g.min * 60 <= sec then
			table.insert(out, g.min)
		end
	end
	return out
end

function Rewards.gift(list: { Gift }, min: number): Gift?
	for _, g in list do
		if g.min == min then
			return g
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------- the calendar (§4)
-- the first entry in a day: the next day if the previous one is claimed; true - the day counted
function Rewards.calendarAdvance(cal: Calendar, t: number): boolean
	local today = Rewards.dateKey(t)
	cal.claimed = cal.claimed or 0
	if cal.lastDate == today or cal.claimed < cal.day then
		return false
	end
	cal.day += 1
	cal.lastDate = today
	return true
end

function Rewards.calendarPending(cal: Calendar?): boolean
	return cal ~= nil and (cal.claimed or 0) < (cal.day or 0)
end

-- the reward of day n: 1-7 by the table, 8-13 like 1-6, 14 - day14, then the cycle 1-7
function Rewards.calendarReward(n: number, R: any): Reward
	local C = R.calendar
	if n <= 7 then
		return C.days[math.max(n, 1)]
	elseif n <= 13 then
		return C.days[n - 7]
	elseif n == 14 then
		return C.day14
	end
	return C.days[((n - 15) % 7) + 1]
end

-- the reward of day n for a specific player - the day 2 experiment (R.calendar.d2ab): group "B" gets a Rare dragon of the element
-- from the UserId instead of a Cliffs egg (without a choice: the element is known in advance to the "tomorrow" banner and the notification)
function Rewards.calendarRewardFor(n: number, R: any, userId: number, elements: { string }): Reward
	local cfg = R.calendar.d2ab
	if n == 2 and cfg and Experiments.d2Group(userId, cfg) == "B" then
		return { hatchling = cfg.rarity, element = Experiments.d2Element(userId, elements) }
	end
	return Rewards.calendarReward(n, R)
end

-- the day's place in the strip of 7 tiles (1..7) - for the screen
function Rewards.calendarSlot(n: number): number
	if n <= 14 then
		return ((n - 1) % 7) + 1
	end
	return ((n - 15) % 7) + 1
end

-- the elements to choose from for the Rare hatchling: k in a row around the circle from the day number (the same for everyone on this day)
function Rewards.choices(n: number, elements: { string }, k: number): { string }
	local out = {}
	local start = (n * 5) % #elements
	for i = 0, math.min(k, #elements) - 1 do
		table.insert(out, elements[((start + i * 2) % #elements) + 1])
	end
	return out
end

-- ---------------------------------------------------------------------------------------------- the zones (§3: Rare nest 90 min)
-- the best open zone by the senior dragon stage: a hatchling - Cliffs (gliding), a teen - Springs, an adult - Summit
function Rewards.bestZone(maxStage: number): string
	if maxStage >= 2 then
		return "Summit"
	elseif maxStage >= 1 then
		return "Springs"
	end
	return "Cliffs"
end

-- the next zone after zone (Summit - itself)
function Rewards.nextZone(zone: string, order: { string }): string
	local i = table.find(order, zone) or #order
	return order[math.min(i + 1, #order)]
end

-- ---------------------------------------------------------------------------------------------- the tasks of the week (add. 21.10, R8)
-- the week Sun 19:00 - Sun 19:00 UTC: the same boundaries as the activeFrom of the updates; the set - Content.Updates[n].weekly of the last running
-- update that has one (a week without a new update repeats it from zero); live = 0 (before 08.11) - no tasks
export type WeeklyDef = { id: string, event: string, count: number }
export type WeeklySet = { egg: string, quests: { WeeklyDef } }
export type Weekly = { week: number, update: number, counters: { [string]: number }, done: { [string]: boolean }, seen: number? }

function Rewards.weekIndex(t: number, anchor: number): number
	return math.floor((t - anchor) / 604800)
end

-- seconds to the next week reset
function Rewards.weekLeft(t: number, anchor: number): number
	return (Rewards.weekIndex(t, anchor) + 1) * 604800 + anchor - math.floor(t)
end

-- the set of the week: (the set, the number of its update) or nil
function Rewards.weeklySet(updates: { any }, live: number): (WeeklySet?, number)
	for n = math.min(live, #updates), 1, -1 do
		local w = updates[n].weekly
		if w and #(w.quests or {}) > 0 then
			return w, n
		end
	end
	return nil, 0
end

-- a new week (or another set): the counters and the marks from zero; true - reset
function Rewards.weeklyReset(w: Weekly, t: number, anchor: number, update: number): boolean
	local week = Rewards.weekIndex(t, anchor)
	if w.week == week and w.update == update then
		return false
	end
	w.week = week
	w.update = update
	w.counters = {}
	w.done = {}
	return true
end

-- the progress of task i: (k, n, def)
function Rewards.weeklyProgress(w: Weekly, i: number, set: WeeklySet): (number, number, WeeklyDef?)
	local d = set.quests[i]
	if not d then
		return 0, 1, nil
	end
	return math.min((w.counters or {})[d.event] or 0, d.count), d.count, d
end

-- whether a NOT closed task of the week needs the event
function Rewards.weeklyUses(w: Weekly, event: string, set: WeeklySet): boolean
	for i, d in set.quests do
		if d.event == event and not (w.done or {})[tostring(i)] then
			return true
		end
	end
	return false
end

-- a week event: the counter += n; returns the numbers of the tasks closed now
function Rewards.weeklyEvent(w: Weekly, event: string, n: number, set: WeeklySet): { number }
	local closed: { number } = {}
	if not Rewards.weeklyUses(w, event, set) then
		return closed
	end
	w.counters = w.counters or {}
	w.counters[event] = (w.counters[event] or 0) + n
	w.done = w.done or {}
	for i in set.quests do
		local k, cnt = Rewards.weeklyProgress(w, i, set)
		if not w.done[tostring(i)] and k >= cnt then
			w.done[tostring(i)] = true
			table.insert(closed, i)
		end
	end
	return closed
end

-- the event badge (add. 21.10 (2), R9): the badge key of update upd if week week is the first week of this update; otherwise nil
function Rewards.weeklyBadge(updates: { any }, upd: number, week: number, anchor: number): string?
	local u = updates[upd]
	if u and u.badge and Rewards.weekIndex(u.activeFrom, anchor) == week then
		return u.badge
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------- the season (§8)
-- the steps that can be claimed: enough points, not claimed yet (claimed[tostring(i)])
function Rewards.seasonClaimable(points: number, claimed: { [string]: boolean }?, steps: { number }): { number }
	local out = {}
	for i, need in steps do
		if points >= need and not (claimed or {})[tostring(i)] then
			table.insert(out, i)
		end
	end
	return out
end

function Rewards.seasonStep(points: number, steps: { number }): number
	local k = 0
	for i, need in steps do
		if points >= need then
			k = i
		end
	end
	return k
end

return Rewards
