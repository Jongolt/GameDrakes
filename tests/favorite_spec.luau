--!strict
-- when the "favorite" window. Run from the repository root: luau tests/favorite_spec.luau
local Config = require("../src/shared/Config")
local Favorite = require("../src/shared/Core/Favorite")

local F = Config.FavPrompt
local FL = { on = true, delay = 4, moment = "flight" } -- the previous rule (after the first flight) - for the old checks
local passed, failed = 0, 0
local function check(name: string, cond: boolean)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name)
	end
end

check("enabled in Config", F.on == true and typeof(F.delay) == "number" and F.delay > 0)
check("has not flown - no", not Favorite.due({ flew = false }, false, 0, 100, FL))
check("no onboarding - no", not Favorite.due(nil, false, 0, 100, FL))
check("flew, got off, delay passed - yes", Favorite.due({ flew = true }, false, 0, FL.delay, FL))
check("flew, got off, too early - no", not Favorite.due({ flew = true }, false, 0, FL.delay - 0.5, FL))
check("riding - no", not Favorite.due({ flew = true }, true, 0, 100, FL))
check("did not get off this session - no (no window at the entry)", not Favorite.due({ flew = true }, false, nil, 100, FL))
check("already asked - no (once per lifetime)", not Favorite.due({ flew = true, favAsked = 1792600000 }, false, 0, 100, FL))
check("disabled - no", not Favorite.due({ flew = true }, false, 0, 100, { on = false, delay = 1 }))
-- the moment "glow" (ask when the glowing dragon hatches) - F from Config
check("glow: the moment glow in Config", F.moment == "glow")
check("glow: the dragon has not hatched - no", not Favorite.due({ flew = true }, false, 0, 100, F, nil))
check("glow: hatched, delay passed, standing - yes (even without a flight)", Favorite.due({ flew = false }, false, nil, F.delay, F, 0))
check("glow: hatched, too early - no", not Favorite.due({ flew = true }, false, 0, F.delay - 0.5, F, 0))
check("glow: riding - no", not Favorite.due({ flew = true }, true, 0, 100, F, 0))
check("glow: already asked - no", not Favorite.due({ favAsked = 1792600000 }, false, 0, 100, F, 0))

print(string.format("favorite_spec: %d ok, %d fail", passed, failed))
if failed > 0 then
	error("favorite_spec failed")
end
