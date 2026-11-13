--!strict
-- The looks showcase: a bought look is visible in the world. What is visible is decided by
-- Core/Looks (pure logic, tests/looks_spec.luau), the numbers and colors - Config.Looks, the texts - Strings.Looks.
-- 1) A color preset (Sunset - a purchase, Solstice - the Season 1 reward, only Dusk): one copy per dragon, Remote SetLook
-- ("preset", id | "none", uid); in the profile dragons[uid].preset; the model gets the Preset attribute (DragonVisuals.applyPreset), painted by
-- the client (Controllers/Looks). The model is not rebuilt: a mounted companion is not dismounted.
-- 2) The Comet trail: a Trail from the tip of the companion's tail while the owner rides an adult/elder in the air (checked every trailEvery s).
-- 3) A nest skin (Lagoon - a purchase, Royal - the Bundle, Gilded - VIP): the color and material of the owner's nest parts by role on an
-- OwnerId change (Nest assign/release) and after a purchase; no owner - the original look (the original color and material are stored in the attributes
-- LookColor0/LookMat0 on the part). The player's choice - SetLook("nestSkin", id | "ascended" | "auto" | "classic"); no choice - the skin by
-- priority, otherwise the Ascension tint (Core/Looks.nestLook). "classic" - the regular look without a tint.
-- 4) The Royal aura (the Bundle): one spark emitter above the owner's nest.
-- 5) Above the head: the VIP tag (a pass) and the Nest Lord title (the Bundle) - a BillboardGui on the head, visible to everyone (not to oneself, showToSelf).
-- 6) The scarf (Starter Pack) - Outfit (together with the basket, after every respawn); here only Outfit.refresh after a purchase.
-- A purchase during play - Shop.afterGrant calls Looks.refresh (a preset - also Looks.autoEquip: at once onto the companion); joining with a purchase -
-- by the nest OwnerId and CharacterAdded.
-- Studio debugging: LoopDebug "looks" | "looks give all|sunset|solstice|comet|lagoon|royal|vip|aura|lord|scarf" | "looks preset <n|uid>
-- <id|none>" | "looks skin <id|ascended|auto|classic>" | "looks asc <n>" (the Ascension step) | "looks trail" | "looks reset".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Content = require(Shared:WaitForChild("Content"))
local LooksCore = require(Shared:WaitForChild("Core"):WaitForChild("Looks"))
local Format = require(Shared:WaitForChild("Core"):WaitForChild("Format")) -- the Roman step of the Ascended title

local Looks = {}

local services: { [string]: any } = {}
local L = Config.Looks
local TG = L.tag
local UI_FONT: Enum.Font = (function()
	local ok, f = pcall(function()
		return (Enum.Font :: any)[Config.UI.font]
	end)
	return if ok and typeof(f) == "EnumItem" then f :: Enum.Font else Enum.Font.FredokaOne
end)()

type Reply = { ok: boolean, reason: string?, [string]: any }

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function material(name: any): Enum.Material?
	if typeof(name) ~= "string" then
		return nil
	end
	local ok, m = pcall(function()
		return (Enum.Material :: any)[name]
	end)
	return if ok and typeof(m) == "EnumItem" then m :: Enum.Material else nil
end

-- ---------------------------------------------------------------------------------------------- the nest skin and aura
-- the part group for the role: the nearest FenceSeg / Fence ancestor (the fence mesh can be nested), otherwise the parent's name
local function groupOf(p: Instance, nest: Model): string?
	local a = p.Parent
	while a and a ~= nest do
		if a.Name == "FenceSeg" or a.Name == "Fence" then
			return a.Name
		end
		a = a.Parent
	end
	return if p.Parent then p.Parent.Name else nil
end

-- tint (05 §6) - the Ascension tint number: paints the fence and sign roles if there is no skin (the skin outranks)
local function paint(nest: Model, skinId: string?, tint: number?)
	local SK = if skinId then (L.nestSkins :: any)[skinId] else nil
	if not SK and tint and L.ascTints then
		SK = { colors = (L.ascTints :: any)[tint] }
	end
	local dragons = nest:FindFirstChild("Dragons")
	for _, p in nest:GetDescendants() do
		if not p:IsA("BasePart") or (dragons and p:IsDescendantOf(dragons)) then
			continue
		end
		local role = LooksCore.nestRole(p.Name, groupOf(p, nest))
		if not role then
			continue
		end
		-- the incubator bowl mesh has its texture in a SurfaceAppearance - the part's Color and Material do not affect the picture (P8 frames:
		-- the bowl is the same under all skins); we tint the texture SurfaceAppearance.Color, the original - the attribute LookSA0
		local sa = p:FindFirstChildOfClass("SurfaceAppearance")
		if p:GetAttribute("LookColor0") == nil then
			p:SetAttribute("LookColor0", p.Color)
			p:SetAttribute("LookMat0", p.Material.Name)
			if sa then
				p:SetAttribute("LookSA0", (sa :: any).Color)
			end
		end
		local c0 = p:GetAttribute("LookColor0")
		local color: Color3? = if typeof(c0) == "Color3" then c0 else nil
		local mat: Enum.Material? = material(p:GetAttribute("LookMat0"))
		local saColor: Color3? = nil
		if SK and SK.colors then
			local c = SK.colors[role]
			if c then -- a role without a color in the Ascension tint - the original color
				color = rgb(c)
				saColor = color
			end
			mat = material(SK.materials and SK.materials[role]) or mat -- a tint without a material - the original
		end
		if color then
			p.Color = color
		end
		if mat then
			p.Material = mat
		end
		if sa then
			local sa0 = p:GetAttribute("LookSA0")
			pcall(function()
				(sa :: any).Color = saColor or (if typeof(sa0) == "Color3" then sa0 else Color3.new(1, 1, 1))
			end)
		end
	end
	nest:SetAttribute("NestSkin", skinId)
	nest:SetAttribute("NestTint", if skinId then nil else tint)
end

local function setAura(nest: Model, id: string?)
	local old = nest:FindFirstChild("LookAura")
	if old and id and old:GetAttribute("Aura") == id then
		return
	end
	if old then
		old:Destroy()
	end
	local A = if id then (L.auras :: any)[id] else nil
	local base = nest.PrimaryPart
	if not A or not base then
		return
	end
	local N = Config.World.nests
	local p = Instance.new("Part")
	p.Name = "LookAura"
	p.Size = Vector3.new(N.lotWidth * A.area, 1, N.lotDepth * A.area)
	p.CFrame = base.CFrame * CFrame.new(0, A.height, 0)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Aura"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Shape = Enum.ParticleEmitterShape.Box
	pe.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = A.rate
	pe.Lifetime = NumberRange.new(A.lifetime[1], A.lifetime[2])
	pe.Speed = NumberRange.new(A.speed[1], A.speed[2])
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.Acceleration = Vector3.new(0, A.rise, 0)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, A.size), NumberSequenceKeypoint.new(0.7, A.size * 0.7), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(1, 1) })
	pe.Color = ColorSequence.new(rgb(A.colors[1]), rgb(A.colors[2]))
	pe.LightEmission = A.lightEmission
	pe.LightInfluence = 0
	pe.Parent = p
	p:SetAttribute("Aura", id)
	p.Parent = nest
end

-- the nest look by the owner (OwnerId): the skin and the aura; no owner (or a bot) - the regular look
local function applyNest(nest: Model)
	local id = nest:GetAttribute("OwnerId")
	local owner = if typeof(id) == "number" and id > 0 then Players:GetPlayerByUserId(id) else nil
	local data = owner and services.PlayerData.get(owner)
	local skin: string?, tint: number? = nil, nil
	if data then
		skin, tint = LooksCore.nestLook(data, L) -- the skin, the Ascension tint or the regular look - by the player's choice
	end
	local aura = if data then LooksCore.aura(data, L) else nil
	paint(nest, skin, tint)
	setAura(nest, aura)
end

function Looks.refreshNest(player: Player)
	local nest = services.Nest and services.Nest.of(player)
	if nest then
		applyNest(nest)
	end
end

-- ---------------------------------------------------------------------------------------------- above the head
function Looks.refreshTag(player: Player)
	local ch = player.Character
	local head = ch and ch:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("LookTag")
	if old then
		old:Destroy()
	end
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	local tags = LooksCore.tags(data, L)
	local rows: { { text: any, color: Color3 } } = {} -- text: a string or Loc.text (the tag above the head is seen by everyone)
	if tags.vip then
		table.insert(rows, { text = Strings.Looks.vipTag, color = rgb(TG.vip) })
	end
	if tags.title then
		table.insert(rows, { text = (Strings.Looks.titles :: any)[tags.title] or tags.title, color = rgb(TG.title) })
	end
	if tags.ascended then -- «Ascended II»
		table.insert(rows, { text = Loc.text(Strings.Looks.ascendedTag, { roman = Format.roman(tags.ascended) }), color = rgb(TG.ascended or TG.title) })
	end
	if #rows == 0 then
		return
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "LookTag"
	bb.Size = UDim2.fromOffset(TG.width, TG.rowHeight * #rows)
	bb.StudsOffset = Vector3.new(0, TG.above, 0)
	bb.MaxDistance = TG.maxDistance
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.Adornee = head
	if not TG.showToSelf then
		bb.PlayerToHideFrom = player
	end
	bb:SetAttribute("DeclutterRank", TG.declutterRank)
	for i, r in rows do
		local t = Instance.new("TextLabel")
		t.Name = "Row" .. i
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1 / #rows)
		t.Position = UDim2.fromScale(0, (i - 1) / #rows)
		t.TextScaled = true
		t.Font = UI_FONT
		t.TextColor3 = r.color
		t.TextStrokeTransparency = 0.3
		t.TextStrokeColor3 = Color3.fromRGB(30, 22, 18)
		Loc.set(t, "Text", r.text)
		t.Parent = bb
	end
	bb.Parent = head
end

-- ---------------------------------------------------------------------------------------------- the flight trail
local function ensureTrail(m: Model, id: string): Trail?
	local body = m.PrimaryPart
	if not body then
		return nil
	end
	local old = body:FindFirstChild("LookTrail")
	if old and old:IsA("Trail") and old:GetAttribute("Trail") == id then
		return old
	end
	if old then
		old:Destroy()
	end
	local tail = body:FindFirstChild("TailTip")
	local T = (L.trails :: any)[id]
	if not tail or not tail:IsA("Attachment") or not T then
		return nil
	end
	local _, size = m:GetBoundingBox()
	local w = math.max(0.4, size.Y * T.widthOfHeight)
	local right = m:GetPivot().RightVector
	local function att(name: string, sign: number): Attachment
		local found = body:FindFirstChild(name)
		local a: Attachment
		if found and found:IsA("Attachment") then
			a = found
		else
			a = Instance.new("Attachment")
			a.Name = name
			a.Parent = body
		end
		a.WorldPosition = tail.WorldPosition + right * (sign * w / 2)
		return a
	end
	local tr = Instance.new("Trail")
	tr.Name = "LookTrail"
	tr.Attachment0 = att("LookTrail0", -1)
	tr.Attachment1 = att("LookTrail1", 1)
	tr.Color = ColorSequence.new(rgb(T.head), rgb(T.tail))
	tr.Transparency = NumberSequence.new(T.transparency[1], T.transparency[2])
	tr.WidthScale = NumberSequence.new(1, T.widthEnd)
	tr.Lifetime = T.lifetime
	tr.LightEmission = T.lightEmission
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Enabled = false
	tr:SetAttribute("Trail", id)
	tr.Parent = body
	return tr
end

-- no ground or water under the belly closer than minAir studs
local function airborne(player: Player, m: Model, body: BasePart, minAir: number): boolean
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { m }
	if player.Character then
		table.insert(ignore, player.Character)
	end
	params.FilterDescendantsInstances = ignore
	params.IgnoreWater = false
	local _, size = m:GetBoundingBox()
	return workspace:Raycast(body.Position, Vector3.new(0, -(minAir + size.Y / 2), 0), params) == nil
end

local function trailTick()
	for _, player in Players:GetPlayers() do
		local m = services.Movement and services.Movement.companionOf(player)
		local body = m and m.PrimaryPart
		if not m or not body then
			continue
		end
		local data = services.PlayerData.get(player)
		local id = data and LooksCore.trail(data, L)
		local stage = m:GetAttribute("Stage")
		local riding = player:GetAttribute("Mounted") ~= nil and typeof(stage) == "number" and stage >= 2
		if id and riding then
			local tr = ensureTrail(m, id)
			if tr then
				tr.Enabled = airborne(player, m, body, (L.trails :: any)[id].minAir)
			end
		else
			local tr = body:FindFirstChild("LookTrail")
			if tr and tr:IsA("Trail") then
				tr.Enabled = false
			end
		end
	end
end

-- ---------------------------------------------------------------------------------------------- the color preset
-- the models of dragon uid of the player: the copy in the nest and/or the companion
local function modelsOf(player: Player, uid: string): { Model }
	local out: { Model } = {}
	local nest = services.Nest and services.Nest.of(player)
	local f = nest and nest:FindFirstChild("Dragons")
	if f then
		for _, m in f:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Uid") == uid then
				table.insert(out, m)
			end
		end
	end
	local c = services.Movement and services.Movement.companionOf(player)
	if c and c:GetAttribute("Uid") == uid then
		table.insert(out, c)
	end
	return out
end

-- SetLook: kind "preset" (id | "none", uid) or "nestSkin" (id | "auto" | "classic")
function Looks.set(player: Player, kind: string, id: string, uid: string?): Reply
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if kind == "preset" then
		if not uid then
			return { ok = false, reason = "bad_request" }
		end
		local pid: string? = if id == "none" then nil else id
		local ok, why, changed = false, nil :: string?, {} :: { string }
		services.PlayerData.update(player, "dragons", function(_, d)
			ok, why, changed = LooksCore.setPreset(d, uid, pid, L)
			return nil
		end)
		if not ok then
			local reply: Reply = { ok = false, reason = why }
			if why == "wrong_element" and pid then
				local el = (L.presets :: any)[pid].element
				local E = el and (Content.Elements :: any)[el]
				reply.element = if E then E.name else el
			end
			return reply
		end
		for _, u in changed do
			local rec = data.dragons[u]
			for _, m in modelsOf(player, u) do
				services.DragonVisuals.applyPreset(m, rec and rec.preset)
			end
		end
		if services.Analytics then
			services.Analytics.custom(player, "look_set", 1, { kind = "preset", id = id })
		end
		return { ok = true, preset = pid, moved = #changed > 1 }
	elseif kind == "nestSkin" then
		local ok, why = false, nil :: string?
		services.PlayerData.update(player, "looks", function(_, d)
			ok, why = LooksCore.setNestSkin(d, id, L)
			return nil
		end)
		if not ok then
			return { ok = false, reason = why }
		end
		Looks.refreshNest(player)
		if services.Analytics then
			services.Analytics.custom(player, "look_set", 1, { kind = "nestSkin", id = id })
		end
		return { ok = true, skin = LooksCore.nestCurrent(data, L) }
	end
	return { ok = false, reason = "bad_request" }
end

-- a preset right after a purchase (Shop.afterGrant) or a reward (Season 1 Solstice - Reward may call the same): put it on if it is not on
-- anyone yet - onto the companion or the first suitable dragon without a preset (Core/Looks.autoTarget); a toast where it is now
function Looks.autoEquip(player: Player, id: string)
	local data = services.PlayerData.get(player)
	local uid = data and LooksCore.autoTarget(data, id, L)
	if not data or not uid then
		return
	end
	local reply = Looks.set(player, "preset", id, uid)
	if reply.ok and services.Net then
		local d = data.dragons[uid]
		local name = (Strings.Looks.presets :: any)[id] or id
		services.Net.notice(player, { kind = "toast", text = Loc.text(Strings.Looks.presetAuto, { name = Loc.text(name), dragon = d and d.name or "" }) }) -- name: Sunset is translated, Cinder/Solstice (dragon names) are not: they are not in the table
	end
end

-- after a purchase or a gift (Shop.afterGrant) and on join: everything that depends on the ownership flags
function Looks.refresh(player: Player)
	for name, fn in { nest = Looks.refreshNest, tag = Looks.refreshTag, outfit = function(p: Player)
		if services.Outfit and services.Outfit.refresh then
			services.Outfit.refresh(p)
		end
	end } :: { [string]: (Player) -> () } do
		local ok, err = pcall(fn, player)
		if not ok then
			warn("[Looks] refresh " .. name .. ": " .. tostring(err))
		end
	end
end

-- ---------------------------------------------------------------------------------------------- debugging (Studio only)
function Looks.debug(player: Player, arg: string): Reply
	if not RunService:IsStudio() then
		return { ok = false, reason = "forbidden" }
	end
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local words = {}
	for w in string.gmatch(arg, "%S+") do
		table.insert(words, w)
	end
	local verb = words[1] or "state"
	if verb == "give" then
		local what = words[2] or "all"
		services.PlayerData.update(player, "owned", function(o)
			o = if typeof(o) == "table" then o else {}
			local function look(group: string, id: string)
				o[group] = if typeof(o[group]) == "table" then o[group] else {}
				o[group][id] = true
			end
			local all = what == "all"
			if all or what == "sunset" or what == "solstice" then
				look("presets", if what == "solstice" then "solstice" else "sunset")
				if all then
					look("presets", "solstice")
				end
			end
			if all or what == "comet" then
				look("trails", "comet")
			end
			if all or what == "lagoon" or what == "royal" then
				look("nestSkins", if what == "royal" then "royal" else "lagoon")
				if all then
					look("nestSkins", "royal")
				end
			end
			if all or what == "aura" then
				look("auras", "royal")
			end
			if all or what == "lord" then
				look("titles", "nestLord")
			end
			if all or what == "vip" then
				o.vip = true
			end
			if all or what == "scarf" then
				o.scarf = true
			end
			return o
		end)
		if services.Nest then
			services.Nest.refresh(player) -- VIP: a slot in the nest
		end
		Looks.refresh(player)
		return { ok = true, reason = "give " .. what .. " | " .. LooksCore.summary(data, L) }
	elseif verb == "preset" then
		local target = words[2] or "1"
		local uid = if tonumber(target) then data.nestOrder[tonumber(target) :: number] else target
		return Looks.set(player, "preset", words[3] or "sunset", uid)
	elseif verb == "skin" then
		return Looks.set(player, "nestSkin", words[2] or "auto", nil)
	elseif verb == "asc" then -- the Ascension step for tint probes ("looks asc 6")
		local n = math.max(0, math.floor(tonumber(words[2]) or 0))
		services.PlayerData.update(player, "ascension", function()
			return n
		end)
		Looks.refresh(player)
		return { ok = true, reason = "ascension=" .. n .. " | " .. LooksCore.summary(data, L) }
	elseif verb == "reset" then
		services.PlayerData.update(player, "owned", function(o)
			if typeof(o) == "table" then
				for _, g in { "presets", "trails", "nestSkins", "auras", "titles" } do
					o[g] = nil
				end
				o.vip = nil
				o.scarf = nil
			end
			return nil
		end)
		services.PlayerData.update(player, "dragons", function(_, d)
			LooksCore.cleanPresets(d, L)
			return nil
		end)
		services.PlayerData.update(player, "looks", function()
			return { nestSkin = "" }
		end)
		if services.Nest then
			services.Nest.refresh(player)
		end
		Looks.refresh(player)
		return { ok = true, reason = "reset | " .. LooksCore.summary(data, L) }
	elseif verb == "trail" then
		local m = services.Movement and services.Movement.companionOf(player)
		local tr = m and m.PrimaryPart and m.PrimaryPart:FindFirstChild("LookTrail")
		return { ok = tr ~= nil, reason = string.format("mounted=%s stage=%s trail=%s enabled=%s", tostring(player:GetAttribute("Mounted")),
			tostring(m and m:GetAttribute("Stage")), tostring(tr ~= nil), tostring(tr and tr:IsA("Trail") and tr.Enabled)) }
	end
	local nest = services.Nest and services.Nest.of(player)
	local head = player.Character and player.Character:FindFirstChild("Head")
	local presets = {}
	for _, m in game:GetService("CollectionService"):GetTagged("Dragon") do
		if m:GetAttribute("OwnerId") == player.UserId and m:GetAttribute("Preset") then
			table.insert(presets, tostring(m:GetAttribute("Uid")) .. "=" .. tostring(m:GetAttribute("Preset")) .. (if m:GetAttribute("PresetTinted") then "/sa" else "/hl"))
		end
	end
	return { ok = true, reason = string.format("%s | world: nestSkin=%s aura=%s tag=%s scarf=%s models[%s]", LooksCore.summary(data, L),
		tostring(nest and nest:GetAttribute("NestSkin")), tostring(nest and nest:FindFirstChild("LookAura") ~= nil), tostring(head and head:FindFirstChild("LookTag") ~= nil),
		tostring(player.Character and player.Character:FindFirstChild("Scarf") ~= nil), table.concat(presets, ",")) }
end

-- ---------------------------------------------------------------------------------------------- init / start
function Looks.init(s: { [string]: any })
	services = s
end

function Looks.start()
	services.Net.handle("SetLook", function(player: Player, kind: string, id: string, uid: string?)
		return Looks.set(player, kind, id, uid)
	end)
	-- join: order in the presets (not bought, not of the own element, duplicates). Loaded returns a copy of the profile - write through update (a pitfall)
	services.PlayerData.Loaded:Connect(function(player: Player)
		services.PlayerData.update(player, "dragons", function(_, d)
			LooksCore.cleanPresets(d, L)
			return nil
		end)
	end)
	local function hookPlayer(player: Player)
		player.CharacterAdded:Connect(function(ch)
			task.defer(function()
				ch:WaitForChild("Head", 10)
				if player.Character == ch then
					local ok, err = pcall(Looks.refreshTag, player)
					if not ok then
						warn("[Looks] tag: " .. tostring(err))
					end
				end
			end)
		end)
		if player.Character then
			task.defer(Looks.refreshTag, player)
		end
	end
	Players.PlayerAdded:Connect(hookPlayer)
	for _, p in Players:GetPlayers() do
		hookPlayer(p)
	end
	task.spawn(function()
		while true do
			task.wait(L.trailEvery)
			local ok, err = pcall(trailTick)
			if not ok then
				warn("[Looks] trail: " .. tostring(err))
				task.wait(5)
			end
		end
	end)
	-- the nests are built by WorldBuilder.start (~6 s): the nest look on an owner change (Nest assign/release, Admin bots)
	while #services.WorldBuilder.nests < Config.World.nests.count do
		task.wait(0.25)
	end
	for _, nest in services.WorldBuilder.nests do
		nest:GetAttributeChangedSignal("OwnerId"):Connect(function()
			task.defer(function()
				local ok, err = pcall(applyNest, nest)
				if not ok then
					warn("[Looks] nest: " .. tostring(err))
				end
			end)
		end)
		task.defer(applyNest, nest)
	end
end

return Looks
