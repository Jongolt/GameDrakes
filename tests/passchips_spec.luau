--!strict
-- which pass buttons are visible next to the coins. Run from the repository root:
-- luau tests/passchips_spec.luau
local Config = require("../src/shared/Config")
local Strings = require("../src/shared/Strings")
local ShopIds = require("../src/shared/ShopIds")
local Shop = require("../src/shared/Core/Shop")
local PassChips = require("../src/shared/Core/PassChips")

Shop.setup(Config.Shop)
local C = Config.UI.passChips
local passed, failed = 0, 0
local function check(name: string, cond: boolean)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name)
	end
end

local ok = { robuxOk = true, mounted = false, rate = 5 }
local function same(a: { string }, b: { string }): boolean
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

check("Config: on, two buttons", C.on == true and #C.list == 2 and C.minPx >= 40)
for _, c in C.list do
	local sku = Shop.get(c.key)
	check(c.key .. ": a catalog pass with a Roblox id", sku ~= nil and sku.kind == "pass" and ShopIds.passes[c.key] ~= nil)
	check(c.key .. ": the button word and the card lines", typeof((Strings.PassCard.chip :: any)[c.word]) == "string"
		and typeof((Strings.PassCard.lines :: any)[c.key]) == "table" and #(Strings.PassCard.lines :: any)[c.key] == 3)
end
check("all conditions met - both in order", same(PassChips.visible({ owned = {} }, ok, C), { "X2Coins_299", "AutoCollect_149" }))
check("no owned profile - both", #PassChips.visible({}, ok, C) == 2)
check("before 3:00 of the first session - none", #PassChips.visible({}, { robuxOk = false, mounted = false, rate = 5 }, C) == 0)
check("riding - none", #PassChips.visible({}, { robuxOk = true, mounted = true, rate = 5 }, C) == 0)
check("a Roblox window on screen (blocked) - none", #PassChips.visible({}, { robuxOk = true, mounted = false, rate = 5, blocked = true }, C) == 0)
check("the nest does not earn yet - none", #PassChips.visible({}, { robuxOk = true, mounted = false, rate = 0 }, C) == 0)
check("bought x2 - only Auto", same(PassChips.visible({ owned = { x2 = true } }, ok, C), { "AutoCollect_149" }))
check("bought both - none", #PassChips.visible({ owned = { x2 = true, autoCollect = true } }, ok, C) == 0)
check("VIP does not interfere", #PassChips.visible({ owned = { vip = true } }, ok, C) == 2)
check("off - none", #PassChips.visible({}, ok, { on = false, list = C.list }) == 0)
check("a product instead of a pass - skipped", #PassChips.visible({}, ok, { on = true, list = { { key = "Treats_1_49" } } }) == 0)
check("a foreign key - skipped", #PassChips.visible({}, ok, { on = true, list = { { key = "Nope_1" } } }) == 0)

-- layout: to the right of the pill in a row, not leaving the screen and outside the Roblox player list zone on PC
local KEYS = { "X2Coins_299", "AutoCollect_149" }
local phone = { 316, 4, 495, 32 } -- the pill on a phone 812x317
local L = PassChips.layout(phone, 812, 317, KEYS, C, PassChips.zones(812, 317, true, true, C))
local a, b = L.X2Coins_299, L.AutoCollect_149
check("phone: both to the right of the pill, x2 first", a ~= nil and b ~= nil and a[1] >= phone[3] + C.gap and b[1] >= a[3] + C.gap)
check("phone: height minPx, the top not above 2 px, no overlap", a[4] - a[2] == C.minPx and a[2] >= 2 and b[2] >= 2 and a[3] <= b[1])
check("phone: inside the screen", b[3] <= 812 - 2 and b[4] <= 317)
local only = PassChips.layout(phone, 812, 317, { "AutoCollect_149" }, C, {})
check("x2 bought: Auto moves to the pill", only.AutoCollect_149 ~= nil and only.AutoCollect_149[1] == phone[3] + C.gap)
local pcz = PassChips.zones(812, 317, false, true, C)
check("PC: the player list zone at the top right", #pcz == 1 and pcz[1][1] == 812 - C.playerListW)
check("PC without the player list / phone - no zones", #PassChips.zones(812, 317, false, false, C) == 0 and #PassChips.zones(812, 317, true, true, C) == 0)
local pc812 = PassChips.layout(phone, 812, 317, KEYS, C, pcz)
check("PC 812 (a phone-sized window): both would touch the player list (the zone from 552 px) - not placed", next(pc812) == nil)
local function noHit(L2: any, zones: any): boolean
	for _, r in L2 do
		for _, z in zones do
			if r[1] < z[3] and z[1] < r[3] and r[2] < z[4] and z[2] < r[4] then
				return false
			end
		end
	end
	return true
end
check("PC 812: nothing touches the zone", noHit(pc812, pcz))
local p1200 = { 468, 7, 732, 42 }
local L1200 = PassChips.layout(p1200, 1200, 617, KEYS, C, PassChips.zones(1200, 617, false, true, C))
check("PC 1200x675: both, outside the zone", L1200.X2Coins_299 ~= nil and L1200.AutoCollect_149 ~= nil and noHit(L1200, PassChips.zones(1200, 617, false, true, C)))
local p1024 = { 400, 6, 624, 36 }
local z1024 = PassChips.zones(1024, 517, false, true, C)
check("PC 1024: nothing touches the zone", noHit(PassChips.layout(p1024, 1024, 517, KEYS, C, z1024), z1024))
local tiny = PassChips.layout({ 120, 4, 280, 32 }, 330, 300, KEYS, C, {})
check("narrow screen: what does not fit is not placed, inside the screen", tiny.AutoCollect_149 == nil and (tiny.X2Coins_299 == nil or tiny.X2Coins_299[3] <= 328))
check("empty - empty", next(PassChips.layout(phone, 812, 317, {}, C, {})) == nil)

print(string.format("passchips_spec: %d ok, %d fail", passed, failed))
if failed > 0 then
	error("passchips_spec: there are failures")
end
