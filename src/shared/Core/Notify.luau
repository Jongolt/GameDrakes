--!strict
-- the "calendar day is ready" notification - pure logic without Roblox API (tests/notify_spec.luau).
-- The server (Services/Notify) puts an Entry into the queue Config.Notify.store when the player leaves; the VPS (tools/notify_send.py) once an hour
-- sends the ones due via Open Cloud. The text - a Creator Hub string (Engagement -> Notifications), the English template:
-- "{dragon} is waiting at your nest! Day {day} gift: {gift}" - the parameters come from here, so the reward captions here are in English.

local Rewards = require("./Rewards")

local Notify = {}

export type Entry = { due: number, day: number, gift: string, dragon: string, left: number }

-- the day reward caption for the notification text (English, like the Creator Hub string)
function Notify.giftWord(rw: any): string
	if typeof(rw) ~= "table" then
		return "a gift"
	elseif rw.minutes then
		return tostring(rw.minutes) .. " minutes of nest coins"
	elseif rw.berries then
		return tostring(rw.berries) .. " berries"
	elseif rw.rareNest then
		return "a Rare nest egg"
	elseif rw.egg then
		if rw.minRarity == "Epic" then
			return "an Epic " .. tostring(rw.egg) .. " egg"
		end
		return "a " .. tostring(rw.egg) .. " egg"
	elseif rw.decor == "Banner" then
		return "a nest banner"
	elseif rw.decor then
		return "a " .. tostring(rw.decor) .. " for your nest"
	elseif rw.hatchling then
		if typeof(rw.element) == "string" and rw.element ~= "" then -- the day 2 dragon with an element (Experiments.d2Element)
			return "a " .. tostring(rw.hatchling) .. " " .. string.upper(string.sub(rw.element, 1, 1)) .. string.sub(rw.element, 2) .. " baby dragon"
		end
		return "a " .. tostring(rw.hatchling) .. " baby dragon"
	elseif rw.preset then
		return "a new dragon look"
	end
	return "a gift"
end

-- when to send: not earlier than the next midnight UTC (a new calendar day) + 5 min and not earlier than afterHours after the leave -
-- about the same time of day the player played yesterday
function Notify.due(left: number, afterHours: number): number
	local nextMidnight = (left // 86400 + 1) * 86400
	return math.max(nextMidnight + 300, left + math.floor(afterHours * 3600))
end

-- the dragon name for the text: the companion, otherwise the most senior by stage (at a tie - the smaller uid); no dragons - nil
function Notify.dragonName(dragons: any, companion: any): string?
	if typeof(dragons) ~= "table" then
		return nil
	end
	local c = if companion ~= nil then dragons[companion] else nil
	if typeof(c) == "table" and typeof(c.name) == "string" and c.name ~= "" then
		return c.name
	end
	local best: any, bestUid: string? = nil, nil
	for uid, d in dragons do
		if typeof(d) == "table" and typeof(d.name) == "string" and d.name ~= "" then
			local s = tonumber(d.stage) or 0
			local bs = if best then (tonumber(best.stage) or 0) else -1
			if s > bs or (s == bs and bestUid ~= nil and tostring(uid) < bestUid) then
				best, bestUid = d, tostring(uid)
			end
		end
	end
	return if best then best.name else nil
end

-- the queue entry at the leave: only for those whose calendar is started and who have at least one dragon (the text says "{dragon} is waiting")
function Notify.entry(data: any, left: number, R: any, N: any, userId: number?, elements: { string }?): Entry?
	if typeof(data) ~= "table" or typeof(data.rewards) ~= "table" then
		return nil
	end
	local cal = data.rewards.calendar
	if typeof(cal) ~= "table" or (tonumber(cal.day) or 0) <= 0 then
		return nil
	end
	local dragon = Notify.dragonName(data.dragons, data.companion)
	if not dragon then
		return nil
	end
	local n = (tonumber(cal.claimed) or 0) + 1 -- today's is claimed - tomorrow the next; not claimed - it is the one waiting
	local rw = if userId and elements then Rewards.calendarRewardFor(n, R, userId, elements) else Rewards.calendarReward(n, R)
	return { due = Notify.due(left, N.afterHours), day = n, gift = Notify.giftWord(rw), dragon = dragon, left = left }
end

return Notify
