--!strict
-- 2.9: live ops (spec 09 §1-3). The updates from Content.Updates switch on by date by themselves (Core/LiveOps.live)
-- the number of running updates - the attribute ReplicatedStorage.UpdatesLive (the client: the quest count, the scrolls). On switching on on a live
-- server - an announcement to everyone and new quests opened (Quest.advance). The quest scrolls 16-20 "The Great Egg": five notes in
-- the world (Config.LiveOps.scrolls; placed only while update 1 runs, hidden), seen and taken only by the one whose current quest it is
-- (the client Controllers/LiveOps shows it only to himself; the server checks the step and the distance). The codes of the week (Content.Codes): Settings -> Code, Remote Code, once per profile,
-- the reward - minutes of income. Studio: ServerStorage.LiveOpsDebug:Invoke("update N" | "offset S" | "state").

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local LiveOpsCore = require(Core:WaitForChild("LiveOps"))
local Quests = require(Core:WaitForChild("Quests"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Economy = require(Core:WaitForChild("Economy"))
local IndexCore = require(Core:WaitForChild("Index"))

local LiveOps = {}

local services: { [string]: any } = {}
local L = Config.LiveOps
local S = L.scrolls
local T = Strings.LiveOps
local offset = 0 -- Studio only: a clock shift to check updates before their date
local live = 0
local scrolls: { BasePart } = {}
local scrollsBuilt = false -- the scrolls are placed only while their update runs (before the date they are not in the world)
local scrollBuilt: { [number]: boolean } = {} -- chapters 2 and 4 are added on their own dates
local scrollFolder: Folder? = nil


local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

-- the live ops clock (in the game - os.time(); in Studio it can be shifted)
function LiveOps.now(): number
	return os.time() + offset
end

-- how many updates run now (0 - D0)
function LiveOps.live(): number
	return live
end

-- scroll n closes the quest with the event scrollN (chapters 1, 2, 4 - quests 16-20, 21-25, 31-35)
local function scrollStep(n: number): number
	for _, q in Quests.List do
		if q.event == "scroll" .. n then
			return q.id
		end
	end
	return 0
end

-- ---------------------------------------------------------------------------------------------- scrolls
local function groundY(x: number, z: number, near: number): number
	local root = services.WorldBuilder and services.WorldBuilder.root
	local skip: { Instance } = {}
	if root then
		for _, name in { "EggPoints", "Zones", "Bounds", "Clouds", "WindRings", "Coins", "Scrolls" } do
			local f = root:FindFirstChild(name)
			if f then
				table.insert(skip, f)
			end
		end
	end
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(skip, p.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = skip
	local hit = workspace:Raycast(Vector3.new(x, near + 40, z), Vector3.new(0, -80, 0), params)
	-- the egg spots stand ON a surface (the bath rim, the ledge): noticeably below the anchor - a miss past the mesh (still loading) - hang at the anchor
	if hit and hit.Position.Y >= near - 1.5 and hit.Position.Y <= near + S.maxDrop then
		return hit.Position.Y
	end
	return near
end

local function scrollAnchor(at: string): Vector3?
	if at == "stall" then
		local st = Config.World.stall
		return Vector3.new(st.x, st.y, st.z)
	end
	local wb = services.WorldBuilder
	local p = wb and wb.getEggPoint and wb.getEggPoint(at)
	return if p then p.Position else nil
end

-- a scroll: parchment (a cylinder + two sticks), a warm glow, a light pillar, the Read button; the client shows only the needed one
local function buildScroll(n: number, pos: Vector3, parent: Instance): BasePart
	local m = Instance.new("Model")
	m.Name = "Scroll" .. n
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent -- streaming: a scroll on the other edge of the island exists on the client too (the 📜 icon)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(1.8, 0.7, 0.7)
	body.Color = rgb(S.color)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 1 -- hidden by default, shown only by the client (Controllers/LiveOps) to the needed player
	body.Anchored = true
	body.CanCollide = false
	body.CanTouch = false
	body.CanQuery = false
	body.CastShadow = false
	body.CFrame = CFrame.new(pos + Vector3.new(0, S.lift, 0))
	for i, x in { -1, 1 } do
		local rod = Instance.new("Part")
		rod.Name = "Rod" .. i
		rod.Shape = Enum.PartType.Cylinder
		rod.Size = Vector3.new(0.25, 0.85, 0.85)
		rod.Color = Color3.fromRGB(120, 78, 44)
		rod.Material = Enum.Material.Wood
		rod.Transparency = 1
		rod.Anchored = true
		rod.CanCollide = false
		rod.CanTouch = false
		rod.CanQuery = false
		rod.CastShadow = false
		rod.CFrame = body.CFrame * CFrame.new(x * 1.0, 0, 0)
		rod.Parent = body
	end
	local light = Instance.new("PointLight")
	light.Color = rgb(S.glow)
	light.Range = 10
	light.Brightness = 1.5
	light.Enabled = false
	light.Parent = body
	-- a light pillar from the ground up (Neon, semi-transparent) - visible from afar
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(S.beam, 1.2, 1.2)
	beam.CFrame = CFrame.new(pos + Vector3.new(0, S.beam / 2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Color = rgb(S.glow)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 1
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Parent = body
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Read"
	prompt.ActionText = T.read
	prompt.ObjectText = T.noteObject
	prompt.MaxActivationDistance = S.promptDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.Parent = body
	m:SetAttribute("Scroll", n)
	m:SetAttribute("Step", scrollStep(n))
	prompt.Triggered:Connect(function(player: Player)
		LiveOps.readScroll(player, n)
	end)
	body.Parent = m
	m.PrimaryPart = body
	m.Parent = parent
	return body
end

-- world parts near the anchor (and decor without queries: the raycast does not see it - otherwise a scroll sinks into a rock)
local SKIP_FOLDERS = { EggPoints = true, Zones = true, Bounds = true, Clouds = true, WindRings = true, Coins = true, Scrolls = true }
local function partsNear(root: Instance, c: Vector3, r: number): { BasePart }
	local out = {}
	local function walk(inst: Instance)
		for _, ch in inst:GetChildren() do
			if not (ch:IsA("Folder") and SKIP_FOLDERS[ch.Name]) then
				if ch:IsA("BasePart") and ch.Transparency < 1 and (ch.Position - c).Magnitude <= r + ch.Size.Magnitude / 2 then
					table.insert(out, ch)
				end
				walk(ch)
			end
		end
	end
	walk(root)
	return out
end

-- the distance from a point to a part's box (0 - inside)
local function boxDist(p: BasePart, at: Vector3): number
	local l = p.CFrame:PointToObjectSpace(at)
	local h = p.Size / 2
	local d = Vector3.new(math.max(math.abs(l.X) - h.X, 0), math.max(math.abs(l.Y) - h.Y, 0), math.max(math.abs(l.Z) - h.Z, 0))
	return d.Magnitude
end

-- the scroll spot at the anchor: a sweep of rings (Config.LiveOps.scrolls.rings x 12 directions), the ground at the anchor level, the farthest from
-- parts (no closer than eggGap to the anchor itself - the egg is there); preference to the near ring and the off shift from the config
local function pickSpot(a: Vector3, sp: any, root: Instance): Vector3
	local near = partsNear(root, a, 30)
	local best, bestScore = nil :: Vector3?, -math.huge
	local pref = Vector3.new(sp.off[1], 0, sp.off[3])
	for _, r in S.rings do
		for k = 0, 11 do
			local ang = k * math.pi / 6
			local x, z = a.X + math.cos(ang) * r, a.Z + math.sin(ang) * r
			local y = groundY(x, z, a.Y)
			local at = Vector3.new(x, y + S.lift, z)
			local clear = 99
			for _, p in near do
				clear = math.min(clear, boxDist(p, at))
			end
			local flat = Vector3.new(x - a.X, 0, z - a.Z)
			local score = math.min(clear, S.clearWant) - r * 0.05 - (flat - pref).Magnitude * 0.02
			if flat.Magnitude >= S.eggGap and score > bestScore then
				best, bestScore = Vector3.new(x, y, z), score
			end
		end
	end
	return best or Vector3.new(a.X + sp.off[1], groundY(a.X + sp.off[1], a.Z + sp.off[3], a.Y), a.Z + sp.off[3])
end

local function buildScrolls()
	if scrollsBuilt then
		return
	end
	scrollsBuilt = true -- busy for the duration of the build
	local root = services.WorldBuilder and services.WorldBuilder.root
	local f = scrollFolder or Instance.new("Folder")
	scrollFolder = f
	f.Name = "Scrolls"
	local t0 = os.clock() -- the decor is placed by its own service (the attribute World.DecorModels at the end) - wait to go around its rocks
	while root and Config.World.decor and Config.World.decor.enabled ~= false and root:GetAttribute("DecorModels") == nil and os.clock() - t0 < 60 do
		task.wait(1)
	end
	for n, sp in S.points do
		if scrollBuilt[n] or (sp.update or 1) > live then
			continue
		end
		scrollBuilt[n] = true
		local a = scrollAnchor(sp.at)
		if a then
			scrolls[n] = buildScroll(n, pickSpot(a, sp, root or workspace), f)
		else
			warn("[LiveOps] scroll " .. n .. ": no anchor " .. tostring(sp.at))
		end
	end
	f.Parent = root or workspace
	scrollsBuilt = false
end

-- the player read scroll n: only if it is his current quest (16..20) and he is near
function LiveOps.readScroll(player: Player, n: number)
	local data = services.PlayerData.get(player)
	local step = data and data.quests and data.quests.keeper and data.quests.keeper.step
	local q = Quests.get(scrollStep(n), live)
	if not q or step ~= q.id then
		return
	end
	local part = scrolls[n]
	local pos = services.Nest.rootPos(player)
	if not part or not pos or (pos - part.Position).Magnitude > S.promptDistance + 6 then
		return
	end
	if services.Quest then
		services.Quest.event(player, "scroll" .. n)
	end
	local note = Content.Notes[n]
	if note then -- the Done! banner (Quest.advance) would cover the note a frame later - the note goes after it
		task.delay(Config.Quests.chainDelay + S.noteDelay, function()
			if player.Parent == Players then
				services.Net.notice(player, { kind = "announce", text = note, sub = Loc.text(T.noteOf, { n = ((n - 1) % 5) + 1, total = 5 }) }) -- the number within the chapter
			end
		end)
	end
end

-- ---------------------------------------------------------------------------------------------- the codes of the week
local function nestRate(data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) }
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, Config.Balance)
end

function LiveOps.redeem(player: Player, raw: string): { ok: boolean, reason: string?, coins: number? }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local code = LiveOpsCore.normCode(raw)
	local def, why = LiveOpsCore.codeCheck(Content.Codes, Content.Updates, code, LiveOps.now(), data.codes)
	if not def then
		return { ok = false, reason = why }
	end
	local coins = math.max(Config.Quests.minMinutesReward, math.floor(nestRate(data) * 60 * def.minutes))
	services.PlayerData.update(player, "codes", function(c)
		local t = if typeof(c) == "table" then c else {}
		t[code] = os.time()
		return t
	end)
	services.Nest.addCoins(player, coins, "Code")
	if services.Analytics then
		services.Analytics.custom(player, "code_redeem", 1, { code = code })
	end
	services.Net.notice(player, { kind = "reward", title = Loc.text(T.codeDone, { code = code }), coins = coins, color = "daily" })
	return { ok = true, coins = coins }
end

-- ---------------------------------------------------------------------------------------------- the update date
local function ensureScrolls()
	local want = false
	for n, sp in S.points do
		if not scrollBuilt[n] and (sp.update or 1) <= live then
			want = true
		end
	end
	if want and not scrollsBuilt then
		task.spawn(function()
			local ok, err = pcall(buildScrolls)
			if not ok then
				warn("[LiveOps] scrolls: " .. tostring(err))
			end
		end)
	end
end

local function poll()
	local n = LiveOpsCore.live(Content.Updates, LiveOps.now())
	if n == live then
		return
	end
	local was = live
	live = n
	ReplicatedStorage:SetAttribute("UpdatesLive", n)
	ReplicatedStorage:SetAttribute("LiveOffset", offset) -- the client (the shop) computes the Dragon of the Week window by the same clock
	local u = Content.Updates[n]
	ReplicatedStorage:SetAttribute("UpdateTitle", if u then u.title else "")
	if n > was and was >= 0 and #Players:GetPlayers() > 0 and u then
		services.Net.noticeAll({ kind = "announce", text = Loc.text(T.updateLive, { title = u.title }), sub = if u.quests then T.updateSub else nil }) -- updates 2-4 have no quests
	end
	ensureScrolls()
	if services.Quest then -- new quests opened: those who waited for "More tales next week" get the next one
		for _, p in Players:GetPlayers() do
			task.spawn(services.Quest.advance, p)
		end
	end
end

local function debugCmd(cmd: string): string
	local word, arg, arg2 = string.match(cmd, "^(%S+)%s*(%S*)%s*(%S*)")
	local p1 = Players:GetPlayers()[1]
	if p1 and word == "step" then -- the Keeper's quest N for the first player
		services.PlayerData.update(p1, "quests", function(qd)
			qd.keeper.step = tonumber(arg) or qd.keeper.step
			return nil
		end)
		return "step " .. tostring(arg)
	elseif p1 and word == "go" then -- to scroll N (3 studs to the side)
		local sc = scrolls[tonumber(arg) or 0]
		local ch = p1.Character
		if sc and ch then
			ch:PivotTo(CFrame.new(sc.Position + Vector3.new(3, 1, 0)))
			if services.AntiCheat then -- a server relocation (probes with the protection on)
				services.AntiCheat.moved(p1)
			end
		end
		return "go " .. tostring(arg)
	elseif p1 and word == "read" then
		LiveOps.readScroll(p1, tonumber(arg) or 0)
		return "read " .. tostring(arg)
	elseif p1 and word == "egg" then -- an egg of element arg from zone arg2 into the hands (Glacier: egg frost Summit)
		local data = services.PlayerData.get(p1)
		local Eggs = require(Core:WaitForChild("Eggs"))
		local rng = Random.new()
		local egg: any = Eggs.rollGuaranteed("lo", arg2, "Common", function()
			return rng:NextNumber()
		end, Config.Balance, Config.Elements, arg)
		egg.zone = arg2
		egg.foundAt = os.time()
		if data then
			services.PlayerData.update(p1, "eggs", function(e)
				e.carry = egg
				return nil
			end)
			services.EggSpawner.showCarry(p1, egg)
		end
		return "egg " .. tostring(egg.element) .. " " .. tostring(egg.zone) .. " " .. tostring(egg.rarity)
	elseif p1 and word == "code" then
		local r = LiveOps.redeem(p1, arg)
		return "code " .. tostring(r.ok) .. "/" .. tostring(r.reason) .. "/" .. tostring(r.coins)
	elseif word == "update" then
		local k = tonumber(arg) or 0
		local u = Content.Updates[k]
		offset = if u then u.activeFrom - os.time() + 5 else 0
		ReplicatedStorage:SetAttribute("LiveOffset", offset) -- the client (the quest week, the shop) - the same clock and without changing live
		poll()
	elseif word == "offset" then
		offset = tonumber(arg) or 0
		ReplicatedStorage:SetAttribute("LiveOffset", offset)
		poll()
	end
	local where = {}
	for n, p in scrolls do
		table.insert(where, string.format("%d@%.0f,%.0f,%.0f", n, p.Position.X, p.Position.Y, p.Position.Z))
	end
	return string.format("live=%d offset=%d now=%s scrolls=%s", live, offset, os.date("!%Y-%m-%d %H:%M", LiveOps.now()) :: string, table.concat(where, " "))
end

function LiveOps.init(s: { [string]: any })
	services = s
	live = LiveOpsCore.live(Content.Updates, LiveOps.now())
	ReplicatedStorage:SetAttribute("UpdatesLive", live)
	local u = Content.Updates[live]
	ReplicatedStorage:SetAttribute("UpdateTitle", if u then u.title else "")
	if RunService:IsStudio() then
		local bf = Instance.new("BindableFunction")
		bf.Name = "LiveOpsDebug"
		bf.OnInvoke = debugCmd
		bf.Parent = ServerStorage
	end
end

function LiveOps.start()
	services.Net.handle("Code", function(player: Player, code: string)
		return LiveOps.redeem(player, code)
	end)
	ensureScrolls()
	while true do
		task.wait(L.pollSeconds)
		local ok2, err2 = pcall(poll)
		if not ok2 then
			warn("[LiveOps] poll: " .. tostring(err2))
		end
	end
end

return LiveOps
