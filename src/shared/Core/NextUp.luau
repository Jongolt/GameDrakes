--!strict
-- the line "what awaits you and when" - pure logic without Roblox API (the client Controllers/NextUp, the Gifts tab); without it the stage
-- and egg timers are visible only up close. The elements:
-- timer - the player's nearest timer: the growth of a dragon in the nest (the companion is in the nest too) or an egg still warming in an incubator;
-- update - the next update of Content.Updates (not earlier than now), with the eventId of the Roblox event for RSVP if it exists.

local Format = require("./Format")

local NextUp = {}

export type Item = { kind: string, at: number, name: string?, stage: number?, title: string?, eventId: string?, first: boolean? } -- first: the firstborn (growAs)

-- data: { dragons, nestOrder, eggs } as in the profile (on the client - from the Store)
function NextUp.timer(data: any, now: number): Item?
	local best: Item? = nil
	local order = data.nestOrder
	local dragons = data.dragons
	if type(order) == "table" and type(dragons) == "table" then
		for _, uid in order do
			local d = dragons[uid]
			if type(d) == "table" and type(d.stageEndsAt) == "number" and d.stageEndsAt > now and (d.stage or 0) < 3 then
				if not best or d.stageEndsAt < best.at then
					best = { kind = "grow", at = d.stageEndsAt, name = tostring(d.name or ""), stage = (d.stage or 0) + 1, first = d.growAs ~= nil }
				end
			end
		end
	end
	local inc = type(data.eggs) == "table" and data.eggs.incubating or nil
	if type(inc) == "table" then
		for _, rec in inc do
			if type(rec) == "table" and type(rec.endsAt) == "number" and rec.endsAt > now then
				if not best or rec.endsAt < best.at then
					best = { kind = "hatch", at = rec.endsAt }
				end
			end
		end
	end
	return best
end

-- the nearest update that has not started yet; within - not farther than this many seconds (nil - any)
function NextUp.update(updates: { any }, now: number, within: number?): Item?
	for _, u in updates do
		if u.activeFrom > now then
			if within and u.activeFrom - now > within then
				return nil
			end
			return { kind = "update", at = u.activeFrom, title = u.title, eventId = u.eventId }
		end
	end
	return nil
end

-- how much is left: from a day - the days template (days: "{d}d {h}h"), less - hours (Format.clock)
function NextUp.left(seconds: number, days: string): string
	local s = math.max(0, math.floor(seconds + 0.5))
	if s >= 86400 then
		local d = s // 86400
		local h = (s % 86400) // 3600
		return (string.gsub(string.gsub(days, "{d}", tostring(d)), "{h}", tostring(h)))
	end
	return Format.clock(s)
end

return NextUp
