--!strict
-- dragon voices and the hatch ladder by rarity (spec 03 §10). Run from the repository root:
-- luau tests/voices_spec.luau
local Config = require("../src/shared/Config")
local Content = require("../src/shared/Content")
local Voices = require("../src/shared/Core/Voices")

local V = (Content :: any).Voices
local S = Content.Sounds :: any
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end
local function isId(x: any): boolean
	return typeof(x) == "number" and x > 1e9 and x == math.floor(x)
end

-- the ladder: every rarity has its own step, its own files (not library stubs), the music ducking grows with rarity
local prevDuck = 0
for _, r in Voices.RARITIES do
	local name = Voices.hatchName(r)
	check("step " .. r .. " in Content.Sounds", isId(S[name]), S[name])
	local d = (Content :: any).Music.duck[name]
	check("music ducking under " .. name, typeof(d) == "number" and d >= prevDuck, d)
	prevDuck = d or prevDuck
end
check("6 different files for 6 steps", (function()
	local seen = {}
	for _, r in Voices.RARITIES do
		seen[S[Voices.hatchName(r)]] = true
	end
	local n = 0
	for _ in seen do
		n += 1
	end
	return n == 6
end)())
check("an unknown rarity - the common hatch", Voices.hatchName("Weird") == "hatch" and Voices.hatchName(nil) == "hatch" and S.hatch ~= nil)
check("Mythic starts with the shaking, the rest at the crack", Voices.hatchStartsEarly("Mythic") and not Voices.hatchStartsEarly("Legendary")
	and not Voices.hatchStartsEarly("Common"))
check("Legendary+ longer than the scene: ducking >= the Legendary sky", (Content :: any).Music.duck.hatch_Legendary >= Config.UI.hatchScene.legend.seconds)
check("the fanfare stub is removed (the Legendary step instead of it)", S.fanfare == nil)
for _, k in { "egg_crack", "feed", "wing", "land" } do
	check("own sound " .. k, isId(S[k]), S[k])
end

-- voices: every stage (Config.Stages) answers every occasion, the ids are real, the pitch within sane bounds
local kinds = { "birth", "call", "happy", "roar" }
for st = 0, #Config.Stages - 1 do
	for _, k in kinds do
		for _, r in { 0, 0.34, 0.67, 0.999 } do
			local e = Voices.pick(V, st, k, r)
			check(("voice of stage %d occasion %s r=%.2f"):format(st, k, r), e ~= nil and isId(e.id) and e.speed >= 0.6 and e.speed <= 1.6,
				e and (tostring(e.id) .. " x" .. e.speed))
		end
	end
end
check("baby: its own first squeak", V.stages[0].birth ~= nil and #V.stages[0].birth >= 1)
check("the baby has no roar - its usual voice", (function()
	local e = Voices.pick(V, 0, "roar", 0) :: any
	for _, c in V.stages[0].call do
		if c.id == e.id then
			return true
		end
	end
	return false
end)())
local adult = Voices.pick(V, 2, "roar", 0) :: any
local elder = Voices.pick(V, 3, "roar", 0) :: any
check("Elder = adult lower (elderSpeed)", elder.id == adult.id and math.abs(elder.speed - adult.speed * V.elderSpeed) < 1e-9 and V.elderSpeed < 1)
check("the adult roars with 2 variants", #V.stages[2].roar >= 2)
check("stage nil - like a baby", (Voices.pick(V, nil, "call", 0) :: any).id == V.stages[0].call[1].id)
check("r at the edge does not go beyond the list", Voices.pick(V, 2, "call", 0.9999999) ~= nil)
check("life at the nest less often than 20 s", Voices.nextIdle(V, 0) >= 20 and Voices.nextIdle(V, 0.999) <= 90)
check("roar cooldown", typeof(V.roarCooldown) == "number" and V.roarCooldown >= 10)
check("3D: fades toward max > min", V.rolloff.max > V.rolloff.min and V.rolloff.min > 0)
check("Feed all: no more than 3 voices", V.fedMax >= 1 and V.fedMax <= 3)

print(("voices_spec: passed %d, failed %d"):format(passed, failed))
if failed > 0 then
	error("voices_spec failed")
end
