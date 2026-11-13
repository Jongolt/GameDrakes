--!strict
-- the "Dragon of the Week" stand on the plaza - a live Adult model on a stone stand, a sign
-- (name, rarity, element; the Robux price is written by the client - products have regional prices), a ProximityPrompt View -> the shop (client).
-- The stand exists only while the SKU is on sale (Core/Shop.standSku = Shop.onSale): before the update date and after 7 days it is not in the world;
-- on any check error - absent too (not fail-open). The clock - LiveOps.now/live (in Studio shifted by LiveOpsDebug).
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local ShopCore = require(Core:WaitForChild("Shop"))
local DragonLook = require(Core:WaitForChild("DragonLook"))

local DragonStand = {}
local services: { [string]: any } = {}
local P = Config.World.dragonStand
local T = Strings.World
local stand: Model? = nil
local shownKey: string? = nil

local UI_FONT: Enum.Font = (function() -- the same book font as the world labels (Config.UI.font)
	local ok, f = pcall(function()
		return (Enum.Font :: any)[Config.UI.font]
	end)
	return if ok and typeof(f) == "EnumItem" then f :: Enum.Font else Enum.Font.FredokaOne
end)()

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function line(parent: Instance, name: string, text: any, y: number, h: number, color: Color3): TextLabel -- text: a string or Loc.text
	local t = Instance.new("TextLabel")
	t.Name = name
	t.Size = UDim2.fromScale(1, h)
	t.Position = UDim2.fromScale(0, y)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = UI_FONT
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.fromRGB(40, 30, 30)
	Loc.set(t, "Text", text)
	t.Parent = parent
	return t
end

local function clear()
	if stand then
		stand:Destroy()
	end
	stand = nil
	shownKey = nil
end

-- the plaza height under the point: a ray only against World and the terrain (not players, dragons or the stand itself)
local function groundY(x: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local world = Workspace:FindFirstChild("World")
	params.FilterDescendantsInstances = if world then { world, Workspace.Terrain } else { Workspace.Terrain }
	params.IgnoreWater = true
	local hit = Workspace:Raycast(Vector3.new(x, 120, z), Vector3.new(0, -200, 0), params)
	return if hit then hit.Position.Y else Config.World.stall.y
end

local function build(sku: any)
	local m = Instance.new("Model")
	m.Name = "DragonStand"
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- the stand, the sign and the prompt reach the client together
	m:SetAttribute("Sku", sku.key)
	local gy = groundY(P.x, P.z)
	local base = Instance.new("Part")
	base.Name = "StandBase"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(P.height, P.radius * 2, P.radius * 2) -- the cylinder lies along X: a 90 deg rotation makes it a slab
	base.CFrame = CFrame.new(P.x, gy + P.height / 2, P.z) * CFrame.Angles(0, 0, math.rad(90))
	base.Anchored = true
	base.Material = Enum.Material.Slate
	base.Color = Color3.fromRGB(128, 120, 112)
	base.Parent = m
	local rec = { uid = "stand_week" .. tostring(sku.week), element = sku.element, rarity = sku.rarity, stage = 2,
		name = sku.dragonName, preset = sku.preset }
	local d = services.DragonVisuals.build(rec, false)
	d:SetAttribute("Stand", true) -- not a player's dragon: no OwnerId, outside the nests
	local top = gy + P.height
	local at = Vector3.new(P.x, top + 5, P.z)
	d:PivotTo(CFrame.lookAt(at, Vector3.new(P.faceX, at.Y, P.faceZ)))
	local cf, size = d:GetBoundingBox()
	d:PivotTo(d:GetPivot() + Vector3.new(0, top - (cf.Position.Y - size.Y / 2), 0))
	d.Parent = m
	cf, size = d:GetBoundingBox()
	-- the sign above the dragon: the title, the name in the rarity color, "Epic Ember", the price line (empty - the client writes it)
	local anchor = Instance.new("Part")
	anchor.Name = "StandSign"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(P.x, cf.Position.Y + size.Y / 2 + P.labelAbove, P.z)
	anchor.Parent = m
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(190, 96)
	bb.AlwaysOnTop = false
	bb.MaxDistance = P.labelMaxDistance
	line(bb, "Title", T.standTitle, 0, 0.24, Color3.fromRGB(255, 236, 170))
	Loc.raw(line(bb, "Name", sku.dragonName, 0.24, 0.32, rgb(DragonLook.rarityColor(sku.rarity)))) -- the name of the dragon of the week
	local el = (Content.Elements :: any)[sku.element]
	line(bb, "Kind", Loc.text("{r} {e}", { r = Loc.text((Strings.Rarity :: any)[sku.rarity] or sku.rarity), e = if el then el.name else sku.element }), 0.56, 0.22, Color3.new(1, 1, 1))
	line(bb, "Price", "", 0.78, 0.22, Color3.fromRGB(255, 236, 170))
	bb.Parent = anchor
	local pr = Instance.new("ProximityPrompt")
	pr.Name = "StandView"
	pr.ActionText = T.standView
	pr.ObjectText = sku.dragonName
	pr.HoldDuration = 0
	pr.MaxActivationDistance = P.promptDistance
	pr.RequiresLineOfSight = false
	pr.Parent = base
	CollectionService:AddTag(m, "DragonStand")
	local world = Workspace:FindFirstChild("World")
	m.Parent = world or Workspace
	stand = m
	shownKey = sku.key
end

function DragonStand.refresh()
	local ok, sku = pcall(function()
		local lo = services.LiveOps
		return ShopCore.standSku(lo.live(), lo.now(), Content.Updates)
	end)
	local key = if ok and sku then (sku :: any).key else nil
	if key == shownKey and (key == nil or (stand ~= nil and stand.Parent ~= nil)) then
		return
	end
	clear()
	if key then
		local ok2, err = pcall(build, sku)
		if not ok2 then
			warn("[DragonStand] build " .. tostring(key) .. ": " .. tostring(err))
			clear()
		end
	elseif not ok then
		warn("[DragonStand] check: " .. tostring(sku))
	end
end

function DragonStand.init(s: { [string]: any })
	services = s
end

function DragonStand.start()
	while true do
		DragonStand.refresh()
		task.wait(Config.LiveOps.pollSeconds)
	end
end

return DragonStand
