--!strict
-- Decor with meshes (craft/02 §3-4, 04 §1): the layout from DecorLayout (pure, deterministic), the meshes from ModelLibrary
-- (Kenney Nature Kit, CC0, cut by material), recoloring by part name with the Config.World.palette palette, the height by
-- Config.World.decor.height, on the ground with hills (WorldBuilder.getHills). No collisions, shadows or queries except trunks,
-- rocks and large stones. Built in batches of batch models per frame after the world and the dragons.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Layout = require(Shared:WaitForChild("Core"):WaitForChild("Layout"))
local DecorLayout = require(Shared:WaitForChild("Core"):WaitForChild("DecorLayout"))
local ModelLibrary = require("./ModelLibrary")

local W = Config.World
local D = W.decor
local P = W.palette

local Decor = {}
local services: { [string]: any } = {}
local stats = { placed = 0, missing = 0, parts = 0, kindsMissing = {} :: { string } }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local GRASS_TOP = rgb(W.colors.grass)

-- C2: rock meshes with granite. The phone draws the terrain as flat color but parts with a texture (devforum 4246362), so all
-- Kenney rocks (rock_*, stone_*, cliff_*) and items with granite get the granite MaterialVariant on the stone parts and grass on
-- the grassy ones; Color = the variant's tint (the _v2 maps are normalized for it).
local VARIANTS: { [string]: { name: string, tint: Color3 } } = {}
if W.materials and W.materials.enabled then
	for _, v in W.materials.variants do
		VARIANTS[v.base] = { name = v.name, tint = rgb(v.tint or { 255, 255, 255 }) }
	end
end
local function isStoneKind(kind: string): boolean
	local k = string.sub(kind, 1, 5)
	return k == "rock_" or k == "stone" or k == "cliff"
end
local function graniteSkin(d: BasePart, partName: string)
	local base = string.gsub(partName, "%d+$", "")
	local isGrass = string.sub(base, 1, 5) == "grass"
	local v = if isGrass then VARIANTS.Grass else VARIANTS.Limestone
	d.Material = if isGrass then Enum.Material.Grass else Enum.Material.Limestone
	if v then
		d.Color = v.tint
		pcall(function()
			(d :: any).MaterialVariant = v.name
		end)
	end
end

-- the part color by the Kenney material name; for rocks and stones "grass" = the terrain grass color, so they blend with the glade
local function colorFor(kind: string, partName: string, tint: number): Color3?
	local base = string.gsub(partName, "%d+$", "")
	if base == "grass" and (string.sub(kind, 1, 5) == "cliff" or string.sub(kind, 1, 4) == "rock") then
		return GRASS_TOP
	end
	if base == "dirt" and string.sub(kind, 1, 4) == "rock" then
		return rgb(W.colors.rock) -- the rock body is gray, not clay (otherwise the glade rocks read as sand lumps)
	end
	local list = P[base]
	if not list then
		return nil
	end
	return rgb(list[(tint % #list) + 1])
end

-- ready PBR models (Poly Haven `ph_*`, Creator Store `cs_*`): the material and SurfaceAppearance are not touched, only the anchor,
-- collisions, shadows and LOD (RenderFidelity Automatic: 6-16k triangles per rock, the phone trims by itself)
local function preparePbr(model: Model, item: DecorLayout.Item)
	local night = D.nightKinds and D.nightKinds[item.kind]
	local emitters, lights = 0, 0
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
			d:Destroy() -- foreign scripts and sounds do not go into the game
		elseif d:IsA("ParticleEmitter") or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") then
			emitters += 1
			if emitters > (D.emittersPerModel or 2) then
				d:Destroy()
			end
		elseif d:IsA("Light") and lights >= (D.lightsPerModel or 99) then
			d:Destroy() -- 1.14: a second fire light at the same point - an extra cost on the phone
		elseif d:IsA("Light") then -- C7: the light of fires/lanterns/crystals without shadows; for nightKinds only at night (DayCycle)
			lights += 1
			d.Shadows = false
			local LM = D.lightMax
			if LM then -- softer, the grass around does not turn yellow
				pcall(function()
					(d :: any).Range = math.min((d :: any).Range, LM.range)
				end)
				d.Brightness = math.min(d.Brightness, LM.brightness)
			end
			if night then
				d.Enabled = false
				CollectionService:AddTag(d, "NightLight")
			end
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CastShadow = item.h >= 4
			-- Poly Haven rocks from 4 studs are always solid
			-- rocks from 2 studs (taller - cannot step over anymore); the ph_fern fern - no
			local rock = string.sub(item.kind, 1, 3) == "ph_" and string.find(item.kind, "rock", 1, true) ~= nil
			local solid = item.collide == true or (rock and item.h >= 2)
			d.CanCollide = solid
			d.CanQuery = solid
			d.CanTouch = false
			if d:IsA("MeshPart") then
				pcall(function()
					(d :: any).RenderFidelity = Enum.RenderFidelity.Automatic
				end)
			end
		end
	end
end

local function prepare(model: Model, item: DecorLayout.Item)
	local pre = string.sub(item.kind, 1, 3)
	if pre == "ph_" or pre == "cs_" then
		preparePbr(model, item)
		return
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			-- the painted foliage cards - only on our own trees (the "leaf" part); for Kenney "leafsGreen/leafsDark" - the palette
			--
			local prefix = string.sub(item.kind, 1, 6)
			local painted = prefix == "ptree_" or prefix == "ctree_" or prefix == "under_" -- our own trees, conifers (C4), undergrowth (C4)
			local isLeaf = painted and string.sub(d.Name, 1, 4) == "leaf"
			d.CastShadow = item.h >= 8 and not isLeaf -- shadows from trunks and rocks; foliage cards without shadows
			d.Material = Enum.Material.SmoothPlastic
			if item.granite or isStoneKind(item.kind) then -- C2: granite on the stone, grass on the caps
				graniteSkin(d, d.Name)
				d.CastShadow = item.h >= 4
			elseif isLeaf then -- P17: the texture stays, a light tint on the copy; the cards are visible from both sides
				local tints = W.decor.leafTint
				d.Color = rgb(tints[(item.tint % #tints) + 1])
				if d:IsA("MeshPart") then
					pcall(function()
						(d :: any).DoubleSided = true
					end)
				end
			elseif painted and string.find(d.Name, "woodBark") then
				local tints = W.decor.barkTint -- a trunk with a bark texture: only a light tint
				d.Color = rgb(tints[(item.tint % #tints) + 1])
			else
				local col = colorFor(item.kind, d.Name, item.tint)
				if col then
					d.Color = col
				end
			end
			-- Kenney rocks have the grassy top as a separate part, solid too
			local solid = item.collide == true and (d.Name:find("wood") ~= nil or d.Name:find("stone") ~= nil or d.Name:find("dirt") ~= nil
				or (isStoneKind(item.kind) and d.Name:find("grass") ~= nil))
			d.CanCollide = solid
			d.CanQuery = solid
			d.CanTouch = false
			if d:IsA("MeshPart") then
				pcall(function()
					(d :: any).RenderFidelity = Enum.RenderFidelity.Performance
				end)
			end
		end
	end
end

-- the model's world frame by part corners (the pivots of foreign models can be rotated: GetBoundingBox gives the size in their axes,
-- for Letaij packs the "height" went into Z); returns minY, maxY, the XZ center and the sizes along X and Z (C7)
local function worldBox(model: Model): (number, number, number, number, number, number)
	local minY, maxY = math.huge, -math.huge
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d.Size / 2
			for sx = -1, 1, 2 do
				for sy = -1, 1, 2 do
					for sz = -1, 1, 2 do
						local c = d.CFrame:PointToWorldSpace(Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
						minY, maxY = math.min(minY, c.Y), math.max(maxY, c.Y)
						minX, maxX = math.min(minX, c.X), math.max(maxX, c.X)
						minZ, maxZ = math.min(minZ, c.Z), math.max(maxZ, c.Z)
					end
				end
			end
		end
	end
	if minY == math.huge then
		return 0, 0, 0, 0, 0, 0
	end
	return minY, maxY, (minX + maxX) / 2, (minZ + maxZ) / 2, maxX - minX, maxZ - minZ
end

-- Creator Store (`cs_*`): a pack (several Models without direct MeshParts) -> one tree by tint; the preview camera goes; the scale and
-- the placement by the world frame, a rotation around the world Y axis on top of the original orientation (the tree keeps standing)
local function pickFromPack(model: Model, tint: number): Model
	local models, directParts = {}, 0
	for _, c in model:GetChildren() do
		if c:IsA("Model") then
			table.insert(models, c)
		elseif c:IsA("BasePart") then
			directParts += 1
		elseif c:IsA("Camera") then
			c:Destroy()
		end
	end
	if #models >= 3 and directParts == 0 then
		local keep = models[(tint % #models) + 1]
		keep.Parent = nil
		model:Destroy()
		return keep
	end
	return model
end

-- C7: a pack of separate parts (RedWood rocks, mushrooms) -> one part by tint
local function pickPart(model: Model, tint: number): Model
	local parts = {}
	for _, c in model:GetChildren() do
		if c:IsA("BasePart") then
			table.insert(parts, c)
		end
	end
	if #parts < 3 then
		return model
	end
	local keep = parts[(tint % #parts) + 1]
	local one = Instance.new("Model")
	keep.Parent = one
	one.PrimaryPart = keep
	model:Destroy()
	return one
end

-- byLength (C7: the pier, the boat, the trail slab): h = the length along the long horizontal axis, yaw = where that axis looks
-- (the cos/sin direction in the XZ plane); top: y = the model top (the pier deck at the water)
local function placeWorld(model: Model, item: DecorLayout.Item, y: number)
	local byLen = D.byLength and D.byLength[item.kind]
	local minY, maxY, _, _, ex, ez = worldBox(model)
	local size = math.max(if byLen then math.max(ex, ez) else maxY - minY, 0.01)
	pcall(function()
		model:ScaleTo(model:GetScale() * item.h / size)
	end)
	local theta = math.rad(item.yaw)
	if byLen then
		local hx, hz = math.cos(theta), math.sin(theta)
		theta = if ex >= ez then math.atan2(-hz, hx) else math.atan2(hx, hz)
	end
	local pv = model:GetPivot()
	model:PivotTo(CFrame.new(pv.Position) * CFrame.Angles(0, theta, 0) * pv.Rotation)
	local bMinY, bMaxY, cx, cz = worldBox(model)
	local dy = if item.top then y - bMaxY else y - bMinY
	model:PivotTo(model:GetPivot() + Vector3.new(item.x - cx, dy, item.z - cz))
end

local function placeOn(model: Model, pos: Vector3)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + (pos - Vector3.new(cf.Position.X, bottom, cf.Position.Z)))
end

function Decor.init(s: { [string]: any })
	services = s
end

function Decor.build()
	local wb = services.WorldBuilder
	local hills = if wb and wb.getHills then wb.getHills() else {}
	local root = Workspace:FindFirstChild("World")
	if not root then
		return
	end
	local old = root:FindFirstChild("Meshes")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Meshes"
	folder.Parent = root
	local assets = Content.Assets.decor
	local t0 = os.clock()
	local byKind: { [string]: Folder } = {}
	local n = 0
	for _, item in DecorLayout.items() do
		if D.solidKinds and table.find(D.solidKinds, item.kind) then
			item.collide = true -- buildings and large Creator Store items are solid (large trees - only the trunk, the trunk rule)
		end
		local id = assets[item.kind] or 0
		local model = if id ~= 0 then ModelLibrary.get(id) else nil
		if not model then
			stats.missing += 1
			if not table.find(stats.kindsMissing, item.kind) then
				table.insert(stats.kindsMissing, item.kind)
			end
			continue
		end
		local m = model :: Model
		local y = if item.y ~= nil then item.y else Layout.terrainHeight(hills, item.x, item.z) - 0.3 -- C2: the full terrain height (beach, plateau, slopes)
		if item.snapDown then -- onto the rock by a ray; a miss - to the post axis; a miss there too - skip
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { folder }
			params.IgnoreWater = true
			local hit = Workspace:Raycast(Vector3.new(item.x, y + 30, item.z), Vector3.new(0, -70, 0), params)
			if not hit and item.ax and item.az then
				hit = Workspace:Raycast(Vector3.new(item.ax, y + 30, item.az), Vector3.new(0, -70, 0), params)
				if hit then
					item = table.clone(item)
					item.x, item.z = item.ax, item.az
				end
			end
			if not hit then
				model:Destroy()
				stats.missing += 1
				continue
			end
			y = hit.Position.Y - 0.6
		end
		if string.sub(item.kind, 1, 3) == "cs_" then -- Creator Store: packs and rotated pivots
			m = pickFromPack(m, item.tint)
			if D.onePart and D.onePart[item.kind] then
				m = pickPart(m, item.tint)
			end
			m.Name = item.kind
			prepare(m, item)
			placeWorld(m, item, y)
			local hr = D.height[item.kind]
			-- a trunk for EVERY tree (58 conifers and birches on the islets, the ridge and the second island had none - pass-through)
			-- not trees: vines and items whose D.height is a length (the pier lost its collision under this rule)
			local tree = hr and hr[1] >= 14 and not (D.byLength and D.byLength[item.kind]) and item.kind ~= "cs_vines"
			if D.trunk and tree then -- a tree - only the trunk is solid (the crown shell caught the player)
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanQuery = false
					end
				end
				local trunk = Instance.new("Part")
				trunk.Name = "TrunkCollider"
				trunk.Size = Vector3.new(D.trunk.size, D.trunk.height, D.trunk.size)
				trunk.CFrame = CFrame.new(item.x, y + D.trunk.height / 2, item.z)
				trunk.Anchored = true
				trunk.Transparency = 1
				trunk.CanQuery = false
				trunk.CanTouch = false
				trunk.CastShadow = false
				trunk.Parent = m
			end
		else
			m.Name = item.kind
			m:ScaleTo(m:GetScale() * item.h)
			prepare(m, item)
			m:PivotTo(CFrame.new(0, 0, 0) * CFrame.Angles(if item.flip then math.pi else 0, math.rad(item.yaw), 0))
			if item.widthTo then -- the island body - a rock stretched to the island width (MeshPart.Size along X/Z)
				local _, sz = m:GetBoundingBox()
				local f = item.widthTo / math.max(sz.X, sz.Z, 0.01)
				local c0 = m:GetPivot().Position
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") then
						local rel = d.Position - c0
						d.Size = Vector3.new(d.Size.X * f, d.Size.Y, d.Size.Z * f)
						d.Position = c0 + Vector3.new(rel.X * f, rel.Y, rel.Z * f)
					end
				end
			end
			if item.top then -- the model top at y (the rock under the grass cap)
				local cf, sz = m:GetBoundingBox()
				m:PivotTo(m:GetPivot() + (Vector3.new(item.x, y, item.z) - Vector3.new(cf.Position.X, cf.Position.Y + sz.Y / 2, cf.Position.Z)))
			else
				placeOn(m, Vector3.new(item.x, y, item.z))
			end
			if item.collide and D.trunk and string.sub(item.kind, 1, 6) == "ctree_" then -- our own conifers (one mesh of cards) - a solid invisible trunk
				local trunk = Instance.new("Part")
				trunk.Name = "TrunkCollider"
				trunk.Size = Vector3.new(D.trunk.size, D.trunk.height, D.trunk.size)
				trunk.CFrame = CFrame.new(item.x, y + D.trunk.height / 2, item.z)
				trunk.Anchored = true
				trunk.Transparency = 1
				trunk.CanQuery = false
				trunk.CanTouch = false
				trunk.CastShadow = false
				trunk.Parent = m
			end
		end
		local kf = byKind[item.kind]
		if not kf then
			kf = Instance.new("Folder")
			kf.Name = item.kind
			kf.Parent = folder
			byKind[item.kind] = kf
		end
		m.Parent = kf
		CollectionService:AddTag(m, "Decor")
		stats.placed += 1
		n += 1
		if n % D.batch == 0 then
			task.wait()
		end
	end
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			stats.parts += 1
		end
	end
	root:SetAttribute("DecorModels", stats.placed)
	root:SetAttribute("DecorParts", stats.parts)
	root:SetAttribute("DecorMissing", stats.missing)
	print(string.format("[Decor] %d models (%d parts) placed, %d missing (%s), %.2f s", stats.placed, stats.parts, stats.missing, table.concat(stats.kindsMissing, ","), os.clock() - t0))
end

function Decor.start()
	if not D.enabled then
		return
	end
	-- decor ids into the library preload
	for _, id in Content.Assets.decor :: { [string]: number } do
		if id ~= 0 then
			task.spawn(ModelLibrary.load, id)
		end
	end
	local ok, err = pcall(Decor.build)
	if not ok then
		warn("[Decor] build failed: " .. tostring(err))
	end
end

function Decor.stats()
	return stats
end

return Decor
