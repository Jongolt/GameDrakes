--!strict
-- The appearance showcase (the 2.2 tail; spec 07 §2 no. 3, no. 11, no. 13, add. 2.6; 06 §8): pure logic without Roblox API - what of the bought
-- appearance is visible and where. The ownership flags are written by Core/Shop (owned.presets/trails/nestSkins/auras/titles, owned.vip, owned.bundle,
-- owned.scarf), the Season 1 reward - owned.presets.solstice. The numbers and colors - Config.Looks (comes here as the parameter L), the texts - Strings.
-- A color preset: one instance per one dragon (dragons[uid].preset), can be taken off and put on another; a preset may have
-- an element restriction (Solstice - only Dusk). The nest look (nestLook): the player's choice (looks.nestSkin) - a skin, "ascended" (the Ascension
-- tint, 05 §6) or "classic" (the ordinary look, without a tint); without a choice - a skin by L.nestSkinOrder (royal > night > gilded >
-- lagoon - the most expensive first), otherwise the Ascension tint, otherwise the ordinary look. before that "classic" gave the tint to an ascended one
-- . The tests - tests/looks_spec.luau.

local Looks = {}

export type Choice = { id: string, state: string, holder: string? } -- state: on (on this dragon) | free | other (on another)
export type Tags = { vip: boolean, title: string?, ascended: number? }

local AUTO = ""
local CLASSIC = "classic"
local ASCENDED = "ascended" -- the Ascension tint as a separate choice in the "Nest look" row
Looks.CLASSIC = CLASSIC
Looks.ASCENDED = ASCENDED

local function owned(data: any): { [string]: any }
	local o = data and data.owned
	return if typeof(o) == "table" then o else {}
end

-- owned[group][id] == true
function Looks.owns(data: any, group: string, id: string): boolean
	local g = owned(data)[group]
	return typeof(g) == "table" and g[id] == true
end

function Looks.ownsPreset(data: any, id: string): boolean
	return Looks.owns(data, "presets", id)
end

-- ---------------------------------------------------------------------------------------------- the color presets
-- does the preset fit the element? unknown -> bad_request, an element restriction -> wrong_element
function Looks.presetFits(id: string, element: string?, L: any): (boolean, string?)
	local P = L.presets[id]
	if not P then
		return false, "bad_request"
	end
	if P.element and P.element ~= element then
		return false, "wrong_element"
	end
	return true, nil
end

-- which dragon has the preset (uid) or nil; at a duplicate (data corruption) - the first by uid
function Looks.holderOf(data: any, id: string): string?
	local best: string? = nil
	for uid, d in (data and data.dragons or {}) :: { [string]: any } do
		if typeof(d) == "table" and d.preset == id and (best == nil or uid < (best :: string)) then
			best = uid
		end
	end
	return best
end

-- put the preset id on dragon uid (id = nil - take off). Returns ok, the refusal reason and the list of uids whose look changed (this dragon and
-- the previous wearer). A preset on another dragon is moved over; the previous preset of this dragon is freed.
function Looks.setPreset(data: any, uid: string, id: string?, L: any): (boolean, string?, { string })
	local dragons = data and data.dragons
	local d = typeof(dragons) == "table" and dragons[uid]
	if typeof(d) ~= "table" then
		return false, "no_dragon", {}
	end
	if id == nil then
		if d.preset == nil then
			return false, "already", {}
		end
		d.preset = nil
		return true, nil, { uid }
	end
	local fits, why = Looks.presetFits(id, d.element, L)
	if not fits then
		return false, why, {}
	end
	if not Looks.ownsPreset(data, id) then
		return false, "not_owned", {}
	end
	if d.preset == id then
		return false, "already", {}
	end
	local changed = { uid }
	for other, od in dragons :: { [string]: any } do
		if other ~= uid and typeof(od) == "table" and od.preset == id then
			od.preset = nil
			table.insert(changed, other)
		end
	end
	d.preset = id
	return true, nil, changed
end

-- whom to put a preset on right after a purchase or a reward: only if it is not on anyone yet; the companion, then the nest dragons in order, then
-- the rest by uid - the first fitting by element and without its own preset (we do not override someone's choice). nil - nobody
function Looks.autoTarget(data: any, id: string, L: any): string?
	local dragons = data and data.dragons
	if typeof(dragons) ~= "table" or not L.presets[id] or Looks.holderOf(data, id) then
		return nil
	end
	local order: { string } = {}
	if typeof(data.companion) == "string" then
		table.insert(order, data.companion)
	end
	for _, uid in (if typeof(data.nestOrder) == "table" then data.nestOrder else {}) :: { string } do
		table.insert(order, uid)
	end
	local rest = {}
	for uid in dragons :: { [string]: any } do
		table.insert(rest, uid)
	end
	table.sort(rest)
	for _, uid in rest do
		table.insert(order, uid)
	end
	for _, uid in order do
		local d = dragons[uid]
		if typeof(d) == "table" and d.preset == nil and Looks.presetFits(id, d.element, L) then
			return uid
		end
	end
	return nil
end

-- the order at the entry: presets not owned, not of the own element, unknown and duplicates are taken off. Returns the number of fixes.
function Looks.cleanPresets(data: any, L: any): number
	local fixed = 0
	local dragons = data and data.dragons
	if typeof(dragons) ~= "table" then
		return 0
	end
	local uids = {}
	for uid in dragons :: { [string]: any } do
		table.insert(uids, uid)
	end
	table.sort(uids)
	local seen: { [string]: boolean } = {}
	for _, uid in uids do
		local d = dragons[uid]
		local id = typeof(d) == "table" and d.preset
		if typeof(id) == "string" then
			local ok = Looks.presetFits(id, d.element, L) and Looks.ownsPreset(data, id) and not seen[id]
			if ok then
				seen[id] = true
			else
				d.preset = nil
				fixed += 1
			end
		elseif typeof(d) == "table" and d.preset ~= nil then
			d.preset = nil
			fixed += 1
		end
	end
	return fixed
end

-- the preset buttons on the dragon card: the owned presets fitting this dragon, in the order L.presetOrder
function Looks.cardPresets(data: any, uid: string, L: any): { Choice }
	local out: { Choice } = {}
	local d = data and typeof(data.dragons) == "table" and data.dragons[uid]
	if typeof(d) ~= "table" then
		return out
	end
	for _, id in L.presetOrder do
		if Looks.ownsPreset(data, id) and Looks.presetFits(id, d.element, L) then
			local holder = Looks.holderOf(data, id)
			local state = if d.preset == id then "on" elseif holder then "other" else "free"
			table.insert(out, { id = id, state = state, holder = if state == "other" then holder else nil })
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------- the nest skin
function Looks.ownsNestSkin(data: any, id: string, L: any): boolean
	local S = L.nestSkins[id]
	if not S then
		return false
	end
	if Looks.owns(data, "nestSkins", id) then
		return true
	end
	return S.flag ~= nil and owned(data)[S.flag] == true -- Gilded comes with the VIP pass (owned.vip)
end

-- the owned skins in priority order
function Looks.nestSkinChoices(data: any, L: any): { string }
	local out = {}
	for _, id in L.nestSkinOrder do
		if Looks.ownsNestSkin(data, id, L) then
			table.insert(out, id)
		end
	end
	return out
end

-- the nest tint for Ascension (05 §6) - the number 1..#L.ascTints in a cycle, nil - there was no Ascension
local function ascTint(data: any, L: any): number?
	local n = data and data.ascension
	local T = L.ascTints
	if typeof(n) ~= "number" or n < 1 or typeof(T) ~= "table" or #T == 0 then
		return nil
	end
	return ((math.floor(n) - 1) % #T) + 1
end

-- what to show on the nest: (the skin, nil) | (nil, the Ascension tint) | (nil, nil) - the ordinary look.
-- The player's choice: "classic" - the ordinary look; "ascended" - the tint (no step - as without a choice); an owned skin - it.
-- Without a choice (auto) or a choice not owned: the first skin by priority, otherwise the Ascension tint, otherwise the ordinary look
function Looks.nestLook(data: any, L: any): (string?, number?)
	local looks = data and data.looks
	local chosen = if typeof(looks) == "table" and typeof(looks.nestSkin) == "string" then looks.nestSkin else AUTO
	if chosen == CLASSIC then
		return nil, nil
	end
	if chosen == ASCENDED then
		local t = ascTint(data, L)
		if t then
			return nil, t
		end
	elseif chosen ~= AUTO and Looks.ownsNestSkin(data, chosen, L) then
		return chosen, nil
	end
	local skin = Looks.nestSkinChoices(data, L)[1]
	if skin then
		return skin, nil
	end
	return nil, ascTint(data, L)
end

-- which skin to show (nil - no skin: the Ascension tint or the ordinary look)
function Looks.nestSkin(data: any, L: any): string?
	local skin = Looks.nestLook(data, L)
	return skin
end

-- what to highlight in the "Nest look" row: the skin id | "ascended" | "classic"
function Looks.nestCurrent(data: any, L: any): string
	local skin, tint = Looks.nestLook(data, L)
	return skin or (if tint then ASCENDED else CLASSIC)
end

-- the row buttons besides Classic: the owned skins by priority, then "ascended" if there is an Ascension step
function Looks.nestChoices(data: any, L: any): { string }
	local out = Looks.nestSkinChoices(data, L)
	if ascTint(data, L) then
		table.insert(out, ASCENDED)
	end
	return out
end

-- the player's choice: a skin id, "ascended" (the Ascension tint; without a step - not_owned), "auto" (by priority) or "classic" (the ordinary look)
function Looks.setNestSkin(data: any, id: string, L: any): (boolean, string?)
	local value: string
	if id == "auto" then
		value = AUTO
	elseif id == CLASSIC then
		value = CLASSIC
	elseif id == ASCENDED then
		if not ascTint(data, L) then
			return false, "not_owned"
		end
		value = ASCENDED
	elseif L.nestSkins[id] then
		if not Looks.ownsNestSkin(data, id, L) then
			return false, "not_owned"
		end
		value = id
	else
		return false, "bad_request"
	end
	data.looks = if typeof(data.looks) == "table" then data.looks else {}
	if (data.looks.nestSkin or AUTO) == value then
		return false, "already"
	end
	data.looks.nestSkin = value
	return true, nil
end

-- the nest part role for the skin by the part name and its parent (the WorldBuilder.buildNestTemplate template); nil - the part is not painted;
-- the incubator bowls (bowl) are painted too
function Looks.nestRole(name: string, parentName: string?): string?
	if parentName == "FenceSeg" then -- the Kenney fence mesh: the dark parts are the posts
		return if string.find(name, "Dark", 1, true) then "fenceDark" else "fence"
	end
	if parentName == "Fence" then -- the fallback fence of parts (without the mesh)
		if name == "Rail" then
			return "fence"
		elseif name == "Post" then
			return "fenceDark"
		end
		return nil
	end
	if parentName == "Bowl" then -- the incubator bowl mesh (WorldBuilder.incubatorBowl: Bowl / Straw / Runes; the runes are painted by setIncubatorLight)
		return if name == "Bowl" then "bowl" else nil
	end
	if parentName == "Incubators" and string.match(name, "^Incubator%d+$") then -- the fallback ring disc (the bowl mesh did not load)
		return "bowl"
	end
	if name == "RailPost" or name == "SignPole" then
		return "post"
	elseif name == "SignPost" then
		return "sign"
	elseif name == "Showcase" then
		return "stone"
	elseif name == "EggTable" then
		return "wood"
	elseif name == "EggTableLeg" then
		return "woodDark"
	end
	return nil
end

-- ---------------------------------------------------------------------------------------------- the aura, the trail, the tags, the scarf
local function firstOwned(data: any, group: string, order: { string }): string?
	for _, id in order do
		if Looks.owns(data, group, id) then
			return id
		end
	end
	return nil
end

function Looks.aura(data: any, L: any): string?
	return firstOwned(data, "auras", L.auraOrder)
end

function Looks.trail(data: any, L: any): string?
	return firstOwned(data, "trails", L.trailOrder)
end

-- above the head: the VIP tag (the pass) and the title (the bundle)
-- the Ascension step or nil (there was none)
local function ascSteps(data: any): number?
	local n = data and data.ascension
	return if typeof(n) == "number" and n >= 1 then math.floor(n) else nil
end

function Looks.tags(data: any, L: any): Tags
	return { vip = owned(data).vip == true, title = firstOwned(data, "titles", L.tag.titleOrder), ascended = ascSteps(data) }
end

-- the nest tint for Ascension - the number 1..#L.ascTints in a cycle, nil - there was no Ascension
function Looks.ascTint(data: any, L: any): number?
	return ascTint(data, L)
end

function Looks.scarf(data: any): boolean
	return owned(data).scarf == true
end

-- the state line for the Studio probes (LoopDebug "looks")
function Looks.summary(data: any, L: any): string
	local presets = {}
	for _, id in L.presetOrder do
		if Looks.ownsPreset(data, id) then
			table.insert(presets, id .. "@" .. tostring(Looks.holderOf(data, id) or "-"))
		end
	end
	local t = Looks.tags(data, L)
	local looks = data and data.looks
	return string.format("presets[%s] look=%s (choice=%s, own=%s) aura=%s trail=%s vip=%s title=%s scarf=%s",
		table.concat(presets, ","), Looks.nestCurrent(data, L),
		tostring(if typeof(looks) == "table" and looks.nestSkin ~= "" then looks.nestSkin else "auto"),
		table.concat(Looks.nestSkinChoices(data, L), ","), tostring(Looks.aura(data, L)), tostring(Looks.trail(data, L)),
		tostring(t.vip), tostring(t.title), tostring(Looks.scarf(data)))
end

return Looks
