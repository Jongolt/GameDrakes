--!strict
-- Shop spec (spec 07 §9, 10 §10): the Core/Shop catalog against ShopIds (all SKUs are set up in Roblox and there are no extra ones), gift
-- copies for everything except Hatch Now / Grow Now / Starter (07 §5 item 5), grant determinism with the same state, tiers and tickets,
-- Starter Pack, Bundle, slots from passes, income modifiers, stop words in the shop texts.
-- Run from the repository root: luau tests/shop_spec.luau

local Config = require("../src/shared/Config")
local Strings = require("../src/shared/Strings")
local ShopIds = require("../src/shared/ShopIds")
local Shop = require("../src/shared/Core/Shop")
local Economy = require("../src/shared/Core/Economy")
local Dragons = require("../src/shared/Core/Dragons")

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
local function deepcopy(t: any): any
	if type(t) ~= "table" then
		return t
	end
	local out = {}
	for k, v in t do
		out[k] = deepcopy(v)
	end
	return out
end
local function count(t: any): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- catalog <-> Roblox ids ---------------------------------------------------------------------
local keys = Shop.allKeys()
check("catalog: 57 items (34 SKU + 23 Gift; 17.10: + Tidal, Night Sky, Dragons of the week 1-2)", #keys == 57, #keys)
local ids: { [string]: number } = {}
for k, v in ShopIds.passes do
	ids[k] = v
end
for k, v in ShopIds.products do
	ids[k] = v
end
for _, k in keys do
	check("Roblox id exists: " .. k, (ids[k] or 0) > 0)
end
check("no extra ids", count(ids) == #keys, count(ids))
for _, sku in Shop.catalog() do
	check("kind in ShopIds: " .. sku.key, if sku.kind == "pass" then ShopIds.passes[sku.key] ~= nil else ShopIds.products[sku.key] ~= nil)
end
local seen: { [number]: boolean } = {}
for k, v in ids do
	check("id is unique: " .. k, not seen[v])
	seen[v] = true
end

-- gifts (07 §5 item 5) ---------------------------------------------------------------------------
for _, sku in Shop.catalog() do
	local noGift = sku.class == "hatchNow" or sku.class == "growNow" or sku.class == "starter"
	check("gift " .. sku.key, sku.gift == not noGift)
	local g, isGift = Shop.resolve(Shop.giftKey(sku.key))
	check("resolve Gift_" .. sku.key, (g ~= nil) == sku.gift and isGift)
end
check("resolve of a foreign key", Shop.resolve("Nope_1") == nil)

-- stop words (07 §9) ----------------------------------------------------------------------------
local bad = Shop.bannedIn(Strings.Shop, Strings.Shop.banned)
check("no stop words in the shop texts", #bad == 0, table.concat(bad, " | "))
check("stop words are caught", #Shop.bannedIn({ x = "Buy now and hurry" }, Strings.Shop.banned) == 2)

-- probe profile --------------------------------------------------------------------------------
local NOW = 1000000
local function profile(): any
	local inv = Dragons.newInventory()
	local data: any = {
		coins = 100, pot = 0, ascension = 0, incubators = 1, shelfCap = 3, slots = { coins = 3 },
		eggs = { shelf = {}, incubating = {
			["1"] = { egg = { element = "ember", rarity = "Common" }, endsAt = NOW + 50 }, -- remainder 50 s -> tier 1
			["2"] = { egg = { element = "moss", rarity = "Rare" }, endsAt = NOW + 900 }, -- 15 min -> tier 3
		} },
		items = { treats = 0, hatchNow = {}, growNow = {} }, owned = {}, boost = { secondsLeft = 0 }, index = {},
		quests = {}, rewards = {}, onboarding = {}, purchases = {}, purchaseLog = {}, giftsReceived = {},
	}
	for k, v in inv :: any do
		data[k] = v
	end
	data.dragons = {
		a = { uid = "a", element = "ember", rarity = "Common", stage = 0, stageEndsAt = NOW + 200, name = "A", inNest = true },
		b = { uid = "b", element = "tide", rarity = "Rare", stage = 1, stageEndsAt = NOW + 5000, name = "B", inNest = true },
		c = { uid = "c", element = "dusk", rarity = "Rare", stage = 3, name = "C", inNest = true },
	}
	data.nestOrder = { "a", "b", "c" }
	return data
end
local function ctx(over: { [string]: any }?): Shop.Ctx
	local c: any = { now = NOW, rate = 10, B = B, S = S, elements = Config.Elements, rng = function()
		return 0.42
	end }
	for k, v in (over or {}) :: { [string]: any } do
		c[k] = v
	end
	return c
end

-- tiers ----------------------------------------------------------------------------------------
check("tier 50 s = 1", Shop.tierOf(50, S) == 1)
check("tier 300 s = 2", Shop.tierOf(300, S) == 2)
check("tier 301 s = 3", Shop.tierOf(301, S) == 3)
check("tier 3600 = 4", Shop.tierOf(3600, S) == 4)
check("tier 2 h = 5", Shop.tierOf(7200, S) == 5)
check("tier key", Shop.tierKey("hatchNow", 3, S) == "HatchNow_19" and Shop.tierKey("growNow", 5, S) == "GrowNow_49")
check("the tier 5 limit is infinite", Shop.tierLimit(5, S) == math.huge)

-- Hatch Now: target by tier, 'or higher', ticket -------------------------------------------------------
do
	local d = profile()
	check("tier 1 target = slot 1", Shop.pickHatchTarget(d, 1, NOW, S) == "1")
	check("tier 3 target without a slot = the longest fitting one (slot 2)", Shop.pickHatchTarget(d, 3, NOW, S) == "2")
	check("tier 1 does not take slot 2", Shop.pickHatchTarget(d, 1, NOW, S, "2") == "1")
	check("tier 5 takes any", Shop.pickHatchTarget(d, 5, NOW, S) == "2")
	local g = Shop.grant(d, "HatchNow_5", ctx({ slot = "1" }))
	check("HatchNow_5 applied to slot 1", g.ok and g.applied == "slot" and g.slot == "1" and d.eggs.incubating["1"].endsAt == NOW, g.applied)
	local g2 = Shop.grant(d, "HatchNow_5", ctx())
	check("HatchNow_5 without a target -> ticket", g2.ok and g2.applied == "ticket" and d.items.hatchNow["1"] == 1, g2.applied)
	check("1 ticket", Shop.ticketCount(d, "hatchNow") == 1)
	d.eggs.incubating["3"] = { egg = { element = "frost", rarity = "Common" }, endsAt = NOW + 30 }
	check("the ticket fires on a fitting egg", Shop.useTicket(d, "hatchNow", "3", NOW, S) == 1 and d.eggs.incubating["3"].endsAt == NOW and d.items.hatchNow["1"] == 0)
	check("the ticket does not fire on a long egg", Shop.useTicket(d, "hatchNow", "2", NOW, S) == nil)
	-- the golden egg on the stand - the "glow" target of the HatchNow ladder (Services/GlowEgg, data.glowEgg.readyAt)
	d.glowEgg = { taken = NOW - 100, readyAt = NOW + 20 * 3600 }
	check("glow: remainder 20 h", Shop.hatchRemaining(d, "glow", NOW) == 20 * 3600)
	check("glow: tier 5 (more than an hour)", Shop.tierOf(Shop.hatchRemaining(d, "glow", NOW) :: number, S) == 5)
	check("glow: tier 1 does not take the stand (the remainder is large)", Shop.pickHatchTarget(d, 1, NOW, S, "glow") == nil)
	check("glow: without a named target the stand is not chosen", Shop.pickHatchTarget(d, 5, NOW, S) ~= "glow")
	local g3 = Shop.grant(d, "HatchNow_49", ctx({ slot = "glow" }))
	check("HatchNow_49 with the glow target: the stand is ready now", g3.ok and g3.applied == "slot" and g3.slot == "glow" and d.glowEgg.readyAt == NOW, g3.applied)
	check("glow: after - remainder 0, no target", Shop.hatchRemaining(d, "glow", NOW) == 0 and Shop.pickHatchTarget(d, 5, NOW, S, "glow") == nil)
	d.glowEgg = { taken = NOW - 100, readyAt = NOW + 40 }
	d.items.hatchNow["1"] = 1
	check("glow: a tier 1 ticket covers 40 s of the stand", Shop.useTicket(d, "hatchNow", "glow", NOW, S) == 1 and d.glowEgg.readyAt == NOW)
	d.glowEgg = { taken = NOW - 100, readyAt = NOW + 3600, hatched = true }
	check("glow: hatched - no target", Shop.hatchRemaining(d, "glow", NOW) == nil)
	check("slot 2 remainder", Shop.hatchRemaining(d, "2", NOW) == 900)
	local slot, rem = Shop.longestHatch(d, NOW)
	check("the longest egg", slot == "2" and rem == 900)
end

-- Grow Now and treats -------------------------------------------------------------------------------
do
	local d = profile()
	check("tier 2 growth target (<= 300 s) = a", Shop.pickGrowTarget(d, 2, NOW, S) == "a")
	check("tier 2 growth target does not take b", Shop.pickGrowTarget(d, 2, NOW, S, "b") == "a")
	local g = Shop.grant(d, "GrowNow_49", ctx({ uid = "b" }))
	check("GrowNow_49 to b", g.ok and g.uid == "b" and d.dragons.b.stageEndsAt == NOW)
	local g2 = Shop.grant(d, "GrowNow_9", ctx({ uid = "c" }))
	check("GrowNow_9 (<= 5 min): c without a timer, a (200 s) fits -> a", g2.ok and g2.uid == "a", g2.uid)
	local g3 = Shop.grant(d, "GrowNow_5", ctx({ uid = "c" }))
	check("GrowNow_5 (<= 1 min): nobody fits -> ticket", g3.ok and g3.applied == "ticket" and d.items.growNow["1"] == 1, g3.applied)
	local d2 = profile()
	check("no treats - cannot apply", Shop.useTreat(d2, "b", NOW, B) == false)
	Shop.grant(d2, "Treats_3_129", ctx())
	check("3 treats", d2.items.treats == 3)
	check("a treat halves the remainder", Shop.useTreat(d2, "b", NOW, B) and d2.dragons.b.stageEndsAt == NOW + 2500 and d2.items.treats == 2)
	check("Gift_Treats_1_49 = +1", Shop.grant(d2, "Gift_Treats_1_49", ctx()).ok and d2.items.treats == 3)
end

-- boost, income, passes, looks ---------------------------------------------------------------------------
do
	local d = profile()
	check("Boost30 = 1800 s", Shop.grant(d, "Boost30_49", ctx()).ok and d.boost.secondsLeft == 1800)
	check("Boost120 stacks", Shop.grant(d, "Boost120_149", ctx()).ok and d.boost.secondsLeft == 1800 + 7200)
	local mods = Shop.rateMods(d, 0)
	check("boost in the modifiers", mods.boost == true and mods.vip == false and mods.x2 == false)
	local g = Shop.grant(d, "NestIncome4h_299", ctx({ rate = 12.5 }))
	check("Nest income 4 h = rate x 14 400", g.ok and g.coins == math.floor(12.5 * 14400) and d.coins == 100 + math.floor(12.5 * 14400), g.coins)
	check("Nest income 1 h is computed", Shop.incomeAmount(3, 1) == 10800)
	check("VIP", Shop.grant(d, "VIP_299", ctx()).ok and d.owned.vip == true and Shop.rateMods(d, 0).vip == true)
	check("x2", Shop.grant(d, "Gift_X2Coins_299", ctx()).ok and Shop.rateMods(d, 0).x2 == true)
	check("slots from passes: VIP = +1", Shop.passSlots(d, B) == 1)
	check("slot II without I - locked", select(2, Shop.sellable(d, Shop.get("NestSlot2_199") :: any)) == "locked")
	check("VIP already owned - owned", select(2, Shop.sellable(d, Shop.get("VIP_299") :: any)) == "owned")
	Shop.grant(d, "NestSlot1_99", ctx())
	check("slot II after I is on sale", (Shop.sellable(d, Shop.get("NestSlot2_199") :: any)))
	Shop.grant(d, "NestSlot2_199", ctx())
	Shop.grant(d, "NestSlot3_399", ctx())
	check("slots from passes: 3 + VIP", Shop.passSlots(d, B) == 4)
	check("looks", Shop.grant(d, "Trail_Comet_149", ctx()).ok and Shop.hasLook(d, "trails", "comet") and Shop.owned(d, Shop.get("Trail_Comet_149") :: any))
	local rate = Economy.nestRate(Dragons.nestList(d) :: any, Shop.rateMods(d, 0) :: any, B)
	check("income with VIP x1.1, x2, boost x2 (Common H 1 + Rare J 96 + Rare E 1600)", math.abs(rate - (1 + 96 + 1600) * 1.1 * 2 * 2) < 0.01, rate)
end

-- Starter Pack and Bundle -----------------------------------------------------------------------------
do
	local d = profile()
	local g = Shop.grant(d, "StarterPack_49", ctx({ pick = { "frost", "storm" } }))
	check("Starter: 2 eggs on the shelf", g.ok and g.eggs == 2 and #d.eggs.shelf == 2, g.eggs)
	check("Starter: the elements as chosen", d.eggs.shelf[1].element == "frost" and d.eggs.shelf[2].element == "storm")
	check("Starter: not below Rare (owner decision 19.10 evening: the lower bound Rare)", d.eggs.shelf[1].rarity == "Rare" and d.eggs.shelf[2].rarity == "Rare", d.eggs.shelf[1].rarity)
	check("Starter: the second incubator", d.incubators == 2 and g.coins == 0)
	check("Starter: the scarf and the flag", d.owned.starter == true and d.owned.scarf == true)
	check("Starter the second time - already", Shop.grant(d, "StarterPack_49", ctx({ pick = { "frost", "storm" } })).reason == "already")
	local d2 = profile()
	d2.incubators = 2
	local g2 = Shop.grant(d2, "StarterPack_49", ctx({ pick = { "ember", "ember" } }))
	check("Starter with 2 incubators - coins", g2.coins == S.starter.incubatorFallbackCoins and d2.coins == 100 + S.starter.incubatorFallbackCoins)
	-- without randomStarter (countries banning paid randomness and by default) - the outcome is known before payment
	for _, r in { 0.00001, 0.5, 0.99999 } do
		local df = profile()
		local gf = Shop.grant(df, "StarterPack_49", ctx({ pick = { "tide", "dusk" }, rng = function()
			return r
		end }))
		local a, b = df.eggs.shelf[1], df.eggs.shelf[2]
		check("Starter without randomness: 2 x " .. S.starter.fixedRarity .. ", without shiny and size (rng " .. r .. ")", gf.ok and gf.random == false
			and a.rarity == S.starter.fixedRarity and b.rarity == S.starter.fixedRarity and not a.shiny and not b.shiny
			and a.size == "normal" and b.size == "normal" and a.element == "tide" and b.element == "dusk", a.rarity .. "/" .. tostring(a.shiny) .. "/" .. a.size)
	end
	local dn = profile()
	Shop.grant(dn, "StarterPack_49", ctx({ pick = nil }))
	check("Starter without randomness and without a choice (the receipt on another server): the element is not rolled", dn.eggs.shelf[1].element == Config.Elements[1]
		and dn.eggs.shelf[2].element == Config.Elements[1], dn.eggs.shelf[1].element)
	-- the random variant: the rarity from the Cliffs slice not below Rare (minRarity), the variants are rolled
	local seen, shiny = {}, 0
	for i = 1, 400 do
		local dr = profile()
		local gr = Shop.grant(dr, "StarterPack_49", ctx({ pick = { "frost", "storm" }, randomStarter = true, rng = function()
			return ((i * 7919 + 13) % 10007) / 10007
		end }))
		for _, e in dr.eggs.shelf do
			seen[e.rarity] = true
			if e.shiny then
				shiny += 1
			end
		end
		if i == 1 then
			check("Starter with randomness: grant.random", gr.random == true)
		end
	end
	check("Starter with randomness: without Common and Uncommon", seen.Common == nil and seen.Uncommon == nil)
	check("Starter with randomness: different rarities drop", seen.Rare and seen.Epic and seen.Legendary, seen)
	-- the odds to show before the purchase: every outcome, sum 100, exactly the slice of the zone table
	local odds = Shop.starterOdds(B, S)
	local sum, ids = 0, {}
	for _, o in odds.rarity do
		sum += o.pct
		table.insert(ids, o.id)
	end
	check("Starter odds: sum 100%", math.abs(sum - 100) < 1e-9, sum)
	check("Starter odds: Rare..Mythic, without Common and Uncommon", table.concat(ids, ",") == "Rare,Epic,Legendary,Mythic", table.concat(ids, ","))
	local z = B.zones[S.starter.zone]
	check("Starter odds: Rare = weight / the sum of weights from Rare", math.abs(odds.rarity[1].pct - z[3] / (z[3] + z[4] + z[5] + z[6]) * 100) < 1e-9, odds.rarity[1].pct)
	local r2 = 0
	for _, o in odds.rarity do
		r2 += tonumber(string.format("%.2f", o.pct)) :: number
	end
	check("Starter odds: rounded to 0.01 the sum is 100.00", math.abs(r2 - 100) < 1e-6, r2)
	check("variant odds: shiny/big/huge from Config", odds.shiny == B.variants.shiny.p * 100 and odds.big == B.variants.big.p * 100 and odds.huge == B.variants.huge.p * 100)
	local d3 = profile()
	check("Bundle: 0 of 5", Shop.bundleOwnedCount(d3) == 0)
	Shop.grant(d3, "NestSlot1_99", ctx())
	check("Bundle: 1 of 5", Shop.bundleOwnedCount(d3) == 1)
	check("Bundle gives everything", Shop.grant(d3, "NestBundle_2999", ctx()).ok and Shop.bundleOwnedCount(d3) == Shop.BUNDLE_ITEMS and d3.owned.bundle and Shop.hasLook(d3, "titles", "nestLord"))
	check("slots after Bundle = 3", Shop.passSlots(d3, B) == 3)
end

-- determinism (07 §9): the same state and ctx -> the same result ---------------------------------
do
	for _, key in keys do
		local a, b = profile(), profile()
		local ga = Shop.grant(a, key, ctx({ slot = "1", uid = "a", pick = { "ember", "tide" } }))
		local gb = Shop.grant(b, key, ctx({ slot = "1", uid = "a", pick = { "ember", "tide" } }))
		local same = ga.ok == gb.ok and ga.applied == gb.applied and ga.coins == gb.coins and ga.slot == gb.slot and ga.uid == gb.uid
		local ja = game == nil and "" or ""
		check("determinism " .. key, same and ga.ok, ga.reason)
		-- after granting the profile has no nil holes in arrays and has numeric/string keys (ProfileStore)
		local function walk(t: any, path: string)
			for k, v in t do
				check("profile key " .. path .. "." .. tostring(k), typeof(k) == "string" or typeof(k) == "number")
				if typeof(v) == "table" then
					walk(v, path .. "." .. tostring(k))
				end
			end
		end
		walk(a, key)
		local _ = ja
	end
	local saved = deepcopy(profile())
	Shop.grant(saved, "Boost30_49", ctx())
	local loaded = deepcopy(saved)
	check("the boost survives saving", loaded.boost.secondsLeft == 1800)
end

-- the update 2-4 products by date and the Dragon of the week
do
	local Content = require("../src/shared/Content")
	local U = Content.Updates
	local dw1, tidal, night, dw2 = Shop.get("DragonWeek_1_199"), Shop.get("Trail_Tidal_149"), Shop.get("NestSkin_Night_299"), Shop.get("DragonWeek_2_299")
	check("the new SKUs in the catalog", dw1 ~= nil and tidal ~= nil and night ~= nil and dw2 ~= nil)
	if dw1 and tidal and night and dw2 then
		check("before update 2 Dragon 1 is not on sale (locked)", select(2, Shop.onSale(dw1, 1, U[2].activeFrom - 1, U)) == "locked")
		check("in the update 2 week it is on sale", (Shop.onSale(dw1, 2, U[2].activeFrom + 3600, U)))
		check("after 7 days - archived (expired)", select(2, Shop.onSale(dw1, 3, U[2].activeFrom + 7 * 86400, U)) == "expired")
		check("Tidal from update 3", not Shop.onSale(tidal, 2, U[3].activeFrom - 1, U) and (Shop.onSale(tidal, 3, U[3].activeFrom, U)))
		check("Tidal does not disappear after a week", (Shop.onSale(tidal, 4, U[3].activeFrom + 30 * 86400, U)))
		check("Night Sky from update 4", not Shop.onSale(night, 3, U[4].activeFrom - 1, U) and (Shop.onSale(night, 4, U[4].activeFrom, U)))
		check("the old SKUs are always on sale", (Shop.onSale(Shop.get("Trail_Comet_149") :: any, 0, 0, U)))
		-- the stand on the plaza - only within the sale window
		local function stand(live: number, now: number): string
			local k = Shop.standSku(live, now, U)
			return if k then k.key else "-"
		end
		check("stand: empty before update 2", stand(1, U[2].activeFrom - 1) == "-")
		check("stand: the update 2 week - Cinder", stand(2, U[2].activeFrom + 3600) == "DragonWeek_1_199")
		check("stand: empty after 7 days", stand(2, U[2].activeFrom + 7 * 86400) == "-" and stand(3, U[3].activeFrom + 3600) == "-")
		check("stand: the update 4 week - Nightfall", stand(4, U[4].activeFrom + 3600) == "DragonWeek_2_299")
		check("stand: empty after the Nightfall window", stand(4, U[4].activeFrom + 7 * 86400 + 1) == "-")
		check("stand: D0 (live 0) empty", stand(0, 0) == "-")
		local d = { coins = 0, dragons = {}, nestOrder = {}, nextUid = 1, index = {}, owned = {} }
		local ctx = { now = U[2].activeFrom + 100, B = Config.Balance, S = Config.Shop, slots = 3 }
		local g = Shop.grant(d, "DragonWeek_1_199", ctx :: any)
		local dr = g.uid and d.dragons[g.uid]
		check("Dragon 1: an Ember Epic Cinder baby with the preset in the nest", g.ok and dr ~= nil and dr.element == "ember" and dr.rarity == "Epic" and dr.name == "Cinder" and dr.preset == "cinder" and dr.stage == 0 and g.where == "nest", g)
		check("Dragon 1: the preset owned, the Index entry is new", Shop.hasLook(d, "presets", "cinder") and d.index["ember:Epic"] == true and g.wasNew == true)
		check("Dragon 1: not a second time (sellable owned, grant already)", select(2, Shop.sellable(d, dw1)) == "owned" and Shop.grant(d, "DragonWeek_1_199", ctx :: any).reason == "already")
		local g2 = Shop.grant(d, "Gift_DragonWeek_2_299", ctx :: any)
		check("Dragon 2 gift: Dusk Legendary Nightfall", g2.ok and g2.uid ~= nil and d.dragons[g2.uid].rarity == "Legendary" and d.dragons[g2.uid].name == "Nightfall")
		check("the cinder preset only for Ember", Config.Looks.presets.cinder.element == "ember")
		check("the Tidal trail and the Night Sky skin in the looks", Config.Looks.trails.tidal ~= nil and Config.Looks.nestSkins.night ~= nil and table.find(Config.Looks.trailOrder, "tidal") ~= nil)
	end
end

-- the storefront (Config.Shop.listed); the hidden ones are not removed and can be bought by key
do
	local shown, kinds = {}, {}
	for _, sku in Shop.catalog() do
		if Shop.listed(sku, S) then
			table.insert(shown, sku.key)
			kinds[if sku.class == "hatchNow" or sku.class == "dragonWeek" then sku.class else sku.key] = true
		end
	end
	local nk = 0
	for _ in kinds do
		nk += 1
	end
	check("storefront: 12 items (Hatch now tiers and the dragon of the week - one each)", nk == 12, nk .. ": " .. table.concat(shown, ","))
	check("storefront: Starter 49 and the 2 999 anchor are visible", Shop.listed(Shop.get("StarterPack_49") :: any, S) and Shop.listed(Shop.get("NestBundle_2999") :: any, S))
	check("storefront: Grow now, treats, boosts, income and VIP are hidden", not Shop.listed(Shop.get("GrowNow_5") :: any, S) and not Shop.listed(Shop.get("VIP_299") :: any, S))
	check("the hidden ones are not removed: Grow now and VIP are found by key (a purchase from the world)", Shop.resolve("GrowNow_5") ~= nil and Shop.resolve("VIP_299") ~= nil)
	check("without the storefront list everything is visible", Shop.listed(Shop.get("VIP_299") :: any, {}))
end

print(string.format("shop spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed checks")
end
