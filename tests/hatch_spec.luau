--!strict
-- the hatch scene against spec 02 §2 (0:10-0:13, 3:30) and 03 §2. Run from the repository root: luau tests/hatch_spec.luau
local Config = require("../src/shared/Config")
local HatchFx = require("../src/shared/Core/HatchFx")

local HS = Config.UI.hatchScene
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

-- which scene kind
check("1st hatch Common - the full scene", HatchFx.kind("Common", 1) == "full")
check("1st hatch Uncommon - full", HatchFx.kind("Uncommon", 1) == "full")
check("2nd Common - short (02 §2 line 3:30)", HatchFx.kind("Common", 2) == "short")
check("2nd Uncommon - full (02 §2: '1 in 4' full frame)", HatchFx.kind("Uncommon", 2) == "full")
check("3rd Common and Uncommon - short (03 §2)", HatchFx.kind("Common", 3) == "short" and HatchFx.kind("Uncommon", 7) == "short")
for _, r in { "Rare", "Epic", "Legendary", "Mythic" } do
	check("Rare+ always full: " .. r, HatchFx.kind(r, 50) == "full")
end
check("the number unknown - full", HatchFx.kind("Common", nil) == "full")
check("an unknown rarity - full", HatchFx.kind("Weird", 9) == "full")

-- the durations (03 §2: 3 s and 1.5 s; 02 §2: the control not longer than 5 s)
local full = HatchFx.plan("Rare", 4, HS)
local short = HatchFx.plan("Common", 4, HS)
check("full 2.5-3.5 s", full.total >= 2.5 and full.total <= 3.5, full.total)
check("short 1.5 s", math.abs(short.total - 1.5) < 1e-9, short.total)
check("full: the camera control < 5 s", HatchFx.controlSeconds(full) > 0 and HatchFx.controlSeconds(full) < 5, HatchFx.controlSeconds(full))
check("short: the camera is not taken", HatchFx.controlSeconds(short) == 0)
for _, p in { full, short } do
	local t = p.t
	check(p.kind .. ": the order shake -> crack -> hatchling -> banner -> end", t.shakeFrom < t.crackAt and t.crackAt <= t.popAt
		and t.popAt < t.bannerAt and t.bannerAt < t.total)
	check(p.kind .. ": the hatchling's bounce of 0.7 s fits before the end", t.popAt + 0.7 <= t.total + 1e-9, t.popAt + 0.7)
end
check("full: the camera moved in before the crack", full.t.camIn <= full.t.crackAt and full.t.camOutAt < full.total)
check("the shake not shorter than 0.5 s (02 §2)", full.t.crackAt - full.t.shakeFrom >= 0.5, full.t.crackAt - full.t.shakeFrom)
check("the server holds the egg until the crack of the full scene", HS.holdSeconds >= full.t.crackAt)

-- Legendary+
local leg = HatchFx.plan("Legendary", 10, HS)
local myth = HatchFx.plan("Mythic", 10, HS)
check("Legendary: legend, not mythic", leg.legend and not leg.mythic)
check("Mythic: legend and mythic", myth.legend and myth.mythic)
check("Epic: without legend", not HatchFx.plan("Epic", 1, HS).legend)
check("Legendary: the effect ~5 s after the 3-second scene (03 §2 '3 s + 5 s')", leg.fxEnd - leg.total >= 4 and leg.fxEnd - leg.total <= 5.5, leg.fxEnd - leg.total)
check("Legendary: the control not longer than the ordinary scene", HatchFx.controlSeconds(leg) == HatchFx.controlSeconds(full))

local over = HatchFx.plan("Legendary", 1, HS, true)
check("a scene on top of a running one - short, the Legendary effect is kept", over.kind == "short" and over.legend and HatchFx.controlSeconds(over) == 0)

-- the rocking grows
local a1 = HatchFx.shakeDeg(full, full.t.shakeFrom + 0.05, HS.shake)
local a2 = HatchFx.shakeDeg(full, full.t.crackAt - 0.05, HS.shake)
check("the rocking grows toward the crack", a2 > a1 and a2 <= HS.shake.degTo, string.format("%.2f -> %.2f", a1, a2))
check("before the shake and after the crack the egg is still", HatchFx.shakeDeg(full, 0, HS.shake) == 0 and HatchFx.shakeDeg(full, full.t.crackAt, HS.shake) == 0)

-- everyone sees the dragon name - the Roblox rule (creator-docs chat/guidelines) requires a limit of not more than once a minute
local Strings = require("../src/shared/Strings")
local Remotes = require("../src/shared/Remotes")
check("the dragon name limit >= 60 s (the Roblox rule for text visible to others)", (Config.Names.renameCooldown or 0) >= 60, Config.Names.renameCooldown)
check("the name limit: the refusal code name_cooldown is declared and translated", table.find(Remotes.Reasons, "name_cooldown") ~= nil
	and typeof((Strings.Errors :: any).name_cooldown) == "string" and string.find((Strings.Errors :: any).name_cooldown, "{n}", 1, true) ~= nil)

print(string.format("hatch_spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("hatch_spec failed")
end
