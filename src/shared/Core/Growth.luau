--!strict
-- The growth and incubation timers (05 §2, 10 §7): by the end moment (unix), not the remainder; Fed x2 for 5 minutes; Treat;
-- Grow Now / Hatch Now; Hatch Party. Pure logic; now is passed from outside (os.time()).

local Growth = {}

export type Grower = { rarity: string, stage: number, stageEndsAt: number?, fedUntil: number?, growAs: string?, growGroup: string? }
export type Slot = { hatchAt: number?, partied: boolean? }

-- seconds to the next stage; nil for Elder
function Growth.stageSeconds(rarity: string, stage: number, B: any): number?
	local mins = B.growMin[rarity]
	assert(mins, "unknown rarity " .. tostring(rarity))
	local m = mins[stage + 1]
	return if m then m * 60 else nil
end

-- 05 add. 2.18: the rarity by which the growth timers (and the feed price) go: the firstborn until B.firstDragon.untilStage - by growAs
function Growth.timerRarity(d: Grower, B: any): string
	local F = B.firstDragon
	if d.growAs and F and d.stage < F.untilStage then
		return d.growAs :: string
	end
	return d.rarity
end

-- seconds of this dragon's current stage (the card scale); nil for Elder
-- the firstborn (growAs is set) until untilStage has its own timers B.firstDragon.growMin [H->J, J->A] in minutes;
-- the test group B (growGroup) - F.ab.growMinB
function Growth.stageSecondsOf(d: Grower, B: any): number?
	local F = B.firstDragon
	if d.growAs and F and F.growMin and d.stage < F.untilStage then
		local gm = if d.growGroup == "B" and F.ab and F.ab.on and F.ab.growMinB then F.ab.growMinB else F.growMin -- ab.on = false - everyone by growMin
		local m = gm[d.stage + 1]
		if m then
			return m * 60
		end
	end
	return Growth.stageSeconds(Growth.timerRarity(d, B), d.stage, B)
end

-- The end moment at a remainder remaining of "game" time, if until fedUntil the time runs x times faster
function Growth.endWithSpeed(now: number, remaining: number, fedUntil: number?, x: number): number
	if fedUntil and fedUntil > now and x > 1 then
		local f = fedUntil - now
		if remaining <= f * x then
			return now + remaining / x
		end
		return now + f + (remaining - f * x)
	end
	return now + remaining
end

-- Starting the current stage timer (after the hatch and after every transition)
function Growth.start(d: Grower, now: number, B: any)
	local s = Growth.stageSecondsOf(d, B)
	d.stageEndsAt = if s then Growth.endWithSpeed(now, s, d.fedUntil, B.feed.x) else nil
end

function Growth.remaining(d: Grower, now: number): number?
	return if d.stageEndsAt then math.max(0, d.stageEndsAt - now) else nil
end

function Growth.isFed(d: Grower, now: number): boolean
	return d.fedUntil ~= nil and (d.fedUntil :: number) > now
end

-- Feeding: x2 growth speed for 5 minutes. Refusal: an elder or already fed.
function Growth.feed(d: Grower, now: number, B: any): (boolean, string?)
	if d.stage >= 3 or d.stageEndsAt == nil then
		return false, "elder"
	end
	if Growth.isFed(d, now) then
		return false, "already_fed"
	end
	d.fedUntil = now + B.feed.seconds
	local rem = (d.stageEndsAt :: number) - now
	if rem > 0 then
		d.stageEndsAt = Growth.endWithSpeed(now, rem, d.fedUntil, B.feed.x)
	end
	return true, nil
end

-- A treat: minus half of the remaining real time
function Growth.treat(d: Grower, now: number, B: any): boolean
	local rem = Growth.remaining(d, now)
	if not rem or rem <= 0 then
		return false
	end
	d.stageEndsAt = now + rem * (1 - B.treatShare)
	return true
end

function Growth.growNow(d: Grower, now: number): boolean
	if d.stageEndsAt == nil then
		return false
	end
	d.stageEndsAt = now
	return true
end

-- The server sweep once per 1 s (and at the entry after offline): raises the stage if the timer ran out and starts a new
-- timer from now - so the offline growth stops by itself at the next stage (05 §8). Returns true at a transition.
function Growth.tick(d: Grower, now: number, B: any): boolean
	if d.stageEndsAt and now >= d.stageEndsAt and d.stage < 3 then
		d.stage += 1
		Growth.start(d, now, B)
		return true
	end
	return false
end

-- ---------------------------------------------------------------------------------------------- incubation
function Growth.startIncubation(slot: Slot, now: number, seconds: number)
	slot.hatchAt = now + seconds
	slot.partied = false
end

function Growth.incubationRemaining(slot: Slot, now: number): number
	return if slot.hatchAt then math.max(0, slot.hatchAt - now) else 0
end

function Growth.isReady(slot: Slot, now: number): boolean
	return slot.hatchAt ~= nil and now >= (slot.hatchAt :: number)
end

-- Hatch Party: a foreign player touched the incubator - the remainder /2 (a friend /3), once per egg
function Growth.party(slot: Slot, now: number, isFriend: boolean, B: any): boolean
	if slot.hatchAt == nil or slot.partied or Growth.isReady(slot, now) then
		return false
	end
	local rem = (slot.hatchAt :: number) - now
	slot.hatchAt = now + rem / (if isFriend then B.party.friendDiv else B.party.div)
	slot.partied = true
	return true
end

function Growth.hatchNow(slot: Slot, now: number): boolean
	if slot.hatchAt == nil then
		return false
	end
	slot.hatchAt = now
	return true
end

-- The Hatch Now / Grow Now price step by the remainder (07 §2): <= 1 min 5; <= 5 min 9; <= 20 min 19; <= 60 min 29; further 49
function Growth.priceTier(remaining: number, S: any): (number, number)
	for i, limit in S.hatchNow.steps do
		if remaining <= limit then
			return i, S.hatchNow.prices[i]
		end
	end
	return #S.hatchNow.prices, S.hatchNow.prices[#S.hatchNow.prices]
end

return Growth
