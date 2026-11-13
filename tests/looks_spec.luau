--!strict
-- The appearance showcase specification (spec 07 add. 2.6): Core/Looks against Config.Looks, Strings, Remotes and the Core/Shop granting -
-- a preset per one dragon (the move, the take-off, the Solstice element), the data order at the entry, the nest skin priority and the player's choice,
-- the nest part roles, the aura, the trail, the tags above the head, the scarf, the profile keys for ProfileStore.
-- Run from the repository root: luau tests/looks_spec.luau

local Config = require("../src/shared/Config")
local Strings = require("../src/shared/Strings")
local Remotes = require("../src/shared/Remotes")
local Shop = require("../src/shared/Core/Shop")
local Looks = require("../src/shared/Core/Looks")
local Dragons = require("../src/shared/Core/Dragons")

local L: any = Config.Looks
local SL: any = Strings.Looks
local SE: any = Strings.Errors
local RL: any = Remotes.List
local RR: any = Remotes.Reasons
local RateLimit: any = Config.RateLimit
local B = Config.Balance
local S = Config.Shop
Shop.setup(S)

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end
local function isRgb(c: any): boolean
	if typeof(c) ~= "table" or #c ~= 3 then
		return false
	end
	for _, v in c do
		if typeof(v) ~= "number" or v < 0 or v > 255 then
			return false
		end
	end
	return true
end

-- the config, the texts, the remote call -------------------------------------------------------------------
check("Config.Looks exists", typeof(L) == "table")
for _, id in L.presetOrder do
	local P = L.presets[id]
	check("preset in the config: " .. id, P ~= nil)
	check("preset color: " .. id, P ~= nil and isRgb(P.tint))
	check("the preset element exists: " .. id, P == nil or P.element == nil or table.find(Config.Elements, P.element) ~= nil)
	check("preset name: " .. id, typeof(SL.presets[id]) == "string")
end
check("Solstice only on Dusk (06 §8)", L.presets.solstice.element == "dusk")
check("Sunset on any element", L.presets.sunset.element == nil)
for _, id in L.nestSkinOrder do
	local SK = L.nestSkins[id]
	check("skin in the config: " .. id, SK ~= nil)
	for _, role in L.nestRoles do
		check("the color of role " .. role .. " in " .. id, SK ~= nil and isRgb(SK.colors[role]))
		local m = SK and SK.materials and SK.materials[role]
		check("the material of role " .. role .. " in " .. id, m == nil or (typeof(m) == "string" and m ~= "Limestone" and m ~= "Rock" and m ~= "Ground" and m ~= "Sand" and m ~= "Grass"), m)
	end
	check("skin name: " .. id, typeof(SL.skins[id]) == "string")
end
check("the skin priority royal > night > gilded > lagoon (17.10: + Night Sky)", L.nestSkinOrder[1] == "royal" and L.nestSkinOrder[2] == "night" and L.nestSkinOrder[3] == "gilded" and L.nestSkinOrder[4] == "lagoon")
check("the classic name", typeof(SL.skins.classic) == "string")
for _, id in L.auraOrder do
	local A = L.auras[id]
	check("aura: " .. id, A ~= nil and isRgb(A.colors[1]) and isRgb(A.colors[2]) and A.rate > 0 and A.rate <= 20)
end
for _, id in L.trailOrder do
	local T = L.trails[id]
	check("trail: " .. id, T ~= nil and isRgb(T.head) and isRgb(T.tail) and T.lifetime > 0 and T.widthOfHeight > 0 and T.minAir > 0)
end
for _, id in L.tag.titleOrder do
	check("title: " .. id, typeof(SL.titles[id]) == "string")
end
check("the VIP tag", SL.vipTag == "VIP" and isRgb(L.tag.vip) and isRgb(L.tag.title))
check("tag: MaxDistance ~60", L.tag.maxDistance >= 40 and L.tag.maxDistance <= 80)
check("not more than 3 color highlights (04 §9)", L.highlight.max >= 1 and L.highlight.max <= 3)
check("highlight: the range, the step, the fill, the frame tint", L.highlight.distance > 0 and L.highlight.every > 0 and L.highlight.fill > 0 and L.highlight.fill < 1 and L.highlight.viewport > 0 and L.highlight.viewport <= 1)
check("the trail check step", L.trailEvery > 0 and L.trailEvery <= 1)
check("tag: the rows and the offset", L.tag.width > 0 and L.tag.rowHeight > 0 and L.tag.above > 0 and typeof(L.tag.declutterRank) == "number" and L.tag.declutterRank > 0)
check("scarf: the colors", isRgb(L.scarf.color) and isRgb(L.scarf.fringe))
check("SetLook in Remotes", RL.SetLook ~= nil and RL.SetLook.kind == "RemoteFunction")
local kindArg = RL.SetLook and RL.SetLook.args and RL.SetLook.args[1]
check("SetLook kind - enum preset/nestSkin", kindArg ~= nil and kindArg.type == "enum" and table.find(kindArg.values, "preset") ~= nil and table.find(kindArg.values, "nestSkin") ~= nil)
check("the SetLook limit", (RateLimit.SetLook or 0) > 0)
for _, r in { "not_owned", "wrong_element" } do
	check("reason in Remotes: " .. r, table.find(RR, r) ~= nil)
	check("reason text: " .. r, typeof(SE[r]) == "string")
end
-- the preset and skin ids fit the SetLook schema (string max 16)
for _, id in L.presetOrder do
	check("preset id <= 16: " .. id, #id <= 16)
end
for _, id in L.nestSkinOrder do
	check("skin id <= 16: " .. id, #id <= 16)
end

-- the profile ---------------------------------------------------------------------------------------------
local NOW = 1000000
local function profile(): any
	local inv = Dragons.newInventory()
	local data: any = {
		coins = 100, pot = 0, ascension = 0, incubators = 1, shelfCap = 3, slots = { coins = 3 },
		eggs = { shelf = {}, incubating = {} }, items = { treats = 0, hatchNow = {}, growNow = {} }, owned = {}, boost = { secondsLeft = 0 },
		index = {}, quests = {}, rewards = {}, onboarding = {}, looks = { nestSkin = "" },
	}
	for k, v in inv :: any do
		data[k] = v
	end
	data.dragons = {
		a = { uid = "a", element = "ember", rarity = "Common", stage = 2, name = "A", inNest = true },
		b = { uid = "b", element = "dusk", rarity = "Rare", stage = 3, name = "B", inNest = true },
		c = { uid = "c", element = "dusk", rarity = "Epic", stage = 1, name = "C", inNest = true },
	}
	data.nestOrder = { "a", "b", "c" }
	return data
end
local function ctx(): Shop.Ctx
	return { now = NOW, rate = 10, B = B, S = S, elements = Config.Elements, rng = function()
		return 0.5
	end } :: any
end

-- the presets ---------------------------------------------------------------------------------------------
do
	local d = profile()
	check("without a purchase - not_owned", select(2, Looks.setPreset(d, "a", "sunset", L)) == "not_owned")
	check("an unknown preset - bad_request", select(2, Looks.setPreset(d, "a", "rainbow", L)) == "bad_request")
	check("no dragon - no_dragon", select(2, Looks.setPreset(d, "zz", "sunset", L)) == "no_dragon")
	check("take off without a preset - already", select(2, Looks.setPreset(d, "a", nil, L)) == "already")
	check("the card without purchases - empty", #Looks.cardPresets(d, "a", L) == 0)
	Shop.grant(d, "Preset_Sunset_99", ctx())
	check("Sunset is bought", Looks.ownsPreset(d, "sunset"))
	local ok, why, changed = Looks.setPreset(d, "a", "sunset", L)
	check("Sunset on ember", ok and why == nil and d.dragons.a.preset == "sunset" and #changed == 1 and changed[1] == "a", why)
	check("the Sunset wearer = a", Looks.holderOf(d, "sunset") == "a")
	check("a repeat - already", select(2, Looks.setPreset(d, "a", "sunset", L)) == "already")
	local cp = Looks.cardPresets(d, "a", L)
	check("card a: Sunset on", #cp == 1 and cp[1].id == "sunset" and cp[1].state == "on")
	local cpb = Looks.cardPresets(d, "b", L)
	check("card b: Sunset other (on a)", #cpb == 1 and cpb[1].state == "other" and cpb[1].holder == "a")
	local ok2, _, ch2 = Looks.setPreset(d, "b", "sunset", L)
	check("the move of Sunset a -> b", ok2 and d.dragons.b.preset == "sunset" and d.dragons.a.preset == nil and #ch2 == 2 and table.find(ch2, "a") ~= nil)
	check("one instance: the wearer b", Looks.holderOf(d, "sunset") == "b")
	check("Solstice without the reward - not_owned", select(2, Looks.setPreset(d, "c", "solstice", L)) == "not_owned")
	d.owned.presets.solstice = true -- the Season 1 reward (06 §8): the flag owned.presets.solstice
	check("Solstice on ember - wrong_element", select(2, Looks.setPreset(d, "a", "solstice", L)) == "wrong_element")
	check("card ember: Solstice is not offered", #Looks.cardPresets(d, "a", L) == 1)
	local ok3 = Looks.setPreset(d, "b", "solstice", L)
	check("Solstice on dusk b instead of Sunset", ok3 and d.dragons.b.preset == "solstice" and Looks.holderOf(d, "sunset") == nil)
	local cpc = Looks.cardPresets(d, "c", L)
	check("card c: Sunset free, Solstice other", #cpc == 2 and cpc[1].id == "sunset" and cpc[1].state == "free" and cpc[2].id == "solstice" and cpc[2].state == "other")
	local ok4, _, ch4 = Looks.setPreset(d, "b", nil, L)
	check("take Solstice off b", ok4 and d.dragons.b.preset == nil and #ch4 == 1)
	check("the data order: all clean", Looks.cleanPresets(d, L) == 0)
end

-- put on right after a purchase / reward ------------------------------------------------------------------------
do
	local d = profile()
	d.companion = "c"
	d.owned = { presets = { sunset = true, solstice = true } }
	check("auto Sunset: the companion first", Looks.autoTarget(d, "sunset", L) == "c")
	d.dragons.c.preset = "solstice"
	check("auto Sunset: the companion has its own - the first in the nest", Looks.autoTarget(d, "sunset", L) == "a")
	d.dragons.a.preset = "sunset"
	check("auto: already worn - nobody", Looks.autoTarget(d, "sunset", L) == nil)
	local d2 = profile()
	d2.companion = "a" -- ember
	d2.owned = { presets = { solstice = true } }
	check("auto Solstice: the ember companion does not fit - the first dusk", Looks.autoTarget(d2, "solstice", L) == "b")
	d2.dragons.b.element = "ember"
	d2.dragons.c.element = "moss"
	check("auto Solstice: no dusk - nobody", Looks.autoTarget(d2, "solstice", L) == nil)
	check("auto: an unknown preset", Looks.autoTarget(d2, "rainbow", L) == nil)
	check("auto: without dragons", Looks.autoTarget({ owned = {} }, "sunset", L) == nil)
	local d3 = profile()
	d3.nestOrder = { "b" }
	d3.dragons.a.preset = "solstice" -- data corruption does not disturb the choice
	check("auto: not in the nest - by uid", Looks.autoTarget(d3, "sunset", L) == "b" and Looks.autoTarget({ dragons = { z = { element = "tide" }, y = { element = "tide" } } }, "sunset", L) == "y")
end

-- the order at the entry ----------------------------------------------------------------------------------------
do
	local d = profile()
	d.owned = { presets = { sunset = true, solstice = true } }
	d.dragons.a.preset = "sunset"
	d.dragons.b.preset = "sunset" -- a duplicate
	d.dragons.c.preset = "rainbow" -- unknown
	check("cleanup: 2 fixes", Looks.cleanPresets(d, L) == 2)
	check("cleanup: the first wearer remains", d.dragons.a.preset == "sunset" and d.dragons.b.preset == nil and d.dragons.c.preset == nil)
	local d2 = profile()
	d2.dragons.a.preset = "sunset" -- not bought
	d2.owned = { presets = { solstice = true } }
	d2.dragons.b.preset = "solstice"
	d2.dragons.a.element = "ember"
	check("cleanup: the unbought one is taken off, Solstice on dusk remains", Looks.cleanPresets(d2, L) == 1 and d2.dragons.a.preset == nil and d2.dragons.b.preset == "solstice")
	local d3 = profile()
	d3.owned = { presets = { solstice = true } }
	d3.dragons.a.preset = "solstice" -- ember
	check("cleanup: Solstice not on dusk is taken off", Looks.cleanPresets(d3, L) == 1 and d3.dragons.a.preset == nil)
	check("cleanup without dragons", Looks.cleanPresets({}, L) == 0)
end

-- the nest skins ----------------------------------------------------------------------------------------------
do
	local d = profile()
	check("without skins - the ordinary look", Looks.nestSkin(d, L) == nil and #Looks.nestSkinChoices(d, L) == 0)
	Shop.grant(d, "NestSkin_Lagoon_299", ctx())
	check("Lagoon", Looks.nestSkin(d, L) == "lagoon")
	Shop.grant(d, "VIP_299", ctx())
	check("VIP gives Gilded", Looks.ownsNestSkin(d, "gilded", L) and Looks.nestSkin(d, L) == "gilded")
	Shop.grant(d, "NestBundle_2999", ctx())
	check("Bundle gives Royal - it is first", Looks.nestSkin(d, L) == "royal")
	local ch = Looks.nestSkinChoices(d, L)
	check("the choice: royal, gilded, lagoon", #ch == 3 and ch[1] == "royal" and ch[2] == "gilded" and ch[3] == "lagoon")
	check("choose Lagoon", (Looks.setNestSkin(d, "lagoon", L)) and Looks.nestSkin(d, L) == "lagoon" and d.looks.nestSkin == "lagoon")
	check("a repeat - already", select(2, Looks.setNestSkin(d, "lagoon", L)) == "already")
	check("classic - the ordinary look", (Looks.setNestSkin(d, "classic", L)) and Looks.nestSkin(d, L) == nil)
	check("auto - Royal again", (Looks.setNestSkin(d, "auto", L)) and Looks.nestSkin(d, L) == "royal" and d.looks.nestSkin == "")
	check("an unknown skin - bad_request", select(2, Looks.setNestSkin(d, "pink", L)) == "bad_request")
	local d2 = profile()
	check("a foreign skin - not_owned", select(2, Looks.setNestSkin(d2, "royal", L)) == "not_owned")
	d2.looks = nil
	check("auto without the looks table", (Looks.setNestSkin(d2, "classic", L)) and d2.looks.nestSkin == "classic")
	local d3 = profile()
	d3.looks.nestSkin = "royal" -- chosen but not owned (for example, from a previous version) - by priority
	Shop.grant(d3, "NestSkin_Lagoon_299", ctx())
	check("a choice without ownership - by priority", Looks.nestSkin(d3, L) == "lagoon")
end

-- the Ascension tint and Classic ------
do
	local d = profile()
	check("the Ascended name", typeof(Strings.Looks.skins.ascended) == "string")
	check("without a step and skins: no row, the ordinary look", #Looks.nestChoices(d, L) == 0 and Looks.nestCurrent(d, L) == "classic")
	check("without a step ascended - not_owned", select(2, Looks.setNestSkin(d, "ascended", L)) == "not_owned")
	d.ascension = 6
	local skin, tint = Looks.nestLook(d, L)
	check("step 6 without a choice - tint 6 (dusk), no skin", skin == nil and tint == 6 and Looks.nestCurrent(d, L) == "ascended")
	check("the row: only Ascended", #Looks.nestChoices(d, L) == 1 and Looks.nestChoices(d, L)[1] == "ascended")
	check("classic - the ordinary look WITHOUT a tint", (Looks.setNestSkin(d, "classic", L)) and select(2, Looks.nestLook(d, L)) == nil and Looks.nestSkin(d, L) == nil and Looks.nestCurrent(d, L) == "classic")
	check("ascended - the tint back", (Looks.setNestSkin(d, "ascended", L)) and select(2, Looks.nestLook(d, L)) == 6 and d.looks.nestSkin == "ascended")
	Shop.grant(d, "VIP_299", ctx())
	check("VIP + ascended chosen - the tint, not Gilded", Looks.nestSkin(d, L) == nil and select(2, Looks.nestLook(d, L)) == 6)
	check("the row: Gilded, Ascended", #Looks.nestChoices(d, L) == 2 and Looks.nestChoices(d, L)[1] == "gilded" and Looks.nestChoices(d, L)[2] == "ascended")
	check("choose Gilded - the skin, no tint", (Looks.setNestSkin(d, "gilded", L)) and Looks.nestSkin(d, L) == "gilded" and select(2, Looks.nestLook(d, L)) == nil and Looks.nestCurrent(d, L) == "gilded")
	check("auto with VIP and a step - Gilded (the skin takes priority)", (Looks.setNestSkin(d, "auto", L)) and Looks.nestSkin(d, L) == "gilded")
	d.ascension = 0
	check("the step is removed: the ascended choice - like auto (Gilded)", (Looks.setNestSkin(d, "ascended", L) == false) and Looks.nestSkin(d, L) == "gilded")
	d.looks.nestSkin = "ascended" -- from a profile where the step was zeroed
	check("ascended in the profile without a step - by priority", Looks.nestSkin(d, L) == "gilded" and Looks.nestCurrent(d, L) == "gilded")
	check("the summary", string.find(Looks.summary(d, L), "look=gilded", 1, true) ~= nil)
end

-- the nest part roles (the WorldBuilder.buildNestTemplate template) -------------------------------------------------
check("the fence mesh", Looks.nestRole("Wood", "FenceSeg") == "fence" and Looks.nestRole("WoodDark", "FenceSeg") == "fenceDark")
check("the fallback fence", Looks.nestRole("Rail", "Fence") == "fence" and Looks.nestRole("Post", "Fence") == "fenceDark")
check("the fence wall is not painted", Looks.nestRole("FenceCollider", "Fence") == nil)
check("the posts and the sign", Looks.nestRole("RailPost", "NestTemplate") == "post" and Looks.nestRole("SignPole", "Nest1") == "post" and Looks.nestRole("SignPost", "Nest1") == "sign")
check("the showcase and the table", Looks.nestRole("Showcase", "Nest1") == "stone" and Looks.nestRole("EggTable", "Nest1") == "wood" and Looks.nestRole("EggTableLeg", "Nest1") == "woodDark")
check("the shelf, the dragons, the lantern are not painted", Looks.nestRole("Shelf1", "Shelf") == nil and Looks.nestRole("Body", "Dragon") == nil and Looks.nestRole("Post", "Lantern") == nil)
for _, role in L.nestRoles do
	check("the role from the config occurs: " .. role, ({ fence = 1, fenceDark = 1, post = 1, sign = 1, stone = 1, wood = 1, woodDark = 1, bowl = 1 } :: any)[role] ~= nil)
end
-- the incubator bowls
check("role bowl: the bowl mesh", Looks.nestRole("Bowl", "Bowl") == "bowl")
check("the bowl straw and runes are not painted", Looks.nestRole("Straw", "Bowl") == nil and Looks.nestRole("Runes", "Bowl") == nil)
check("role bowl: the fallback ring disc", Looks.nestRole("Incubator1", "Incubators") == "bowl" and Looks.nestRole("Incubator2", "Incubators") == "bowl")
check("the Lock dome is not painted", Looks.nestRole("Lock", "Incubators") == nil)
check("role bowl in nestRoles", table.find(L.nestRoles, "bowl") ~= nil)

-- the aura, the trail, the tags, the scarf ------------------------------------------------------------------------------------
do
	local d = profile()
	check("nothing", Looks.aura(d, L) == nil and Looks.trail(d, L) == nil and not Looks.scarf(d))
	local t0 = Looks.tags(d, L)
	check("no tags", t0.vip == false and t0.title == nil)
	Shop.grant(d, "Trail_Comet_149", ctx())
	check("the Comet trail", Looks.trail(d, L) == "comet")
	Shop.grant(d, "VIP_299", ctx())
	check("the VIP tag", Looks.tags(d, L).vip == true and Looks.tags(d, L).title == nil)
	Shop.grant(d, "Gift_NestBundle_2999", ctx())
	check("Bundle: the Royal aura and the Nest Lord title", Looks.aura(d, L) == "royal" and Looks.tags(d, L).title == "nestLord")
	Shop.grant(d, "StarterPack_49", { now = NOW, B = B, S = S, elements = Config.Elements, pick = { "ember", "moss" } } :: any)
	check("Starter: the scarf", Looks.scarf(d))
	check("the summary for the probes", string.find(Looks.summary(d, L), "look=royal", 1, true) ~= nil)
end

-- the profile keys after the appearance edits (ProfileStore: strings and numbers, no nil holes in arrays) --------------------
do
	local d = profile()
	Shop.grant(d, "Preset_Sunset_99", ctx())
	Looks.setPreset(d, "a", "sunset", L)
	Looks.setNestSkin(d, "classic", L)
	local function walk(t: any, path: string)
		for k, v in t do
			check("key " .. path .. "." .. tostring(k), typeof(k) == "string" or typeof(k) == "number")
			check("value " .. path .. "." .. tostring(k), typeof(v) ~= "function" and typeof(v) ~= "userdata")
			if typeof(v) == "table" then
				walk(v, path .. "." .. tostring(k))
			end
		end
	end
	walk(d, "data")
end

-- the nest tint and the Ascended title
do
	local L = Config.Looks
	check("ascTints: 6 tints", typeof(L.ascTints) == "table" and #L.ascTints == 6, L.ascTints and #L.ascTints)
	for i, t in L.ascTints or {} do
		for _, role in { "fence", "fenceDark", "sign" } do
			check("ascTints[" .. i .. "]." .. role .. " - a color", isRgb(t[role]))
		end
	end
	check("title: the ascended color", isRgb(L.tag.ascended))
	check("the string Ascended {roman}", typeof(Strings.Looks.ascendedTag) == "string" and string.find(Strings.Looks.ascendedTag, "{roman}", 1, true) ~= nil)
	check("without Ascension - no tint", Looks.ascTint({ ascension = 0 }, L) == nil and Looks.ascTint({}, L) == nil)
	check("without Ascension - no title", Looks.tags({}, L).ascended == nil)
	for _, c in { { 1, 1 }, { 2, 2 }, { 6, 6 }, { 7, 1 }, { 12, 6 }, { 13, 1 } } do
		check("step " .. c[1] .. " -> tint " .. c[2], Looks.ascTint({ ascension = c[1] }, L) == c[2], Looks.ascTint({ ascension = c[1] }, L))
	end
	check("the title - the step", Looks.tags({ ascension = 3 }, L).ascended == 3)
	check("VIP and Nest Lord are in place together with the title", Looks.tags({ ascension = 2, owned = { vip = true, titles = { nestLord = true } } }, L).title == "nestLord")
end

print(string.format("appearance specification: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed checks")
end
