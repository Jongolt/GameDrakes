--!strict
-- The world from Config.World at the server start (04 §1-6, §9-10; 10 §3; task 1.5). The terrain - Terrain (land, beach, water,
-- the northern rock, the Springs channel and pad, the Summit mountain, Frost Isle and the backdrop); the game geometry - Parts (the terrace,
-- the plaza, 6 petals with a fence and a ledge, stairs, rock platforms, the bridge, wind rings, signs, arrows);
-- the Nest / Egg templates in ServerStorage (Nest is cloned onto 6 supports). Decor meshes (04 §1) are placeholders of parts for now.
-- The eggs at the 30 spots are only shown statically here (the element by zone) until EggSpawner (1.7) - pickup does not work yet.
-- Polish 1.5 (craft/04 §7.4-7.8): the glade hills (WriteVoxels), the paths (ReplaceMaterial Grass -> Ground), the stair
-- steps, the plaza pattern, the slab rocks along the edge, the floating islets, the coins on the paths, the visible zone gates, the incubator light.

local CollectionService = game:GetService("CollectionService")
local InsertService = game:GetService("InsertService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UI_FONT: Enum.Font = (function() -- one book font for the interface and the world labels (Config.UI.font)
	local ok, f = pcall(function()
		return (Enum.Font :: any)[Config.UI.font]
	end)
	return if ok and typeof(f) == "EnumItem" then f :: Enum.Font else Enum.Font.FredokaOne
end)()
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Layout = require(Shared:WaitForChild("Core"):WaitForChild("Layout"))
local Island = require(Shared:WaitForChild("Core"):WaitForChild("Island")) -- C2: the terrain height
local DecorLayout = require(Shared:WaitForChild("Core"):WaitForChild("DecorLayout"))
local PlazaShape = require(Shared:WaitForChild("Core"):WaitForChild("PlazaShape")) -- the Old Ash plaza as a mesh
local SpringsShape = require(Shared:WaitForChild("Core"):WaitForChild("SpringsShape")) -- the bath cascade
local IncubatorShape = require(Shared:WaitForChild("Core"):WaitForChild("IncubatorShape")) -- the bowl incubator
local ModelLibrary = require("./ModelLibrary")

local W = Config.World
local C = W.colors

local WorldBuilder = {}
WorldBuilder.root = nil :: Folder?
WorldBuilder.nests = {} :: { Model }
WorldBuilder.eggPoints = {} :: { [string]: BasePart }
WorldBuilder.templates = nil :: Folder?

local partCount = 0
local hills: { Layout.Hill } = {} -- the glade hills (Layout.hills), computed once in init

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function v3(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local STONE = rgb(C.stone)
local STONE_LIGHT = Color3.fromRGB(200, 184, 162)
local PAD = Color3.fromRGB(196, 160, 92) -- straw
local YELLOW = Color3.fromRGB(240, 196, 70)

local function part(props: { [string]: any }, parent: Instance?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate -- SmoothPlastic under Future reflects the sky into white at a grazing angle (the plaza, the steps); Slate is matte
	p.Color = STONE
	for k, v in props do
		(p :: any)[k] = v
	end
	if parent then
		p.Parent = parent
	end
	partCount += 1
	return p
end

local function wedge(props: { [string]: any }, parent: Instance?): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate -- SmoothPlastic under Future reflects the sky into white at a grazing angle (the plaza, the steps); Slate is matte
	p.Color = STONE
	for k, v in props do
		(p :: any)[k] = v
	end
	if parent then
		p.Parent = parent
	end
	partCount += 1
	return p
end

-- a vertical cylinder (the Y axis): the Cylinder shape lies along X, rotated by 90 degrees around Z
local function disc(name: string, center: Vector3, radius: number, height: number, color: Color3, parent: Instance, extra: { [string]: any }?): Part
	local props: { [string]: any } = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, radius * 2, radius * 2),
		CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
	}
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	return part(props, parent)
end

local function noCollide(p: BasePart)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
end

-- text/sub - a string (translated by Roblox by the table) or a Loc.text template (translated by every player's client)
local function setText(lbl: TextLabel, x: any)
	Loc.set(lbl, "Text", x)
end

local function label(parent: Instance, text: any, sub: any, offsetY: number, widthPx: number, maxDist: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(widthPx, if sub then 64 else 40)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = maxDist
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, if sub then 0.58 else 1)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = UI_FONT
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.fromRGB(40, 30, 30)
	t.Parent = bb
	if sub then
		local s = t:Clone() -- before setText(t): the clone must not carry the template and the Loc tag away
		s.Size = UDim2.fromScale(1, 0.42)
		s.Position = UDim2.fromScale(0, 0.58)
		s.TextColor3 = Color3.fromRGB(255, 236, 170)
		setText(s, sub)
		s.Parent = bb
	end
	setText(t, text)
	bb.Parent = parent
	return bb
end

-- a yellow 3D arrow on the ground: a tail 6 x 0.3 x 1.6 + a chevron of two slats (04 §4, 02 §1); looks along dirV
local function arrow(name: string, from: Vector3, dirV: Vector3, parent: Instance)
	if not W.groundArrows then -- the arrows lay under the grass or flickered flush with it; the way is led by the hint chevrons (Hints)
		return
	end
	local d = Vector3.new(dirV.X, 0, dirV.Z)
	if d.Magnitude < 0.01 then
		d = Vector3.zAxis
	end
	d = d.Unit
	local cf = CFrame.lookAt(from, from + d) -- LookVector = -Z = the arrow direction
	local shaft = part({ Name = name, Size = Vector3.new(1.3, 0.2, 5), CFrame = cf * CFrame.new(0, 0.1, -2.5), Color = YELLOW, Material = Enum.Material.SmoothPlastic }, parent)
	noCollide(shaft)
	for _, side in { -1, 1 } do
		local wing = part({ Name = name .. "Head", Size = Vector3.new(1.1, 0.2, 3.4),
			CFrame = cf * CFrame.new(side * 1.1, 0.1, -5.3) * CFrame.Angles(0, side * math.rad(40), 0), Color = YELLOW, Material = Enum.Material.SmoothPlastic }, parent)
		noCollide(wing)
	end
	CollectionService:AddTag(shaft, "PathArrow")
end

-- a lantern (P16): a post, a warm lamp (Neon at night, tag NightLight) and a PointLight tagged NightLight - switched by DayCycle
local function lantern(name: string, pos: Vector3, parent: Instance, height: number?)
	local h = height or 6
	local LT = W.dayCycle.lantern
	-- a torch - a dark post, a bowl, live fire
	-- the PointLight only at night (tag NightLight, DayCycle)
	if LT.torch then
		local post = part({ Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 0.7, 0.7), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(78, 52, 36), Material = Enum.Material.Wood }, parent)
		post.CanCollide = true
		local bowl = part({ Name = name .. "Bowl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 1.5, 1.5), CFrame = CFrame.new(pos + Vector3.new(0, h + 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(60, 50, 44), Material = Enum.Material.Slate }, parent)
		noCollide(bowl)
		local fire = Instance.new("Fire")
		fire.Size = LT.flame
		fire.Heat = 7
		fire.Color = Color3.fromRGB(255, 150, 60)
		fire.SecondaryColor = Color3.fromRGB(255, 220, 120)
		fire.Parent = bowl
		local light = Instance.new("PointLight")
		light.Range = LT.range
		light.Brightness = LT.brightness
		light.Color = rgb(LT.color)
		light.Shadows = false
		light.Enabled = false
		light.Parent = bowl
		CollectionService:AddTag(light, "NightLight")
		return post
	end
	local post = part({ Name = name, Size = Vector3.new(0.5, h, 0.5), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color = Color3.fromRGB(95, 60, 40), Material = Enum.Material.Wood }, parent)
	post.CanCollide = false
	local lamp = part({ Name = name .. "Lamp", Size = Vector3.new(1.1, 1.3, 1.1), CFrame = CFrame.new(pos + Vector3.new(0, h + 0.5, 0)), Color = rgb(LT.color), Material = Enum.Material.SmoothPlastic }, parent)
	noCollide(lamp)
	CollectionService:AddTag(lamp, "NightLight")
	local cap = part({ Name = name .. "Cap", Size = Vector3.new(1.5, 0.3, 1.5), CFrame = CFrame.new(pos + Vector3.new(0, h + 1.3, 0)), Color = Color3.fromRGB(95, 60, 40), Material = Enum.Material.Wood }, parent)
	noCollide(cap)
	local light = Instance.new("PointLight")
	light.Range = LT.range
	light.Brightness = LT.brightness
	light.Color = rgb(LT.color)
	light.Shadows = false
	light.Enabled = false
	light.Parent = lamp
	CollectionService:AddTag(light, "NightLight")
	return post
end

-- ---------------------------------------------------------------------------------------------- terrain
-- every terrain operation is guarded: one unavailable property must not bring the world down (Terrain.Decoration
-- is not available to scripts - set only in the place file)
local terrainErrors = 0
local function tsafe(what: string, f: () -> ())
	local ok, err = pcall(f)
	if not ok then
		terrainErrors += 1
		warn("[WorldBuilder] terrain " .. what .. ": " .. tostring(err))
	end
end

-- C2: Island 2.0 - the terrain in chunks by WriteVoxels by the height of Core/Island (a noisy shore, a beach, hills, a plateau with
-- slopes, the Cliffs ridge, the Summit peak, Springs with a lagoon and a channel). The top layer by Island.material (grass / pebbles / granite /
-- ground), under it 8 studs of the same material (on steep ground - down to the bottom of the neighbors), deeper Limestone; water where the surface is below the water level.
local MAT: { [string]: Enum.Material } = { Grass = Enum.Material.Grass, Sand = Enum.Material.Sand, Limestone = Enum.Material.Limestone, Ground = Enum.Material.Ground, Snow = Enum.Material.Snow, Glacier = Enum.Material.Glacier, LeafyGrass = Enum.Material.LeafyGrass, Salt = Enum.Material.Salt } -- + LeafyGrass (the nest pads); Rock deliberately absent - steep slopes with grass (the phone draws Rock as gray facets)
local function writeIsland()
	local T = Workspace.Terrain
	local I2 = W.island2
	local t0 = os.clock()
	local written, voxels, skipped = 0, 0, 0
	for _, ch in Island.chunks() do
		local nx = math.floor((ch.x2 - ch.x1) / 4 + 0.5)
		local nz = math.floor((ch.z2 - ch.z1) / 4 + 0.5)
		local H: { { number } } = {}
		local WL: { { number? } } = {}
		local hmin, hmax, wlmax = math.huge, -math.huge, -math.huge
		local anyLand = false
		for ix = 0, nx + 1 do
			H[ix], WL[ix] = {}, {}
			local wx = ch.x1 + (ix - 0.5) * 4
			for iz = 0, nz + 1 do
				local wz = ch.z1 + (iz - 0.5) * 4
				local h, wl = Island.height(hills, wx, wz)
				H[ix][iz] = h
				WL[ix][iz] = wl
				if ix >= 1 and ix <= nx and iz >= 1 and iz <= nz then
					if h > I2.beach.seabed + 0.5 then
						anyLand = true
					end
					hmin = math.min(hmin, h)
					hmax = math.max(hmax, h)
					if wl then
						wlmax = math.max(wlmax, wl)
					end
				end
			end
		end
		if not anyLand then
			skipped += 1
			continue
		end
		local ymin = math.floor(math.min(hmin, I2.seaLevel) / 4) * 4 - 4
		local ymax = math.ceil(math.max(hmax, wlmax, I2.seaLevel) / 4) * 4 + 4
		local ny = math.floor((ymax - ymin) / 4 + 0.5)
		local mats: { { { Enum.Material } } }, occ: { { { number } } } = {}, {}
		for ix = 1, nx do
			mats[ix], occ[ix] = {}, {}
			for iy = 1, ny do
				mats[ix][iy], occ[ix][iy] = {}, {}
			end
		end
		for ix = 1, nx do
			local wx = ch.x1 + (ix - 0.5) * 4
			for iz = 1, nz do
				local wz = ch.z1 + (iz - 0.5) * 4
				local h, wl = H[ix][iz], WL[ix][iz]
				local slope = math.max(math.abs(H[ix + 1][iz] - H[ix - 1][iz]), math.abs(H[ix][iz + 1] - H[ix][iz - 1])) / 8
				local top = MAT[Island.material(wx, wz, h, slope, wl)] or Enum.Material.Grass
				-- on a steep slope the neighboring column is 20-30 studs lower
				-- and in the column's side Limestone deeper than 8 studs was exposed (the phone draws it flat gray). The top material goes
				-- down to the lowest neighbor: only it faces outward, Limestone stays inside
				local low = math.min(H[ix - 1][iz], H[ix + 1][iz], H[ix][iz - 1], H[ix][iz + 1], H[ix - 1][iz - 1], H[ix + 1][iz + 1], H[ix - 1][iz + 1], H[ix + 1][iz - 1])
				local topDepth = math.max(8, h - low + 4)
				for iy = 1, ny do
					local y0 = ymin + (iy - 1) * 4
					local m, o = Enum.Material.Air, 0
					if y0 + 4 <= h then
						m, o = (if h - y0 > topDepth then (if top == Enum.Material.Snow or top == Enum.Material.Glacier then Enum.Material.Glacier else Enum.Material.Limestone) else top), 1
					elseif y0 < h then
						o = (h - y0) / 4
						m = top
						if wl and o < 0.5 and wl > y0 + 4 then
							m, o = Enum.Material.Water, 1
						end
					elseif wl and y0 < wl then
						m, o = Enum.Material.Water, math.min(1, (wl - y0) / 4)
					end
					mats[ix][iy][iz] = m
					occ[ix][iy][iz] = o
				end
			end
		end
		local region = Region3.new(Vector3.new(ch.x1, ymin, ch.z1), Vector3.new(ch.x2, ymax, ch.z2)):ExpandToGrid(4)
		local ok, err = pcall(function()
			T:WriteVoxels(region, 4, mats, occ)
		end)
		if ok then
			written += 1
			voxels += nx * ny * nz
		else
			terrainErrors += 1
			warn("[WorldBuilder] island chunk " .. ch.x1 .. "," .. ch.z1 .. ": " .. tostring(err))
		end
	end
	print(string.format("[WorldBuilder] island: %d chunks written, %d skipped (sea), %d voxels, %.2f s", written, skipped, voxels, os.clock() - t0))
end

local function buildTerrain()
	local T = Workspace.Terrain
	tsafe("clear", function() T:Clear() end)
	tsafe("water props", function()
		T.WaterColor = rgb(C.water)
		T.WaterTransparency = W.waterTransparency
		T.WaterWaveSize = W.waterWave
		T.WaterWaveSpeed = W.waterWaveSpeed or 8
	end)
	tsafe("water reflectance", function() T.WaterReflectance = W.waterReflectance or 0.2 end) -- C1: 0.3 (spec 04 addendum 2.0)
	-- C1: own terrain MaterialVariants (build.py puts them into the file's MaterialService and writes <Base>Name; here a repeat under pcall,
	-- so the override holds even if the file lost it). The material color under the variant - the tint from Config.
	local variantTint: { [string]: Color3 } = {}
	local MAT = W.materials
	if MAT and MAT.enabled then
		local MaterialService = game:GetService("MaterialService")
		for _, v in MAT.variants do
			local base = (Enum.Material :: any)[v.base]
			if base and MaterialService:FindFirstChild(v.name) then
				tsafe("material override " .. v.name, function()
					(MaterialService :: any):SetBaseMaterialOverride(base, v.name)
				end)
				variantTint[v.base] = rgb(v.tint or { 255, 255, 255 })
			end
		end
	end
	tsafe("material colors", function()
		T:SetMaterialColor(Enum.Material.Grass, variantTint.Grass or rgb(C.grass))
		T:SetMaterialColor(Enum.Material.Sand, variantTint.Sand or rgb(C.sand))
		T:SetMaterialColor(Enum.Material.Rock, variantTint.Rock or rgb(C.rock)) -- the color from Config (lightened: a dark rock reads as black)
		T:SetMaterialColor(Enum.Material.Limestone, variantTint.Limestone or Color3.fromRGB(186, 172, 150))
		T:SetMaterialColor(Enum.Material.Ground, variantTint.Ground or Color3.fromRGB(190, 160, 120))
		T:SetMaterialColor(Enum.Material.LeafyGrass, variantTint.LeafyGrass or Color3.fromRGB(104, 148, 72)) -- C1: under realistic light and the olive glade 78,182,66 screamed; the patches darker and duller
		T:SetMaterialColor(Enum.Material.Snow, Color3.fromRGB(235, 242, 250))
		local AP = W.springsMesh and W.springsMesh.apron
		if AP and AP.salt then -- travertine around the Springs baths - Salt terrain
			T:SetMaterialColor(Enum.Material.Salt, rgb(AP.salt))
		end
		T:SetMaterialColor(Enum.Material.Glacier, Color3.fromRGB(190, 225, 245))
	end)

	-- the sea and the bottom over the whole map (the sea level island2.seaLevel); the land is written on top in chunks by WriteVoxels by Core/Island
	local I2 = W.island2
	local sea = I2.seaLevel
	tsafe("water", function() T:FillBlock(CFrame.new(0, (sea + I2.beach.seabed) / 2, 0), Vector3.new(W.waterSize, sea - I2.beach.seabed, W.waterSize), Enum.Material.Water) end)
	tsafe("seabed", function() T:FillBlock(CFrame.new(0, I2.beach.seabed - 4, 0), Vector3.new(W.waterSize, 8, W.waterSize), Enum.Material.Sand) end)
	-- beyond the terrain water square - 4 strips of "sea" as parts up to seaPlane.size
	-- (no collisions or rays, the water color, a light glint); under the haze they read as an ocean to the horizon, the terrain water stays 6,000
	tsafe("seaPlane", function()
		local SP = W.seaPlane
		if not SP or SP.client then -- the sea to the horizon is built by the client (Controllers/Ocean) - the server strips did not reach the client
			return
		end
		local half = W.waterSize / 2
		local outer = SP.size / 2
		local y = sea - (SP.below or 0.35)
		local f = Instance.new("Folder")
		f.Name = "SeaPlane"
		f.Parent = Workspace
		local strips = {
			{ 0, -(half + outer) / 2, SP.size, outer - half }, -- north (-Z)
			{ 0, (half + outer) / 2, SP.size, outer - half }, -- south
			{ -(half + outer) / 2, 0, outer - half, W.waterSize }, -- west
			{ (half + outer) / 2, 0, outer - half, W.waterSize }, -- east
		}
		for i, st in strips do
			local p = Instance.new("Part")
			p.Name = "Sea" .. i
			p.Anchored = true
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.CastShadow = false
			p.Material = Enum.Material.SmoothPlastic
			p.Color = rgb(SP.color)
			p.Reflectance = SP.reflectance or 0
			p.TopSurface = Enum.SurfaceType.Smooth
			p.Size = Vector3.new(st[3], 1, st[4])
			p.CFrame = CFrame.new(st[1], y - 0.5, st[2])
			p.Parent = f
		end
	end)
	writeIsland()

	-- LeafyGrass patches on the glade: 3-4 terrain materials per frame, like the leaders; occupancy is not touched
	for i, lp in DecorLayout.leafyPatches() do
		tsafe("leafy " .. i, function()
			local region = Region3.new(Vector3.new(lp.x - lp.r, -4, lp.z - lp.r), Vector3.new(lp.x + lp.r, 12, lp.z + lp.r)):ExpandToGrid(4)
			T:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.LeafyGrass)
		end)
	end
	-- the paths (craft/04 §7.4, §7.6): the top grass layer is replaced with ground along a line, the voxel occupancy is not touched
	for _, pa in Layout.paths() do
		tsafe("path " .. pa.zone, function()
			local a, b = v3(pa.from), v3(pa.to)
			local u = (b - a).Unit
			local half0 = W.paths.width / 2
			local t = 0
			while t <= pa.length do
				local c = a + u * t
				local half = half0 * (1 + (W.paths.widthVar or 0) * math.sin((t + (pa.part or 0) * 37) / 19)) -- the width wanders
				local region = Region3.new(Vector3.new(c.X - half, -4, c.Z - half), Vector3.new(c.X + half, 0, c.Z + half)):ExpandToGrid(4)
				T:ReplaceMaterial(region, 4, Enum.Material.Grass, Enum.Material.Ground)
				t += W.paths.step
			end
		end)
	end

	-- Frost Isle (closed) and the backdrop: distant silhouette islands
	-- Frost Isle: since C3 - a zone island as terrain through Island (island2.extra), the old snow block is removed
	tsafe("backdrop", function()
		for i = 1, W.backdropIslands do
			local a = math.rad(70 + (i - 1) * 75)
			local r = (W.backdropRadius or 950) + 40 * ((i - 1) % 3) -- C2: farther, the sea 3,200
			local x, z = math.cos(a) * r, -math.sin(a) * r
			T:FillBall(Vector3.new(x, -20, z), 70 + 10 * (i % 2), Enum.Material.Grass)
			T:FillBall(Vector3.new(x + 10, 10, z), 26, Enum.Material.Rock)
		end
	end)
end

-- ---------------------------------------------------------------------------------------------- the egg template
local eggShellCache: { [string]: Model? } = {}

local function loadEggShell(element: string): Model?
	if eggShellCache[element] ~= nil then
		local m = eggShellCache[element]
		return if m then m:Clone() else nil
	end
	local assetId = Content.Assets.eggs[element]
	if not assetId or assetId == 0 then
		eggShellCache[element] = false :: any
		return nil
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn("[WorldBuilder] egg mesh " .. tostring(assetId) .. " failed: " .. tostring(container))
		eggShellCache[element] = false :: any
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		model = Instance.new("Model")
		for _, c in container:GetChildren() do
			c.Parent = model
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Transparency = 0.12
			if d:IsA("MeshPart") then
				model.PrimaryPart = d
			end
		elseif d:IsA("LuaSourceContainer") then -- ModuleScripts too, like ModelLibrary.load
			d:Destroy()
		end
	end
	model.Parent = nil
	container:Destroy()
	eggShellCache[element] = model
	return model:Clone()
end

-- An element egg ~2.8 studs tall (03 addendum): a glass shell (a mesh or a ball with a SpecialMesh) + a neon core
local function makeEgg(element: string, height: number): Model
	local root = Instance.new("Model")
	root.Name = "Egg"
	local el = Content.Elements[element]
	local color = if el then rgb(el.color) else Color3.fromRGB(255, 240, 200)
	local shell = loadEggShell(element)
	if shell then
		local _, size = shell:GetBoundingBox()
		if size.Y > 0 then
			shell:ScaleTo(shell:GetScale() * height / size.Y)
		end
		shell.Name = "Shell"
		shell.Parent = root
		root.PrimaryPart = shell.PrimaryPart
	else
		local s = part({ Name = "Shell", Shape = Enum.PartType.Ball, Size = Vector3.new(height / 1.3, height / 1.3, height / 1.3),
			Color = color, Material = Enum.Material.Glass, Transparency = 0.12 }, root)
		noCollide(s)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Scale = Vector3.new(1, 1.3, 1)
		mesh.Parent = s
		root.PrimaryPart = s
	end
	local core = part({ Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * (height * 0.55), Material = Enum.Material.Neon,
		Color = color, Transparency = 0.3 }, root)
	noCollide(core)
	root:SetAttribute("Element", element)
	return root
end
WorldBuilder.makeEgg = makeEgg -- 1.7: EggSpawner and Incubation place eggs with the same model
WorldBuilder.lantern = lantern -- 2.4: the nest lantern - the calendar reward, day 5 (Reward)
WorldBuilder.label = label -- the zone label above an island egg is placed by EggSpawner (the placeholder with the label is destroyed when the egg appears)

-- put a model with its sole on a point
local function placeOn(model: Model, pos: Vector3)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + (pos - Vector3.new(cf.Position.X, bottom, cf.Position.Z)))
end

-- ---------------------------------------------------------------------------------------------- the nest template
local function attach(parent: BasePart, name: string, localPos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = name
	a.Position = localPos
	a.Parent = parent
	return a
end

-- an own mesh (tools/*_glb.py) by the node frames from the shape: the size and the center in world studs (the import scale does not matter), the extra turn
-- importYaw (a GLB import rotates every node by 180 degrees around Y). configure(part, kind) - properties
-- by the node kind (the name without the number). nil - a load failure. The model attributes: Parts, Missing, ScaleSpread, ImportScale
local function loadShapeModel(assetId: number, nodes: any, yawDeg: number, name: string, configure: (MeshPart, string) -> ()): Model?
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn("[WorldBuilder] " .. name .. " mesh failed: " .. tostring(container))
		return nil
	end
	local model = Instance.new("Model")
	model.Name = name
	local minK, maxK, parts, missing = math.huge, 0, 0, 0
	for _, d in container:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("MeshPart") then
			local node = nodes[d.Name]
			if not node then
				missing += 1
				continue
			end
			local sz, c = node.s, node.c
			for i, v in { d.Size.X, d.Size.Y, d.Size.Z } do -- the import scale along the three axes: a spread = rotation/distortion
				local k = v / math.max(sz[i], 0.05)
				if sz[i] > 1 then
					minK, maxK = math.min(minK, k), math.max(maxK, k)
				end
			end
			d.Size = Vector3.new(sz[1], sz[2], sz[3])
			d.CFrame = CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(0, math.rad(yawDeg), 0)
			d.Anchored = true
			d.CanTouch = false
			configure(d, (string.gsub(d.Name, "%d+$", "")))
			d.Parent = model
			parts += 1
		end
	end
	container:Destroy()
	if parts == 0 then
		model:Destroy()
		warn("[WorldBuilder] " .. name .. " mesh: no known nodes")
		return nil
	end
	local spread = if maxK > 0 then maxK / minK else 0
	if spread > 1.03 then
		warn(string.format("[WorldBuilder] %s mesh: import scale spread %.3f (rotated or mirrored?)", name, spread))
	end
	model:SetAttribute("Parts", parts)
	model:SetAttribute("Missing", missing)
	model:SetAttribute("ScaleSpread", spread)
	model:SetAttribute("ImportScale", maxK)
	return model
end

-- a stone bowl with straw, an own mesh tools/incubator_glb.py
-- (the nodes Bowl, Straw, Runes by the frames of Core/IncubatorShape from the bottom center on the nest floor). Loaded once, copies - into the nest template.
-- The runes and the rim ring glow at an occupied incubator (setIncubatorLight). nil - a load failure, the old discs stay
local bowlProto: Model? = nil
local bowlTried = false
-- the bowl stop - in the Curtain group, like the Springs water curtain: cannot pass on foot, a rider (Rider) and a dragon (Dragon)
-- pass (otherwise the companion ran into an invisible post and could sit on its top). Rider/Dragon are registered by Movement after the world
local curtainReady = false
local function ensureCurtainGroup()
	if curtainReady then
		return
	end
	curtainReady = true
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Curtain")
	end)
	task.spawn(function()
		for _ = 1, 120 do
			if PhysicsService:IsCollisionGroupRegistered("Rider") and PhysicsService:IsCollisionGroupRegistered("Dragon") then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable("Curtain", "Rider", false)
					PhysicsService:CollisionGroupSetCollidable("Curtain", "Dragon", false)
				end)
				return
			end
			task.wait(0.5)
		end
		warn("[WorldBuilder] bowl wall: Rider/Dragon groups not registered")
	end)
end
local function incubatorBowl(): Model?
	if bowlTried then
		return bowlProto
	end
	bowlTried = true
	local IM = W.incubatorMesh
	if not (IM and IM.enabled and IM.assetId and IM.assetId ~= 0) then
		return nil
	end
	bowlProto = loadShapeModel(IM.assetId, IncubatorShape.nodes, IM.importYaw or 0, "IncubatorBowl", function(d: MeshPart, kind: string)
		d.CanCollide = false -- the stop is an invisible cylinder along the rim (the player does not stand on the bowl)
		d.CanQuery = false -- the camera and dragon touches through the bowl
		d.CastShadow = kind == "Bowl"
		if kind == "Runes" then
			d.Material = Enum.Material.Slate
			d.Color = rgb(IM.runeIdle)
		end
	end)
	if bowlProto then
		bowlProto.WorldPivot = CFrame.new()
	end
	return bowlProto
end

local function buildNestTemplate(): Model
	local L = W.nestLayout
	local n = W.nests
	local nest = Instance.new("Model")
	nest.Name = "NestTemplate"
	-- the invisible support slab = the local coordinate system of the petal (the center, y = the terrace floor)
	local base = part({ Name = "Base", Size = Vector3.new(n.lotWidth, 0.2, n.lotDepth), CFrame = CFrame.new(0, -0.1, 0),
		Transparency = 1 }, nest)
	noCollide(base)
	nest.PrimaryPart = base
	for _, nm in { "Spawn", "CoinPile", "Showcase", "Sign" } do
		local key = string.lower(string.sub(nm, 1, 1)) .. string.sub(nm, 2)
		attach(base, nm, v3((L :: any)[key]))
	end
	for i, p in L.incubators do
		attach(base, "Incubator" .. i, v3(p))
	end
	for i, p in L.shelf do
		attach(base, "Shelf" .. i, v3(p))
	end
	for i, p in L.slots do
		attach(base, "Slot" .. i, v3(p))
	end
	for i, p in L.decor do
		attach(base, "Decor" .. i, v3(p))
	end
	attach(base, "EggTable", v3(L.eggTable))

	-- the fence: a low colored hedge along the perimeter with a gap at the entrance (z = -55)
	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fence.Parent = nest
	local accent = rgb(Content.Elements.ember.color)
	local hw, hd = n.lotWidth / 2, n.lotDepth / 2
	local fh = 2
	local F = W.decor.fence
	local fenceMesh = if W.decor.enabled then ModelLibrary.load(Content.Assets.decor[F.kind] or 0) else nil
	local function fenceLine(a: Vector3, b: Vector3)
		local d = b - a
		local len = d.Magnitude
		local dirV = d.Unit
		local cf = CFrame.lookAt(a, b)
		-- an invisible wall along the line, the Kenney meshes give no collisions
		-- jumped over the fence with the egg - into the pen only through the gap: the wall higher than a jump (nests.wallHeight), the dragon flies higher
		local wh = n.wallHeight or 9
		local wallC = part({ Name = "FenceCollider", Size = Vector3.new(0.8, wh, len), CFrame = CFrame.new((a + b) / 2 + Vector3.new(0, wh / 2, 0)) * cf.Rotation, Transparency = 1 }, fence)
		wallC.CanQuery = false
		wallC.CanTouch = false
		wallC.CastShadow = false
		if fenceMesh then -- P18: a fence of Kenney meshes (the posts in the mesh), a segment ~8 studs wide at a height of 2.8
			local _, sz = fenceMesh:GetBoundingBox()
			local segW = sz.X * F.height
			local n = math.max(1, math.floor(len / segW + 0.5))
			local step = len / n
			for i = 1, n do
				local seg = fenceMesh:Clone()
				seg:ScaleTo(seg:GetScale() * F.height)
				for _, d2 in seg:GetDescendants() do
					if d2:IsA("BasePart") then
						d2.Material = Enum.Material.SmoothPlastic
						d2.Color = if d2.Name:find("Dark") then rgb(F.tintDark) else rgb(F.tint)
						d2.CanCollide = true
						d2.CanQuery = false
						d2.CastShadow = false
					end
				end
				seg.Name = "FenceSeg"
				local center = a + dirV * (step * (i - 0.5))
				-- the mesh lies along X: rotated so that X looks along the line
				seg:PivotTo(CFrame.new(center) * cf.Rotation * CFrame.Angles(0, math.rad(90), 0))
				local cf2, sz2 = seg:GetBoundingBox()
				seg:PivotTo(seg:GetPivot() + Vector3.new(0, -(cf2.Position.Y - sz2.Y / 2), 0))
				seg.Parent = fence
			end
			return
		end
		local n = math.max(1, math.floor(len / 14 + 0.5))
		for i = 0, n do
			local p = a + dirV * (len * i / n)
			local post = part({ Name = "Post", Size = Vector3.new(0.8, 2.6, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 1.3, 0)), Color = Color3.fromRGB(125, 85, 55), Material = Enum.Material.Wood }, fence)
			post.CanCollide = false
		end
		for _, y in { 0.9, 1.9 } do
			local r = part({ Name = "Rail", Size = Vector3.new(0.35, 0.3, len), CFrame = CFrame.new((a + b) / 2 + Vector3.new(0, y, 0)) * cf.Rotation, Color = accent }, fence)
			r.CanCollide = false
		end
	end
	local gap = 12
	fenceLine(Vector3.new(-hw, 0, -hd), Vector3.new(-hw, 0, hd))
	fenceLine(Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd))
	fenceLine(Vector3.new(-hw, 0, -hd), Vector3.new(-gap / 2, 0, -hd))
	fenceLine(Vector3.new(gap / 2, 0, -hd), Vector3.new(hw, 0, -hd))
	lantern("Lantern", Vector3.new(gap / 2 + 2.5, 0, -hd - 1.2), nest, 5.5) -- P16: a lantern at the entrance, opposite the sign
	-- the glide ledge: a railing along the face and the edge (04 §2); the edge is invisible, the Ledge tag stays
	local ledge = part({ Name = "LedgeGlow", Size = Vector3.new(n.lotWidth, 0.4, 0.6), CFrame = CFrame.new(0, 0.2, L.ledgeZ - 0.3),
		Color = Color3.fromRGB(255, 240, 150), Material = Enum.Material.SmoothPlastic, Transparency = 1 }, nest)
	noCollide(ledge)
	CollectionService:AddTag(ledge, "Ledge")
	for _, x in { -hw + 1, hw - 1 } do
		part({ Name = "RailPost", Size = Vector3.new(0.6, 3, 0.6), CFrame = CFrame.new(x, 1.5, L.ledgeZ - 0.3), Color = STONE_LIGHT }, nest)
	end
	-- an updraft right past the ledge - stepped into it, got lifted
	-- with the hatchling on the shoulder then gliding onto the meadow (the slope past the ledge is gentle: from the ledge itself there is no Glide.minHeight)
	local UD = W.updraft.nest
	local up = part({ Name = "LedgeUpdraft", Size = Vector3.new(UD.width, UD.below + UD.above, UD.depth),
		CFrame = CFrame.new(0, (UD.above - UD.below) / 2, L.ledgeZ + UD.gap + UD.depth / 2), Transparency = 0.85,
		Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.ForceField }, nest)
	up.CanCollide = false
	up.CanQuery = false
	up.CanTouch = false
	up.CastShadow = false
	CollectionService:AddTag(up, "Updraft")
	label(up, Strings.World.updraft, Strings.World.updraftSub, (UD.below + UD.above) / 2 + 1.5, 150, UD.labelDistance)
	local wisp = Instance.new("ParticleEmitter") -- rare light wind strokes upward: the stream is visible from afar (ForceField 0.85 is almost transparent)
	wisp.Name = "Wind"
	wisp.Shape = Enum.ParticleEmitterShape.Box
	wisp.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	wisp.EmissionDirection = Enum.NormalId.Top
	wisp.Rate = UD.wisps
	wisp.Lifetime = NumberRange.new(1.2, 2)
	wisp.Speed = NumberRange.new(10, 16)
	wisp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.15) })
	wisp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.45), NumberSequenceKeypoint.new(1, 1) })
	wisp.Color = ColorSequence.new(Color3.fromRGB(225, 242, 255))
	wisp.LightEmission = 0.5
	wisp.Parent = up

	-- the dragon spots: round stands r = 6, the stone color (an empty spot; the contrasting color is set by DragonVisuals)
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = nest
	for i, p in L.slots do
		local pad = disc("SlotPad" .. i, Vector3.new(p[1], 0.15, p[3]), L.slotPadRadius, 0.3, PAD, slots)
		pad.Material = Enum.Material.Fabric -- woven straw
		pad.Transparency = 1 -- the grass is on the floor at 18.0 - the stands are hidden explicitly
		pad.CanCollide = false
		pad:SetAttribute("Slot", i)
		CollectionService:AddTag(pad, "NestSlot")
	end
	-- the incubators: a stone ring, the 2nd and 3rd locked until bought
	local inc = Instance.new("Folder")
	inc.Name = "Incubators"
	inc.Parent = nest
	local IM = W.incubatorMesh
	local bowl = incubatorBowl()
	for i, p in L.incubators do
		local ring = disc("Incubator" .. i, Vector3.new(p[1], 0.3, p[3]), 2.4, 0.6, if i == 1 then Color3.fromRGB(235, 225, 205) else Color3.fromRGB(205, 198, 190), inc)
		ring:SetAttribute("Slot", i)
		ring:SetAttribute("EggLift", 0.3) -- the egg sole above the ring center (Incubation.showEgg): the disc top
		local bowlOk = bowl ~= nil and pcall(function() -- a bowl failure does not bring the world down - the disc stays
			local b = (bowl :: Model):Clone()
			b.Name = "Bowl"
			b:PivotTo(CFrame.new(p[1], p[2], p[3]) * CFrame.Angles(0, math.rad(i * 47), 0))
			b.Parent = ring
			ring.Transparency = 1
			ring.CanCollide = false
			ring:SetAttribute("EggLift", IncubatorShape.eggY - 0.3)
			local wall = disc("BowlWall", Vector3.new(p[1], IM.wallHeight / 2, p[3]), IncubatorShape.rimR, IM.wallHeight, STONE, ring, { Transparency = 1 })
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CastShadow = false
			ensureCurtainGroup()
			wall.CollisionGroup = "Curtain"
			if IM.sparks and IM.sparks > 0 then -- warm sparks above an occupied one (switched by setIncubatorLight); from a thin zone
				-- above the straw (before - from the ring disc at the floor: born in the stone and on the grass beyond the rim)
				local zone = part({ Name = "SparkZone", Size = Vector3.new(IM.sparkZone, 0.2, IM.sparkZone), CFrame = CFrame.new(p[1], IncubatorShape.eggY + 0.35, p[3]),
					Transparency = 1 }, ring)
				noCollide(zone)
				zone.CanQuery = false
				zone.CanTouch = false
				zone.CastShadow = false
				local em = Instance.new("ParticleEmitter")
				em.Name = "WarmSparks"
				em.Enabled = false
				em.Rate = IM.sparks
				em.Lifetime = NumberRange.new(1.2, 2)
				em.Speed = NumberRange.new(0.6, 1.4)
				em.SpreadAngle = Vector2.new(25, 25)
				em.Acceleration = Vector3.new(0, 0.8, 0)
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
				em.Color = ColorSequence.new(rgb(IM.runeWarm), Color3.fromRGB(255, 120, 40))
				em.LightEmission = 1
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
				em.EmissionDirection = Enum.NormalId.Top
				em.Shape = Enum.ParticleEmitterShape.Box
				em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				em.Parent = zone
			end
		end)
		if bowl and not bowlOk then
			warn("[WorldBuilder] incubator bowl " .. i .. " failed, disc kept")
			ring.Transparency = 0
			ring.CanCollide = true
			ring:SetAttribute("EggLift", 0.3)
			for _, nm in { "Bowl", "BowlWall", "SparkZone" } do
				local partial = ring:FindFirstChild(nm)
				if partial then
					partial:Destroy()
				end
			end
		end
		ring:SetAttribute("Locked", i > 1)
		CollectionService:AddTag(ring, "Incubator")
		-- the warm light of an occupied incubator (spec 1.3, 04 addendum): off while there is no egg; switched on by Incubation (1.7)
		local IL = W.incubatorLight
		local light = Instance.new("PointLight")
		light.Name = "WarmLight"
		light.Range = IL.range
		light.Brightness = IL.brightness
		light.Color = rgb(IL.color)
		light.Shadows = false
		light.Enabled = false
		light.Parent = ring
		if i > 1 then
			local lsz = if bowlOk then Vector3.new(IM.lockSize[1], IM.lockSize[2], IM.lockSize[3]) else Vector3.new(4.4, 2.6, 4.4)
			local lock = part({ Name = "Lock", Shape = Enum.PartType.Ball, Size = lsz, CFrame = CFrame.new(p[1], if bowlOk then IncubatorShape.lipY else 1.2, p[3]),
				Color = Color3.fromRGB(120, 125, 140), Transparency = 0.55 }, inc) -- the dome lid until bought (on the bowl rim)
			noCollide(lock)
			lock:SetAttribute("Slot", i) -- Incubation hides the dome of an open incubator (a coin purchase, Starter Pack)
			label(lock, Strings.Errors.locked or "Locked", nil, 1.4, 60, 16)
		end
	end
	-- the egg shelf: 5 cups, 4-5 locked
	local shelf = Instance.new("Folder")
	shelf.Name = "Shelf"
	shelf.Parent = nest
	for i, p in L.shelf do
		local cup = disc("Shelf" .. i, Vector3.new(p[1], 0.25, p[3]), 1.7, 0.5, if i <= Config.Balance.shelf.start then STONE_LIGHT else Color3.fromRGB(150, 140, 130), shelf)
		cup.CanCollide = false
		cup:SetAttribute("Slot", i)
		CollectionService:AddTag(cup, "Shelf")
	end
	-- the coin pile (an empty stand for now), the showcase, the newcomer's table
	local pile = disc("CoinPile", Vector3.new(L.coinPile[1], 0.15, L.coinPile[3]), 2.2, 0.3, Color3.fromRGB(240, 200, 90), nest)
	pile.CanCollide = false
	CollectionService:AddTag(pile, "CoinPile")
	local show = disc("Showcase", Vector3.new(L.showcase[1], 1, L.showcase[3]), 4, 2, STONE_LIGHT, nest)
	CollectionService:AddTag(show, "Showcase")
	-- a wooden table on legs, the eggs on the tabletop
	local TH = 2.8
	local tbl = part({ Name = "EggTable", Size = Vector3.new(7.4, 0.5, 3.4), CFrame = CFrame.new(L.eggTable[1], TH - 0.25, L.eggTable[3]), Color = Color3.fromRGB(128, 86, 56), Material = Enum.Material.WoodPlanks }, nest)
	CollectionService:AddTag(tbl, "EggTable")
	for _, lx in { -3.2, 3.2 } do
		for _, lz in { -1.3, 1.3 } do
			part({ Name = "EggTableLeg", Size = Vector3.new(0.45, TH - 0.5, 0.45), CFrame = CFrame.new(L.eggTable[1] + lx, (TH - 0.5) / 2, L.eggTable[3] + lz), Color = Color3.fromRGB(96, 64, 42), Material = Enum.Material.Wood }, nest)
		end
	end
	for i, el in { "ember", "frost", "moss" } do
		local egg = makeEgg(el, 2.2)
		placeOn(egg, Vector3.new(L.eggTable[1] - 2.2 + (i - 1) * 2.2, TH, L.eggTable[3]))
		egg.Name = "TableEgg" .. i
		egg.Parent = tbl
	end
	-- the nest sign at the entrance: a wooden post with a board ("VACANT PLOT" in the world, not in the air);
	-- the owner's caption above the entrance (L.sign, 10 studs) appears with Nest
	local sx, sz = -(gap / 2 + 2.5), -hd - 1.2
	part({ Name = "SignPole", Size = Vector3.new(0.6, 4.2, 0.6), CFrame = CFrame.new(sx, 2.1, sz), Color = Color3.fromRGB(125, 85, 55), Material = Enum.Material.Wood }, nest).CanCollide = false
	local signPost = part({ Name = "SignPost", Size = Vector3.new(6.4, 2.4, 0.5), CFrame = CFrame.new(sx, 4.6, sz), Color = Color3.fromRGB(150, 108, 72), Material = Enum.Material.Wood }, nest) -- wood, not a white plate
	signPost.CanCollide = false
	label(signPost, Strings.World.nestWord, nil, 1.9, 150, 40).Name = "SignGui" -- world labels closer and smaller
	-- the newcomer path arrows: the table -> incubator 1 -> the ledge (02 §1)
	local t, i1 = v3(L.eggTable), v3(L.incubators[1])
	arrow("ArrowToIncubator", Vector3.new((t.X + i1.X) / 2, 0, (t.Z + i1.Z) / 2 - 4), i1 - t, nest)
	arrow("ArrowToLedge", Vector3.new(0, 0, 8), Vector3.zAxis, nest)
	arrow("ArrowToLedge2", Vector3.new(0, 0, 30), Vector3.zAxis, nest)
	return nest
end

-- ---------------------------------------------------------------------------------------------- building the world
-- the plaza rings were a stack of discs
-- with a 0.1 step - on the phone the top of the lower disc fought for depth under the upper one (on P8 more precise, not visible). Now the pattern is rings
-- of ONE height edge to edge (CSG: a cylinder minus the inner one), no hidden layers; the thickness down to plaza.bottom - the terrain under the plaza is lowered
-- (terraceTerrain.plazaSink). CSG failed - one solid disc without a pattern.
local function buildPlaza(tr: Folder)
	local P = W.plaza
	local top = W.terrace.y + 0.5
	local h = top - P.bottom
	local c = Vector3.new(0, top - h / 2, 0)
	local radii = { P.radius }
	for _, r in W.plazaRings do
		table.insert(radii, r)
	end
	local tmp = Instance.new("Folder") -- the subtraction - on parts in Workspace
	tmp.Name = "PlazaCSG"
	tmp.Parent = Workspace
	local made: { BasePart } = {}
	local ok = true
	for i, r in radii do
		local color = if i % 2 == 1 then STONE_LIGHT else STONE
		local name = if i == 1 then "Plaza" else "PlazaRing" .. (i - 1)
		local outer = disc(name, c, r, h, color, tmp)
		local inner = radii[i + 1]
		if inner then
			local cut = disc("Cut", c, inner, h + 2, color, tmp)
			local okS, u = pcall(function()
				return outer:SubtractAsync({ cut })
			end)
			cut:Destroy()
			outer:Destroy()
			if not okS or not u then
				warn("[WorldBuilder] plaza CSG: " .. tostring(u))
				ok = false
				break
			end
			u.Name = name
			u.UsePartColor = true
			u.Color = color
			u.Material = Enum.Material.Slate
			u.Anchored = true
			table.insert(made, u)
		else
			table.insert(made, outer)
		end
	end
	if not ok then
		for _, p in made do
			p:Destroy()
		end
		made = { disc("Plaza", c, P.radius, h, STONE_LIGHT, tmp) }
	end
	for _, p in made do
		p.Parent = tr
	end
	tmp:Destroy()
end

-- an own mesh tools/plaza_glb.py -
-- a clay glade with an uneven outline (36 almost convex pieces: Roblox collisions follow the surface, the Popper camera
-- rests on the clay and does not go under it), a circle of worn slabs around Ash, slab paths to the stairs, 6 rune stones at the nests.
-- The nodes are placed by the frames from Core/PlazaShape (the center and the size in world studs), so the GLB import scale does not matter.
-- The runes by day - dark carving, at night they glow (tag NightGlow, DayCycle). A load failure - false, the old rings are built.
local plazaLift = 0 -- Old Ash stands on the slab circle: this much higher than before (the old plaza - the top at 18.5)

-- an own mesh tools/plaza_glb.py -
-- a clay glade with an uneven outline (36 almost convex pieces: Roblox collisions follow the surface, the Popper camera
-- rests on the clay and does not go under it), a circle of worn slabs around Ash, slab paths to the stairs, 6 rune stones at the nests.
-- The runes by day - dark carving, at night they glow (tag NightGlow, DayCycle). A load failure - false, the old rings are built.
local function buildPlazaMesh(tr: Folder): boolean
	local PM = W.plazaMesh
	if not (PM and PM.enabled and PM.assetId and PM.assetId ~= 0) then
		return false
	end
	local model = loadShapeModel(PM.assetId, PlazaShape.nodes, PM.importYaw or 0, "OldAshPlaza", function(d: MeshPart, kind: string)
		local solid = kind ~= "Rune" and kind ~= "Tufts" -- the runes and the grass tufts in the cracks - no collisions or rays
		d.CanCollide = solid
		d.CanQuery = solid
		d.CastShadow = kind == "Stone" or kind == "Circle" or kind == "Trail"
		pcall(function()
			(d :: any).RenderFidelity = if kind == "Clay" then Enum.RenderFidelity.Precise else Enum.RenderFidelity.Automatic
		end)
		if kind == "Rune" then
			d.Material = Enum.Material.Slate
			d.Color = rgb(PM.runeDay)
			d:SetAttribute("DayColor", rgb(PM.runeDay))
			d:SetAttribute("NightColor", rgb(PM.runeNight))
			d:SetAttribute("DayMaterial", "Slate")
			CollectionService:AddTag(d, "NightGlow")
		elseif (kind == "Clay" or kind == "Trail") and PM.clayTint then
			-- the plaza clay is too pink - a tint over the texture (the mesh Color and SurfaceAppearance.Color)
			local tint = rgb(PM.clayTint)
			d.Color = tint
			for _, sa in d:GetChildren() do
				if sa:IsA("SurfaceAppearance") then
					pcall(function()
						(sa :: any).Color = tint
					end)
				end
			end
		end
	end)
	if not model then
		return false
	end
	model.Parent = tr
	plazaLift = PlazaShape.circleTop - (W.terrace.y + 0.5)
	return true
end

local function buildTerrace(root: Folder)
	local tr = Instance.new("Folder")
	tr.Name = "Terrace"
	tr.Parent = root
	-- the plateau top - the terrain exactly at the terrace y (a slab flush with the grass flickered); the cylinder body is only a support 1.5 below the grass;
	-- the plaza - rings of alternating tone
	local bodyH = W.terrace.y - 1.5
	disc("TerraceBody", Vector3.new(0, bodyH / 2, 0), W.terrace.radius, bodyH, STONE, tr)
	local meshPlaza = buildPlazaMesh(tr)
	if not meshPlaza then
		buildPlaza(tr)
	end
	-- the Keeper's stall (0, 18, -40): a counter, a canopy, a sign
	local st = W.stall
	local counter = part({ Name = "Stall", Size = Vector3.new(8, 3, 3), CFrame = CFrame.new(st.x, st.y + 1.5, st.z), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.Wood }, tr)
	CollectionService:AddTag(counter, "Stall")
	-- they jump onto the counter (the top at 3), the head went through the canopy
	-- at 7 - the canopy at 8.8: one standing on the counter fits under it
	local RH = 8.8
	for _, dx in { -3.6, 3.6 } do
		part({ Name = "StallPost", Size = Vector3.new(0.5, RH, 0.5), CFrame = CFrame.new(st.x + dx, st.y + RH / 2, st.z - 1.2), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.Wood }, tr)
	end
	local roof = part({ Name = "StallRoof", Size = Vector3.new(9.5, 0.5, 5), CFrame = CFrame.new(st.x, st.y + RH, st.z - 0.5) * CFrame.Angles(math.rad(-10), 0, 0),
		Color = Color3.fromRGB(230, 90, 80) }, tr)
	roof.CanCollide = false
	label(counter, Strings.World.stall, Strings.World.stallSub, 12.2, 140, 40) -- above the canopy (otherwise the label is behind the roof)
	lantern("StallLantern", Vector3.new(st.x + 6, st.y, st.z + 2), tr, 7)
	lantern("KeeperLantern", Vector3.new(W.keeper.x - 9, W.keeper.y, W.keeper.z + 8), tr, 7)
	-- the Keeper's stone table (the shared plaza landmark; a newcomer's eggs lie at his nest); with the mesh plaza the landmark is the slab circle
	if not meshPlaza then part({ Name = "KeeperStone", Size = Vector3.new(10, 2, 10), CFrame = CFrame.new(W.keeper.x, W.keeper.y + 1, W.keeper.z + 10), Color = Color3.fromRGB(120, 110, 105), Material = Enum.Material.Slate }, tr) end

	-- the stairs between the petals: a wedge from the terrace edge onto the glade
	for _, s in Layout.stairs() do
		local top, bottom = v3(s.top), v3(s.bottom)
		local mid = (top + bottom) / 2
		local run = (Vector3.new(bottom.X, 0, bottom.Z) - Vector3.new(top.X, 0, top.Z))
		local cf = CFrame.lookAt(mid, mid + run.Unit)
		-- WedgePart: the sloped face looks at -Z with Size (width, height, length); turned so the descent goes outward.
		-- the wedge is invisible and without collisions - a stair marker for the hints; they walk on the steps below
		local w = wedge({ Name = "Stairs" .. s.index, Size = Vector3.new(8, W.terrace.y, run.Magnitude),
			CFrame = cf, Color = STONE_LIGHT, Transparency = 1 }, tr) -- the thin wedge edge along LookVector (outward, onto the glade)
		w.CanCollide = false
		w.CanQuery = false
		w:SetAttribute("Angle", s.angleDeg)
		CollectionService:AddTag(w, "Stairs")
		-- the steps: N blocks from the terrace edge down, each to the ground (reads as stairs, not a ramp)
		local n = W.stairsSteps
		local rise = W.terrace.y / n
		local tread = run.Magnitude / n
		local u = run.Unit
		for k = 1, n - 1 do
			local topY = W.terrace.y - rise * k
			local c = Vector3.new(top.X, 0, top.Z) + u * (tread * (k - 0.5))
			local step = part({ Name = "Step", Size = Vector3.new(8, topY, tread + 0.05), CFrame = CFrame.lookAt(Vector3.new(c.X, topY / 2, c.Z), Vector3.new(c.X, topY / 2, c.Z) + u),
				Color = if k % 2 == 0 then STONE_LIGHT else Color3.fromRGB(190, 172, 150) }, tr)
			step.CanQuery = false
		end
		-- a down arrow at the top of the stairs and an arrow on the glade toward the nearest spot
		arrow("StairsArrow" .. s.index, top + Vector3.new(0, 0.2, 0) - run.Unit * 6, run.Unit, tr)
	end
end

local function buildNests(root: Folder, template: Model)
	local f = Instance.new("Folder")
	f.Name = "Nests"
	f.Parent = root
	for _, pv in Layout.nestPivots() do
		local nest = template:Clone()
		nest.Name = "Nest" .. pv.index
		nest:SetAttribute("NestIndex", pv.index)
		nest:SetAttribute("OwnerId", 0)
		nest:SetAttribute("AngleDeg", pv.angleDeg)
		local cf = CFrame.new(v3(pv.center)) * CFrame.Angles(0, math.rad(pv.yawDeg), 0)
		nest:PivotTo(cf * CFrame.new(0, -0.1, 0)) -- Base lies at -0.1 relative to the floor
		-- Base - the PrimaryPart at y = -0.1 locally; the rest relative to it
		nest.Parent = f
		CollectionService:AddTag(nest, "Nest")
		local gui = nest:FindFirstChild("SignPost") and (nest.SignPost :: Instance):FindFirstChild("SignGui")
		if gui and gui:IsA("BillboardGui") then
			local tl = gui:FindFirstChildWhichIsA("TextLabel")
			if tl then
				Loc.tag(tl, "Text", Strings.World.freeNest, { n = pv.index })
			end
		end
		table.insert(WorldBuilder.nests, nest)
	end
end

-- a cascade of turquoise baths - an own mesh tools/springs_glb.py: 4 travertine
-- bowls down the hillside and a lagoon (the rim in pieces, the white bottom - solid; the water - a part of its own color without collisions: in
-- a bath they walk on the bottom), Beam spillways from the rim into the lower bowl with foam, steam above the upper bowls, water noise at the lagoon
local function buildSpringsMesh(root: Folder): boolean
	local SM = W.springsMesh
	if not (SM and SM.enabled and SM.assetId and SM.assetId ~= 0) then
		return false
	end
	local WC = SM.water
	local model = loadShapeModel(SM.assetId, SpringsShape.nodes, SM.importYaw or 0, "SpringsPools", function(d: MeshPart, kind: string)
		if kind == "GatePillarL" or kind == "GatePillarR" or kind == "GateLintel" or kind == "Step" or string.sub(kind, 1, 6) == "Grotto" then -- the curtain arch, the crossing stones, the grotto
			d.CanCollide = true
			d.CanQuery = true
			d.CastShadow = true
		elseif string.find(kind, "Water$") then
			d.CanCollide = false
			d.CanQuery = false
			d.CastShadow = false
			d.Material = Enum.Material.SmoothPlastic
			d.Color = rgb(if string.sub(kind, 1, 6) == "Lagoon" then WC.low else WC.top)
			d.Transparency = WC.transparency
			d.Reflectance = WC.reflectance
		else
			local floor = string.find(kind, "Floor$") ~= nil
			d.CanCollide = true
			d.CanQuery = true
			d.CastShadow = not floor
			pcall(function()
				(d :: any).RenderFidelity = if floor then Enum.RenderFidelity.Precise else Enum.RenderFidelity.Automatic
			end)
		end
	end)
	if not model then
		return false
	end
	local f = Instance.new("Folder")
	f.Name = "SpringsFx"
	f.Parent = root
	model.Parent = root
	local TEX = (W.islets.waterfall and W.islets.waterfall.textures) or {}
	local CS = SM.cascade or {}
	for i, c in SpringsShape.cascades do
		local top, bottom, dirV = v3(c.top), v3(c.bottom), v3(c.dir)
		local holder = part({ Name = "Cascade" .. i, Size = Vector3.one, CFrame = CFrame.lookAt(top, top + dirV), Transparency = 1 }, f)
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder:SetAttribute("From", c.from)
		local a0 = Instance.new("Attachment")
		a0.Axis = Vector3.new(0, 0, -1)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		a1.WorldPosition = bottom
		-- a white ribbon on white travertine vanished - the spillway water is blue, denser
		-- the lower ribbon is solid turquoise (the smoke texture is almost transparent - invisible on white), on top - running white jets
		for k, spec in { { "Fall", 1, 1.2, 0, 0.22, "" }, { "Core", 0.75, 0.9, 2.4, 0.05, TEX[1] } } do
			local b = Instance.new("Beam")
			b.Name = spec[1]
			b.Attachment0, b.Attachment1 = a0, a1
			b.Width0, b.Width1 = c.width * spec[2], c.width * spec[3]
			b.Color = ColorSequence.new(if k == 1 then Color3.fromRGB(72, 178, 200) else Color3.fromRGB(235, 250, 255))
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec[5]), NumberSequenceKeypoint.new(0.75, spec[5] + 0.2), NumberSequenceKeypoint.new(1, 0.9) })
			b.LightEmission = 0.25
			b.LightInfluence = 0.7
			b.FaceCamera = true
			b.Segments = 12
			b.CurveSize0 = 1.6
			b.CurveSize1 = -0.4
			b.ZOffset = (k - 1) * 0.2
			if spec[6] and spec[6] ~= "" then
				b.Texture = spec[6]
				b.TextureMode = Enum.TextureMode.Wrap
				b.TextureLength = 6
				b.TextureSpeed = spec[4]
			end
			b.Parent = holder
		end
		local foam = Instance.new("ParticleEmitter") -- foam where the spillway falls into the lower bowl
		foam.Texture = "rbxasset://textures/particles/smoke_main.dds"
		foam.Rate = CS.foamRate or 8
		foam.Lifetime = NumberRange.new(0.6, 1.2)
		foam.Speed = NumberRange.new(2, 5)
		foam.SpreadAngle = Vector2.new(70, 70)
		foam.EmissionDirection = Enum.NormalId.Top
		foam.Acceleration = Vector3.new(0, -6, 0)
		foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.2) })
		foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		foam.Color = ColorSequence.new(Color3.fromRGB(245, 252, 252))
		foam.Parent = a1
		local sndId = Content.Sounds and Content.Sounds.waterfall or 0
		if c.to == CS.sound and typeof(sndId) == "number" and sndId > 0 then -- the water noise from one source - at the lagoon
			local snd = Instance.new("Sound")
			snd.Name = "CascadeSound"
			snd.SoundId = "rbxassetid://" .. sndId
			snd.Looped = true
			snd.Volume = 0.35
			snd.RollOffMode = Enum.RollOffMode.InverseTapered
			snd.RollOffMinDistance = 10
			snd.RollOffMaxDistance = 90
			snd.Parent = holder
			snd.Playing = true
		end
	end
	-- the waterfall from the floating islet above the top of the cascade (add. 2.2 item 2 "water from the sky", 2.7): from the islet edge into the upper bowl right
	-- in front of the grotto entrance (add. 2.9: the grotto behind the water) - three ribbons like the island waterfalls, water dust below, noise
	local SI, G = SpringsShape.islet, SpringsShape.grotto
	if SI and G then
		local top = Vector3.new(G.fall[1], SI.y + 0.6, G.fall[3])
		local out = Vector3.new(G.fall[1] - SI.x, 0, G.fall[3] - SI.z).Unit
		local holder = part({ Name = "IsletFall", Size = Vector3.one, CFrame = CFrame.lookAt(top, top + out), Transparency = 1 }, f)
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		local a0 = Instance.new("Attachment")
		a0.Axis = Vector3.new(0, 0, -1)
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		a1.WorldPosition = Vector3.new(G.fall[1], G.fall[2], G.fall[3])
		for k, spec in { { "Fall", 6.5, 8.5, 1.4, 0.2, 0.2, Color3.fromRGB(205, 232, 245), 0 }, { "Core", 3.2, 4.2, 2.1, 0.08, 0.45, Color3.fromRGB(236, 246, 255), 0.3 },
			{ "Veil", 10, 12, 0.9, 0.8, 0.1, Color3.fromRGB(220, 236, 250), -0.3 } } do
			local b = Instance.new("Beam")
			b.Name = spec[1]
			b.Attachment0, b.Attachment1 = a0, a1
			b.Width0, b.Width1 = spec[2], spec[3]
			b.Color = ColorSequence.new(spec[7])
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec[5]), NumberSequenceKeypoint.new(0.85, math.min(spec[5] + 0.15, 0.95)), NumberSequenceKeypoint.new(1, 0.9) })
			b.LightEmission = spec[6]
			b.LightInfluence = 0.7
			b.FaceCamera = true
			b.Segments = 24
			b.CurveSize0 = 3
			b.CurveSize1 = -1
			b.ZOffset = spec[8]
			local tex = TEX[k] or ""
			if tex ~= "" then
				b.Texture = tex
				b.TextureMode = Enum.TextureMode.Wrap
				b.TextureLength = 18
				b.TextureSpeed = spec[4]
			end
			b.Parent = holder
		end
		local mist = Instance.new("ParticleEmitter")
		mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
		mist.Rate = 10
		mist.Lifetime = NumberRange.new(2, 3.5)
		mist.Speed = NumberRange.new(2, 5)
		mist.SpreadAngle = Vector2.new(180, 180)
		mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 11) })
		mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		mist.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
		mist.Parent = a1
		local sndId = Content.Sounds and Content.Sounds.waterfall or 0
		if typeof(sndId) == "number" and sndId > 0 then
			local snd = Instance.new("Sound")
			snd.Name = "IsletFallSound"
			snd.SoundId = "rbxassetid://" .. sndId
			snd.Looped = true
			snd.Volume = 0.45
			snd.RollOffMode = Enum.RollOffMode.InverseTapered
			snd.RollOffMinDistance = 10
			snd.RollOffMaxDistance = 110
			snd.Parent = a1
			snd.Playing = true
		end
	end
	-- night (add. 2.7, the night layer add. 2.2 item 4): turquoise light from the water of every bowl, fireflies above the brook at the crossing -
	-- only at dusk and night (tag NightLight, DayCycle), without shadows
	local NL = SM.night or {}
	for _, b in SpringsShape.basins do
		local src = part({ Name = "Glow_" .. b.name, Size = Vector3.one, CFrame = CFrame.new(b.x, b.water + 1.2, b.z), Transparency = 1 }, f)
		src.CanCollide = false
		src.CanQuery = false
		src.CanTouch = false
		local li = Instance.new("PointLight")
		li.Color = rgb(NL.glow or { 90, 220, 232 })
		li.Range = math.min(NL.range or 18, b.rin[1] * 1.4)
		li.Brightness = NL.brightness or 1.2
		li.Shadows = false
		li.Enabled = false
		li.Parent = src
		CollectionService:AddTag(li, "NightLight")
	end
	local Sp = W.zones.Springs
	local ff = part({ Name = "Fireflies", Size = Vector3.new(30, 6, NL.firefliesLength or 150), CFrame = CFrame.new(Sp.bridge.x, 4, Sp.bridge.z), Transparency = 1 }, f)
	ff.CanCollide = false
	ff.CanQuery = false
	ff.CanTouch = false
	local fe = Instance.new("ParticleEmitter")
	fe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	fe.Shape = Enum.ParticleEmitterShape.Box
	fe.Rate = NL.fireflies or 6
	fe.Lifetime = NumberRange.new(3, 6)
	fe.Speed = NumberRange.new(0.2, 0.9)
	fe.SpreadAngle = Vector2.new(180, 180)
	fe.RotSpeed = NumberRange.new(-40, 40)
	fe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.5, 0.5), NumberSequenceKeypoint.new(1, 0.2) })
	fe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) })
	fe.Color = ColorSequence.new(Color3.fromRGB(255, 238, 140))
	fe.LightEmission = 1
	fe.Enabled = false
	fe.Parent = ff
	CollectionService:AddTag(fe, "NightLight")
	-- steam above the upper bowls (hot springs): slow white puffs from the water surface
	local ST = SM.steam or {}
	for _, b in SpringsShape.basins do
		if table.find(ST.pools or {}, b.name) then
			local r = b.rin[1]
			local src = part({ Name = "Steam_" .. b.name, Size = Vector3.new(r * 1.3, 0.2, r * 1.3), CFrame = CFrame.new(b.x, b.water + 0.3, b.z), Transparency = 1 }, f)
			src.CanCollide = false
			src.CanQuery = false
			src.CanTouch = false
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/smoke_main.dds"
			pe.Shape = Enum.ParticleEmitterShape.Box
			pe.EmissionDirection = Enum.NormalId.Top
			pe.Rate = ST.rate or 4
			pe.Lifetime = NumberRange.new(4, 6.5)
			pe.Speed = NumberRange.new(1.2, 2.6)
			pe.Acceleration = Vector3.new(0.4, 0.5, 0)
			pe.RotSpeed = NumberRange.new(-15, 15)
			pe.Rotation = NumberRange.new(0, 360)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 13) })
			pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.72), NumberSequenceKeypoint.new(1, 1) })
			pe.Color = ColorSequence.new(Color3.fromRGB(246, 249, 250))
			pe.LightInfluence = 0.7
			pe.Parent = src
		end
	end
	return true
end

-- the Springs gate - a "water curtain" in the stone arch of the bath mesh:
-- Beam jets from the lintel to the ground, spray and dust below, water noise; a barrier in the Curtain collision group - cannot pass on foot,
-- a rider (Rider) and a dragon (Dragon) pass; the client (Controllers/Curtain) parts the jets in front of a mounted teen. The tag
-- SpringsCurtain - on the curtain folder. The caption as before (Hot Springs / Ride a Juvenile dragon across)
local function buildSpringsCurtain(z: Folder)
	local GC = W.springsMesh.gate
	local Gs = SpringsShape.gate
	local ground = Layout.terrainHeight(hills, Gs.x, Gs.z)
	local top = Gs.lintelLow - 0.15
	local bottom = math.max(ground, 0) + 0.2
	local f = Instance.new("Folder")
	f.Name = "SpringsCurtain"
	f.Parent = z
	f:SetAttribute("NeedsStage", GC.needsStage)
	f:SetAttribute("Center", Vector3.new(Gs.x, (top + bottom) / 2, Gs.z))
	CollectionService:AddTag(f, "SpringsCurtain")
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Curtain")
	end)
	-- Rider and Dragon are registered by Movement (after the world); they cannot be registered here - its pcall would break on "already exists"
	task.spawn(function()
		for _ = 1, 120 do
			if PhysicsService:IsCollisionGroupRegistered("Rider") and PhysicsService:IsCollisionGroupRegistered("Dragon") then
				pcall(function()
					PhysicsService:CollisionGroupSetCollidable("Curtain", "Rider", false)
					PhysicsService:CollisionGroupSetCollidable("Curtain", "Dragon", false)
				end)
				return
			end
			task.wait(0.5)
		end
		warn("[WorldBuilder] curtain: Rider/Dragon groups not registered")
	end)
	local barrier = part({ Name = "CurtainBarrier", Size = Vector3.new(1.5, top - bottom + 4, Gs.open + 0.6), CFrame = CFrame.new(Gs.x, (top + bottom) / 2, Gs.z), Transparency = 1 }, f)
	barrier.CanQuery = false
	barrier.CanTouch = false
	barrier.CollisionGroup = "Curtain"
	barrier:SetAttribute("NeedsStage", GC.needsStage)
	label(barrier, Strings.World.springsGate, Strings.World.springsGateSub, (top - bottom) / 2 + 4, 200, 120)
	local TEX = (W.islets.waterfall and W.islets.waterfall.textures) or {}
	local n = GC.strips or 3
	local w = Gs.open / n
	for i = 1, n do
		local zz = Gs.z - Gs.open / 2 + w * (i - 0.5)
		local holder = part({ Name = "Strip" .. i, Size = Vector3.one, CFrame = CFrame.new(Gs.x, top, zz), Transparency = 1 }, f)
		holder.CanCollide = false
		holder.CanQuery = false
		holder.CanTouch = false
		holder:SetAttribute("BaseZ", zz)
		local a0 = Instance.new("Attachment")
		a0.Parent = holder
		local a1 = Instance.new("Attachment")
		a1.Parent = holder
		a1.Position = Vector3.new(0, bottom - top, 0)
		for k, spec in { { "Fall", 1.15, 1.3, 1.5, 0.3, TEX[1] }, { "Core", 0.55, 0.7, 2.2, 0.15, TEX[2] } } do
			local b = Instance.new("Beam")
			b.Name = spec[1]
			b.Attachment0, b.Attachment1 = a0, a1
			b.Width0, b.Width1 = w * spec[2], w * spec[3]
			b:SetAttribute("W0", b.Width0)
			b:SetAttribute("W1", b.Width1)
			b.Color = ColorSequence.new(if k == 1 then Color3.fromRGB(210, 236, 240) else Color3.fromRGB(240, 250, 252))
			b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, spec[5]), NumberSequenceKeypoint.new(0.8, spec[5] + 0.15), NumberSequenceKeypoint.new(1, 0.85) })
			b.LightEmission = 0.25
			b.LightInfluence = 0.7
			b.FaceCamera = true
			b.Segments = 10
			b.ZOffset = (k - 1) * 0.2
			if spec[6] and spec[6] ~= "" then
				b.Texture = spec[6]
				b.TextureMode = Enum.TextureMode.Wrap
				b.TextureLength = 7
				b.TextureSpeed = spec[4]
			end
			b.Parent = holder
		end
	end
	-- spray and water dust at the ground across the whole arch width
	local base = part({ Name = "CurtainSplash", Size = Vector3.new(1.5, 0.2, Gs.open), CFrame = CFrame.new(Gs.x, bottom + 0.2, Gs.z), Transparency = 1 }, f)
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/smoke_main.dds"
	sp.Shape = Enum.ParticleEmitterShape.Box
	sp.EmissionDirection = Enum.NormalId.Top
	sp.Rate = 14
	sp.Lifetime = NumberRange.new(0.8, 1.6)
	sp.Speed = NumberRange.new(3, 6)
	sp.SpreadAngle = Vector2.new(40, 40)
	sp.Acceleration = Vector3.new(0, -8, 0)
	sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4.5) })
	sp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	sp.Color = ColorSequence.new(Color3.fromRGB(240, 250, 252))
	sp.Parent = base
	local sndId = Content.Sounds and Content.Sounds.waterfall or 0
	if typeof(sndId) == "number" and sndId > 0 then
		local snd = Instance.new("Sound")
		snd.Name = "CurtainSound"
		snd.SoundId = "rbxassetid://" .. sndId
		snd.Looped = true
		snd.Volume = 0.4
		snd.RollOffMode = Enum.RollOffMode.InverseTapered
		snd.RollOffMinDistance = 8
		snd.RollOffMaxDistance = 80
		snd.Parent = base
		snd.Playing = true
	end
end

local function buildZones(root: Folder)
	local z = Instance.new("Folder")
	z.Name = "Zones"
	z.Parent = root
	tsafe("springs pools", function()
		buildSpringsMesh(z)
	end)
	-- the Cliffs platforms on the rock (y 40/50/60) and the wind stream at the foot
	local cz = W.zones.Cliffs.z
	for _, p in Layout.eggPoints() do
		if p.zone == "Cliffs" then
			local slab = part({ Name = "CliffSlab", Size = Vector3.new(14, 1.2, 12), CFrame = CFrame.new(p.pos[1], p.pos[2] - 0.6, cz + 1), Color = Color3.fromRGB(140, 130, 125), Material = Enum.Material.Slate }, z)
			slab:SetAttribute("PointId", p.id)
		end
	end
	local wind = part({ Name = "CliffsUpdraft", Size = Vector3.new(W.zones.Cliffs.wind.size, 70, W.zones.Cliffs.wind.size), CFrame = CFrame.new(W.zones.Cliffs.wind.x, 35, cz + W.zones.Cliffs.wind.dz), Transparency = 0.85,
		Color = Color3.fromRGB(200, 230, 255), Material = Enum.Material.ForceField }, z)
	wind.CanCollide = false
	wind.CanQuery = false
	CollectionService:AddTag(wind, "Updraft")
	label(wind, Strings.World.updraft, Strings.World.updraftSub, 36, 150, 90)
	local S = W.zones.Springs
	local springsMesh = z:FindFirstChild("SpringsPools") ~= nil
	if springsMesh then
		-- the crossing - stones in the bath mesh; the gate - the water curtain in the arch (buildSpringsCurtain)
		lantern("SpringsLantern", Vector3.new(S.bridge.x + 14, 0, S.bridge.z - 6), z, 6)
		tsafe("springs curtain", function()
			buildSpringsCurtain(z)
		end)
	else
		-- the bridge in Springs across the channel
		local S = W.zones.Springs
		local bridge = part({ Name = "SpringsBridge", Size = Vector3.new(24, 1, 8), CFrame = CFrame.new(S.bridge.x, 0.5, S.bridge.z), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.WoodPlanks }, z)
		CollectionService:AddTag(bridge, "Bridge")
		if S.bridgeModel then -- a rope bridge (DecorLayout c7.bridge) on top, the plank only for walking
			bridge.Transparency = 1
		end
		for _, dz in if S.bridgeModel then {} else { -3.6, 3.6 } do
			local r = part({ Name = "BridgeRail", Size = Vector3.new(24, 1.2, 0.4), CFrame = CFrame.new(S.bridge.x, 1.6, S.bridge.z + dz), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.Wood }, z)
			r.CanCollide = false
		end
		-- the Springs gate: a visible semi-transparent wall in the element color (craft/04 §7.4 item 2) until a teen; removed by Movement (1.9)
		local G = W.gates.springs
		local gate = part({ Name = "SpringsGate", Size = Vector3.new(1, G.height, G.width), CFrame = CFrame.new(S.bridge.x - 13, G.height / 2, S.bridge.z),
			Transparency = G.transparency, Color = rgb(Content.Elements.tide.color), Material = Enum.Material.ForceField }, z) -- a shimmering barrier visible at night too
		gate.CanQuery = false
		gate:SetAttribute("NeedsStage", 1)
		CollectionService:AddTag(gate, "ZoneGate")
		label(gate, Strings.World.springsGate, Strings.World.springsGateSub, G.height / 2 + 6, 200, 120) -- above the runes, the runes cut the caption
		lantern("SpringsLantern", Vector3.new(S.bridge.x + 14, 0, S.bridge.z - 6), z, 6)
		for _, dz in { -G.width / 2, G.width / 2 } do
			local rune = part({ Name = "GateRune", Size = Vector3.new(1.2, G.height + 1, 1.2), CFrame = CFrame.new(S.bridge.x - 13, G.height / 2, S.bridge.z + dz), Color = rgb(Content.Elements.tide.color2), Material = Enum.Material.Neon }, z)
			noCollide(rune)
		end
	end
	-- the Summit platform: a stone disc at the peak and a sign
	local M = W.zones.Summit.center
	if W.mountain.topDisc ~= false then
		disc("SummitTop", Vector3.new(M[1], M[2] - 0.5, M[3]), W.mountain.topRadius, 1, STONE, z)
	end
	-- Frost Isle: an invisible wall with a sign
	-- the wall from y = -60 to 300 (was 0..300): a swimmer at depth passed under it and caught the zone rollback dozens of times per session
	-- a part no longer than 2048 studs (Ocean.luau), the sea W.waterSize = 6000 - the wall in three pieces along Z, otherwise the edges |z| > 1024 are open
	local segZ = W.waterSize / 3
	for i = -1, 1 do
		local wall = part({ Name = "FrostWall", Size = Vector3.new(2, 360, segZ), CFrame = CFrame.new(W.frostIsle.wallX, 120, i * segZ), Transparency = 1 }, z)
		wall.CanQuery = false
		CollectionService:AddTag(wall, "ZoneGate")
	end
	local F = W.gates.frost -- the visible blue band of the wall at the water (craft/04 §7.4 item 2: the zone is visible before you run into it)
	if F.band ~= false then -- the white band on the sea is removed, the boundary - the sign and the invisible wall
		local band = part({ Name = "FrostWallBand", Size = Vector3.new(1, F.height, W.waterSize), CFrame = CFrame.new(W.frostIsle.wallX - 1, F.height / 2, 0),
			Transparency = F.transparency, Color = rgb(Content.Elements.frost.color) }, z)
		noCollide(band)
	end
	-- a post in a rock out of the sea (the rocks - DecorLayout, gates.frost.sign.rocks) and
	-- a board like the zone signs, facing the main island (the island opens in a later update)
	local FS = W.gates.frost.sign
	local sx = W.frostIsle.wallX - FS.back
	part({ Name = "FrostSignPost", Size = Vector3.new(1, FS.postTop - FS.postBottom, 1), CFrame = CFrame.new(sx, (FS.postTop + FS.postBottom) / 2, 0),
		Color = Color3.fromRGB(110, 78, 55), Material = Enum.Material.Wood }, z)
	local fsign = part({ Name = "FrostSign", Size = Vector3.new(FS.boardSize[1], FS.boardSize[2], 0.5), CFrame = CFrame.new(sx - 0.75, FS.boardY, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(245, 235, 215), Material = Enum.Material.Wood }, z)
	do
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = fsign
		local title = Instance.new("TextLabel")
		title.Name = "Title"
		title.Size = UDim2.fromScale(1, 0.5)
		title.Position = UDim2.fromScale(0, 0.06)
		title.BackgroundTransparency = 1
		title.TextScaled = true
		title.Font = UI_FONT
		title.TextColor3 = Color3.fromRGB(60, 45, 40)
		Loc.tag(title, "Text", Strings.World.frostGate)
		title.Parent = gui
		local sub = title:Clone()
		sub.Name = "Sub"
		sub.Size = UDim2.fromScale(0.92, 0.32)
		sub.Position = UDim2.fromScale(0.04, 0.6)
		Loc.tag(sub, "Text", Strings.Social.frostIsle)
		sub.Parent = gui
	end

	-- the zone signs with the odds (04 §4)
	for _, sg in Layout.zoneSigns() do
		local pos = v3(sg.pos) + Vector3.new(0, math.max(0, Layout.terrainHeight(hills, sg.pos[1], sg.pos[3])), 0) -- C2: the sign on the terrain (a slope, a hill)
		local post = part({ Name = "ZoneSign_" .. sg.zone, Size = Vector3.new(0.8, 3.8, 0.8), CFrame = CFrame.new(pos + Vector3.new(0, 1.9, 0)), Color = Color3.fromRGB(150, 100, 70), Material = Enum.Material.Wood }, z)
		post:SetAttribute("Zone", sg.zone)
		CollectionService:AddTag(post, "ZoneSign")
		local odds = Config.Balance.zones[sg.zone]
		local rows = {}
		local words = {} -- the rarity name is translated by the client (the template {r1} 60% ... - not a source, the values are translated)
		for i, name in Config.Rarities do
			if odds[i] and odds[i] > 0 then
				table.insert(rows, "{r" .. (#rows + 1) .. "} " .. tostring(odds[i]) .. "%")
				words["r" .. #rows] = Loc.text(Strings.Rarity[name] or name)
			end
		end
		local line1 = table.concat({ rows[1] or "", rows[2] or "", rows[3] or "" }, "   ")
		local line2 = table.concat({ rows[4] or "", rows[5] or "", rows[6] or "" }, "   ")
		local titleText = if sg.zone == "Summit" then Strings.World.summitSign else Strings.Zone[sg.zone]
		-- two identical boards back to back, each with its own SurfaceGui on Front (a cloned board draws no text)
		local function makeBoard(name: string, yawDeg: number, shift: number): Part
			local cf = CFrame.new(pos + Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.new(0, 0, shift)
			local b = part({ Name = name, Size = Vector3.new(15, 6.5, 0.5), CFrame = cf, Color = Color3.fromRGB(245, 235, 215) }, z)
			b.CanCollide = true -- the post ends under the board, the board is solid
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			gui.PixelsPerStud = 40
			gui.Parent = b
			local title = Instance.new("TextLabel")
			title.Size = UDim2.fromScale(1, 0.34)
			title.BackgroundTransparency = 1
			title.TextScaled = true
			title.Font = UI_FONT
			title.TextColor3 = Color3.fromRGB(60, 45, 40)
			title.Text = titleText
			title.Parent = gui
			local body = Instance.new("TextLabel")
			body.Size = UDim2.fromScale(1, 0.62)
			body.Position = UDim2.fromScale(0, 0.36)
			body.BackgroundTransparency = 1
			body.Font = Enum.Font.GothamBold
			body.TextSize = 26
			body.TextWrapped = true
			body.TextColor3 = Color3.fromRGB(60, 45, 40)
			Loc.tag(body, "Text", line1 .. "\n" .. line2, words)
			body.Parent = gui
			return b
		end
		-- two boards (cloned or built from scratch) give empty signs on both sides; the working variant -
		-- one board with a SurfaceGui in front and a second SurfaceGui on Back
		local board = makeBoard("Board", sg.yawDeg, 0)
		local front = board:FindFirstChildWhichIsA("SurfaceGui")
		if front then
			local back = front:Clone()
			back.Face = Enum.NormalId.Back
			back.Parent = board
		end
		if sg.zone ~= "Springs" then -- at Springs the arrow lay in the brook water
		arrow("ZoneArrow_" .. sg.zone, pos + Vector3.new(0, 0, 0) + CFrame.Angles(0, math.rad(sg.yawDeg), 0).LookVector * -8, -CFrame.Angles(0, math.rad(sg.yawDeg), 0).LookVector, z)
		end
	end
end

local function buildEggPoints(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "EggPoints"
	f.Parent = root
	for _, p in Layout.eggPoints() do
		local anchor = part({ Name = p.id, Size = Vector3.new(2, 0.2, 2), CFrame = CFrame.new(v3(p.pos) + Vector3.new(0, 0.1, 0)), Transparency = 1 }, f)
		noCollide(anchor)
		anchor:SetAttribute("Zone", p.zone)
		anchor:SetAttribute("PointId", p.id)
		if p.secret then
			anchor:SetAttribute("Secret", true) -- no label above the egg and no Hints prompts
		end
		CollectionService:AddTag(anchor, "EggPoint")
		WorldBuilder.eggPoints[p.id] = anchor
		-- a placeholder until EggSpawner (1.7): a static egg of the zone's home element, the zone label
		local home = Config.Balance.homeElements[p.zone]
		local el = home[((tonumber(string.match(p.id, "%d+")) or 1) % #home) + 1]
		local egg = makeEgg(el, 3.0)
		placeOn(egg, v3(p.pos) + Vector3.new(0, if p.zone == "Cliffs" then 0.6 else 1.3, 0)) -- the terrain is smoothed upward by ~1 stud
		egg.Parent = anchor
		-- without a label - the labels (only Meadow, up close) are placed by EggSpawner together with the real egg
	end
end

local function buildWindRings(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "WindRings"
	f.Parent = root
	local R = W.windRings
	local color = rgb(R.color)
	for _, rg in Layout.windRings() do
		local m = Instance.new("Model")
		m.Name = "WindRing" .. rg.index
		local center = v3(rg.pos)
		local cf = CFrame.lookAt(center, center + v3(rg.axis))
		local hub = part({ Name = "Hub", Size = Vector3.new(R.radius * 2, R.radius * 2, 0.4), CFrame = cf, Transparency = 1 }, m)
		hub.CanCollide = false
		hub.CanQuery = false
		m.PrimaryPart = hub
		for i = 1, R.segments do
			local a = (i - 1) / R.segments * math.pi * 2
			local seg = part({ Name = "Seg", Size = Vector3.new(1.4, 2 * math.pi * R.radius / R.segments * 1.08, 1.4),
				CFrame = cf * CFrame.Angles(0, 0, a) * CFrame.new(R.radius, 0, 0), Color = color, Material = Enum.Material.Neon }, m)
			noCollide(seg)
		end
		m:SetAttribute("Ring", rg.index)
		CollectionService:AddTag(m, "WindRing")
		m.Parent = f
	end
end

-- the world boundaries: 4 invisible walls along the sea perimeter (past the water edge the character would fall into the void)
local function buildBounds(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "Bounds"
	f.Parent = root
	local B = W.bounds
	local half = W.waterSize / 2 - B.margin
	local len = W.waterSize
	for _, def in { { "East", half, 0, 2, len }, { "West", -half, 0, 2, len }, { "South", 0, half, len, 2 }, { "North", 0, -half, len, 2 } } do
		local wall = part({ Name = "Bound" .. def[1], Size = Vector3.new(def[4], B.height, def[5]), CFrame = CFrame.new(def[2], B.height / 2 - 40, def[3]), Transparency = 1 }, f)
		wall.CanQuery = false
		CollectionService:AddTag(wall, "WorldBound")
	end
end

local function buildClouds(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "Clouds"
	f.Parent = root
	-- Roblox volumetric clouds (Terrain.Clouds): in the place file they are written by build.py, here a safeguard on the live server
	if W.clouds.volumetric then
		pcall(function()
			local T = Workspace.Terrain
			local c = T:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
			c.Cover = W.clouds.volumetric.cover
			c.Density = W.clouds.volumetric.density
			c.Color = Color3.fromRGB(255, 255, 255)
			c.Enabled = true
			c.Parent = T
		end)
	end
	if not W.clouds.balls then
		return
	end
	local rng = Random.new(7)
	for i = 1, W.clouds.count do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(120, 520)
		local y = rng:NextNumber(W.clouds.yMin, W.clouds.yMax)
		local c = Vector3.new(math.cos(a) * r, y, math.sin(a) * r)
		local m = Instance.new("Model")
		m.Name = "Cloud" .. i
		for k = 1, 3 do
			local s = rng:NextNumber(14, 26)
			local b = part({ Name = "Puff", Shape = Enum.PartType.Ball, Size = Vector3.new(s * 1.6, s, s * 1.2),
				CFrame = CFrame.new(c + Vector3.new((k - 2) * s * 0.9, rng:NextNumber(-3, 3), rng:NextNumber(-4, 4))),
				Color = Color3.fromRGB(252, 252, 255), Material = Enum.Material.SmoothPlastic, Transparency = 0.12 }, m) -- Neon on the phone = lanterns
			noCollide(b)
		end
		m.Parent = f
	end
end

local keeperModel: Model? = nil
local function buildKeeper(root: Folder)
	local assetId = Content.Assets.keeper
	if not assetId or assetId == 0 then
		return
	end
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn("[WorldBuilder] keeper mesh failed: " .. tostring(container))
		return
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		model = Instance.new("Model")
		for _, c in container:GetChildren() do
			c.Parent = model
		end
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			if d:IsA("MeshPart") then
				model.PrimaryPart = d
			end
		elseif d:IsA("LuaSourceContainer") then -- ModuleScripts too, like ModelLibrary.load
			d:Destroy()
		end
	end
	local _, size = model:GetBoundingBox()
	local height = Config.Dragon.stages[4].height * 1.3
	if size.Y > 0 then
		model:ScaleTo(model:GetScale() * height / size.Y)
	end
	model.Name = "OldAsh"
	-- the snout at -Z: the Keeper is placed behind the table, facing south (toward petals 240-300 and the stall), 10 studs north of the center
	placeOn(model, Vector3.new(W.keeper.x, W.keeper.y + plazaLift, W.keeper.z + 4)) -- the snout at -Z: looks north, toward the stall and the spawn; on the slab circle
	model:SetAttribute("DisplayName", Strings.Keeper.name)
	CollectionService:AddTag(model, "Keeper")
	local adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if adornee then
		label(adornee, Strings.Keeper.name, Strings.World.keeperSub, height * 0.55 + 2, 150, 50) -- was 200 px up to 140 studs - huge from above, on the coin counter
	end
	model.Parent = root -- first take it out of the container, otherwise Destroy() of the container locks the model's Parent
	local col = disc("KeeperCollider", Vector3.new(W.keeper.x, W.keeper.y + 9, W.keeper.z + 4), 8, 18, Color3.new(1, 1, 1), root, { Transparency = 1 })
	col.CanQuery = false -- the player does not go inside the mesh
	container:Destroy()
	keeperModel = model
end

-- decor placeholders until own meshes (04 §1; "empty and plain"): trees of 2 parts, bushes, rocks on the glade
local function buildDecor(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "Decor"
	f.Parent = root
	local rng = Random.new(11)
	local pts = Layout.eggPoints()
	local signs = Layout.zoneSigns()
	local paths = Layout.paths()
	local S = W.zones.Summit.center
	local function free(x: number, z: number, margin: number): boolean
		if x < -190 or z < -280 then
			return false -- Springs with the channel and the Cliffs foot
		end
		for _, pa in paths do
			if Layout.segDist(x, z, pa.from, pa.to) < W.paths.width / 2 + 5 then
				return false -- the paths and the coins on them stay free
			end
		end
		if math.sqrt((x - S[1]) ^ 2 + (z - S[3]) ^ 2) < W.mountain.baseRadius + 25 then
			return false
		end
		for _, p in pts do
			if math.abs(p.pos[1] - x) < margin and math.abs(p.pos[3] - z) < margin then
				return false
			end
		end
		for _, sg in signs do
			if math.abs(sg.pos[1] - x) < 14 and math.abs(sg.pos[3] - z) < 14 then
				return false
			end
		end
		return true
	end
	local function spot(margin: number): (number?, number?)
		for _ = 1, 30 do
			local a = rng:NextNumber(0, math.pi * 2)
			local r = rng:NextNumber(W.terrace.radius + 45, W.islandSize / 2 - 30)
			local x, z = math.cos(a) * r, math.sin(a) * r
			if free(x, z, margin) then
				return x, z
			end
		end
		return nil, nil
	end
	local crowns = { Color3.fromRGB(96, 186, 78), Color3.fromRGB(78, 168, 92), Color3.fromRGB(118, 198, 72) }
	for _ = 1, 40 do
		local x, z = spot(16)
		if x and z then
			local g = Layout.groundHeight(hills, x, z)
			local h = rng:NextNumber(8, 13)
			local trunk = disc("Trunk", Vector3.new(x, g + h / 2, z), 1.1, h, Color3.fromRGB(125, 85, 55), f)
			trunk.Material = Enum.Material.Wood
			local d = rng:NextNumber(11, 17)
			local crown = part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d * 0.9, d), CFrame = CFrame.new(x, g + h + d * 0.3, z), Color = crowns[rng:NextInteger(1, #crowns)] }, f)
			crown.CanCollide = false
			crown.CanQuery = false
		end
	end
	for _ = 1, 40 do
		local x, z = spot(12)
		if x and z then
			local g = Layout.groundHeight(hills, x, z)
			local d = rng:NextNumber(4, 7)
			local bush = part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d * 0.7, d), CFrame = CFrame.new(x, g + d * 0.3, z), Color = crowns[rng:NextInteger(1, #crowns)] }, f)
			bush.CanCollide = false
			bush.CanQuery = false
			bush.CastShadow = false
		end
	end
	for _ = 1, 30 do
		local x, z = spot(12)
		if x and z then
			local g = Layout.groundHeight(hills, x, z)
			local d = rng:NextNumber(3, 7)
			local rock = part({ Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(d * 1.3, d * 0.7, d), CFrame = CFrame.new(x, g + d * 0.2, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Color = Color3.fromRGB(150, 140, 128), Material = Enum.Material.Slate }, f)
			rock.CanCollide = d > 5
		end
	end
end

-- slab rocks along the island edge (craft/04 §7.4 item 1): rock with a grass cap instead of a flat beach, with gaps
local function buildEdgeRocks(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "EdgeRocks"
	f.Parent = root
	local rng = Random.new(13)
	for i, r in Layout.edgeRocks() do
		local cf = CFrame.new(r.x, r.h / 2 - 3, r.z) * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), math.rad(r.yawDeg), math.rad(rng:NextNumber(-4, 4)))
		part({ Name = "EdgeRock" .. i, Size = Vector3.new(r.w, r.h, r.d), CFrame = cf, Color = rgb(C.rock), Material = Enum.Material.Slate }, f)
		local cap = part({ Name = "EdgeRockCap" .. i, Size = Vector3.new(r.w * 0.92, 1.2, r.d * 0.92), CFrame = cf * CFrame.new(0, r.h / 2 + 0.4, 0), Color = rgb(C.grass) }, f)
		cap.CanCollide = false
		cap.CanQuery = false
		-- a second slab offset at every second rock: the silhouette of "stacked slabs of different height" (craft/04 §7.4)
		if i % 2 == 0 then
			local h2 = r.h * rng:NextNumber(0.45, 0.7)
			local cf2 = cf * CFrame.new(rng:NextNumber(-r.w * 0.2, r.w * 0.2), r.h / 2 + h2 / 2 - 0.2, rng:NextNumber(-r.d * 0.15, r.d * 0.15)) * CFrame.Angles(0, math.rad(rng:NextNumber(-20, 20)), 0)
			part({ Name = "EdgeRockTop" .. i, Size = Vector3.new(r.w * 0.6, h2, r.d * 0.7), CFrame = cf2, Color = rgb(C.rock), Material = Enum.Material.Slate }, f)
			local cap2 = part({ Name = "EdgeRockTopCap" .. i, Size = Vector3.new(r.w * 0.55, 1, r.d * 0.65), CFrame = cf2 * CFrame.new(0, h2 / 2 + 0.3, 0), Color = rgb(C.grass) }, f)
			cap2.CanCollide = false
			cap2.CanQuery = false
		end
	end
end

-- C3: stone arches in the sea - two pillars of tilted blocks and a lintel of three segments; the Limestone material with the granite
-- variant (the phone draws parts with a texture). The numbers - island2.arches.
local function graniteBlock(name: string, size: Vector3, cf: CFrame, parent: Instance): Part
	local v = nil
	if W.materials and W.materials.enabled then
		for _, mv in W.materials.variants do
			if mv.base == "Limestone" then
				v = mv
			end
		end
	end
	local p = part({ Name = name, Size = size, CFrame = cf, Material = Enum.Material.Limestone, Color = rgb(if v then v.tint else { 150, 140, 125 }) }, parent)
	if v then
		pcall(function()
			(p :: any).MaterialVariant = v.name
		end)
	end
	return p
end

local function buildArches(root: Folder)
	local A = W.island2 and W.island2.arches
	if not A then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "Arches"
	f.Parent = root
	for i, a in A do
		local rng = Random.new(a.seed)
		local rad = Island.coastRadius(math.rad(a.angleDeg)) * a.dist
		local d = Layout.dir(a.angleDeg)
		local center = Vector3.new(d[1] * rad, 0, d[3] * rad)
		local tangent = Vector3.new(-d[3], 0, d[1])
		local base = W.island2.beach.seabed
		local m = Instance.new("Model")
		m.Name = "Arch" .. i
		for side = -1, 1, 2 do
			local foot = center + tangent * (a.span / 2 * side)
			local y = base
			local blockH = (a.height - base) / 3
			for k = 1, 3 do
				local w = 16 - (k - 1) * 3
				local cf = CFrame.new(foot.X + rng:NextNumber(-2, 2), y + blockH / 2, foot.Z + rng:NextNumber(-2, 2))
					* CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), math.rad(rng:NextNumber(0, 360)), math.rad(rng:NextNumber(-4, 4)))
				graniteBlock("Pillar" .. k, Vector3.new(w, blockH + 2, w), cf, m)
				y += blockH
			end
		end
		-- the lintel: three segments, the middle one higher (a slight arc)
		local segLen = a.span / 3 + 4
		for k = -1, 1 do
			local lift = if k == 0 then 4 else 0
			local tilt = -k * math.rad(10)
			local cf = CFrame.new(center + tangent * (k * a.span / 3) + Vector3.new(0, a.height + 2 + lift, 0))
				* CFrame.fromMatrix(Vector3.zero, tangent, Vector3.yAxis) * CFrame.Angles(0, 0, tilt)
			graniteBlock("Lintel" .. (k + 2), Vector3.new(segLen, 9, 12), cf, m)
		end
		m.Parent = f
	end
end

-- the floating islets above the glade (craft/04 §7.5): a vertical and a backdrop without meshes
local function buildIslets(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "Islets"
	f.Parent = root
	local I = W.islets
	local rng = Random.new(17)
	local T = Workspace.Terrain
	for i, isl in Layout.islets() do -- a ring of islands around the Summit, the radius from the layout
		local r = isl.r
		local c = Vector3.new(isl.x, isl.y, isl.z)
		local m = Instance.new("Model")
		m.Name = "Islet" .. i
		if I.terrain then -- an islet as terrain - rock below, a grass cap on top
			tsafe("islet " .. i, function()
				-- a thin cap (3 studs) over the void is not rendered, the ball reads as a whole. So the cap is 6 studs
				-- (c-5..c+1) with radius r, a rock ball of 0.85 r with its top inside the cap: a flat grass disc from above, a stone hemisphere from below
				local mat = (Enum.Material :: any)[W.cliffMaterial] or Enum.Material.Rock
				local B = I.body
				if B then -- one body - an inverted rocky cone with bumps, a tail to the side
					local rr = Random.new(500 + i)
					local depth = r * rr:NextNumber(B.depth[1], B.depth[2])
					local steps = math.max(3, math.floor(depth / B.step))
					local tx, tz = rr:NextNumber(-B.tilt, B.tilt) * r, rr:NextNumber(-B.tilt, B.tilt) * r
					for k = 0, steps do
						local f = k / steps
						local rad = math.max(2.5, r * 0.95 * (1 - f) ^ B.shape * (1 + 0.15 * math.sin(k * 1.7 + i)))
						local cen = c + Vector3.new(tx * f + rr:NextNumber(-1, 1) * r * 0.06, -4 - f * depth + rad * 0.35, tz * f + rr:NextNumber(-1, 1) * r * 0.06)
						T:FillBall(cen, rad, mat)
						if k % 2 == 1 and rad > 5 then
							local a = rr:NextNumber(0, math.pi * 2)
							T:FillBall(cen + Vector3.new(math.cos(a) * rad * 0.65, rr:NextNumber(-2, 2), math.sin(a) * rad * 0.65), rad * 0.42, mat)
						end
					end
					T:FillCylinder(CFrame.new(c + Vector3.new(0, 1 + r, 0)), r * 2, r * 1.3, Enum.Material.Air) -- nothing above the cap
				else
					local br = r * (I.ballScale or 0.85)
					T:FillBall(c - Vector3.new(0, br + 2, 0), br, mat)
				end
				T:FillCylinder(CFrame.new(c - Vector3.new(0, 2, 0)), 6, r, Enum.Material.Grass)
				T:FillCylinder(CFrame.new(c - Vector3.new(0, 1, 0)), 4, r, Enum.Material.Grass)
			end)
			m.Parent = f
			continue
		end
		local top = disc("IsletTop", c, r, 3, rgb(C.grass), m)
		top.CanQuery = false
		local under = part({ Name = "IsletRock", Shape = Enum.PartType.Ball, Size = Vector3.new(r * 1.9, r * 1.1, r * 1.9), CFrame = CFrame.new(c - Vector3.new(0, r * 0.5, 0)), Color = rgb(C.rock), Material = Enum.Material.Slate }, m)
		under.CanCollide = false
		under.CanQuery = false
		if W.decor.placeholders then -- a tree and a bush of parts; with mesh decor they are placed by Decor
			local h = rng:NextNumber(6, 9)
			local trunk = disc("Trunk", c + Vector3.new(r * 0.3, 1.5 + h / 2, 0), 0.9, h, Color3.fromRGB(125, 85, 55), m)
			trunk.Material = Enum.Material.Wood
			trunk.CanCollide = false
			local d = rng:NextNumber(8, 12)
			local crown = part({ Name = "Crown", Shape = Enum.PartType.Ball, Size = Vector3.new(d, d * 0.9, d), CFrame = CFrame.new(c + Vector3.new(r * 0.3, 1.5 + h + d * 0.3, 0)), Color = Color3.fromRGB(96, 186, 78) }, m)
			crown.CanCollide = false
			crown.CanQuery = false
			local bush = part({ Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.new(5, 3.5, 5), CFrame = CFrame.new(c + Vector3.new(-r * 0.4, 2.6, r * 0.2)), Color = Color3.fromRGB(118, 198, 72) }, m)
			bush.CanCollide = false
			bush.CanQuery = false
		end
		m.Parent = f
	end
	-- waterfalls from the edge of the big islands outward from the peak - a Beam ribbon and mist below
	-- (the official Roblox teardown "Create waterfalls with VFX"); the water goes into the mist, the islands need no ground
	local WF = I.waterfall
	if WF then
		local list = Layout.islets()
		table.sort(list, function(a, b)
			return a.r > b.r
		end)
		local SC = W.zones.Summit.center
		for k = 1, math.min(WF.count, #list) do
			local isl = list[k]
			local dirV = Vector3.new(isl.x - SC[1], 0, isl.z - SC[3]).Unit
			local top = Vector3.new(isl.x, isl.y + 0.6, isl.z) + dirV * isl.r * 0.96
			local holder = part({ Name = "Waterfall" .. k, Size = Vector3.one, CFrame = CFrame.lookAt(top, top + dirV), Transparency = 1 }, f)
			holder.CanCollide = false
			holder.CanQuery = false
			holder.CanTouch = false
			local a0 = Instance.new("Attachment")
			a0.Axis = Vector3.new(0, 0, -1) -- the ribbon bends outward
			a0.Parent = holder
			local a1 = Instance.new("Attachment")
			a1.Parent = holder
			a1.WorldPosition = top + dirV * WF.out - Vector3.new(0, WF.length, 0)
			-- three ribbons with a running jet texture (an own map
			-- assets_src/ui/waterfall_streaks.png, transparent gaps between the jets), the scene light affects it (LightInfluence),
			-- at the bottom the ribbon fans out and melts, on top - a narrow bright core faster, around - a wide misty veil
			local TEX = WF.textures or {}
			local ribbonIndex = 0
			local function ribbon(name: string, w0: number, w1: number, speed: number, trans: NumberSequence, emission: number, curve: number, color: Color3, z: number): Beam
				ribbonIndex += 1
				local tex = TEX[ribbonIndex] or ""
				local b = Instance.new("Beam")
				b.Name = name
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.Width0 = w0
				b.Width1 = w1
				b.Color = ColorSequence.new(color)
				b.Transparency = trans
				b.LightEmission = emission
				b.LightInfluence = WF.lightInfluence or 0.7
				b.FaceCamera = true
				b.Segments = 24
				b.CurveSize0 = curve
				b.CurveSize1 = -curve * 0.35 -- a slight S-bend - the ribbon bottom deflects back, like a real jet
				b.ZOffset = z
				if tex ~= "" then
					b.Texture = tex
					b.TextureMode = Enum.TextureMode.Wrap
					b.TextureLength = WF.textureLength or 22
					b.TextureSpeed = speed
				end
				b.Parent = holder
				return b
			end
			local SP = WF.speed or { 1.4, 2.1, 0.9 }
			ribbon("Fall", WF.width[1], WF.width[2] * 1.3, SP[1],
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.3), NumberSequenceKeypoint.new(0.85, 0.6), NumberSequenceKeypoint.new(1, 1) }),
				0.2, WF.curve, Color3.fromRGB(205, 228, 245), 0)
			ribbon("Core", WF.width[1] * 0.45, WF.width[2] * 0.55, SP[2],
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) }),
				0.45, WF.curve * 0.85, Color3.fromRGB(236, 246, 255), 0.3)
			ribbon("Veil", WF.width[1] * 1.7, WF.width[2] * 2.1, SP[3],
				NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.85), NumberSequenceKeypoint.new(0.5, 0.75), NumberSequenceKeypoint.new(1, 1) }),
				0.1, WF.curve * 1.15, Color3.fromRGB(220, 236, 250), -0.3)
			-- drops and water dust along the whole height: an invisible column, an emitter from the volume downward
			local col = part({ Name = "WaterfallSpray" .. k, Size = Vector3.new(WF.width[1], WF.length, WF.width[1]), CFrame = CFrame.new(top + dirV * (WF.out * 0.5) - Vector3.new(0, WF.length / 2, 0)), Transparency = 1 }, f)
			col.CanCollide = false
			col.CanQuery = false
			col.CanTouch = false
			local drops = Instance.new("ParticleEmitter")
			drops.Shape = Enum.ParticleEmitterShape.Box
			drops.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			drops.EmissionDirection = Enum.NormalId.Bottom
			drops.Rate = WF.dropsRate
			drops.Lifetime = NumberRange.new(1, 2)
			drops.Speed = NumberRange.new(10, 22)
			drops.Acceleration = Vector3.new(0, -30, 0)
			drops.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
			drops.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			drops.Color = ColorSequence.new(Color3.fromRGB(230, 242, 255))
			drops.LightEmission = 0.2
			drops.Parent = col
			local spray = Instance.new("ParticleEmitter") -- spray at the top edge
			spray.Rate = WF.mistRate * 0.6
			spray.Lifetime = NumberRange.new(0.6, 1.2)
			spray.Speed = NumberRange.new(3, 7)
			spray.SpreadAngle = Vector2.new(60, 60)
			spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 4) })
			spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
			spray.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
			spray.Parent = a0
			local mist = Instance.new("ParticleEmitter")
			mist.Rate = WF.mistRate
			mist.Lifetime = NumberRange.new(2, 3.5)
			mist.Speed = NumberRange.new(2, 6)
			mist.SpreadAngle = Vector2.new(180, 180)
			mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 5), NumberSequenceKeypoint.new(1, 16) })
			mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
			mist.Color = ColorSequence.new(Color3.fromRGB(235, 245, 255))
			mist.Parent = a1
			local sndId = Content.Sounds and Content.Sounds.waterfall or 0 -- 3D water noise at the foot (the Roblox library)
			if typeof(sndId) == "number" and sndId > 0 then
				local snd = Instance.new("Sound")
				snd.Name = "WaterfallSound"
				snd.SoundId = "rbxassetid://" .. sndId
				snd.Looped = true
				snd.Volume = 0.45
				snd.RollOffMode = Enum.RollOffMode.InverseTapered
				snd.RollOffMinDistance = 12
				snd.RollOffMaxDistance = 150
				snd.Parent = col
				snd.Playing = true
			end
			local foam = Instance.new("ParticleEmitter") -- foam at the foot: flat white tufts scatter sideways
			foam.Rate = WF.foamRate or 16
			foam.Lifetime = NumberRange.new(0.8, 1.6)
			foam.Speed = NumberRange.new(6, 14)
			foam.SpreadAngle = Vector2.new(90, 90)
			foam.EmissionDirection = Enum.NormalId.Top
			foam.Acceleration = Vector3.new(0, -18, 0)
			foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
			foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
			foam.Color = ColorSequence.new(Color3.fromRGB(250, 253, 255))
			foam.LightEmission = 0.15
			foam.Parent = a1
		end
	end
end

-- the coins on the paths (craft/04 §7.4 item 3): golden discs, pickup by passing through; crediting the coins - IncomeService (1.7),
-- here only the disappearance and the return after respawnSeconds
local coins: { BasePart } = {}
local function buildCoins(root: Folder)
	local f = Instance.new("Folder")
	f.Name = "Coins"
	f.Parent = root
	local K = W.coins
	local paths = Layout.paths()
	for _, c in Layout.coins() do
		local pos = v3(c.pos)
		local dirV = Vector3.zAxis
		for _, pa in paths do
			if pa.zone == c.zone then
				dirV = (v3(pa.to) - v3(pa.from)).Unit
			end
		end
		local y = Layout.terrainHeight(hills, pos.X, pos.Z) + 2 -- C2
		local coin = part({ Name = c.id, Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, K.size, K.size),
			CFrame = CFrame.lookAt(Vector3.new(pos.X, y, pos.Z), Vector3.new(pos.X, y, pos.Z) + dirV) * CFrame.Angles(0, math.rad(90), 0),
			Color = Color3.fromRGB(240, 190, 50), Material = Enum.Material.Neon }, f)
		coin.CanCollide = false
		coin.CanQuery = false
		coin:SetAttribute("Value", K.value)
		coin:SetAttribute("CoinId", c.id)
		CollectionService:AddTag(coin, "TrailCoin")
		label(coin, string.gsub(Strings.World.coin, "{n}", tostring(K.value)), nil, K.size / 2 + 1, 60, 35) -- loc-ok: "+5" without words
		table.insert(coins, coin)
	end
end

-- ---------------------------------------------------------------------------------------------- the service
local svc: { [string]: any } = {}
function WorldBuilder.init(_services: { [string]: any })
	svc = _services
	local t0 = os.clock()
	partCount = 0
	pcall(function() -- in the live game the property may be editor-only; in the place file it is already off
		Workspace.StreamingEnabled = W.streamingEnabled
	end)
	local old = Workspace:FindFirstChild("World")
	if old then
		old:Destroy()
	end
	hills = Layout.hills()
	buildTerrain()
	local root = Instance.new("Folder")
	root.Name = "World"
	WorldBuilder.root = root

	local templates = Instance.new("Folder")
	templates.Name = "Templates"
	local nestTemplate = buildNestTemplate()
	nestTemplate.Parent = templates
	local eggTemplate = makeEgg("ember", 2.8)
	eggTemplate.Name = "EggTemplate"
	eggTemplate.Parent = templates
	templates.Parent = ServerStorage
	WorldBuilder.templates = templates

	local errors = 0
	local steps = { { "terrace", buildTerrace }, { "zones", buildZones }, { "eggPoints", buildEggPoints }, { "windRings", buildWindRings }, { "clouds", buildClouds }, { "bounds", buildBounds }, { "islets", buildIslets }, { "arches", buildArches }, { "coins", buildCoins } }
	if W.decor.placeholders then -- placeholders of balls and slabs; with mesh decor the trees and rocks are placed by Decor
		table.insert(steps, { "decor", buildDecor })
		table.insert(steps, { "edgeRocks", buildEdgeRocks })
	end
	for _, step in steps do
		local ok, err = pcall(step[2] :: any, root)
		if not ok then
			errors += 1
			warn("[WorldBuilder] " .. step[1] .. ": " .. tostring(err))
		end
	end
	local okN, errN = pcall(buildNests, root, nestTemplate)
	if not okN then
		errors += 1
		warn("[WorldBuilder] nests: " .. tostring(errN))
	end
	root.Parent = Workspace
	task.spawn(function()
		local ok, err = pcall(buildKeeper, root)
		if not ok then
			warn("[WorldBuilder] keeper: " .. tostring(err))
		end
	end)
	root:SetAttribute("BuildErrors", errors + terrainErrors)
	root:SetAttribute("Hills", #hills)

	local parts = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	root:SetAttribute("Parts", parts)
	if parts > Config.Perf.partsMax then
		warn(string.format("[WorldBuilder] parts %d > budget %d (04 §9)", parts, Config.Perf.partsMax))
	end
	print(string.format("[WorldBuilder] world built: %d parts, %d nests, %d egg points, %d rings, errors %d, %.2f s", parts, #WorldBuilder.nests,
		#Layout.eggPoints(), #Layout.windRings(), errors + terrainErrors, os.clock() - t0))
end

-- the coins on the paths: a touch hides the coin and brings it back after respawnSeconds; the spin - by the server for now (1.8: the client)
local function startCoins()
	local K = W.coins
	for _, coin in coins do
		coin.CanTouch = true
		coin.Touched:Connect(function(hit: BasePart)
			if coin.Transparency > 0 then
				return
			end
			local ch = hit.Parent
			-- a touch from afar (firetouchinterest) hid the coin for everyone - only at the player's honest position nearby
			local pl = ch and game:GetService("Players"):GetPlayerFromCharacter(ch)
			if pl and svc.AntiCheat and not svc.AntiCheat.near(pl, coin.Position, coin.Size.Magnitude / 2 + K.touchSlack) then
				return
			end
			if ch and ch:FindFirstChildOfClass("Humanoid") then
				coin.Transparency = 1
				local gui = coin:FindFirstChildWhichIsA("BillboardGui")
				if gui then
					gui.Enabled = false
				end
				task.delay(K.respawnSeconds, function()
					coin.Transparency = 0
					if gui then
						gui.Enabled = true
					end
				end)
			end
		end)
	end
	task.spawn(function()
		local spin = CFrame.Angles(math.rad(12), 0, 0) -- the coin axis = the local X after the 90-degree turn around Y
		while true do
			task.wait(0.1)
			for _, coin in coins do
				if coin.Parent then
					coin.CFrame = coin.CFrame * spin
				end
			end
		end
	end)
end

-- switch the warm incubator light on/off (called by Incubation when an egg appears and leaves)
function WorldBuilder.setIncubatorLight(nest: Model, slot: number, on: boolean)
	local inc = nest:FindFirstChild("Incubators")
	local ring = inc and inc:FindFirstChild("Incubator" .. slot)
	local light = ring and ring:FindFirstChild("WarmLight")
	if light and light:IsA("PointLight") then
		light.Enabled = on
	end
	local IM = W.incubatorMesh
	local b = ring and ring:FindFirstChild("Bowl")
	local runes = b and b:FindFirstChild("Runes")
	if runes and runes:IsA("BasePart") then -- the bowl runes glow at an occupied one
		runes.Material = if on then Enum.Material.Neon else Enum.Material.Slate
		runes.Color = rgb(if on then IM.runeWarm else IM.runeIdle)
	end
	local em = ring and ring:FindFirstChild("WarmSparks", true)
	if em and em:IsA("ParticleEmitter") then
		em.Enabled = on
	end
end

-- the Springs guard. Before, the zone was closed only by the wall on the bridge (there was no "open to a teen" logic)
-- a hatchling swam across the brook or glided from the plateau. Now a hatchling (a companion of stage < needsStage) west of the brook in the Springs area
-- is returned to the crossing on the east bank with a hint (not more often than toastEvery s)
local function springsGuard()
	local SM = W.springsMesh
	local GC = SM and SM.enabled and SM.gate
	if not GC or not Workspace:FindFirstChild("World") then
		return
	end
	local Players = game:GetService("Players")
	local b = W.island2.springs.box
	local back = Vector3.new(GC.back[1], GC.back[2], GC.back[3])
	local told: { [Player]: number } = {}
	while true do
		task.wait(GC.checkSeconds or 0.5)
		for _, pl in Players:GetPlayers() do
			local stage = pl:GetAttribute("CompanionStage")
			if typeof(stage) ~= "number" or stage < GC.needsStage then
				local ch = pl.Character
				local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
				if hrp and hrp:IsA("BasePart") then
					local p = hrp.Position
					if p.X >= b.x1 - 30 and p.X <= b.x2 and p.Z >= b.z1 - 20 and p.Z <= b.z2 + 20 and p.X < Island.channelX(p.Z) - Island.channelHalf(p.Z) - 1 then
						ch:PivotTo(CFrame.new(back))
						hrp.AssemblyLinearVelocity = Vector3.zero
						if svc.AntiCheat then -- a server relocation - a new honest point
							svc.AntiCheat.moved(pl)
						end
						if os.clock() - (told[pl] or -99) > (GC.toastEvery or 6) and svc.Net then
							told[pl] = os.clock()
							svc.Net.notice(pl, { kind = "toast", text = Strings.World.springsGuard })
						end
					end
				end
			end
		end
	end
end

-- a safeguard: the character below the water or beyond the boundary - returned to the spawn pad (before Nest/Movement in 1.7-1.9)
function WorldBuilder.start()
	local Players = game:GetService("Players")
	pcall(startCoins)
	task.spawn(function()
		local ok, err = pcall(springsGuard)
		if not ok then
			warn("[WorldBuilder] springs guard: " .. tostring(err))
		end
	end)
	local B = W.bounds
	local limit = W.waterSize / 2 - B.margin - 5
	while true do
		task.wait(B.checkSeconds)
		local spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation")
		local back = if spawn then spawn.Position + Vector3.new(0, 4, 0) else Vector3.new(0, W.terrace.y + 4, -30)
		for _, pl in Players:GetPlayers() do
			local ch = pl.Character
			local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local p = hrp.Position
				if p.Y < B.returnBelowY or math.abs(p.X) > limit or math.abs(p.Z) > limit then
					ch:PivotTo(CFrame.new(back))
					hrp.AssemblyLinearVelocity = Vector3.zero
					if svc.AntiCheat then -- a server relocation - a new honest point
						svc.AntiCheat.moved(pl)
					end
				end
			end
		end
	end
end

function WorldBuilder.getHills(): { Layout.Hill }
	return hills
end

-- the nest by number, the spot by id (for Nest / EggSpawner)
function WorldBuilder.getNest(index: number): Model?
	return WorldBuilder.nests[index]
end

function WorldBuilder.getEggPoint(id: string): BasePart?
	return WorldBuilder.eggPoints[id]
end

function WorldBuilder.getKeeper(): Model?
	return keeperModel
end

return WorldBuilder
