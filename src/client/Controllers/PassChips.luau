--!strict
-- pass buttons by the coin pill. In Tame An Animal
-- Auto Tame / Auto Command / Teleport sit right on screen with a Robux icon; a tap - the pass card: what you get (3 lines),
-- "Buy once - keep it forever", a green price and "Not now". Here: right of the coins in a row x2 Coins and Auto Collect (Config.UI.passChips).
-- When visible - Core/PassChips (not before Shop.robuxAllowed, not mounted, the nest already earns, not bought). Purchase - Shop.buy
-- (ShopIntent -> the Roblox window), bought (Store owned) - the card closes, the button goes away. The shop funnel: a button visible >= 1 s -
-- offer_impression (Shop.impression), a tap - shop_open by=chip_<word>.
-- the card does not open over another window
-- (UIStack not empty) or while the Roblox "favorite" prompt is on screen (Favorite.busy - then no buttons either); while the card is open, the
-- "favorite" prompt and the goal banner wait for it to close (Controllers/Favorite); the HUD with the buttons is hidden under any window (UIStack).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local ShopIcons = require(Shared:WaitForChild("ShopIcons"))
local Core = Shared:WaitForChild("Core")
local ChipsCore = require(Core:WaitForChild("PassChips"))
local ShopCore = require(Core:WaitForChild("Shop"))
local Format = require(Core:WaitForChild("Format"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Store = require(script.Parent:WaitForChild("Store"))

local PassChips = {}

local C = Config.UI.passChips
local T = Strings.PassCard
local me = Players.LocalPlayer
local hud: any = nil
local shop: any = nil
local favorite: any = nil
local gifts: any = nil
local quiet: any = nil -- pass chips - not during an activity (Controllers/Quiet)
local loadedRef: any = nil -- Glow (the pedestal board) loads later - take it lazily in refresh
local chips: { [string]: TextButton } = {}
local cardGui: ScreenGui? = nil
local cardKey: string? = nil

local function analytics(name: string, fields: { [string]: any })
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, fields)
	end
end

-- ---------------------------------------------------------------------------------------------- the pass card
local function destroyCard()
	if cardGui then
		cardGui:Destroy()
		cardGui = nil
	end
	cardKey = nil
end

local function openCard(key: string, word: string)
	if cardGui or not shop or UIStack.depth() > 0 or (favorite and favorite.busy and favorite.busy()) or (gifts and gifts.busy and gifts.busy()) then
		return
	end
	local g = UIKit.screen("PassCard", 9)
	cardGui = g
	cardKey = key
	if not UIStack.open("passCard", destroyCard) then
		destroyCard()
		return
	end
	analytics("shop_open", { by = "chip_" .. word })
	local small = g.AbsoluteSize.Y > 0 and g.AbsoluteSize.Y < (Config.UI.book.smallBelow or 0) -- phone: the card is larger (like DragonCard)
	local panel, body = UIKit.panel(g, Loc.t((Strings.Shop.names :: any)[key] or key), if small then 0.78 else 0.54, if small then 0.9 else 0.66, function()
		UIStack.close("passCard")
	end, UIKit.GOLD)
	panel.Name = "PassCardPanel"
	-- on the left the pass picture (as in the shop) and the GAME PASS label under it
	local icon = UIKit.image(body, ShopIcons[key] or 0, { Name = "Icon", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(0.28, 0.5) })
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = icon
	local tag = UIKit.pill(body, { Name = "Tag", BackgroundColor3 = UIKit.GOLD, BackgroundTransparency = 0, Position = UDim2.fromScale(0.02, 0.52), Size = UDim2.fromScale(0.24, 0.1) })
	UIKit.text(tag, Loc.t(T.tag), UIKit.STROKE, { Position = UDim2.fromScale(0.06, 0.1), Size = UDim2.fromScale(0.88, 0.8) })
	-- on the right: what you get, three lines with a check mark
	UIKit.text(body, Loc.t(T.whatYouGet), UIKit.GOLD, { Name = "WhatYouGet", Position = UDim2.fromScale(0.32, 0), Size = UDim2.fromScale(0.66, 0.11), TextXAlignment = Enum.TextXAlignment.Left })
	for i, line in (T.lines :: any)[key] or {} do
		UIKit.text(body, "✔  " .. Loc.t(line), UIKit.ONE, { Name = "Line" .. i, Position = UDim2.fromScale(0.32, 0.13 + (i - 1) * 0.15), Size = UDim2.fromScale(0.66, 0.12), TextXAlignment = Enum.TextXAlignment.Left })
	end
	UIKit.text(body, Loc.t(T.forever), UIKit.GOLD, { Name = "Forever", Position = UDim2.fromScale(0.05, 0.62), Size = UDim2.fromScale(0.9, 0.1) })
	-- the price from GetProductInfoAsync (regional), as in the shop; an API error - "See price" (the Roblox window will show the price)
	local buy = UIKit.button(body, "...", UIKit.GREEN, function()
		shop.buy(key)
	end)
	buy.Name = "Buy"
	buy.AnchorPoint = Vector2.new(0, 1)
	buy.Position = UDim2.fromScale(0.04, 1)
	buy.Size = UDim2.fromScale(0.44, 0.22)
	shop.price(key, function(price: number?)
		if buy.Parent then
			buy.Text = if price then (Strings.Shop.robux .. " " .. Format.number(price)) else Loc.t(Strings.Shop.seePrice)
		end
	end)
	local no = UIKit.button(body, Loc.t(T.notNow), UIKit.GREY, function()
		UIStack.close("passCard")
	end)
	no.Name = "NotNow"
	no.AnchorPoint = Vector2.new(1, 1)
	no.Position = UDim2.fromScale(0.96, 1)
	no.Size = UDim2.fromScale(0.44, 0.22)
end

-- ---------------------------------------------------------------------------------------------- the buttons by the coins
local function makeChip(g: ScreenGui, c: any): TextButton
	local b = Instance.new("TextButton")
	b.Name = "PassChip_" .. c.key
	b.Text = ""
	b.AutoButtonColor = false
	b.BackgroundColor3 = UIKit.PANEL
	b.BackgroundTransparency = 0.18
	b.Visible = false
	UIKit.corner(b, 0.5)
	UIKit.stroke(b, UIKit.GOLD, 2)
	UIKit.iconText(b, (Strings.Shop.icons :: any)[c.key] or "", { Name = "Glyph", Position = UDim2.fromScale(0.08, 0.14), Size = UDim2.fromScale(0.34, 0.72) })
	UIKit.text(b, Loc.t((T.chip :: any)[c.word] or c.word), UIKit.CREAM, { Name = "Word", Position = UDim2.fromScale(0.42, 0.16), Size = UDim2.fromScale(0.5, 0.68), TextXAlignment = Enum.TextXAlignment.Left })
	-- the Robux icon in the corner (like Tame An Animal): a green "R$" circle
	local badge = Instance.new("Frame")
	badge.Name = "Robux"
	badge.BackgroundColor3 = UIKit.GREEN
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.Position = UDim2.fromScale(0.93, 0.12)
	badge.Size = UDim2.fromScale(0.42, 0.42)
	local bar = Instance.new("UIAspectRatioConstraint")
	bar.AspectRatio = 1
	bar.Parent = badge
	UIKit.corner(badge, 0.5)
	UIKit.stroke(badge, UIKit.STROKE, 1.5)
	UIKit.text(badge, Strings.Shop.robux, UIKit.ONE, { Position = UDim2.fromScale(0.1, 0.18), Size = UDim2.fromScale(0.8, 0.64) })
	badge.Parent = b
	local sc = Instance.new("UIScale")
	sc.Parent = b
	b.Activated:Connect(function()
		sc.Scale = 0.9
		TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if UIKit.onPress then
			UIKit.onPress()
		end
		openCard(c.key, c.word)
	end)
	b.Parent = g
	return b
end

-- the visible buttons (Core/PassChips.visible) and their spots (layout: right of the pill in a row, without leaving the screen and without the Roblox
-- player list zone on PC). While the pill "catches" coins (UIScale ~= 1), the spots are not recomputed - otherwise the buttons twitch; after the animation the size
-- changes once more and refresh is called again
local placed: { [string]: boolean } = {}
local function refresh()
	local g, box = hud.coinFrame()
	local pill = box and box:FindFirstChild("Pill")
	if not g or not box or not pill or not pill:IsA("GuiObject") then
		return
	end
	local sc = box:FindFirstChildOfClass("UIScale")
	if sc and math.abs(sc.Scale - 1) > 0.001 then
		return
	end
	local ctx = { robuxOk = shop.robuxAllowed(), mounted = me:GetAttribute("Mounted") ~= nil, rate = hud.rate(),
		blocked = (favorite ~= nil and favorite.busy ~= nil and favorite.busy()) or (hud.newbie ~= nil and hud.newbie()) or (quiet ~= nil and quiet.busy() ~= nil)
			-- one request at a time
			or (loadedRef ~= nil and loadedRef.Glow ~= nil and loadedRef.Glow.boardVisible ~= nil and loadedRef.Glow.boardVisible()) or os.clock() < (UIKit.bannerUntil or 0) } -- a start in waves; and not during an activity
	local p = pill.AbsolutePosition - g.AbsolutePosition
	local z = pill.AbsoluteSize
	local W, H = g.AbsoluteSize.X, g.AbsoluteSize.Y
	local playerList = true
	local okCg, errCg = pcall(function()
		playerList = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
	end)
	if not okCg then
		warn("[PassChips] GetCoreGuiEnabled: " .. tostring(errCg)) -- the default true is safe, but the failure is visible
	end
	local zones = ChipsCore.zones(W, H, UserInputService.TouchEnabled, playerList, C)
	local rects = ChipsCore.layout({ p.X, p.Y, p.X + z.X, p.Y + z.Y }, W, H, ChipsCore.visible(Store.all(), ctx, C), C, zones)
	for key, b in chips do
		local r = rects[key]
		if r then
			b.Position = UDim2.fromOffset(r[1], r[2])
			b.Size = UDim2.fromOffset(r[3] - r[1], r[4] - r[2])
		end
		if r and not placed[key] then
			placed[key] = true
			if quiet and quiet.asked then
				quiet.asked() -- purchase chips are a request too, the next ones wait askGap
			end
			b.Visible = true
			local bs = b:FindFirstChildOfClass("UIScale") :: UIScale
			bs.Scale = 0.6
			TweenService:Create(bs, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			shop.impression(key, "chip", function()
				return b.Visible and g.Enabled
			end)
		elseif not r and placed[key] then
			placed[key] = nil
			b.Visible = false
		end
	end
end

function PassChips.init(_snapshot: any, loaded: any)
	loadedRef = loaded
	hud = loaded.HUD
	shop = loaded.Shop
	favorite = loaded.Favorite
	gifts = loaded.Gifts -- the notifications opt-in prompt (Gifts.busy)
	quiet = loaded.Quiet
end

function PassChips.start()
	if not (C and C.on) or not hud or not hud.coinFrame or not shop then
		return
	end
	local g, box = hud.coinFrame()
	if not g or not box then
		return
	end
	for _, c in C.list do
		chips[c.key] = makeChip(g, c)
	end
	local function safe()
		local ok, err = pcall(refresh)
		if not ok then
			warn("[PassChips] " .. tostring(err))
		end
	end
	local pill = box:FindFirstChild("Pill")
	if pill and pill:IsA("GuiObject") then
		pill:GetPropertyChangedSignal("AbsoluteSize"):Connect(safe)
		pill:GetPropertyChangedSignal("AbsolutePosition"):Connect(safe)
	end
	g:GetPropertyChangedSignal("AbsoluteSize"):Connect(safe)
	-- the card's pass is bought (Store owned) - the card closes, the button leaves at once without waiting for the cycle
	Store.on("owned", function()
		local key = cardKey
		local sku = key and ShopCore.get(key)
		if cardGui and sku and ShopCore.owned(Store.all(), sku) then
			UIStack.close("passCard")
		end
		safe()
	end)
	task.spawn(function()
		while true do
			safe()
			task.wait(0.5)
		end
	end)
end

return PassChips
