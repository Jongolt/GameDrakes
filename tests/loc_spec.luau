--!strict
-- the Loc module without Roblox - the translation by the source text, the substitution, the server templates, the notice parsing
-- the completeness of LocaleData in our languages (es, pt, de, fr) and the placeholders. The translations and the code as a whole - tools/locales.py --check.
-- luau tests/loc_spec.luau

local Loc = require("../src/shared/Loc")
local LocaleData = require("../src/shared/LocaleData")
local Strings = require("../src/shared/Strings")
local Content = require("../src/shared/Content")
local list = require("./loc_list")

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: string?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail then ": " .. detail else ""))
	end
end

local LANGS = { "es", "pt", "de", "fr" }

-- without Roblox and without a language - English
check("no language: English", Loc.lang() == "en" and Loc.t(Strings.Hints.feed) == "Feed")
check("no language: the substitution", Loc.fill(Strings.Errors.not_enough, { n = 37 }) == "Needs 37 more coins")

Loc.setLang("es-MX")
check("the language code es-MX -> es", Loc.lang() == "es")
check("es: a static string", Loc.t(Strings.Hints.feed) == "Alimentar", Loc.t(Strings.Hints.feed))
-- a standard word (roblox_standard.txt) - we do not set our translation, Roblox gives it (outside Roblox - English)
check("es: Shop - the Roblox translation, not ours", Loc.t(Strings.HUD.shop) == "Shop")
check("es: an unknown string as is", Loc.t("Zap the dragon") == "Zap the dragon")
check("es: a template and a number", Loc.fill(Strings.Errors.not_enough, { n = 37 }) == "Faltan 37 monedas", Loc.fill(Strings.Errors.not_enough, { n = 37 }))
-- a dragon name is not translated even if it coincides with a game word (the element Storm); a game word - via Loc.text
local grew = Loc.fill(Strings.Rewards.awayGrew, { name = "Storm", stage = Loc.text(Strings.Stage[2]) })
check("es: the name as is, the stage translated", grew == "Storm creció a Adulto", grew)
-- the element name is a dragon name, not translated: the value as is, the rarity - by a template
local ann = Loc.fill(Strings.Social.hatchAnnounce, { name = "Zap", rarity = Loc.text(Strings.Rarity.Rare), element = Content.Elements.ember.name })
check("es: nested templates, the element name as is", ann == "¡Zap eclosionó un Ember Raro!", ann)
check("es: an empty value", Loc.fill(Strings.Hatch.eggAt, {}, nil, "") == "Huevo de ", Loc.fill(Strings.Hatch.eggAt, {}, nil, ""))
check("es: without a value - {x} stays", Loc.fill(Strings.Hatch.eggAt, {}) == "Huevo de {zone}")
-- a server notice: templates -> strings, static text/title/sub -> a translation, the other fields as is
local p = Loc.resolve({ kind = "toast", text = Loc.text(Strings.Card.released, { n = "1,200" }), name = "Storm",
	sub = Strings.Hints.nestFull, item = Loc.text(Strings.Shop.names.StarterPack_49), title = "Zap" })
check("resolve: the text template", p.text == "Dragón liberado: +1,200 monedas", p.text)
check("resolve: a static sub", p.sub == "Nido lleno", p.sub)
check("resolve: a template in another field", p.item == "Paquete inicial", p.item)
check("resolve: the name as is", p.name == "Storm" and p.title == "Zap")
check("resolve: the notice kind is not touched", p.kind == "toast")
-- a template that is not a source itself (the zone signs: {r1} 60%) - only the values are translated
local sign = Loc.fill("{r1} 60%   {r2} 25%", { r1 = Loc.text(Strings.Rarity.Common), r2 = Loc.text(Strings.Rarity.Uncommon) }, nil, "")
check("es: a template not from the table", sign == "Común 60%   Poco común 25%", sign)

Loc.setLang("de")
check("de: a static string", Loc.t(Strings.Hints.feed) == "Füttern")
check("de: the word order in a template", Loc.fill(Strings.Errors.not_enough, { n = 5 }) == "Es fehlen 5 Münzen")
Loc.setLang("ja")
check("ja (the Roblox machine translation, without ours): English outside Roblox", Loc.t(Strings.Hints.feed) == "Feed")
Loc.setLang(nil)
check("the language reset", Loc.lang() == "en")

-- the completeness: every source string exists in every our language, the placeholders are the same
local function holders(s: string): string
	local t = {}
	for k in string.gmatch(s, "{(%w+)}") do
		table.insert(t, k)
	end
	table.sort(t)
	return table.concat(t, ",")
end
-- the standard words (src/shared/locales/roblox_standard.txt) - without our translation; the file is read by locales.py, here - the same 43
local STANDARD = { Shop = true, Settings = true, Close = true, Back = true, Skip = true, ["Tap to skip"] = true, Music = true,
	Sounds = true, On = true, Off = true, Code = true, ["Enter code"] = true, Redeem = true, ["Invite friends"] = true,
	["Play with friends"] = true, Join = true, Done = true, Claim = true, ["Claim!"] = true, Claimed = true, Owned = true,
	Paused = true, Locked = true, Read = true, Talk = true, View = true, Now = true, Gifts = true, Gift = true,
	["Open shop"] = true, ["See price"] = true, Rename = true, Collect = true, Coins = true, Up = true, Down = true,
	Dragons = true, Index = true, Quests = true, ["Still loading..."] = true, ["Something went wrong"] = true,
	["Not allowed"] = true, ["Waiting for network..."] = true }
for _, lang in LANGS do
	local D = (LocaleData :: any)[lang]
	local missing, bad, dup = 0, 0, 0
	for _, row in list do
		local tr = D and D[row[2]]
		if STANDARD[row[2]] then
			if tr ~= nil then
				dup += 1
			end
		elseif tr == nil then
			missing += 1
			if missing <= 3 then
				print("  no translation " .. lang .. ": " .. row[1])
			end
		elseif holders(tr) ~= holders(row[2]) then
			bad += 1
			print("  placeholders " .. lang .. " " .. row[1] .. ": " .. tr)
		end
	end
	check(lang .. ": everything is translated except the standard words (" .. #list .. ")", missing == 0, tostring(missing) .. " without a translation")
	check(lang .. ": the standard words have no translation of ours", dup == 0, tostring(dup))
	check(lang .. ": the placeholders match", bad == 0)
	-- the game words substituted into the templates are in the table
	local words = {}
	for _, w in Strings.Rarity :: any do
		table.insert(words, w)
	end
	for _, w in Strings.Stage :: any do
		table.insert(words, w)
	end
	for _, w in Strings.Zone :: any do
		table.insert(words, w)
	end
	local miss = 0
	for _, w in words do
		if not (D and D[w]) then
			miss += 1
		end
	end
	check(lang .. ": the game words (the rarity, the stage, the zone)", miss == 0)
	-- the dragon names are not translated and are not in the table (otherwise Roblox would translate a dragon with such a name too); Dusk - the time of day
	local named = 0
	for _, e in Content.Elements :: any do
		if e.name ~= Strings.World.phase.dusk and D and D[e.name] then
			named += 1
		end
	end
	for _, v in Content.Variants :: any do
		if D and D[v.label] then
			named += 1
		end
	end
	for _, n in { "Cinder", "Nightfall", "Solstice", "Pearl Tide" } do
		if D and D[n] then
			named += 1
		end
	end
	check(lang .. ": no dragon names in the table", named == 0, tostring(named))
end

-- the labels with names: Loc.raw outside Roblox does not fail and returns the same
check("Loc.raw outside Roblox", Loc.raw("x") == "x")

-- the Index set names: Strings.Index.sets (translated) = Core/Index (the book is built by them)
local IndexCore = require("../src/shared/Core/Index")
for id, name in Strings.Index.sets :: any do
	local set = IndexCore.set(id)
	check("Index set " .. id .. " = Core/Index", set ~= nil and (set :: any).name == Loc.t(name), set and (set :: any).name or "no set") -- "{Ember} set"
end

-- a name inside a phrase - {Name}, Loc.t sets it after the translation
local N = Loc.NAMES
for id, e in Content.Elements :: any do
	if typeof(e) == "table" and e.name then
		check("Loc.NAMES." .. tostring(e.name) .. " = element " .. tostring(id), N[e.name] == e.name)
	end
end
for id, v in (Content.Variants or {}) :: any do
	if typeof(v) == "table" and v.label then
		check("Loc.NAMES." .. tostring(v.label) .. " = variant " .. tostring(id), N[v.label] == v.label)
	end
end
check("Loc.NAMES: the dragons of the week and the presets", N.Cinder == Strings.Looks.presets.cinder and N.Solstice == Strings.Looks.presets.solstice
	and N.Nightfall == "Nightfall" and N.StormDragon == "Storm Dragon")
local unknown = {}
for _, row in list do
	for k in string.gmatch(row[2], "{(%w+)}") do
		if string.match(k, "^%u") and not N[k] then
			table.insert(unknown, row[1] .. " {" .. k .. "}")
		end
	end
end
check("capitalized placeholders - only the names from Loc.NAMES", #unknown == 0, table.concat(unknown, ", "))
check("en: the name after the translation", Loc.t(Strings.Shop.names.DragonWeek_1_199) == "Dragon of the week: Cinder", Loc.t(Strings.Shop.names.DragonWeek_1_199))
check("en: the name and the numbers", Loc.fill(Strings.Weather.dragonDone, { k = 3, n = 8 }) == "Storm Dragon: 3/8 shards", Loc.fill(Strings.Weather.dragonDone, { k = 3, n = 8 }))
Loc.setLang("es")
check("es: our translation + the name", Loc.t(Strings.Shop.names.DragonWeek_2_299) == "Dragón de la semana: Nightfall", Loc.t(Strings.Shop.names.DragonWeek_2_299))
check("es: two names", Loc.t(Strings.Weather.aurora) == "¡Aurora! Los huevos Frost de la Cumbre eclosionados ahora serán dragones Glacier", Loc.t(Strings.Weather.aurora))
Loc.setLang("ja")
check("ja (the Roblox machine, outside Roblox - English): the name is substituted", Loc.t(Strings.Rewards.joined) == "Welcome to Lanternfox Studios! Here is your Moss egg", Loc.t(Strings.Rewards.joined))
Loc.setLang(nil)

print(string.format("loc_spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("loc_spec: " .. failed .. " failed")
end
