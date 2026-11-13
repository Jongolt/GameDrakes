--!strict
-- Spec 02 add. 2.15: world labels
-- (the server's BillboardGuis above the stall, nests, eggs, gates, dragons) are not drawn under the HUD and under the Keeper's bubble - while
-- the label rectangle on screen intersects them (with a margin), the label fades out smoothly; it returns when it is at least
-- clear px away (no flicker at the border). Own labels with buttons (WorldUI) are dimmed only under the HUD, the hint arrow - yes.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack")) -- a menu over a menu is not written to the overlap journal

local Declutter = {}

local D = Config.UI.declutter
local labels: { [BillboardGui]: boolean } = {} -- true - dimmed here
local saved: { [Instance]: { [string]: number } } = {} -- transparency before dimming
local quests: any = nil

local PROPS: { [string]: { string } } = {
	TextLabel = { "TextTransparency", "TextStrokeTransparency", "BackgroundTransparency" },
	TextButton = { "TextTransparency", "TextStrokeTransparency", "BackgroundTransparency" },
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	ImageButton = { "ImageTransparency", "BackgroundTransparency" },
	Frame = { "BackgroundTransparency" },
	UIStroke = { "Transparency" },
}

local function fade(g: BillboardGui, hide: boolean)
	labels[g] = hide
	local info = TweenInfo.new(D.fade)
	for _, d in g:GetDescendants() do
		if d:IsA("GuiButton") then -- a dimmed button does not catch presses
			pcall(function()
				(d :: any).Interactable = not hide
			end)
		end
		local props = PROPS[d.ClassName]
		if not props then
			continue
		end
		if hide then
			local s = saved[d] or {}
			saved[d] = s
			local goal = {}
			for _, p in props do
				if s[p] == nil then
					s[p] = (d :: any)[p]
				end
				goal[p] = 1
			end
			TweenService:Create(d, info, goal):Play()
		else
			local s = saved[d]
			if s then
				saved[d] = nil
				TweenService:Create(d, info, s):Play()
			end
		end
	end
end

-- the label rectangle on screen (viewport): the StudsOffsetWorldSpace offset is in the adornee axes (that is how Roblox draws), StudsOffset - by
-- the camera; size = studs x px per stud + px
local function rectOf(g: BillboardGui, cam: Camera): { number }?
	local a = g.Adornee or g.Parent
	local cf: CFrame
	if a and a:IsA("BasePart") then
		cf = a.CFrame
	elseif a and a:IsA("Attachment") then
		cf = a.WorldCFrame
	elseif a and a:IsA("Model") then
		cf = a:GetPivot()
	else
		return nil
	end
	local pos = cf:PointToWorldSpace(g.StudsOffsetWorldSpace)
	local dist = (cam.CFrame.Position - pos).Magnitude
	-- MaxDistance is not checked: Roblox measures it differently (P8: the nest label is visible farther than computed), and dimming an invisible
	-- label is harmless
	local v = cam:WorldToViewportPoint(pos)
	if v.Z <= 0 then
		return nil
	end
	local pps = cam.ViewportSize.Y / (2 * math.max(dist, 0.5) * math.tan(math.rad(cam.FieldOfView / 2)))
	local w = g.Size.X.Scale * pps + g.Size.X.Offset
	local h = g.Size.Y.Scale * pps + g.Size.Y.Offset
	local x = v.X + g.StudsOffset.X * pps + g.SizeOffset.X * w
	local y = v.Y - g.StudsOffset.Y * pps - g.SizeOffset.Y * h
	return { x - w / 2, y - h / 2, x + w / 2, y + h / 2, dist }
end

-- a label with a visible button (WorldUI: Hatch now) - "button": dimmed only under the HUD; without visible text - does not take part
local function kind(g: BillboardGui): string
	local text = false
	for _, d in g:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible then
			return "button"
		end
		if (d:IsA("TextLabel") and d.Visible and d.Text ~= "") or (d:IsA("ImageLabel") and d.Visible) then
			text = true
		end
	end
	return if text then "label" else "empty"
end

local function overlap(a: { number }, b: { number }, m: number): boolean
	return a[1] - m < b[3] and b[1] < a[3] + m and a[2] - m < b[4] and b[2] < a[4] + m
end

-- rectangles of the label's visible buttons on screen (label canvas -> its rectangle rectOf): we dim by the buttons themselves, not
-- by the backing (P8 day1 H2: the pedestal board backing touched a neighboring label - the Warm button, covered by nothing, was dimmed too)
local function buttonRects(g: BillboardGui, r: { number }): { { number } }
	local out = {}
	local cw, chh = g.AbsoluteSize.X, g.AbsoluteSize.Y
	if cw < 1 or chh < 1 then
		return out
	end
	local sx, sy = (r[3] - r[1]) / cw, (r[4] - r[2]) / chh
	local o = g.AbsolutePosition
	for _, d in g:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 1 and d.AbsoluteSize.Y > 1 then
			local p, z = d.AbsolutePosition - o, d.AbsoluteSize
			table.insert(out, { r[1] + p.X * sx, r[2] + p.Y * sy, r[1] + (p.X + z.X) * sx, r[2] + (p.Y + z.Y) * sy })
		end
	end
	return out
end

-- the share of button a's area under rectangle b
local function coverShare(a: { number }, b: { number }): number
	local w = math.min(a[3], b[3]) - math.max(a[1], b[1])
	local h = math.min(a[4], b[4]) - math.max(a[2], b[2])
	local area = (a[3] - a[1]) * (a[4] - a[2])
	if w <= 0 or h <= 0 or area <= 0 then
		return 0
	end
	return w * h / area
end

-- besides the HUD and the callout - labels among themselves: higher DeclutterRank is placed first (equal -
-- the nearer one); a label running into an already placed one is dimmed. "+N" (rank 0) live for a second - dimmed without return.
local function pass()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local blocks = UIKit.hudRects()
	local br = quests and quests.bubbleRect and quests.bubbleRect()
	if br then
		table.insert(blocks, br)
	end
	local hudBlocks = table.clone(blocks) -- only the HUD and the callout - for labels with buttons
	-- it is an obstacle too
	local pgui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	local tg = pgui and pgui:FindFirstChild("TouchGui")
	local jb = if tg and tg:IsA("ScreenGui") and tg.Enabled then tg:FindFirstChild("JumpButton", true) else nil
	if jb and jb:IsA("GuiObject") and jb.Visible and jb.AbsoluteSize.X > 1 then
		local dy = if (tg :: ScreenGui).IgnoreGuiInset then 0 else GuiService:GetGuiInset().Y
		local jp, jz = jb.AbsolutePosition, jb.AbsoluteSize
		table.insert(hudBlocks, { jp.X, jp.Y + dy, jp.X + jz.X, jp.Y + jz.Y + dy })
	end
	local btnCands = {} -- labels with buttons - the nearer is placed first, the farther one under it is dimmed
	local cands = {}
	-- labels with buttons are obstacles too
	for g in labels do
		if g.Parent and g.Enabled and kind(g) == "button" then
			local r = rectOf(g, cam)
			if r then
				table.insert(blocks, r)
			end
		end
	end
	for g, hidden in labels do
		if not g.Parent then
			labels[g] = nil
			continue
		end
		if not g.Enabled then
			continue
		end
		local k = kind(g)
		if k ~= "label" then
			-- a label with a button under the HUD or under a nearer label with a button is dimmed and not pressable; not compared
			-- with world labels - a button outranks a label
			local r = if k == "button" then rectOf(g, cam) else nil
			local br = if r then buttonRects(g, r) else {}
			if r and #br > 0 then
				table.insert(btnCands, { g = g, r = r, br = br, hidden = hidden })
			elseif hidden then
				fade(g, false)
			end
			continue
		end
		local r = rectOf(g, cam)
		if not r then
			continue
		end
		local m = if hidden then D.clear else D.margin
		local hit = false
		for _, b in blocks do
			if overlap(r, b, m) then
				hit = true
				break
			end
		end
		local rank = g:GetAttribute("DeclutterRank")
		table.insert(cands, { g = g, r = r, hidden = hidden, hit = hit, rank = if typeof(rank) == "number" then rank else 1 })
	end
	table.sort(btnCands, function(a, b)
		return a.r[5] < b.r[5]
	end)
	local btnPlaced = {}
	local share = (Config.Analytics and Config.Analytics.uiOverlap and Config.Analytics.uiOverlap.minShare) or 0.3
	for _, c in btnCands do
		-- a button under a HUD button (the callout) or under the button of a nearer label by a share >= share (with hysteresis: a dimmed one
		-- returns when the share < share / 2)
		local lim = if c.hidden then share / 2 else share
		local hit = false
		for _, b in c.br do
			for _, h in hudBlocks do
				if coverShare(b, h) >= lim then
					hit = true
					break
				end
			end
			if not hit then
				for _, a in btnPlaced do
					if coverShare(b, a) >= lim then
						hit = true
						break
					end
				end
			end
			if hit then
				break
			end
		end
		if not hit then
			for _, b in c.br do
				table.insert(btnPlaced, b)
			end
		end
		if hit ~= c.hidden then
			fade(c.g, hit)
		end
	end
	table.sort(cands, function(a, b)
		if a.rank ~= b.rank then
			return a.rank > b.rank
		end
		return a.r[5] < b.r[5]
	end)
	local placed = {}
	for _, c in cands do
		local hide = c.hit
		if not hide then
			local m = if c.hidden then D.clear else D.margin
			for _, a in placed do
				if overlap(c.r, a, m) then
					hide = true
					break
				end
			end
		end
		if not hide then
			table.insert(placed, c.r)
		end
		if c.rank == 0 then
			if hide and not c.hidden then
				fade(c.g, true)
			end
		elseif hide ~= c.hidden then
			fade(c.g, hide)
		end
	end
end

local function track(d: Instance)
	if d:IsA("BillboardGui") and labels[d] == nil then
		labels[d] = false
	end
end

-- in PlayerGui - only the hint arrow (Hints): under a plaque or a banner it is not visible, and its "80 m" landed on them
local function trackArrow(d: Instance)
	if d:IsA("BillboardGui") and (d.Name == "HintArrow" or d.Name == "WUI") then -- WorldUI labels too (buttons - in kind)
		if d.Name == "HintArrow" and d:GetAttribute("DeclutterRank") == nil then
			d:SetAttribute("DeclutterRank", 3)
		end
		track(d)
	end
end

-- for Studio probes: how many labels are tracked and how many are dimmed
function Declutter.state(): string
	local n, off = 0, 0
	for _, hidden in labels do
		n += 1
		if hidden then
			off += 1
		end
	end
	return string.format("labels=%d hidden=%d", n, off)
end

-- ---------------------------------------------------------------------------------------------- overlap tracking
-- once per every s the visible buttons of the
-- screen (ScreenGui, with ScrollingFrame clipping) and of the world (labels with a button, not dimmed); a pair intersecting longer than hold s - to
-- the server with names (ScreenGui/parent/button), screen and device, each pair once per session. The player sees nothing
local UO = Config.Analytics and Config.Analytics.uiOverlap
local screenButtons: { [GuiButton]: ScreenGui } = {}
local overlapSeen: { [string]: number } = {}
local overlapSent: { [string]: boolean } = {}
local overlapCount = 0

local function trackButton(d: Instance)
	if d:IsA("GuiButton") and not d:FindFirstAncestorWhichIsA("BillboardGui") and not d:FindFirstAncestorWhichIsA("SurfaceGui") then
		local sg = d:FindFirstAncestorWhichIsA("ScreenGui")
		if sg then
			screenButtons[d] = sg
		end
	end
end

local function solid(b: GuiButton): boolean -- invisible press zones do not count
	if b.BackgroundTransparency < 0.95 then
		return true
	end
	if b:IsA("TextButton") and b.Text ~= "" and b.TextTransparency < 0.95 then
		return true
	end
	if b:IsA("ImageButton") and b.Image ~= "" and b.ImageTransparency < 0.95 then
		return true
	end
	return false
end

-- the rectangle of a screen button in viewport coordinates, or nil (hidden, clipped, transparent)
local function screenRect(b: GuiButton, sg: ScreenGui, inset: number): { number }?
	if not sg.Enabled or not b.Visible or not solid(b) then
		return nil
	end
	local p, z = b.AbsolutePosition, b.AbsoluteSize
	if z.X < 8 or z.Y < 8 then
		return nil
	end
	local r = { p.X, p.Y, p.X + z.X, p.Y + z.Y }
	local x: Instance? = b.Parent
	while x and x ~= sg do
		if x:IsA("GuiObject") then
			if not x.Visible then
				return nil
			end
			if x.ClipsDescendants then
				local cp, cz = x.AbsolutePosition, x.AbsoluteSize
				r = { math.max(r[1], cp.X), math.max(r[2], cp.Y), math.min(r[3], cp.X + cz.X), math.min(r[4], cp.Y + cz.Y) }
				if r[3] - r[1] < 4 or r[4] - r[2] < 4 then
					return nil
				end
			end
		end
		x = x.Parent
	end
	if x ~= sg then
		return nil
	end
	local dy = if sg.IgnoreGuiInset then 0 else inset
	return { r[1], r[2] + dy, r[3], r[4] + dy }
end

local function shortName(o: Instance, root: Instance): string
	local parent = o.Parent
	local mid = if parent and parent ~= root then parent.Name .. "/" else ""
	return string.sub(root.Name .. "/" .. mid .. o.Name, 1, 60)
end

local function overlapWatch()
	local cam = workspace.CurrentCamera
	if not cam or overlapCount >= UO.perSession then
		return
	end
	local vp = cam.ViewportSize
	local inset = GuiService:GetGuiInset().Y
	local items: { { r: { number }, name: string, o: Instance } } = {}
	for b, sg in screenButtons do
		if not b.Parent then
			screenButtons[b] = nil
			continue
		end
		local r = screenRect(b, sg, inset)
		if r and (r[3] - r[1]) * (r[4] - r[2]) < UO.bigShare * vp.X * vp.Y then
			table.insert(items, { r = r, name = shortName(b, sg), o = b })
		end
	end
	for g, hidden in labels do
		if not hidden and g.Parent and g.Enabled and kind(g) == "button" then
			local r = rectOf(g, cam)
			if r then -- by the label's own buttons, as Declutter dims
				local a = g.Adornee or g.Parent
				local k = 0
				for _, d in g:GetDescendants() do
					if d:IsA("GuiButton") and d.Visible and d.AbsoluteSize.X > 1 and d.AbsoluteSize.Y > 1 then
						k += 1
						local br = buttonRects(g, r)[k]
						if br then
							table.insert(items, { r = br, name = string.sub("W:" .. (if a then a.Name else "?") .. "/" .. d.Name, 1, 60), o = d })
						end
					end
				end
			end
		end
	end
	local now: { [string]: boolean } = {}
	for i = 1, #items do
		local A1 = items[i]
		for j = i + 1, #items do
			local B1 = items[j]
			if A1.o:IsDescendantOf(B1.o) or B1.o:IsDescendantOf(A1.o) then
				continue
			end
			local w = math.min(A1.r[3], B1.r[3]) - math.max(A1.r[1], B1.r[1])
			local h = math.min(A1.r[4], B1.r[4]) - math.max(A1.r[2], B1.r[2])
			if w <= 0 or h <= 0 then
				continue
			end
			local small = math.min((A1.r[3] - A1.r[1]) * (A1.r[4] - A1.r[2]), (B1.r[3] - B1.r[1]) * (B1.r[4] - B1.r[2]))
			if small <= 0 or w * h / small < UO.minShare then
				continue
			end
			-- a menu over a menu
			-- (two or more in the stack) between different screens is not an overlap
			local sgA = A1.o:FindFirstAncestorWhichIsA("LayerCollector")
			local sgB = B1.o:FindFirstAncestorWhichIsA("LayerCollector")
			if UIStack.depth() >= 2 and sgA ~= sgB and sgA and sgB and sgA:IsA("ScreenGui") and sgB:IsA("ScreenGui") then
				continue
			end
			local key = if A1.name < B1.name then A1.name .. "|" .. B1.name else B1.name .. "|" .. A1.name
			now[key] = true
			overlapSeen[key] = (overlapSeen[key] or 0) + UO.every
			if overlapSeen[key] >= UO.hold and not overlapSent[key] and overlapCount < UO.perSession then
				overlapSent[key] = true
				overlapCount += 1
				local folder = ReplicatedStorage:FindFirstChild("Remotes")
				local rem = folder and folder:FindFirstChild("UiOverlap")
				if rem and rem:IsA("RemoteEvent") then
					local dev = if GuiService:IsTenFootInterface() then "console" elseif UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "touch" else "pc"
					rem:FireServer(A1.name, B1.name, string.format("%dx%d", math.floor(vp.X), math.floor(vp.Y)), dev)
				end
			end
		end
	end
	for k in overlapSeen do
		if not now[k] then
			overlapSeen[k] = nil
		end
	end
end

function Declutter.init(_snapshot: any, loaded: any)
	quests = loaded.Quests
end

function Declutter.start()
	for _, d in workspace:GetDescendants() do
		track(d)
	end
	workspace.DescendantAdded:Connect(track)
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
	for _, d in pg:GetChildren() do
		trackArrow(d)
	end
	pg.ChildAdded:Connect(trackArrow)
	workspace.DescendantRemoving:Connect(function(d)
		if d:IsA("BillboardGui") then
			labels[d] = nil
			for _, c in d:GetDescendants() do
				saved[c] = nil
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(D.tick)
			local ok, err = pcall(pass)
			if not ok then
				warn("[Declutter] " .. tostring(err))
				task.wait(5)
			end
		end
	end)
	if UO and UO.on then
		for _, d in pg:GetDescendants() do
			trackButton(d)
		end
		pg.DescendantAdded:Connect(trackButton)
		task.spawn(function()
			while true do
				task.wait(UO.every)
				local ok, err = pcall(overlapWatch)
				if not ok then
					warn("[Declutter] overlap: " .. tostring(err))
					task.wait(10)
				end
			end
		end)
	end
end

return Declutter
