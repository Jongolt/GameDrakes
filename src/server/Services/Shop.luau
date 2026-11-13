--!strict
-- 2.1: ShopService (spec 07 §4-6, 10 §3). ProcessReceipt: idempotent by PurchaseId, a grant counts as done only
-- after a real profile save (ProfileStore LastSavedData / OnAfterSave); while the profile loads - wait for it or for the player leaving.
-- Passes: UserOwnsGamePassAsync on join (an error - a retry, the profile flag as a fallback) and PromptGamePassPurchaseFinished. ShopIntent:
-- the client names the SKU (or the class HatchNow/GrowNow with a target) - the server checks, computes the step by the remainder, remembers the intent
-- (the target, the Starter elements, the gift recipient in the profile) and returns the product id for PromptProductPurchase; a ticket instead of a purchase if
-- there is one. Gifts: the product Gift_<sku>, to the recipient - ProfileStore mail (MessageAsync, reliable) plus straight into the hands if he is on the server
-- (a duplicate by PurchaseId is cut off by giftsReceived). PolicyService on join into the profile (policy). The boost ticks in Nest through Shop.tick.
-- No prices in the code: the client takes them from GetProductInfoAsync. Studio debugging: LoopDebug "shop <sku> [pick]" - a receipt without Robux.
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local PolicyService = game:GetService("PolicyService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local ShopIds = require(Shared:WaitForChild("ShopIds"))
local Core = Shared:WaitForChild("Core")
local ShopCore = require(Core:WaitForChild("Shop"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local IndexCore = require(Core:WaitForChild("Index"))
local Content = require(Shared:WaitForChild("Content")) -- the update dates (Shop.onSale)

local Shop = {}

local services: { [string]: any } = {}
local B = Config.Balance
local S = Config.Shop
ShopCore.setup(S)

type Intent = { sku: string, slot: string?, uid: string?, pick: { string }?, giftTo: number?, at: number, odds: boolean? }
local intents: { [Player]: Intent } = {}
-- paid randomness (Starter Pack) - only for those whom
-- Roblox allows it (PolicyService ArePaidRandomItemsRestricted = false, read in THIS session); for the rest and before the read -
-- the same pack without randomness. The player attribute PaidRandomOK (true/false) - the showcase shows the needed variant and the odds
local paidRandomOK: { [Player]: boolean } = {}
local forcePolicy: { [Player]: boolean } = {} -- only debug "policy open|restricted" (Admin/ClientDebug)
local boostSync: { [Player]: number } = {} -- when the boost key last went to the client
local rng = Random.new()

-- product id -> SKU key (including Gift_*), key -> id
local productKey: { [number]: string } = {}
local passKey: { [number]: string } = {}
for k, id in ShopIds.products do
	productKey[id] = k
end
for k, id in ShopIds.passes do
	passKey[id] = k
end


-- the name for the client notification - a Loc.text template (the client translates)
local function nameOf(key: string): any
	local sku = ShopCore.resolve(key)
	if not sku then
		return key
	end
	local N = Strings.Shop.names
	if sku.class == "treats" then
		return Loc.text(N.treats, { n = sku.n })
	elseif sku.class == "boost" then
		return Loc.text(N.boost, { time = if (sku.minutes :: number) >= 60 then tostring((sku.minutes :: number) / 60) .. " h" else tostring(sku.minutes) .. " min" })
	elseif sku.class == "income" then
		return Loc.text(N.income, { time = tostring(sku.hours) .. " h" })
	elseif sku.class == "hatchNow" or sku.class == "growNow" then
		return Loc.text(N[sku.class])
	end
	return Loc.text(N[sku.key] or sku.key)
end
Shop.nameOf = nameOf

-- the nest income without the temporary boost (Nest income 07 §4) - the permanent passes count
local function rateNoBoost(data: any): number
	local mods = ShopCore.rateMods(data, IndexCore.pct(data.index))
	mods.boost = false
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

-- ---------------------------------------------------------------------------------------------- the grant into the profile
-- after the grant: what to refresh in the world (slots, incubators, the shelf) and what to tell the player
local function afterGrant(player: Player, key: string, g: any)
	local sku = ShopCore.resolve(key)
	if not sku then
		return
	end
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	services.PlayerData.replicate(player, { "owned", "items", "boost", "coins", "eggs", "dragons", "incubators", "glowEgg" })
	if g.applied == "slot" and g.slot == "glow" then -- the golden egg on the pedestal - ready now
		if services.GlowEgg and services.GlowEgg.resync then
			services.GlowEgg.resync(player)
		end
	elseif g.applied == "slot" and services.Incubation and services.Incubation.resync then
		services.Incubation.resync(player, g.slot)
	elseif g.applied == "dragon" then
		services.Nest.refresh(player)
	elseif g.applied == "dragonWeek" then -- the hatchling of the week in the nest or the sanctuary, the Index entry, the preset on it
		services.PlayerData.replicate(player, { "nestOrder", "index", "companion", "nextUid" })
		services.Nest.refresh(player)
		if services.Index and g.indexKey then
			pcall(services.Index.onHatched, player, data, g.indexKey, g.wasNew == true)
		end
		if services.Looks and services.Looks.refresh then
			task.spawn(services.Looks.refresh, player)
		end
	elseif g.applied == "flag" or sku.class == "starter" then
		services.Nest.refresh(player) -- slots from passes, the incubator, the shelf
		if services.Incubation and services.Incubation.restore then
			services.Incubation.restore(player)
		end
		if services.EggSpawner and services.EggSpawner.tableEggs then
			services.EggSpawner.tableEggs(player)
		end
		if sku.class == "starter" and services.Analytics then -- which variant was bought (countries with the ban - random 0)
			services.Analytics.custom(player, "starter_variant", 1, { random = if g.random then 1 else 0 })
		end
	elseif g.applied == "coins" then
		services.Nest.addCoins(player, 0, "Shop") -- the leaderboard/counter only (the coins are already credited in grant)
		if services.Analytics then -- 11 §2: Source Shop with the SKU
			services.Analytics.coins(player, "Source", g.coins or 0, data.coins or 0, "Shop", sku.key)
		end
	end
	-- looks (07 add. 2.6): the nest skin and aura, the VIP tag / the title above the head, the scarf - visible right after a purchase or a gift
	if (g.applied == "look" or g.applied == "flag" or sku.class == "starter") and services.Looks and services.Looks.refresh then
		task.spawn(services.Looks.refresh, player) -- no waiting in the receipt path
	end
	if sku.look and sku.look.group == "presets" and services.Looks and services.Looks.autoEquip then
		task.spawn(services.Looks.autoEquip, player, sku.look.id) -- the preset at once onto the companion (if on nobody yet)
	end
	local A = Strings.Shop.applied
	local text = A[g.applied or ""] or Strings.Shop.bought
	local dname = ""
	if g.uid and data.dragons and data.dragons[g.uid] then
		dname = data.dragons[g.uid].name or ""
	end
	local timeText = ""
	if sku.class == "boost" then
		timeText = if (sku.minutes :: number) >= 60 then tostring((sku.minutes :: number) / 60) .. " h" else tostring(sku.minutes) .. " min"
	end
	services.Net.notice(player, { kind = "purchase", sku = sku.key, name = nameOf(sku.key), applied = g.applied, text = Loc.text(text, { name = dname, time = timeText, coins = g.coins or 0 }) })
end

local function grantTo(player: Player, data: any, key: string, intent: Intent?): any
	local ctx: ShopCore.Ctx = {
		now = os.time(),
		rate = rateNoBoost(data),
		rng = function()
			return rng:NextNumber()
		end,
		pick = intent and intent.pick,
		elements = Config.Elements,
		B = B,
		S = S,
		slot = intent and intent.slot,
		uid = intent and intent.uid,
		slots = if services.Nest and services.Nest.slotsTotal then services.Nest.slotsTotal(data) else nil,
		-- the flag is checked once more at the grant moment: no intent (a receipt on another server) or the flag changed - without randomness
		randomStarter = intent ~= nil and intent.odds == true and paidRandomOK[player] == true,
	}
	return ShopCore.grant(data, key, ctx)
end

-- ---------------------------------------------------------------------------------------------- gifts
local function deliverGift(toPlayer: Player, msg: any): boolean
	local data = services.PlayerData.get(toPlayer)
	if not data or not services.PlayerData.canSave(toPlayer) then
		return false
	end
	data.giftsReceived = data.giftsReceived or {}
	local pid = tostring(msg.pid or "")
	if pid ~= "" and data.giftsReceived[pid] then
		return true -- already received (the direct grant + the mail)
	end
	local g = grantTo(toPlayer, data, msg.sku, nil)
	if not g.ok then
		return false
	end
	if pid ~= "" then
		data.giftsReceived[pid] = os.time()
	end
	afterGrant(toPlayer, msg.sku, g)
	services.Net.notice(toPlayer, { kind = "gift", from = tostring(msg.from or ""), item = nameOf(msg.sku), text = Loc.text(Strings.Shop.giftReceived, { name = msg.from or "", item = nameOf(msg.sku) }) })
	if services.Analytics then
		services.Analytics.custom(toPlayer, "gift_received", 1, { sku = msg.sku })
	end
	return true
end

-- ---------------------------------------------------------------------------------------------- ProcessReceipt (07 §4)
local function waitSaved(profile: any, pid: string): boolean
	if profile.LastSavedData and profile.LastSavedData.purchases and profile.LastSavedData.purchases[pid] then
		return true
	end
	local done = false
	local conn = profile.OnAfterSave:Connect(function(last: any)
		if last and last.purchases and last.purchases[pid] then
			done = true
		end
	end)
	profile:Save()
	local deadline = os.clock() + S.saveWaitSeconds
	while not done and os.clock() < deadline do
		task.wait(0.25)
	end
	conn:Disconnect()
	return done
end

local function pruneOld(data: any, now: number)
	local keep = S.purchasesKeepDays * 86400
	for pid, t in data.purchases do
		if typeof(t) == "number" and now - t > keep then
			data.purchases[pid] = nil
		end
	end
end

local function process(receipt: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local profile = services.PlayerData.waitProfileOrLeave(player, S.receiptWaitSeconds)
	if not profile or not services.PlayerData.canSave(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = profile.Data
	data.purchases = data.purchases or {}
	local pid = tostring(receipt.PurchaseId)
	if data.purchases[pid] then
		return if waitSaved(profile, pid) then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local key = productKey[receipt.ProductId]
	if not key then
		warn("[Shop] a receipt for an unknown product " .. tostring(receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local sku, isGift = ShopCore.resolve(key)
	if not sku then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local intent = intents[player]
	if intent and intent.sku ~= key then
		intent = nil
	end
	if not intent and sku.class == "starter" and typeof(data.pendingPick) == "table" then
		-- the receipt came without an intent (another server, a restart) - the elements from the profile, the variant without randomness
		intent = { sku = key, pick = data.pendingPick, at = os.time(), odds = false }
	end
	local now = os.time()
	local giftTo: number? = nil
	local starterRandom: boolean? = nil -- which Starter Pack variant was granted (the purchase log - for support and the P8 probe)
	local duplicate: boolean? = nil -- a receipt for an already granted one-time SKU, closed without a grant
	if isGift then
		data.pendingGift = data.pendingGift or {}
		giftTo = tonumber(data.pendingGift[tostring(receipt.ProductId)]) or (intent and intent.giftTo)
		if giftTo then
			local msg = { sku = sku.key, from = player.Name, pid = pid, t = now }
			local okMail, sent = pcall(function()
				return services.PlayerData.message(tostring(giftTo), msg)
			end)
			if not okMail or not sent then
				warn("[Shop] the gift mail did not go: " .. tostring(sent))
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			local toPlayer = Players:GetPlayerByUserId(giftTo)
			if toPlayer then
				pcall(deliverGift, toPlayer, msg) -- straight into the hands; the mail is cut off later by pid
			end
			data.pendingGift[tostring(receipt.ProductId)] = nil
		else
			-- the recipient is unknown (the receipt came after a restart without an intent): grant to the buyer so the payment is not lost
			local g = grantTo(player, data, sku.key, nil)
			if not g.ok then
				return Enum.ProductPurchaseDecision.NotProcessedYet
			end
			afterGrant(player, sku.key, g)
			if services.Analytics then
				services.Analytics.custom(player, "gift_no_recipient", 1, { sku = sku.key })
			end
		end
	else
		local g = grantTo(player, data, key, intent)
		if not g.ok and g.reason == "already" then
			-- a one-time SKU is already granted (a receipt bypassing the showcase: PromptProductPurchase from the client) - no second grant
			-- but the receipt is closed, otherwise NotProcessedYet repeats on every join of the player forever
			warn("[Shop] receipt " .. pid .. " for the already granted " .. key .. " - closed without a grant")
			duplicate = true
			if services.Analytics then
				services.Analytics.custom(player, "purchase_duplicate", 1, { sku = key })
			end
		elseif not g.ok then
			warn("[Shop] the grant of " .. key .. " failed: " .. tostring(g.reason))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		else
			afterGrant(player, key, g)
			if sku.class == "starter" then
				starterRandom = g.random == true
			end
		end
		if sku.class == "starter" then
			data.pendingPick = nil
		end
	end
	intents[player] = nil
	data.purchases[pid] = now
	pruneOld(data, now)
	data.purchaseLog = data.purchaseLog or {}
	table.insert(data.purchaseLog, { t = now, sku = key, robux = receipt.CurrencySpent or 0, giftTo = giftTo or 0, random = starterRandom, duplicate = duplicate })
	while #data.purchaseLog > S.purchaseLogMax do
		table.remove(data.purchaseLog, 1)
	end
	data.analytics = data.analytics or {}
	data.analytics.purchasesCount = (data.analytics.purchasesCount or 0) + 1
	data.analytics.firstPurchaseAt = data.analytics.firstPurchaseAt or now
	data.analytics.lastPurchaseAt = now
	if not waitSaved(profile, pid) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if services.Analytics and services.Analytics.purchase then
		services.Analytics.purchase(player, key, receipt.CurrencySpent or 0, giftTo)
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- ---------------------------------------------------------------------------------------------- passes
local function applyPass(player: Player, key: string, why: string)
	local data = services.PlayerData.get(player)
	local sku = ShopCore.get(key)
	if not data or not sku or sku.kind ~= "pass" then
		return
	end
	if ShopCore.owned(data, sku) then
		return
	end
	local g = grantTo(player, data, key, nil)
	if g.ok then
		afterGrant(player, key, g)
		local price = tonumber(string.match(key, "_(%d+)$")) -- the price in the SKU key (X2Coins_299); GetProductInfoAsync is not called here
		if not price then
			warn("[Shop] applyPass: no price in the key - " .. key) -- a receipt with 0 without a signal
			price = 0
		end
		if why == "purchase" then -- a pass purchase into the journal, like ProcessReceipt receipts (the first payer's VIP was not seen by the probe)
			data.purchaseLog = data.purchaseLog or {}
			table.insert(data.purchaseLog, { t = os.time(), sku = key, robux = price, giftTo = 0, pass = true })
			while #data.purchaseLog > S.purchaseLogMax do
				table.remove(data.purchaseLog, 1)
			end
			data.analytics = data.analytics or {}
			data.analytics.purchasesCount = (data.analytics.purchasesCount or 0) + 1
		end
		services.PlayerData.save(player)
		if services.Analytics and why == "purchase" then
			services.Analytics.purchase(player, key, price, nil)
		end
	end
end

local function checkPasses(player: Player)
	if RunService:IsStudio() then
		return -- Studio answers "owns" for all the creator's passes: not written to the profile; the check - LoopDebug "shop pass <key>"
	end
	local attempt = 0
	while player.Parent == Players do
		attempt += 1
		local failed = false
		for key, id in ShopIds.passes do
			if player.Parent ~= Players then
				return
			end
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
			end)
			if ok then
				if owns then
					applyPass(player, key, "join")
				end
			else
				failed = true
			end
		end
		if not failed or attempt >= 5 then
			return
		end
		task.wait(S.passRetrySeconds)
	end
end

local function readPolicy(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	data.policy = data.policy or {}
	if ok and typeof(info) == "table" then
		for k, v in info :: any do
			if typeof(v) == "boolean" then
				data.policy[k] = v
			end
		end
		data.policy.ok = true
	else
		data.policy.ok = false -- an error: all restrictions are treated as on (07 §6)
	end
	local allowed = ok and typeof(info) == "table" and (info :: any).ArePaidRandomItemsRestricted == false
	if forcePolicy[player] ~= nil then -- a P8 probe (debug policy): Studio does not allow changing the country
		allowed = forcePolicy[player] :: boolean
	end
	paidRandomOK[player] = allowed
	player:SetAttribute("PaidRandomOK", allowed)
	if services.Analytics then -- policy_flags on join; restricted = 1 - paid randomness is closed or the policy was not read
		local restricted = not ok or (info :: any).ArePaidRandomItemsRestricted == true
		services.Analytics.custom(player, "policy_flags", 1, { restricted = if restricted then 1 else 0, read = if ok then 1 else 0 })
	end
end

-- ---------------------------------------------------------------------------------------------- the intent (ShopIntent)
local function parsePick(pick: string?): { string }
	local out = {}
	for w in string.gmatch(pick or "", "[%w_]+") do
		table.insert(out, w)
	end
	return out
end

function Shop.intent(player: Player, skuArg: string, giftTo: number?, pick: string?): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if not services.PlayerData.canSave(player) then
		return { ok = false, reason = "forbidden" } -- the profile is not saved: not selling (07 §4)
	end
	local now = os.time()
	local picks = parsePick(pick)
	local key = skuArg
	local intent: Intent = { sku = key, at = now }
	-- the class by the target's remainder: HatchNow <slot>, GrowNow <uid>
	if skuArg == "HatchNow" or skuArg == "GrowNow" then
		local class = if skuArg == "HatchNow" then "hatchNow" else "growNow"
		local target = picks[1]
		local rem: number? = nil
		if class == "hatchNow" then
			if not target then
				target = ShopCore.longestHatch(data, now)
			end
			rem = if target then ShopCore.hatchRemaining(data, target :: string, now) else nil
			if not rem or rem < S.hatchNow.minRemaining then
				return { ok = false, reason = "no_target" }
			end
			intent.slot = target
		else
			if not target then
				target = ShopCore.longestGrow(data, now)
			end
			rem = if target then ShopCore.growRemaining(data, target :: string, now) else nil
			if not rem or rem < S.growNow.minRemaining then
				return { ok = false, reason = "no_target" }
			end
			intent.uid = target
		end
		if class == "hatchNow" and not S.hatchNowEnabled then
			return { ok = false, reason = "forbidden" }
		end
		-- a ticket covers it: applied without a purchase
		local used: number? = nil
		services.PlayerData.update(player, { "items", "eggs", "dragons" }, function(_, d)
			used = ShopCore.useTicket(d, class, target :: string, now, S)
			return nil
		end)
		if used then
			local g = { ok = true, applied = if class == "hatchNow" then "slot" else "dragon", slot = intent.slot, uid = intent.uid, tier = used }
			afterGrant(player, ShopCore.tierKey(class, used, S), g)
			services.Net.notice(player, { kind = "toast", text = Loc.text(Strings.Shop.ticketUsed, { name = nameOf(ShopCore.tierKey(class, used, S)) }) })
			return { ok = true, ticket = true }
		end
		local tier = ShopCore.tierOf(rem :: number, S)
		key = ShopCore.tierKey(class, tier, S)
		intent.sku = key
	end
	local sku, isGift = ShopCore.resolve(key)
	if not sku then
		return { ok = false, reason = "bad_request" }
	end
	if isGift then
		return { ok = false, reason = "bad_request" } -- a gift is named by the base SKU + giftTo
	end
	local onSale, saleWhy = ShopCore.onSale(sku, if services.LiveOps then services.LiveOps.live() else 0,
		if services.LiveOps then services.LiveOps.now() else os.time(), Content.Updates) -- only from the update date
	if not onSale then
		return { ok = false, reason = saleWhy or "locked" }
	end
	if giftTo then
		if not sku.gift then
			return { ok = false, reason = "bad_request" }
		end
		if giftTo == player.UserId then
			return { ok = false, reason = "bad_request" }
		end
		local toPlayer = Players:GetPlayerByUserId(giftTo)
		if not toPlayer then
			return { ok = false, reason = "no_player" }
		end
		-- regional prices (07 §5 item 2): the buyer's tier no lower than the recipient's - gap; on an API error we do not block
		local okLv, levels = pcall(function()
			return (MarketplaceService :: any):GetUsersPriceLevelsAsync({ player.UserId, giftTo })
		end)
		if okLv and typeof(levels) == "table" then
			local lv: { [number]: number } = {}
			for _, rec in levels :: { any } do
				if typeof(rec) == "table" and rec.UserId then
					lv[rec.UserId] = rec.PriceLevel or 0
				end
			end
			if (lv[player.UserId] or 0) < (lv[giftTo] or 0) - S.giftLevelGap then
				return { ok = false, reason = "region" }
			end
		end
		local giftProduct = ShopIds.products[ShopCore.giftKey(sku.key)]
		if not giftProduct then
			return { ok = false, reason = "bad_request" }
		end
		intent.sku = ShopCore.giftKey(sku.key)
		intent.giftTo = giftTo
		intents[player] = intent
		services.PlayerData.update(player, "pendingGift", function(p, d)
			d.pendingGift = if typeof(d.pendingGift) == "table" then d.pendingGift else {}
			d.pendingGift[tostring(giftProduct)] = giftTo
			return nil
		end)
		if services.Analytics then
			services.Analytics.custom(player, "shop_intent", 1, { sku = sku.key, gift = "1" })
			services.Analytics.shopStep(player, 3, "purchase_prompt", { sku = sku.key })
		end
		return { ok = true, productId = giftProduct, key = intent.sku, gift = true }
	end
	local sellable, why = ShopCore.sellable(data, sku)
	if not sellable then
		return { ok = false, reason = why }
	end
	if sku.class == "starter" then
		local valid = {}
		for _, el in picks do
			if table.find(Config.Elements, el) then
				table.insert(valid, el)
			end
		end
		if #valid < S.starter.eggs then
			return { ok = false, reason = "bad_request" }
		end
		intent.pick = valid
		-- a random variant - only if the client showed the odds (the word odds in the choice) and Roblox allows the player paid randomness
		intent.odds = table.find(picks, "odds") ~= nil and paidRandomOK[player] == true
		-- the element choice in the profile before the receipt - a receipt on another server grants the chosen elements, not two Embers
		services.PlayerData.update(player, "pendingPick", function(_, d)
			d.pendingPick = table.clone(valid)
			return nil
		end)
	end
	intents[player] = intent
	if services.Analytics then
		services.Analytics.custom(player, "shop_intent", 1, { sku = key })
		services.Analytics.shopStep(player, 3, "purchase_prompt", { sku = key })
	end
	if sku.kind == "pass" then
		return { ok = true, passId = ShopIds.passes[sku.key], key = sku.key, pass = true }
	end
	return { ok = true, productId = ShopIds.products[sku.key], key = sku.key }
end

-- a treat from the stock (07 §2 no. 8): the dragon card, the remainder > 60 s
function Shop.treat(player: Player, uid: string): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if not data.items or (data.items.treats or 0) <= 0 then
		return { ok = false, reason = "no_treats" }
	end
	local d = data.dragons[uid]
	if not d then
		return { ok = false, reason = "no_dragon" }
	end
	local rem = ShopCore.growRemaining(data, uid, os.time())
	if not rem or rem < S.growNow.minRemaining then
		return { ok = false, reason = "not_ready" }
	end
	local ok = false
	services.PlayerData.update(player, { "items", "dragons" }, function(_, dd)
		ok = ShopCore.useTreat(dd, uid, os.time(), B)
		return nil
	end)
	if not ok then
		return { ok = false, reason = "not_ready" }
	end
	services.Nest.refresh(player)
	if services.Analytics then
		services.Analytics.custom(player, "treat_used", 1, {})
	end
	return { ok = true, treats = data.items.treats }
end

-- the boost tick from Nest (every LP.tickSeconds): the seconds run only online; the boost key to the client every replicateEvery and at the end
function Shop.tick(player: Player, data: any, dt: number)
	local b = data.boost
	if typeof(b) ~= "table" or (b.secondsLeft or 0) <= 0 then
		return
	end
	b.secondsLeft = math.max(0, b.secondsLeft - dt)
	local now = os.clock()
	if b.secondsLeft <= 0 or (now - (boostSync[player] or 0)) >= S.boost.replicateEvery then
		boostSync[player] = now
		services.PlayerData.replicate(player, { "boost" })
	end
end

-- the income modifiers for Economy.nestRate (Nest, Movement, Quest, Index)
function Shop.rateMods(data: any): { [string]: any }
	return ShopCore.rateMods(data, IndexCore.pct(data.index))
end

function Shop.hasAutoCollect(data: any): boolean
	return ShopCore.has(data, "autoCollect")
end

function Shop.hasFastIncubator(data: any): boolean
	return ShopCore.has(data, "fastIncubator")
end

function Shop.passSlots(data: any): number
	return ShopCore.passSlots(data, B)
end

-- Studio only (LoopDebug "shop <sku|HatchNow|GrowNow> [pick]"): a receipt without Robux through the same ProcessReceipt; "shop pass <key>"
-- "shop state" - ownership, tickets, treats, the boost
function Shop.debug(player: Player, arg: string): any
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local words = parsePick(arg)
	local what = words[1] or "state"
	if what == "state" then
		local o = data.owned or {}
		local flags = {}
		for k, v in o do
			table.insert(flags, k .. "=" .. (if typeof(v) == "table" then "{" .. tostring(next(v)) .. "}" else tostring(v)))
		end
		table.sort(flags)
		return { ok = true, reason = string.format("owned[%s] treats=%d hatchT=%d growT=%d boost=%d coins=%d inc=%d slots=%d purchases=%d",
			table.concat(flags, ","), (data.items and data.items.treats) or 0, ShopCore.ticketCount(data, "hatchNow"), ShopCore.ticketCount(data, "growNow"),
			(data.boost and data.boost.secondsLeft) or 0, math.floor(data.coins or 0), data.incubators or 1, services.Nest.slotsTotal(data), (function()
				local n = 0
				for _ in (data.purchases or {}) :: { [string]: any } do
					n += 1
				end
				return n
			end)()) }
	elseif what == "pass" then
		applyPass(player, words[2] or "", "purchase")
		return { ok = true, reason = "pass " .. tostring(words[2]) }
	elseif what == "policy" then -- "shop policy open|restricted" - as if Roblox allowed / closed paid randomness (a P8 probe)
		local open = words[2] == "open"
		forcePolicy[player] = open
		paidRandomOK[player] = open
		player:SetAttribute("PaidRandomOK", open)
		return { ok = true, reason = "PaidRandomOK=" .. tostring(open) }
	elseif what == "allow" then -- the second session: the context Robux buttons and the Starter card at once
		services.PlayerData.update(player, "sessions", function()
			return math.max(2, data.sessions or 1)
		end)
		return { ok = true, reason = "sessions=" .. tostring(data.sessions) }
	end
	local pick = table.concat(words, ",", 2)
	local reply = Shop.intent(player, what, nil, pick)
	if not reply.ok then
		return reply
	end
	if reply.ticket then
		return { ok = true, reason = "ticket used" }
	end
	local id = reply.productId or reply.passId
	if reply.pass then
		applyPass(player, reply.key, "purchase")
		return { ok = true, reason = "pass granted " .. tostring(reply.key) }
	end
	local decision = process({ PurchaseId = "dbg-" .. tostring(math.floor(os.clock() * 1000)), PlayerId = player.UserId, ProductId = id, CurrencySpent = 0, CurrencyType = Enum.CurrencyType.Robux, PlaceIdWherePurchased = game.PlaceId })
	return { ok = decision == Enum.ProductPurchaseDecision.PurchaseGranted, reason = tostring(decision) .. " " .. tostring(reply.key) }
end

function Shop.init(s: { [string]: any })
	services = s
end

function Shop.start()
	MarketplaceService.ProcessReceipt = function(receipt: any)
		local ok, decision = pcall(process, receipt)
		if not ok then
			warn("[Shop] ProcessReceipt: " .. tostring(decision))
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end
		return decision
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		local key = passKey[passId]
		if wasPurchased and key then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if (ok and owns) or RunService:IsStudio() then
				applyPass(player, key, "purchase")
			end
		end
	end)
	services.Net.handle("ShopIntent", function(player: Player, sku: string, giftTo: number?, pick: string?)
		return Shop.intent(player, sku, giftTo, pick)
	end)
	services.Net.handle("Treat", function(player: Player, uid: string)
		return Shop.treat(player, uid)
	end)
	services.PlayerData.onMessage(function(player: Player, message: any): boolean
		if typeof(message) == "table" and message.sku and ShopCore.resolve(tostring(message.sku)) then
			return deliverGift(player, message)
		end
		return false
	end)
	services.PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(readPolicy, player)
		task.spawn(checkPasses, player)
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		intents[player] = nil
		paidRandomOK[player] = nil
		forcePolicy[player] = nil
		boostSync[player] = nil
	end)
end

return Shop
