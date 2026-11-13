--!strict
-- the same "Living light"
-- from glow-phone-test 98ddf95 (the light session), but ONLY a dragon with the attribute Glow = true glows (from a glowing egg, Services/GlowEgg),
-- by day per Config.Glow.dayFloor.
-- "Living light" on the own client.
-- A game script cannot write SurfaceAppearance maps (ColorMapContent/EmissiveMaskContent - Plugin only:
-- "lacking capability Plugin"), so the SA templates lie ready in the place: ReplicatedStorage.GlowTemplates, one per texture
-- and phase, name "<key>|<night|dusk|day>", attribute Texture = the mesh TextureID. Created in Studio (runs/roblox_glow_phone_test_2026-10-25/
-- templates.py) before publishing. Here only a copy of the template onto a mesh with the same texture (adults of all elements, super dragons) and a swap
-- of the copy on a phase change (the Phase attribute of ReplicatedStorage.DayCycle). A sweep every scanEvery s - models arrive by streaming.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Net = require(script.Parent:WaitForChild("Net"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local loadedRef: any = nil -- Shop (the "Hatch now" button on the pedestal) loads later
local Banners = require(script.Parent:WaitForChild("Banners"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Glow = {}

local G = (Config :: any).Glow
local byTexture: { [string]: string } = {} -- mesh TextureID -> template key
local templates: Folder? = nil
local dcRef: Instance? = nil -- ReplicatedStorage.DayCycle
local parts: { [MeshPart]: string } = {} -- mesh -> key
local fixed: { [MeshPart]: boolean } = {} -- a style showcase statue mesh (the key from the GlowKey attribute, not by texture)
-- (P8 v8: «Unable to load ... GlowSA - EmissiveMap ... NetFail» + «Unable to generate ... Change a TextureId property to retry»):
-- the map did not load the first time - the SurfaceAppearance does not assemble and the engine does not retry by itself; recreate the copy, up to retryMax times
local tries: { [MeshPart]: number } = {}
local RETRY_MAX = 6

-- not three steps by phase but smoothly - one night copy on the mesh, its EmissiveStrength
-- (and Color, if the night has its own, like Prism) changes on the fly: night 1, dawn 1 -> 0 over the phase, day 0, dusk 0 -> 1 (PhaseEndsAt/PhaseSeconds
-- of DayCycle, server time). The copy is not recreated on a phase change - fewer map loads.
local function phaseFactor(): number
	local dc = dcRef
	local ph = dc and dc:GetAttribute("Phase")
	if ph == "night" then
		return 1
	end
	if ph ~= "dawn" and ph ~= "dusk" then
		return 0
	end
	local ends = (dc :: Instance):GetAttribute("PhaseEndsAt")
	local secs = (dc :: Instance):GetAttribute("PhaseSeconds")
	local p = 0.5
	if typeof(ends) == "number" and typeof(secs) == "number" and secs > 0 then
		p = math.clamp(1 - (ends - workspace:GetServerTimeNow()) / secs, 0, 1)
	end
	return if ph == "dawn" then 1 - p else p
end

local function factor(): number
	return math.max(phaseFactor(), G.dayFloor or 0)
end

local WHITE = Color3.new(1, 1, 1)
local function shade(g: Instance, f: number)
	local base = g:GetAttribute("Base")
	if typeof(base) == "number" then
		(g :: any).EmissiveStrength = base * f
	end
	local bc = g:GetAttribute("BaseColor")
	if typeof(bc) == "Color3" then
		(g :: any).Color = WHITE:Lerp(bc, f)
	end
end

local function put(d: MeshPart, key: string)
	local f = templates
	local t = f and f:FindFirstChild(key .. "|night")
	local old = d:FindFirstChild("GlowSA")
	if old then
		old:Destroy()
	end
	if t then
		local n = t:Clone()
		n.Name = "GlowSA"
		n:SetAttribute("Base", (t :: any).EmissiveStrength)
		if (t :: any).Color ~= WHITE then
			n:SetAttribute("BaseColor", (t :: any).Color)
		end
		pcall(shade, n, factor())
		n.Parent = d
	end
end

local function scan()
	for _, tag in { "Dragon" } do
		for _, m in CollectionService:GetTagged(tag) do
			if m:IsDescendantOf(workspace) and m:GetAttribute("Glow") == true then -- only a dragon from a glowing egg
				for _, d in m:GetDescendants() do
					if d:IsA("MeshPart") and not parts[d] then
						local key = byTexture[d.TextureID]
						if key and not d:FindFirstChildWhichIsA("SurfaceAppearance") then
							parts[d] = key
							put(d, key)
						end
					end
				end
			end
		end
	end
	for _, m in CollectionService:GetTagged("StyleGlow") do -- the template by the model key
		local key = m:GetAttribute("GlowKey")
		if typeof(key) == "string" and m:IsDescendantOf(workspace) then
			for _, d in m:GetDescendants() do
				if d:IsA("MeshPart") and d.TextureID ~= "" and not parts[d] then
					parts[d] = key
					fixed[d] = true
					put(d, key)
				end
			end
		end
	end
	for d, key in parts do
		if not d.Parent then
			parts[d] = nil
			fixed[d] = nil
		elseif not fixed[d] and byTexture[d.TextureID] ~= key then -- the mesh changed its texture (looks/stage): remove
			local old = d:FindFirstChild("GlowSA")
			if old then
				old:Destroy()
			end
			parts[d] = nil
		end
	end
end

-- glow diagnostics: a line in the player attribute GlowDiag, Controllers/Perf adds it to the
-- PerfLog_v1 journal. gl=glowing/dragons; fm/fc = glow mask/texture: loaded/error/loading; x: element (2 letters)+stage+
-- reason: tx - no template for the mesh texture, sa - another SurfaceAppearance on the mesh, pt - no template for the phase, nm - no mesh
local function failed(g: Instance): boolean
	local bad = false
	pcall(function()
		for _, c in { (g :: any).EmissiveMaskContent, (g :: any).ColorMapContent } do
			if ContentProvider:GetAssetFetchStatus(c.Uri) == Enum.AssetFetchStatus.Failure then
				bad = true
			end
		end
	end)
	return bad
end

local function retryFailed()
	for d, key in parts do
		local g = d.Parent and d:FindFirstChild("GlowSA")
		if g and (tries[d] or 0) < RETRY_MAX and failed(g) then
			tries[d] = (tries[d] or 0) + 1
			g:Destroy()
			put(d, key)
		end
	end
	for d in tries do
		if not d.Parent then
			tries[d] = nil
		end
	end
end

-- the engine message "Unable to generate 'Workspace.….GlowSA' due to some of the textures being unavailable" / "Unable to load ….GlowSA -
-- …" -> find that copy by path and recreate it (GetAssetFetchStatus may not show such a failure)
local function onLog(msg: string)
	local path = string.match(msg, "Unable to generate '([^']+%.GlowSA)'") or string.match(msg, "Unable to load ([^%s]+%.GlowSA) ")
	if not path then
		return
	end
	local node: Instance? = game
	for seg in string.gmatch(path, "[^%.]+") do
		if seg == "Workspace" and node == game then
			node = workspace
		else
			node = node and node:FindFirstChild(seg)
		end
	end
	local d = node and node.Parent
	if d and d:IsA("MeshPart") and parts[d] and (tries[d] or 0) < RETRY_MAX then
		tries[d] = (tries[d] or 0) + 1
		local key = parts[d]
		task.delay(3, function()
			local g = d:FindFirstChild("GlowSA")
			if g then
				g:Destroy()
			end
			if d.Parent then
				put(d, key)
			end
		end)
	end
end

local function diag()
	local total, lit, miss = 0, 0, {}
	local fm, fc = { 0, 0, 0 }, { 0, 0, 0 }
	local function st(uri: any, t: { number })
		local ok, s = pcall(function()
			return ContentProvider:GetAssetFetchStatus(uri)
		end)
		if ok and s == Enum.AssetFetchStatus.Success then
			t[1] += 1
		elseif ok and s == Enum.AssetFetchStatus.Failure then
			t[2] += 1
		else
			t[3] += 1
		end
	end
	for _, m in CollectionService:GetTagged("Dragon") do
		if m:IsDescendantOf(workspace) then
			total += 1
			local has, why = false, "nm"
			for _, d in m:GetDescendants() do
				if d:IsA("MeshPart") then
					local g = d:FindFirstChild("GlowSA")
					if g then
						has = true
						pcall(function()
							st((g :: any).EmissiveMaskContent.Uri, fm)
							st((g :: any).ColorMapContent.Uri, fc)
						end)
					elseif not byTexture[d.TextureID] then
						why = "tx"
					elseif d:FindFirstChildWhichIsA("SurfaceAppearance") then
						why = "sa"
					else
						why = "pt"
					end
				end
			end
			if has then
				lit += 1
			elseif #miss < 6 then
				table.insert(miss, string.sub(tostring(m:GetAttribute("Element") or "?"), 1, 2) .. tostring(m:GetAttribute("Stage") or "?") .. why)
			end
		end
	end
	local rt = 0
	for _, k in tries do
		rt += k
	end
	local s = string.format("gl=%d/%d fm=%d/%d/%d fc=%d/%d/%d rt=%d", lit, total, fm[1], fm[2], fm[3], fc[1], fc[2], fc[3], rt)
	if #miss > 0 then
		s ..= " x:" .. table.concat(miss, ",")
	end
	local me = Players.LocalPlayer
	if me then
		me:SetAttribute("GlowDiag", string.sub(s, 1, 110))
	end
end

-- the pedestal boards (the timer above the pedestal + the side card with buttons) - at module level, Glow.boardVisible reads them
local boards: { [Instance]: any } = {}

-- a pedestal board with buttons on screen - for PassChips (pass chips) and Gifts (the notifications prompt): one request at a time
function Glow.boardVisible(): boolean
	for _, b in boards do
		if b.card.Enabled and (b.warm.Visible or b.hn.Visible) then
			return true
		end
	end
	return false
end

function Glow.init(_snapshot: any, loaded: any)
	loadedRef = loaded
end

-- the thief gets a golden
-- path from the nest to the lot gate and a green SAFE line with a caption on the floor; removed at home, on capture, on a new nest
local raidFx: Folder? = nil
local function clearRaidFx()
	if raidFx then
		raidFx:Destroy()
		raidFx = nil
	end
end

local function flatPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, transparency: number): Part
	local q = Instance.new("Part")
	q.Anchored = true
	q.CanCollide = false
	q.CanQuery = false
	q.CanTouch = false
	q.CastShadow = false
	q.Material = Enum.Material.Neon
	q.Color = color
	q.Transparency = transparency
	q.Size = size
	q.CFrame = cf
	q.Parent = parent
	return q
end

-- the path nest -> a point in front of the lot gate (out) -> the pedestal (home)
-- through the gate; the SAFE line across the gate (a-b), the caption inside
local function showRaidFx(from: any, out: any, home: any, gate: any, a: any, b: any, mid: any?)
	clearRaidFx()
	if typeof(from) ~= "Vector3" or typeof(gate) ~= "Vector3" then
		return
	end
	local pts: { Vector3 } = { from }
	if typeof(out) == "Vector3" then
		table.insert(pts, out)
	end
	if typeof(mid) == "Vector3" then -- through the gate center (the pedestal is off the axis - a dash at the post)
		table.insert(pts, mid)
	end
	table.insert(pts, if typeof(home) == "Vector3" then home else gate)
	local f = Instance.new("Folder")
	f.Name = "GlowRaidFx"
	f.Parent = workspace
	raidFx = f
	local skip: { Instance } = { f }
	for _, n in { "GlowEggs", "Gloom" } do
		local x = workspace:FindFirstChild(n)
		if x then
			table.insert(skip, x)
		end
	end
	for _, pl in Players:GetPlayers() do
		if pl.Character then
			table.insert(skip, pl.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	local function floorY(x: number, z: number, ref: number): number
		local h = workspace:Raycast(Vector3.new(x, ref + 20, z), Vector3.new(0, -60, 0), params)
		return if h then h.Position.Y else ref
	end
	-- one path: the way is shown only by the hint chevron chain (Hints) from the player's feet; what stays here is the SAFE
	-- line in the gate and the SAFE ZONE caption (the arrow target and the end of the run). pts and floorY - for the line and the caption below
	local _ = pts
	if typeof(a) == "Vector3" and typeof(b) == "Vector3" then -- the SAFE line along the lot edge and the caption on the floor inside
		local mid = (a + b) / 2
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local y = mid.Y + 0.1
		local green = Color3.fromRGB(90, 230, 110)
		local line = flatPart(f, Vector3.new(0.9, 0.15, ab.Magnitude), CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X, y, mid.Z) + ab.Unit), green, 0.1)
		line.Name = "SafeLine" -- the target of the home arrow (Hints glowHome): into the gate, not through the fence to the bowl
		local n = Vector3.new(-ab.Z, 0, ab.X).Unit
		if n:Dot(Vector3.new(mid.X - from.X, 0, mid.Z - from.Z)) < 0 then
			n = -n -- into the lot, away from the nest
		end
		local lp = Vector3.new(gate.X, y, gate.Z) + n * 4
		local sign = flatPart(f, Vector3.new(10, 0.1, 3), CFrame.lookAt(lp, lp + n) * CFrame.Angles(0, math.pi / 2, 0), green, 1)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Top
		sg.LightInfluence = 0
		sg.PixelsPerStud = 40
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.FredokaOne
		t.Text = Loc.fill(Strings.GlowEgg.safeZone)
		t.TextColor3 = green
		t.TextStrokeTransparency = 0.3
		t.Parent = sg
		sg.Parent = sign
	end
end

-- the Gloom caught up - the glowing egg flies in an arc from the hands back into the golden nest (the server puts it there after seconds s)
local function eggArc(from: any, to: any, seconds: number)
	if typeof(from) ~= "Vector3" or typeof(to) ~= "Vector3" then
		return
	end
	local egg = Instance.new("Part")
	egg.Name = "GlowEggArc"
	egg.Size = Vector3.new(1.7, 1.7, 1.7)
	egg.Material = Enum.Material.Neon
	egg.Color = Color3.fromRGB(255, 190, 90)
	egg.Anchored = true
	egg.CanCollide = false
	egg.CanQuery = false
	egg.CanTouch = false
	egg.CastShadow = false
	egg.CFrame = CFrame.new(from)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1.3, 1)
	mesh.Parent = egg
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 200, 80)
	light.Range = 14
	light.Brightness = 2
	light.Parent = egg
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Rate = 40
	sp.Lifetime = NumberRange.new(0.4, 0.7)
	sp.Speed = NumberRange.new(0.5, 1.5)
	sp.Size = NumberSequence.new(0.6, 0)
	sp.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140))
	sp.LightEmission = 1
	sp.Parent = egg
	egg.Parent = workspace
	local apex = math.max(10, (to - from).Magnitude * 0.35)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local t = math.clamp((os.clock() - t0) / math.max(seconds, 0.1), 0, 1)
		egg.CFrame = CFrame.new(from:Lerp(to, t) + Vector3.new(0, apex * 4 * t * (1 - t), 0))
		if t >= 1 then
			if conn then
				conn:Disconnect()
			end
			egg:Destroy()
		end
	end)
	task.delay(seconds + 2, function() -- a reserve: the frame did not reach the end (the window was minimized)
		if conn and conn.Connected then
			conn:Disconnect()
		end
		if egg.Parent then
			egg:Destroy()
		end
	end)
end

-- the finish at the own dragon (rings 1-2) - a golden path from the nest to point D and a green "SAFE" ring there
local function showDragonFx(from: any, d: any)
	clearRaidFx()
	if typeof(from) ~= "Vector3" or typeof(d) ~= "Vector3" then
		return
	end
	local f = Instance.new("Folder")
	f.Name = "GlowRaidFx"
	f.Parent = workspace
	raidFx = f
	-- one path - the hint chevron chain; no dashes to point D, the green SAFE ring at the dragon stays
	local _ = from
	local green = Color3.fromRGB(90, 230, 110)
	local ring = Instance.new("Part")
	ring.Name = "SafeRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.15, 14, 14)
	ring.CFrame = CFrame.new(d + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Material = Enum.Material.Neon
	ring.Color = green
	ring.Transparency = 0.55
	ring.Parent = f
end

local function mmss(sec: number): string
	sec = math.max(0, math.floor(sec + 0.5))
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

function Glow.start()
	-- the raid screen for an egg from the shared Gloom nests
	Net.on("raid", function(p)
		local SR = Strings.Raid
		local red = Color3.fromRGB(255, 70, 60)
		local green = Color3.fromRGB(90, 230, 110)
		local rarity = Loc.fill(Strings.Rarity[tostring(p.rarity)] or tostring(p.rarity or ""))
		if p.ev == "take" then
			if p.chase ~= false then
				Banners.banner(Loc.fill(SR.run), red, Loc.fill(if p.safe == "dragon" then SR.runDragon else SR.runHome), 1.5, true)
				Sounds.play("storm", { volume = 0.7 })
			else
				Banners.banner(Loc.fill(SR.take, { rarity = rarity }), Color3.fromRGB(255, 170, 70), nil, 3, true)
			end
			Sounds.play("egg_pick", { volume = 0.9 })
			local okF, errF = pcall(function()
				if p.safe == "dragon" then
					showDragonFx(p.from, p.d)
				else
					showRaidFx(p.from, p.out, p.home, p.gate, p.a, p.b)
				end
			end)
			if not okF then
				warn("[Glow] raid fx: " .. tostring(errF))
			end
		elseif p.ev == "gate" then
			Banners.toast(Loc.fill(SR.gateWait))
		elseif p.ev == "caught" then
			clearRaidFx()
			Banners.banner(Loc.fill(SR.caught), Color3.fromRGB(255, 92, 70), Loc.fill(SR.caughtSub), 3, true)
			Sounds.play("deny", { volume = 0.8 })
			local okA, errA = pcall(eggArc, p.from, p.to, tonumber(p.seconds) or 1)
			if not okA then
				warn("[Glow] egg arc: " .. tostring(errA))
			end
		elseif p.ev == "escaped" then
			Banners.toast(Loc.fill(SR.escaped))
		elseif p.ev == "safe" then
			clearRaidFx()
			Banners.banner(Loc.fill(SR.safe), green, Loc.fill(SR.safeDragon), 3, true)
			Sounds.play("quest_done", { volume = 0.7 })
		elseif p.ev == "home" then
			clearRaidFx()
			Banners.banner(Loc.fill(if p.shelf then SR.homeShelf else SR.safe), green, Loc.fill(SR.safeSub, { rarity = rarity, t = mmss(tonumber(p.t) or 0) }), 4, true)
			Sounds.play("quest_done", { volume = 0.7 })
			-- the first egg of the daily raid at home - the "invite a friend" card (in idle, once per session)
			if tonumber(p.daily) == 1 and loadedRef and loadedRef.Social and loadedRef.Social.inviteSoon then
				pcall(loadedRef.Social.inviteSoon)
			end
			-- how many eggs are left today; the limit is out - after the SAFE banner "that is all for today, again tomorrow"
			local left = tonumber(p.left)
			if left and left > 0 then
				-- after the SAFE banner (4 s), otherwise the toast drowns under it and the bowl toasts interrupt it
				task.delay(4.2, function()
					Banners.toast(if left == 1 then Loc.fill(SR.dayLeftOne) else Loc.fill(SR.dayLeft, { n = left }))
				end)
			elseif left == 0 then
				task.delay(4.4, function()
					Banners.banner(Loc.fill(SR.dayDone), Color3.fromRGB(255, 200, 80), Loc.fill(SR.dayDoneSub, { n = tonumber(p.of) or 4 }), 4, true)
				end)
			end
		elseif p.ev == "toShelf" then
			Banners.toast(Loc.fill(SR.toShelf))
		elseif p.ev == "noRoom" then -- the bowls are busy, the shelf is full - the raid egg is not taken
			Banners.toast(Loc.fill(SR.noRoom))
		end
	end)
	-- glowing egg announcements
	-- the spawn notice from the server did not arrive during the walkthrough (sent by hand
	-- it shows; the cause in the tick was not found). The banner "A GOLDEN NEST…" is shown once per session on either of two
	-- occasions: the notice OR the own nest GlowEgg_<UserId> appeared in workspace.GlowEggs more than 20 s after joining (not during loading);
	-- wait until the current banner plays out ("{name} grew into a Teen!" arrives in the same tick)
	local spawnShown = false
	local sessionT0 = os.clock()
	local function showSpawnBanner()
		if spawnShown then
			return
		end
		spawnShown = true
		local SG = Strings.GlowEgg
		local col = Color3.fromRGB(255, 170, 70)
		local wait = math.max(0, ((UIKit :: any).bannerUntil or 0) - os.clock()) + 0.2
		task.delay(wait, function()
			if Banners.hold then
				Banners.hold(4.4) -- growth/flight arrive in the same second - let them queue behind the golden one
			end
			Banners.banner(Loc.fill(SG.spawn), col, Loc.fill(SG.spawnSub), 4, true)
			Sounds.play("quest_done", { volume = 0.7 })
		end)
	end
	task.spawn(function()
		local f = workspace:WaitForChild("GlowEggs", 30)
		if not f then
			return
		end
		local mine = "GlowEgg_" .. Players.LocalPlayer.UserId
		f.ChildAdded:Connect(function(c: Instance)
			if c.Name == mine and os.clock() - sessionT0 > 20 then
				showSpawnBanner()
			end
		end)
	end)
	Net.on("glowEgg", function(p)
		local SG = Strings.GlowEgg
		local col = Color3.fromRGB(255, 170, 70)
		if p.ev == "spawn" then
			clearRaidFx()
			showSpawnBanner()
		elseif p.ev == "take" then
			-- a huge red "RUN!" for 1.5 s, the path home and the SAFE line; the chase did not start (no
			-- room on the server) - just "You stole the Glowing Egg!"
			local toDragon = p.safe == "dragon" -- on the slope - "RUN TO YOUR DRAGON!", the path to point D, the SAFE ring at the dragon
			if p.chase ~= false then
				Banners.banner(Loc.fill(SG.run), Color3.fromRGB(255, 70, 60), Loc.fill(if toDragon then Strings.Raid.runDragon else SG.takeSub), 1.5, true)
				Sounds.play("storm", { volume = 0.7 })
			else
				Banners.banner(Loc.fill(SG.take), col, nil, 3, true)
			end
			Sounds.play("egg_pick", { volume = 0.9 })
			local okF, errF = pcall(function()
				if toDragon then
					showDragonFx(p.from, p.d)
				else
					showRaidFx(p.from, p.out, p.home, p.gate, p.a, p.b, p.mid)
				end
			end)
			if not okF then
				warn("[Glow] raid fx: " .. tostring(errF))
			end
		elseif p.ev == "gate" then
			Banners.toast(Loc.fill(if p.mode == "dragon" then Strings.Raid.gateWait else SG.gateWait))
		elseif p.ev == "safe" then -- reached the dragon and mounted - "SAFE!", home by air; the pedestal - at the lot (ev home)
			clearRaidFx()
			Banners.banner(Loc.fill(SG.safe), Color3.fromRGB(90, 230, 110), Loc.fill(Strings.Raid.safeDragon), 3, true)
			Sounds.play("quest_done", { volume = 0.7 })
		elseif p.ev == "caught" then
			clearRaidFx()
			Banners.banner(Loc.fill(SG.caught), Color3.fromRGB(255, 92, 70), Loc.fill(SG.caughtSub), 3, true)
			Sounds.play("deny", { volume = 0.8 })
			local okA, errA = pcall(eggArc, p.from, p.to, tonumber(p.seconds) or 1)
			if not okA then
				warn("[Glow] egg arc: " .. tostring(errA))
			end
		elseif p.ev == "escaped" then
			Banners.toast(Loc.fill(SG.escaped))
		elseif p.ev == "handsFull" then
			Banners.toast(Loc.fill(SG.handsFull))
		elseif p.ev == "toShelf" then
			Banners.toast(Loc.fill(SG.toShelf))
		elseif p.ev == "guard" then
			Banners.banner(Loc.fill(SG.guard), Color3.fromRGB(196, 120, 255), nil, 3, true)
		elseif p.ev == "free" then
			Banners.banner(Loc.fill(SG.free), col, nil, 3, true)
		elseif p.ev == "home" then
			clearRaidFx()
			Banners.banner(Loc.fill(SG.safe), Color3.fromRGB(90, 230, 110), Loc.fill(SG.safeSub), 4, true) -- "SAFE!"
			Sounds.play("quest_done", { volume = 0.7 })
		elseif p.ev == "ready" then
			Banners.banner(Loc.fill(SG.ready), col, nil, 3, true)
		end
	end)
	-- the timer above the pedestal with the glowing egg ("Hatches in 19:59:59")
	-- under the timer two buttons - "Warm the egg -1 h for N coins" (Net GlowWarm; the price - the attribute
	-- WarmPrice of the pedestal, the server computes it from the pen income) and "Hatch now R$" (the shop's HatchNow ladder with the goal "glow")
	task.spawn(function()
		local me = Players.LocalPlayer
		type Board = { bb: BillboardGui, t: TextLabel, card: ScreenGui, frame: Frame, warm: TextButton, hn: TextButton, tier: number?, left: TextLabel }
		local SC = Config.Shop
		local function thousands(n: number): string
			local s = tostring(math.floor(n + 0.5))
			local out = (s:reverse():gsub("(%d%d%d)", "%1,")):reverse()
			return (out:gsub("^,", ""))
		end
		while true do
			for _, m in CollectionService:GetTagged("GlowPedestal") do
				if m:GetAttribute("OwnerId") == me.UserId and m:IsA("Model") and m.PrimaryPart and not boards[m] then
					local bb = Instance.new("BillboardGui")
					-- smaller, closer, not when mounted; the buttons - only nearby
					-- above the pedestal only
					-- a one-line timer, the "Hatch now" and "Warm the egg" buttons - in a side card at the right edge (UIKit.sideCard)
					bb.Size = UDim2.fromOffset(170, 34)
					bb.StudsOffsetWorldSpace = Vector3.new(0, 6.0, 0)
					bb.AlwaysOnTop = true
					bb.MaxDistance = 60
					bb.LightInfluence = 0
					bb.Adornee = m.PrimaryPart
					-- buttons in a BillboardGui receive taps only with Active = true and
					-- when the board lives in PlayerGui (like WorldUI.bb), not in a model in the world
					bb.Active = true
					bb.ResetOnSpawn = false
					bb.Name = "GlowBoard"
					local t = Instance.new("TextLabel")
					t.Size = UDim2.fromScale(1, 0.34)
					t.BackgroundTransparency = 1
					t.TextScaled = true
					t.Font = Enum.Font.FredokaOne
					t.TextColor3 = Color3.fromRGB(255, 200, 120)
					t.TextStrokeTransparency = 0.2
					t.Parent = bb
					-- 150x52 pt
					-- (phone 812x375), without the timer line (it is above the pedestal), two narrow buttons, at the right edge above the Keeper panel
					local card = UIKit.screen("GlowCard", 4)
					local cf = Instance.new("Frame")
					cf.Name = "Card"
					-- buttons 180x34 pt (text ~18 pt) on a light semi-transparent backing 192x80 pt - 22% of the width and 21% of the height of a phone
					cf.BackgroundColor3 = UIKit.PANEL
					cf.BackgroundTransparency = 0.45
					cf.Size = UDim2.fromOffset(192, 80)
					cf.AnchorPoint = Vector2.new(1, 0)
					cf.Position = UDim2.new(1, -8, 0, 52)
					UIKit.corner(cf, 0.14)
					cf.Parent = card
					card.Enabled = false
					-- the deadline large above the buttons - "Hatches in H:MM"
					local cl = Instance.new("TextLabel")
					cl.Name = "Left"
					cl.BackgroundTransparency = 1
					cl.Size = UDim2.new(1, -12, 0, 28)
					cl.Position = UDim2.new(0, 6, 0, 4)
					cl.Font = UIKit.FONT
					cl.TextScaled = true
					cl.TextColor3 = UIKit.GOLD
					cl.TextStrokeTransparency = 0.3
					cl.Parent = cf
					local warm = UIKit.button(cf, Strings.GlowEgg.warm, Color3.fromRGB(226, 150, 40), function(btn)
						local reply = Net.call("GlowWarm")
						if reply.ok then
							Sounds.play("stage_up")
						else
							UIKit.shake(btn)
							local why = reply.reason or ""
							if why == "not_enough" then
								Banners.toast(Loc.fill(Strings.Errors.not_enough, { n = tostring(reply.need or 0) }))
							elseif Strings.Errors[why] then
								Banners.toast(Loc.fill(Strings.Errors[why]))
							end
						end
					end, { minSize = Vector2.new(180, 34) })
					warm.Name = "Warm"
					warm.Visible = false
					warm.Position = UDim2.new(0, 6, 0, 42)
					warm.Size = UDim2.new(1, -12, 0, 34)
					local hn = UIKit.button(cf, Strings.Shop.hatchNow, Color3.fromRGB(80, 150, 230), function(btn)
						local shop = loadedRef and loadedRef.Shop
						if shop then
							shop.buy("HatchNow", "glow", nil)
						else
							UIKit.shake(btn)
						end
					end, { minSize = Vector2.new(180, 34) })
					hn.Name = "HatchNow"
					hn.Visible = false
					hn.Position = UDim2.new(0, 6, 0, 4)
					hn.Size = UDim2.new(1, -12, 0, 34)
					bb.Parent = me:WaitForChild("PlayerGui")
					boards[m] = { bb = bb, t = t, card = card, frame = cf, warm = warm, hn = hn, tier = nil, left = cl }
				end
			end
			for m, b in boards do
				if not m.Parent then
					b.bb:Destroy() -- the board is in PlayerGui: remove together with the pedestal
					b.card:Destroy()
					boards[m] = nil
				else
					local left = math.max(0, (tonumber(m:GetAttribute("ReadyAt")) or 0) - workspace:GetServerTimeNow())
					local h, mi, sec = math.floor(left / 3600), math.floor(left % 3600 / 60), math.floor(left % 60)
					b.t.Text = Loc.fill(Strings.GlowEgg.hatchIn, { t = string.format("%d:%02d:%02d", h, mi, sec) })
					-- mounted / in flight the board is not shown; the buttons - when you came close (<= 20) and stand on the ground
					local riding = me:GetAttribute("Mounted") ~= nil
					local root = me.Character and me.Character:FindFirstChild("HumanoidRootPart")
					local near = root ~= nil and root:IsA("BasePart") and m.PrimaryPart ~= nil and (root.Position - m.PrimaryPart.Position).Magnitude <= 20
					-- while a large banner
					-- is up, the board is not shown
					b.bb.Enabled = not riding and os.clock() >= (UIKit.bannerUntil or 0)
					local GW = G and G.egg and G.egg.warm
					local price = tonumber(m:GetAttribute("WarmPrice"))
					local showWarm = not riding and near and GW ~= nil and GW.on == true and price ~= nil and left >= (GW.minLeft or 60)
					b.warm.Visible = showWarm
					if showWarm then
						b.warm.Text = Loc.fill(Strings.GlowEgg.warmHint, { n = thousands(price :: number) }) -- short: "-1 h for 10,800 coins"
					end
					local shop = loadedRef and loadedRef.Shop
					local showHn = not riding and near and shop ~= nil and SC.hatchNowEnabled == true and left >= SC.hatchNow.minRemaining and shop.robuxAllowed()
					b.hn.Visible = showHn
					-- the card at the edge - only near the pedestal on foot, without a large banner and while there is something to press; the spot - above the Keeper panel
					-- and not over an open "Welcome gift" card (one request at a time)
					b.card.Enabled = (showWarm or showHn) and os.clock() >= (UIKit.bannerUntil or 0) and not UIKit.worldUiHidden
						and me.PlayerGui:FindFirstChild("FreeGiftCard") == nil
					if b.card.Enabled then
						-- visible buttons from the top in a row, the frame sized by their count, the frame bottom no lower than 8 pt above the Keeper panel
						b.left.Text = Loc.fill(Strings.GlowEgg.cardHatchIn, { t = string.format("%d:%02d", h, mi) })
						local y = 4 + 30
						for _, btn in { b.hn, b.warm } do
							if btn.Visible then
								btn.Position = UDim2.new(0, 6, 0, y)
								y += 38
							end
						end
						local h = y + 4 - 4
						b.frame.Size = UDim2.fromOffset(192, h)
						local pgQ = me.PlayerGui:FindFirstChild("Quests")
						local panel = if pgQ then pgQ:FindFirstChild("Panel") else nil
						if panel and panel:IsA("GuiObject") and panel.AbsoluteSize.Y > 1 and panel.Visible then
							b.frame.Position = UDim2.new(1, -8, 0, math.max(44, panel.AbsolutePosition.Y - h - 8))
						else
							b.frame.Position = UDim2.new(1, -8, 0, 52)
						end
					end
					if showHn then
						if shop.ticketFits("hatchNow", left) then
							b.hn.Text = Loc.fill(Strings.Shop.useTicket)
							b.tier = nil
						else
							local tier = #SC.hatchNow.prices
							for i, s in SC.hatchNow.steps do
								if left <= s then
									tier = i
									break
								end
							end
							if tier ~= b.tier then
								b.tier = tier
								local hnBtn = b.hn
								shop.contextPrice("hatchNow", left, function(txt: string)
									if hnBtn.Parent and hnBtn.Visible then
										hnBtn.Text = Loc.fill(Strings.Shop.hatchNow) .. "  " .. txt
									end
								end)
							end
						end
					else
						b.tier = nil
					end
				end
			end
			task.wait(1)
		end
	end)
	if not G then
		return
	end
	local f = ReplicatedStorage:WaitForChild("GlowTemplates", 30)
	if not f or not f:IsA("Folder") then
		warn("[Glow] no ReplicatedStorage.GlowTemplates - glow is off")
		return
	end
	templates = f
	for _, t in f:GetChildren() do
		local tex = t:GetAttribute("Texture")
		local key = string.match(t.Name, "^(.-)|")
		if typeof(tex) == "string" and key then
			byTexture[tex] = key
		end
	end
	LogService.MessageOut:Connect(function(msg)
		if string.find(msg, "GlowSA", 1, true) then
			pcall(onLog, msg)
		end
	end)
	dcRef = ReplicatedStorage:WaitForChild("DayCycle", 60)
	task.spawn(function()
		local last = -1
		while true do
			local f = factor()
			if math.abs(f - last) > 0.004 or (f == 0 and last ~= 0) or (f == 1 and last ~= 1) then -- the extremes 0 and 1 always exactly
				last = f
				for d in parts do
					local g = d.Parent and d:FindFirstChild("GlowSA")
					if g then
						pcall(shade, g, f)
					end
				end
			end
			task.wait(0.2)
		end
	end)
	local n = 0
	while true do
		scan()
		n += 1
		if n % 3 == 0 then
			pcall(retryFailed)
		end
		if n % 5 == 0 then
			pcall(diag)
		end
		task.wait(G.scanEvery or 2)
	end
end

return Glow
