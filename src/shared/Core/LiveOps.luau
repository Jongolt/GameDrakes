--!strict
-- 2.9: live operations (spec 09 §1-3) - pure logic without Roblox API (the services LiveOps, Weather, Incubation, Reward).
-- The updates (Content.Updates) switch on by themselves by the date activeFrom (Sun 19:00 UTC); live = how many updates are already running in a row
-- (0 - D0, 1 - Aurora, ...). The element variants (Content.Variants): the element + the egg zone + the weather at the moment of the hatch. The codes of the week
-- (Content.Codes): a window of days days from the activeFrom of their update, once per profile.
-- a code without an update - from (UTC) instead of update; days = nil - no end
-- (the community goal codes "50LIKES": they work from the release, announced on the page when the goal is reached).

local LiveOps = {}

export type Update = { id: string, activeFrom: number, title: string }
export type Variant = { element: string, update: number?, condition: { zone: string?, weather: string? }, label: string }
export type Code = { update: number?, from: number?, days: number?, minutes: number }

-- how many updates are running (in order; the next does not switch on before the previous)
function LiveOps.live(updates: { Update }, now: number): number
	local n = 0
	for i, u in updates do
		if now >= u.activeFrom then
			n = i
		else
			break
		end
	end
	return n
end

-- the variant for a hatch: egg - the element and the zone, weather - the weather now ("" - none); nil - an ordinary dragon
function LiveOps.variantFor(variants: { [string]: Variant }, egg: { element: string, zone: string? }, weather: string, live: number): string?
	for id, v in variants do
		local c = v.condition
		if (v.update or 0) <= live and egg.element == v.element and (c.zone == nil or egg.zone == c.zone) and (c.weather == nil or weather == c.weather) then
			return id
		end
	end
	return nil
end

-- the code as the player typed it -> the lookup form: without spaces, uppercase
function LiveOps.normCode(s: string): string
	return string.upper((string.gsub(s, "%s", "")))
end

-- the code check: (the description, nil) or (nil, the reason: "bad_code" - no such code or not started yet, "expired", "already")
function LiveOps.codeCheck(codes: { [string]: Code }, updates: { Update }, code: string, now: number, used: { [string]: any }?): (Code?, string?)
	local c = codes[code]
	local u = c and c.update and updates[c.update]
	local from = if u then u.activeFrom else c and c.from
	if not c or not from or now < from then
		return nil, "bad_code"
	end
	if used and used[code] then
		return nil, "already"
	end
	if c.days and now >= from + c.days * 86400 then
		return nil, "expired"
	end
	return c, nil
end

-- Update Party (09 §1) - seconds to the end of the party before an update: the window updatePartyMinutes before
-- updateHourUtc on the day updateWeekdayUtc, and only if an update starts at that hour (activeFrom); without an update this Sunday -
-- 0 (before, the party with "New content in 29:59" ran every Sunday, there was no content)
function LiveOps.partyLeft(updates: { Update }, t: number, LO: any): number
	local d = os.date("!*t", math.floor(t)) :: any
	if d.wday ~= LO.updateWeekdayUtc then
		return 0
	end
	local mins = d.hour * 60 + d.min
	local to = LO.updateHourUtc * 60
	if mins < to - LO.updatePartyMinutes or mins >= to then
		return 0
	end
	local at = math.floor(t) - (mins * 60 + d.sec) + to * 60 -- 19:00 of this day
	for _, u in updates do
		if math.abs(u.activeFrom - at) < 60 then
			return at - math.floor(t)
		end
	end
	return 0
end

return LiveOps
