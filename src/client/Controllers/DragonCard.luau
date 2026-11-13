--!strict
-- The dragon card (1.8 DragonCard; 03 addendum, craft/04 §7.10: a card in the element color): a live model in a ViewportFrame,
-- name, rarity, stage and element, a growth bar with a timer (StageEndsAt - server time), income, the Feed button (price from
-- the FeedPrice attribute) and Rename. Opens by tapping the own dragon (Input) or from the Dragons menu. Data - only Store.
-- Looks (07 add. 2.6): a row of color presets (Remote SetLook), the coloring in the frame - ImageColor3 of the frame.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local Growth = require(Core:WaitForChild("Growth"))
local Economy = require(Core:WaitForChild("Economy"))
local LooksCore = require(Core:WaitForChild("Looks")) -- looks

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local NameDialog = require(script.Parent:WaitForChild("NameDialog"))

local DragonCard = {}

local B = Config.Balance
local me = Players.LocalPlayer
local gui: ScreenGui? = nil
local seq = 0
local loadedRef: any = nil -- 2.2: Shop (Grow now / Treat)

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function findModel(uid: string): Model?
	local companion: Model? = nil
	for _, m in workspace:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Uid") == uid and m:GetAttribute("OwnerId") == me.UserId then
			if m:GetAttribute("Companion") ~= true then -- 1.9: the copy in the nest is preferred
				return m
			end
			companion = m
		end
	end
	return companion -- the companion has no copy in the nest - the frame takes the companion itself
end

-- the live model in the frame: a clone without labels, the camera at three quarters
local function viewport(parent: Frame, m: Model?): ViewportFrame
	local vp = Instance.new("ViewportFrame")
	vp.Name = "View"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(0.42, 0.9)
	vp.Position = UDim2.fromScale(0, 0.05)
	vp.Ambient = Color3.fromRGB(170, 170, 180)
	vp.LightColor = Color3.fromRGB(255, 245, 225)
	vp.LightDirection = Vector3.new(-1, -1.5, -0.6)
	vp.Parent = parent
	if not m then
		return vp
	end
	local ok, clone = pcall(function()
		local c = m:Clone()
		for _, d in c:GetDescendants() do
			if d:IsA("BillboardGui") or d:IsA("Highlight") or d:IsA("Seat") or d:IsA("Attachment") or d:IsA("Beam") or d:IsA("ParticleEmitter") then
				d:Destroy()
			end
		end
		return c
	end)
	if not ok or not clone then
		return vp
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = Config.UI.card.viewportFov
	local cf, size = clone:GetBoundingBox()
	clone:PivotTo(CFrame.identity) -- the asset's original orientation (snout toward -Z); before, the nest spot rotation was taken - the teen stood with its back
	cf, size = clone:GetBoundingBox()
	local dist = math.max(size.X, size.Y, size.Z) * 1.45
	-- the snout toward -Z: the camera front-side
	local eye = cf.Position + Vector3.new(-0.75, 0.45, -1).Unit * dist
	cam.CFrame = CFrame.lookAt(eye, cf.Position)
	cam.Parent = vp
	vp.CurrentCamera = cam
	clone.Parent = vp
	task.spawn(function() -- slow rotation
		local t0 = os.clock()
		while clone.Parent do
			local a = (os.clock() - t0) * 0.5
			local e = cf.Position + (CFrame.Angles(0, a, 0) * Vector3.new(-0.75, 0.45, -1).Unit) * dist
			cam.CFrame = CFrame.lookAt(e, cf.Position)
			task.wait(0.03)
		end
	end)
	return vp
end

function DragonCard.open(uid: string)
	local dragons = Store.get("dragons")
	local d = typeof(dragons) == "table" and dragons[uid]
	if not d or gui then
		return
	end
	seq += 1
	local my = seq
	local g = UIKit.screen("DragonCard", 7)
	gui = g
	-- over the book the book's cross is hidden - otherwise two crosses stand next to each other
	local fromBook = UIStack.isOpen("book")
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local bookGui = pg and pg:FindFirstChild("Book")
	local bookX = if fromBook and bookGui then bookGui:FindFirstChild("Close", true) else nil
	if bookX and bookX:IsA("GuiObject") then
		bookX.Visible = false
	end
	local function close()
		if bookX and bookX:IsA("GuiObject") and bookX.Parent then
			bookX.Visible = true
		end
		if my == seq and gui then
			gui:Destroy()
			gui = nil
		end
	end
	if not UIStack.open("card", close) then
		close()
		return
	end
	local el = Content.Elements[d.element]
	local tint = if el then rgb(el.color) else UIKit.BORDER -- the panel is charcoal, the element - the frame color
	-- on a low screen the card is larger, like the book
	local BK = Config.UI.book
	local small = g.AbsoluteSize.Y > 0 and g.AbsoluteSize.Y < (BK.smallBelow or 0)
	-- X and a tap outside the card - to the game (closes the book too); "‹" - back to the list
	local panel, body = UIKit.panel(g, d.name, if small then 0.86 else 0.7, if small then 0.92 else 0.72, function()
		UIStack.closeAll()
	end, tint)
	panel.Name = "Card"
	Loc.raw(panel:FindFirstChild("Title")) -- the dragon's name is not translated (unique)
	if fromBook then
		local back = UIKit.button(panel, "‹", Color3.fromRGB(110, 110, 120), function()
			UIStack.close("card")
		end, { minSize = Vector2.new(40, 40) })
		back.Name = "Back"
		back.AnchorPoint = Vector2.new(0.5, 0.2)
		back.Position = UDim2.fromScale(0, 0)
		back.Size = UDim2.fromScale(0.075, 0.12)
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = back
		back.ZIndex = 5
	end
	local title = panel:FindFirstChild("Title") :: TextLabel
	local vp = viewport(body, findModel(uid))
	local col = Instance.new("Frame")
	col.Name = "Info"
	col.BackgroundTransparency = 1
	col.Position = UDim2.fromScale(0.46, 0)
	col.Size = UDim2.fromScale(0.54, 1)
	col.Parent = body
	local rc = UIKit.RARITY[d.rarity] or Color3.new(1, 1, 1)
	local tags = {}
	if d.size == "huge" then
		table.insert(tags, Loc.t(Strings.Card.tagHuge))
	elseif d.size == "big" then
		table.insert(tags, Loc.t(Strings.Card.tagBig))
	end
	if d.shiny then
		table.insert(tags, Loc.t(Strings.Card.tagShiny))
	end
	table.insert(tags, Loc.t(Strings.Rarity[d.rarity] or d.rarity))
	UIKit.text(col, table.concat(tags, " "), rc, { Name = "Rarity", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.13), TextXAlignment = Enum.TextXAlignment.Left })
	local stageLbl = UIKit.text(col, "", Color3.new(1, 1, 1), { Name = "Stage", Position = UDim2.fromScale(0, 0.14), Size = UDim2.fromScale(1, 0.11), TextXAlignment = Enum.TextXAlignment.Left })
	local incomeLbl = UIKit.text(col, "", UIKit.GREEN, { Name = "Income", Position = UDim2.fromScale(0, 0.26), Size = UDim2.fromScale(1, 0.13), TextXAlignment = Enum.TextXAlignment.Left })
	-- growth bar
	local bar = Instance.new("Frame")
	bar.Name = "GrowthBar"
	bar.BackgroundColor3 = Color3.fromRGB(22, 22, 26)
	UIKit.stroke(bar, UIKit.BORDER, 1)
	bar.Position = UDim2.fromScale(0, 0.43)
	bar.Size = UDim2.fromScale(1, 0.09)
	UIKit.corner(bar, 0.5)
	bar.Parent = col
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = UIKit.GOLD
	fill.Size = UDim2.fromScale(0, 1)
	UIKit.corner(fill, 0.5)
	fill.Parent = bar
	local growLbl = UIKit.text(col, "", Color3.fromRGB(255, 240, 190), { Name = "Grow", Position = UDim2.fromScale(0, 0.53), Size = UDim2.fromScale(1, 0.1), TextXAlignment = Enum.TextXAlignment.Left })
	local whereLbl = UIKit.text(col, "", Color3.fromRGB(200, 200, 210), { Name = "Where", Position = UDim2.fromScale(0, 0.64), Size = UDim2.fromScale(1, 0.09), TextXAlignment = Enum.TextXAlignment.Left })
	local feedBtn = UIKit.button(col, "", Color3.fromRGB(230, 120, 70), function(btn)
		local reply = Net.call("Feed", uid)
		if not reply.ok then -- the crunch and the "fed" voice - Sounds by FedUntil (one path for the card, the button and Feed all)
			UIKit.shake(btn)
		end
	end)
	feedBtn.Name = "Feed"
	feedBtn.Position = UDim2.fromScale(0, 0.78)
	feedBtn.Size = UDim2.fromScale(0.32, 0.2)
	local renameBtn = UIKit.button(col, Strings.Card.rename, Color3.fromRGB(80, 140, 220), function()
		NameDialog.open(uid, d.name, { onDone = function(name)
			if title then
				title.Text = name
			end
		end })
	end)
	renameBtn.Position = UDim2.fromScale(0.34, 0.78)
	renameBtn.Size = UDim2.fromScale(0.32, 0.2)
	-- 1.9 (craft/04 §7.11 the "companion" star, §7.12 Ride): the third button - "Companion" (make it the companion) or Ride / Fly if it is the companion
	local thirdBtn = UIKit.button(col, Strings.Card.setCompanion, Color3.fromRGB(150, 110, 200), function(btn)
		local isComp = Store.get("companion") == uid
		local reply = if isComp then Net.call("Mount", uid) else Net.call("SetCompanion", uid)
		if reply.ok then
			Sounds.play(if isComp then "mount" else "button")
			if isComp then
				UIStack.close("card")
			end
		else
			UIKit.shake(btn)
		end
	end)
	thirdBtn.Name = "Third"
	thirdBtn.Position = UDim2.fromScale(0.68, 0.78)
	thirdBtn.Size = UDim2.fromScale(0.32, 0.2)
	-- (spec 03 add. 1.3 "Move (nest / sanctuary)", 05 §3 Release): under the model on the left - move and release; the companion has neither.
	-- Release - a second press within Config.UI.card.releaseConfirm s ("Sure? +N"); with a full nest "To Nest" swaps with the weakest
	local moveBtn = UIKit.button(body, Strings.Card.toNest, Color3.fromRGB(70, 150, 120), function(btn)
		local order = Store.get("nestOrder")
		local inNestNow = typeof(order) == "table" and table.find(order, uid) ~= nil
		local reply = Net.call("MoveDragon", uid, if inNestNow then "sanctuary" else "nest")
		if reply.ok then
			Sounds.play("button")
		else
			UIKit.shake(btn)
		end
	end)
	moveBtn.Name = "Move"
	local armedUntil = 0
	local releaseBtn: TextButton
	releaseBtn = UIKit.button(body, Strings.Card.release, Color3.fromRGB(150, 70, 70), function(btn)
		local now = os.clock()
		if now > armedUntil then
			armedUntil = now + (Config.UI.card.releaseConfirm or 3)
			local rec = (Store.get("dragons") or {})[uid]
			releaseBtn.Text = fmt(Strings.Card.releaseSure, { n = Format.number(if rec then Economy.releaseRefund(rec, B) else 0) })
			releaseBtn.BackgroundColor3 = Color3.fromRGB(210, 60, 60)
			local mine = armedUntil
			task.delay((Config.UI.card.releaseConfirm or 3) + 0.05, function()
				if armedUntil == mine and releaseBtn.Parent then
					armedUntil = 0
					releaseBtn.Text = Strings.Card.release
					releaseBtn.BackgroundColor3 = Color3.fromRGB(150, 70, 70)
				end
			end)
			return
		end
		armedUntil = 0
		local reply = Net.call("Release", uid, true)
		if reply.ok then
			Sounds.play("coin_plus")
			UIStack.close("card")
		else
			UIKit.shake(btn)
			releaseBtn.Text = Strings.Card.release
			releaseBtn.BackgroundColor3 = Color3.fromRGB(150, 70, 70)
		end
	end)
	releaseBtn.Name = "Release"
	-- 2.2 (07 §2 no. 1b, no. 8): the shop row above the main buttons - Grow now (price by step or Use ticket) and Treat (from stock, otherwise
	-- buy x1); only with growth remaining > 60 s and from 3:00 of the first session (Shop.robuxAllowed); the main buttons below
	local shop = loadedRef and loadedRef.Shop
	local growBtn = UIKit.button(col, Strings.Card.growNow, Color3.fromRGB(80, 150, 230), function(btn)
		if shop then
			shop.buy("GrowNow", uid, nil)
		else
			UIKit.shake(btn)
		end
	end, { minSize = Vector2.new(60, 36) })
	growBtn.Name = "GrowNow"
	growBtn.Position = UDim2.fromScale(0, 0.74)
	growBtn.Size = UDim2.fromScale(0.49, 0.1)
	growBtn.Visible = false
	local treatBtn = UIKit.button(col, Strings.Card.treat, Color3.fromRGB(200, 120, 60), function(btn)
		if shop and shop.treats() > 0 then
			local reply = Net.call("Treat", uid)
			if reply.ok then
				Sounds.play("feed")
				-- a treat speeds growth, does not feed (FedUntil is the same) - the content voice here, 2D
				local rec = (Store.get("dragons") or {})[uid]
				task.delay((Content :: any).Voices.happyDelay or 0.3, Sounds.voice, if rec then rec.stage else nil, "happy")
			else
				UIKit.shake(btn)
			end
		elseif shop then
			shop.buy("Treats_1_49", nil, nil)
		else
			UIKit.shake(btn)
		end
	end, { minSize = Vector2.new(60, 36) })
	treatBtn.Name = "Treat"
	treatBtn.Position = UDim2.fromScale(0.51, 0.74)
	treatBtn.Size = UDim2.fromScale(0.49, 0.1)
	treatBtn.Visible = false

	-- looks (07 add. 2.6): the row of color presets above the shop row - owned presets that fit this dragon (Solstice -
	-- only Dusk): "✓ Sunset" is on this one (a tap removes it), "Move Sunset" is on another (a tap moves it here), "Sunset" is free.
	-- No presets - a single Looks button (the Looks tab of the shop), only when the Grow now / Treat row is hidden (07 §9: one contextual)
	local LK = Config.Looks
	local lookRow = Instance.new("Frame")
	lookRow.Name = "Looks"
	lookRow.BackgroundTransparency = 1
	lookRow.Visible = false
	lookRow.Parent = col
	local lookList = Instance.new("UIListLayout")
	lookList.FillDirection = Enum.FillDirection.Horizontal
	lookList.Padding = UDim.new(0, 4)
	lookList.SortOrder = Enum.SortOrder.LayoutOrder
	lookList.Parent = lookRow
	local lookSig = ""
	local function toast(text: string)
		local banners = loadedRef and loadedRef.Banners
		if banners then
			banners.toast(text)
		end
	end
	local function renderLooks()
		local list = LooksCore.cardPresets({ owned = Store.get("owned"), dragons = Store.get("dragons") }, uid, LK)
		local fallback = #list == 0 and shop ~= nil and shop.robuxAllowed() and not growBtn.Visible and not treatBtn.Visible
		local parts = {}
		for _, e in list do
			table.insert(parts, e.id .. ":" .. e.state)
		end
		local sig = table.concat(parts, ",") .. (if fallback then "|shop" else "")
		if sig == lookSig then
			return
		end
		lookSig = sig
		for _, ch in lookRow:GetChildren() do
			if ch:IsA("GuiButton") then
				ch:Destroy()
			end
		end
		lookRow.Visible = fallback or #list > 0
		if fallback then
			local b = UIKit.button(lookRow, Strings.Card.looks, Color3.fromRGB(150, 90, 190), function()
				UIStack.closeAll()
				shop.open("looks")
			end, { minSize = Vector2.new(60, 44) })
			b.Name = "ShopLooks"
			b.Size = UDim2.new(0.49, 0, 1, 0)
			return
		end
		for i, e in list do
			local name = (Strings.Looks.presets :: any)[e.id] or e.id
			local P = (LK.presets :: any)[e.id]
			local text = if e.state == "on" then fmt(Strings.Looks.presetOn, { name = name }) elseif e.state == "other" then fmt(Strings.Looks.presetMove, { name = name }) else name
			local b = UIKit.button(lookRow, text, if e.state == "on" then rgb(P.tint) else Color3.fromRGB(84, 80, 96), function(btn)
				local id = if e.state == "on" then "none" else e.id
				local reply = Net.call("SetLook", "preset", id, uid)
				if reply.ok then
					Sounds.play("button")
					toast(fmt(if id == "none" then Strings.Looks.presetOff else Strings.Looks.presetSet, { name = name, dragon = d.name or "" }))
				else
					UIKit.shake(btn)
					toast(fmt((Strings.Errors :: any)[reply.reason or ""] or Strings.Errors.bad_request, { element = reply.element or "" }))
				end
			end, { minSize = Vector2.new(60, 44) })
			b.Name = "Preset_" .. e.id
			b.LayoutOrder = i
			b.Size = UDim2.new(1 / #list, -4, 1, 0)
			b.TextStrokeTransparency = 0.4 -- light Solstice under white text
			if e.state ~= "on" then
				b.TextColor3 = rgb(P.tint)
			end
		end
	end

	-- the column layout in px bottom-up (buttons at least 44 px - height fractions on the phone pushed them out of the card):
	-- the main buttons at the bottom, above them the shop row (if visible), the texts and the bar share the rest in the old proportions
	local texts = { { stageLbl, 0.14, 0.11 }, { incomeLbl, 0.26, 0.13 }, { bar, 0.43, 0.09 }, { growLbl, 0.53, 0.1 }, { whereLbl, 0.64, 0.09 } }
	local rarityLbl = col:FindFirstChild("Rarity") :: TextLabel
	local function layoutCol()
		local H = UIKit.unscaled(col).Y
		if H < 20 then
			return
		end
		local bh = math.max(44, math.floor(H * 0.14))
		local shopOn = growBtn.Visible or treatBtn.Visible
		local sh = if shopOn then math.max(36, math.floor(H * 0.1)) else 0
		local rowY = H - bh
		for i, bt in { feedBtn, renameBtn, thirdBtn } do
			bt.Position = UDim2.new((i - 1) * 0.34, 0, 0, rowY)
			bt.Size = UDim2.new(0.32, 0, 0, bh)
		end
		-- move and release under the model (the same row height); the model above them
		local actOn = moveBtn.Visible or releaseBtn.Visible
		moveBtn.Position = UDim2.new(0, 0, 0, rowY)
		moveBtn.Size = UDim2.new(if releaseBtn.Visible then 0.235 else 0.44, 0, 0, bh)
		releaseBtn.Position = UDim2.new(if moveBtn.Visible then 0.245 else 0, 0, 0, rowY)
		releaseBtn.Size = UDim2.new(if moveBtn.Visible then 0.195 else 0.44, 0, 0, bh)
		vp.Position = UDim2.new(0, 0, 0, 4)
		vp.Size = UDim2.new(0.42, 0, 0, math.max(40, (if actOn then rowY - 8 else H - 8)))
		local shopY = rowY - 4 - sh
		growBtn.Position = UDim2.new(0, 0, 0, shopY)
		growBtn.Size = UDim2.new(0.49, 0, 0, sh)
		treatBtn.Position = UDim2.new(0.51, 0, 0, shopY)
		treatBtn.Size = UDim2.new(0.49, 0, 0, sh)
		local topY = if shopOn then shopY else rowY
		-- looks: the preset row above the shop row (or above the main buttons)
		local lh = if lookRow.Visible then math.max(44, math.floor(H * 0.1)) else 0
		local lookY = topY - 4 - lh
		lookRow.Position = UDim2.new(0, 0, 0, lookY)
		lookRow.Size = UDim2.new(1, 0, 0, lh)
		if lookRow.Visible then
			topY = lookY
		end
		local k = math.max(0, topY - 6) / 0.73
		rarityLbl.Position = UDim2.new(0, 0, 0, 0)
		rarityLbl.Size = UDim2.new(1, 0, 0, 0.13 * k)
		for _, t in texts do
			(t[1] :: GuiObject).Position = UDim2.new(0, 0, 0, t[2] * k)
			;(t[1] :: GuiObject).Size = UDim2.new(1, 0, 0, t[3] * k)
		end
	end
	col:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutCol)

	local function refresh()
		local dd = Store.get("dragons")
		local rec = typeof(dd) == "table" and dd[uid]
		if not rec then
			UIStack.close("card")
			return
		end
		d = rec
		title.Text = rec.name
		local now = workspace:GetServerTimeNow()
		local vdef = if typeof(rec.variant) == "string" then (Content.Variants :: any)[rec.variant] else nil -- 2.9: «Adult - Glacier Frost»
		local elName = if el then el.name else rec.element
		stageLbl.Text = fmt(Strings.Card.stageLine, { stage = Loc.t(Strings.Stage[rec.stage] or ""), element = if vdef then fmt(Strings.LiveOps.variant, { label = vdef.label, element = elName }) else elName })
		local order = Store.get("nestOrder") -- income with the nest multiplier if the dragon is in the nest
		local inNest = typeof(order) == "table" and table.find(order, rec.uid) ~= nil
		incomeLbl.Text = fmt(Strings.Card.income, { n = Format.number(Economy.dragonIncome(rec, B) * (if inNest then UIKit.rateMult() else 1)) })
		local wherePlace = if inNest then Strings.Card.inNest else Strings.Card.inSanctuary -- one grown in the sanctuary read "In the Nest"
		local total = Growth.stageSecondsOf(rec, B) -- 05 add. 2.18: the firstborn's bar by growAs
		local left = Growth.remaining(rec, now)
		if total and left then
			local fed = Growth.isFed(rec, now)
			fill.Size = UDim2.fromScale(math.clamp(1 - left / total, 0, 1), 1)
			fill.BackgroundColor3 = if fed then Color3.fromRGB(255, 150, 60) else UIKit.GOLD
			growLbl.Text = if fed then fmt(Strings.Card.fedLine, { time = Format.clock(left) }) else fmt(Strings.Card.growsIn, { time = Format.clock(left) })
			feedBtn.Visible = not fed
			local nestOrder = Store.get("nestOrder")
			local inNest = typeof(nestOrder) == "table" and table.find(nestOrder, uid) ~= nil
			feedBtn.Text = fmt(Strings.Card.feed, { n = Format.number(Economy.feedPrice(rec, Store.get("ascension") or 0, B)) })
			feedBtn.Visible = not fed and inNest
			whereLbl.Text = if inNest then Strings.Card.inNest else Strings.Card.inSanctuary
			local allowed = shop ~= nil and left >= Config.Shop.growNow.minRemaining and shop.robuxAllowed()
			growBtn.Visible = allowed
			treatBtn.Visible = allowed
			if allowed then
				local t = shop.treats()
				treatBtn.Text = if t > 0 then fmt(Strings.Shop.treatsLeft, { n = t }) else Strings.Card.treat
				if shop.ticketFits("growNow", left) then
					growBtn.Text = Strings.Shop.useTicket
				else
					shop.contextPrice("growNow", left, function(txt: string)
						if growBtn.Parent then
							growBtn.Text = Strings.Card.growNow .. "  " .. txt
						end
					end)
				end
			end
		else
			fill.Size = UDim2.fromScale(1, 1)
			growLbl.Text = Strings.Card.fullyGrown
			feedBtn.Visible = false
			growBtn.Visible = false
			treatBtn.Visible = false
			whereLbl.Text = wherePlace
		end
		-- 1.9: the companion - a label and the Ride / Fly button (stage >= 1, not mounted); otherwise "Companion"
		local isComp = Store.get("companion") == uid
		moveBtn.Visible = not isComp -- the companion is neither moved nor released
		releaseBtn.Visible = not isComp
		moveBtn.Text = if inNest then Strings.Card.toSanctuary else Strings.Card.toNest
		if isComp then
			whereLbl.Text = Strings.Card.isCompanion -- the companion is with the player and takes no visible nest spot (was "Your companion - In the Nest")
			local st = rec.stage or 0
			thirdBtn.Text = if st >= 2 then Strings.Hints.fly else Strings.Hints.ride
			thirdBtn.BackgroundColor3 = if st >= 2 then Color3.fromRGB(80, 150, 230) else Color3.fromRGB(226, 150, 60)
			thirdBtn.Visible = st >= 1 and Players.LocalPlayer:GetAttribute("Mounted") == nil
		else
			thirdBtn.Text = Strings.Card.setCompanion
			thirdBtn.BackgroundColor3 = Color3.fromRGB(150, 110, 200)
			local nestOrder = Store.get("nestOrder")
			thirdBtn.Visible = typeof(nestOrder) == "table" and table.find(nestOrder, uid) ~= nil
		end
		-- looks: the preset row and the coloring in the frame (Highlight is not drawn in a ViewportFrame - a tint of the whole frame image)
		renderLooks()
		local P = if typeof(rec.preset) == "string" then (LK.presets :: any)[rec.preset] else nil
		vp.ImageColor3 = if P then Color3.new(1, 1, 1):Lerp(rgb(P.tint), LK.highlight.viewport) else Color3.new(1, 1, 1)
		layoutCol()
	end
	refresh()
	task.spawn(function()
		while my == seq and gui do
			task.wait(0.5)
			if my == seq and gui then
				pcall(refresh)
			end
		end
	end)
end

function DragonCard.init(_snapshot: any, _loaded: any)
	loadedRef = _loaded -- 2.2: Shop (Grow now / Treat) loads after the card
end

return DragonCard
