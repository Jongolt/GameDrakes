--!strict
-- The newcomer hint target (02 §1, §3; P11): by a state snapshot we pick one next step - where to lead the arrow and what
-- to highlight. Pure logic: the snapshot is collected by the client (Controllers/Hints) from the Store data and the world tags, here only the choice.
-- The order of importance: hatch a ready egg -> an egg in the hands into the incubator -> take an egg from the table (while there are no dragons) ->
-- collect the pile (the first time) -> find an egg on the island (the first time, there is a free incubator) -> feed (the first time).
-- one-time steps
-- are marked by the server in onboarding (coinsCollected, eggFound, fedOnce).

local Hints = {}

export type Snapshot = {
	tableFree: number, -- free eggs on the own nest table
	carry: boolean, -- an egg in the hands
	ringReady: number?, -- the incubator slot with a ready egg
	ringFree: number?, -- the first open empty slot
	dragons: number, -- dragons in the nest
	incubating: number, -- eggs warming
	pot: number, -- coins in the pile
	coins: number,
	feedPrice: number?, -- the minimum feed price among the own dragons that can be fed
	eggNear: boolean, -- there is an egg on an island spot within the radius
	coinsDone: boolean?, -- the pile was already collected (onboarding.coinsCollected) - the "coins" step once (02 §2 step 4)
	eggDone: boolean?, -- an egg on the island was already found (onboarding.eggFound) - the "find an egg" step once
	fedDone: boolean?, -- already fed (onboarding.fedOnce) - the "feed" step once
	-- 1.9: riding and flight (02 §2 2:30 and 7:30, 04 §5.1)
	companionStage: number?, -- the stage of the companion nearby (nil - no companion)
	mounted: boolean?, -- riding now
	flying: boolean?, -- in the air riding
	rodeDone: boolean?, -- already mounted (onboarding.rode)
	flewDone: boolean?, -- already took off (onboarding.flew)
	ringDone: boolean?, -- already flew through a ring (onboarding.ring)
	glideDone: boolean?, -- already glided with the hatchling (onboarding.glided)
	nestRideable: boolean?, -- the nest has an own dragon of stage >= 1, no companion - the target "take it"
	-- combat - Gloom stages passed, the own wave on the meadow (guardian - the guard) and in the sky
	combatStage: number?,
	gloomWave: boolean?,
	gloomGuardian: boolean?,
	skyWave: boolean?,
	glowEgg: boolean?, -- after the first flight an own glowing egg lies on an islet (Services/GlowEgg)
	carryGlow: boolean?, -- a glowing egg in the hands (the Gloom chases) - home, to the own nest, even riding and without a free bowl
	companionMissing: boolean?, -- no companion in the profile either (data.companion is empty or not in the nest) - the CompanionStage attribute can be nil on respawn
	-- an open ring has a Gloom nest with an egg (raidNear) or all are empty - wait (raidWait)
	-- carryRaid - the ring of the raid egg in the hands; nearHome - the player is at his bowls (Tap Hatch does not call from a raid)
	raidNear: boolean?,
	raidWait: boolean?,
	carryRaid: number?,
	nearHome: boolean?,
	-- glowDragon - a glowing egg in the hands, a raid to the slope (the GlowRaid attribute "dragon"): to the dragon, riding - home
	-- glowPending - has a dragon, the golden egg is not stolen yet: we do not call to the ring nests (the second dragon is the glowing one); the first raid - yes
	glowDragon: boolean?,
	glowPending: boolean?,
	-- a veteran's golden nest of the series (2-6) stands almost always - while there are daily raids today, we lead to them;
	-- the limit is over - to the golden nest
	glowLater: boolean?,
	-- has a dragon - we do not lead to the free island eggs either
	oneDragonDay: boolean?,
	-- has an own golden stand (glowPedestal) and the warming
	-- price (warmPrice, the stand attribute) - the target "warm the egg" when there are enough coins
	glowPedestal: boolean?,
	warmPrice: number?,
}

-- the one-dragon day - there is always a target: warm the egg (enough coins) -> the pile -> the hatchling to the updraft -> the adult take off ->
-- to the stand to save up -> to the Keeper's stall
local function dayGoal(s: Snapshot, C: { pileMin: number, dayPileMin: number? }, mounted: boolean): Goal?
	if not s.oneDragonDay then
		return nil
	end
	if s.glowPedestal and s.warmPrice and s.coins >= s.warmPrice then
		return { kind = "warm" }
	end
	-- an idle pile does not call the arrow -
	-- it accumulated to dayPileMin, led home and after collecting returned to the stall
	local cs = s.companionStage or 0
	if not mounted and cs == 0 and s.dragons >= 1 and not s.glideDone then -- the ledge - once, then the stall
		return { kind = "glide" }
	end
	if cs >= 2 then
		return { kind = "fly" }
	end
	if s.glowPedestal then
		return { kind = "warm" }
	end
	return { kind = "stall" }
end

export type Goal = { kind: string, slot: number? }

-- C = Config.Hints
function Hints.goal(s: Snapshot, C: { pileMin: number }): Goal?
	-- riding: only the air - takeoff (the first time) and the wind rings (the first time); the other steps wait for landing
	-- the glowing egg is the main target after the first flight
	-- also with an ordinary egg in the hands - at the golden nest it goes to the shelf by itself (Services/GlowEgg)
	-- the GlowRaid attribute "dragon" is set by the server at the moment of the theft and removed
	-- at the catch and at home, and the egg in the hands (the profile) arrives later - until then the target stayed "the golden nest" at the thief's feet
	local holdingGlow = s.carryGlow == true or s.glowDragon == true
	local toGlow = s.glowEgg == true and not holdingGlow and s.glowLater ~= true
	if toGlow then
		return { kind = "glowEgg" }
	end
	local glowHome = (s.carry and s.carryGlow == true) or s.glowDragon == true -- via a local: narrowing the type of s in the condition confused the analyzer (false "Key is missing")
	if glowHome then
		if s.glowDragon then -- on the slope - to the own dragon (waits 35 from the nest), mounted - home riding
			if s.mounted then
				return { kind = "raidRide" }
			end
			if (s.companionStage or 0) >= 1 then
				return { kind = "raidDragon" }
			end
		end
		return { kind = "glowHome" }
	end
	-- a raid egg in the hands - home: ring 0 on foot to the SAFE line; rings 1-2 - to the own dragon (mounted by itself), home riding
	local cr = s.carryRaid
	if s.carry and cr ~= nil then
		if s.mounted then
			return { kind = "raidRide" }
		end
		if cr >= 1 and (s.companionStage or 0) >= 1 then
			return { kind = "raidDragon" }
		end
		return { kind = "raidHome" }
	end
	if s.mounted then
		if s.flying then
			if not s.ringDone then
				return { kind = "ring" }
			end
			if s.raidNear and not s.glowPending then -- in flight - to a ring 2 nest
				return { kind = "raid" }
			end
			-- combat does not move the arrow (the waves come and go, the target would dart); the arrow only leads where to run, what to steal, where to carry
			return nil
		end
		if (s.companionStage or 0) >= 2 and not s.flewDone then
			return { kind = "fly" }
		end
		if s.raidNear and not s.glowPending then -- riding - to a Gloom nest of an open ring
			return { kind = "raid" }
		end
		if s.raidWait and not s.glowPending then
			return { kind = "raidWait" }
		end
		-- the Gloom, the meadow guard and "take off to the sky Gloom" do not move the arrow
		return dayGoal(s, C, true) -- riding idle - to the stand / the stall
	end
	if s.ringReady and (s.nearHome ~= false or not s.raidNear) then -- a ready egg is hatched at home, we do not call from a raid
		return { kind = "hatch", slot = s.ringReady }
	end
	if s.carry then
		if s.ringFree then
			return { kind = "incubator", slot = s.ringFree }
		end
		return nil
	end
	if s.tableFree > 0 and s.dragons == 0 and s.incubating == 0 then
		return { kind = "table" }
	end
	-- first the ledge with the hatchling (one target), then the pile once - before
	-- the pile (pileMin 5) overrode the ledge a second after the hatch
	if s.companionStage == 0 and s.dragons >= 1 and not s.glideDone then
		return { kind = "glide" }
	end
	if s.pot >= C.pileMin and not s.coinsDone then
		return { kind = "pile" }
	end
	-- a teen nearby, not mounted yet - first the ride (opens ring 1); then THE RAID - the verb of the whole game
	local cs0 = s.companionStage or 0
	if (cs0 >= 1 and not s.rodeDone) or (cs0 >= 2 and not s.flewDone) then
		return { kind = "ride" }
	end
	-- until the golden one is stolen
	-- we do not lead to the ring nests (the ring 0 nest itself stands - one can steal, but the arrow does not call there); the first raid (0 dragons) - always
	if s.raidNear and (s.dragons == 0 or not s.glowPending) then
		return { kind = if s.dragons == 0 then "raidFirst" else "raid" } -- no dragons - the first dragon is obtained by a raid
	end
	if s.raidWait and (s.dragons == 0 or not s.glowPending) then
		return { kind = "raidWait" }
	end
	-- the hatchling on the shoulder, has not glided yet - to the updraft at the ledge of the own nest
	if s.companionStage == 0 and s.dragons >= 1 and not s.glideDone then
		return { kind = "glide" }
	end
	-- the dragon grew up in the nest, no companion, has not mounted yet - first take it (Dragons -> Companion)
	if s.companionStage == nil and s.companionMissing and s.nestRideable and not s.rodeDone then
		return { kind = "companion" }
	end
	-- a teen nearby - mount (once); an adult nearby - mount to take off (until the first takeoff)
	local cs = s.companionStage or 0
	if (cs >= 1 and not s.rodeDone) or (cs >= 2 and not s.flewDone) then
		return { kind = "ride" }
	end
	-- a Gloom ambush does not move the arrow (there was a gloom/guardian target - every wave took the arrow off the way and brought it back)
	if s.dragons >= 1 and s.ringFree ~= nil and s.eggNear and not s.eggDone and not s.oneDragonDay then
		return { kind = "egg" }
	end
	if s.feedPrice and s.coins >= s.feedPrice and not s.fedDone then
		return { kind = "feed" }
	end
	-- nothing else to do - to the nearest egg on the island (there is somewhere to put it)
	if s.dragons >= 1 and s.ringFree ~= nil and s.eggNear and not s.oneDragonDay then
		return { kind = "egg" }
	end
	return dayGoal(s, C, false) -- there is always an arrow
end

-- The hint timer (02 §1): the target holds kind >= delay seconds and this step was not hinted yet -> show.
-- state = { kind, since, shown = { [kind] = true } }; returns true when it is time to show (and marks the step shown).
export type TimerState = { kind: string?, since: number, fired: boolean?, shown: { [string]: boolean } }

function Hints.newTimer(): TimerState
	return { kind = nil, since = 0, shown = {} }
end

function Hints.tick(t: TimerState, goal: Goal?, now: number, delay: number): boolean
	local kind = if goal then goal.kind else nil
	-- an arrow
	-- on every target change, not once per game per step (shown[kind] marks only the first show)
	if kind ~= t.kind then
		t.kind = kind
		t.since = now
		t.fired = false
		return false
	end
	if kind and not t.fired and now - t.since >= delay then
		t.fired = true
		t.shown[kind] = true
		return true
	end
	return false
end

-- how many icons fly into the counter (02 §2, 0:18-0:30: up to 10, a parabola of 1 s)
function Hints.coinIcons(n: number, max: number): number
	return math.clamp(math.ceil(n / 10), 1, max)
end

return Hints
