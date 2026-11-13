--!strict
-- Combat (spec 19 "Sky Guardians"): the dragon power, the stages of island 1, the rewards, the auto aim target choice, the guard pulse.
-- Pure logic without Roblox API; the numbers from Config.Combat (C) and Config.Balance (B).

local Economy = require("./Economy")

local Combat = {}

export type StageDef = { n: number?, hp: number, guardian: boolean?, seconds: number?, sky: boolean?, name: string? }

-- The hit power: the companion's income x (1 + ascension) x fedMult (while fed) + nestShare x the income of the other nest dragons.
-- data - the profile (dragons, nestOrder, companion, ascension); without a companion - 0 (nobody to hit with).
-- assumeFed (the combat rhythm): the power if the companion is fed now (the "feed" hint before a too strong wave)
function Combat.power(data: any, now: number, C: any, B: any, assumeFed: boolean?): number
	local dragons = if typeof(data.dragons) == "table" then data.dragons else {}
	local uid = data.companion
	local d = if typeof(uid) == "string" then dragons[uid] else nil
	if not d then
		return 0
	end
	local p = Economy.dragonIncome(d, B) * (1 + math.max(data.ascension or 0, 0))
	if assumeFed or (d.fedUntil and d.fedUntil > now) then
		p *= C.power.fedMult
	end
	local rest = 0
	if typeof(data.nestOrder) == "table" then
		for _, other in data.nestOrder :: { string } do
			local o = dragons[other]
			if o and other ~= uid then
				rest += Economy.dragonIncome(o, B)
			end
		end
	end
	p += rest * C.power.nestShare
	return p
end

-- The hit: an integer, not less than 1 (a Common hatchling hits for 1)
function Combat.damage(power: number): number
	return math.max(1, math.floor(power + 0.5))
end

function Combat.stageCount(C: any): number
	return #C.stages
end

function Combat.stage(C: any, k: number): StageDef?
	return C.stages[k]
end

-- The number of the first sky stage (after the meadow guard)
function Combat.firstSky(C: any): number
	for k, s in C.stages :: { StageDef } do
		if s.sky then
			return k
		end
	end
	return #C.stages + 1
end

-- Which wave to keep on the arena: cleared - stages passed (the profile combat.stage); arena "meadow" | "sky".
-- Returns the stage number and the replay flag. The meadow: the next unpassed one up to the meadow guard; after it - a replay of the last
-- ordinary meadow stage. The sky: empty until the meadow guard is beaten; then the next unpassed one, after the last - a replay
-- of the last ordinary sky stage.
function Combat.waveFor(C: any, cleared: number, arena: string): (number?, boolean)
	local sky1 = Combat.firstSky(C)
	local total = #C.stages
	if arena == "meadow" then
		if cleared + 1 < sky1 then
			return cleared + 1, false
		end
		return sky1 - 2, true -- the last ordinary meadow stage (before the guard)
	end
	if cleared + 1 < sky1 then
		return nil, false
	end
	if cleared < total then
		return cleared + 1, false
	end
	return total - 1, true
end

-- The health of the whole wave (for the helper's share)
function Combat.waveHp(def: StageDef): number
	if def.guardian then
		return def.hp
	end
	return def.hp * (def.n or 1)
end

-- The stage reward: coins (a number) or minutes of income; replay - the share replayShare. rate - the nest income per second.
-- Returns the coins, the guard's egg ({ egg, minRarity }?) - the egg only for the first win
function Combat.reward(C: any, k: number, rate: number, replay: boolean, minMinutesReward: number): (number, any?)
	local R = C.rewards
	local coins = 0
	local egg: any = nil
	local g = R.guardian[k]
	if g then
		coins = Economy.minutesOfIncome(rate, g.minutes or 0)
		coins = math.max(coins, minMinutesReward)
		if not replay and g.egg then
			egg = { egg = g.egg, minRarity = g.minRarity }
		end
	elseif R.coins[k] then
		coins = R.coins[k]
	elseif R.minutes[k] then
		coins = math.max(Economy.minutesOfIncome(rate, R.minutes[k]), minMinutesReward)
	end
	if replay then
		coins = math.floor(coins * R.replayShare)
		if R.replayCapSeconds then -- not a farm - a ceiling in seconds of the nest income
			coins = math.min(coins, math.max(math.floor(rate * R.replayCapSeconds), R.replayMinCoins or 0))
		end
	end
	return coins, egg
end

-- To the helper of a foreign wave: a share of the reward if his damage >= helperMinShare of the wave health
function Combat.helperCoins(C: any, ownerCoins: number, dealt: number, waveHp: number): number
	if waveHp <= 0 or dealt < waveHp * C.rewards.helperMinShare then
		return 0
	end
	return math.floor(ownerCoins * C.rewards.helperShare)
end

-- The arena center of the own nest: the axis of nest index (1..count, the angle (index - 1) * angleStep, the direction as Layout.dir:
-- (cos, 0, -sin) - nest 1 on the +X axis), the radius and the height from C.arena. The meadow height is given by the server by a raycast; here x, z (and the sky y)
function Combat.arenaXZ(C: any, nests: any, index: number, arena: string): (number, number, number?)
	local sh = if arena == "meadow" and C.arena.shift then C.arena.shift[index] else nil
	local a = math.rad((index - 1) * nests.angleStep + (if sh then sh.angle else 0))
	local r = if arena == "sky" then C.arena.skyR elseif sh then sh.r else C.arena.meadowR
	return math.cos(a) * r, -math.sin(a) * r, if arena == "sky" then C.arena.skyY else nil
end

export type V3 = { x: number, y: number, z: number }
export type Target = { id: string, pos: V3 }

-- The auto aim: the nearest enemy in the cone coneDeg in front of the gaze look (horizontally), otherwise the nearest within the radius range.
-- The vectors - tables { x, y, z } (tests without Roblox API; the client converts Vector3)
function Combat.pick(from: V3, look: V3, list: { Target }, C: any): string?
	local range = C.breath.range
	local cosHalf = math.cos(math.rad(C.breath.coneDeg / 2))
	local lx, lz = look.x, look.z
	local ll = math.sqrt(lx * lx + lz * lz)
	local bestCone, dCone = nil, math.huge
	local bestAny, dAny = nil, math.huge
	for _, t in list do
		local vx, vy, vz = t.pos.x - from.x, t.pos.y - from.y, t.pos.z - from.z
		local d = math.sqrt(vx * vx + vy * vy + vz * vz)
		if d <= range then
			if d < dAny then
				bestAny, dAny = t.id, d
			end
			local fl = math.sqrt(vx * vx + vz * vz)
			if ll > 1e-3 and fl > 1e-3 and (vx * lx + vz * lz) / (fl * ll) >= cosHalf and d < dCone then
				bestCone, dCone = t.id, d
			end
		end
	end
	return bestCone or bestAny
end

-- The guard pulse: the phase in the cycle pulseEvery s from the fight start t (s). "idle" | "warn" (the circle glows) | "hit" (the moment of the hit)
function Combat.pulsePhase(t: number, G: any): string
	if t < 0 then
		return "idle"
	end
	local inCycle = t % G.pulseEvery
	if inCycle >= G.pulseEvery - G.warn then
		return "warn"
	end
	return "idle"
end

-- The number of the pulse that should have hit by the moment t (0 - none yet): the hit at the end of every cycle
function Combat.pulseCount(t: number, G: any): number
	if t < 0 then
		return 0
	end
	return math.floor(t / G.pulseEvery)
end

-- ---------------------------------------------------------------------------------------------- the hunt rhythm
-- the hunt comes in a pause, not into
-- a task, and only with a wave the dragon takes in reasonable time. H = C.hunt; the seconds - the server's os.clock().

-- The expected fight seconds of wave def at damage dmg per hit (H.hitsPerSec hits per second)
function Combat.expectSec(def: StageDef, dmg: number, H: any): number
	return Combat.waveHp(def) / (math.max(dmg, 1) * H.hitsPerSec)
end

-- hist - the player's past waves { { start, end } }: the share of seconds with a live wave over the last window s
function Combat.fightShare(hist: { { number } }, now: number, window: number): number
	local from = now - window
	local sum = 0
	for _, h in hist do
		local a, b = math.max(h[1], from), math.min(h[2], now)
		if b > a then
			sum += b - a
		end
	end
	return sum / window
end

-- how many waves started over the last window s
function Combat.wavesIn(hist: { { number } }, now: number, window: number): number
	local n = 0
	for _, h in hist do
		if h[1] >= now - window then
			n += 1
		end
	end
	return n
end

-- Which wave the hunt leads on arena arena: (stage?, replay, hint?). dmg / dmgFed - the damage now and if fed.
-- The next unpassed one (Combat.waveFor) if its expected seconds <= H.maxFightSec (the guard - H.guardianMaxSec); otherwise a replay
-- of the last passed one of this arena and the hint weak: "feed" (fed, it will take it), "grow" (needs stronger), "storm" (the sky guard - not today);
-- after the meadow guard on the ground - a replay with the hint "sky" (fly). Nothing to replay (the arena's first stage is beyond the power) - nil and a hint.
-- The replay takes the strongest passed ordinary stage of the arena not above from that the dragon takes by power (the companion changed to a hatchling -
-- the replay is smaller, not 90 s against the hounds).
function Combat.huntStage(C: any, cleared: number, arena: string, dmg: number, dmgFed: number, newbie: boolean): (number?, boolean, string?)
	local H = C.hunt
	local M = H.maxFightSec
	local function limit(def: StageDef): number
		return if def.guardian then H.guardianMaxSec elseif def.sky then M.sky elseif newbie then M.new else M.old
	end
	local sky1 = Combat.firstSky(C)
	local first = if arena == "sky" then sky1 else 1
	local function replayFrom(from: number): number?
		for j = from, first, -1 do
			local def = C.stages[j] :: StageDef
			-- the replay is short (replayMaxSec), not 80 s for half the reward
			if not def.guardian and Combat.expectSec(def, dmg, H) <= math.min(limit(def), H.replayMaxSec or math.huge) then
				return j
			end
		end
		return nil
	end
	local k, rep = Combat.waveFor(C, cleared, arena)
	if not k then
		return nil, false, nil
	end
	if rep then
		local j = replayFrom(k)
		return j, j ~= nil, if arena == "meadow" then "sky" else nil
	end
	local def = C.stages[k] :: StageDef
	if Combat.expectSec(def, dmg, H) <= limit(def) then
		return k, false, nil
	end
	local weak = if Combat.expectSec(def, dmgFed, H) <= limit(def) then "feed" elseif def.guardian and def.sky then "storm" else "grow"
	local j = replayFrom(math.min(cleared, k - 1))
	return j, j ~= nil, weak
end

export type HuntSig = {
	now: number,
	joinedAt: number, -- the entry (the quiet after the entry counts as after a wave)
	lastEnd: number?, -- the end of the previous wave
	progAt: number?, -- the last progress (progressKey: dragons, stages, eggs, onboarding, the Keeper, combat)
	busyEnd: number?, -- a menu / scene closed
	newbie: boolean, -- the first session, has not flown yet
	busy: boolean, -- a menu / scene is open
	afk: boolean, -- no input Reward.isActive
	hold: string?, -- a task in hand: carry | grow | ride | fly | hatch
	hist: { { number } },
	replayGap: number?, -- the wave is a replay: not more often (s since the previous), only in a pause and without a task in hand
}

-- Whether it is time to announce a hunt wave: (yes, the reason). The "no" reasons: busy, afk, join, menu, gap, cap, hold, wait; "yes": idle (a pause)
-- max (gapMax: the fight finds you itself), replay
function Combat.huntReady(sig: HuntSig, H: any): (boolean, string)
	if sig.busy then
		return false, "busy"
	end
	if sig.afk then
		return false, "afk"
	end
	local now = sig.now
	if now - sig.joinedAt < H.firstAfterJoin then
		return false, "join"
	end
	if sig.busyEnd and now - sig.busyEnd < H.afterBusy then
		return false, "menu"
	end
	local who = if sig.newbie then "new" else "old"
	local last = sig.lastEnd or sig.joinedAt
	local since = now - last
	local gapMin = H.gapMin[who]
	if Combat.fightShare(sig.hist, now, H.share.window) > H.share.max then
		gapMin *= 2
	end
	if since < gapMin then
		return false, "gap"
	end
	if Combat.wavesIn(sig.hist, now, H.cap.window) >= H.cap[who] then
		return false, "cap"
	end
	local idle = now - math.max(sig.progAt or last, last)
	if sig.replayGap then
		if since < sig.replayGap then
			return false, "gap"
		end
		-- a task in hand does not hold the replay forever (the adult has not taken off yet, the egg lies ready) - up to 2 x the interval
		if sig.hold and since < 2 * sig.replayGap then
			return false, "hold"
		end
		return idle >= H.idle[who], if idle >= H.idle[who] then "replay" else "wait"
	end
	if since >= H.gapMax[who] then
		return true, "max"
	end
	if sig.hold then
		return false, "hold"
	end
	if idle >= H.idle[who] then
		return true, "idle"
	end
	return false, "wait"
end

-- The stage bar caption: "Stage k/N"; for a replay - the number of the last passed one
function Combat.label(C: any, k: number): string
	return string.format("%d/%d", k, #C.stages)
end

return Combat
