--!strict
-- the newcomer's path by seconds (a real walkthrough: the hatch 23 s, the ledge 36, the coins 40, the feed 43, the teen 63, the ride 86, the adult 93,
-- the ambush in waves) via Core/Hints.goal; darting = the target A -> B -> A within <= 25 s. Run: luau tests/hints_flow_spec.luau
local Config = require("../src/shared/Config")
local Hints = require("../src/shared/Core/Hints")

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then " | " .. tostring(detail) else ""))
	end
end

-- the newcomer's snapshot at second t; wave - the ambush waves (on/off every period s), golden - the golden nest exists, taken - stolen
local function snap(t: number, o: { wavePeriod: number, potRate: number, collectEvery: number }): any
	local s: any = { tableFree = 0, carry = false, dragons = 0, incubating = 0, pot = 0, coins = 0, eggNear = false, oneDragonDay = true }
	if t < 23 then
		s.raidNear = t < 12
		s.carry = t >= 12
		s.carryRaid = if t >= 12 then 0 else nil
		return s
	end
	s.dragons = 1
	s.companionStage = if t < 63 then 0 elseif t < 93 then 1 else 2
	s.glideDone = t >= 36
	s.coinsDone = t >= 40
	s.fedDone = t >= 43
	s.rodeDone = t >= 86
	s.flewDone = false
	s.mounted = t >= 86 and t < 120 -- at the golden nest the server dismounts (closer than 35)
	s.flying = false
	s.glowEgg = t >= 88 -- the golden nest appears after the first ride
	s.glowPending = true
	-- the ambush: the waves come and go
	s.gloomWave = t >= 33 and math.floor((t - 33) / o.wavePeriod) % 2 == 0
	s.gloomGuardian = false
	s.combatStage = 0
	-- the pile grows potRate/s, the player collects it every collectEvery s
	local since = (t - 23) % o.collectEvery
	s.pot = math.floor(since * o.potRate)
	s.coins = 500
	return s
end

local function run(o: any): ({ { t: number, k: string } }, { string })
	local seq: { { t: number, k: string } } = {}
	for t = 0, 180, 0.5 do
		local g = Hints.goal(snap(t, o), Config.Hints :: any)
		local k = if g then g.kind else "-"
		if #seq == 0 or seq[#seq].k ~= k then
			table.insert(seq, { t = t, k = k })
		end
	end
	local flips: { string } = {}
	for i = 3, #seq do
		local a, b, c = seq[i - 2], seq[i - 1], seq[i]
		if a.k == c.k and c.t - a.t <= 25 then
			table.insert(flips, string.format("%.0f-%.0f s: %s -> %s -> %s", a.t, c.t, a.k, b.k, c.k))
		end
	end
	return seq, flips
end

for _, o in { { wavePeriod = 4, potRate = 30, collectEvery = 60 }, { wavePeriod = 8, potRate = 30, collectEvery = 45 }, { wavePeriod = 2, potRate = 60, collectEvery = 30 } } do
	local seq, flips = run(o)
	local line = {}
	for _, e in seq do
		table.insert(line, string.format("%.0f:%s", e.t, e.k))
	end
	print(string.format("waves %d s, pile %d/s: %s", o.wavePeriod, o.potRate, table.concat(line, " ")))
	check(string.format("no arrow darting (waves %d s, pile %d/s)", o.wavePeriod, o.potRate), #flips == 0, table.concat(flips, "; "))
	local fight = false
	for _, e in seq do
		if e.k == "gloom" or e.k == "guardian" or e.k == "sky" or e.k == "skyUp" then
			fight = true
		end
	end
	check("combat does not move the arrow (no gloom/guardian/sky/skyUp targets)", not fight)
end

print(string.format("hints_flow_spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("hints_flow_spec failed")
end
