--!strict
-- 2.2: the shop on the client (spec 07 §1-3, add. 2.3-2.4; 02 §6; craft/04 §7.10-7.11 HTTYD: a book with tabs, tiles with
-- a large icon and a green price button, Gift as a separate panel). The `Shop` plaque first on the left; the Shop book tab with the sub-tabs
-- Time / Nest / Coins / Looks / Gifts; a card = icon, title, 1-2 lines, a button with the price from GetProductInfoAsync (5 min cache,
-- on an error `See price` - the Roblox window shows the price), `Owned` for permanent ones; Starter Pack - a choice of two elements; gifts - a list of
-- the server's players (avatar + nick) -> product -> `Gift`. A tone without pressure: no timers and no "worth" (Config.Shop.anchors = false).
-- Purchase: ShopIntent (the server checks and remembers the target) -> PromptProductPurchase / PromptGamePassPurchase -> Notice purchase.
-- Context (07 §2): Hatch now at the incubator (WorldUI) and Grow now / Treat on the card (DragonCard) call Shop.buy; the context Robux buttons
-- not before 3:00 of the first session (Shop.robuxAllowed).
local CollectionService = game:GetService("CollectionService") -- the Dragon of the Week stand (tag DragonStand)
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local ShopIds = require(Shared:WaitForChild("ShopIds"))
local ShopIcons = require(Shared:WaitForChild("ShopIcons")) -- product pictures (runs/roblox_shop_icons_2026-10-16)
local Core = Shared:WaitForChild("Core")
local ShopCore = require(Core:WaitForChild("Shop"))
local Economy = require(Core:WaitForChild("Economy"))
local Dragons = require(Core:WaitForChild("Dragons"))
local IndexCore = require(Core:WaitForChild("Index"))
local Format = require(Core:WaitForChild("Format"))
local LooksCore = require(Core:WaitForChild("Looks")) -- looks
local Content = require(Shared:WaitForChild("Content")) -- the dates of updates 2-4 (ShopCore.onSale)

-- whether the SKU is on sale now - live and the clock shift from ReplicatedStorage (the server LiveOps), as the server will check
local function saleState(sku: ShopCore.Sku): (boolean, string?)
	local live = ReplicatedStorage:GetAttribute("UpdatesLive")
	local off = ReplicatedStorage:GetAttribute("LiveOffset")
	local now = workspace:GetServerTimeNow() + (if typeof(off) == "number" then off else 0)
	return ShopCore.onSale(sku, if typeof(live) == "number" then live else 0, now, Content.Updates)
end
-- the Dragon of the Week after its 7 days stays visible for another week as an "Archived" card (07 §2 no. 12), then disappears
local function showArchived(sku: ShopCore.Sku): boolean
	local u = sku.update and (Content.Updates :: any)[sku.update]
	local off = ReplicatedStorage:GetAttribute("LiveOffset")
	local now = workspace:GetServerTimeNow() + (if typeof(off) == "number" then off else 0)
	return u ~= nil and sku.days ~= nil and now < u.activeFrom + (sku.days :: number) * 2 * 86400
end

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Shop = {}

local me = Players.LocalPlayer
local B = Config.Balance
local S = Config.Shop
local T = Strings.Shop
ShopCore.setup(S)

local loaded: any = nil
local banners: any = nil
local sub = "nest" -- the sub-tab; "nest" by default (Starter and the main passes), "time" is empty without a warming egg
local body: Frame? = nil -- the book tab body while it is open
local gridFrame: ScrollingFrame? = nil
local selectedGift: number? = nil -- the recipient's UserId
local pickMode = false -- the Starter Pack element choice
local picked: { string } = {}
local joinedAt = os.clock()
local playAtJoin = 0
local priceCache: { [string]: { price: number?, at: number } } = {}
local priceWaiters: { [string]: { (number?) -> () } } = {}

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function data(): any
	return Store.all()
end

-- ---------------------------------------------------------------------------------------------- display rules
-- the context Robux buttons: from the 2nd session at once, in the first - from 3:00 (07 §1 item 3)
function Shop.robuxAllowed(): boolean
	local sessions = Store.get("sessions") or 1
	if sessions >= 2 then
		return true
	end
	return (playAtJoin + (os.clock() - joinedAt)) >= S.fromSeconds
end

local function timeWord(minutes: number): string
	return if minutes >= 60 then tostring(minutes / 60) .. " h" else tostring(minutes) .. " min"
end

local function nameOf(sku: ShopCore.Sku): string
	local N = T.names
	if sku.class == "treats" then
		return fmt(N.treats, { n = sku.n })
	elseif sku.class == "boost" then
		return fmt(N.boost, { time = timeWord(sku.minutes :: number) })
	elseif sku.class == "income" then
		return fmt(N.income, { time = tostring(sku.hours) .. " h" })
	elseif sku.class == "hatchNow" or sku.class == "growNow" then
		return Loc.t(N[sku.class])
	end
	return Loc.t(N[sku.key] or sku.key) -- the name also goes into concatenations ("Starter Pack 49 R$"), not only into the label
end
Shop.nameOf = nameOf

local function iconOf(sku: ShopCore.Sku): string
	return T.icons[sku.key] or T.icons[sku.class] or "✨"
end

-- the income without the temporary boost (Nest income "= N coins")
local function rateNoBoost(): number
	local d = data()
	if typeof(d.dragons) ~= "table" then
		return 0
	end
	local mods = ShopCore.rateMods(d, IndexCore.pct(d.index))
	mods.boost = false
	return Economy.nestRate(Dragons.nestList(d) :: any, mods :: any, B)
end

local function lineOf(sku: ShopCore.Sku): string
	local L = T.lines
	if sku.class == "income" then
		return fmt(L.income, { coins = Format.number(ShopCore.incomeAmount(rateNoBoost(), sku.hours :: number)) })
	elseif sku.class == "treats" or sku.class == "boost" or sku.class == "hatchNow" or sku.class == "growNow" then
		return L[sku.class]
	elseif sku.class == "dragonWeek" then
		return Loc.t(L[sku.key] or "") -- {Ember}, {Dusk} - the name after translation
	elseif sku.class == "starter" and me:GetAttribute("PaidRandomOK") ~= true then
		return L.StarterPack_49_fixed -- without randomness (Roblox closes it to the player) and until the server has read the policy
	end
	return L[sku.key] or ""
end

-- the odds of one Starter Pack egg - every outcome in percent, before the buy button
local function pctText(x: number): string
	local t = string.format("%.2f", x)
	t = string.gsub(t, "0+$", "")
	t = string.gsub(t, "%.$", "")
	return t .. "%"
end

local function starterOddsText(): string
	local o = ShopCore.starterOdds(Config.Balance, S)
	local parts, sum = {}, 0
	for _, r in o.rarity do
		table.insert(parts, Loc.t((Strings.Rarity :: any)[r.id] or r.id) .. " " .. pctText(r.pct))
		sum += tonumber(string.format("%.2f", r.pct)) :: number
	end
	local txt = fmt(T.starterOdds, { list = table.concat(parts, ", ") }) .. "\n"
		.. fmt(T.starterVariants, { shiny = pctText(o.shiny), big = pctText(o.big), huge = pctText(o.huge) })
	if math.abs(sum - 100) > 0.001 then
		txt ..= ". " .. Loc.t(T.starterRounded)
	end
	return txt
end

-- ---------------------------------------------------------------------------------------------- prices (GetProductInfoAsync, cache)
local function idOf(key: string): (number?, Enum.InfoType)
	if ShopIds.passes[key] then
		return ShopIds.passes[key], Enum.InfoType.GamePass
	end
	return ShopIds.products[key], Enum.InfoType.Product
end

-- cb(price | nil) right away from the cache or after the request; nil = an API error (the "See price" button)
function Shop.price(key: string, cb: (number?) -> ())
	local c = priceCache[key]
	if c and os.clock() - c.at < S.priceCacheSeconds then
		cb(c.price)
		return
	end
	local w = priceWaiters[key]
	if w then
		table.insert(w, cb)
		return
	end
	priceWaiters[key] = { cb }
	task.spawn(function()
		local id, infoType = idOf(key)
		local price: number? = nil
		if id then
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfoAsync(id, infoType)
			end)
			if ok and typeof(info) == "table" then
				price = tonumber((info :: any).PriceInRobux)
			end
		end
		priceCache[key] = { price = price, at = os.clock() }
		local list = priceWaiters[key] or {}
		priceWaiters[key] = nil
		for _, f in list do
			pcall(f, price)
		end
	end)
end

local function priceText(price: number?): string
	return if price then (T.robux .. " " .. Format.number(price)) else T.seePrice
end

-- ---------------------------------------------------------------------------------------------- purchase
-- ShopIntent -> the Roblox window. sku: a SKU key or the class "HatchNow"/"GrowNow"; pick: the target or the elements; giftTo: UserId
function Shop.buy(sku: string, pick: string?, giftTo: number?): boolean
	local reply = Net.call("ShopIntent", sku, giftTo, pick)
	if not reply.ok then
		if banners then
			banners.toast(Strings.Errors[reply.reason or ""] or Strings.Errors.bad_request)
		end
		return false
	end
	if reply.ticket then
		Sounds.play("stage_up")
		return true
	end
	Sounds.play("button")
	local ok, err = pcall(function()
		if reply.pass then
			MarketplaceService:PromptGamePassPurchase(me, reply.passId)
		else
			MarketplaceService:PromptProductPurchase(me, reply.productId)
		end
	end)
	if not ok then
		warn("[Shop] prompt: " .. tostring(err))
	end
	return ok
end

-- an offer impression - a tab card or a context button visible >= 1 s; the same product
-- no more often than once per Config.Shop.impressionEvery s (RemoteEvent Analytics, the server limits to 5/s)
local seenAt: { [string]: number } = {}
local function onScreen(o: Instance): boolean -- is the label visible: all ancestors Visible, the ScreenGui enabled
	local x: Instance? = o
	while x do
		if x:IsA("GuiObject") and not (x :: GuiObject).Visible then
			return false
		elseif x:IsA("ScreenGui") then
			return (x :: ScreenGui).Enabled
		end
		x = x.Parent
	end
	return false
end
function Shop.impression(sku: string, ctx: string, still: (() -> boolean)?)
	local now = os.clock()
	if seenAt[sku] and now - seenAt[sku] < (S.impressionEvery or 120) then
		return
	end
	seenAt[sku] = now
	task.delay(1, function()
		if still and not still() then
			seenAt[sku] = nil -- gone before a second - not an impression
			return
		end
		local rf = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local ev = rf and rf:FindFirstChild("Analytics")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireServer("offer_impression", { sku = sku, by = ctx })
		end
	end)
end

-- the Hatch Now / Grow Now price for the target by the remaining time (context buttons): cb(text)
function Shop.contextPrice(class: string, remaining: number, cb: (string) -> ())
	local tier = ShopCore.tierOf(remaining, S)
	local key = ShopCore.tierKey(class, tier, S)
	Shop.impression(key, class) -- a context button (dragon card, incubator) is shown
	Shop.price(key, function(p)
		cb(priceText(p))
	end)
end

function Shop.tickets(class: string): number
	return ShopCore.ticketCount(data(), class)
end

function Shop.treats(): number
	local items = Store.get("items")
	return if typeof(items) == "table" then (items.treats or 0) else 0
end

-- is there a ticket that covers this remainder (the button says "Use ticket" instead of the price)
function Shop.ticketFits(class: string, remaining: number): boolean
	local items = Store.get("items")
	local pool = typeof(items) == "table" and (if class == "hatchNow" then items.hatchNow else items.growNow)
	if typeof(pool) ~= "table" then
		return false
	end
	for tier = 1, #S.hatchNow.prices do
		if (pool[tostring(tier)] or 0) > 0 and remaining <= ShopCore.tierLimit(tier, S) then
			return true
		end
	end
	return false
end

-- ---------------------------------------------------------------------------------------------- cards
local CARD = { w = 0.315, h = 0.41, gap = 0.02 } -- two full rows, no cut-off second row
-- cells and strips
-- in pixels from the book body size - the button no smaller than 44 px, so the card no lower than minH; on a narrow body (< narrow px) 2 columns
local FIT = { minH = 150, narrow = 700, scrollbar = 8, barFrac = 0.1, barMin = 44, barMax = 56, gap = 6, noteMin = 28, noteFrac = 0.09 }

local function barHeight(parent: GuiObject): number
	return math.clamp(math.floor(UIKit.unscaled(parent).Y * FIT.barFrac), FIT.barMin, FIT.barMax)
end

local function noteHeight(parent: GuiObject): number
	return math.max(FIT.noteMin, math.floor(UIKit.unscaled(parent).Y * FIT.noteFrac))
end

-- the start of the content under the sub-tab strip (px)
local function topOf(parent: GuiObject): number
	return barHeight(parent) + FIT.gap
end

local function card(parent: Instance, sku: ShopCore.Sku, order: number, big: boolean?, giftTo: number?): Frame
	local f = Instance.new("Frame")
	f.Name = "Card_" .. sku.key
	-- not in the showcase list - the card exists but is hidden (the grid skips it), no impression is counted
	local listed = ShopCore.listed(sku, S)
	f.Visible = listed
	if listed then
		Shop.impression(sku.key, if giftTo then "gift" else "shop", function() -- a tab card visible >= 1 s
			return onScreen(f)
		end)
	end
	f.BackgroundColor3 = rgb(Config.UI.panel.light)
	f.LayoutOrder = order
	UIKit.corner(f, 0.08)
	UIKit.stroke(f, if big then Color3.fromRGB(235, 150, 60) else UIKit.BORDER, if big then 3 else 2)
	local iconId = (ShopIcons :: any)[sku.key] -- the product picture (the same as in the Roblox purchase window) instead of an emoji
	if typeof(iconId) == "number" and iconId > 0 then
		local img = Instance.new("ImageLabel")
		img.Name = "Icon"
		img.BackgroundTransparency = 1
		img.Image = "rbxassetid://" .. tostring(iconId)
		img.ScaleType = Enum.ScaleType.Fit
		img.Position = UDim2.fromScale(0.04, 0.04)
		img.Size = UDim2.fromScale(0.3, 0.3)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = img
		UIKit.corner(img, 0.18)
		img.Parent = f
	else
		UIKit.iconText(f, iconOf(sku), { Position = UDim2.fromScale(0.04, 0.04), Size = UDim2.fromScale(0.3, 0.3) })
	end
	UIKit.goldText(f, nameOf(sku), { Position = UDim2.fromScale(0.36, 0.05), Size = UDim2.fromScale(0.6, 0.16), TextXAlignment = Enum.TextXAlignment.Left })
	local line = lineOf(sku)
	local d = data()
	if sku.class == "bundle" then
		local k = ShopCore.bundleOwnedCount(d)
		if k > 0 and k < ShopCore.BUNDLE_ITEMS then
			line = Loc.t(line) .. ". " .. fmt(T.alreadyOwn, { k = k, n = ShopCore.BUNDLE_ITEMS })
		end
	end
	UIKit.text(f, line, Color3.fromRGB(225, 220, 205), { Name = "Line", Position = UDim2.fromScale(0.05, 0.34), Size = UDim2.fromScale(0.9, 0.3), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
	local owned = (sku.flag or sku.look) and ShopCore.owned(d, sku)
	local sellable, why = ShopCore.sellable(d, sku)
	local onSale, saleWhy = saleState(sku) -- the Dragon of the Week after its window - Archived
	if not onSale and sellable then -- for a buyer - "You own this", not Archived
		sellable, why = false, saleWhy
	end
	local btn = UIKit.button(f, "", UIKit.GREEN, function(b)
		if owned or not sellable then
			UIKit.shake(b)
			return
		end
		if sku.class == "starter" then
			pickMode = true
			picked = {}
			Shop.render()
			return
		end
		if sku.class == "hatchNow" then
			Shop.buy("HatchNow", nil, nil)
		elseif sku.class == "growNow" then
			Shop.buy("GrowNow", nil, nil)
		else
			Shop.buy(sku.key, nil, giftTo)
		end
	end)
	-- pressed to the card bottom - the minimum 44 px grow upward, not under the next row
	btn.Name = "Price"
	btn.AnchorPoint = Vector2.new(0, 1)
	btn.Position = UDim2.new(0.05, 0, 1, -6)
	btn.Size = UDim2.fromScale(0.9, 0.26)
	if owned or (sku.class == "dragonWeek" and why == "owned") then
		btn.Text = T.owned
		btn.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
	elseif not sellable and why == "expired" then
		btn.Text = T.archived
		btn.TextScaled = true
		btn.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
	elseif not sellable and why == "locked" and sku.requires then
		local req = ShopCore.get(sku.requires)
		btn.Text = fmt(T.requires, { name = if req then nameOf(req) else "" })
		btn.BackgroundColor3 = Color3.fromRGB(110, 110, 120)
	else
		btn.Text = if giftTo then T.gift else T.seePrice
		local key = sku.key
		if sku.class == "hatchNow" or sku.class == "growNow" then
			local now = workspace:GetServerTimeNow()
			local rem = 0 -- (an if-expression truncates the second return value: nil <= number in Growth)
			if sku.class == "hatchNow" then
				local _, r = ShopCore.longestHatch(d, now)
				rem = r
			else
				local _, r = ShopCore.longestGrow(d, now)
				rem = r
			end
			key = ShopCore.tierKey(sku.class, ShopCore.tierOf(rem, S), S)
		end
		if giftTo then
			key = ShopCore.giftKey(sku.key)
		end
		Shop.price(key, function(p)
			if btn.Parent then
				btn.Text = (if giftTo then T.gift .. "  " else "") .. priceText(p)
			end
		end)
	end
	f.Parent = parent
	return f
end

local scrollKeep: Vector2? = nil -- the grid scroll between redraws (otherwise it resets every second)

-- y - the top inset in px; cols - columns (nil: 3, on a narrow body 2)
local function grid(parent: GuiObject, y: number, cols: number?): ScrollingFrame
	local sf = Instance.new("ScrollingFrame")
	sf.Name = "Grid"
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.Position = UDim2.new(0, 0, 0, y)
	sf.Size = UDim2.new(1, 0, 1, -y)
	sf.ScrollBarThickness = 6
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new(0, 0, 0, 0)
	sf.ScrollingDirection = Enum.ScrollingDirection.Y
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromScale(CARD.w, CARD.h)
	gl.CellPadding = UDim2.fromScale(CARD.gap, CARD.gap * 2)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = sf
	sf.Parent = parent
	local function fit()
		local us = UIKit.unscaled(sf)
		local w, h = us.X, us.Y
		if w < 10 or h < 10 then
			return
		end
		local n = cols or (if w < FIT.narrow then 2 else 3)
		local gx = math.max(6, math.floor(w * CARD.gap))
		local cw = math.floor((w - FIT.scrollbar - gx * (n - 1)) / n)
		local ch = math.max(FIT.minH, math.floor((h - gx * 2) / 2)) -- two rows per height, but no lower than minH (then scrolling)
		gl.CellSize = UDim2.fromOffset(cw, ch)
		gl.CellPadding = UDim2.fromOffset(gx, gx * 2)
	end
	fit()
	sf:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
	if scrollKeep then
		local keep = scrollKeep
		scrollKeep = nil
		task.defer(function()
			if sf.Parent then
				sf.CanvasPosition = keep
			end
		end)
	end
	return sf
end

-- an explanation line at y px; returns the height
local function note(parent: GuiObject, text: string, y: number): number
	local h = noteHeight(parent)
	UIKit.text(parent, text, Color3.fromRGB(215, 210, 195), { Name = "Note", Position = UDim2.new(0.02, 0, 0, y), Size = UDim2.new(0.96, 0, 0, h), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
	return h
end

-- ---------------------------------------------------------------------------------------------- sub-tabs
local SUBS = { "time", "nest", "coins", "looks", "gifts" }

local function subBar(parent: Frame)
	local bar = Instance.new("Frame")
	bar.Name = "Subs"
	bar.BackgroundTransparency = 1
	bar.Position = UDim2.fromScale(0, 0)
	bar.Size = UDim2.new(1, 0, 0, barHeight(parent)) -- the height in px (44-56): with a 0.1 fraction on the phone a 44 px button climbed onto the tabs and cards
	bar.Parent = parent
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0.012, 0)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = bar
	for i, id in SUBS do
		-- a tab without visible products (coins: the income packs are hidden) - no button
		local any = id == "gifts" or id == "time"
		if not any then
			for _, sku in ShopCore.catalog() do
				if sku.tab == id and ShopCore.listed(sku, S) then
					any = true
					break
				end
			end
		end
		if not any then
			continue
		end
		local on = id == sub
		local b = UIKit.button(bar, T.tabs[id], if on then rgb(Config.UI.tabs.shop) else Color3.fromRGB(70, 70, 78), function()
			sub = id
			pickMode = false
			Shop.render()
		end)
		b.LayoutOrder = i
		b.Size = UDim2.fromScale(0.19, 1)
		local lim = b:FindFirstChildOfClass("UISizeConstraint")
		if lim then
			lim.MinSize = Vector2.new(56, FIT.barMin)
			lim.MaxSize = Vector2.new(260, FIT.barMax)
		end
		b.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(205, 205, 205)
	end
end

local function renderTime(parent: Frame)
	local y0 = topOf(parent)
	local g = grid(parent, y0)
	local d = data()
	local now = workspace:GetServerTimeNow()
	local order = 1
	local slot = ShopCore.longestHatch(d, now)
	local uid = ShopCore.longestGrow(d, now)
	if slot and S.hatchNowEnabled then
		card(g, ShopCore.get("HatchNow_5") :: any, order)
		order += 1
	end
	if uid then
		card(g, ShopCore.get("GrowNow_5") :: any, order)
		order += 1
	end
	for _, sku in ShopCore.catalog() do
		if sku.class == "treats" or sku.class == "boost" then
			card(g, sku, order)
			order += 1
		end
	end
	if not slot and not uid then
		local y = y0 + note(parent, T.nothingTime, y0) + FIT.gap
		g.Position = UDim2.new(0, 0, 0, y)
		g.Size = UDim2.new(1, 0, 1, -y)
	end
end

local function renderNest(parent: Frame)
	local g = grid(parent, topOf(parent))
	local d = data()
	local order = 1
	local sessions = Store.get("sessions") or 1
	local rode = typeof(d.onboarding) == "table" and d.onboarding.rode == true
	-- also in the 1st session after the first ride - otherwise Starter shows only after rejoins
	if (sessions >= S.starter.fromSession or (S.starter.afterRide == true and rode)) and not ShopCore.has(d, "starter") then
		card(g, ShopCore.get("StarterPack_49") :: any, order, true)
		order += 1
	end
	-- the Dragon of the Week - a large card first while on sale (and a week after - Archived)
	for _, sku in ShopCore.catalog() do
		if sku.class == "dragonWeek" then
			local ok, why = saleState(sku)
			if ok or (why == "expired" and showArchived(sku)) then
				card(g, sku, order, true)
				order += 1
			end
		end
	end
	card(g, ShopCore.get("NestBundle_2999") :: any, order, true)
	order += 1
	for _, sku in ShopCore.catalog() do
		if sku.class == "pass" then
			card(g, sku, order)
			order += 1
		end
	end
end

local function renderCoins(parent: Frame)
	local g = grid(parent, topOf(parent))
	local order = 1
	for _, sku in ShopCore.catalog() do
		if sku.class == "income" then
			card(g, sku, order)
			order += 1
		end
	end
end

-- looks (07 add. 2.6): the nest look choice above the cards if there is something to choose - Classic, owned skins by priority
-- (Royal > Night > Gilded > Lagoon) and Ascended (the Ascension tint); the pressed one - in the tab color. Without the player's choice the nest takes
-- the first skin by priority, otherwise the Ascension tint (Core/Looks.nestLook). The button width - by their count (up to 6 in a row on the phone)
local function nestLookRow(parent: Frame, y: number): number
	local d = data()
	local choices = LooksCore.nestChoices(d, Config.Looks)
	if #choices == 0 then
		return 0
	end
	local h = barHeight(parent)
	local row = Instance.new("Frame")
	row.Name = "NestLook"
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, y)
	row.Size = UDim2.new(1, 0, 0, h)
	row.Parent = parent
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.Padding = UDim.new(0.012, 0)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = row
	local lbl = UIKit.text(row, Strings.Looks.skinRow, UIKit.CREAM, { Name = "Label", Size = UDim2.new(0.18, 0, 0.8, 0), TextXAlignment = Enum.TextXAlignment.Right })
	lbl.LayoutOrder = 0
	local current = LooksCore.nestCurrent(d, Config.Looks)
	local ids = { LooksCore.CLASSIC }
	for _, id in choices do
		table.insert(ids, id)
	end
	local bw = math.min(0.18, (0.8 - 0.012 * #ids) / #ids) -- the caption 0.18 + the buttons with gaps in one line
	for i, id in ids do
		local on = id == current
		local name = (Strings.Looks.skins :: any)[id] or id
		local b = UIKit.button(row, name, if on then rgb(Config.UI.tabs.shop) else Color3.fromRGB(70, 70, 78), function(btn)
			if on then
				return
			end
			local reply = Net.call("SetLook", "nestSkin", id)
			if reply.ok then
				Sounds.play("button")
				if banners then
					banners.toast(fmt(Strings.Looks.skinSet, { name = name }))
				end
			else
				UIKit.shake(btn)
				if banners then
					banners.toast((Strings.Errors :: any)[reply.reason or ""] or Strings.Errors.bad_request)
				end
			end
		end)
		b.Name = "Skin_" .. id
		b.LayoutOrder = i
		b.Size = UDim2.fromScale(bw, 1)
		local lim = b:FindFirstChildOfClass("UISizeConstraint")
		if lim then
			lim.MinSize = Vector2.new(56, FIT.barMin)
			lim.MaxSize = Vector2.new(220, FIT.barMax)
		end
	end
	return h + FIT.gap
end

local function renderLooks(parent: Frame)
	local y0 = topOf(parent)
	y0 += nestLookRow(parent, y0)
	local g = grid(parent, y0)
	local order = 1
	for _, sku in ShopCore.catalog() do
		if sku.class == "look" and (saleState(sku)) then -- Tidal, Night Sky - from the update date
			card(g, sku, order)
			order += 1
		end
	end
end

local function renderGifts(parent: Frame)
	local others = {}
	for _, p in Players:GetPlayers() do
		if p ~= me then
			table.insert(others, p)
		end
	end
	if #others == 0 then
		selectedGift = nil
		note(parent, T.giftNobody, topOf(parent))
		return
	end
	if selectedGift and not Players:GetPlayerByUserId(selectedGift) then
		selectedGift = nil
	end
	local list = Instance.new("ScrollingFrame")
	list.Name = "Players"
	list.BackgroundColor3 = rgb(Config.UI.panel.color)
	list.BackgroundTransparency = 0.3
	list.BorderSizePixel = 0
	local y0 = topOf(parent)
	list.Position = UDim2.new(0, 0, 0, y0)
	list.Size = UDim2.new(0.3, 0, 1, -y0)
	list.ScrollBarThickness = 6
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	UIKit.corner(list, 0.05)
	list.Parent = parent
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0.02, 0)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	for i, p in others do
		local row = UIKit.button(list, "", if selectedGift == p.UserId then rgb(Config.UI.tabs.shop) else Color3.fromRGB(70, 70, 78), function()
			selectedGift = p.UserId
			Shop.render()
		end)
		row.LayoutOrder = i
		row.Size = UDim2.new(0.96, 0, 0, 48)
		row.Text = ""
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Position = UDim2.fromScale(0.02, 0.1)
		img.Size = UDim2.fromScale(0.25, 0.8)
		img.Parent = row
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
			end)
			if ok and img.Parent then
				img.Image = url
			end
		end)
		UIKit.text(row, p.DisplayName, Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.3, 0.15), Size = UDim2.fromScale(0.68, 0.7), TextXAlignment = Enum.TextXAlignment.Left })
	end
	local right = Instance.new("Frame")
	right.BackgroundTransparency = 1
	right.Position = UDim2.new(0.32, 0, 0, y0)
	right.Size = UDim2.new(0.68, 0, 1, -y0)
	right.Parent = parent
	if not selectedGift then
		note(right, T.giftPick, 0)
		return
	end
	local to = Players:GetPlayerByUserId(selectedGift)
	local nh = note(right, fmt(T.giftTo, { name = if to then to.DisplayName else "" }), 0)
	local g = grid(right, nh + FIT.gap, 2)
	local order = 1
	for _, sku in ShopCore.catalog() do
		if sku.gift and (saleState(sku)) then -- gifts - only what is on sale right now
			card(g, sku, order, false, selectedGift)
			order += 1
		end
	end
end

-- the choice of two Starter Pack elements (07 no. 2): six tiles in the element color, the two chosen framed, a confirm button
local function renderPick(parent: Frame)
	local y0 = topOf(parent)
	local nh = note(parent, T.starterPick, y0)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Position = UDim2.new(0, 0, 0, y0 + nh + FIT.gap)
	-- the tiles lower (used to be 0.3 of the height) - under them the odds in two lines in a readable font (on the phone 0.3 left ~10 px)
	row.Size = UDim2.new(1, 0, 0, math.max(44, math.floor(UIKit.unscaled(parent).Y * 0.2)))
	row.Parent = parent
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromScale(0.15, 1)
	gl.CellPadding = UDim2.fromScale(0.015, 0)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = row
	local Content = require(Shared:WaitForChild("Content"))
	for i, el in Config.Elements do
		local info = Content.Elements[el]
		local b = Loc.raw(UIKit.button(row, info and info.name or el, if info then rgb(info.color) else UIKit.GREEN, function(btn)
			local at = table.find(picked, el)
			if at then
				table.remove(picked, at)
			elseif #picked < S.starter.eggs then
				table.insert(picked, el)
			else
				UIKit.shake(btn)
				return
			end
			Shop.render()
		end)) -- the element name
		b.LayoutOrder = i
		if table.find(picked, el) then
			UIKit.stroke(b, UIKit.GOLD, 5)
		end
	end
	-- what exactly is being bought - before the buy button: the odds (where Roblox allows paid randomness) or "both Rare"
	local showOdds = me:GetAttribute("PaidRandomOK") == true
	-- one label (lines of one size), from the tiles to the buttons with a margin of 12
	local top = row.Position.Y.Offset + row.Size.Y.Offset + FIT.gap
	local info = UIKit.text(parent, if showOdds then starterOddsText() else Loc.t(T.starterFixed), Color3.fromRGB(235, 228, 205), {
		Name = "StarterOdds", Position = UDim2.new(0.02, 0, 0, top), Size = UDim2.new(0.96, 0, 0.84, -top - 12),
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center })
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 20
	cap.Parent = info
	Loc.raw(info) -- already in the player's language (templates + percentages)
	local confirm = UIKit.button(parent, nameOf(ShopCore.get("StarterPack_49") :: any), UIKit.GREEN, function(btn)
		if #picked < S.starter.eggs then
			UIKit.shake(btn)
			return
		end
		pickMode = false
		-- "odds" - the player was shown the odds; the server gives a random variant only if Roblox allows it for this player too
		Shop.buy("StarterPack_49", table.concat(picked, ",") .. (if showOdds then ",odds" else ""), nil)
		Shop.render()
	end)
	confirm.AnchorPoint = Vector2.new(0, 1)
	confirm.Position = UDim2.new(0.3, 0, 1, -4)
	confirm.Size = UDim2.fromScale(0.4, 0.16)
	Shop.price("StarterPack_49", function(p)
		if confirm.Parent then
			confirm.Text = nameOf(ShopCore.get("StarterPack_49") :: any) .. "  " .. priceText(p)
		end
	end)
	local back = UIKit.button(parent, Strings.Menu.back, Color3.fromRGB(110, 110, 120), function()
		pickMode = false
		Shop.render()
	end)
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position = UDim2.new(0.02, 0, 1, -4)
	back.Size = UDim2.fromScale(0.2, 0.16)
end

-- the book body is shared by all tabs: draw only when Shop is open (otherwise Store.on("coins") would redraw Shop over another tab every second)
local function shopOpen(): boolean
	local menu = loaded and loaded.Menu
	return menu ~= nil and menu.current ~= nil and menu.current() == "shop"
end

function Shop.render()
	local b = body
	if not b or not b.Parent or not shopOpen() then
		return
	end
	local old = b:FindFirstChild("Grid", true)
	if old and old:IsA("ScrollingFrame") and scrollKeep == nil then
		scrollKeep = old.CanvasPosition
	end
	for _, ch in b:GetChildren() do
		ch:Destroy()
	end
	subBar(b)
	if pickMode then
		renderPick(b)
	elseif sub == "time" then
		renderTime(b)
	elseif sub == "nest" then
		renderNest(b)
	elseif sub == "coins" then
		renderCoins(b)
	elseif sub == "looks" then
		renderLooks(b)
	else
		renderGifts(b)
	end
end

-- open the book on the Shop tab (the sub-tab by name)
function Shop.open(which: string?, by: string?)
	if which and table.find(SUBS, which) then
		sub = which
	end
	pickMode = false
	local menu = loaded and loaded.Menu
	if menu and menu.open then
		menu.open("shop")
		-- Analytics - a RemoteEvent; Net.call (a RemoteFunction) answered "loading", the event did not arrive
		local rf = game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
		local ev = rf and rf:FindFirstChild("Analytics")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireServer("shop_open", { by = by or "button" })
		end
	end
end

local function onPurchase(p: any)
	if banners then
		banners.toast(tostring(p.text or fmt(T.bought, { name = p.name or "" })))
	end
	Sounds.play("stage_up")
	priceCache = {} -- Owned may have changed
	task.delay(0.2, Shop.render)
end

local function onGift(p: any)
	if banners then
		banners.toast(tostring(p.text or ""))
	end
	Sounds.play("stage_up")
	task.delay(0.2, Shop.render)
end

function Shop.init(snapshot: any, l: any)
	loaded = l
	banners = l.Banners
	playAtJoin = (typeof(snapshot) == "table" and tonumber(snapshot.playSeconds)) or 0
	local hud = l.HUD
	if hud and hud.addMenuButton then
		hud.addMenuButton("left", Strings.HUD.shop, rgb(Config.UI.tabs.shop), function()
			Shop.open(nil)
		end, UIKit.ICON.shop)
	end
end

-- View on the Dragon of the Week stand - the Nest tab from the start (the dragon card is first there after Starter)
function Shop.view()
	scrollKeep = Vector2.zero
	Shop.open("nest", "stand")
end

-- the stand on the plaza (the server DragonStand): the View prompt and the price on the sign - the price is taken here, on the player's side (regional prices)
local function wireStand(m: Instance)
	if not m:IsA("Model") then
		return
	end
	local base = m:WaitForChild("StandBase", 10)
	local pr = base and base:FindFirstChild("StandView")
	if pr and pr:IsA("ProximityPrompt") then
		pr.Triggered:Connect(Shop.view)
	end
	local key = m:GetAttribute("Sku")
	local sign = m:FindFirstChild("StandSign")
	local label = sign and sign:FindFirstChild("Label")
	local line = label and label:FindFirstChild("Price")
	if typeof(key) == "string" and line and line:IsA("TextLabel") then
		task.spawn(function() -- the price in Robux - as for the context buttons: not before 3:00 of the first session (Shop.robuxAllowed)
			while line.Parent and not Shop.robuxAllowed() do
				task.wait(5)
			end
			if line.Parent then
				Shop.price(key, function(price: number?)
					if line.Parent and price then
						line.Text = priceText(price)
					end
				end)
			end
		end)
	end
end

function Shop.start()
	CollectionService:GetInstanceAddedSignal("DragonStand"):Connect(wireStand)
	for _, m in CollectionService:GetTagged("DragonStand") do
		task.spawn(wireStand, m)
	end
	local menu = loaded and loaded.Menu
	if menu and menu.register then
		menu.register({ id = "shop", word = T.title, icon = UIKit.ICON.shop, color = rgb(Config.UI.tabs.shop), order = 25, render = function(frame: Frame) -- after Dragons (20), before Quests (30)
			body = frame
			scrollKeep = nil -- the tab was opened anew: the grid from the start
			Shop.render()
		end })
	end
	Net.on("purchase", onPurchase)
	Net.on("gift", onGift)
	me:GetAttributeChangedSignal("PaidRandomOK"):Connect(function() -- the server read the policy - the Starter Pack variant
		if body and body.Parent then
			Shop.render()
		end
	end)
	-- the coins change every second - the cards do not depend on them (prices in Robux), hence no "coins"; eggs/dragons/incubators
	-- are needed only by the Time tab (Hatch now / Grow now); redraw no more often than once per second
	local pending = false
	local function rerender()
		if pending then
			return
		end
		pending = true
		task.delay(0.5, function()
			pending = false
			if body and body.Parent and not pickMode then
				Shop.render()
			end
		end)
	end
	for _, key in { "owned", "items", "boost", "looks" } do -- looks: the nest look choice
		Store.on(key, rerender)
	end
	for _, key in { "eggs", "dragons", "incubators" } do
		Store.on(key, function()
			if sub == "time" then
				rerender()
			end
		end)
	end
	Players.PlayerRemoving:Connect(function()
		if body and body.Parent and sub == "gifts" then
			task.defer(Shop.render)
		end
	end)
	Players.PlayerAdded:Connect(function()
		if body and body.Parent and sub == "gifts" then
			task.defer(Shop.render)
		end
	end)
end

return Shop
