--!strict
-- 2.9: live ops on the client (spec 09 §3). The quest scrolls 16-20 "The Great Egg" (the server Services/LiveOps
-- places all five in World/Scrolls, Persistent models): only the scroll of the current quest is visible - it sways, glows, a light pillar and a 📜 icon with
-- the distance over everything (to find it from afar); the rest are hidden locally (transparency, no Read button). The server still
-- checks the step and the distance.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))

local LiveOps = {}

local me = Players.LocalPlayer
local folder: Instance? = nil
local shown: BasePart? = nil
local tag: BillboardGui? = nil
local tagText: TextLabel? = nil
local base: { [BasePart]: CFrame } = {}

local function myStep(): number
	local qd = Store.get("quests")
	return if typeof(qd) == "table" and typeof(qd.keeper) == "table" then qd.keeper.step or 1 else 1
end

local function setVisible(p: BasePart, on: boolean)
	for _, d in p:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = if on then (if d.Name == "Beam" then 0.6 else 0) else 1
		elseif d:IsA("ProximityPrompt") then
			d.Enabled = on
		elseif d:IsA("PointLight") then
			d.Enabled = on
		end
	end
	p.Transparency = if on then 0 else 1
end

local function ensureTag(): (BillboardGui, TextLabel)
	if tag and tagText then
		return tag, tagText
	end
	local g = Instance.new("BillboardGui")
	g.Name = "ScrollTag"
	g.AlwaysOnTop = true
	g.Size = UDim2.fromOffset(90, 34)
	g.StudsOffset = Vector3.new(0, 3, 0)
	g.MaxDistance = 2000
	g.LightInfluence = 0
	local t = UIKit.text(g, "", Color3.fromRGB(255, 230, 170), { Name = "T", Size = UDim2.fromScale(1, 1) })
	t.TextStrokeTransparency = 0.3
	g.Parent = me:WaitForChild("PlayerGui")
	tag, tagText = g, t
	return g, t
end

local function refresh()
	local f = folder
	if not f then
		return
	end
	local live = (ReplicatedStorage:GetAttribute("UpdatesLive") :: number?) or 0
	local step = myStep()
	local want: BasePart? = nil
	for _, m in f:GetChildren() do
		local p = if m:IsA("Model") then m.PrimaryPart else nil
		if p then
			if not base[p] then
				base[p] = p.CFrame
			end
			local on = live >= 1 and m:GetAttribute("Step") == step
			setVisible(p, on)
			if on then
				want = p
			end
		end
	end
	if want ~= shown then
		if shown and base[shown] then
			shown.CFrame = base[shown]
		end
		shown = want
	end
	local g = ensureTag()
	g.Adornee = want
	g.Enabled = want ~= nil and not UIKit.worldUiHidden
end

-- the swaying and rotation of the visible scroll, the distance on the icon
local function animate()
	local p = shown
	local b0 = p and base[p]
	if not p or not b0 or not p.Parent then
		return
	end
	local t = os.clock()
	local cf = b0 * CFrame.new(0, math.sin(t * 2) * 0.35, 0) * CFrame.Angles(0, t * 0.8, 0)
	-- the sticks and the pillar move with the body: the pillar is kept vertical from the ground
	local delta = cf * b0:Inverse()
	for _, d in p:GetChildren() do
		if d:IsA("BasePart") and d.Name ~= "Beam" then
			local key = d :: BasePart
			if not base[key] then
				base[key] = key.CFrame
			end
			key.CFrame = delta * base[key]
		end
	end
	p.CFrame = cf
	local ch = me.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	local _, txt = ensureTag()
	if root then
		txt.Text = string.format("📜 %d", math.floor((root.Position - b0.Position).Magnitude + 0.5))
	end
	if tag then
		tag.Enabled = not UIKit.worldUiHidden
	end
end

function LiveOps.init(_snapshot: any, _loaded: any) end

function LiveOps.start()
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		folder = world and world:WaitForChild("Scrolls", 60)
		local f = folder
		if not f then
			return
		end
		f.ChildAdded:Connect(function()
			task.defer(refresh)
		end)
		refresh()
	end)
	Store.on("quests", refresh)
	ReplicatedStorage:GetAttributeChangedSignal("UpdatesLive"):Connect(refresh)
	local warned = false
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(animate)
		if not ok and not warned then
			warned = true
			warn("[LiveOps] " .. tostring(err))
		end
	end)
end

return LiveOps
