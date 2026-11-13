--!strict
-- which hatch scene to play (spec 03 §2, 02 §2). Pure logic: the client takes the timings (HatchScene, Banners)
-- the server - how long not to put a new egg into the bowl (Incubation). The numbers - Config.UI.hatchScene; the check tests/hatch_spec.luau.

local Eggs = require("./Eggs")

local HatchFx = {}

export type Plan = { kind: string, legend: boolean, mythic: boolean, t: { [string]: number }, total: number, fxEnd: number }

-- n - the player's hatch number (1 - the first; nil - unknown, counted as the first). short: Common/Uncommon from the 3rd and Common at the 2nd
function HatchFx.kind(rarity: string, n: number?): string
	local r = Eggs.rarityIndex(rarity)
	local k = n or 1
	if r >= 1 and r <= 2 and (k >= 3 or (k == 2 and r == 1)) then
		return "short"
	end
	return "full"
end

-- fxEnd - when the last effect fades (for Legendary+ the sky and the confetti run after the camera returns, the control is already with the player).
-- forceShort - a second scene on top of a running one (two bowls in a row): without the camera, the short timings
function HatchFx.plan(rarity: string, n: number?, cfg: any, forceShort: boolean?): Plan
	local kind = if forceShort then "short" else HatchFx.kind(rarity, n)
	local t = cfg[kind]
	local r = Eggs.rarityIndex(rarity)
	local legend = r >= Eggs.rarityIndex("Legendary")
	local total = t.total
	local fxEnd = total
	if legend then
		fxEnd = math.max(total, t.crackAt + cfg.legend.seconds)
	end
	return { kind = kind, legend = legend, mythic = r >= Eggs.rarityIndex("Mythic"), t = t, total = total, fxEnd = fxEnd }
end

-- how many seconds the camera control is taken from the player (full: until camOutAt; short - none)
function HatchFx.controlSeconds(plan: Plan): number
	return if plan.kind == "full" then plan.t.camOutAt else 0
end

-- the rocking amplitude (degrees) at moment t: from degFrom at shakeFrom to degTo at crackAt, outside the window 0
function HatchFx.shakeDeg(plan: Plan, t: number, shake: any): number
	local a, b = plan.t.shakeFrom, plan.t.crackAt
	if t < a or t >= b or b <= a then
		return 0
	end
	local k = (t - a) / (b - a)
	return shake.degFrom + (shake.degTo - shake.degFrom) * k * k
end

return HatchFx
