--!strict
-- 1.13 (spec 13, 02 §5): the first 10 minutes bot on the pure core (shared/Core) by the 02 §2 scenario - the median moments of the player actions,
-- the real growth timers, food (x2 for 5 min, the price 60 s of income, not less than 50), the Keeper quest 1-5 rewards. The bot policy:
-- after 1:45 it is at the nest, collects the pile every 5 s and feeds everyone it has coins for. Gates 02 §5: hatch <= 20 s,
-- glide <= 60 s, second egg <= 120 s, teen <= 180 s, adult <= 480 s. Run from the repository root:
-- luau tests/sim_first10.luau
-- the second 'live player' scenario per the 2.14 measurement (REPORT newcomer20 §1): hatch 0:18 (spawn on the plaza 86 m
-- from the table), the first food not earlier than 2:05 (berries at the stall per spec 02 1:45-2:00 + the walk), then feeds at the first chance;
-- gates spec 02 §5: teen <= 3:00, adult <= 8:00 (the '<= 7:20' share is printed for information). The firstborn timers
-- Config.Balance.firstDragon.growMin.
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Core/Economy")
local Growth = require("../src/shared/Core/Growth")
local Eggs = require("../src/shared/Core/Eggs")
local QuestsCore = require("../src/shared/Core/Quests")
local Dragons = require("../src/shared/Core/Dragons") -- 05 Add. 2.18: the dragon record by the same path as the server (firstborn - growAs)

local B = Config.Balance
local RAR = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
local MEADOW = B.zones.Meadow

-- the 02 §2 scenario moments (median), seconds
local T = { pick1 = 8, place1 = 11, glide = 55, pick2 = 85, place2 = 105, nestFrom = 105, collectEvery = 5, rideAfter = 15 }

local function reward(id: number): number
	return (QuestsCore.List[id].reward.coins or 0) :: number
end

type Dr = { rarity: string, stage: number, stageEndsAt: number?, fedUntil: number?, size: string, shiny: boolean }

local function newDragon(rarity: string, now: number, first: boolean?): Dr
	local inv = { dragons = {}, nestOrder = {}, companion = nil, nextUid = 1 }
	return Dragons.fromEgg(inv :: any, { element = "ember", rarity = rarity, shiny = false, size = "normal" }, now, false, B, first) :: any
end

-- one run: r1 - the rarity of the first egg (from the table), r2 - of the second (meadow); returns the event moments
-- opts: place1 - the moment of placing the first egg (s), feedFrom - the bot does not feed before this second (a live player at the stall ~2:05)
type Opts = { place1: number?, feedFrom: number? }
local function run(r1: string, r2: string, maxT: number, opts: Opts?): { [string]: number? }
	local o: Opts = opts or {}
	local place1 = o.place1 or T.place1
	local feedFrom = o.feedFrom or 0
	local ev: { [string]: number? } = {}
	local coins, pot = 0, 0
	local dragons: { Dr } = {}
	local hatch1 = place1 + Eggs.incubationSeconds({ rarity = r1, cold = false } :: any, { firstEgg = true }, B)
	local hatch2 = T.place2 + Eggs.incubationSeconds({ rarity = r2, cold = false } :: any, { firstEgg = false }, B)
	ev.hatch1 = hatch1
	ev.glide = T.glide
	ev.egg2 = T.place2
	local fedOnce, rode = false, false
	for t = 0, maxT do
		if t == hatch1 then
			table.insert(dragons, newDragon(r1, t, true))
			coins += reward(1)
		end
		if t == T.glide then
			coins += reward(2)
		end
		if t == T.place2 then
			coins += reward(3)
		end
		if t == hatch2 then
			table.insert(dragons, newDragon(r2, t))
			ev.hatch2 = t
		end
		-- income into the pile
		for _, d in dragons do
			pot += Economy.dragonIncome(d :: any, B)
			if Growth.tick(d :: any, t, B) then
				if d == dragons[1] and d.stage == 1 and not ev.teen then
					ev.teen = t
				elseif d == dragons[1] and d.stage == 2 and not ev.adult then
					ev.adult = t
				end
			end
		end
		-- at the nest: collecting the pile and food
		local atNest = t >= T.nestFrom or (t >= hatch1 and t <= 30)
		if atNest and t % T.collectEvery == 0 then
			coins += pot
			pot = 0
			for _, d in dragons do
				if d.stage < 2 and t >= feedFrom and not Growth.isFed(d :: any, t) then
					local price = Economy.feedPrice(d :: any, 0, B)
					if coins >= price then
						local ok = Growth.feed(d :: any, t, B)
						if ok then
							coins -= price
							if not fedOnce then
								fedOnce = true
								coins += reward(4)
								ev.feed1 = t
							end
						end
					end
				end
			end
		end
		if ev.teen and not rode and t >= (ev.teen :: number) + T.rideAfter then
			rode = true
			coins += reward(5)
		end
	end
	return ev
end

local function fmtT(s: number?): string
	if not s then
		return "  -  "
	end
	return string.format("%2d:%02d", s // 60, s % 60)
end

print("First 10 minutes bot (02 §2, 05 §2): the moments for the first dragon by the rarity of the first egg (the second - Common)")
print("rarity     | hatch   | food 1 | teen      | adult    | gates: teen<=3:00, adult<=8:00")
for _, r in RAR do
	local ev = run(r, "Common", 3600)
	print(string.format("%-10s |  %s  | %s |   %s   |  %s  | %s %s", r, fmtT(ev.hatch1), fmtT(ev.feed1), fmtT(ev.teen), fmtT(ev.adult),
		if (ev.teen or 9999) <= 180 then "teen OK" else "teen NO", if (ev.adult or 9999) <= 480 then "adult OK" else "adult NO"))
end

-- Monte Carlo over the meadow table (the first and the second egg)
local seed = 12345
local function rnd(): number
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end
local function rollMeadow(): string
	local sum = 0
	for i = 1, #RAR do
		sum += MEADOW[i] or 0
	end
	local x = rnd() * sum
	for i = 1, #RAR do
		x -= MEADOW[i] or 0
		if x <= 0 then
			return RAR[i]
		end
	end
	return "Common"
end
local N = 2000
local hit = { teen3 = 0, adult8 = 0, adult10 = 0, adult15 = 0 }
for _ = 1, N do
	local ev = run(rollMeadow(), rollMeadow(), 1800)
	if (ev.teen or 9999) <= 180 then hit.teen3 += 1 end
	if (ev.adult or 9999) <= 480 then hit.adult8 += 1 end
	if (ev.adult or 9999) <= 600 then hit.adult10 += 1 end
	if (ev.adult or 9999) <= 900 then hit.adult15 += 1 end
end
print(string.format("Monte Carlo %d newcomers (meadow: %s): teen <= 3:00 - %d%%; adult <= 8:00 - %d%%, <= 10:00 - %d%%, <= 15:00 - %d%%",
	N, table.concat(MEADOW, "/"), math.floor(hit.teen3 * 100 / N), math.floor(hit.adult8 * 100 / N), math.floor(hit.adult10 * 100 / N), math.floor(hit.adult15 * 100 / N)))

-- a live player (measurement 2.14): the egg in the bowl at 0:15 -> hatch 0:18, the first food not earlier than 2:05; gates 02 §5 teen <= 3:00, adult <= 8:00
local REAL: Opts = { place1 = 15, feedFrom = 125 }
print("")
print("Live player (hatch 0:18, the first food not earlier than 2:05): the first dragon by rarity; gates 02 §5 teen <= 3:00, adult <= 8:00")
print("rarity     | hatch   | food 1 | teen      | adult    |")
local failed = 0
for _, r in RAR do
	local ev = run(r, "Common", 3600, REAL)
	local okTeen, okAdult = (ev.teen or 9999) <= 180, (ev.adult or 9999) <= 480
	if not okTeen or not okAdult then
		failed += 1
	end
	print(string.format("%-10s |  %s  | %s |   %s   |  %s  | %s %s", r, fmtT(ev.hatch1), fmtT(ev.feed1), fmtT(ev.teen), fmtT(ev.adult),
		if okTeen then "teen OK" else "teen NO", if okAdult then "adult OK" else "adult NO"))
end
local hitR = { teen3 = 0, adult720 = 0, adult8 = 0 }
for _ = 1, N do
	local ev = run(rollMeadow(), rollMeadow(), 1800, REAL)
	if (ev.teen or 9999) <= 180 then hitR.teen3 += 1 end
	if (ev.adult or 9999) <= 440 then hitR.adult720 += 1 end
	if (ev.adult or 9999) <= 480 then hitR.adult8 += 1 end
end
print(string.format("Monte Carlo %d live newcomers: teen <= 3:00 - %d%%; adult <= 8:00 - %d%% (for information: <= 7:20 - %d%%)",
	N, math.floor(hitR.teen3 * 100 / N), math.floor(hitR.adult8 * 100 / N), math.floor(hitR.adult720 * 100 / N)))
if failed > 0 or hitR.teen3 < N or hitR.adult8 < N then
	error("sim_first10: the live player gates are not passed")
end
