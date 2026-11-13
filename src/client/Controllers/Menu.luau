--!strict
-- The book window: one window for all menus with colored tabs on top. Tabs: Dragons
-- (a grid of cards of the own dragons, the background in the rarity color, a tap -> the card), Settings (sounds/music; for the game owner and in
-- Studio - "Reset Progress (test)"). The HUD plaques open the needed tab. Also: Shop, Quests, Index.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local QuestsCore = require(Shared:WaitForChild("Core"):WaitForChild("Quests"))
local IndexCore = require(Shared:WaitForChild("Core"):WaitForChild("Index"))
local RewardsCore = require(Shared:WaitForChild("Core"):WaitForChild("Rewards")) -- 2.4: dailies
local NextUpCore = require(Shared:WaitForChild("Core"):WaitForChild("NextUp")) -- "6d 3h" until the weekly quest reset
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local Economy = require(Core:WaitForChild("Economy"))
local ShopCore = require(Core:WaitForChild("Shop")) -- slots from passes

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local DragonCard = require(script.Parent:WaitForChild("DragonCard"))

local Menu = {}

local B = Config.Balance
local me = Players.LocalPlayer
local banners: any = nil
local coinFlight: any = nil
local hud: any = nil
local dragonLife: any = nil -- P37: showing other players' dragons
local perfCtl: any = nil -- the last average FPS for admins
local gui: ScreenGui? = nil
local body: Frame? = nil
local setActive: ((string) -> ())? = nil
local currentTab: string? = nil

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function isOwner(): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return game.CreatorId == me.UserId
	end
	return table.find(Config.AdminUserIds, me.UserId) ~= nil -- the game belongs to a group - admins come from the Config list
end

local function clearBody()
	local b = body
	if b then
		for _, c in b:GetChildren() do
			c:Destroy()
		end
	end
end

-- ---------------------------------------------------------------------------------------------- the Dragons tab
local function dragonGrid()
	local b = body
	if not b then
		return
	end
	clearBody()
	local dragons = Store.get("dragons")
	local order = Store.get("nestOrder")
	local coinSlots = (Store.get("slots") or {}).coins or B.slots.start
	local slots = math.min(10, coinSlots + ShopCore.passSlots(Store.all(), B)) -- plus slots from passes / VIP (used to be coins only)
	local inNestCount = if typeof(order) == "table" then #order else 0
	-- the ascension line - the step and the reward, the requirement, the Ascend button (px: phone 812x375)
	local asc = (Store.get("ascension") or 0) :: number
	local step = asc + 1
	local cost = Economy.ascensionCost(step, B)
	local need = Economy.ascensionNeed(step, B)
	local needWhat = if need.elements > 1 then fmt(Strings.Menu.needElders, { n = need.elements }) elseif need.stage >= 3 then Loc.t(Strings.Menu.needElder) else Loc.t(Strings.Menu.needAdult)
	UIKit.text(b, fmt(Strings.Menu.ascendTitle, { roman = Format.roman(step), n = step + 1 }), UIKit.GOLD, { Name = "AscTitle", Position = UDim2.new(0, 0, 0, 2), Size = UDim2.new(0.5, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.text(b, fmt(Strings.Menu.ascendNeed, { what = needWhat, cost = Format.number(cost) }), UIKit.CREAM, { Name = "AscNeed", Position = UDim2.new(0, 0, 0, 24), Size = UDim2.new(0.5, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.text(b, fmt(Strings.Menu.slots, { k = inNestCount, n = slots }), UIKit.CREAM, { Name = "Slots", Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.new(0.22, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	local ab = UIKit.button(b, Strings.Menu.ascend, Color3.fromRGB(170, 120, 230), function()
		local r = Net.call("Ascend")
		if r.ok then
			Sounds.play("stage_up")
		end
	end)
	ab.Name = "Ascend"
	ab.AnchorPoint = Vector2.new(1, 0)
	ab.Position = UDim2.new(1, -8, 0, 0)
	ab.Size = UDim2.new(0.24, 0, 0, 44)
	local list = Instance.new("ScrollingFrame")
	list.Name = "Grid"
	list.BackgroundTransparency = 1
	list.Position = UDim2.new(0, 0, 0, 50)
	list.Size = UDim2.new(1, 0, 1, -50)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = b
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.235, 0.47)
	grid.CellPadding = UDim2.fromScale(0.02, 0.04)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	if typeof(dragons) ~= "table" or next(dragons) == nil then
		UIKit.text(b, Strings.Menu.empty, Color3.fromRGB(220, 220, 230), { Position = UDim2.fromScale(0, 0.4), Size = UDim2.fromScale(1, 0.14) })
		return
	end
	local uids: { string } = {}
	if typeof(order) == "table" then
		for _, uid in order do
			table.insert(uids, uid)
		end
	end
	for uid in dragons do
		if not table.find(uids, uid) then
			table.insert(uids, uid)
		end
	end
	for i, uid in uids do
		local d = dragons[uid]
		if not d then
			continue
		end
		local rc = UIKit.RARITY[d.rarity] or Color3.new(1, 1, 1)
		local card = Instance.new("TextButton")
		card.Name = uid
		card.LayoutOrder = i
		card.AutoButtonColor = false
		card.Text = ""
		card.BackgroundColor3 = rc:Lerp(UIKit.PANEL, 0.55)
		UIKit.corner(card, 0.1)
		UIKit.stroke(card, rc, 2)
		UIKit.gloss(card, 0.3)
		Instance.new("UIScale").Parent = card
		Loc.raw(UIKit.text(card, d.name, Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.04, 0.03), Size = UDim2.fromScale(0.92, 0.2) })) -- the dragon's name
		local el = Content.Elements[d.element]
		local dot = Instance.new("Frame")
		dot.BackgroundColor3 = if el then rgb(el.color) else Color3.new(1, 1, 1)
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromScale(0.5, 0.5)
		dot.Size = UDim2.fromScale(0.42, 0.42)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = dot
		UIKit.corner(dot, 1)
		UIKit.stroke(dot, UIKit.STROKE, 2)
		UIKit.gloss(dot, 0.35)
		dot.Parent = card
		-- a portrait instead of 🐉; by day - a 3:2 480x320 portrait across the whole tile between
		-- the name and the stage, the element circle stays as a medallion behind it
		if not UIKit.portrait(card, d.element, d.stage or 0, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.fromScale(0.92, 0.5), ZIndex = 3 }) then
			UIKit.iconText(dot, UIKit.ICON.dragons, { Position = UDim2.fromScale(0.12, 0.12), Size = UDim2.fromScale(0.76, 0.76) })
		end
		local inNest = typeof(order) == "table" and table.find(order, uid) ~= nil
		UIKit.text(card, Loc.t(Strings.Stage[d.stage] or "") .. (if inNest then "" else "  " .. Loc.t(Strings.Menu.sanctuary)), Color3.fromRGB(225, 225, 232), { Position = UDim2.fromScale(0.04, 0.72), Size = UDim2.fromScale(0.92, 0.13) })
		local realIncome = Economy.dragonIncome(d, B) * (if inNest then UIKit.rateMult() else 1) -- with the nest multiplier
		UIKit.text(card, Loc.t(Strings.Rarity[d.rarity] or d.rarity) .. "  " .. fmt(Strings.Card.income, { n = Format.number(realIncome) }), rc, { Position = UDim2.fromScale(0.04, 0.85), Size = UDim2.fromScale(0.92, 0.12) })
		card.Activated:Connect(function()
			UIKit.press(card)
			DragonCard.open(uid)
		end)
		card.Parent = list
	end
	-- empty nest slots: gray cells (HTTYD: empty slots are visible)
	for k = #uids + 1, math.max(slots, 3) do
		local empty = Instance.new("Frame")
		empty.LayoutOrder = 100 + k
		empty.BackgroundColor3 = UIKit.PANEL_LIGHT
		empty.BackgroundTransparency = 0.4
		UIKit.corner(empty, 0.1)
		UIKit.stroke(empty, UIKit.PANEL_LIGHT, 2)
		UIKit.iconText(empty, UIKit.ICON.egg, { Position = UDim2.fromScale(0.3, 0.3), Size = UDim2.fromScale(0.4, 0.4), TextTransparency = 0.6 })
		empty.Parent = list
	end
	-- the "+1 Slot" tile with the price while coin
	-- slots remain; Remote Buy "slot", the first dragon from the sanctuary moves into the nest at once
	local slotPrice = Economy.slotPrice(coinSlots, B)
	if slotPrice then
		local plus = Instance.new("TextButton")
		plus.Name = "BuySlot"
		plus.Text = ""
		plus.AutoButtonColor = false
		plus.LayoutOrder = 1000
		plus.BackgroundColor3 = Color3.fromRGB(70, 52, 34)
		UIKit.corner(plus, 0.1)
		UIKit.stroke(plus, UIKit.GOLD, 2)
		UIKit.text(plus, "+", UIKit.GOLD, { Name = "Plus", Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(1, 0.4) })
		UIKit.text(plus, Strings.Buy.slotTile, Color3.new(1, 1, 1), { Name = "Word", Position = UDim2.fromScale(0.04, 0.46), Size = UDim2.fromScale(0.92, 0.2) })
		UIKit.coin(plus, nil, { Position = UDim2.new(0.18, 0, 0.72, 0), Size = UDim2.fromScale(0.16, 0.18) })
		UIKit.text(plus, Format.number(slotPrice), UIKit.GOLD, { Name = "Price", Position = UDim2.fromScale(0.36, 0.7), Size = UDim2.fromScale(0.5, 0.22), TextXAlignment = Enum.TextXAlignment.Left })
		plus.Activated:Connect(function()
			UIKit.press(plus)
			local r = Net.call("Buy", "slot")
			if r.ok then
				Sounds.play("stage_up")
				dragonGrid()
			else
				UIKit.shake(plus)
				if banners then
					banners.toast(fmt(Strings.Errors[r.reason or ""] or Strings.Errors.bad_request, { n = Format.number(r.n or 0) }))
				end
			end
		end)
		plus.Parent = list
	end
	-- a tile when the sanctuary has Commons (except the companion); a second press within 3 s - release
	local commons, refund = 0, 0
	local comp = Store.get("companion")
	for cuid, d in (if typeof(dragons) == "table" then dragons else {}) :: { [string]: any } do
		local inNestC = typeof(order) == "table" and table.find(order, cuid) ~= nil
		if not inNestC and d.rarity == "Common" and cuid ~= comp then
			commons += 1
			refund += Economy.releaseRefund(d, B)
		end
	end
	if commons > 0 then
		local rel = Instance.new("TextButton")
		rel.Name = "ReleaseCommon"
		rel.Text = ""
		rel.AutoButtonColor = false
		rel.LayoutOrder = 1001
		rel.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
		UIKit.corner(rel, 0.1)
		UIKit.stroke(rel, Color3.fromRGB(190, 90, 90), 2)
		local word = UIKit.text(rel, fmt(Strings.Card.releaseCommonTile, { k = commons }), Color3.new(1, 1, 1), { Name = "Word", Position = UDim2.fromScale(0.04, 0.2), Size = UDim2.fromScale(0.92, 0.26) })
		UIKit.coin(rel, nil, { Position = UDim2.new(0.18, 0, 0.6, 0), Size = UDim2.fromScale(0.16, 0.18) })
		local price = UIKit.text(rel, "+" .. Format.number(refund), UIKit.GOLD, { Name = "Price", Position = UDim2.fromScale(0.36, 0.58), Size = UDim2.fromScale(0.5, 0.22), TextXAlignment = Enum.TextXAlignment.Left })
		local armed = 0
		rel.Activated:Connect(function()
			UIKit.press(rel)
			if os.clock() > armed then
				armed = os.clock() + (Config.UI.card.releaseConfirm or 3)
				word.Text = fmt(Strings.Card.releaseCommonSure, { n = Format.number(refund) })
				rel.BackgroundColor3 = Color3.fromRGB(150, 50, 50)
				local mine = armed
				task.delay((Config.UI.card.releaseConfirm or 3) + 0.05, function()
					if armed == mine and rel.Parent then
						armed = 0
						word.Text = fmt(Strings.Card.releaseCommonTile, { k = commons })
						rel.BackgroundColor3 = Color3.fromRGB(70, 40, 40)
					end
				end)
				return
			end
			armed = 0
			local r = Net.call("Release", "common", true)
			if r.ok then
				Sounds.play("coin_plus")
				dragonGrid()
			else
				UIKit.shake(rel)
			end
		end)
		local _ = price
		rel.Parent = list
	end
end

-- ---------------------------------------------------------------------------------------------- the Settings tab
local settingsTab: () -> ()

-- P37: apply locally at once, write to the profile; a server refusal - revert
function Menu.setOtherDragons(on: boolean)
	if dragonLife then
		dragonLife.setShowOthers(on)
	end
	task.spawn(function()
		local reply = Net.call("Setting", "otherDragons", on)
		if not reply.ok and dragonLife then
			dragonLife.setShowOthers(not on)
			if currentTab == "settings" then
				settingsTab()
			end
		end
	end)
end

function settingsTab()
	local b = body
	if not b then
		return
	end
	clearBody()
	-- get/set - the toggle state; P37: a longer caption - the caption field up to 0.68 of the width
	-- rows in px - the toggle no smaller than 44 px; with 0.22 fractions Reset ran into the version line
	local bh = UIKit.unscaled(b).Y
	-- four rows (+ Code); admins have a button row at the bottom - the rows shrink so Redeem does not run into Perf test (812x375)
	local reserve = math.max(18, math.floor(bh * 0.08)) + 8 + (if isOwner() then math.max(44, math.floor(bh * 0.14)) + 6 else 0)
	local rowH = math.max(44, math.min(math.max(50, math.floor(bh * 0.2)), math.floor((bh - reserve - 8) / 4)))
	-- the rows do not shrink below 44 pt (a finger) -
	-- if 4 rows and the bottom do not fit, the tab scrolls (the bottom elements are anchored to the canvas bottom)
	local need = 4 + 4 * rowH + 8 + reserve
	if need > bh + 1 then
		local sc = Instance.new("ScrollingFrame")
		sc.Name = "SettingsScroll"
		sc.BackgroundTransparency = 1
		sc.BorderSizePixel = 0
		sc.Size = UDim2.fromScale(1, 1)
		sc.CanvasSize = UDim2.new(1, 0, 0, need)
		sc.ScrollBarThickness = 6
		sc.ScrollingDirection = Enum.ScrollingDirection.Y
		sc.Parent = b
		b = sc :: any
	end
	local function toggleRow(i: number, label: string, get: () -> boolean, set: (boolean) -> ())
		local y = 4 + (i - 1) * rowH
		UIKit.text(b, label, UIKit.CREAM, { Name = "Label" .. i, Position = UDim2.new(0.04, 0, 0, y + rowH * 0.12), Size = UDim2.new(0.68, 0, 0, rowH * 0.6), TextXAlignment = Enum.TextXAlignment.Left })
		local t: TextButton
		local function paint()
			t.Text = if get() then Strings.Menu.on else Strings.Menu.off
			t.BackgroundColor3 = if get() then UIKit.GREEN else UIKit.GREY
		end
		t = UIKit.button(b, "", UIKit.GREEN, function()
			set(not get())
			paint()
		end)
		t.Name = "Toggle" .. i
		paint()
		t.AnchorPoint = Vector2.new(1, 0)
		t.Position = UDim2.new(0.96, 0, 0, y)
		t.Size = UDim2.new(0.22, 0, 0, rowH - 6)
	end
	local function soundRow(i: number, label: string, kind: string)
		toggleRow(i, label, function()
			return Sounds.isEnabled(kind)
		end, function(on: boolean)
			Sounds.setEnabled(kind, on)
		end)
	end
	soundRow(1, Strings.Menu.sounds, "sfx")
	soundRow(2, Strings.Menu.music, "music")
	-- P37 (Ride A Pet "View Other's Pets"): other players' dragons beyond Config.Dragon.lod.othersKeep are hidden locally; stored in
	-- the profile (settings.otherDragons), applied on the client at once, the server confirms
	toggleRow(3, Strings.Menu.otherDragons, function()
		return dragonLife == nil or dragonLife.showOthers()
	end, function(on: boolean)
		Menu.setOtherDragons(on)
	end)
	-- 2.9 (09 §1): the code of the week - a field and Redeem; case and spaces do not matter, the window and "once" are checked by the server
	do
		local y = 4 + 3 * rowH
		UIKit.text(b, Strings.Menu.code, UIKit.CREAM, { Name = "CodeLabel", Position = UDim2.new(0.04, 0, 0, y + rowH * 0.12), Size = UDim2.new(0.18, 0, 0, rowH * 0.6), TextXAlignment = Enum.TextXAlignment.Left })
		local box = Instance.new("TextBox")
		box.Name = "CodeBox"
		box.Text = ""
		box.PlaceholderText = Strings.Menu.codeHint
		box.PlaceholderColor3 = Color3.fromRGB(150, 145, 135)
		box.ClearTextOnFocus = false
		box.Font = UIKit.FONT
		box.TextScaled = true
		box.TextColor3 = Color3.new(1, 1, 1)
		box.BackgroundColor3 = UIKit.PANEL_LIGHT
		box.Position = UDim2.new(0.23, 0, 0, y) -- the height as Redeem
		box.Size = UDim2.new(0.49, 0, 0, rowH - 6)
		UIKit.corner(box, 0.25)
		UIKit.stroke(box, UIKit.GOLD, 2)
		box:GetPropertyChangedSignal("Text"):Connect(function()
			if #box.Text > Config.LiveOps.codeMax then
				box.Text = string.sub(box.Text, 1, Config.LiveOps.codeMax)
			end
		end)
		box.Parent = b
		local busy = false
		local redeem: TextButton
		redeem = UIKit.button(b, Strings.Menu.redeem, UIKit.GREEN, function()
			if busy or box.Text == "" then
				return
			end
			busy = true
			local reply = Net.call("Code", box.Text)
			busy = false
			if reply.ok then
				box.Text = ""
			else
				UIKit.shake(redeem)
				if banners then
					banners.toast(Strings.Errors[reply.reason or ""] or Strings.Errors.bad_request)
				end
			end
		end)
		redeem.Name = "Redeem"
		redeem.AnchorPoint = Vector2.new(1, 0)
		redeem.Position = UDim2.new(0.96, 0, 0, y)
		redeem.Size = UDim2.new(0.22, 0, 0, rowH - 6)
	end
	local verH = math.max(18, math.floor(bh * 0.08))
	-- the release number (game.PlaceVersion) - a screenshot shows which build it was taken on;
	-- for admins next to it - the last average FPS (Controllers/Perf)
	local fps = if perfCtl and perfCtl.lastFps then perfCtl.lastFps() else nil
	local ver = Config.GameVersion .. "  build " .. tostring(game.PlaceVersion) .. (if fps then "  " .. fmt(Strings.Menu.fps, { n = math.floor(fps + 0.5) }) else "")
	UIKit.text(b, fmt(Strings.Menu.version, { v = ver }), Color3.fromRGB(165, 160, 150), { Name = "Version", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.04, 0, 1, -2), Size = UDim2.new(0.92, 0, 0, verH), TextXAlignment = Enum.TextXAlignment.Left })
	if isOwner() then
		-- reset only by holding for Config.Admin.resetHold s, released - cancelled
		local r: TextButton
		local holdId = 0
		r = UIKit.button(b, Strings.Menu.reset, Color3.fromRGB(190, 64, 64), function() end) -- reset - only by holding (below)
		r.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			holdId += 1
			local my = holdId
			local t0 = os.clock()
			while holdId == my and r.Parent do
				local left = Config.Admin.resetHold - (os.clock() - t0)
				if left <= 0 then
					holdId = 0
					r.Text = Strings.Menu.reset
					local reply = Net.call("Admin", "reset")
					if reply.ok then
						UIStack.closeAll()
						if banners then
							banners.toast(Strings.Menu.resetDone)
						end
					else
						UIKit.shake(r)
					end
					return
				end
				r.Text = fmt(Strings.Menu.resetHolding, { n = math.ceil(left) })
				task.wait(0.1)
			end
		end)
		r.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				if holdId ~= 0 then -- released early: a hint for 2 s, no reset
					holdId = 0
					r.Text = Strings.Menu.resetHold
					task.delay(2, function()
						if r.Parent and holdId == 0 then
							r.Text = Strings.Menu.reset
						end
					end)
				end
			end
		end)
		r.Name = "Reset"
		local ownerH = math.max(44, math.floor(bh * 0.14))
		r.AnchorPoint = Vector2.new(0, 1) -- above the version line, under the three toggle rows
		r.Position = UDim2.new(0.04, 0, 1, -(verH + 6))
		r.Size = UDim2.new(0.29, 0, 0, ownerH) -- the admin buttons in a row (Reset, Bots, Perf test)
		-- 1.14 (gate 1: FPS with 6 nests): bots occupy the free nests; a press - all Config.Admin.bots.max or remove
		local bt: TextButton
		local function botsText(): string
			local n = workspace:GetAttribute("Bots")
			return if typeof(n) == "number" and n > 0 then fmt(Strings.Menu.bots, { n = n }) else Strings.Menu.botsOff
		end
		bt = UIKit.button(b, botsText(), Color3.fromRGB(70, 110, 170), function(btn)
			local n = workspace:GetAttribute("Bots")
			local want = if typeof(n) == "number" and n > 0 then 0 else Config.Admin.bots.max
			local reply = Net.call("Admin", "bots " .. want)
			if reply.ok then
				bt.Text = botsText()
			else
				UIKit.shake(btn)
			end
		end)
		bt.Name = "Bots"
		bt.AnchorPoint = Vector2.new(0.5, 1)
		bt.Position = UDim2.new(0.5, 0, 1, -(verH + 6))
		bt.Size = UDim2.new(0.29, 0, 0, ownerH)
		-- the "Perf test" experiment (Controllers/Perf) - the menu closes (the menu blur would distort the measurement); a press during the experiment - stop
		local pt: TextButton
		local function perfText(): string
			local on, k, n = false, 0, 0
			if perfCtl and perfCtl.testState then
				on, k, n = perfCtl.testState()
			end
			return if on then fmt(Strings.Menu.perfStep, { k = k, n = n }) else Strings.Menu.perfTest
		end
		pt = UIKit.button(b, perfText(), Color3.fromRGB(90, 130, 80), function(btn)
			if not perfCtl or not perfCtl.startTest then
				UIKit.shake(btn)
				return
			end
			local on = perfCtl.testState()
			if on then
				perfCtl.stopTest()
				pt.Text = perfText()
			elseif perfCtl.startTest() then
				UIStack.closeAll()
			else
				UIKit.shake(btn)
			end
		end)
		pt.Name = "PerfTest"
		pt.AnchorPoint = Vector2.new(1, 1)
		pt.Position = UDim2.new(0.96, 0, 1, -(verH + 6))
		pt.Size = UDim2.new(0.29, 0, 0, ownerH)
	end
end

-- the Keeper's 15 quests
local function questList()
	local b = body
	if not b then
		return
	end
	clearBody()
	local qd = Store.get("quests")
	local step = if typeof(qd) == "table" and typeof(qd.keeper) == "table" then (qd.keeper.step or 1) else 1
	local counters = if typeof(qd) == "table" and typeof(qd.counters) == "table" then qd.counters else {}
	-- 2.4: the dailies on top (06 §2), a header with the hours until the 00:00 UTC reset; below - the Keeper's chain with its own header
	local now = workspace:GetServerTimeNow()
	UIKit.text(b, Loc.t(Strings.Daily.header) .. "  -  " .. fmt(Strings.Daily.newIn, { time = Format.clock(RewardsCore.toReset(now)) }), UIKit.CREAM, { Name = "Header", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.09), TextXAlignment = Enum.TextXAlignment.Left })
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0, 0.11)
	list.Size = UDim2.fromScale(1, 0.89)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = b
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0.015, 0)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
	-- dailies: 3 rows (group, task, k/n, reward) + "all three"; the day's tasks are set by the server (quests.daily.ids)
	local R = Config.Rewards
	local daily = if typeof(qd) == "table" and typeof(qd.daily) == "table" then qd.daily else { ids = {}, counters = {}, done = {} }
	local sameDay = daily.date == RewardsCore.dateKey(now)
	for t, tier in RewardsCore.TIERS do
		local k, n, d = RewardsCore.dailyProgress(daily :: any, t, R)
		if not sameDay then
			k = 0
		end
		local done = sameDay and typeof(daily.done) == "table" and daily.done[tier] == true
		local row = Instance.new("Frame")
		row.Name = "Daily" .. t
		row.LayoutOrder = -20 + t
		row.BackgroundColor3 = if done then Color3.fromRGB(40, 48, 40) else Color3.fromRGB(52, 46, 60)
		row.BackgroundTransparency = if done then 0.25 else 0
		row.Size = UDim2.new(1, -10, 0.11, 0)
		UIKit.corner(row, 0.18)
		UIKit.stroke(row, UIKit.BORDER, 1)
		UIKit.text(row, (Strings.Daily.tiers :: any)[tier], if done then UIKit.GREEN else Color3.fromRGB(200, 170, 255), { Position = UDim2.fromScale(0.01, 0.1), Size = UDim2.fromScale(0.12, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		UIKit.text(row, if d then ((Strings.Daily.titles :: any)[d.id] or d.id) else "-", if done then UIKit.GREEN else Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.14, 0.1), Size = UDim2.fromScale(0.45, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		local prog = if d and (d.event == "playSec" or d.event == "flySec") then Format.clock(k) .. "/" .. Format.clock(n) else fmt(Strings.Steps.progress, { k = k, n = n })
		UIKit.text(row, if done then Strings.Quests.doneMark else prog, if done then UIKit.GREEN else UIKit.CREAM, { Position = UDim2.fromScale(0.6, 0.1), Size = UDim2.fromScale(0.15, 0.8), TextXAlignment = Enum.TextXAlignment.Right })
		UIKit.text(row, fmt(Strings.Quests.rewardMinutes, { n = B.daily[t] }), UIKit.GOLD, { Position = UDim2.fromScale(0.76, 0.1), Size = UDim2.fromScale(0.21, 0.8), TextXAlignment = Enum.TextXAlignment.Right }) -- the edge not under the scroll bar
		row.Parent = list
	end
	local bonus = sameDay and daily.bonus == true
	UIKit.text(list, (if bonus then "✓ " else "") .. Strings.Daily.bonus, if bonus then UIKit.GREEN else UIKit.GOLD, { Name = "DailyBonus", LayoutOrder = -16, Size = UDim2.new(1, -14, 0.08, 0), TextXAlignment = Enum.TextXAlignment.Right })
	-- the weekly quests of the running update - a header with the update and the time until the reset (Sun 19:00 UTC)
	-- two rows like the dailies; no set (off or before 08.11) - no block. Progress - from the profile if the set is the same (the week
	-- is reset by the server)
	local WK = R.weekly
	local wset, wupd = nil, 0
	if WK.on then
		wset, wupd = RewardsCore.weeklySet(Content.Updates, (ReplicatedStorage:GetAttribute("UpdatesLive") :: number?) or 0)
	end
	if wset then
		local wnow = now + ((ReplicatedStorage:GetAttribute("LiveOffset") :: number?) or 0)
		local wk = if typeof(qd) == "table" and typeof(qd.weekly) == "table" then qd.weekly else {}
		local same = wk.update == wupd and wk.week == RewardsCore.weekIndex(wnow, WK.anchor)
		local u = Content.Updates[wupd]
		UIKit.text(list, fmt(Strings.Weekly.header, { title = u and u.title or "" }) .. "  -  " .. fmt(Strings.Weekly.newIn, { time = NextUpCore.left(RewardsCore.weekLeft(wnow, WK.anchor), Loc.t(Strings.Next.days)) }), UIKit.CREAM,
			{ Name = "WeeklyHeader", LayoutOrder = -15, Size = UDim2.fromScale(1, 0.09), TextXAlignment = Enum.TextXAlignment.Left })
		local zone = Loc.t(Strings.Zone[wset.egg] or wset.egg)
		for i in wset.quests do
			local k, n, d = RewardsCore.weeklyProgress(wk :: any, i, wset)
			if not same then
				k = 0
			end
			local done = same and typeof(wk.done) == "table" and wk.done[tostring(i)] == true
			local row = Instance.new("Frame")
			row.Name = "Weekly" .. i
			row.LayoutOrder = -15 + i
			row.BackgroundColor3 = if done then Color3.fromRGB(40, 48, 40) else Color3.fromRGB(44, 52, 70)
			row.BackgroundTransparency = if done then 0.25 else 0
			row.Size = UDim2.new(1, -10, 0.11, 0)
			UIKit.corner(row, 0.18)
			UIKit.stroke(row, UIKit.BORDER, 1)
			UIKit.text(row, Loc.t(Strings.Weekly.tag), if done then UIKit.GREEN else Color3.fromRGB(140, 200, 255), { Position = UDim2.fromScale(0.01, 0.1), Size = UDim2.fromScale(0.12, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
			UIKit.text(row, if d then Loc.t((Strings.Weekly.titles :: any)[d.id] or d.id) else "-", if done then UIKit.GREEN else Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.14, 0.1), Size = UDim2.fromScale(0.45, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
			UIKit.text(row, if done then Strings.Quests.doneMark else fmt(Strings.Steps.progress, { k = k, n = n }), if done then UIKit.GREEN else UIKit.CREAM, { Position = UDim2.fromScale(0.6, 0.1), Size = UDim2.fromScale(0.1, 0.8), TextXAlignment = Enum.TextXAlignment.Right })
			UIKit.text(row, fmt(Strings.Weekly.reward, { n = WK.points, zone = zone }), UIKit.GOLD, { Position = UDim2.fromScale(0.71, 0.1), Size = UDim2.fromScale(0.26, 0.8), TextXAlignment = Enum.TextXAlignment.Right })
			row.Parent = list
		end
		-- the event badge - only in the first week of the update and if it is created (id > 0)
		local bkey = RewardsCore.weeklyBadge(Content.Updates, wupd, RewardsCore.weekIndex(wnow, WK.anchor), WK.anchor)
		local bdef = bkey and (Content.Badges :: any)[bkey]
		if bdef and (bdef.id or 0) > 0 then
			local owned = Store.get("badges")
			local got = typeof(owned) == "table" and owned[bkey] ~= nil
			UIKit.text(list, fmt(if got then Strings.Weekly.badgeDone else Strings.Weekly.badge, { badge = bdef.name }), if got then UIKit.GREEN else UIKit.GOLD,
				{ Name = "WeeklyBadge", LayoutOrder = -12, Size = UDim2.new(1, -14, 0.08, 0), TextXAlignment = Enum.TextXAlignment.Right })
		end
	end
	-- 2.8 (06 §1 item 15): the Keeper's gift - a Rare egg, the element chosen from 3
	local pick = if typeof(qd) == "table" and typeof(qd.keeper) == "table" and typeof(qd.keeper.pick) == "table" then qd.keeper.pick else nil
	if pick and #pick > 0 then
		UIKit.text(list, Strings.Quests.pickEgg, UIKit.GOLD, { Name = "PickHead", LayoutOrder = -4, Size = UDim2.fromScale(1, 0.08), TextXAlignment = Enum.TextXAlignment.Left })
		local row = Instance.new("Frame")
		row.Name = "PickRow"
		row.LayoutOrder = -3
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, -10, 0, 48)
		local gl = Instance.new("UIGridLayout")
		gl.CellPadding = UDim2.fromOffset(6, 0)
		gl.CellSize = UDim2.new(1 / #pick, -6, 1, 0)
		gl.SortOrder = Enum.SortOrder.LayoutOrder
		gl.Parent = row
		for i, el in pick do
			local e = Content.Elements[el]
			local b = Loc.raw(UIKit.button(row, if e then e.name else el, if e then rgb(e.color) else UIKit.GREY, function()
				Sounds.play("button")
				local r = Net.call("Claim", "keeper", el)
				if not r.ok and banners then
					banners.toast(Strings.Errors[r.reason or ""] or tostring(r.reason))
				end
			end)) -- the element name (Dusk coincides with the time of day)
			b.LayoutOrder = i
		end
		row.Parent = list
	end
	local total = QuestsCore.total((ReplicatedStorage:GetAttribute("UpdatesLive") :: number?) or 0) -- 2.9: 15 + the quests of the running updates
	UIKit.text(list, fmt(Strings.Quests.header, { n = math.min(step, total), total = total }), UIKit.CREAM, { Name = "KeeperHeader", LayoutOrder = -5, Size = UDim2.fromScale(1, 0.09), TextXAlignment = Enum.TextXAlignment.Left }) -- the same number as on the KEEPER n/15 plaque
	for i, q in QuestsCore.List do
		if i > total then
			break
		end
		local done = i < step
		local now = i == step
		local row = Instance.new("Frame")
		row.Name = "Q" .. i
		row.LayoutOrder = i
		row.BackgroundColor3 = if now then Color3.fromRGB(70, 52, 34) elseif done then Color3.fromRGB(40, 48, 40) else Color3.fromRGB(44, 44, 48)
		row.BackgroundTransparency = if done then 0.25 else 0
		row.Size = UDim2.fromScale(1, if now then 0.2 else 0.11)
		UIKit.corner(row, 0.18)
		UIKit.stroke(row, if now then Color3.fromRGB(226, 150, 60) else UIKit.BORDER, if now then 3 else 1)
		local mark = if done then "✓" elseif now then "📜" else "🔒"
		UIKit.iconText(row, mark, { Position = UDim2.fromScale(0.01, 0.08), Size = UDim2.fromScale(0.08, if now then 0.42 else 0.84) })
		local titleColor = if done then UIKit.GREEN elseif now then Color3.fromRGB(255, 200, 120) else Color3.fromRGB(150, 150, 160)
		UIKit.text(row, string.format("%d. %s", i, Loc.t(if done or now then q.title else Strings.Quests.locked)), titleColor, { Position = UDim2.fromScale(0.1, 0.06), Size = UDim2.fromScale(0.56, if now then 0.4 else 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		local reward = QuestsCore.rewardText(q, Strings.Quests :: any, Loc.t)
		UIKit.text(row, if done then Strings.Quests.doneMark elseif now then reward else reward, if done then UIKit.GREEN else UIKit.GOLD, { Position = UDim2.fromScale(0.67, 0.06), Size = UDim2.fromScale(0.31, if now then 0.4 else 0.8), TextXAlignment = Enum.TextXAlignment.Right })
		if now then
			local k = math.min(counters[q.event] or 0, q.count)
			UIKit.text(row, q.text, UIKit.CREAM, { Position = UDim2.fromScale(0.1, 0.5), Size = UDim2.fromScale(0.68, 0.42), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true })
			UIKit.text(row, fmt(Strings.Steps.progress, { k = k, n = q.count }), Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.8, 0.52), Size = UDim2.fromScale(0.18, 0.38), TextXAlignment = Enum.TextXAlignment.Right })
		end
		row.Parent = list
	end
end

-- a grid of 6 elements x 6 rarities
-- sets (Meadow first, then by element) with a Claim button, the "Ancient worldwide" line
local function indexGrid()
	local b = body
	if not b then
		return
	end
	clearBody()
	local index = Store.get("index") or {}
	local rewards = Store.get("rewards") or {}
	local claimed = rewards.indexClaimed or {}
	local k, n = IndexCore.count(index), IndexCore.total()
	local pct = if n > 0 then k / n else 0
	local bonusNow, bonusNext, atPct = IndexCore.tier(pct, B.index.thresholds)
	local bonusLine = if bonusNext then fmt(Strings.Index.bonusNext, { b = math.floor(bonusNext * 100 + 0.5), t = math.floor((atPct or 0) * 100 + 0.5) }) else fmt(Strings.Index.bonusNow, { b = math.floor(bonusNow * 100 + 0.5) })
	UIKit.text(b, fmt(Strings.Index.header, { k = k, n = n, pct = math.floor(pct * 100 + 0.5) }) .. "    " .. bonusLine, UIKit.CREAM, { Name = "Header", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.09), TextXAlignment = Enum.TextXAlignment.Left })
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0, 0.11)
	list.Size = UDim2.fromScale(1, 0.89)
	list.ScrollBarThickness = 6
	list.CanvasSize = UDim2.fromScale(0, 0)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.Parent = b
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0.012, 0)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
	local order = 0
	local function setRow(s: IndexCore.Set)
		order += 1
		local sk, sn = IndexCore.setProgress(index, s)
		local full = sk >= sn
		local row = Instance.new("Frame")
		row.Name = "Set_" .. s.id
		row.LayoutOrder = order
		row.BackgroundColor3 = if full then Color3.fromRGB(40, 56, 40) else Color3.fromRGB(44, 44, 48)
		row.Size = UDim2.fromScale(1, 0.1)
		UIKit.corner(row, 0.2)
		UIKit.stroke(row, if full and not claimed[s.id] then UIKit.GREEN else UIKit.BORDER, if full and not claimed[s.id] then 2 else 1)
		UIKit.text(row, fmt(Strings.Index.setRow, { name = Loc.t((Strings.Index.sets :: any)[s.id] or s.name), k = sk, n = sn }), if full then UIKit.GREEN else UIKit.CREAM, { Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.55, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		if full and not claimed[s.id] then
			local btn = UIKit.button(row, Strings.Index.claim, UIKit.GREEN, function()
				local r = Net.call("Claim", "index", s.id)
				if r.ok then
					Sounds.play("coin_plus")
					if coinFlight and typeof(r.coins) == "number" then
						coinFlight.fly(r.coins, nil)
					end
					indexGrid()
				elseif banners then
					banners.toast((Strings.Errors :: any)[r.reason or ""] or Strings.Errors.bad_request)
				end
			end, { minSize = Vector2.new(70, 28) })
			btn.AnchorPoint = Vector2.new(1, 0.5)
			btn.Position = UDim2.fromScale(0.97, 0.5)
			btn.Size = UDim2.fromScale(0.3, 0.8)
		else
			UIKit.text(row, if claimed[s.id] then Strings.Index.claimed else fmt(Strings.Index.rewardSet, { m = s.minutes }), if claimed[s.id] then UIKit.GREEN else UIKit.GOLD, { Position = UDim2.fromScale(0.6, 0.1), Size = UDim2.fromScale(0.37, 0.8), TextXAlignment = Enum.TextXAlignment.Right })
		end
		row.Parent = list
	end
	local sets = IndexCore.sets()
	setRow(sets[1])
	-- the grid
	order += 1
	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.LayoutOrder = order
	grid.BackgroundTransparency = 1
	grid.Size = UDim2.fromScale(1, 1) -- the grid over the whole list height, the sets below - by scrolling
	grid.Parent = list
	local elements = IndexCore.elements()
	local rarities = IndexCore.rarities()
	local rowH = 1 / #elements
	local colW = 0.86 / #rarities
	for ri, el in elements do
		local elc = (Content.Elements :: any)[el]
		Loc.raw(UIKit.text(grid, IndexCore.display(el), if elc then rgb(elc.color) else UIKit.CREAM, { Position = UDim2.fromScale(0, (ri - 1) * rowH), Size = UDim2.fromScale(0.13, rowH * 0.9), TextXAlignment = Enum.TextXAlignment.Left })) -- the element name
		for ci, r in rarities do
			local has = index[IndexCore.key(el, r)] ~= nil
			local cell = Instance.new("Frame")
			cell.Name = el .. "_" .. r
			cell.BackgroundColor3 = if has then (UIKit.RARITY[r] or UIKit.CREAM) else Color3.fromRGB(34, 34, 38)
			cell.BackgroundTransparency = if has then 0.15 else 0
			cell.Position = UDim2.fromScale(0.14 + (ci - 1) * colW, (ri - 1) * rowH)
			cell.Size = UDim2.fromScale(colW * 0.94, rowH * 0.88)
			UIKit.corner(cell, 0.18)
			UIKit.stroke(cell, if has then UIKit.STROKE else Color3.fromRGB(60, 60, 66), 1)
			-- the adult portrait of the element, undiscovered - a dark silhouette; the caption below
			-- the portrait at full height on the left, the caption on the right
			local pic = UIKit.portrait(cell, el, 2, { Position = UDim2.fromScale(0.01, 0.06), Size = UDim2.fromScale(0.44, 0.88) }, not has) -- 3:2 almost at full height
			UIKit.text(cell, if has then r else Strings.Index.unknown, if has then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 130),
				if pic then { Position = UDim2.fromScale(0.45, 0.16), Size = UDim2.fromScale(0.54, 0.68) } else { Position = UDim2.fromScale(0.05, 0.15), Size = UDim2.fromScale(0.9, 0.7) })
			cell.Parent = grid
		end
	end
	for i = 2, #sets do
		setRow(sets[i])
	end
	order += 1
	local anc = ReplicatedStorage:GetAttribute("AncientWorldwide")
	UIKit.text(list, fmt(Strings.Index.ancientWorldwide, { n = if anc ~= nil then anc else "?" }), Color3.fromRGB(200, 180, 230), { Name = "Ancient", LayoutOrder = order, Size = UDim2.fromScale(1, 0.08), TextXAlignment = Enum.TextXAlignment.Left })
end

local RENDER: { [string]: () -> () } = { dragons = dragonGrid, quests = questList, index = indexGrid, settings = settingsTab }
-- 2.2: tabs of other controllers (Shop): register before the book opens; render receives the tab body
export type ExtraTab = { id: string, word: string, icon: string, color: Color3, order: number, render: (Frame) -> () }
local extra: { ExtraTab } = {}
function Menu.register(tab: ExtraTab)
	table.insert(extra, tab)
	RENDER[tab.id] = function()
		if body then
			tab.render(body)
		end
	end
end

local function show(tab: string)
	currentTab = tab
	if setActive then
		setActive(tab)
	end
	local fn = RENDER[tab]
	if fn then
		fn()
	end
end

local function closeBook()
	if gui then
		gui:Destroy()
		gui = nil
	end
	body = nil
	setActive = nil
	currentTab = nil
end

-- which book tab is open (nil - the book is closed); Shop draws itself only on its own
function Menu.current(): string?
	return currentTab
end

-- open the book on a tab (or switch the tab if the book is open)
function Menu.open(tab: string)
	if gui then
		show(tab)
		return
	end
	local g = UIKit.screen("Book", 6)
	gui = g
	if not UIStack.open("book", closeBook) then
		closeBook()
		return
	end
	Sounds.play("menu_open")
	local T = Config.UI.tabs
	local tabs: { any } = { -- the tab order (Dragons, Index, Quests, Settings) + Shop second; UIKit.book sorts by order
		{ id = "dragons", word = Strings.Menu.dragons, icon = UIKit.ICON.dragons, color = rgb(T.dragons), order = 20 },
		{ id = "index", word = Strings.HUD.index, icon = UIKit.ICON.index, color = rgb(T.index), order = 30 },
		{ id = "quests", word = Strings.HUD.quests, icon = UIKit.ICON.quests, color = rgb(T.quests), order = 40 },
		{ id = "settings", word = Strings.Menu.settings, icon = UIKit.ICON.settings, color = rgb(T.settings), order = 90 },
	}
	for _, t in extra do -- 2.2: Shop (order 10 - first)
		table.insert(tabs, { id = t.id, word = t.word, icon = t.icon, color = t.color, order = t.order })
	end
	table.sort(tabs, function(a, b)
		return a.order < b.order
	end)
	local _, bodyFrame, setter = UIKit.book(g, tabs, tab, function(id)
		show(id)
	end, function()
		UIStack.close("book")
	end)
	body = bodyFrame
	setActive = setter
	show(tab)
end

function Menu.openDragons()
	Menu.open("dragons")
end

function Menu.openSettings()
	Menu.open("settings")
end

function Menu.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	coinFlight = loaded.CoinFlight
	hud = loaded.HUD
	dragonLife = loaded.DragonLife
	perfCtl = loaded.Perf
	if hud and hud.addMenuButton then
		local T = Config.UI.tabs
		hud.addMenuButton("left", Strings.Menu.dragons, rgb(T.dragons), Menu.openDragons, UIKit.ICON.dragons)
		-- P33: Settings - a round button in the Roblox button row at the top left (used to be top right)
		if hud.addTopbarButton then
			hud.addTopbarButton("Settings", UIKit.ICON.settings, Menu.openSettings)
		end
	end
	Store.on("dragons", function()
		if gui and currentTab == "dragons" then
			dragonGrid()
		end
	end)
	Store.on("ascension", function() -- the ascension line
		if gui and currentTab == "dragons" then
			dragonGrid()
		end
	end)
	Store.on("quests", function()
		if gui and currentTab == "quests" then
			questList()
		end
	end)
	Store.on("badges", function() -- the event badge line in the Quests tab
		if gui and currentTab == "quests" then
			questList()
		end
	end)
	Store.on("index", function()
		if gui and currentTab == "index" then
			indexGrid()
		end
	end)
end

return Menu
