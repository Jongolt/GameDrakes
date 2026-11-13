--!strict
-- Shared interface parts (02 §1, §6; craft/04 §7.11 HTTYD): one "book" font over the world with a dark outline
-- (Config.UI.font), dark charcoal panels with a thin light frame, buttons with gloss and an outline, icons are emoji (drawn on
-- all platforms without loading images), sizes in screen fractions, buttons no smaller than 44 px, ResetOnSpawn = false and ScreenInsets on
-- every screen GUI; a press - a micro-movement in the same frame, a server refusal - the button shakes briefly.

local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UIKit = {}

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the font from Config (an Enum.Font name); if this client lacks it - FredokaOne
local function pickFont(name: string): Enum.Font
	local ok, f = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and typeof(f) == "EnumItem" then f :: Enum.Font else Enum.Font.FredokaOne
end

local P = Config.UI.panel
UIKit.FONT = pickFont(Config.UI.font)
UIKit.GREEN = Color3.fromRGB(88, 196, 92)
UIKit.GOLD = Color3.fromRGB(255, 214, 92)
UIKit.CREAM = rgb(P.text)
UIKit.STROKE = Color3.fromRGB(32, 26, 24)
UIKit.ONE = Color3.new(1, 1, 1)
UIKit.PANEL = rgb(P.color)
UIKit.PANEL_LIGHT = rgb(P.light)
UIKit.BORDER = rgb(P.border)
UIKit.GREY = Color3.fromRGB(120, 120, 130)
UIKit.ORANGE = Color3.fromRGB(226, 110, 40)
UIKit.worldUiHidden = false -- in a menu/scene the labels above objects and the hint arrow are not drawn
UIKit.hudHidden = false -- menu / scene (HUD.setVisible false) - separately from combat focus
UIKit.focusGuide = false -- the chase focus with the road (HUD.setFocus keepGuide) - the screen-edge pointer stays
UIKit.bannerUntil = 0 -- until this os.clock() the step banner and the Keeper's line are hidden

-- the dragon portrait by element and stage (Content.Assets.portraits)
-- silhouette - the dark silhouette of the undiscovered (Index); nil - no picture (the caller draws an emoji)
function UIKit.portrait(parent: Instance, element: string, stage: number, props: { [string]: any }?, silhouette: boolean?): ImageLabel?
	local Content = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Content"))
	local list = (Content.Assets :: any).portraits and (Content.Assets :: any).portraits[element]
	local id = list and list[math.clamp(stage, 0, 3) + 1]
	if not id or id == 0 then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Portrait"
	img.BackgroundTransparency = 1
	img.Image = "rbxassetid://" .. tostring(id)
	img.ScaleType = Enum.ScaleType.Fit
	if silhouette then
		img.ImageColor3 = Color3.new(0, 0, 0)
		img.ImageTransparency = 0.35
	end
	for k, v in props or {} do
		(img :: any)[k] = v
	end
	img.Parent = parent
	return img
end

-- the income multiplier of the own nest (the server Nest writes RateMult = the nest income / the sum of the base values): the "real" dragon income in
-- the cards and "+N"; 1 - no nest yet
function UIKit.rateMult(): number
	local me = Players.LocalPlayer
	for _, r in game:GetService("CollectionService"):GetTagged("Incubator") do
		if r:GetAttribute("OwnerId") == me.UserId then
			local nest = r.Parent and r.Parent.Parent
			local m = nest and nest:GetAttribute("RateMult")
			return if typeof(m) == "number" and m > 0 then m else 1
		end
	end
	return 1
end

-- Roblox computes StudsOffsetWorldSpace of a BillboardGui in the axes of the adornee part. Incubator rings and the coin
-- pile are cylinders rotated by 90 degrees, and "up by 4.2" went sideways along the ground: the round Hatch was drawn under the ring or
-- behind the player, a click on it did not land. The world-up offset is converted into the axes of a static part (moving ones - as before).
function UIKit.worldUp(adornee: Instance?, h: number): Vector3
	if adornee and adornee:IsA("BasePart") and adornee.Anchored then
		return adornee.CFrame:VectorToObjectSpace(Vector3.new(0, h, 0))
	end
	return Vector3.new(0, h, 0)
end

-- HUD rectangles in viewport coordinates (like WorldToViewportPoint: from the very top of the screen) -
-- the Roblox buttons at the top left, the coins, the plaques on the left, the step banner, the Keeper, Settings in the Roblox row, the action and flight buttons. By them
-- world labels and the Keeper's bubble are not drawn under the HUD. AbsolutePosition of every ScreenGui is counted from the bottom of the Roblox bar.
function UIKit.hudRects(): { { number } }
	local out: { { number } } = {}
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not pg then
		return out
	end
	local inset = GuiService:GetGuiInset().Y
	table.insert(out, { 0, 0, GuiService.TopbarInset.Min.X, inset })
	local function add(o: Instance?)
		if o and o:IsA("GuiObject") and o.Visible and o.AbsoluteSize.X > 1 and o.AbsoluteSize.Y > 1 then
			local p, z = o.AbsolutePosition, o.AbsoluteSize
			table.insert(out, { p.X, p.Y + inset, p.X + z.X, p.Y + z.Y + inset })
		end
	end
	local function on(name: string): ScreenGui?
		local g = pg:FindFirstChild(name)
		return if g and g:IsA("ScreenGui") and g.Enabled then g else nil
	end
	local hud = on("HUD")
	if hud then
		for _, c in hud:GetChildren() do
			if c.Name == "LeftColumn" then
				for _, b in c:GetChildren() do
					add(b)
				end
			else
				add(c)
			end
		end
	end
	local sb = on("StepBanner")
	if sb then
		add(sb:FindFirstChild("Step"))
		add(sb:FindFirstChild("Next")) -- the NEXT line (Controllers/NextUp) in place of the step banner - Old Ash's bubble goes under it
	end
	local q = on("Quests")
	if q then
		add(q:FindFirstChild("Panel"))
	end
	for _, name in { "Topbar", "Movement" } do
		local g = on(name)
		if g then
			for _, d in g:GetDescendants() do
				if d:IsA("GuiButton") then
					add(d)
				end
			end
		end
	end
	for _, name in { "FreeGiftCard", "InviteCard" } do -- the side cards are HUD too (world labels under them are dimmed)
		local g = on(name)
		if g then
			for _, c in g:GetChildren() do
				add(c)
			end
		end
	end
	return out
end

-- (in the top right corner the Free Gift and Hatch Party cards lay on the step banner):
-- the side card stands at the right edge RIGHT UNDER the Keeper plaque (Quests.Panel, 0.28 of the height), not above it; mounted and in flight
-- it is hidden (02 §1: menus do not open in flight; the Up/Down/Dismount buttons are there) and returns after dismounting.
function UIKit.sideCard(g: ScreenGui, f: GuiObject, gap: number?)
	local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
	for _, name in { "FreeGiftCard", "InviteCard" } do -- one side card at a time: a new one closes the previous (there is one spot under the plaque)
		local other = pg and pg:FindFirstChild(name)
		if other and other ~= g and other:IsA("ScreenGui") then
			other:Destroy()
		end
	end
	local q = pg and pg:FindFirstChild("Quests")
	local panel = if q then q:FindFirstChild("Panel") else nil
	f.AnchorPoint = Vector2.new(1, 0)
	if panel and panel:IsA("GuiObject") and panel.AbsoluteSize.Y > 1 then
		f.Position = UDim2.new(1, -8, 0, panel.AbsolutePosition.Y + panel.AbsoluteSize.Y + (gap or 8))
	else
		f.Position = UDim2.new(1, -8, Config.Quests.panelY, 46 + (gap or 8))
	end
	local me = Players.LocalPlayer
	local function sync()
		local wanted = me:GetAttribute("Mounted") == nil
		if UIKit.worldUiHidden then -- a menu is open or a scene is playing (HUD.setVisible(false)): do not show over it, return with the HUD
			g.Enabled = false
			g:SetAttribute("HudWasEnabled", wanted)
		else
			g.Enabled = wanted
		end
	end
	local conn = me:GetAttributeChangedSignal("Mounted"):Connect(sync)
	g.Destroying:Connect(function()
		conn:Disconnect()
	end)
	sync()
end

-- half the world height of a part (for a rotated cylinder Size.Y is the diameter, not the height)
function UIKit.halfHeight(p: BasePart): number
	local cf, sz = p.CFrame, p.Size
	return (math.abs(cf.RightVector.Y) * sz.X + math.abs(cf.UpVector.Y) * sz.Y + math.abs(cf.LookVector.Y) * sz.Z) / 2
end
UIKit.onPress = nil :: (() -> ())? -- Sounds hooks the button sound onto every press
UIKit.onDeny = nil :: (() -> ())? -- the refusal sound on a shake
UIKit.RARITY = {
	Common = Color3.fromRGB(190, 190, 190),
	Uncommon = Color3.fromRGB(96, 205, 100),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(180, 105, 255),
	Legendary = Color3.fromRGB(255, 200, 70),
	Mythic = Color3.fromRGB(255, 90, 90),
}
UIKit.ICON = { dragons = "🐉", settings = "⚙️", coin = "🪙", egg = "🥚", shop = "🛒", quests = "📜", index = "📖", star = "⭐", dice = "🎲", pen = "✎" }

-- ---------------------------------------------------------------------------------------------- images (reserve)
-- Open Cloud images are not guaranteed to load on phones - the interface does not rely on them; preloading is kept for
-- future assets (Beam textures etc.)
UIKit.ready = {} :: { [number]: boolean }
local pendingImages: { [ImageLabel]: number } = setmetatable({}, { __mode = "k" }) :: any
local assetWatchers: { (number) -> () } = {}

function UIKit.onAssetReady(fn: (number) -> ())
	table.insert(assetWatchers, fn)
end

function UIKit.preload(ids: { number })
	task.spawn(function()
		local left: { number } = {}
		for _, id in ids do
			if id and id > 0 and not UIKit.ready[id] then
				table.insert(left, id)
			end
		end
		for attempt = 1, 8 do
			if #left == 0 then
				return
			end
			local urls = {}
			for _, id in left do
				table.insert(urls, "rbxassetid://" .. id)
			end
			local failed: { number } = {}
			local ok, err = pcall(function()
				ContentProvider:PreloadAsync(urls, function(content: string, status: Enum.AssetFetchStatus)
					local id = tonumber(string.match(content, "%d+"))
					if not id then
						return
					end
					if status == Enum.AssetFetchStatus.Success then
						UIKit.ready[id] = true
						for img, iid in pendingImages do
							if iid == id and img.Parent then
								img.Image = ""
								img.Image = content
								pendingImages[img] = nil
							end
						end
						for _, fn in assetWatchers do
							task.spawn(fn, id)
						end
					else
						table.insert(failed, id)
					end
				end)
			end)
			if not ok then
				warn("[UIKit] preload: " .. tostring(err))
				failed = left
			end
			left = failed
			if #left > 0 then
				task.wait(3 * attempt)
			end
		end
		if #left > 0 then
			warn("[UIKit] images did not load: " .. table.concat(left, ","))
		end
	end)
end

function UIKit.image(parent: Instance, assetId: number, props: { [string]: any }?): ImageLabel
	local i = Instance.new("ImageLabel")
	i.BackgroundTransparency = 1
	i.Image = if assetId and assetId > 0 then "rbxassetid://" .. assetId else ""
	i.ScaleType = Enum.ScaleType.Fit
	for k, v in props or {} do
		(i :: any)[k] = v
	end
	i.Parent = parent
	if assetId and assetId > 0 and not UIKit.ready[assetId] then
		pendingImages[i] = assetId
	end
	return i
end

-- ---------------------------------------------------------------------------------------------- basic elements
function UIKit.screen(name: string, order: number?): ScreenGui
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = false
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.DisplayOrder = order or 1
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.Parent = pg
	return g
end

-- a panel without a backing, frame or gloss
-- the text outline is thicker - readable on grass and sky. The flag Config.UI.plainText (false - the old plaques)
function UIKit.plain(obj: GuiObject)
	if not Config.UI.plainText then
		return
	end
	obj.BackgroundTransparency = 1
	for _, c in obj:GetChildren() do
		if c:IsA("UIStroke") and c.ApplyStrokeMode == Enum.ApplyStrokeMode.Border then
			c.Enabled = false
		elseif c:IsA("UIGradient") then
			c.Enabled = false
		end
	end
	for _, d in obj:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			local s = d:FindFirstChildOfClass("UIStroke")
			if s and s.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
				s.Thickness = math.max(s.Thickness, Config.UI.plainStroke)
				s.Transparency = 0
			end
		end
	end
end

function UIKit.corner(obj: GuiObject, scale: number): UICorner
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = obj
	return c
end

function UIKit.stroke(obj: GuiObject, color: Color3, thickness: number, contextual: boolean?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.ApplyStrokeMode = if contextual then Enum.ApplyStrokeMode.Contextual else Enum.ApplyStrokeMode.Border
	s.Parent = obj
	return s
end

-- the size without the ancestors' UIScale (the book opens from scale 0.7 - the px layout must be computed from the final size)
function UIKit.unscaled(o: GuiObject): Vector2
	local k = 1
	local p: Instance? = o
	while p do
		local sc = p:FindFirstChildOfClass("UIScale")
		if sc and sc.Scale > 0 then
			k *= sc.Scale
		end
		p = p.Parent
		if p and p:IsA("LayerCollector") then
			break
		end
	end
	return o.AbsoluteSize / k
end

-- a label: the book font, a dark outline, scaled to the frame
function UIKit.text(parent: Instance, text: string, color: Color3?, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = UIKit.FONT
	t.TextScaled = true
	t.TextColor3 = color or Color3.new(1, 1, 1)
	t.Text = text
	local s = Instance.new("UIStroke")
	s.Color = UIKit.STROKE
	s.Thickness = 2
	s.Parent = t
	for k, v in props or {} do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

-- an emoji icon (no outline: an emoji has its own picture)
function UIKit.iconText(parent: Instance, glyph: string, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = "Icon"
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = glyph
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props or {} do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

-- a golden label with a gradient (logo, headers)
function UIKit.goldText(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = UIKit.text(parent, text, Color3.new(1, 1, 1), props)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 170)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(246, 196, 86)), ColorSequenceKeypoint.new(1, Color3.fromRGB(196, 128, 36)) })
	g.Parent = t
	local s = t:FindFirstChildOfClass("UIStroke")
	if s then
		s.Thickness = 3
	end
	return t
end

local function press(b: GuiObject)
	local sc = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	sc.Parent = b
	sc.Scale = 0.9
	TweenService:Create(sc, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if UIKit.onPress then
		UIKit.onPress()
	end
end
UIKit.press = press

function UIKit.shake(b: GuiObject)
	if UIKit.onDeny then
		UIKit.onDeny()
	end
	local p0 = b.Position
	task.spawn(function()
		for i = 1, 6 do
			b.Position = p0 + UDim2.fromOffset(if i % 2 == 0 then 6 else -6, 0)
			task.wait(0.03)
		end
		b.Position = p0
	end)
end

-- gloss: a gradient lighter at the top (DA / Ride A Pet / HTTYD), multiplies the background color
function UIKit.gloss(obj: GuiObject, strength: number?): UIGradient
	local k = strength or 0.22
	local g = Instance.new("UIGradient")
	g.Name = "Gloss"
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.48, Color3.new(1 - k * 0.35, 1 - k * 0.35, 1 - k * 0.35)),
		ColorSequenceKeypoint.new(0.52, Color3.new(1 - k * 0.7, 1 - k * 0.7, 1 - k * 0.7)),
		ColorSequenceKeypoint.new(1, Color3.new(1 - k, 1 - k, 1 - k)),
	})
	g.Parent = obj
	return g
end

-- a button: a colored plaque with a word; onClick after the micro-movement. opts.minSize - its own minimum (crosses, toggles)
function UIKit.button(parent: Instance, text: string, color: Color3, onClick: (TextButton) -> (), opts: { minSize: Vector2? }?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = UIKit.FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = text
	UIKit.corner(b, 0.28)
	UIKit.stroke(b, UIKit.STROKE, 3)
	UIKit.stroke(b, UIKit.STROKE, 2, true)
	UIKit.gloss(b)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0.08, 0)
	pad.PaddingRight = UDim.new(0.08, 0)
	pad.Parent = b
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = (opts and opts.minSize) or Vector2.new(70, 44)
	lim.Parent = b
	b.Activated:Connect(function()
		press(b)
		onClick(b)
	end)
	b.Parent = parent
	return b
end

-- a coin icon from primitives (the 🪙 emoji does not render in the Roblox client): a golden disc, a dark rim, an inner
-- ring and a glint; the second argument is kept for call compatibility
function UIKit.coin(parent: Instance, _assetId: number?, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.Name = "Coin"
	f.BackgroundColor3 = Color3.fromRGB(250, 204, 70)
	for k, v in props do
		(f :: any)[k] = v
	end
	UIKit.corner(f, 1)
	UIKit.stroke(f, Color3.fromRGB(128, 84, 18), 2)
	UIKit.gloss(f, 0.3)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = f
	local ring = Instance.new("Frame")
	ring.BackgroundTransparency = 1
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.62, 0.62)
	UIKit.corner(ring, 1)
	UIKit.stroke(ring, Color3.fromRGB(176, 120, 30), 2)
	ring.Parent = f
	local hl = Instance.new("Frame")
	hl.BackgroundColor3 = Color3.fromRGB(255, 244, 200)
	hl.BackgroundTransparency = 0.25
	hl.AnchorPoint = Vector2.new(0.5, 0.5)
	hl.Position = UDim2.fromScale(0.36, 0.3)
	hl.Size = UDim2.fromScale(0.22, 0.16)
	UIKit.corner(hl, 1)
	hl.Parent = f
	f.Parent = parent
	return f
end

-- a golden down arrow as text (a glyph), with a dark outline: one image of "here" (P11)
function UIKit.arrowGlyph(parent: Instance, props: { [string]: any }): TextLabel
	local t = UIKit.text(parent, "\u{25BC}", UIKit.GOLD, props)
	local st = t:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 3
	end
	return t
end

-- a dark pill (currency, the step banner): charcoal, semi-transparent, a thin light frame
function UIKit.pill(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.PANEL
	f.BackgroundTransparency = 0.18
	for k, v in props or {} do
		(f :: any)[k] = v
	end
	UIKit.corner(f, 0.5)
	UIKit.stroke(f, UIKit.BORDER, 2)
	f.Parent = parent
	return f
end

-- a round action button above a world object (DA "circle + word", HTTYD Ride/Talk) with a caption under the circle
function UIKit.roundAction(parent: Instance, word: string, color: Color3, onClick: (TextButton) -> ()): (TextButton, TextLabel)
	local b = Instance.new("TextButton")
	b.Name = "Round"
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.Font = UIKit.FONT
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = word
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.fromScale(0.5, 0)
	b.Size = UDim2.fromScale(0.62, 0.62)
	UIKit.corner(b, 1)
	UIKit.stroke(b, UIKit.STROKE, 3)
	UIKit.stroke(b, UIKit.STROKE, 2, true)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.3, 0)
	pad.PaddingBottom = UDim.new(0.3, 0)
	pad.PaddingLeft = UDim.new(0.12, 0)
	pad.PaddingRight = UDim.new(0.12, 0)
	pad.Parent = b
	UIKit.gloss(b)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = b
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(44, 44)
	lim.Parent = b
	b.Activated:Connect(function()
		press(b)
		onClick(b)
	end)
	b.Parent = parent
	local sub = UIKit.text(parent, "", UIKit.GOLD, { Name = "Sub", Position = UDim2.fromScale(0, 0.66), Size = UDim2.fromScale(1, 0.3) })
	return b, sub
end

-- ---------------------------------------------------------------------------------------------- panels and the book
local function dimmer(gui: ScreenGui, onClose: () -> ()): TextButton
	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Size = UDim2.fromScale(1, 1)
	dim.Activated:Connect(onClose)
	dim.Parent = gui
	return dim
end

-- a cross outside the panel at the top right (HTTYD): orange, 40 px
local function closeButton(panel: Frame, onClose: () -> ()): TextButton
	local x = UIKit.button(panel, "X", UIKit.ORANGE, function()
		onClose()
	end, { minSize = Vector2.new(40, 40) })
	x.Name = "Close"
	-- only a fifth of the cross sticks out above the panel - on the phone the panel top is right at the Roblox bar, and
	-- half of the cross went into it (a touch does not reach there with the top of the finger)
	x.AnchorPoint = Vector2.new(0.5, 0.2)
	x.Position = UDim2.fromScale(1, 0)
	x.Size = UDim2.fromScale(0.075, 0.12)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = x
	x.ZIndex = 5
	return x
end

local function panelFrame(gui: ScreenGui, w: number, h: number, border: Color3?): Frame
	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = UIKit.PANEL
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(w, h)
	UIKit.corner(panel, 0.04)
	UIKit.stroke(panel, border or UIKit.BORDER, 2)
	local inner = Instance.new("UIStroke") -- a dark outer edge behind the light frame
	inner.Color = UIKit.STROKE
	inner.Thickness = 5
	inner.Transparency = 0.35
	inner.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Scale = 0.7
	sc.Parent = panel
	TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	panel.Parent = gui
	return panel
end

-- a panel with a title (card, name window): a dark backing (a tap outside = close), the cross outside. tint - the frame color.
function UIKit.panel(gui: ScreenGui, title: string, w: number, h: number, onClose: () -> (), tint: Color3?): (Frame, Frame)
	dimmer(gui, onClose)
	local panel = panelFrame(gui, w, h, tint)
	UIKit.text(panel, title, UIKit.GOLD, { Name = "Title", Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.8, 0.12), TextXAlignment = Enum.TextXAlignment.Left })
	closeButton(panel, onClose)
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.04, 0.2)
	body.Size = UDim2.fromScale(0.92, 0.76)
	body.Parent = panel
	return panel, body
end

export type Tab = { id: string, word: string, icon: string, color: Color3 }

-- the book window (HTTYD): a row of colored tabs on top (icon + word, the active one brighter and larger), the cross outside, the body under the tabs.
-- onTab(id) is called on a press; setActive(id) highlights. Returns the panel, the body, setActive.
function UIKit.book(gui: ScreenGui, tabs: { Tab }, activeId: string, onTab: (string) -> (), onClose: () -> ()): (Frame, Frame, (string) -> ())
	dimmer(gui, onClose)
	local BK = Config.UI.book
	local small = gui.AbsoluteSize.Y > 0 and gui.AbsoluteSize.Y < (BK.smallBelow or 0)
	local panel = panelFrame(gui, if small then BK.smallWidth else BK.width, if small then BK.smallHeight else BK.height)
	closeButton(panel, onClose)
	local bar = Instance.new("Frame")
	bar.Name = "Tabs"
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 33)
	bar.BackgroundTransparency = 0.2
	bar.Size = UDim2.fromScale(1, BK.tabHeight)
	UIKit.corner(bar, 0.4)
	bar.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0.015, 0)
	layout.SortOrder = Enum.SortOrder.LayoutOrder -- without this the tabs went alphabetically by name (P8: Shop last)
	layout.Parent = bar
	local buttons: { [string]: TextButton } = {}
	for i, tab in tabs do
		local b = Instance.new("TextButton")
		b.Name = "Tab_" .. tab.id
		b.LayoutOrder = i
		b.AutoButtonColor = false
		b.Text = ""
		b.BackgroundColor3 = tab.color
		b.Size = UDim2.fromScale(math.min(0.16, 0.92 / #tabs - 0.015), 0.74) -- the active tab x1.1 ran into the book body; 6 tabs (Gifts) - narrower so the strip does not stick out
		local lim = Instance.new("UISizeConstraint")
		lim.MinSize = Vector2.new(64, 44)
		lim.Parent = b
		UIKit.corner(b, 0.22)
		UIKit.stroke(b, UIKit.STROKE, 3)
		UIKit.gloss(b, 0.3)
		Instance.new("UIScale").Parent = b
		UIKit.iconText(b, tab.icon, { Position = UDim2.fromScale(0.05, 0.04), Size = UDim2.fromScale(0.9, 0.52) })
		UIKit.text(b, tab.word, Color3.new(1, 1, 1), { Name = "Word", Position = UDim2.fromScale(0.04, 0.56), Size = UDim2.fromScale(0.92, 0.4) })
		b.Activated:Connect(function()
			press(b)
			onTab(tab.id)
		end)
		b.Parent = bar
		buttons[tab.id] = b
	end
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromScale(0.03, BK.tabHeight + 0.05)
	body.Size = UDim2.fromScale(0.94, 1 - BK.tabHeight - 0.08)
	body.Parent = panel
	local function setActive(id: string)
		for tid, b in buttons do
			local on = tid == id
			local sc = b:FindFirstChildOfClass("UIScale") :: UIScale
			TweenService:Create(sc, TweenInfo.new(0.15), { Scale = if on then 1.1 else 0.96 }):Play()
			b.BackgroundTransparency = if on then 0 else 0.28
			local w = b:FindFirstChild("Word") :: TextLabel
			w.TextColor3 = if on then Color3.new(1, 1, 1) else Color3.fromRGB(205, 205, 205)
			b.ZIndex = if on then 3 else 2
		end
	end
	setActive(activeId)
	return panel, body, setActive
end

return UIKit
