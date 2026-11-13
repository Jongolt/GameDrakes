--!strict
-- Newcomer hints: every half second we take a snapshot of the state (Store + world tags and attributes), the core
-- Core/Hints picks the target. If the step is not done within Config.HintDelaySeconds (the first time for each step) - from the feet to the target
-- runs a chain of golden chevrons on the ground with a running shimmer (parts, no images),
-- the target gets a Highlight (only while the hint is visible) and an arrow glyph with the distance above it. Above
-- the needed HUD button - the same glyph. The step line - in StepBanner.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Core = Shared:WaitForChild("Core")
local HintsCore = require(Core:WaitForChild("Hints"))
local RaidLoop = require(Core:WaitForChild("RaidLoop")) -- raid rings

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))

local Hints = {}

local C = Config.Hints
local me = Players.LocalPlayer
local hud: any = nil
local banners: any = nil
local stepBanner: any = nil
local timer = HintsCore.newTimer()
local active: { kind: string, slot: number?, hl: Highlight?, arrow: BillboardGui?, arrow2d: GuiObject?, target: BasePart? }? = nil
local warned = false

local TEXT = { table = "goTable", incubator = "toIncubator", hatch = "tapHatch", pile = "collectPile", egg = "findEgg", feed = "feedHint", ride = "rideHint", fly = "takeOffHint", ring = "windRings", gloom = "gloomHint", guardian = "guardianHint", sky = "gloomHint", skyUp = "skyHint", warm = "warmHint", stall = "stallHint" } -- warm / stall
-- 1.9: the show delay per step (s); default Config.HintDelaySeconds. In the air the chain to the ring at once, takeoff - after 3 s
local DELAY = { ring = 0, fly = 3, companion = 3, table = 0, gloom = 2, guardian = 0, sky = 0, skyUp = 3, raid = 0, raidFirst = 0, raidWait = 0, raidHome = 0, raidDragon = 0, raidRide = 0, warm = 1, stall = 2 } -- the raid arrow at once -- companion - the dragon grew in the nest; table 0 (first-10-minutes audit: 10 s without an arrow at the start); combat (spec 19)
local fly: any = nil
local companion: any = nil
local combat: any = nil -- the BREATH button for the FIGHT step arrow
local goalTarget: BasePart? = nil -- P34: the current step target for the distance on the banner (StepBanner), updated every tick

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function root(): BasePart?
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function myNest(): Model?
	for _, r in CollectionService:GetTagged("Incubator") do
		if r:GetAttribute("OwnerId") == me.UserId then
			local m = r.Parent and r.Parent.Parent
			if m and m:IsA("Model") then
				return m
			end
		end
	end
	return nil
end

local function visible(m: Instance): boolean
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.99 then
			return true
		end
	end
	return false
end

local function basePart(m: Instance?): BasePart?
	if not m then
		return nil
	end
	if m:IsA("BasePart") then
		return m
	end
	if m:IsA("Model") then
		return m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart", true)
	end
	return m:FindFirstChildWhichIsA("BasePart", true)
end

-- the free table eggs of the own nest (the server hides taken ones by transparency; fading ones are marked Fading)
local function tableEggs(nest: Model): { Model }
	local out = {}
	local t = nest:FindFirstChild("EggTable")
	if t then
		for _, c in t:GetChildren() do
			if c:IsA("Model") and not c:GetAttribute("Fading") and visible(c) then
				table.insert(out, c)
			end
		end
	end
	return out
end

local function ring(nest: Model, slot: number): BasePart?
	local inc = nest:FindFirstChild("Incubators")
	local r = inc and inc:FindFirstChild("Incubator" .. slot)
	return if r and r:IsA("BasePart") then r else nil
end

local function nearestEgg(pos: Vector3): (Model?, number)
	local best: Model? = nil
	local bestD = C.eggRadius
	for _, a in CollectionService:GetTagged("EggPoint") do
		local egg = a:FindFirstChild("Egg")
		if egg and egg:IsA("Model") and a:IsA("BasePart") and not a:GetAttribute("Secret") then -- the hints do not give away the secret grotto
			local d = (a.Position - pos).Magnitude
			if d < bestD then
				best, bestD = egg, d
			end
		end
	end
	return best, bestD
end

local function feedTarget(): (Model?, number?)
	local best: Model? = nil
	local price: number? = nil
	local soon = Config.Combat.hunt and Config.Combat.hunt.growHint or 0
	for _, m in CollectionService:GetTagged("CanFeed") do
		-- the dragon grows anyway earlier than growHint s (a firstborn teen - 1 min) - no FEED step on it
		local ends = m:GetAttribute("StageEndsAt") :: number?
		if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and not (ends and ends - os.time() <= soon) then
			local p = (m:GetAttribute("FeedPrice") :: number?) or math.huge
			if not price or p < price then
				best, price = m, p
			end
		end
	end
	return best, price
end

-- the Gloom nest for the raid step - the nearest with an egg in the farthest open ring where an egg exists; all empty -
-- the nearest open one (wait, the ReadyAt attribute). Ring opening - Core/RaidLoop by the profile (dragons, rode, flew)
local raidTarget: Model? = nil
local function raidNests(pos: Vector3, data: any): (Model?, Model?)
	local R = Config.Raid
	if not R or not R.on then
		return nil, nil
	end
	local onb = data.onboarding
	local dragons = if typeof(data.nestOrder) == "table" then #data.nestOrder else 0
	-- the current target while its egg flies back after a capture (Returning) or lies there - do not jump to another nest
	local keep = raidTarget
	if keep and keep.Parent and keep.PrimaryPart and (keep:GetAttribute("HasEgg") == true or keep:GetAttribute("Returning") == true)
		and RaidLoop.open(R, tonumber(keep:GetAttribute("Ring")) or 0, onb, dragons) and (keep.PrimaryPart.Position - pos).Magnitude <= 120 then
		return keep, nil
	end
	local bestEgg: Model? = nil
	local bestRing = -1
	local bestD = math.huge
	local bestAny: Model? = nil
	local anyD = math.huge
	local firstId = me:GetAttribute("FirstNest") -- a newcomer - only the assigned far nest; with a dragon too
	for _, m in CollectionService:GetTagged("RaidNest") do
		if m:IsA("Model") and m.PrimaryPart and not (firstId ~= nil and m:GetAttribute("NestId") ~= firstId) then
			local ring = tonumber(m:GetAttribute("Ring")) or 0
			if RaidLoop.open(R, ring, onb, dragons) then
				local d = (m.PrimaryPart.Position - pos).Magnitude
				if m:GetAttribute("HasEgg") == true then
					if ring > bestRing or (ring == bestRing and d < bestD) then
						bestEgg, bestRing, bestD = m, ring, d
					end
				elseif d < anyD then
					bestAny, anyD = m, d
				end
			end
		end
	end
	return bestEgg, bestAny
end

-- for those who already have a dragon, eggs in
-- Gloom nests are not visible (the server does not give them to such a player either - Raid.firstEggOnly); the nest and the sleeping guardian stay. Client only
local ringEggsHidden = false
local function hideRingEggs()
	local RC = Config.Raid
	if not (RC and RC.on and RC.firstEggOnly) then
		return
	end
	local data = Store.all()
	local dragons = if typeof(data.nestOrder) == "table" then #data.nestOrder else 0
	-- with a dragon the nest eggs are visible while today's limit remains (the RaidLeft attribute from Services/Raid)
	local hide = dragons >= 1 and not ((tonumber(me:GetAttribute("RaidLeft")) or 0) > 0)
	local ringHide = dragons >= 1 -- the free island eggs: with a dragon they are not given at all
	local firstId = me:GetAttribute("FirstNest") -- a newcomer sees the egg only in the assigned far nest
	if not hide and not ringHide and not ringEggsHidden and firstId == nil then
		return
	end
	ringEggsHidden = hide or ringHide or firstId ~= nil
	local function eggVisible(egg: Instance, show: boolean)
		for _, d in egg:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = if show then 0 else 1
			elseif d:IsA("PointLight") or d:IsA("ParticleEmitter") or d:IsA("BillboardGui") or d:IsA("ProximityPrompt") then
				d.Enabled = show
			end
		end
	end
	for _, m in CollectionService:GetTagged("RaidNest") do
		local egg = m:FindFirstChild("Egg")
		if egg then
			local hideThis = hide or (firstId ~= nil and m:GetAttribute("NestId") ~= firstId) -- the own nest also on daily raids
			eggVisible(egg, not hideThis)
		end
	end
	-- and the free island eggs (EggPoint spots; the EggSpawner server does not give them to such a player)
	for _, a in CollectionService:GetTagged("EggPoint") do
		local egg = a:FindFirstChild("Egg")
		if egg then
			eggVisible(egg, not ringHide)
		end
	end
end

-- an own dragon of stage >= 1 in the nest, not the companion - the goal "take it out" when there is no companion (uid - for the arrow)
local rideableUid: string? = nil
local function rideableInNest(data: any): string?
	local comp = data.companion
	if typeof(data.dragons) ~= "table" or typeof(data.nestOrder) ~= "table" then
		return nil
	end
	for _, uid in data.nestOrder do
		local d = data.dragons[uid]
		if typeof(d) == "table" and uid ~= comp and (d.stage or 0) >= 1 and d.inNest ~= false then
			return uid
		end
	end
	return nil
end

-- no companion by the profile either - otherwise a nil CompanionStage attribute on respawn/rebuild would give a false TAKE goal
local function companionMissing(data: any): boolean
	local comp = data.companion
	if typeof(comp) ~= "string" then
		return true
	end
	if typeof(data.dragons) ~= "table" or data.dragons[comp] == nil then
		return true
	end
	return typeof(data.nestOrder) == "table" and table.find(data.nestOrder, comp) == nil
end

local function nestDragonModel(nest: Model?, uid: string): Model?
	if not nest then
		return nil
	end
	for _, m in nest:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Uid") == uid and m:GetAttribute("Companion") ~= true then
			return m
		end
	end
	return nil
end

-- the own wave of the arena - a guardian? (the stage from the Gloom_<arena> attribute)
local function gloomGuardian(arena: string): boolean
	local raw = me:GetAttribute("Gloom_" .. arena)
	local st = if typeof(raw) == "string" then tonumber(string.match(raw, "^(%d+)|")) else nil
	local def = st and Config.Combat.stages[st]
	return def ~= nil and def.guardian == true
end

-- the nearest own Gloom of the arena (the FIGHT step arrow target)
local function nearestGloom(pos: Vector3, arena: string): Model?
	local best, bd = nil, math.huge
	for _, m in CollectionService:GetTagged("Gloom") do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Arena") == arena then
			local d = (m:GetPivot().Position - pos).Magnitude
			if d < bd then
				best, bd = m, d
			end
		end
	end
	return best
end

local function snapshot(nest: Model?, pos: Vector3?): HintsCore.Snapshot
	local data = Store.all()
	rideableUid = rideableInNest(data)
	local eggs = data.eggs
	local s: HintsCore.Snapshot = {
		tableFree = 0, carry = typeof(eggs) == "table" and eggs.carry ~= nil, ringReady = nil, ringFree = nil,
		dragons = if typeof(data.nestOrder) == "table" then #data.nestOrder else 0, incubating = 0, pot = 0,
		coins = data.coins or 0, feedPrice = nil, eggNear = false,
		coinsDone = typeof(data.onboarding) == "table" and data.onboarding.coinsCollected == true,
		eggDone = typeof(data.onboarding) == "table" and data.onboarding.eggFound == true,
		fedDone = typeof(data.onboarding) == "table" and data.onboarding.fedOnce == true,
		-- 1.9: the companion and mounted
		companionStage = me:GetAttribute("CompanionStage") :: number?,
		mounted = me:GetAttribute("Mounted") ~= nil,
		flying = me:GetAttribute("Flying") == true,
		rodeDone = typeof(data.onboarding) == "table" and data.onboarding.rode == true,
		flewDone = typeof(data.onboarding) == "table" and data.onboarding.flew == true,
		ringDone = typeof(data.onboarding) == "table" and data.onboarding.ring == true,
		glideDone = typeof(data.onboarding) == "table" and data.onboarding.glided == true,
		nestRideable = rideableUid ~= nil, -- (B3)
		companionMissing = companionMissing(data),
		-- combat - stages passed (profile), own waves from the server attributes ("stage|left|replay|timer")
		combatStage = if typeof(data.combat) == "table" then tonumber(data.combat.stage) else 0,
		gloomWave = me:GetAttribute("Gloom_meadow") ~= nil,
		gloomGuardian = gloomGuardian("meadow"),
		skyWave = me:GetAttribute("Gloom_sky") ~= nil,
		carryGlow = typeof(eggs) == "table" and typeof(eggs.carry) == "table" and eggs.carry.glow == true, -- (spec 25)
		glowDragon = me:GetAttribute("GlowRaid") == "dragon", -- the golden nest on the slope - with the egg to the dragon
	}
	-- a dragon exists, the golden egg is not stolen yet - no calls to the ring raids (the second dragon is the glowing one)
	local GEc = Config.Glow and Config.Glow.egg
	if GEc and GEc.on == true and GEc.raid and GEc.raid.safe == "dragon" then
		local ge = data.glowEgg
		-- "no calls to the ring nests" - only until the FIRST golden egg (day 1); series eggs 2-6 (data.glowEgg.n) do not block raids
		local seriesN = if typeof(ge) == "table" then (tonumber(ge.n) or 1) else 1
		s.glowPending = s.dragons >= 1 and seriesN <= 1 and not (typeof(ge) == "table" and (tonumber(ge.taken) or 0) > 0)
		s.glowLater = seriesN >= 2 and (tonumber(me:GetAttribute("RaidLeft")) or 0) > 0
	end
	-- day 1 = one dragon + the golden egg: with a dragon we lead neither to Gloom nests nor to free eggs at all
	-- we lead to the Gloom nest while today's limit remains (RaidLeft) and the golden one is already stolen (glowPending above)
	if Config.Raid and Config.Raid.on and Config.Raid.firstEggOnly and s.dragons >= 1 then
		if not ((tonumber(me:GetAttribute("RaidLeft")) or 0) > 0) then
			s.glowPending = true
		end
		s.oneDragonDay = true
	end
	for _, m in CollectionService:GetTagged("GlowPedestal") do -- the own pedestal and the warming price
		if m:GetAttribute("OwnerId") == me.UserId then
			s.glowPedestal = true
			s.warmPrice = tonumber(m:GetAttribute("WarmPrice"))
			break
		end
	end
	-- a raid - an egg in hand (carry.raid = the ring), a nest of an open ring with an egg nearby / all empty
	s.carryRaid = if typeof(eggs) == "table" and typeof(eggs.carry) == "table" and eggs.carry.raid ~= nil then tonumber(eggs.carry.raid) else nil
	raidTarget = nil
	if pos then
		local withEgg, empty = raidNests(pos, data)
		if withEgg then
			s.raidNear = true
			raidTarget = withEgg
		elseif empty then
			s.raidWait = true
			raidTarget = empty
		end
	end
	for _, g in CollectionService:GetTagged("GlowEgg") do -- the own glowing egg on the islet
		if g:GetAttribute("OwnerId") == me.UserId then
			s.glowEgg = true
			break
		end
	end
	if nest then
		s.tableFree = #tableEggs(nest)
		for slot = 1, 3 do
			local r = ring(nest, slot)
			local st = r and r:GetAttribute("State")
			if st == "ready" and not s.ringReady then
				s.ringReady = slot
			elseif st == "empty" and not s.ringFree then
				s.ringFree = slot
			elseif st == "warming" then
				s.incubating += 1
			end
		end
		local pile = nest:FindFirstChild("CoinPile")
		s.pot = (pile and pile:GetAttribute("Pot") :: number?) or 0
	end
	if nest and pos then -- whether at home (by the bowls) - no Tap Hatch call from a raid
		local r1 = ring(nest, 1)
		s.nearHome = r1 ~= nil and (r1.Position - pos).Magnitude <= 60
	end
	local _, price = feedTarget()
	s.feedPrice = price
	if pos then
		s.eggNear = nearestEgg(pos) ~= nil
	end
	return s
end

local function resolve(goal: HintsCore.Goal, nest: Model?, pos: Vector3): (BasePart?, Instance?)
	if goal.kind == "table" and nest then
		local eggs = tableEggs(nest)
		table.sort(eggs, function(a, b)
			return (a:GetPivot().Position - pos).Magnitude < (b:GetPivot().Position - pos).Magnitude
		end)
		return basePart(eggs[1]), eggs[1]
	elseif (goal.kind == "incubator" or goal.kind == "hatch") and nest then
		local r = ring(nest, goal.slot or 1)
		return r, (r and r:FindFirstChild("Bowl")) or r -- the ring is invisible - the Highlight on the bowl model
	elseif goal.kind == "glowHome" and nest then -- the glowing egg in hand - home
		-- to the SAFE line in the fence gate (Glow: GlowRaidFx.SafeLine), not straight to the bowl - otherwise the arrow led through the fence
		local fx = workspace:FindFirstChild("GlowRaidFx")
		local line = fx and fx:FindFirstChild("SafeLine")
		if line and line:IsA("BasePart") then
			return line, line
		end
		local r = ring(nest, 1)
		return r, (r and r:FindFirstChild("Bowl")) or r
	elseif goal.kind == "raid" or goal.kind == "raidFirst" or goal.kind == "raidWait" then -- the Gloom nest of an open ring
		local m = raidTarget
		return basePart(m), m
	elseif goal.kind == "raidDragon" then -- with an egg of rings 1-2 - to the own dragon (it waits 35 from the nest)
		local m = companion and companion.model()
		return basePart(m), m
	elseif (goal.kind == "raidHome" or goal.kind == "raidRide") and nest then -- home - to the SAFE line in the gate, otherwise to bowl 1
		local fx = workspace:FindFirstChild("GlowRaidFx")
		local line = fx and fx:FindFirstChild("SafeLine")
		if line and line:IsA("BasePart") then
			return line, line
		end
		local r = ring(nest, 1)
		return r, (r and r:FindFirstChild("Bowl")) or r
	elseif goal.kind == "glowEgg" then -- the glowing egg on the islet
		for _, g in CollectionService:GetTagged("GlowEgg") do
			if g:IsA("Model") and g:GetAttribute("OwnerId") == me.UserId then
				return basePart(g), g
			end
		end
		return nil, nil
	elseif goal.kind == "pile" and nest then
		local p = nest:FindFirstChild("CoinPile")
		return basePart(p), p
	elseif goal.kind == "warm" then -- the own golden pedestal
		for _, m in CollectionService:GetTagged("GlowPedestal") do
			if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId then
				return basePart(m), m
			end
		end
		return nil, nil
	elseif goal.kind == "stall" then -- the Keeper's stall
		local st = CollectionService:GetTagged("Stall")[1]
		return basePart(st), st
	elseif goal.kind == "glide" and nest then -- the wind stream at the own nest ledge (WorldBuilder LedgeUpdraft)
		local u = nest:FindFirstChild("LedgeUpdraft")
		return basePart(u), u
	elseif goal.kind == "egg" then
		local egg = nearestEgg(pos)
		return basePart(egg), egg
	elseif goal.kind == "feed" then
		-- feeding happens at the nest - the target is a hungry dragon IN THE NEST, otherwise the nest itself; the companion (on the shoulder/nearby)
		-- is never the target (the highlight and the arrow would be above the own head, and the server rejects Feed away from the nest)
		local best: Model? = nil
		local price: number? = nil
		for _, m in CollectionService:GetTagged("CanFeed") do
			if m:IsA("Model") and m:GetAttribute("OwnerId") == me.UserId and m:GetAttribute("Companion") ~= true then
				local p = (m:GetAttribute("FeedPrice") :: number?) or math.huge
				if not price or p < price then
					best, price = m, p
				end
			end
		end
		local target: BasePart? = nil
		local adornee: Instance? = nil
		if best then
			target, adornee = basePart(best), best
		elseif nest then
			local base = nest.PrimaryPart or nest:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				target, adornee = base, base
			end
		end
		-- quest 4 - "berries at the stall" (Nest.feed feeds at the stall), but the step target led
		-- back to the nest ("FEED ... 123 m"): if the player is within the stall radius or closer to the stall than to the nest - the step target is the stall
		local stall = CollectionService:GetTagged("Stall")[1]
		if stall and stall:IsA("BasePart") then
			local dStall = (Vector3.new(stall.Position.X, 0, stall.Position.Z) - Vector3.new(pos.X, 0, pos.Z)).Magnitude
			local dNest = if target then (target.Position - pos).Magnitude else math.huge
			if dStall <= Config.Loop.stallFeedDistance or dStall < dNest then
				return stall, stall
			end
		end
		return target, adornee
	elseif goal.kind == "ride" or goal.kind == "fly" then -- 1.9: the own companion
		local m = companion and companion.model()
		return basePart(m), m
	elseif goal.kind == "companion" then -- the dragon in the nest that has to be taken out
		local m = if rideableUid then nestDragonModel(nest, rideableUid) else nil
		return basePart(m), m
	elseif goal.kind == "gloom" or goal.kind == "guardian" or goal.kind == "sky" then -- own Gloom
		local m = nearestGloom(pos, if goal.kind == "sky" then "sky" else "meadow")
		return basePart(m), m
	elseif goal.kind == "skyUp" then -- fly up to the sky Gloom - the target is the own companion, like the FLY step
		local m = companion and companion.model()
		return basePart(m), m
	elseif goal.kind == "ring" then -- 1.9: the next wind ring along the route
		local m = fly and fly.nextRing()
		return basePart(m), m
	end
	return nil, nil
end

-- ---------------------------------------------------------------------------------------------- the chevron chain (trail)
-- instead of a Beam ribbon - chevrons made of parts on the ground from the feet to the target (DA, craft/04 §7.2), each - two golden slats
-- Neon over a dark backing (outline); the shimmer runs from the player to the target (phase by index). Parts exist only on the client.
local T = C.trail
local trailFolder: Folder? = nil
local chevrons: { { gold: { BasePart }, dark: { BasePart } } } = {}
local trailConn: RBXScriptConnection? = nil
local lastLayoutPos: Vector3? = nil
local lastLayoutAt = 0

local function flatPart(size: Vector3, color: Color3, neon: boolean): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = size
	p.Color = color
	p.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	return p
end

local function makeChevron(parent: Instance): { gold: { BasePart }, dark: { BasePart } }
	local gold, dark = {}, {}
	for _, side in { -1, 1 } do
		local d = flatPart(Vector3.new(T.length + T.outline, T.thickness * 0.8, T.width * 0.34 + T.outline), UIKit.STROKE, false)
		d.Parent = parent
		table.insert(dark, d)
		local g = flatPart(Vector3.new(T.length, T.thickness, T.width * 0.34), UIKit.GOLD, true)
		g.Parent = parent
		table.insert(gold, g)
		g:SetAttribute("Side", side)
		d:SetAttribute("Side", side)
	end
	return { gold = gold, dark = dark }
end

-- place a chevron: center pos, normal n, direction forward (along the path); the tip forward
local function placeChevron(ch: { gold: { BasePart }, dark: { BasePart } }, pos: Vector3, n: Vector3, forward: Vector3)
	local right = forward:Cross(n).Unit
	-- the chevron is raised and tilted toward the viewer (from behind, third-person camera) - readable over the grass
	local base = CFrame.fromMatrix(pos, right, n, -forward) * CFrame.Angles(math.rad(T.tiltDeg or 0), 0, 0)
	for _, list in { ch.dark, ch.gold } do
		for _, part in list do
			local side = part:GetAttribute("Side") :: number
			-- the two slats meet at the tip in front (the center is shifted slightly forward), the ends spread back and sideways (angle 48)
			local cf = base * CFrame.new(side * T.width * 0.19, if list == ch.dark then -0.02 else 0, -T.length * 0.07) * CFrame.Angles(0, -side * math.rad(48), 0)
			part.CFrame = cf
		end
	end
end

local function clearTrail()
	if trailConn then
		trailConn:Disconnect()
		trailConn = nil
	end
	if trailFolder then
		trailFolder:Destroy()
		trailFolder = nil
	end
	chevrons = {}
	lastLayoutPos = nil
end

-- air = true (1.9): a straight chain in the air from the dragon to the ring (DA: arrows at eye level), without a ray to the ground
local function layoutTrail(fromPos: Vector3, toPos: Vector3, air: boolean?)
	local f = trailFolder
	if not f then
		return
	end
	local flat = if air then (toPos - fromPos) else Vector3.new(toPos.X - fromPos.X, 0, toPos.Z - fromPos.Z)
	local dist = flat.Magnitude
	if dist < T.spacing * 0.8 then
		for _, ch in chevrons do
			for _, part in ch.gold do
				part.Transparency = 1
			end
			for _, part in ch.dark do
				part.Transparency = 1
			end
		end
		return
	end
	local dir = flat.Unit
	local n = math.clamp(math.floor((dist - T.spacing * 0.5) / T.spacing), 1, T.max)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Instance, f }
	for i = 1, T.max do
		local ch = chevrons[i]
		if not ch then
			ch = makeChevron(f)
			chevrons[i] = ch
		end
		if i <= n then
			local p = fromPos + dir * (i * T.spacing)
			local hit = if air then nil else workspace:Raycast(p + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), params)
			local pos, normal = p, Vector3.yAxis
			if hit then
				pos = hit.Position + hit.Normal * T.lift
				normal = hit.Normal
				if normal:Dot(Vector3.yAxis) < 0.3 then
					normal = Vector3.yAxis
				end
			end
			local forward = (dir - normal * dir:Dot(normal))
			forward = if forward.Magnitude > 0.01 then forward.Unit else dir
			placeChevron(ch, pos, normal, forward)
			ch.gold[1]:SetAttribute("Bob", 0)
		else
			for _, part in ch.gold do
				part.Transparency = 1
			end
			for _, part in ch.dark do
				part.Transparency = 1
			end
		end
	end
	for i = n + 1, #chevrons do
		for _, part in chevrons[i].gold do
			part.Transparency = 1
		end
		for _, part in chevrons[i].dark do
			part.Transparency = 1
		end
	end
	f:SetAttribute("Count", n)
end

-- the chain follows a WALKABLE path (PathfindingService, the world navmesh) - around fences, through gates and stairs;
-- no path - a straight line. Chevrons along the polyline
local PathfindingService = game:GetService("PathfindingService")
local function hideFrom(i0: number)
	for i = i0, #chevrons do
		for _, part in chevrons[i].gold do
			part.Transparency = 1
		end
		for _, part in chevrons[i].dark do
			part.Transparency = 1
		end
	end
end
local function layoutTrailPath(points: { Vector3 })
	local f = trailFolder
	if not f or #points < 2 then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Instance, f }
	local placed = 0
	local carry = T.spacing
	for s = 1, #points - 1 do
		local a, b = points[s], points[s + 1]
		local seg = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local len = seg.Magnitude
		if len > 0.05 then
			local dir = seg.Unit
			local t = carry
			local stop = if s == #points - 1 then len - T.spacing * 0.5 else len -- do not place at the target
			while t <= stop and placed < T.max do
				placed += 1
				local ch = chevrons[placed]
				if not ch then
					ch = makeChevron(f)
					chevrons[placed] = ch
				end
				local p = a + dir * t
				local hit = workspace:Raycast(Vector3.new(p.X, math.max(a.Y, b.Y) + 10, p.Z), Vector3.new(0, -40, 0), params)
				local pos, normal = p, Vector3.yAxis
				if hit then
					pos = hit.Position + hit.Normal * T.lift
					normal = hit.Normal
					if normal:Dot(Vector3.yAxis) < 0.3 then
						normal = Vector3.yAxis
					end
				end
				local forward = (dir - normal * dir:Dot(normal))
				forward = if forward.Magnitude > 0.01 then forward.Unit else dir
				placeChevron(ch, pos, normal, forward)
				ch.gold[1]:SetAttribute("Bob", 0)
				t += T.spacing
			end
			carry = math.max(t - len, 0.5)
		end
	end
	f:SetAttribute("Count", placed)
	hideFrom(placed + 1)
end

-- the chain path - helpers (see startTrail): the ground point under the player; leaving/entering the own lot through the gate
local function trailGround(p: Vector3): Vector3
	local pr = RaycastParams.new()
	pr.FilterType = Enum.RaycastFilterType.Exclude
	local skip: { Instance } = {}
	local ch = me.Character
	if ch then
		table.insert(skip, ch)
	end
	for _, c in CollectionService:GetTagged("Companion") do
		table.insert(skip, c)
	end
	for _, n in { "Gloom", "HintTrail", "GlowRaidFx", "Bots", "Crowd" } do
		local x = workspace:FindFirstChild(n)
		if x then
			table.insert(skip, x)
		end
	end
	pr.FilterDescendantsInstances = skip
	local h = workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -60, 0), pr)
	return if h then h.Position else p
end

-- the start and the target on different sides of the own lot fence -> a point 6 studs outside the gate (the front face, the one closer to the plaza
-- center - like GlowEgg.gateFor / HomeSpawn); the second result - the start is inside the lot
local function lotVia(a: Vector3, b: Vector3): (Vector3?, boolean, Vector3?)
	local n = myNest()
	local base = n and n:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return nil, false
	end
	local cf, sz = base.CFrame, base.Size
	local function inside(p: Vector3): boolean
		local lp = cf:PointToObjectSpace(p)
		return math.abs(lp.X) <= sz.X / 2 and math.abs(lp.Z) <= sz.Z / 2
	end
	local ia, ib = inside(a), inside(b)
	if ia == ib then
		return nil, ia
	end
	local f1 = cf:PointToWorldSpace(Vector3.new(0, sz.Y / 2, -sz.Z / 2))
	local f2 = cf:PointToWorldSpace(Vector3.new(0, sz.Y / 2, sz.Z / 2))
	local P = if Vector3.new(f2.X, 0, f2.Z).Magnitude < Vector3.new(f1.X, 0, f1.Z).Magnitude then f2 else f1
	local out = Vector3.new(P.X - cf.Position.X, 0, P.Z - cf.Position.Z)
	out = if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis
	-- (P8 day1 F5 x5: the chain from the lot to the golden nest touched the gate post FenceCollider@113,21,28 - the path went to a point beyond
	-- the gate diagonally): the third point - 4 studs BEFORE the gate inside; the gate is passed through its center, across the fence
	return trailGround(P + out * 6), ia, trailGround(P - out * 4)
end

local function computePath(a: Vector3, b: Vector3, params: { [string]: any }): { Vector3 }?
	local path = PathfindingService:CreatePath(params)
	path:ComputeAsync(a, b)
	if path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local out: { Vector3 } = {}
	for _, w in path:GetWaypoints() do
		table.insert(out, w.Position)
	end
	return if #out >= 2 then out else nil
end

-- for a rider
-- outside, the path "with a jump" to the gate led through the back wall of the lot. The fallback path without the navmesh - a detour around the lot corners
-- (the Base rectangle with a margin): from behind - two corners, from the side - one, in front of the gate - a straight line
local function lotDetour(start: Vector3, via: Vector3, margin: number): { Vector3 }
	local n = myNest()
	local base = n and n:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return { start, via }
	end
	local cf, sz = base.CFrame, base.Size
	local hx, hz = sz.X / 2 + margin, sz.Z / 2 + margin
	local ls, lv = cf:PointToObjectSpace(start), cf:PointToObjectSpace(via)
	local gateSign = if lv.Z >= 0 then 1 else -1 -- the gate is on this face (lotVia: via = the face middle + 6 outward)
	local pts = { start }
	if ls.Z * gateSign < hz - margin then -- not in front of the gate: from the side or from behind
		local sx = if ls.X >= 0 then 1 else -1
		if ls.Z * gateSign < -(hz - margin) then -- from behind: first the back corner on the own side
			table.insert(pts, trailGround(cf:PointToWorldSpace(Vector3.new(sx * hx, 0, -gateSign * hz))))
		end
		table.insert(pts, trailGround(cf:PointToWorldSpace(Vector3.new(sx * hx, 0, gateSign * hz)))) -- the front corner
	end
	table.insert(pts, via)
	return pts
end

-- the path is computed every 0.8 s, and in that time the player
-- runs 2-3 path points (16 studs/s, faster when mounted) - the chain from the feet went BACK to a passed point, then after a recompute - forward.
-- Now the chain starts from the player's projection onto the path (toward the next point ahead); a new path replaces the old one only if it is noticeably
-- shorter or the player left the old one (the navmesh returned equal detours now left, now right)
local function flatLen(a: Vector3, b: Vector3): number
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z).Magnitude
end
-- search only at the path start (up to 40 studs from the start: in 0.8 s between recomputes one cannot get farther) - otherwise from the own lot when mounted
-- the nearest segment was the detour OUTSIDE along the fence, and the chain went from the feet through the fence
local function projectOnPath(pts: { Vector3 }, p: Vector3): (number, number)
	local bestI, bestD = 1, math.huge
	local walked = 0
	for i = 1, #pts - 1 do
		if walked > 40 then
			break
		end
		local a, b = pts[i], pts[i + 1]
		walked += flatLen(a, b)
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local ap = Vector3.new(p.X - a.X, 0, p.Z - a.Z)
		local l2 = ab:Dot(ab)
		local t = if l2 > 1e-6 then math.clamp(ap:Dot(ab) / l2, 0, 1) else 0
		local q = a:Lerp(b, t)
		local d = flatLen(p, q)
		if d < bestD then
			bestI, bestD = i, d
		end
	end
	return bestI, bestD
end
local function lengthFrom(pts: { Vector3 }, i0: number, p: Vector3): number
	local len = flatLen(p, pts[math.min(i0 + 1, #pts)])
	for i = i0 + 1, #pts - 1 do
		len += flatLen(pts[i], pts[i + 1])
	end
	return len
end

local function startTrail(target: BasePart, air: boolean?)
	clearTrail()
	local f = Instance.new("Folder")
	f.Name = "HintTrail"
	f.Parent = workspace
	trailFolder = f
	local t0 = os.clock()
	local pathPts: { Vector3 }? = nil
	local lastGood: { Vector3 }? = nil -- the last found path - on a compute failure we keep it, not a straight line (otherwise the chain darts)
	if not air then
		task.spawn(function()
			while trailFolder == f and target.Parent do
				local r = root()
				if r then
					local mounted = me:GetAttribute("Mounted") ~= nil
					-- start from the ground (the rider in the saddle is above the navmesh); out of the own lot and from outside
					-- in - only through the gate: inside up to the gate with walking parameters without a jump (no obstacles), outside - with riding ones
					-- without a jump; failed - with a jump; failed - a straight line through the gate (mounted without a jump there is no path, with a jump it leads over the back fence)
					local okP, pts = pcall(function(): { Vector3 }?
						local start = trailGround(r.Position)
						local goal = target.Position
						local params = { AgentRadius = if mounted then 4.5 else 2.5, AgentHeight = if mounted then 9 else 5, AgentCanJump = not mounted, WaypointSpacing = 4 }
						local paramsJump = { AgentRadius = if mounted then 4.5 else 2.5, AgentHeight = if mounted then 9 else 5, AgentCanJump = true, WaypointSpacing = 4 }
						local inLot = { AgentRadius = 2.5, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 }
						-- the detour through the gate only when mounted; on foot - the shortest path with a jump (the fence is meant to be jumped).
						-- Note: `local a, b = if c then f() else nil, false` truncates f() to one value - startInside is computed separately
						local via: Vector3?, startInside, inner: Vector3? = nil, false, nil
						if mounted then
							via, startInside, inner = lotVia(start, goal)
						end
						if via then
							-- mounted from outside to the gate - without the "with a jump" path (it led through the back wall, G8); no path - the corner detour
							local a = if startInside then (computePath(start, inner or via, inLot) or { start, inner or via }) else (computePath(start, via, params) or (if mounted then lotDetour(start, via, 7) else (computePath(start, via, paramsJump) or { start, via })))
							if startInside and inner then -- through the gate center, across the fence
								table.insert(a, via)
							end
							-- (P8 day_5 F5: cross=1 FenceCollider@61,21,28 - from the gate to the golden nest the "with a jump" path cut the corner of the own fence):
							-- mounted outward also without a jump; no path - the corner detour in reverse order (lotDetour from the target to the gate)
							local function back(list: { Vector3 }): { Vector3 }
								local out = {}
								for i = #list, 1, -1 do
									table.insert(out, list[i])
								end
								return out
							end
							local b = if startInside then (computePath(via, goal, params) or (if mounted then back(lotDetour(goal, via, 7)) else (computePath(via, goal, paramsJump) or { via, goal }))) else (computePath(inner or via, goal, inLot) or { inner or via, goal })
							if not startInside and inner then -- from outside inward - also through the gate center
								table.insert(b, 1, via)
							end
							local out = table.clone(a)
							for i = 2, #b do
								table.insert(out, b[i])
							end
							return if #out >= 2 then out else nil
						end
						return computePath(start, goal, params) or (if mounted then computePath(start, goal, paramsJump) else nil)
					end)
					if okP and pts then
						local keep = false
						local old = lastGood
						if old and #old >= 2 then
							local i, d = projectOnPath(old, r.Position)
							keep = d < 8 and lengthFrom(pts, 1, pts[1]) > lengthFrom(old, i, r.Position) * 0.85
						end
						if not keep then
							lastGood = pts
						end
						pathPts = lastGood
					else
						pathPts = lastGood -- no path found this time - keep the previous one (nil only if there never was one)
					end
					lastLayoutPos = nil -- redraw along the new path
				end
				task.wait(0.8)
			end
		end)
	end
	trailConn = RunService.Heartbeat:Connect(function()
		local r = root()
		if not r or not target.Parent or not trailFolder then
			return
		end
		local now = os.clock()
		-- the ground trail
		-- goes out in flight (its anchor - the rider's projection high above the path - jumps); the distance arrow and the task line stay,
		-- after landing the trail is redrawn at once. The air chain to the ring (air) - as it was
		if not air and fly and fly.isFlying() then
			if (f:GetAttribute("Count") :: number?) ~= 0 then
				f:SetAttribute("Count", 0)
				hideFrom(1)
			end
			lastLayoutPos = nil
			return
		end
		if not lastLayoutPos or (r.Position - lastLayoutPos).Magnitude > T.moveThreshold or now - lastLayoutAt > T.refresh * 4 then
			if now - lastLayoutAt >= T.refresh then
				lastLayoutAt = now
				lastLayoutPos = r.Position
				if air then
					layoutTrail(r.Position + r.CFrame.LookVector * 6, target.Position, true)
				elseif pathPts and #pathPts >= 2 then
					-- also for one who left
					-- the path - along the path (a recompute within <= 0.8 s), not a straight line
					local i = projectOnPath(pathPts, r.Position)
					local pts = { r.Position - Vector3.new(0, 2.6, 0) }
					for k = i + 1, #pathPts do
						table.insert(pts, pathPts[k])
					end
					layoutTrailPath(pts)
				elseif now - t0 > 2 or lotVia(r.Position, target.Position) == nil then
					-- the path is still being computed or there is none: a straight line if it does not cut the own lot fence (without it
					-- there were no chevrons toward the dragon for the first half second)
					layoutTrail(r.Position - Vector3.new(0, 2.6, 0), target.Position)
				else -- out of the own lot (or in) the straight line went through the fence - wait for the path through the gate
					hideFrom(1)
				end
			end
		end
		local count = (f:GetAttribute("Count") :: number?) or 0
		for i = 1, math.min(count, #chevrons) do
			local ch = chevrons[i]
			local w = 0.5 + 0.5 * math.sin((now - t0) * T.pulseSpeed - i * T.pulseStep)
			local tr = T.minT + (T.maxT - T.minT) * (1 - w)
			for _, part in ch.gold do
				part.Transparency = tr
			end
			for _, part in ch.dark do
				part.Transparency = math.min(1, tr + 0.15)
			end
		end
		-- swaying of the whole chain (light, by chevron index)
		local bob = T.bob or 0
		if bob > 0 and count > 0 then
			for i = 1, math.min(count, #chevrons) do
				local ch = chevrons[i]
				local dy = bob * math.sin((now - t0) * 2.2 - i * 0.5)
				local prev = (ch.gold[1]:GetAttribute("Bob") :: number?) or 0
				local delta = dy - prev
				if math.abs(delta) > 0.001 then
					for _, list in { ch.gold, ch.dark } do
						for _, part in list do
							part.CFrame = part.CFrame + Vector3.new(0, delta, 0)
						end
					end
					ch.gold[1]:SetAttribute("Bob", dy)
				end
			end
		end
	end)
end

local function clear()
	local a = active
	if not a then
		return
	end
	clearTrail()
	for _, inst in { a.hl, a.arrow, a.arrow2d } do
		if inst then
			inst:Destroy()
		end
	end
	active = nil
end

local function bob(gui: BillboardGui, base: Vector3, lift: Vector3)
	task.spawn(function()
		while gui.Parent do
			local up = TweenService:Create(gui, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { StudsOffsetWorldSpace = base + lift })
			up:Play()
			up.Completed:Wait()
			if not gui.Parent then
				break
			end
			local down = TweenService:Create(gui, TweenInfo.new(0.55, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { StudsOffsetWorldSpace = base })
			down:Play()
			down.Completed:Wait()
		end
	end)
end

local function show(goal: HintsCore.Goal, target: BasePart, adornee: Instance)
	clear()
	local r = root()
	if not r then
		return
	end
	-- the "mount" goal - without a chain, an arrow or an outline, like FLY
	if goal.kind == "fly" or goal.kind == "skyUp" or goal.kind == "ride" then -- skyUp (spec 19) like FLY; mounted, the target is the dragon under you: no "5 m" arrow and no fill, only the banner and the arrow above Jump/Up
		active = { kind = goal.kind, slot = goal.slot, hl = nil, arrow = nil, arrow2d = nil, target = target }
		return
	end
	if goal.kind == "ring" or goal.kind == "sky" or goal.kind == "companion" then -- the sky Gloom (spec 19) like a ring; in the air neither a chain nor an arrow - only the ring outline
		-- the dragon (companion) has no outline (with glowing dragons in the game an outline reads as glow); the rings and the sky Gloom - as before
		local hl: Highlight? = nil
		if goal.kind ~= "companion" then
			local h = Instance.new("Highlight")
			h.Name = "HintHighlight"
			h.FillTransparency = 1
			h.OutlineColor = rgb(C.highlight.fill)
			h.OutlineTransparency = 0
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Adornee = adornee
			h.Parent = target
			hl = h
		end
		active = { kind = goal.kind, slot = goal.slot, hl = hl, arrow = nil, arrow2d = nil, target = target }
		return
	end
	-- feeding while the target is near (the player at the nest) - no highlight, arrow or chain: the banner and the arrow above Feed All
	if goal.kind == "feed" and (target.Position - r.Position).Magnitude < (C.nearSkip or 10) then
		active = { kind = goal.kind, slot = goal.slot, hl = nil, arrow = nil, arrow2d = nil, target = target }
		return
	end
	-- at the own pedestal, where the board with
	-- buttons is already visible, the arrow and the chain are not needed
	if goal.kind == "warm" and (target.Position - r.Position).Magnitude <= 26 then
		active = { kind = goal.kind, slot = goal.slot, hl = nil, arrow = nil, arrow2d = nil, target = target }
		return
	end
	startTrail(target, false)
	-- toward the own dragon ("Run to your dragon!") - only the arrow and the chevrons, no outline
	local hl: Highlight? = nil
	if goal.kind ~= "raidDragon" then
		local h = Instance.new("Highlight")
		hl = h
		h.Name = "HintHighlight"
		h.FillColor = rgb(C.highlight.fill)
		-- dragons and rings get only an outline
		-- the golden nest also outline only
		h.FillTransparency = if goal.kind == "ride" or goal.kind == "ring" or goal.kind == "companion" or goal.kind == "glowEgg" or goal.kind == "raid" or goal.kind == "raidFirst" or goal.kind == "raidWait" or goal.kind == "raidDragon" then 1 else C.highlight.fillTransparency -- Gloom nests and the dragon - outline -- the dragon in the nest also outline only
		h.OutlineColor = rgb(C.highlight.fill)
		h.OutlineTransparency = C.highlight.outlineTransparency
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		h.Adornee = adornee
		h.Parent = target
	end
	-- the arrow above the target: a glyph (no images) + the distance, like Ride A Pet ("314m" under the arrow)
	local arrow = Instance.new("BillboardGui")
	arrow.Name = "HintArrow"
	arrow.Adornee = target
	arrow.Size = UDim2.fromScale(C.arrow.size, C.arrow.size * 1.4)
	arrow.AlwaysOnTop = true
	arrow.MaxDistance = 400
	arrow.ResetOnSpawn = false
	-- for rings and the pile (rotated cylinders) Size.Y is the diameter, the offset is in the part's axes: the height in world space
	local half = UIKit.halfHeight(target)
	if adornee:IsA("Model") then
		local _, bsize = adornee:GetBoundingBox()
		half = bsize.Y / 2
	end
	local base = UIKit.worldUp(target, half + C.arrow.above)
	arrow.StudsOffsetWorldSpace = base
	UIKit.arrowGlyph(arrow, { Name = "Glyph", Size = UDim2.fromScale(1, 0.62) })
	UIKit.text(arrow, "", Color3.new(1, 1, 1), { Name = "Dist", Position = UDim2.fromScale(0, 0.64), Size = UDim2.fromScale(1, 0.3) })
	arrow.Parent = me:WaitForChild("PlayerGui")
	bob(arrow, base, UIKit.worldUp(target, C.arrow.bob))
	active = { kind = goal.kind, slot = goal.slot, hl = hl, arrow = arrow, target = target }
	-- the step line already hangs in the banner (StepBanner); no duplicate toast
end

-- the distance to the target under the arrow
-- a pointer at the screen edge toward the target when the target is off screen -
-- the raid and golden egg steps; does not depend on the parts on the ground (the chain, the path)
local EDGE_KINDS = { raidHome = true, raidDragon = true, raidRide = true, glowHome = true, glowEgg = true, raid = true, raidFirst = true }
local edgeGui: ScreenGui? = nil
local edgeGlyph: GuiObject? = nil
local edgeDist: TextLabel? = nil
local function updateEdge()
	local a = active
	local cam = workspace.CurrentCamera
	local r = root()
	local want = a ~= nil and a.target ~= nil and a.target.Parent ~= nil and EDGE_KINDS[a.kind] == true and cam ~= nil and r ~= nil
		and (not UIKit.worldUiHidden or (UIKit.focusGuide and not UIKit.hudHidden)) -- the chase focus hid the pointer exactly at the "where to run" moment
		and not (fly ~= nil and fly.isFlying()) -- in flight no "where to fly" pointers at all - the player flies by himself; after landing the pointer returns
	local v, on = Vector3.zero, true
	if want then
		v, on = (cam :: Camera):WorldToViewportPoint((a :: any).target.Position)
	end
	if not want or on then
		if edgeGui then
			edgeGui.Enabled = false
		end
		return
	end
	if not edgeGui then
		local g = UIKit.screen("HintEdge", 3)
		g.ResetOnSpawn = false
		local glyph = UIKit.arrowGlyph(g, { Name = "Glyph", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(56, 56), ZIndex = 5 })
		local d = UIKit.text(g, "", UIKit.GOLD, { Name = "Dist", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(90, 22), ZIndex = 5 })
		d.TextStrokeTransparency = 0.2
		edgeGui, edgeGlyph, edgeDist = g, glyph, d
	end
	local vs = (cam :: Camera).ViewportSize
	local dir = Vector2.new(v.X - vs.X / 2, v.Y - vs.Y / 2)
	if v.Z < 0 then
		dir = -dir -- the target is behind: the projection is mirrored
	end
	dir = if dir.Magnitude < 1 then Vector2.new(0, -1) else dir.Unit
	local margin = 72
	local half = Vector2.new(vs.X / 2 - margin, vs.Y / 2 - margin)
	local k = math.min(half.X / math.max(math.abs(dir.X), 1e-3), half.Y / math.max(math.abs(dir.Y), 1e-3))
	local p = Vector2.new(vs.X / 2, vs.Y / 2) + dir * k
	local g = edgeGlyph :: GuiObject
	g.Position = UDim2.fromOffset(p.X, p.Y)
	g.Rotation = math.deg(math.atan2(dir.Y, dir.X)) + 90 -- the glyph looks up, rotate by the direction
	local d = edgeDist :: TextLabel
	d.Position = UDim2.fromOffset(p.X - dir.X * 44, p.Y - dir.Y * 44)
	d.Text = string.format("%d m", math.floor(((a :: any).target.Position - (r :: BasePart).Position).Magnitude + 0.5))
	;(edgeGui :: ScreenGui).Enabled = true
end

local function updateDistance()
	local a = active
	local r = root()
	if not a or not a.arrow or not a.target or not r then
		return
	end
	local d = a.arrow:FindFirstChild("Dist")
	if d and d:IsA("TextLabel") then
		d.Text = string.format("%d m", math.floor((a.target.Position - r.Position).Magnitude + 0.5))
	end
end

-- the 2D arrow above a HUD button while the target is Hatch/Feed (P11): the same glyph
local function arrow2d(on: boolean)
	local a = active
	if not a then
		return
	end
	local btn: GuiObject? = nil
	if on then
		if a.kind == "fly" or a.kind == "skyUp" then
			btn = fly and fly.upButton()
		elseif a.kind == "gloom" or a.kind == "guardian" or a.kind == "sky" then -- the arrow above BREATH
			btn = combat and combat.button()
		elseif a.kind == "companion" then -- the action button at the bottom has nothing to do with this step (the dragon is taken out in the Dragons book)
			btn = nil
		elseif hud then
			btn = hud.actionButton() -- hatch / feed / ride - one button at the bottom center
		end
	end
	if btn and btn ~= (a.arrow2d and a.arrow2d.Parent) and a.arrow2d then
		a.arrow2d:Destroy()
		a.arrow2d = nil
	end
	if btn and not a.arrow2d then
		local g = UIKit.arrowGlyph(btn, { Name = "HintArrow2D", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromScale(0.5, 1.0), ZIndex = 5 })
		local ar = Instance.new("UIAspectRatioConstraint")
		ar.AspectRatio = 1
		ar.Parent = g
		a.arrow2d = g
		task.spawn(function()
			while g.Parent do
				local t = TweenService:Create(g, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 0, -14) })
				t:Play()
				t.Completed:Wait()
				if not g.Parent then
					break
				end
				local t2 = TweenService:Create(g, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Position = UDim2.new(0.5, 0, 0, -2) })
				t2:Play()
				t2.Completed:Wait()
			end
		end)
	elseif not btn and a.arrow2d then
		a.arrow2d:Destroy()
		a.arrow2d = nil
	end
end

local function step()
	local r = root()
	local pos = r and r.Position
	local nest = myNest()
	local goal = HintsCore.goal(snapshot(nest, pos), C)
	if stepBanner then
		stepBanner.setGoal(goal)
	end
	-- P34: mounted, the fly step target is the dragon under the player, no distance
	goalTarget = nil
	if goal and pos and goal.kind ~= "fly" then
		local a0 = active
		if a0 and a0.kind == goal.kind and a0.slot == goal.slot and a0.target and a0.target.Parent then
			goalTarget = a0.target
		else
			goalTarget = (resolve(goal, nest, pos))
		end
	end
	local now = os.clock()
	local fire = HintsCore.tick(timer, goal, now, if goal and DELAY[goal.kind] then DELAY[goal.kind] else Config.HintDelaySeconds)
	local a = active
	if a and (not goal or goal.kind ~= a.kind or goal.slot ~= a.slot or not a.target or not a.target.Parent or not r) then
		clear()
		a = nil
	end
	if fire and goal and pos then
		local target, adornee = resolve(goal, nest, pos)
		if target and adornee then
			show(goal, target, adornee)
		end
	elseif a and goal and goal.kind == "feed" and pos and a.target then
		local target, adornee = resolve(goal, nest, pos) -- the FEED target changes along the way (nest <-> stall)
		if target and adornee and target ~= a.target then
			show(goal, target, adornee)
		elseif ((a.target.Position - pos).Magnitude < (C.nearSkip or 10)) ~= (a.arrow == nil) then
			show(goal, a.target, a.target) -- came up to the nest - remove the arrow/highlight, walked away - bring back
		end
	elseif a == nil and goal and pos and (goal.kind == "raidHome" or goal.kind == "raidDragon" or goal.kind == "raidRide" or goal.kind == "glowHome" or goal.kind == "raid" or goal.kind == "raidFirst" or goal.kind == "glowEgg") then
		-- the raid target may not resolve in the
		-- show tick (the SAFE line not drawn yet, the nest not found) - retry every tick until shown
		local target, adornee = resolve(goal, nest, pos)
		if target and adornee then
			show(goal, target, adornee)
		end
	elseif a and goal and (goal.kind == "egg" or goal.kind == "ring" or goal.kind == "gloom" or goal.kind == "guardian" or goal.kind == "sky" or goal.kind == "raid" or goal.kind == "raidFirst" or goal.kind == "raidWait" or goal.kind == "raidHome" or goal.kind == "raidRide") and pos then -- the raid nest / the SAFE line change -- the nearest Gloom changes -- the nearest egg / the next ring may have changed
		local target, adornee = resolve(goal, nest, pos)
		if target and adornee and target ~= a.target then
			show(goal, target, adornee)
		end
	end
	if not active and edgeGui then
		edgeGui.Enabled = false
	end
	if active then
		-- in combat focus (worldUiHidden) only the fight - the non-combat step arrow above Ride / Up
		-- is hidden, like the 3D arrow below (otherwise two arrows on different buttons while the step line is hidden in focus)
		local fightKind = active.kind == "gloom" or active.kind == "guardian" or active.kind == "sky"
		-- the chase combat focus hid the chevron chain and the arrow above the line -
		-- on raid steps the road under the feet and the arrow stay
		local raidKind = active.kind == "raidHome" or active.kind == "raidDragon" or active.kind == "raidRide" or active.kind == "glowHome"
			or active.kind == "raid" or active.kind == "raidFirst"
		arrow2d(fightKind or (not UIKit.worldUiHidden and (active.kind == "hatch" or active.kind == "feed" or active.kind == "fly" or active.kind == "ride" or active.kind == "skyUp")))
		updateDistance()
		updateEdge()
		-- in the air the arrow above
		-- the target is hidden (the chevron chain - in startTrail, the screen-edge pointer - in updateEdge); the task line in the banner stays;
		-- after landing everything returns. WantEnabled = false so that HUD.setVisible / the combat focus release do not switch the arrow back on in flight
		local flying = fly ~= nil and fly.isFlying()
		local arrow = active.arrow
		if arrow then
			arrow:SetAttribute("WantEnabled", if flying then false else nil)
			-- a ready incubator ("Ready!", the round Hatch) and the pile (the coin count) have their own label - while it is visible
			-- the arrow above the target covered it; the chain, the outline and the meters on the banner lead
			local cam = workspace.CurrentCamera
			local own = if active.kind == "hatch" then Config.UI.incubatorGui.maxDistance elseif active.kind == "pile" then Config.UI.pileGui.maxDistance else nil
			local covered = own ~= nil and cam ~= nil and active.target ~= nil and (cam.CFrame.Position - active.target.Position).Magnitude <= own
			arrow.Enabled = (not UIKit.worldUiHidden or raidKind) and not covered and not flying
		end
		if trailFolder then
			trailFolder.Parent = if UIKit.worldUiHidden and not raidKind then nil else workspace
		end
	end
end

-- P34: the target part of the current step (nil - no target or it is under the player)
function Hints.goalPart(): BasePart?
	local t = goalTarget
	return if t and t.Parent then t else nil
end

-- for Studio probes (ClientDebug): what we hint right now
function Hints.state(): string
	local a = active
	local gt = goalTarget
	return string.format("active=%s slot=%s timerKind=%s target=%s shown=%d", a and a.kind or "-", tostring(a and a.slot), tostring(timer.kind), if gt then gt.Name else "-", (function()
		local n = 0
		for _ in timer.shown do
			n += 1
		end
		return n
	end)())
end

function Hints.init(_snapshot: any, loaded: any)
	hud = loaded.HUD
	banners = loaded.Banners
	stepBanner = loaded.StepBanner
	fly = loaded.Fly
	companion = loaded.Companion
	combat = loaded.Combat
end

function Hints.start()
	-- a new Gloom nest egg is hidden the moment it appears, not on the tick (otherwise it blinked for up to 0.5 s every 20 s)
	local function watchNest(m: Instance)
		m.ChildAdded:Connect(function(c)
			if c.Name == "Egg" then
				task.defer(function()
					pcall(hideRingEggs)
				end)
			end
		end)
	end
	for _, m in CollectionService:GetTagged("RaidNest") do
		watchNest(m)
	end
	CollectionService:GetInstanceAddedSignal("RaidNest"):Connect(watchNest)
	while true do
		hideRingEggs() -- with a dragon the Gloom nest eggs are not visible
		task.wait(C.tick)
		local ok, err = pcall(step)
		if not ok and not warned then
			warned = true
			warn("[Hints] " .. tostring(err))
		end
	end
end

return Hints
