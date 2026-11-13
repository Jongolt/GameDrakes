--!strict
-- all the English source texts of the game for the localization table (the path, the text).
-- Read by tools/locales.py (the translations locales/<lang>.csv, LocaleData, the LocalizationTable in the place). Strings - everything except the dragon names
-- (Names - proper names) and the game name (the brand); Content - only the text fields (the rest there - ids and numbers); Core/Quests -
-- errands 1-35. The translation and the on-screen texts are matched by the source text: the same text by different paths - one entry.
-- The module: a list { {path, text} }; printing - tests/loc_sources.luau, the check - tests/loc_spec.luau.

local Strings = require("../src/shared/Strings")
local Content = require("../src/shared/Content")
local Quests = require("../src/shared/Core/Quests")

local SKIP_STRINGS = { Names = true, GameName = true }
-- not shown to the player: the stop words of the shop text check (07 §9) and the emoji icons
local SKIP_PATHS = { ["Shop.banned"] = true, ["Shop.icons"] = true }
-- the dragon names are not translated - unique: the elements (Content.Elements.*.name), the variants (Variants.*.label)
-- the update names = the names of the dragons of the week (Updates.*.title: Cinder, Nightfall), the dragon-name presets (Cinder, Solstice).
-- They are not in the table - neither our translation nor the Roblox machine touches them; in the translation sentences the names stay in English
local SKIP_KEYS = { ["Looks.presets.cinder"] = true, ["Looks.presets.solstice"] = true }
-- Content: the path templates of the text fields (the digits of the path -> N)
local CONTENT_TEXT = {
	"Notes.N",
	"Keeper.N.title",
	"Keeper.N.text",
	"Calendar.N.text",
	"CalendarDay14.text",
	"Daily.easy.N.title",
	"Daily.medium.N.title",
	"Daily.hard.N.title",
	"Updates.N.eventText",
	"Elements.dusk.trait",
	"Elements.ember.trait",
	"Elements.frost.trait",
	"Elements.moss.trait",
	"Elements.storm.trait",
	"Elements.tide.trait",
	"Badges.ancient.name",
	"Badges.ascend.name",
	"Badges.elder.name",
	"Badges.flyer.name",
	"Badges.glide.name",
	"Badges.hatch.name",
	"Badges.index25.name",
	"Badges.party.name",
	"Badges.rider.name",
}
local contentText: { [string]: boolean } = {}
for _, p in CONTENT_TEXT do
	contentText[p] = true
end

-- the same names wherever they stand (the name of errand 35 = Nightfall); and everything that is not translated at all: the Keeper's
-- name, the brand, VIP, R$, the version, the bot name (the Roblox machine translated "Old Ash" as "Old Ashes", "Hatch & Fly" too)
local SKIP_TEXT = {
	Cinder = true, Nightfall = true, Solstice = true, ["Pearl Tide"] = true,
	["Old Ash"] = true, VIP = true, ["R$"] = true, ["Hatch & Fly"] = true, ["Find, Feed & Fly Dragons {v}"] = true,
	["Bot {n}"] = true, ["{n} fps"] = true,
}
local out: { { string } } = {}
local function emit(path: string, s: string)
	-- strings of substitutions and signs only ("+{n}/s", "{k}/{n}", "x2 {time}", "???") - nothing to translate
	local words = string.gsub(s, "{%w+}", "")
	if not SKIP_TEXT[s] and string.find(words, "%a%a") then
		table.insert(out, { path, s })
	end
end

local function sortedKeys(t: { [any]: any }): { any }
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys, function(a, b)
		if typeof(a) == "number" and typeof(b) == "number" then
			return a < b
		end
		return tostring(a) < tostring(b)
	end)
	return keys
end

local function walk(v: any, path: string, visit: (string, string, any) -> ())
	if typeof(v) == "table" then
		for _, k in sortedKeys(v) do
			walk(v[k], if path == "" then tostring(k) else path .. "." .. tostring(k), visit)
		end
	elseif typeof(v) == "string" then
		visit(path, v, nil)
	end
end

walk(Strings, "", function(path, s)
	local top = string.match(path, "^[^.]+") or path
	local two = string.match(path, "^[^.]+%.[^.]+") or path
	if not SKIP_STRINGS[top] and not SKIP_PATHS[two] and not SKIP_KEYS[path] then
		emit("Strings." .. path, s)
	end
end)

walk(Content, "", function(path, s)
	local pattern = string.gsub(path, "%.%d+", ".N")
	if contentText[pattern] then
		emit("Content." .. path, s)
	end
end)
-- the season rewards: a text only at kind = "decor" (the item name; the other values - zone and preset ids, numbers)
for i, r in (Content.Season :: any).rewards or {} do
	if r.kind == "decor" and typeof(r.value) == "string" then
		emit("Content.Season.rewards." .. i .. ".value", r.value)
	end
end

for _, q in Quests.List do
	emit("Quests." .. q.id .. ".title", q.title)
	emit("Quests." .. q.id .. ".text", q.text)
end

return out
