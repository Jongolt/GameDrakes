--!strict
-- 2.1: the shop, pure logic (spec 07 §2, §4-5, §8-9; 10 §3 ShopService). The catalog of 13 SKU types: 23 items, 7 passes
-- 19 gift copies [Gift]; what every SKU gives - here; the prices only in Roblox (the numbers - ShopIds.luau from monetize.py).
-- grant(data, key, ctx) changes the profile deterministically (tests/shop_spec.luau): without Roblox API; randomness only for the Starter Pack
-- via ctx.rng. The Hatch/Grow Now steps apply only to an egg/dragon whose remainder fits the step (07 §4: "or higher");
-- if there is no fitting one - a ticket items.hatchNow[step] / items.growNow[step], it fires at the next fitting case.
local Growth = require("./Growth")
local Eggs = require("./Eggs")
local Dragons = require("./Dragons") -- the Dragon of the Week (07 §2 no. 12)

local Shop = {}

export type Sku = {
	key: string, -- the SKU key (= the key in ShopIds and monetize.py)
	kind: string, -- "pass" | "product"
	class: string, -- hatchNow | growNow | starter | pass | treats | boost | income | look | bundle
	tab: string, -- the shop tab (07 §3): time | nest | coins | looks
	gift: boolean, -- there is a [Gift] copy Gift_<key>
	tier: number?, -- the Hatch/Grow Now step 1..5
	n: number?, -- treats in the pack
	minutes: number?, -- the boost duration
	hours: number?, -- hours of income
	flag: string?, -- owned[flag] for the permanent ones (the passes, Starter, Bundle)
	look: { group: string, id: string }?, -- owned[group][id] for the appearance
	requires: string?, -- without this SKU we do not sell (slots II/III)
	-- from which update it is sold (Content.Updates[update]); days - how many days from its date (the Dragon of the Week)
	update: number?,
	days: number?,
	-- the Dragon of the Week: the number, the element, the rarity, the name, the appearance preset (07 §2 no. 12: a specific dragon of stage Hatchling, 1 per account)
	week: number?,
	element: string?,
	rarity: string?,
	dragonName: string?,
	preset: string?,
}

export type Ctx = {
	now: number, -- unix
	rate: number?, -- the nest income per second without the temporary boost (Nest income)
	rng: (() -> number)?, -- for the Starter Pack eggs
	pick: { string }?, -- the Starter Pack elements (two), or the target slot/uid for Hatch/Grow Now
	elements: { string }?, -- Config.Elements
	B: any, -- Config.Balance
	S: any, -- Config.Shop
	slot: string?, -- the Hatch Now target (the incubator key "1".."3")
	uid: string?, -- the Grow Now target
	slots: number?, -- slots in the nest (the Dragon of the Week goes into the nest if there is a slot or it earns more than the weakest)
	-- the Starter Pack with a random rarity - only
	-- if the player was shown the odds and Roblox allows him paid randomness (PolicyService); otherwise (and by default) - without
	-- randomness: S.starter.fixedRarity, without shiny and size, the element chosen by the player
	randomStarter: boolean?,
}

export type Grant = { ok: boolean, random: boolean?, applied: string?, slot: string?, uid: string?, coins: number?, eggs: number?, tier: number?, reason: string?, where: string?, wasNew: boolean?, indexKey: string? }

local catalog: { Sku } = {}
local byKey: { [string]: Sku } = {}
local built = false

local function add(s: Sku)
	table.insert(catalog, s)
	byKey[s.key] = s
end

-- the catalog is built from Config.Shop (the steps, the packs, the hours); the SKU keys are fixed - the same in monetize.py
function Shop.setup(S: any)
	if built then
		return
	end
	built = true
	for i, price in S.hatchNow.prices do
		add({ key = "HatchNow_" .. price, kind = "product", class = "hatchNow", tab = "time", gift = false, tier = i })
	end
	for i, price in S.hatchNow.prices do
		add({ key = "GrowNow_" .. price, kind = "product", class = "growNow", tab = "time", gift = false, tier = i })
	end
	for _, p in S.treats.packs do
		add({ key = "Treats_" .. p.n .. "_" .. p.price, kind = "product", class = "treats", tab = "time", gift = true, n = p.n })
	end
	for _, b in S.boost.packs do
		add({ key = "Boost" .. b.minutes .. "_" .. b.price, kind = "product", class = "boost", tab = "time", gift = true, minutes = b.minutes })
	end
	add({ key = "StarterPack_49", kind = "product", class = "starter", tab = "nest", gift = false, flag = "starter" })
	add({ key = "NestBundle_2999", kind = "product", class = "bundle", tab = "nest", gift = true, flag = "bundle" })
	add({ key = "VIP_299", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "vip" })
	add({ key = "X2Coins_299", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "x2" })
	add({ key = "AutoCollect_149", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "autoCollect" })
	add({ key = "NestSlot1_99", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "slot1" })
	add({ key = "NestSlot2_199", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "slot2", requires = "NestSlot1_99" })
	add({ key = "NestSlot3_399", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "slot3", requires = "NestSlot2_199" })
	add({ key = "FastIncubator_249", kind = "pass", class = "pass", tab = "nest", gift = true, flag = "fastIncubator" })
	for _, h in S.income.packs do
		add({ key = "NestIncome" .. h.hours .. "h_" .. h.price, kind = "product", class = "income", tab = "coins", gift = true, hours = h.hours })
	end
	add({ key = "Preset_Sunset_99", kind = "product", class = "look", tab = "looks", gift = true, look = { group = "presets", id = "sunset" } })
	add({ key = "Trail_Comet_149", kind = "product", class = "look", tab = "looks", gift = true, look = { group = "trails", id = "comet" } })
	add({ key = "NestSkin_Lagoon_299", kind = "product", class = "look", tab = "looks", gift = true, look = { group = "nestSkins", id = "lagoon" } })
	-- the items of updates 2-4 - in the shop only from the date of their update
	add({ key = "Trail_Tidal_149", kind = "product", class = "look", tab = "looks", gift = true, look = { group = "trails", id = "tidal" }, update = 3 })
	add({ key = "NestSkin_Night_299", kind = "product", class = "look", tab = "looks", gift = true, look = { group = "nestSkins", id = "night" }, update = 4 })
	add({ key = "DragonWeek_1_199", kind = "product", class = "dragonWeek", tab = "nest", gift = true, week = 1, update = 2, days = 7,
		element = "ember", rarity = "Epic", dragonName = "Cinder", preset = "cinder" })
	add({ key = "DragonWeek_2_299", kind = "product", class = "dragonWeek", tab = "nest", gift = true, week = 2, update = 4, days = 7,
		element = "dusk", rarity = "Legendary", dragonName = "Nightfall" })
end

function Shop.catalog(): { Sku }
	return catalog
end

-- whether the item is visible in the shop showcase (Config.Shop.listed); no list - the whole catalog is visible. Does not forbid the purchase
function Shop.listed(sku: Sku, S: any): boolean
	local L = S and S.listed
	if typeof(L) ~= "table" then
		return true
	end
	return (L.keys ~= nil and L.keys[sku.key] == true) or (L.classes ~= nil and L.classes[sku.class] == true)
end

-- key -> SKU; Gift_<key> -> SKU and the gift flag
function Shop.resolve(key: string): (Sku?, boolean)
	local base = string.match(key, "^Gift_(.+)$")
	if base then
		local s = byKey[base]
		return (if s and s.gift then s else nil), true
	end
	return byKey[key], false
end

function Shop.get(key: string): Sku?
	return byKey[key]
end

function Shop.giftKey(key: string): string
	return "Gift_" .. key
end

-- all the keys that must exist in Roblox (= CATALOG monetize.py)
function Shop.allKeys(): { string }
	local out = {}
	for _, s in catalog do
		table.insert(out, s.key)
	end
	for _, s in catalog do
		if s.gift then
			table.insert(out, Shop.giftKey(s.key))
		end
	end
	return out
end

-- ---------------------------------------------------------------------------------------------- the time steps
-- the step 1..5 by the remainder (07 §2: <= 1 min 5; <= 5 min 9; <= 20 min 19; <= 60 min 29; further 49)
function Shop.tierOf(remaining: number, S: any): number
	local tier = Growth.priceTier(remaining, S)
	return tier
end

function Shop.tierLimit(tier: number, S: any): number
	return S.hatchNow.steps[tier] or math.huge
end

function Shop.tierKey(class: string, tier: number, S: any): string
	return (if class == "hatchNow" then "HatchNow_" else "GrowNow_") .. S.hatchNow.prices[tier]
end

-- the egg for the step: with a remainder > 0 and <= the step limit; the preference - the named slot, otherwise the longest of the fitting ones
function Shop.pickHatchTarget(data: any, tier: number, now: number, S: any, slot: string?): string?
	local limit = Shop.tierLimit(tier, S)
	if slot == "glow" then -- the golden egg on the stand - only by the named target, did not fit the step - a ticket
		local r = Shop.hatchRemaining(data, "glow", now)
		return if r and r > 0 and r <= limit then "glow" else nil
	end
	local inc = data.eggs and data.eggs.incubating or {}
	local function rem(rec: any): number
		return math.max(0, (rec.endsAt or now) - now)
	end
	if slot and inc[slot] and rem(inc[slot]) > 0 and rem(inc[slot]) <= limit then
		return slot
	end
	local best: string? = nil
	local bestRem = 0
	for k, rec in inc do
		local r = rem(rec)
		if r > 0 and r <= limit and r > bestRem then
			best, bestRem = k, r
		end
	end
	return best
end

-- the dragon for the step: with a growth timer, the remainder > 0 and <= the limit; the preference - the named uid
function Shop.pickGrowTarget(data: any, tier: number, now: number, S: any, uid: string?): string?
	local limit = Shop.tierLimit(tier, S)
	local dragons = data.dragons or {}
	local function rem(d: any): number
		return if d.stageEndsAt then math.max(0, d.stageEndsAt - now) else 0
	end
	if uid and dragons[uid] and rem(dragons[uid]) > 0 and rem(dragons[uid]) <= limit then
		return uid
	end
	local best: string? = nil
	local bestRem = 0
	for k, d in dragons do
		local r = rem(d)
		if r > 0 and r <= limit and r > bestRem then
			best, bestRem = k, r
		end
	end
	return best
end

-- the target's timer remainder (seconds) for computing the step on the client and the server
function Shop.hatchRemaining(data: any, slot: string, now: number): number?
	if slot == "glow" then -- the golden egg on the stand (Services/GlowEgg: data.glowEgg.readyAt)
		local g = data.glowEgg
		if typeof(g) == "table" and (tonumber(g.taken) or 0) > 0 and (tonumber(g.readyAt) or 0) > 0 and not g.hatched then
			return math.max(0, g.readyAt - now)
		end
		return nil
	end
	local rec = data.eggs and data.eggs.incubating and data.eggs.incubating[slot]
	return if rec then math.max(0, (rec.endsAt or now) - now) else nil
end

-- "hatch now" for the target - a bowl or the golden stand
local function hatchNowAt(data: any, slot: string, now: number)
	if slot == "glow" then
		data.glowEgg.readyAt = now
	else
		data.eggs.incubating[slot].endsAt = now
	end
end

function Shop.growRemaining(data: any, uid: string, now: number): number?
	local d = data.dragons and data.dragons[uid]
	return if d and d.stageEndsAt then math.max(0, d.stageEndsAt - now) else nil
end

-- the longest egg / dragon with a timer (a shop card without an explicit target)
function Shop.longestHatch(data: any, now: number): (string?, number)
	local best: string? = nil
	local bestRem = 0
	for k, rec in (data.eggs and data.eggs.incubating or {}) :: { [string]: any } do
		local r = math.max(0, (rec.endsAt or now) - now)
		if r > bestRem then
			best, bestRem = k, r
		end
	end
	return best, bestRem
end

function Shop.longestGrow(data: any, now: number): (string?, number)
	local best: string? = nil
	local bestRem = 0
	for k, d in (data.dragons or {}) :: { [string]: any } do
		local r = if d.stageEndsAt then math.max(0, d.stageEndsAt - now) else 0
		if r > bestRem then
			best, bestRem = k, r
		end
	end
	return best, bestRem
end

-- ---------------------------------------------------------------------------------------------- ownership
-- the odds of one egg of the random Starter Pack - what we show before the purchase (the Roblox paid random items rule: every
-- outcome in percent, the sum 100). The same slice of the zone table as in Eggs.rollGuaranteed; the variants - separate rolls.
function Shop.starterOdds(B: any, S: any): { rarity: { { id: string, pct: number } }, shiny: number, big: number, huge: number }
	local ST = S.starter
	local t = Eggs.rarityTable(ST.zone, false, B)
	local minIdx = Eggs.rarityIndex(ST.minRarity)
	local sum = 0
	for i, o in t do
		if i >= minIdx then
			sum += o.weight
		end
	end
	local out = {}
	for i, o in t do
		if i >= minIdx and o.weight > 0 then
			table.insert(out, { id = o.id, pct = o.weight / sum * 100 })
		end
	end
	local V = B.variants
	return { rarity = out, shiny = V.shiny.p * 100, big = V.big.p * 100, huge = V.huge.p * 100 }
end

local function ensureOwned(data: any): any
	data.owned = data.owned or {}
	return data.owned
end

function Shop.owned(data: any, sku: Sku): boolean
	local o = data and data.owned or {}
	if sku.flag then
		return o[sku.flag] == true
	end
	if sku.look then
		local g = o[sku.look.group]
		return typeof(g) == "table" and g[sku.look.id] == true
	end
	return false
end

function Shop.has(data: any, flag: string): boolean
	local o = data and data.owned
	return typeof(o) == "table" and o[flag] == true
end

function Shop.hasLook(data: any, group: string, id: string): boolean
	local o = data and data.owned
	local g = typeof(o) == "table" and o[group]
	return typeof(g) == "table" and g[id] == true
end

-- whether the SKU is sold now: live - how many updates are running (Core/LiveOps.live), now - the live operations clock
-- updates - Content.Updates. Before the date - "locked" (not shown), after the days window - "expired" (07 §2 no. 12: archived)
function Shop.onSale(sku: Sku, live: number, now: number, updates: { any }): (boolean, string?)
	if sku.update and live < sku.update then
		return false, "locked"
	end
	if sku.update and sku.days then
		local u = updates[sku.update]
		if u and now >= u.activeFrom + sku.days * 86400 then
			return false, "expired"
		end
	end
	return true, nil
end

-- which Dragon of the Week stands on the plaza stand - only while it is sold (onSale); before the update date
-- and after the days window - nil: there is no stand in the world (the fail-open pitfall - the server decides, not a client "hide")
function Shop.standSku(live: number, now: number, updates: { any }): Sku?
	for _, sku in catalog do
		if sku.class == "dragonWeek" and sku.update and Shop.onSale(sku, live, now, updates) then
			return sku
		end
	end
	return nil
end

-- a permanent SKU that is already owned, or a requirement not met -> the refusal reason
function Shop.sellable(data: any, sku: Sku): (boolean, string?)
	if sku.flag or sku.look then
		if Shop.owned(data, sku) then
			return false, "owned"
		end
	end
	if sku.class == "starter" and Shop.has(data, "starter") then
		return false, "owned"
	end
	if sku.class == "dragonWeek" then -- 1 per account
		local dw = data and data.owned and data.owned.dragonWeek
		if typeof(dw) == "table" and dw[tostring(sku.week)] then
			return false, "owned"
		end
	end
	if sku.requires then
		local req = byKey[sku.requires]
		if req and not Shop.owned(data, req) then
			return false, "locked"
		end
	end
	return true, nil
end

-- the nest slots from the passes: slot1..3 (not more than maxPasses) + VIP
function Shop.passSlots(data: any, B: any): number
	local n = 0
	for i = 1, B.slots.maxPasses do
		if Shop.has(data, "slot" .. i) then
			n += 1
		end
	end
	if Shop.has(data, "vip") then
		n += B.slots.vipPlus
	end
	return n
end

-- the income modifiers (Economy.nestRate mods): ascension, the Index, VIP, x2, the boost
function Shop.rateMods(data: any, indexPct: number): { [string]: any }
	local boost = typeof(data.boost) == "table" and (data.boost.secondsLeft or 0) > 0
	return { ascension = data.ascension or 0, indexPct = indexPct, vip = Shop.has(data, "vip"), x2 = Shop.has(data, "x2"), boost = boost }
end

function Shop.incomeAmount(rate: number, hours: number): number
	return math.floor(rate * hours * 3600)
end

-- the contents of the Everything for the Nest bundle (5 things: the Royal skin, slots I-III, the Royal aura; the title comes with the aura)
Shop.BUNDLE_ITEMS = 5
function Shop.bundleOwnedCount(data: any): number
	local n = 0
	if Shop.hasLook(data, "nestSkins", "royal") then
		n += 1
	end
	for i = 1, 3 do
		if Shop.has(data, "slot" .. i) then
			n += 1
		end
	end
	if Shop.hasLook(data, "auras", "royal") then
		n += 1
	end
	return n
end

-- ---------------------------------------------------------------------------------------------- granting
local function ensureItems(data: any): any
	data.items = data.items or { treats = 0, hatchNow = {}, growNow = {} }
	data.items.hatchNow = data.items.hatchNow or {}
	data.items.growNow = data.items.growNow or {}
	data.items.treats = data.items.treats or 0
	return data.items
end

local function grantLook(data: any, group: string, id: string)
	local o = ensureOwned(data)
	o[group] = if typeof(o[group]) == "table" then o[group] else {}
	o[group][id] = true
end

-- granting one SKU into the profile data (for a gift - the recipient's profile). Deterministic at the same state and ctx.
function Shop.grant(data: any, key: string, ctx: Ctx): Grant
	local sku, _isGift = Shop.resolve(key)
	if not sku then
		return { ok = false, reason = "bad_request" }
	end
	local S, B, now = ctx.S, ctx.B, ctx.now
	if sku.class == "hatchNow" then
		local tier = sku.tier :: number
		local slot = Shop.pickHatchTarget(data, tier, now, S, ctx.slot)
		if slot then
			hatchNowAt(data, slot, now)
			return { ok = true, applied = "slot", slot = slot, tier = tier }
		end
		local items = ensureItems(data)
		items.hatchNow[tostring(tier)] = (items.hatchNow[tostring(tier)] or 0) + 1
		return { ok = true, applied = "ticket", tier = tier }
	elseif sku.class == "growNow" then
		local tier = sku.tier :: number
		local uid = Shop.pickGrowTarget(data, tier, now, S, ctx.uid)
		if uid then
			Growth.growNow(data.dragons[uid], now)
			return { ok = true, applied = "dragon", uid = uid, tier = tier }
		end
		local items = ensureItems(data)
		items.growNow[tostring(tier)] = (items.growNow[tostring(tier)] or 0) + 1
		return { ok = true, applied = "ticket", tier = tier }
	elseif sku.class == "treats" then
		local items = ensureItems(data)
		items.treats += sku.n :: number
		return { ok = true, applied = "items" }
	elseif sku.class == "boost" then
		data.boost = if typeof(data.boost) == "table" then data.boost else { secondsLeft = 0 }
		data.boost.secondsLeft = (data.boost.secondsLeft or 0) + (sku.minutes :: number) * 60
		return { ok = true, applied = "boost" }
	elseif sku.class == "income" then
		local coins = Shop.incomeAmount(ctx.rate or 0, sku.hours :: number)
		data.coins = (data.coins or 0) + coins
		return { ok = true, applied = "coins", coins = coins }
	elseif sku.class == "pass" then
		ensureOwned(data)[sku.flag :: string] = true
		return { ok = true, applied = "flag" }
	elseif sku.class == "look" then
		grantLook(data, sku.look.group, sku.look.id)
		return { ok = true, applied = "look" }
	elseif sku.class == "bundle" then
		local o = ensureOwned(data)
		o.bundle = true
		for i = 1, 3 do
			o["slot" .. i] = true
		end
		grantLook(data, "nestSkins", "royal")
		grantLook(data, "auras", "royal")
		grantLook(data, "titles", "nestLord")
		return { ok = true, applied = "flag" }
	elseif sku.class == "dragonWeek" then -- a specific hatchling with a name and a preset, an Index entry; 1 per account
		local o = ensureOwned(data)
		o.dragonWeek = if typeof(o.dragonWeek) == "table" then o.dragonWeek else {}
		local wk = tostring(sku.week)
		if o.dragonWeek[wk] then
			return { ok = false, reason = "already" }
		end
		o.dragonWeek[wk] = now
		data.dragons = data.dragons or {}
		data.nestOrder = data.nestOrder or {}
		data.nextUid = data.nextUid or 1
		local d = Dragons.fromEgg(data, { element = sku.element :: string, rarity = sku.rarity :: string, shiny = false, size = "normal" }, now, false, B)
		d.name = sku.dragonName or d.name
		if sku.preset then
			grantLook(data, "presets", sku.preset)
			d.preset = sku.preset
		end
		local where = Dragons.add(data, d, ctx.slots or B.slots.start, B)
		data.index = data.index or {}
		local ik = Dragons.indexKey(d)
		local wasNew = not data.index[ik]
		data.index[ik] = true
		return { ok = true, applied = "dragonWeek", uid = d.uid, where = where, wasNew = wasNew, indexKey = ik }
	elseif sku.class == "starter" then
		local o = ensureOwned(data)
		if o.starter then
			return { ok = false, reason = "already" }
		end
		o.starter = true
		o.scarf = true
		local ST = S.starter
		local rng = ctx.rng or function()
			return 0.5
		end
		local picks = ctx.pick or {}
		local eggs = 0
		data.eggs = data.eggs or { shelf = {}, incubating = {} }
		data.eggs.shelf = data.eggs.shelf or {}
		local random = ctx.randomStarter == true
		for i = 1, ST.eggs do
			local el = picks[i] or picks[1]
			local egg: any
			if random then
				egg = Eggs.rollGuaranteed("starter" .. i, ST.zone, ST.minRarity, rng, B, ctx.elements or { "ember" }, el)
			else -- the outcome is known before the payment: neither the rarity, nor the variants, nor the element are rolled
				egg = { id = "starter" .. i, element = el or (ctx.elements or { "ember" })[1], rarity = ST.fixedRarity, shiny = false, size = "normal", zone = ST.zone, rareNest = false }
			end
			egg.foundAt = now
			table.insert(data.eggs.shelf, egg) -- the shelf may overflow: the purchase is not lost (07 §1 item 8)
			eggs += 1
		end
		local coins = 0
		if (data.incubators or 1) < ST.incubators then
			data.incubators = ST.incubators
		else
			coins = ST.incubatorFallbackCoins
			data.coins = (data.coins or 0) + coins
		end
		return { ok = true, applied = "starter", eggs = eggs, coins = coins, random = random }
	end
	return { ok = false, reason = "bad_request" }
end

-- the Hatch/Grow Now ticket: apply if there is a step the target's remainder fits; returns the step or nil
function Shop.useTicket(data: any, class: string, target: string, now: number, S: any): number?
	local items = data.items
	local pool = items and (if class == "hatchNow" then items.hatchNow else items.growNow)
	if typeof(pool) ~= "table" then
		return nil
	end
	local rem = if class == "hatchNow" then Shop.hatchRemaining(data, target, now) else Shop.growRemaining(data, target, now)
	if not rem or rem <= 0 then
		return nil
	end
	for tier = 1, #S.hatchNow.prices do -- the cheapest fitting step
		local n = pool[tostring(tier)] or 0
		if n > 0 and rem <= Shop.tierLimit(tier, S) then
			pool[tostring(tier)] = n - 1
			if class == "hatchNow" then
				hatchNowAt(data, target, now)
			else
				Growth.growNow(data.dragons[target], now)
			end
			return tier
		end
	end
	return nil
end

function Shop.ticketCount(data: any, class: string): number
	local items = data and data.items
	local pool = items and (if class == "hatchNow" then items.hatchNow else items.growNow)
	local n = 0
	if typeof(pool) == "table" then
		for _, v in pool do
			n += v
		end
	end
	return n
end

-- a treat from the stock: minus half of the growth remainder (Growth.treat)
function Shop.useTreat(data: any, uid: string, now: number, B: any): boolean
	local items = data.items
	if not items or (items.treats or 0) <= 0 then
		return false
	end
	local d = data.dragons and data.dragons[uid]
	if not d or not Growth.treat(d, now, B) then
		return false
	end
	items.treats -= 1
	return true
end

-- the stop list of the shop texts (07 §9): returns the violating strings
function Shop.bannedIn(texts: { [string]: any }, banned: { string }): { string }
	local bad = {}
	local function walk(t: any)
		for k, v in t do
			if typeof(v) == "table" then
				if k ~= "banned" then
					walk(v)
				end
			elseif typeof(v) == "string" then
				local low = string.lower(v)
				for _, w in banned do
					if string.find(low, w, 1, true) then
						table.insert(bad, v)
					end
				end
			end
		end
	end
	walk(texts)
	return bad
end

return Shop
