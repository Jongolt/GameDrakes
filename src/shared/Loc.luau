--!strict
-- the translation of the game texts into the player's language. The source is English (Strings, Content, Core/Quests)
-- the translations - src/shared/locales/<lang>.csv -> LocaleData (tools/locales.py). The order: our translation -> the Roblox Translator (the place
-- table and the cloud one with machine translation - the languages without ours) -> English. The lookup is by the SOURCE TEXT, not by key.
-- Loc.t(s) the string in the player's language (a static string or a template with {x})
-- Loc.fill(s, v) the translation of the TEMPLATE, then the substitution of {x}; a template value Loc.text(...) is translated, strings - as is
-- (the names of players and dragons are not touched; a game word in a substitution - Loc.t(word) or Loc.text(word))
-- Loc.text(s, v) for the server: the template and the values instead of a ready string - the client translates into its language (Net, Loc.resolve)
-- Loc.tag(inst, p, s, v) for the server: the property p (Text, ObjectText...) of a label everyone sees - English as the fallback,
-- the template in the attribute Loc_<p>; the client sets the translation itself (the tag "Loc")
-- Static labels are translated by Roblox (AutoLocalize) by the game's cloud table (the same CSVs, tools/loc_cloud.py; there is no table in the place).
-- The server: Loc.t/fill with player - this player's language. Studio: the attribute ReplicatedStorage.LocTest = "es" - the language for checks (P8).
local LocaleData = require("./LocaleData")

local Loc = {}

export type Text = { loc: string, v: { [string]: any }? }

local OWN: { [string]: { [string]: string } } = LocaleData :: any
local IS_ROBLOX = typeof(game) == "Instance"
local Players: any, RunService: any, LocalizationService: any, ReplicatedStorage: any, CollectionService: any, HttpService: any
if IS_ROBLOX then
	Players = game:GetService("Players")
	RunService = game:GetService("RunService")
	LocalizationService = game:GetService("LocalizationService")
	ReplicatedStorage = game:GetService("ReplicatedStorage")
	CollectionService = game:GetService("CollectionService")
	HttpService = game:GetService("HttpService")
end
local IS_SERVER = IS_ROBLOX and RunService:IsServer()
local TAG = "Loc"
local RETRY = 30 -- s: the Translator request retry after a failure
local TEXT_FIELDS = { text = true, title = true, sub = true } -- the server notice fields: a static string -> a translation

local forced: string? = nil -- Loc.setLang (tests) or LocTest in Studio
local translators: { [any]: any } = {} -- a Player or a language code -> a Translator
local tried: { [any]: number } = {}

local function norm(id: any): string
	return string.match(string.lower(tostring(id or "")), "^(%a+)") or "en"
end

local refreshAll: () -> () = function() end

local function translatorFor(player: any): any
	local key: any = forced or player or (Players and Players.LocalPlayer)
	if key == nil or not IS_ROBLOX then
		return nil
	end
	local tr = translators[key]
	if tr ~= nil then
		return tr
	end
	local at = tried[key]
	if at and os.clock() - at < RETRY then
		return nil
	end
	tried[key] = os.clock()
	task.spawn(function()
		local ok, res = pcall(function()
			if typeof(key) == "string" then
				return LocalizationService:GetTranslatorForLocaleAsync(key)
			end
			return LocalizationService:GetTranslatorForPlayerAsync(key)
		end)
		if ok and res then
			translators[key] = res
			if not IS_SERVER then
				refreshAll()
			end
		end
	end)
	return nil
end

-- the player's language code: "es", "pt", "de"... ("en" - no translation)
function Loc.lang(player: Player?): string
	if forced then
		return forced
	end
	local p: any = player or (Players and Players.LocalPlayer)
	if p == nil then
		return "en"
	end
	local tr = translators[p]
	if tr then
		return norm(tr.LocaleId)
	end
	local ok, id = pcall(function()
		return p.LocaleId
	end)
	return if ok then norm(id) else "en"
end

-- the tests and the P8 check: the language for all calls (nil - the player's language)
function Loc.setLang(lang: string?)
	forced = if lang and lang ~= "" then norm(lang) else nil
	refreshAll()
end

-- a name inside a phrase - the substitution {Ember}
-- {Cinder}, {StormDragon}... The Roblox machine translates the phrase and keeps {…} (checked: 146 of 146), the name is set by Loc.t
-- after the translation. The values are compared by tests/loc_spec.luau against Content (the elements, the variants, the dragons of the week, the presets)
Loc.NAMES = {
	Ember = "Ember",
	Frost = "Frost",
	Moss = "Moss",
	Tide = "Tide",
	Storm = "Storm",
	Dusk = "Dusk",
	Glacier = "Glacier",
	Pearl = "Pearl",
	Cinder = "Cinder",
	Nightfall = "Nightfall",
	Solstice = "Solstice",
	StormDragon = "Storm Dragon",
} :: { [string]: string }

local function names(s: string): string
	if not string.find(s, "{", 1, true) then
		return s
	end
	return (string.gsub(s, "{(%w+)}", function(k)
		return Loc.NAMES[k] -- nil - not a name, {x} stays for Loc.fill
	end))
end

function Loc.t(s: string, player: Player?): string
	if typeof(s) ~= "string" or s == "" then
		return s
	end
	local lang = Loc.lang(player)
	if lang == "en" then
		return names(s)
	end
	local own = OWN[lang]
	local hit = own and own[s]
	if hit then
		return names(hit)
	end
	local tr = translatorFor(player)
	if tr then
		local ok, r = pcall(function()
			return tr:Translate(game, s)
		end)
		if ok and typeof(r) == "string" and r ~= "" then
			return names(r)
		end
	end
	return names(s)
end

-- a template for the client (the server -> Net.notice): the client translates into the player's language
function Loc.text(s: string, values: { [string]: any }?): Text
	return { loc = s, v = values }
end

function Loc.isText(x: any): boolean
	return typeof(x) == "table" and typeof(x.loc) == "string"
end

local render: (any, Player?) -> string

-- missing: what to replace {x} without a value with (by default - keep {x})
function Loc.fill(s: string, values: { [string]: any }?, player: Player?, missing: string?): string
	local tpl = Loc.t(s, player)
	local v: { [string]: any } = values or {}
	return (string.gsub(tpl, "{(%w+)}", function(k)
		local x = v[k]
		if x == nil then
			return missing or ("{" .. k .. "}")
		end
		if Loc.isText(x) then
			return render(x, player)
		end
		return tostring(x)
	end))
end

render = function(x: any, player: Player?): string
	if Loc.isText(x) then
		return Loc.fill(x.loc, x.v, player, "")
	end
	return if typeof(x) == "string" then x else tostring(x)
end
Loc.render = render

-- a server notice (the client, before handing out to the handlers): Loc.text templates -> strings; static text/title/sub -> a translation
function Loc.resolve(payload: any, depth: number?): any
	if typeof(payload) ~= "table" or (depth or 0) > 3 then
		return payload
	end
	for k, x in payload do
		if Loc.isText(x) then
			payload[k] = render(x)
		elseif typeof(x) == "string" and TEXT_FIELDS[k] then
			payload[k] = Loc.t(x)
		elseif typeof(x) == "table" then
			Loc.resolve(x, (depth or 0) + 1)
		end
	end
	return payload
end

-- the server: a label for all players (a sign, a hint) - English into the property, the template into the attribute, the client sets the translation
function Loc.tag(inst: Instance, prop: string, s: string, values: { [string]: any }?)
	local ok = pcall(function()
		(inst :: any)[prop] = Loc.fill(s, values, nil, "")
	end)
	if not ok or not IS_ROBLOX then
		return
	end
	inst:SetAttribute("Loc_" .. prop, HttpService:JSONEncode({ t = s, v = values or {} }))
	CollectionService:AddTag(inst, TAG)
end

-- the server: x - a string (as is; the previous template is removed) or a Loc.text template (Loc.tag)
function Loc.set(inst: Instance, prop: string, x: any)
	if Loc.isText(x) then
		Loc.tag(inst, prop, x.loc, x.v)
		return
	end
	if IS_ROBLOX and inst:GetAttribute("Loc_" .. prop) ~= nil then
		inst:SetAttribute("Loc_" .. prop, nil)
	end
	pcall(function()
		(inst :: any)[prop] = if x == nil then "" else tostring(x)
	end)
end

-- a label with a dragon or element name: Roblox does not touch it and its descendants
-- otherwise a dragon named "Dusk" (the default name = the element) would become "Ocaso" by the time-of-day string
function Loc.raw<T>(inst: T): T
	local i: any = inst
	if typeof(i) == "Instance" then
		for _, o in { i, table.unpack(i:GetDescendants()) } do
			if o:IsA("GuiBase2d") then
				o.AutoLocalize = false
			end
		end
	end
	return inst
end

-- the client: the translation of labels with Loc_<property> attributes
local function apply(inst: Instance)
	for name, val in inst:GetAttributes() do
		local prop = string.match(name, "^Loc_(%w+)$")
		if prop and typeof(val) == "string" then
			local ok, d = pcall(function()
				return HttpService:JSONDecode(val)
			end)
			if ok and typeof(d) == "table" and typeof(d.t) == "string" then
				local text = Loc.fill(d.t, d.v, nil, "")
				pcall(function()
					if (inst :: any)[prop] ~= text then
						(inst :: any)[prop] = text
					end
				end)
			end
		end
	end
end

local function hook(inst: Instance)
	pcall(function()
		(inst :: any).AutoLocalize = false -- the translation is already ours; without this Roblox would look for a ready string in the table
	end)
	apply(inst)
	inst.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 4) == "Loc_" then
			apply(inst)
		end
	end)
	for _, prop in { "Text", "ObjectText", "ActionText" } do
		pcall(function()
			-- the server rewrote the property (the English replica) - restore the translation
			inst:GetPropertyChangedSignal(prop):Connect(function()
				apply(inst)
			end)
		end)
	end
end

if IS_ROBLOX then
	if RunService:IsStudio() then
		local function readTest()
			local v = ReplicatedStorage:GetAttribute("LocTest")
			forced = if typeof(v) == "string" and v ~= "" then norm(v) else nil
			refreshAll()
		end
		ReplicatedStorage:GetAttributeChangedSignal("LocTest"):Connect(readTest)
		if not IS_SERVER and not game:IsLoaded() then
			-- Studio only: LocTest comes with replication; without waiting the first labels (the HUD, the shop cards) came up
			-- in English and were not redrawn. For a player the language is known at once (LocalPlayer.LocaleId)
			game.Loaded:Wait()
		end
		readTest()
	end
	if IS_SERVER then
		Players.PlayerAdded:Connect(function(p)
			translatorFor(p) -- the player's language from the Translator (LocaleId) before the first toasts
		end)
		for _, p in Players:GetPlayers() do
			translatorFor(p)
		end
		Players.PlayerRemoving:Connect(function(p)
			translators[p] = nil
			tried[p] = nil
		end)
	else
		refreshAll = function()
			for _, inst in CollectionService:GetTagged(TAG) do
				apply(inst)
			end
		end
		CollectionService:GetInstanceAddedSignal(TAG):Connect(hook)
		for _, inst in CollectionService:GetTagged(TAG) do
			hook(inst)
		end
		translatorFor(nil)
	end
end

return Loc
