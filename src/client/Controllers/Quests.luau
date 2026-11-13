--!strict
-- the Keeper's quests on the client (spec 06 §1; craft/04 §7.10 series 7 and §7.12: the quest tracker, "Done!").
-- The plaque on the right under Settings: "KEEPER n/15", the title, progress k/n and a bar; a tap - the Quests tab of the book. Notice "quest" -
-- the Done! banner with the reward, a sound, a coin flight. A bubble above Old Ash with the current quest text (up to bubbleDistance studs).
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local QuestsCore = require(Shared:WaitForChild("Core"):WaitForChild("Quests"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Quests = {}

local Q = Config.Quests
local ORANGE = Color3.fromRGB(226, 150, 60)
local banners: any = nil
local coins: any = nil
local menu: any = nil
local gui: ScreenGui? = nil
local catLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local progLabel: TextLabel? = nil
local fill: Frame? = nil
local bubbleText: TextLabel? = nil
-- the Keeper's line - a callout on screen (above his head if there is room, otherwise under the top HUD)
local says: Frame? = nil
local saysTail: TextLabel? = nil
local panelRef: GuiObject? = nil
local keeperPart: BasePart? = nil
local keeperTop = 0 -- the crown above the center of the Keeper's part, studs
local saysRect: { number }? = nil -- where the callout is on screen (viewport) if visible - for Declutter
local warnedSays = false

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

-- 2.9: how many updates are running (the server LiveOps, the ReplicatedStorage.UpdatesLive attribute) - quests 16+ with update 1
local function live(): number
	return (ReplicatedStorage:GetAttribute("UpdatesLive") :: number?) or 0
end

local function state(): QuestsCore.State
	local qd = Store.get("quests")
	if typeof(qd) ~= "table" or typeof(qd.keeper) ~= "table" then
		return { keeper = { step = 1 }, counters = {} }
	end
	return { keeper = { step = qd.keeper.step or 1 }, counters = qd.counters or {} }
end

local function render()
	local st = state()
	local k, n, q = QuestsCore.progress(st, live())
	if catLabel and titleLabel and progLabel and fill then
		if q then
			catLabel.Text = fmt(Strings.Quests.keeperN, { n = st.keeper.step, total = QuestsCore.total(live()) })
			titleLabel.Text = q.title
			-- the count only when there is more than one step
			progLabel.Text = if n > 1 then fmt(Strings.Steps.progress, { k = k, n = n }) else ""
			fill.Size = UDim2.fromScale(math.clamp(k / n, 0, 1), 1)
		else
			catLabel.Text = Strings.Quests.allDone
			titleLabel.Text = Strings.Keeper.moreTales
			progLabel.Text = ""
			fill.Size = UDim2.fromScale(1, 1)
		end
	end
	if bubbleText then
		if QuestsCore.newcomer(Store.all()) then -- a newcomer before the first egg - "Welcome, rider. Pick an egg - any of the three."
			bubbleText.Text = Loc.t(Strings.Keeper.welcome)
		else
			bubbleText.Text = if q then Loc.t(q.text) else Strings.Keeper.moreTales -- {Ember}, {StormDragon} - the name after translation
		end
	end
end

local function build()
	local g = UIKit.screen("Quests", 2)
	local f = Instance.new("TextButton")
	f.Name = "Panel"
	f.AutoButtonColor = false
	f.Text = ""
	f.BackgroundColor3 = UIKit.PANEL
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.fromScale(0.985, Q.panelY)
	f.Size = UDim2.fromScale(0.28, 0.1)
	UIKit.corner(f, 0.18)
	UIKit.stroke(f, UIKit.BORDER, 2)
	UIKit.gloss(f, 0.18)
	local lim = Instance.new("UISizeConstraint")
	lim.MinSize = Vector2.new(130, 46)
	lim.MaxSize = Vector2.new(260, 90)
	lim.Parent = f
	catLabel = UIKit.text(f, "", UIKit.GOLD, { Name = "Cat", Position = UDim2.fromScale(0.05, 0.05), Size = UDim2.fromScale(0.6, 0.3), TextXAlignment = Enum.TextXAlignment.Left })
	progLabel = UIKit.text(f, "", UIKit.CREAM, { Name = "Prog", Position = UDim2.fromScale(0.62, 0.05), Size = UDim2.fromScale(0.33, 0.3), TextXAlignment = Enum.TextXAlignment.Right })
	titleLabel = UIKit.text(f, "", Color3.new(1, 1, 1), { Name = "Title", Position = UDim2.fromScale(0.05, 0.37), Size = UDim2.fromScale(0.9, 0.36), TextXAlignment = Enum.TextXAlignment.Left })
	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.BackgroundColor3 = Color3.fromRGB(28, 24, 26)
	bar.BackgroundTransparency = 1 -- the track is invisible, only the green growth is visible
	bar.BorderSizePixel = 0
	bar.Position = UDim2.fromScale(0.05, 0.8)
	bar.Size = UDim2.fromScale(0.9, 0.12)
	UIKit.corner(bar, 0.5)
	bar.Parent = f
	local fl = Instance.new("Frame")
	fl.Name = "Fill"
	fl.BackgroundColor3 = UIKit.GREEN
	fl.BorderSizePixel = 0
	fl.Size = UDim2.fromScale(0, 1)
	UIKit.corner(fl, 0.5)
	fl.Parent = bar
	fill = fl
	f.Activated:Connect(function()
		Sounds.play("button")
		if menu and menu.open then
			menu.open("quests")
		end
	end)
	f.Parent = g
	UIKit.plain(f) -- Keeper - text with an outline, no plaque
	panelRef = f
	gui = g
	-- the callout of the Keeper's line (add. 2.15): the name and the quest line, the height by the text
	local sp = Instance.new("Frame")
	sp.Name = "KeeperSays"
	sp.BackgroundColor3 = UIKit.PANEL_LIGHT
	sp.BackgroundTransparency = Q.says.back
	sp.Size = UDim2.fromOffset(Q.says.width, 0)
	sp.AutomaticSize = Enum.AutomaticSize.Y
	sp.Visible = false
	UIKit.corner(sp, 0.18)
	UIKit.stroke(sp, UIKit.BORDER, 2)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 7)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = sp
	local lay = Instance.new("UIListLayout")
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Padding = UDim.new(0, 1)
	lay.Parent = sp
	UIKit.text(sp, Strings.Keeper.name, UIKit.GOLD, { Name = "Who", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, Q.says.name), TextXAlignment = Enum.TextXAlignment.Left })
	local line = UIKit.text(sp, "", UIKit.CREAM, { Name = "Line", LayoutOrder = 2, TextScaled = false, TextSize = Q.says.text, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Left })
	local st = line:FindFirstChildOfClass("UIStroke")
	if st then
		st.Thickness = 1
	end
	bubbleText = line
	local tail = UIKit.text(g, "▲", UIKit.PANEL_LIGHT, { Name = "KeeperSaysTail", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(16, 12), Visible = false, TextTransparency = Q.says.back })
	local ts = tail:FindFirstChildOfClass("UIStroke")
	if ts then
		ts.Color = UIKit.BORDER
		ts.Thickness = 1.5
	end
	sp.Parent = g
	says = sp
	saysTail = tail
end

-- the Keeper: the name sign is hidden (the name is in the callout), remember the part and the height for the callout
local function attachBubble(m: Instance)
	if not m:IsA("Model") or (keeperPart ~= nil and keeperPart.Parent ~= nil and keeperPart:IsDescendantOf(m)) then
		return
	end
	local part = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if not part then
		return
	end
	local _, size = m:GetBoundingBox()
	-- the name sign above the Keeper is hidden, the name - as a line in the callout
	for _, d in part:GetChildren() do
		if d:IsA("BillboardGui") then
			for _, t in d:GetChildren() do
				if t:IsA("TextLabel") and t.Text == Strings.Keeper.name then
					d.Enabled = false
				end
			end
		end
	end
	keeperPart = part
	keeperTop = m:GetBoundingBox().Position.Y - part.Position.Y + size.Y * 0.5
	render()
end

-- the bubble in the world above the tall Keeper
-- went under the coins and the step banner whenever it was lowered. The callout on screen: above the head if there is room, otherwise right under the bottom
-- edge of the top HUD; horizontally behind the head, but not under the plaques on the left and not under the Keeper plaque; the tail - onto the head.
local shown = false
local function placeSays()
	local f, tail, part, cam, g = says, saysTail, keeperPart, workspace.CurrentCamera, gui
	saysRect = nil
	if not f or not tail or not g then
		return
	end
	local function hide()
		f.Visible = false
		tail.Visible = false
		shown = false
	end
	if not part or not part.Parent or not cam or not g.Enabled or os.clock() < UIKit.bannerUntil then -- a banner is up - the line waits
		hide()
		return
	end
	local head = part.Position + Vector3.new(0, keeperTop, 0)
	local dist = (cam.CFrame.Position - head).Magnitude
	local v = cam:WorldToViewportPoint(head)
	local vp = cam.ViewportSize
	local w, h = f.AbsoluteSize.X, math.max(f.AbsoluteSize.Y, 30)
	local far = Q.bubbleDistance + (if shown then 3 else 0)
	if dist > far or v.Z <= 0 or v.X < 0 or v.X > vp.X then
		hide()
		return
	end
	local inset = GuiService:GetGuiInset().Y
	local hud = UIKit.hudRects()
	local left, right = 8, vp.X - 8
	for _, r in hud do
		if r[4] - r[2] >= vp.Y * 0.3 and r[3] < vp.X * 0.3 then -- the plaques on the left (a tall column)
			left = math.max(left, r[3] + 8)
		end
	end
	local pr = panelRef
	if pr and pr.Visible then -- the Keeper plaque on the right: the callout does not go under it
		right = math.min(right, pr.AbsolutePosition.X - 8)
	end
	local x = math.clamp(v.X, left + w / 2, math.max(left + w / 2, right - w / 2))
	local floor = inset + 4
	for _, r in hud do
		if r[2] < vp.Y * 0.35 and r[4] - r[2] < vp.Y * 0.3 and x + w / 2 > r[1] and x - w / 2 < r[3] then
			floor = math.max(floor, r[4] + 8)
		end
	end
	local top = math.max(v.Y - h - 14, floor)
	if top + h > vp.Y * 0.78 then -- no room (the screen bottom - action buttons)
		hide()
		return
	end
	local origin = g.AbsolutePosition
	f.Position = UDim2.fromOffset(x - w / 2 - origin.X, top - inset - origin.Y)
	f.Visible = true
	shown = true
	saysRect = { x - w / 2, top, x + w / 2, top + h }
	-- the tail toward the head: above the callout - ▲ on top, under it - ▼ at the bottom, inside - none
	local tx = math.clamp(v.X, x - w / 2 + 16, x + w / 2 - 16)
	if v.Y < top - 4 then
		tail.Text = "▲"
		tail.Position = UDim2.fromOffset(tx - origin.X, top - 5 - inset - origin.Y)
		tail.Visible = true
	elseif v.Y > top + h + 4 then
		tail.Text = "▼"
		tail.Position = UDim2.fromOffset(tx - origin.X, top + h + 5 - inset - origin.Y)
		tail.Visible = true
	else
		tail.Visible = false
	end
end

-- for Declutter: where the callout is on screen (viewport), nil - not visible
function Quests.bubbleRect(): { number }?
	return saysRect
end

local function onDone(p: any)
	local parts = {}
	if typeof(p.coins) == "number" and p.coins > 0 then
		table.insert(parts, fmt(Strings.Quests.rewardCoins, { n = p.coins }))
	end
	if typeof(p.eggZone) == "string" then
		table.insert(parts, fmt(Strings.Quests.rewardEgg, { zone = Loc.t(Strings.Zone[p.eggZone] or p.eggZone) }))
	end
	if banners then
		banners.banner(fmt(Strings.Quests.done, { n = p.step, title = tostring(p.title), total = QuestsCore.total(live()) }), ORANGE, if #parts > 0 then "+ " .. table.concat(parts, " + ") else nil, 2.8)
	end
	Sounds.play("stage_up")
	if coins and typeof(p.coins) == "number" and p.coins > 0 then
		coins.fly(p.coins, nil)
	end
end

function Quests.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	coins = loaded.CoinFlight
	menu = loaded.Menu
end

function Quests.start()
	build()
	render()
	Store.on("quests", render)
	for _, k in { "eggs", "dragons", "onboarding" } do -- the newcomer greeting is replaced by a quest after the first egg
		Store.on(k, render)
	end
	ReplicatedStorage:GetAttributeChangedSignal("UpdatesLive"):Connect(render) -- 2.9: an update switched on - a new quest
	Net.on("quest", onDone)
	for _, m in CollectionService:GetTagged("Keeper") do
		attachBubble(m)
	end
	CollectionService:GetInstanceAddedSignal("Keeper"):Connect(attachBubble)
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(placeSays)
		if not ok and not warnedSays then
			warnedSays = true
			warn("[Quests] says: " .. tostring(err))
		end
	end)
end

return Quests
