--!strict
-- Frame measurement for admins (and in Studio). Every second - frames per second; every Config.Admin.perf.every s to the server (Remote Perf):
-- the window's average FPS, the worst second, client memory (Stats), dragons in the world (tag Dragon), the screen "WxH t|m" (t - touch). The server
-- writes the PerfLog_v1 journal (cloud_test.py perflog_read); Settings shows the last average next to the build number.
-- detail: the day phase and memory by kind (Stats:GetMemoryUsageMbForTag) -
-- textures, meshes, parts, terrain, physics, Lua, instances.
-- The "Perf test" experiment: a minute per mode, on the own client one
-- expensive thing is switched off (base - everything as is; post - light effects except color correction; shadows - shadows; far - decor beyond
-- Config.Admin.perf.test.far studs; water - waves and water glints; all - everything at once), the measurement window resets on a mode change,
-- the journal line has "m=<mode>". Terrain grass (Terrain.Decoration) is not available to scripts - not part of the experiment.
-- The second experiment: base - decor as before, lod / lod2 - DecorLod levels, lodsh - lod without shadows.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))

local Perf = {}

local P = Config.Admin.perf
local me = Players.LocalPlayer
local Lighting = game:GetService("Lighting")
local lastAvg: number? = nil
local banners: any = nil
local decorLod: any = nil -- the distant decor levels (Controllers/DecorLod) for the modes lod / lod2 / lodsh

-- the Perf test experiment: the current mode, the step, the rollback of local changes
local mode = "-"
local step = 0
local testOn = false
local resetWindow = false
local undo: { () -> () } = {}

-- memory by kind, MB: short names -> DeveloperMemoryTag (missing in this version - skipped)
local TAGS = { { "tex", "GraphicsTexture" }, { "msh", "GraphicsMeshParts" }, { "prt", "GraphicsParts" }, { "trn", "GraphicsTerrain" },
	{ "vox", "TerrainVoxels" }, { "phc", "PhysicsCollision" }, { "php", "PhysicsParts" }, { "lua", "LuaHeap" }, { "ins", "Instances" },
	{ "gui", "Gui" }, { "anm", "Animation" }, { "snd", "Sounds" }, { "scr", "Script" }, { "int", "Internal" } } -- script bytecode and "engine without a tag" (on the phone ~900 MB of 1,500)

-- who in PlayerGui paints the left screen edge at full height - the lines
-- "gu=j ..." (the first seconds after the start) and "gu=m ..." (after the first movement) go to the journal instead of detail(); CoreGui
-- (chat, thumbstick) is not visible to the client - if the list is empty, Roblox draws the rectangle
local pendingCensus: { string } = {}

local function paints(o: GuiObject): string?
	local tag: string? = nil
	if o.BackgroundTransparency < 0.98 then
		tag = "b" .. math.floor(o.BackgroundTransparency * 10)
	end
	if (o:IsA("ImageLabel") or o:IsA("ImageButton") or o:IsA("ViewportFrame")) and (o :: any).ImageTransparency < 0.98 then
		tag = (tag or "") .. "i" .. math.floor((o :: any).ImageTransparency * 10)
	end
	if o:IsA("CanvasGroup") and o.GroupTransparency < 0.98 then
		tag = (tag or "") .. "g" .. math.floor(o.GroupTransparency * 10)
	end
	return tag
end

local function shown(o: GuiObject): boolean
	local x: Instance? = o
	while x and not x:IsA("LayerCollector") do
		if x:IsA("GuiObject") and not x.Visible then
			return false
		end
		x = x.Parent
	end
	return x ~= nil and (x :: LayerCollector).Enabled
end

local function censusScan(found: { [string]: string })
	local cam = workspace.CurrentCamera
	local pg = me:FindFirstChildOfClass("PlayerGui")
	if not cam or not pg then
		return
	end
	local vp = cam.ViewportSize
	if vp.X <= 0 or vp.Y <= 0 then
		return
	end
	local C = P.census
	for _, o in pg:GetDescendants() do
		if o:IsA("GuiObject") then
			local sz, ps = o.AbsoluteSize, o.AbsolutePosition
			if sz.X >= C.minW * vp.X and sz.Y >= C.minH * vp.Y and ps.X <= C.maxX * vp.X and shown(o) then
				local tag = paints(o)
				if tag then
					local gui = o:FindFirstAncestorWhichIsA("LayerCollector")
					local key = (if gui then gui.Name else "?") .. "/" .. o.Name
					found[key] = string.format("%s:%d,%d,%d,%d,%s", key, math.floor(100 * ps.X / vp.X), math.floor(100 * ps.Y / vp.Y), math.floor(100 * sz.X / vp.X), math.floor(100 * sz.Y / vp.Y), tag)
				end
			end
		end
	end
end

local function censusWindow(label: string, seconds: number)
	local found: { [string]: string } = {}
	local t0 = os.clock()
	local scans = 0
	while os.clock() - t0 < seconds do
		pcall(censusScan, found)
		scans += 1
		task.wait(P.census.step)
	end
	local list = {}
	for _, v in found do
		table.insert(list, v)
	end
	table.sort(list)
	table.insert(pendingCensus, string.sub(string.format("gu=%s n%d s%d %s", label, #list, scans, table.concat(list, " ")), 1, 160))
end

local function censusStart()
	local C = P.census
	if not C then
		return
	end
	task.spawn(censusWindow, "j", C.seconds)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < C.waitMove do
			local ch = me.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			if hum and hum.MoveDirection.Magnitude > 0 then
				censusWindow("m", C.moveSeconds)
				return
			end
			task.wait(0.1)
		end
	end)
end

-- what the client sees - Gloom (models:meshes:not loaded)
-- the own companion (parts:not loaded:hidden by LocalTransparencyModifier), the own wave (the Gloom_meadow attribute)
local function meshFails(m: Instance): (number, number, number)
	local n, bad, hid = 0, 0, 0
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") then
			n += 1
			local ok, st = pcall(function()
				return game:GetService("ContentProvider"):GetAssetFetchStatus(d.MeshId)
			end)
			if ok and st == Enum.AssetFetchStatus.Failure then
				bad += 1
			end
			if d.LocalTransparencyModifier >= 1 then
				hid += 1
			end
		end
	end
	return n, bad, hid
end
local function seen(): string
	local me = Players.LocalPlayer
	local gm, gn, gb = 0, 0, 0
	for _, m in CollectionService:GetTagged("Gloom") do
		gm += 1
		local n, b = meshFails(m)
		gn += n
		gb += b
	end
	local cp = "-"
	for _, m in CollectionService:GetTagged("Companion") do
		if m:GetAttribute("OwnerId") == me.UserId then
			local n, b, h = meshFails(m)
			cp = string.format("%d:%d:%d", n, b, h)
		end
	end
	local wv = me:GetAttribute("Gloom_meadow")
	return string.format("gl=%d:%d:%d cp=%s wv=%s", gm, gn, gb, cp, if typeof(wv) == "string" then (string.match(wv, "^[^|]*|[^|]*") or "?") else "-")
end

local function detail(): string
	local parts: { string } = { "m=" .. mode }
	local okS, sv = pcall(seen)
	table.insert(parts, if okS then sv else "seen=err")
	local dc = ReplicatedStorage:FindFirstChild("DayCycle")
	table.insert(parts, "ph=" .. tostring(dc and dc:GetAttribute("Phase") or "?"))
	-- the loading screen - after how many seconds the 3D hatchling appeared (none / bad / late / err - did not appear), Main.client
	table.insert(parts, "sp=" .. tostring(game:GetService("ReplicatedFirst"):GetAttribute("Splash3D") or "-"))
	-- the Lua heap of OUR VM in MB (gcinfo - kilobytes); the lua= tag also counts Roblox CoreScripts (it varies a lot between
	-- phones without changing the game) - gc= shows how much of that is ours
	table.insert(parts, string.format("gc=%d", math.floor(gcinfo() / 1024 + 0.5)))
	-- memory by tag only when tracking is on - otherwise every call wrote the warning "Memory tracking is currently disabled"
	-- (hundreds per night in the Error report); Stats.MemoryTrackingEnabled is a read-only property (docs)
	local okT, tracking = pcall(function()
		return (Stats :: any).MemoryTrackingEnabled
	end)
	if okT and tracking == true then
		for _, t in TAGS do
			local ok, mb = pcall(function()
				return Stats:GetMemoryUsageMbForTag((Enum.DeveloperMemoryTag :: any)[t[2]])
			end)
			if ok and typeof(mb) == "number" then
				table.insert(parts, string.format("%s=%d", t[1], math.floor(mb + 0.5)))
			end
		end
	end
	return string.sub(table.concat(parts, " "), 1, 160)
end

local function isOwner(): boolean
	if RunService:IsStudio() then
		return true
	end
	if game.CreatorType == Enum.CreatorType.User then
		return Config.Admin.enabled and game.CreatorId == me.UserId
	end
	return Config.Admin.enabled and table.find(Config.AdminUserIds, me.UserId) ~= nil -- the game belongs to a group - admins come from the Config list
end

-- an action note in the Perf journal - goes as the next Perf line instead of
-- detail() (like the gu= census); text is short (act=fly:ok/0.1 modal=-), the tail - the usual detail()
function Perf.note(text: string)
	if not isOwner() then
		return
	end
	table.insert(pendingCensus, string.sub(text .. " " .. detail(), 1, 160))
end

-- the last average FPS of the window
function Perf.lastFps(): number?
	return lastAvg
end

local function restore()
	for i = #undo, 1, -1 do
		pcall(undo[i])
	end
	undo = {}
end

local function setLocal(inst: Instance, prop: string, value: any)
	local ok, old = pcall(function()
		return (inst :: any)[prop]
	end)
	if not ok or old == value then
		return
	end
	if pcall(function()
		(inst :: any)[prop] = value
	end) then
		table.insert(undo, function()
			(inst :: any)[prop] = old
		end)
	end
end

-- one experiment mode (the rest as it was); changes only locally, nothing goes to the server
local function apply(m: string)
	restore()
	if decorLod and (m == "base" or m == "lod" or m == "lod2" or m == "lodsh") then
		local was = decorLod.level()
		decorLod.setLevel(if m == "base" then "off" elseif m == "lod2" then "strong" else "normal")
		table.insert(undo, function()
			decorLod.setLevel(was)
		end)
	end
	if m == "lodsh" then
		setLocal(Lighting, "GlobalShadows", false)
	end
	if m == "post" or m == "all" then
		local cam = workspace.CurrentCamera
		for _, root in { Lighting :: Instance, cam :: Instance } do
			if root then
				for _, e in root:GetDescendants() do
					if e:IsA("PostEffect") and not e:IsA("ColorCorrectionEffect") then
						setLocal(e, "Enabled", false)
					end
				end
			end
		end
	end
	if m == "shadows" or m == "all" then
		setLocal(Lighting, "GlobalShadows", false)
	end
	if m == "far" or m == "all" then
		local cam = workspace.CurrentCamera
		local world = workspace:FindFirstChild("World")
		local meshes = world and world:FindFirstChild("Meshes")
		if cam and meshes then
			local pos = cam.CFrame.Position
			for _, p in meshes:GetDescendants() do
				if p:IsA("BasePart") and (p.Position - pos).Magnitude > P.test.far then
					setLocal(p, "LocalTransparencyModifier", 1)
				end
			end
		end
	end
	if m == "water" or m == "all" then
		local T = workspace.Terrain
		setLocal(T, "WaterWaveSize", 0)
		setLocal(T, "WaterWaveSpeed", 0)
		setLocal(T, "WaterReflectance", 0)
	end
end

-- is the experiment running? the step and the total steps
function Perf.testState(): (boolean, number, number)
	return testOn, step, #P.test.modes
end

function Perf.stopTest()
	testOn = false
	restore()
	mode, step = "-", 0
	resetWindow = true
end

-- start the experiment: P.test.seconds per mode, then everything as it was and a toast
function Perf.startTest(): boolean
	if testOn or not P.on or not isOwner() then
		return false
	end
	testOn = true
	if banners then
		banners.toast(Loc.fill(Strings.Menu.perfStart, { n = math.ceil(#P.test.modes * P.test.seconds / 60) }))
	end
	task.spawn(function()
		for i, m in P.test.modes do
			if not testOn then
				return
			end
			apply(m)
			mode, step = m, i
			resetWindow = true
			task.wait(P.test.seconds)
		end
		if testOn then
			Perf.stopTest()
			if banners then
				banners.toast(Strings.Menu.perfDone)
			end
		end
	end)
	return true
end

function Perf.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	decorLod = loaded.DecorLod
end

function Perf.start()
	if not P.on or not isOwner() then
		return
	end
	censusStart()
	local frames, acc = 0, 0
	local window: { number } = {}
	RunService.RenderStepped:Connect(function(dt)
		frames += 1
		acc += dt
		if acc >= 1 then
			table.insert(window, frames / acc)
			frames, acc = 0, 0
		end
	end)
	task.spawn(function()
		while true do
			-- a window of P.every s; an experiment mode change resets the window and the count (the line holds frames of one mode)
			local t0 = os.clock()
			while os.clock() - t0 < P.every and not resetWindow do
				task.wait(0.25)
			end
			if resetWindow then
				resetWindow = false
				window = {}
				frames, acc = 0, 0
				continue
			end
			if #window > 0 then
				local sum, low = 0, math.huge
				for _, f in window do
					sum += f
					low = math.min(low, f)
				end
				local avg = sum / #window
				window = {}
				lastAvg = avg
				local cam = workspace.CurrentCamera
				local vp = if cam then cam.ViewportSize else Vector2.zero
				local screen = string.format("%dx%d %s", math.floor(vp.X), math.floor(vp.Y), if UserInputService.TouchEnabled then "t" else "m")
				local r = ReplicatedStorage:FindFirstChild("Remotes")
				local ev = r and r:FindFirstChild("Perf")
				if ev and ev:IsA("RemoteEvent") then
					ev:FireServer(math.clamp(avg, 0, 1000), math.clamp(low, 0, 1000), math.clamp(Stats:GetTotalMemoryUsageMb(), 0, 100000), #CollectionService:GetTagged("Dragon"), screen, if #pendingCensus > 0 then table.remove(pendingCensus, 1) else detail())
				end
			end
		end
	end)
end

return Perf
