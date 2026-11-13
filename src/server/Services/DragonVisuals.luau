--!strict
-- The look of dragons in the world (03 §1, §7; spec 1.2 P3; task 1.6): the model by element and stage from ModelLibrary (or a fallback
-- figure of parts), the scale by stage and size, attachments (eyes, mouth, saddle / shoulder, crest, back, tail, wings),
-- Neon eyes, overlaid element features made of parts (until own meshes), a flat body color for non-Ember J/A/E (until element
-- textures), a label (name, rarity), a spot stand in a contrasting color. The numbers - DragonLook (pure logic) and Config.Dragon.
-- Movement (saddle, flight) - Movement (1.9); LOD by distance (03 §7) - the client (1.8).
-- Without Nest (1.7) it shows the showcase: demo dragons in nests 1-3 (gate 1.6: 6 elements distinguishable from 60 studs).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
local DragonLook = require(Shared:WaitForChild("Core"):WaitForChild("DragonLook"))
local Economy = require(Shared:WaitForChild("Core"):WaitForChild("Economy"))
local Format = require(Shared:WaitForChild("Core"):WaitForChild("Format"))
local ModelLibrary = require("./ModelLibrary")

local D = Config.Dragon
local PAD_EMPTY = Color3.fromRGB(160, 144, 124)

local DragonVisuals = {}
local services: { [string]: any } = {}

export type DragonRec = { uid: string, element: string, rarity: string, stage: number, size: string?, shiny: boolean?, name: string, preset: string?, variant: string?, glow: boolean? }

-- the label above a dragon is seen by everyone - the size and shine marks and the rarity are translated by the client (the template {w1} {w2});
-- the dragon's name (or the element without public names) is not translated - unique. The same order as DragonLook.label
local function labelLoc(rec: any): (any, any)
	local title = DragonLook.label(rec, Config.Names.publicNames)
	local parts, v = {}, {}
	local function add(word: string)
		table.insert(parts, "{w" .. (#parts + 1) .. "}")
		v["w" .. #parts] = Loc.text(word)
	end
	if rec.size == "huge" then
		add(Strings.Card.tagHuge)
	elseif rec.size == "big" then
		add(Strings.Card.tagBig)
	end
	if rec.shiny then
		add(Strings.Card.tagShiny)
	end
	add((Strings.Rarity :: any)[rec.rarity] or rec.rarity)
	return title, Loc.text(table.concat(parts, " "), v)
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function basePart(p: BasePart)
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

-- a fallback figure 1 tall (if the mesh did not load): a ball body, a head, little wings; the element color
local function fallbackBody(element: string): Model
	local m = Instance.new("Model")
	m.Name = "Dragon"
	local el = Content.Elements[element]
	local color = if el then rgb(el.color) else Color3.fromRGB(200, 200, 200)
	local function piece(name: string, shape: Enum.PartType, size: Vector3, cf: CFrame): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = shape
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		basePart(p)
		p.Parent = m
		return p
	end
	local body = piece("Body", Enum.PartType.Ball, Vector3.new(0.62, 0.62, 0.62), CFrame.new(0, 0.31, 0.1))
	piece("Head", Enum.PartType.Ball, Vector3.new(0.5, 0.5, 0.5), CFrame.new(0, 0.72, -0.25))
	piece("WingL", Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.3), CFrame.new(-0.45, 0.55, 0.1) * CFrame.Angles(0, 0, math.rad(25)))
	piece("WingR", Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.3), CFrame.new(0.45, 0.55, 0.1) * CFrame.Angles(0, 0, math.rad(-25)))
	m.PrimaryPart = body
	return m
end

local function overlayPart(o: DragonLook.Overlay, height: number, at: Attachment, body: BasePart, parent: Instance)
	local size = Vector3.new(o.size[1], o.size[2], o.size[3]) * height
	local p: BasePart
	if o.shape == "wedge" then
		local w = Instance.new("WedgePart")
		w.Size = size
		p = w
	else
		local b = Instance.new("Part")
		b.Size = size
		if o.shape == "ball" then
			b.Shape = Enum.PartType.Ball
		elseif o.shape == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = b
		end
		p = b
	end
	p.Name = o.name
	p.Color = rgb(o.color)
	p.Material = if o.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Transparency = o.transparency or 0
	basePart(p)
	p.CFrame = at.WorldCFrame * CFrame.new(o.offset[1] * height, o.offset[2] * height, o.offset[3] * height)
		* CFrame.Angles(math.rad(o.rot[1]), math.rad(o.rot[2]), math.rad(o.rot[3]))
	p.Parent = parent
	weld(body, p)
end

-- looks (07 add. 2.6): a dragon's color preset (Config.Looks.presets). The Preset attribute on the model - the clients see it
-- (Controllers/Looks paints with a highlight: on v4b meshes the texture is in TextureID, the part color does not change it). If the mesh has
-- a SurfaceAppearance, we paint its Color here (visible to everyone without a highlight) and set PresetTinted. id = nil - restore the original color.
function DragonVisuals.applyPreset(m: Model, id: string?)
	local P = if id then (Config.Looks.presets :: any)[id] else nil
	m:SetAttribute("Preset", if P then id else nil)
	local tinted = false
	for _, d in m:GetDescendants() do
		if d:IsA("SurfaceAppearance") then
			local ok = pcall(function()
				if d:GetAttribute("LookColor0") == nil then
					d:SetAttribute("LookColor0", d.Color)
				end
				local c0 = d:GetAttribute("LookColor0")
				d.Color = if P then rgb(P.tint) elseif typeof(c0) == "Color3" then c0 else Color3.new(1, 1, 1)
			end)
			tinted = tinted or (ok and P ~= nil)
		end
	end
	m:SetAttribute("PresetTinted", if tinted then true else nil)
end

-- Build a dragon model from the record (inNest: Big/Huge for A/E only in the nest, 03 §1.2)
function DragonVisuals.build(rec: DragonRec, inNest: boolean?): Model
	local stage = rec.stage
	local height = DragonLook.height(stage, rec.size, inNest ~= false)
	local assets = Content.Assets.dragons[rec.element] or Content.Assets.dragons.ember
	local assetId = assets[stage + 1] or 0
	local vdef = if rec.variant then (Content.Variants :: any)[rec.variant] else nil -- 2.9: an element variant - its own stage mesh (recolor), 0 - regular
	if vdef and vdef.stages and (vdef.stages[stage + 1] or 0) > 0 then
		assetId = vdef.stages[stage + 1]
	end
	-- Studio only: in a local file the meshes do not load (not authorized) and build does not wait;
	-- the attribute workspace.DebugBuildDelay (s) simulates waiting for the mesh load on a live server
	if RunService:IsStudio() then
		local w = workspace:GetAttribute("DebugBuildDelay")
		if typeof(w) == "number" and w > 0 then
			task.wait(w)
		end
	end
	local model = ModelLibrary.get(assetId)
	local fromMesh = model ~= nil
	if not model then
		model = fallbackBody(rec.element)
	end
	local m = model :: Model
	m.Name = "Dragon"
	m:ScaleTo(m:GetScale() * height) -- the library template is 1 tall
	local body = m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	if not body then
		return m
	end
	m.PrimaryPart = body
	body.Name = "Body"
	if stage >= 1 then
		body.CanCollide = true -- the body of a teen and older is solid in the nest too
	end

	-- the body: a flat element color for non-Ember J/A/E (the Ember mesh on all), the texture is removed together with the SurfaceAppearance
	local bodyColor = DragonLook.bodyColor(rec.element, stage)
	if bodyColor and fromMesh then
		for _, d in m:GetDescendants() do
			if d:IsA("MeshPart") then
				d.TextureID = ""
				d.Color = rgb(bodyColor)
				d.Material = Enum.Material.SmoothPlastic
			elseif d:IsA("SurfaceAppearance") then
				d:Destroy()
			end
		end
	end

	-- attachments by fractions of the bounding box (Config.Dragon.attach)
	local cf, size = m:GetBoundingBox()
	local atts: { [string]: Attachment } = {}
	for name, f in DragonLook.attachments(stage) do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = body
		a.WorldPosition = cf:PointToWorldSpace(Vector3.new(f[1] * size.X, (f[2] - 0.5) * size.Y, f[3] * size.Z))
		atts[name] = a
	end

	-- the eyes: Neon balls in the element's second color
	local eyeColor = rgb(DragonLook.eyeColor(rec.element))
	local eyeSize = D.eyes.sizeOfLength * size.Z
	for _, name in { "EyeL", "EyeR" } do
		local a = if D.eyes.enabled ~= false then atts[name] else nil -- v3 models have the eyes in the texture
		if a then
			local e = Instance.new("Part")
			e.Name = name
			e.Shape = Enum.PartType.Ball
			e.Size = Vector3.one * eyeSize
			e.Color = eyeColor
			e.Material = Enum.Material.Neon
			basePart(e)
			e.CFrame = a.WorldCFrame
			e.Parent = m
			weld(body, e)
		end
	end

	-- overlaid element features (P3)
	for _, o in DragonLook.overlays(rec.element, stage) do
		local a = atts[o.at]
		if a then
			overlayPart(o, height, a, body, m)
		end
	end

	-- the saddle (03 §1.2 "a soft saddle"; visible - a leather cushion with a rear cantle; the Seat seats the rider, Movement 1.9)
	local saddle = atts.Saddle
	if saddle then
		-- on v4 the wings are raised above the back, the bounding box fraction
		-- (0.64 of the height) put the saddle in the air. A ray down along the body mesh at the saddle point - the saddle onto the back surface; a miss - as before.
		local seatH = height * 0.03
		if fromMesh then
			local wasParent = m.Parent
			if not wasParent then
				m.Parent = workspace -- the ray sees only parts in Workspace
			end
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Include
			params.FilterDescendantsInstances = { body }
			local wasQuery = body.CanQuery
			body.CanQuery = true -- ModelLibrary.prepare switches CanQuery off on all library parts
			local wp = saddle.WorldPosition
			local hit = workspace:Raycast(Vector3.new(wp.X, cf.Position.Y + size.Y, wp.Z), Vector3.new(0, -size.Y * 2, 0), params)
			if hit then
				saddle.WorldPosition = Vector3.new(wp.X, hit.Position.Y + seatH / 2 + height * 0.004, wp.Z)
				m:SetAttribute("SaddleOnBack", math.floor((wp.Y - hit.Position.Y) * 100) / 100)
			end
			body.CanQuery = wasQuery
			if not wasParent then
				m.Parent = nil
			end
		end
		-- the Seat is invisible (only seats), the look is a leather ellipsoid
		-- cushion, a rear cantle and a front pommel (sphere meshes), a girth and two stirrups; axes: -Z the snout, +Z the tail
		local seat = Instance.new("Seat")
		seat.Name = "Saddle"
		seat.Size = Vector3.new(height * 0.11, seatH, height * 0.16)
		seat.Transparency = 1
		seat.Disabled = true
		basePart(seat)
		seat.CFrame = saddle.WorldCFrame
		seat.Parent = m
		weld(body, seat)
		local LEATHER = Color3.fromRGB(118, 74, 42)
		local LEATHER_DARK = Color3.fromRGB(78, 48, 28)
		local function pad(name: string, sz: Vector3, color: Color3, offset: CFrame, meshType: Enum.MeshType?, material: Enum.Material?)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = sz
			p.Color = color
			p.Material = material or Enum.Material.Leather
			basePart(p)
			if meshType then
				local sm = Instance.new("SpecialMesh")
				sm.MeshType = meshType
				sm.Parent = p
			end
			p.CFrame = saddle.WorldCFrame * offset
			p.Parent = m
			weld(body, p)
			return p
		end
		-- the cushion: a flat ellipsoid slightly wider than the seat, its edges sink into the back
		pad("SaddleCushion", Vector3.new(height * 0.13, height * 0.045, height * 0.2), LEATHER, CFrame.new(0, height * 0.004, height * 0.005), Enum.MeshType.Sphere)
		-- the rear cantle and the front pommel
		pad("SaddleCantle", Vector3.new(height * 0.12, height * 0.075, height * 0.05), LEATHER_DARK, CFrame.new(0, height * 0.03, height * 0.085), Enum.MeshType.Sphere)
		pad("SaddlePommel", Vector3.new(height * 0.05, height * 0.05, height * 0.045), LEATHER_DARK, CFrame.new(0, height * 0.03, -height * 0.085), Enum.MeshType.Sphere)
		-- the girth under the cushion and two stirrups on the sides
		pad("SaddleStrap", Vector3.new(height * 0.17, height * 0.012, height * 0.05), LEATHER_DARK, CFrame.new(0, -height * 0.012, 0))
		for _, sideX in { -1, 1 } do
			-- a cylinder mesh along the X axis: a thin disc, visible from the side as a stirrup ring; the stirrup leather - a narrow strip from the cushion down
			pad("SaddleStirrup", Vector3.new(height * 0.012, height * 0.04, height * 0.04), Color3.fromRGB(92, 92, 98), CFrame.new(sideX * height * 0.085, -height * 0.11, -height * 0.01), Enum.MeshType.Cylinder, Enum.Material.Metal)
			pad("SaddleStirrupStrap", Vector3.new(height * 0.01, height * 0.1, height * 0.03), LEATHER_DARK, CFrame.new(sideX * height * 0.082, -height * 0.055, -height * 0.01))
		end
	end
	-- steam from the mouth: an emitter at the Mouth point, off; the server (Movement)
	-- switches it on for short breaths of companions; the color - light with an element tint
	local mouth = atts.Mouth
	if mouth and stage >= 1 then
		local el = Content.Elements[rec.element]
		local tint = if el then rgb(el.color) else Color3.new(1, 1, 1)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Breath"
		e.Enabled = false
		e.Rate = 26
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.new(0.92, 0.92, 0.96):Lerp(tint, 0.25), Color3.new(0.85, 0.85, 0.9))
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, height * 0.07), NumberSequenceKeypoint.new(1, height * 0.22) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.6, 0.65), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(0.9, 1.6)
		e.Speed = NumberRange.new(height * 0.25, height * 0.45)
		e.SpreadAngle = Vector2.new(14, 14)
		e.EmissionDirection = Enum.NormalId.Front
		e.LightEmission = 0.15
		e.Acceleration = Vector3.new(0, height * 0.08, 0)
		e.Parent = mouth
	end

	-- the label: the name and the rarity (the income is appended by IncomeService, 1.7)
	local title, sub = labelLoc(rec)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(170, 74)
	bb.StudsOffsetWorldSpace = Vector3.new(0, size.Y / 2 + 1.6, 0)
	bb.MaxDistance = D.labelDistance
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.Name = "Name"
	t.Size = UDim2.fromScale(1, 0.42)
	t.BackgroundTransparency = 1
	t.TextScaled = true
	t.Font = UI_FONT
	t.TextColor3 = Color3.new(1, 1, 1)
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = Color3.fromRGB(40, 30, 30)
	t.Parent = bb
	local s = t:Clone()
	s.Name = "Sub"
	s.Size = UDim2.fromScale(1, 0.3)
	s.Position = UDim2.fromScale(0, 0.42)
	s.TextColor3 = rgb(DragonLook.rarityColor(rec.rarity))
	s.Parent = bb
	-- the income per second (P18: a figure under every creature, like the leaders); IncomeService (1.7) updates through the Income attribute
	local inc = t:Clone()
	inc.Name = "Income"
	inc.Size = UDim2.fromScale(1, 0.28)
	inc.Position = UDim2.fromScale(0, 0.72)
	inc.TextColor3 = Color3.fromRGB(255, 226, 120)
	inc.Text = Format.rate(Economy.dragonIncome({ rarity = rec.rarity, stage = stage, shiny = rec.shiny == true, size = rec.size or "normal", stormborn = false } :: any, Config.Balance))
	inc.Parent = bb
	Loc.set(t, "Text", title) -- after the clones: the template and the Loc tag must not leak into Sub and Income
	Loc.raw(t) -- the name: Roblox does not translate it ("Dusk" = both the element and the time of day)
	Loc.set(s, "Text", sub)
	bb.Parent = body

	m:SetAttribute("Uid", rec.uid)
	m:SetAttribute("Element", rec.element)
	m:SetAttribute("Rarity", rec.rarity)
	m:SetAttribute("Stage", stage)
	m:SetAttribute("DragonName", rec.name)
	m:SetAttribute("Size", rec.size or "normal")
	m:SetAttribute("Shiny", rec.shiny == true)
	m:SetAttribute("Glow", if rec.glow == true then true else nil) -- a glowing dragon (Controllers/Glow)
	m:SetAttribute("FromMesh", fromMesh)
	DragonVisuals.applyPreset(m, rec.preset) -- looks: the color preset
	CollectionService:AddTag(m, "Dragon")
	return m
end

-- renaming (NameDragon): the label and the attribute without rebuilding the model
function DragonVisuals.relabel(m: Model, rec: DragonRec)
	local title, sub = labelLoc(rec)
	m:SetAttribute("DragonName", rec.name)
	local body = m.PrimaryPart
	local bb = body and body:FindFirstChild("Label")
	local t = bb and bb:FindFirstChild("Name")
	local s = bb and bb:FindFirstChild("Sub")
	if t and t:IsA("TextLabel") then
		Loc.set(t, "Text", title)
	end
	if s and s:IsA("TextLabel") then
		Loc.set(s, "Text", sub)
	end
end

-- put the model with its sole on the point without changing the rotation
local function placeOn(model: Model, pos: Vector3)
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	model:PivotTo(model:GetPivot() + (pos - Vector3.new(cf.Position.X, bottom, cf.Position.Z)))
end

local function dragonsFolder(nest: Model): Folder
	local f = nest:FindFirstChild("Dragons")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Dragons"
		f.Parent = nest
	end
	return f :: Folder
end

-- Put a dragon in a nest spot: the snout toward the walkway and the entrance (04 §3), the stand - the element's contrasting color (04 §10)
function DragonVisuals.placeInSlot(nest: Model, slot: number, model: Model): boolean
	local base = nest.PrimaryPart
	local att = base and base:FindFirstChild("Slot" .. slot)
	if not base or not att or not att:IsA("Attachment") then
		return false
	end
	DragonVisuals.clearSlot(nest, slot)
	local facing = DragonLook.slotFacing(att.Position.X)
	local dirW = base.CFrame:VectorToWorldSpace(Vector3.new(facing[1], 0, facing[2]))
	local padTop = att.WorldPosition -- the stand is invisible, the dragon stands on the grass (the petal floor = the terrain 18.0)
	model:PivotTo(CFrame.lookAt(padTop, padTop + dirW)) -- the model's snout at -Z = LookVector
	placeOn(model, padTop)
	model:SetAttribute("Slot", slot)
	model.Parent = dragonsFolder(nest)
	local slots = nest:FindFirstChild("Slots")
	local pad = slots and slots:FindFirstChild("SlotPad" .. slot)
	if pad and pad:IsA("BasePart") then
		pad.Color = rgb(DragonLook.padColor(model:GetAttribute("Element") :: string))
	end
	return true
end

function DragonVisuals.clearSlot(nest: Model, slot: number)
	local f = nest:FindFirstChild("Dragons")
	if f then
		for _, d in f:GetChildren() do
			if d:GetAttribute("Slot") == slot then
				d:Destroy()
			end
		end
	end
	local slots = nest:FindFirstChild("Slots")
	local pad = slots and slots:FindFirstChild("SlotPad" .. slot)
	if pad and pad:IsA("BasePart") then
		pad.Color = PAD_EMPTY
	end
end

function DragonVisuals.init(s: { [string]: any })
	services = s
end

-- The showcase before Nest (1.7): nest 1 - the six elements as adults (gate P3: distinguishable from 60 studs); nest 2 - the four stages
-- of Ember and two elders side by side (03 §1.2: check the crowding); nest 3 - a teen, a hatchling, Big and Huge
local DEMO: { { nest: number, slot: number, rec: DragonRec } } = {}
do
	local rar = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
	for i, el in Config.Elements do
		table.insert(DEMO, { nest = 1, slot = i, rec = { uid = "demo1_" .. i, element = el, rarity = rar[i], stage = 2, name = Content.Elements[el].name } })
	end
	for st = 0, 3 do
		table.insert(DEMO, { nest = 2, slot = st + 1, rec = { uid = "demo2_" .. st, element = "ember", rarity = "Rare", stage = st, name = Strings.Stage[st] } })
	end
	table.insert(DEMO, { nest = 2, slot = 5, rec = { uid = "demo2_e1", element = "frost", rarity = "Legendary", stage = 3, name = "Frost" } })
	table.insert(DEMO, { nest = 2, slot = 6, rec = { uid = "demo2_e2", element = "dusk", rarity = "Epic", stage = 3, name = "Dusk" } })
	table.insert(DEMO, { nest = 3, slot = 1, rec = { uid = "demo3_1", element = "moss", rarity = "Uncommon", stage = 1, name = "Moss" } })
	table.insert(DEMO, { nest = 3, slot = 2, rec = { uid = "demo3_2", element = "tide", rarity = "Common", stage = 0, name = "Tide" } })
	table.insert(DEMO, { nest = 3, slot = 3, rec = { uid = "demo3_3", element = "storm", rarity = "Rare", stage = 1, size = "big", name = "Storm" } })
	table.insert(DEMO, { nest = 3, slot = 4, rec = { uid = "demo3_4", element = "ember", rarity = "Epic", stage = 1, size = "huge", shiny = true, name = "Ember" } })
end

function DragonVisuals.demo()
	local wb = services.WorldBuilder
	if not wb then
		return
	end
	local placed = 0
	for _, d in DEMO do
		local nest = wb.getNest(d.nest)
		if nest then
			local ok, err = pcall(function()
				local m = DragonVisuals.build(d.rec, true)
				if DragonVisuals.placeInSlot(nest, d.slot, m) then
					placed += 1
				end
			end)
			if not ok then
				warn("[DragonVisuals] demo " .. d.rec.uid .. ": " .. tostring(err))
			end
		end
	end
	local st = ModelLibrary.stats()
	print(string.format("[DragonVisuals] demo: %d dragons placed, meshes loaded %d, failed %d", placed, st.loaded, st.failed))
end

function DragonVisuals.start()
	if services.Nest == nil then
		DragonVisuals.demo()
	end
end

return DragonVisuals
