--!strict
-- the errands of the Keeper Old Ash (spec 06 §1 + addendum 1.3). 15 steps in order, the texts verbatim.
-- Pure logic: the event counters (quests.counters) always accumulate, a step is closed when counters[event] >= count.
-- The events: hatch, glide, eggInc, eggInc_<Zone>, feed, ride, fly, eggFound, ascension, elder, index (the value = the Index entries).
-- The rewards: coins | minutes (minutes of the nest income = income/s x 60 x N, not less than Config.Quests.minMinutesReward) | egg (the zone, minRarity).

local Quests = {}

export type Reward = { coins: number?, minutes: number?, egg: string?, minRarity: string? }
-- fresh: count the event only from the moment the errand became current (keeper.base[id] - the counter at that moment)
export type Quest = { id: number, title: string, text: string, event: string, count: number, reward: Reward, update: number?, fresh: boolean? }
export type State = { keeper: { step: number, progress: any?, base: { [string]: number }? }, counters: { [string]: number } }

local LIST: { Quest } = {
	{ id = 1, title = "First hatch", text = "Put the egg in the nest and keep it warm.", event = "hatch", count = 1, reward = { coins = 50 } },
	{ id = 2, title = "Wings of a hatchling", text = "Jump off the ledge. The little one will carry you.", event = "glide", count = 1, reward = { coins = 100 } },
	{ id = 3, title = "A second egg", text = "A nest grows with eggs. Find one in the meadow.", event = "eggInc", count = 2, reward = { coins = 100 } },
	{ id = 4, title = "Berries", text = "Hungry dragons grow slow. Buy berries at my stall.", event = "feed", count = 1, reward = { coins = 150 } },
	{ id = 5, title = "Growing up", text = "Raise one to a juvenile and ride it.", event = "ride", count = 1, reward = { coins = 300 } },
	{ id = 6, title = "Two in the nest", text = "Two dragons earn more than one. Hatch another.", event = "hatch", count = 2, reward = { minutes = 3 } },
	{ id = 7, title = "The Cliffs", text = "The north cliffs hold better eggs. Glide from the north ledge.", event = "eggInc_Cliffs", count = 1, reward = { egg = "Cliffs", coins = 200 } },
	{ id = 8, title = "Take to the sky", text = "An adult dragon flies. Raise one and take off.", event = "fly", count = 1, reward = { minutes = 5 } },
	{ id = 9, title = "Egg hunter", text = "Five eggs found. You have the eye.", event = "eggFound", count = 5, reward = { minutes = 4 } },
	{ id = 10, title = "Ascension", text = "Strong nest, strong rider. Ascend.", event = "ascension", count = 1, reward = { minutes = 8 } },
	{ id = 11, title = "Four dragons", text = "Four hatched. The nest is getting loud.", event = "hatch", count = 4, reward = { minutes = 6 } },
	{ id = 12, title = "Hot Springs", text = "Ride across the bridge. The springs are warm.", event = "eggInc_Springs", count = 1, reward = { egg = "Springs" } },
	{ id = 13, title = "Six dragons", text = "Six. I had six once.", event = "hatch", count = 6, reward = { minutes = 8 } },
	{ id = 14, title = "The Elder", text = "Wait for the first elder. Patience is a rider's wing.", event = "elder", count = 1, reward = { minutes = 10 } },
	{ id = 15, title = "The Index", text = "Ten pages filled. Here - a Rare egg, my gift.", event = "index", count = 10, reward = { egg = "Meadow", minRarity = "Rare" } },
	-- 2.9 (09 §3): update 1 Aurora, chapter 1 "The Great Egg" - five Old Ash notes around the island (Services/LiveOps, Config.LiveOps.scrolls)
	-- the scrollN event is sent by LiveOps only when this errand is current
	{ id = 16, update = 1, title = "Lost notes", text = "A storm took my notes on the Great Egg. One fell in the meadow.", event = "scroll1", count = 1, reward = { minutes = 10 } },
	{ id = 17, update = 1, title = "Cliff notes", text = "The second note caught on the north cliffs. Glide and grab it.", event = "scroll2", count = 1, reward = { minutes = 12 } },
	{ id = 18, update = 1, title = "Wet ink", text = "The third flew to the springs. Find it before the steam does.", event = "scroll3", count = 1, reward = { minutes = 12 } },
	{ id = 19, update = 1, title = "High notes", text = "The fourth is up on the summit. Only a flyer gets there.", event = "scroll4", count = 1, reward = { minutes = 15 } },
	{ id = 20, update = 1, title = "The Great Egg", text = "The last note is behind my stall. Read it - and take what it hides.", event = "scroll5", count = 1, reward = { egg = "Cliffs", minutes = 15 } },
	-- update 2 Cinder, chapter 2 "Ember notes" - scrolls 6-10
	{ id = 21, update = 2, title = "Warm ashes", text = "My notes on the first {Ember} dragon blew off the plaza. One landed in the meadow.", event = "scroll6", count = 1, reward = { minutes = 10 } },
	{ id = 22, update = 2, title = "Smoke on the cliffs", text = "The second note is on the cliffs, still smoking. Glide down and grab it.", event = "scroll7", count = 1, reward = { minutes = 12 } },
	{ id = 23, update = 2, title = "Hot ink", text = "The third drifted to the springs. Hot water, hot ink.", event = "scroll8", count = 1, reward = { minutes = 12 } },
	{ id = 24, update = 2, title = "Embers above", text = "The fourth rode the heat up to the summit. Fly after it.", event = "scroll9", count = 1, reward = { minutes = 15 } },
	{ id = 25, update = 2, title = "The first flame", text = "The last note fell by my stall. Read it and keep the warmth.", event = "scroll10", count = 1, reward = { egg = "Springs", minutes = 15 } },
	-- update 3 Pearl Tide, chapter 3 - events from the moment the errand was received (fresh)
	{ id = 26, update = 3, fresh = true, title = "Pearl springs", text = "Pearls rise at the springs when stars fall. Bring me three Springs eggs.", event = "eggInc_Springs", count = 3, reward = { minutes = 12 } },
	{ id = 27, update = 3, fresh = true, title = "Born in weather", text = "Hatch a dragon in a storm, a starfall or an aurora. They come out different.", event = "hatchWeather", count = 1, reward = { minutes = 12 } },
	{ id = 28, update = 3, fresh = true, title = "A bigger storm", text = "The {StormDragon} grew. Help catch 16 of its shards.", event = "shard", count = 16, reward = { minutes = 15 } },
	{ id = 29, update = 3, fresh = true, title = "Tidal winds", text = "The winds are strong this week. Fly through 10 wind rings.", event = "ring", count = 10, reward = { minutes = 12 } },
	{ id = 30, update = 3, fresh = true, title = "Three more", text = "Three new hatchlings since the pearls came. Show me.", event = "hatch", count = 3, reward = { egg = "Cliffs", minutes = 15 } },
	-- update 4 Nightfall, chapter 4 "Night notes" - scrolls 11-15
	{ id = 31, update = 4, title = "Night notes", text = "The night wind took my last notes. One glows in the meadow.", event = "scroll11", count = 1, reward = { minutes = 12 } },
	{ id = 32, update = 4, title = "Sunset cliffs", text = "One hides on the cliffs, where the sun sets first.", event = "scroll12", count = 1, reward = { minutes = 12 } },
	{ id = 33, update = 4, title = "Moon on the water", text = "One floats by the springs. The moon shows the way.", event = "scroll13", count = 1, reward = { minutes = 15 } },
	{ id = 34, update = 4, title = "Close to the stars", text = "One is up on the summit, closest to the stars.", event = "scroll14", count = 1, reward = { minutes = 15 } },
	{ id = 35, update = 4, title = "Nightfall", text = "The last is by my stall. Read it under the night sky.", event = "scroll15", count = 1, reward = { egg = "Summit", minutes = 15 } },
}
Quests.List = LIST
Quests.Total = 15 -- the errands of the test (D0); with updates - Quests.total(live)

-- how many errands are open with live running updates (Core/LiveOps.live)
-- the one-dragon day - an errand is unreachable if it asks for a second egg, more dragons, found eggs,
-- cliff / bath eggs or Index pages (dragons give them)
function Quests.dayOneSkip(q: Quest): boolean
	local e = q.event
	if (e == "eggInc" or e == "hatch") and q.count >= 2 then
		return true
	end
	return e == "eggFound" or e == "index" or e == "eggInc_Cliffs" or e == "eggInc_Springs"
end

function Quests.total(live: number?): number
	local n = 0
	for _, q in LIST do
		if (q.update or 0) <= (live or 0) then
			n += 1
		end
	end
	return n
end

-- the step by number; nil - no such step or its update has not started yet
function Quests.get(step: number, live: number?): Quest?
	local q = Quests.List[step]
	if q and (q.update or 0) > (live or 0) then
		return nil
	end
	return q
end

-- how much is accumulated for the step (for fresh - above the counter at the moment the step became current)
function Quests.count(st: State, q: Quest): number
	local c = (st.counters or {})[q.event] or 0
	if q.fresh then
		local base = st.keeper and st.keeper.base and st.keeper.base[tostring(q.id)]
		return math.max(0, c - (if typeof(base) == "number" then base else c))
	end
	return c
end

-- remember the counter of the current fresh step (once; called when the step became current and its update is running)
function Quests.markBase(st: State, live: number?)
	local q = Quests.get((st.keeper or { step = 1 }).step or 1, live)
	if not q or not q.fresh then
		return
	end
	st.keeper.base = st.keeper.base or {}
	local key = tostring(q.id)
	if (st.keeper.base :: any)[key] == nil then
		(st.keeper.base :: any)[key] = (st.counters or {})[q.event] or 0
	end
end

-- whether the step counter is reached
function Quests.ready(st: State, q: Quest): boolean
	return Quests.count(st, q) >= q.count
end

-- the progress of the current step: k/n and the step itself (nil if all the open ones are closed)
function Quests.progress(st: State, live: number?): (number, number, Quest?)
	local q = Quests.get((st.keeper or { step = 1 }).step or 1, live)
	if not q then
		return 0, 1, nil
	end
	local k = math.min(Quests.count(st, q), q.count)
	return k, q.count, q
end

-- a newcomer - no dragons, no eggs (in the hands, on the shelf, in a bowl), has not taken from the table yet:
-- the Keeper's callout shows the greeting Strings.Keeper.welcome; after the first egg pickup - the text of the current errand (as before)
function Quests.newcomer(data: any): boolean
	if typeof(data) ~= "table" then
		return false
	end
	if typeof(data.dragons) == "table" and next(data.dragons) ~= nil then
		return false
	end
	local eggs = data.eggs
	if typeof(eggs) == "table" then
		if eggs.carry ~= nil then
			return false
		end
		if typeof(eggs.shelf) == "table" and #eggs.shelf > 0 then
			return false
		end
		if typeof(eggs.incubating) == "table" and next(eggs.incubating) ~= nil then
			return false
		end
	end
	local ob = data.onboarding
	if typeof(ob) == "table" and typeof(ob.table) == "table" and next(ob.table) ~= nil then
		return false
	end
	return true
end

-- the reward caption (the strings from Strings.Quests, the substitution {n}/{zone}); tr - the translation of the string into the player's language
-- (the client passes Loc.t; the template and the zone are translated, the numbers are not)
function Quests.rewardText(q: Quest, S: { [string]: string }, tr: ((string) -> string)?): string
	local parts = {}
	local t1: (string) -> string = tr or function(s: string): string
		return s
	end
	local function fmt(s: string, t: { [string]: any }): string
		return (string.gsub(t1(s), "{(%w+)}", function(k)
			return if t[k] ~= nil then tostring(t[k]) else ""
		end))
	end
	if q.reward.egg then
		table.insert(parts, if q.reward.minRarity == "Rare" then t1(S.rewardRare) else fmt(S.rewardEgg, { zone = t1(q.reward.egg) }))
	end
	if q.reward.minutes then
		table.insert(parts, fmt(S.rewardMinutes, { n = q.reward.minutes }))
	end
	if q.reward.coins then
		table.insert(parts, fmt(S.rewardCoins, { n = q.reward.coins }))
	end
	return table.concat(parts, " + ")
end

return Quests
