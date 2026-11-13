--!strict
-- The nest incubators (1.7-1.8; 10 §3-4, 02 §1-2): the rings Incubators/IncubatorN. The egg in hand goes into a free open
-- incubator when the owner comes close (02 §1 "just walk up"; the PlaceEgg call - the same with a distance check <= 10).
-- The duration - Core/Eggs.incubationSeconds (the newcomer's first egg 3 s, a cooled one x1.5). The ring state - attributes
-- (OwnerId, State = empty | warming | ready | locked, Element, Rarity, Zone, HatchAt) and the ReadyToHatch tag; the client draws
-- the pill with the timer and the Hatch button itself. Hatching - the HatchReady call: Dragons.fromEgg + Dragons.add (nest/sanctuary),
-- the Index, Notice hatch (a 3 s scene on the client). The profile: eggs.incubating["N"] = { egg, endsAt }.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content")) -- 2.9: element variants
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Eggs = require(Core:WaitForChild("Eggs"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Format = require(Core:WaitForChild("Format"))
local Odds = require(Core:WaitForChild("Odds"))
local Economy = require(Core:WaitForChild("Economy"))
local ShopCore = require(Core:WaitForChild("Shop")) -- 2.1: Hatch Now tickets
local LiveOpsCore = require(Core:WaitForChild("LiveOps")) -- 2.9: the variant by weather
local HatchFx = require(Core:WaitForChild("HatchFx")) -- the look of the hatch scene
local Experiments = require(Core:WaitForChild("Experiments")) -- the firstborn growth test group

local Incubation = {}

local B = Config.Balance
local LP = Config.Loop
local services: { [string]: any } = {}
local SLOTS = #Config.World.nestLayout.incubators
local HS = Config.UI.hatchScene
-- ring -> os.clock() until which the hatch scene plays in the bowl (a new egg from the shelf - after it)
local sceneUntil: { [Instance]: number } = {}

type Reply = { ok: boolean, reason: string?, [string]: any }

local function ring(nest: Model, slot: number): BasePart?
	local inc = nest:FindFirstChild("Incubators")
	return inc and inc:FindFirstChild("Incubator" .. slot) :: BasePart?
end

local function showEgg(nest: Model, slot: number, egg: any?)
	local r = ring(nest, slot)
	if not r then
		return
	end
	local old = r:FindFirstChild("IncEgg")
	if old then
		old:Destroy()
	end
	services.WorldBuilder.setIncubatorLight(nest, slot, egg ~= nil)
	if not egg then
		return
	end
	local m = services.WorldBuilder.makeEgg(egg.element, 2.4)
	m.Name = "IncEgg"
	local cf, size = m:GetBoundingBox()
	-- the sole on the bowl straw (the EggLift attribute from WorldBuilder); before, r.Size.Y / 2 - for a rotated cylinder that is the radius 2.4
	-- the egg hung 2.1 studs above the disc
	local lift = r:GetAttribute("EggLift")
	local top = r.Position + Vector3.new(0, if typeof(lift) == "number" then lift else r.Size.X / 2, 0)
	m:PivotTo(m:GetPivot() + (top - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
	m.Parent = r
end

-- 2.4: shelf eggs (the Keeper's rewards, gifts, the calendar, Starter Pack) are visible in the cups Shelf1..5 (04 §2: "eggs wait
-- for an incubator, the element is visible by the shell"); redrawn only when the set changes (a signature in the ShelfSig attribute on the folder)
local function syncShelf(nest: Model, data: any?)
	local f = nest:FindFirstChild("Shelf")
	if not f then
		return
	end
	local shelf = data and data.eggs and data.eggs.shelf or {}
	local parts = {}
	for i = 1, math.min(#shelf, 5) do
		table.insert(parts, tostring(shelf[i].element))
	end
	-- open cups light, locked ones dark - by the owner's shelfCap (no owner - the starting 3)
	local cap = (data and data.shelfCap) or Config.Balance.shelf.start
	for i = 1, 5 do
		local cup = f:FindFirstChild("Shelf" .. i)
		if cup and cup:IsA("BasePart") then
			local open = i <= cap
			if cup:GetAttribute("Open") ~= open then
				cup:SetAttribute("Open", open)
				cup.Color = if open then Color3.fromRGB(200, 184, 162) else Color3.fromRGB(150, 140, 130) -- like the template's STONE_LIGHT
			end
		end
	end
	local sig = table.concat(parts, ",")
	if f:GetAttribute("ShelfSig") == sig then
		return
	end
	f:SetAttribute("ShelfSig", sig)
	for i = 1, 5 do
		local cup = f:FindFirstChild("Shelf" .. i)
		if cup and cup:IsA("BasePart") then
			local old = cup:FindFirstChild("ShelfEgg")
			if old then
				old:Destroy()
			end
			local egg = shelf[i]
			if egg then
				local m = services.WorldBuilder.makeEgg(egg.element, 2.0)
				m.Name = "ShelfEgg"
				local cf, size = m:GetBoundingBox()
				local top = cup.Position + Vector3.new(0, cup.Size.X / 2, 0) -- for a rotated disc the height is Size.X (was Size.Y - the radius, the egg hung)
				m:PivotTo(m:GetPivot() + (top - Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)))
				m.Parent = cup
			end
		end
	end
end
Incubation.syncShelf = syncShelf

-- the ring attributes from the owner's data (data = nil - the nest is free)
local function syncRing(nest: Model, slot: number, data: any?, ownerId: number?, now: number)
	local r = ring(nest, slot)
	if not r then
		return
	end
	r:SetAttribute("OwnerId", ownerId)
	local rec = data and data.eggs.incubating[tostring(slot)]
	local state = "empty"
	if not data then
		state = "empty"
	elseif slot > (data.incubators or 1) then
		state = "locked"
	elseif rec then
		state = if now >= rec.endsAt then "ready" else "warming"
	end
	r:SetAttribute("State", state)
	local incF = r.Parent -- the lock dome only over a locked one (before it stayed after Starter Pack too)
	if incF then
		for _, c in incF:GetChildren() do
			if c.Name == "Lock" and c:IsA("BasePart") and c:GetAttribute("Slot") == slot then
				local on = state == "locked"
				c.Transparency = if on then 0.55 else 1
				for _, g in c:GetDescendants() do
					if g:IsA("BillboardGui") then
						g.Enabled = on
					end
				end
			end
		end
	end
	r:SetAttribute("Element", rec and rec.egg.element)
	r:SetAttribute("Rarity", rec and rec.egg.rarity)
	r:SetAttribute("Zone", rec and rec.egg.zone)
	r:SetAttribute("HatchAt", rec and rec.endsAt)
	if state == "ready" then
		CollectionService:AddTag(r, "ReadyToHatch")
	else
		CollectionService:RemoveTag(r, "ReadyToHatch")
	end
end

-- put the egg from the hands into incubator slot
function Incubation.place(player: Player, slot: number): Reply
	local nest, idx = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not idx or not data then
		return { ok = false, reason = "loading" }
	end
	if slot < 1 or slot > SLOTS or slot > (data.incubators or 1) then
		return { ok = false, reason = "locked" }
	end
	local key = tostring(slot)
	if data.eggs.incubating[key] then
		return { ok = false, reason = "already" }
	end
	local rs = ring(nest, slot)
	if rs and (sceneUntil[rs] or 0) > os.clock() then -- a hatch scene is playing in the bowl
		return { ok = false, reason = "already" }
	end
	local carry = data.eggs.carry
	local fromShelf = false
	if not carry and data.eggs.shelf and #data.eggs.shelf > 0 then -- 2.4: an egg from the shelf (it does not cool on the shelf)
		carry = data.eggs.shelf[1]
		fromShelf = true
	end
	if not carry then
		return { ok = false, reason = "no_egg" }
	end
	local now = os.time()
	-- the glowing egg waits on the pedestal until tomorrow (Services/GlowEgg puts it into the bowl by itself when ready)
	local gg = data.glowEgg
	if carry.glow == true and not (typeof(gg) == "table" and (tonumber(gg.readyAt) or 0) > 0 and now >= gg.readyAt) then
		return { ok = false, reason = "glow_wait" }
	end
	local egg = table.clone(carry)
	egg.cold = if fromShelf then false else Eggs.isCold(now - (egg.foundAt or now), B)
	local secs = Eggs.incubationSeconds(egg, { firstEgg = data.onboarding.firstHatch ~= true }, B)
	if egg.glow == true and Config.Glow and Config.Glow.egg then
		secs = Config.Glow.egg.hatchSeconds -- the glowing egg - hatching at once, not the 2 h of a Legendary
	end
	-- the friend invite egg (Services/Social) - as fast as a raid egg
	if (egg.raid ~= nil or egg.invite == true) and Config.Raid and Config.Raid.on and data.onboarding.firstHatch == true then -- a raid egg hatches while the next raid goes on; the first - 3 s (firstHatchSeconds)
		local rs = Config.Raid.hatchSeconds and Config.Raid.hatchSeconds[egg.rarity]
		if rs then
			secs = rs
		end
	end
	if services.Shop and services.Shop.hasFastIncubator(data) then -- 2.1 (07 §2 no. 7): the Fast Incubator pass, the multiplier at the start
		secs *= B.fastIncubatorMult
	end
	local ticket: number? = nil
	services.PlayerData.update(player, { "eggs", "items" }, function(e, d)
		e.incubating[key] = { egg = egg, endsAt = now + math.ceil(secs) }
		if fromShelf then
			table.remove(e.shelf, 1)
		else
			e.carry = nil
		end
		if services.Shop and not fromShelf then -- 2.1: the Hatch Now ticket (07 §4) fires on the first suitable egg brought
			ticket = ShopCore.useTicket(d, "hatchNow", key, now, Config.Shop)
		end
		return nil
	end)
	if ticket then
		services.Nest.toast(player, Loc.text(Strings.Shop.ticketUsed, { name = Loc.text(Strings.Shop.names.hatchNow) }))
	end
	if fromShelf then
		syncShelf(nest, data)
	else
		services.EggSpawner.showCarry(player, nil)
	end
	showEgg(nest, slot, egg)
	syncRing(nest, slot, data, player.UserId, now)
	if services.Quest then -- an egg in the incubator (and by zone: Cliffs, Springs)
		services.Quest.event(player, "eggInc")
		if egg.zone then
			services.Quest.event(player, "eggInc_" .. tostring(egg.zone))
		end
	end
	if services.Analytics and data.quests and data.quests.counters and data.quests.counters.eggInc == 2 then -- funnel 6
		services.Analytics.onboard(player, "egg_second", { zone = tostring(egg.zone), seconds = math.floor(now - (egg.foundAt or now)) })
	end
	return { ok = true, endsAt = now + math.ceil(secs) }
end

-- hatch an egg: from incubator slot or (slot = nil) as a gift outside the incubator (2.4: the calendar's Rare hatchling)
local function hatchEgg(player: Player, nest: Model, data: any, egg: any, slot: number?): Reply
	local key = if slot then tostring(slot) else nil
	local now = os.time()
	local hatched: any = nil
	local where = "nest"
	local evicted: any = nil -- who got pushed into the sanctuary (Dragons.add by potential)
	local wasNew, keeperNew = false, false -- the Index
	local weatherNow = ""
	services.PlayerData.update(player, { "eggs", "dragons", "nestOrder", "nextUid", "companion", "onboarding", "index" }, function(e, d)
		local storm = services.Weather ~= nil and services.Weather.isStorm() -- 2.7 (04 §7): hatched during a storm - Stormborn (income x2)
		local first = key ~= nil and not d.onboarding.firstHatch
		-- 05 add. 2.18: the firstborn grows as a Common (a gift outside a ring is not the firstborn); the test group 2/6 - 3/9 (Config.Balance.firstDragon.ab)
		local d2 = Dragons.fromEgg(d, egg, now, storm, B, first, if first then Experiments.growGroup(player.UserId, B.firstDragon and B.firstDragon.ab, now) else nil)
		weatherNow = if services.Weather and services.Weather.current then services.Weather.current() else ""
		if key and not egg.name then -- 2.9 (09 §3): the variant by the weather and the egg zone (Glacier: Frost from the Summit during an Aurora); gifts outside a ring - without
			d2.variant = LiveOpsCore.variantFor(Content.Variants, egg, weatherNow, if services.LiveOps then services.LiveOps.live() else 0)
		end
		if egg.name then -- a gift with a name (Season 1 Solstice): the name at once, the name window does not open
			d2.name = egg.name
		end
		where, evicted = Dragons.add(d, d2, services.Nest.slotsTotal(d), B)
		if key then
			e.incubating[key] = nil
			d.onboarding.firstHatch = true
		end
		wasNew = not d.index[Dragons.indexKey(d2)]
		d.index[Dragons.indexKey(d2)] = true
		if services.Index then
			keeperNew = services.Index.giftKeeper(d) -- 02 §2 0:18: Old Ash's entry as a gift
		end
		hatched = d2
		return nil
	end)
	local held: Model? = nil
	if slot then
		local rh = ring(nest, slot)
		local old = rh and rh:FindFirstChild("IncEgg")
		if old and old:IsA("Model") then -- the egg stays in the bowl until the crack - the owner's client takes a copy of it for the scene
			old.Name = "HatchingEgg"
			held = old
			task.delay(HS.holdSeconds, function()
				if old.Parent then
					old:Destroy()
				end
			end)
		end
		showEgg(nest, slot, nil)
		syncRing(nest, slot, data, player.UserId, now)
		local r0 = ring(nest, slot)
		if r0 and services.Nest.setHatchOrigin then -- the hatchling appears at the ring and jumps onto the shoulder / onto the pad
			services.Nest.setHatchOrigin(player, hatched.uid, r0.Position)
		end
	end
	-- the scene event - before the Index and the quests (the client holds their banners and toasts until the hatch result) and before
	-- the model build (the client hides it on appearance until the bounce). nHatch - the number of this hatch (Quest.event below adds 1)
	local nHatch = ((data.quests and data.quests.counters and data.quests.counters.hatch) or 0) + 1
	local plan = HatchFx.plan(hatched.rarity, nHatch, HS)
	local r = if slot then ring(nest, slot) else nil
	if r then
		sceneUntil[r] = os.clock() + plan.total
	end
	services.Net.notice(player, {
		kind = "hatch",
		n = nHatch, -- Core/HatchFx - the full or the short scene
		egg = held,
		uid = hatched.uid,
		element = hatched.element,
		rarity = hatched.rarity,
		shiny = hatched.shiny,
		size = hatched.size,
		oneIn = Odds.oneIn({ zone = egg.zone, rarity = egg.rarity, rareNest = egg.rareNest, shiny = egg.shiny, size = egg.size }, B),
		income = Economy.dragonIncome(hatched, B),
		where = where,
		named = egg.name ~= nil,
		at = r and r.Position,
		variant = if hatched.variant and Content.Variants[hatched.variant] then Content.Variants[hatched.variant].label else nil, -- 2.9: «Glacier»
	})
	services.Nest.refresh(player)
	if services.Index then -- the new entry toast, the Keeper's gift, the Ancient counter
		services.Index.onHatched(player, data, Dragons.indexKey(hatched), wasNew, hatched.variant == "ancient", keeperNew)
	end
	if services.Reward and Eggs.rarityIndex(hatched.rarity) >= Eggs.rarityIndex("Rare") then -- 2.4: the daily "Hatch a Rare or better"
		services.Reward.event(player, "hatchRare")
	end
	if services.Reward and slot and weatherNow ~= "" then -- 2.9 pool B: "Hatch a dragon during a storm, starfall or aurora"
		if services.Quest then -- through Quest (quest 27 "Born in weather")
			services.Quest.event(player, "hatchWeather")
		else
			services.Reward.event(player, "hatchWeather")
		end
	end
	if services.Reward then -- weekly quests - the element (and gifts outside a ring), the weather and the day phase (from
		-- the incubator), the variant; only in Reward.event - the Keeper's counters do not grow
		services.Reward.event(player, "hatchEl_" .. tostring(hatched.element))
		if slot then
			if weatherNow ~= "" then
				services.Reward.event(player, "hatchSky_" .. weatherNow)
			end
			if services.DayCycle and services.DayCycle.phase then
				services.Reward.event(player, "hatchAt_" .. services.DayCycle.phase())
			end
		end
		if hatched.variant then
			services.Reward.event(player, "variant_" .. tostring(hatched.variant))
		end
	end
	if services.Quest then -- the "hatch" and "Index" quests
		services.Quest.event(player, "hatch")
		local pages = 0
		if services.Index then
			pages = services.Index.countOf(data) -- without the Keeper's entry
		else
			for _ in data.index do
				pages += 1
			end
		end
		services.Quest.set(player, "index", pages)
	end
	if services.Analytics then -- funnel 3/10, hatch_reveal, the Index percentage
		if nHatch == 1 then
			services.Analytics.onboard(player, "hatch_first", { element = hatched.element, rarity = hatched.rarity })
		elseif nHatch == 2 then
			services.Analytics.onboard(player, "hatch_second", { rarity = hatched.rarity })
		end
		services.Analytics.custom(player, "hatch_reveal", 1, { rarity = hatched.rarity .. ":" .. tostring(hatched.variant or "none"), size = hatched.size })
		if services.Index then
			services.Analytics.custom(player, "index_pct", math.floor(services.Index.pctOf(data) * 100 + 0.5))
		end
	end
	local vdef = hatched.variant and Content.Variants[hatched.variant]
	if vdef and services.Social then -- 2.9: the variant by weather - a line to the whole server (a reason to go out during an Aurora)
		services.Social.announce(Loc.text(Strings.LiveOps.variantLine, { player = player.DisplayName, label = vdef.label, element = (Content.Elements[hatched.element] or { name = hatched.element }).name }))
	end
	if where == "sanctuary" then
		services.Nest.toast(player, Loc.text(Strings.Loop.toSanctuary, { name = hatched.name }))
	elseif where == "swapped" and evicted then -- who gave up the spot
		services.Nest.toast(player, Loc.text(Strings.Loop.swappedOut, { name = evicted.name, new = hatched.name }))
	end
	if services.Badges and hatched.variant == "ancient" then -- 2.8 (06 §5): the Ancient Keeper badge
		services.Badges.award(player, "ancient")
	end
	if plan.mythic and r then -- Mythic - the element sky and light for the whole server
		services.Net.noticeAll({ kind = "hatchFx", at = r.Position, element = hatched.element, rarity = hatched.rarity, ownerId = player.UserId })
	end
	if services.Social and slot ~= nil then -- 2.6 (08 §4): Epic+ - a server banner with "1 in N" (gifts are not chance, without "1 in N")
		services.Social.hatched(player, hatched.rarity, hatched.element, Odds.oneIn({ zone = egg.zone, rarity = egg.rarity, rareNest = egg.rareNest, shiny = egg.shiny, size = egg.size }, B))
	end
	return { ok = true, uid = hatched.uid, where = where }
end

-- a point on the nest lot (the Base slab) - shared by Incubation and Services/GlowEgg
function Incubation.inLot(nest: Model, pos: Vector3): boolean
	local base = nest:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return false
	end
	local lp = base.CFrame:PointToObjectSpace(pos)
	return math.abs(lp.X) <= base.Size.X / 2 and math.abs(lp.Z) <= base.Size.Z / 2
end

-- Studio probes that need the manual path (hatch_check) - LoopDebug "firstegg off"
local firstEggManual = false
function Incubation.debugFirstEgg(arg: string): Reply
	firstEggManual = arg == "off"
	return { ok = true, reason = if firstEggManual then "manual" else "auto" }
end

-- hatch a ready egg from incubator slot
function Incubation.hatchSlot(player: Player, slot: number): Reply
	local nest = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not data then
		return { ok = false, reason = "loading" }
	end
	local rec = data.eggs.incubating[tostring(slot)]
	if not rec then
		return { ok = false, reason = "no_egg" }
	end
	if os.time() < rec.endsAt then
		return { ok = false, reason = "not_ready" }
	end
	return hatchEgg(player, nest, data, rec.egg, slot)
end

-- 2.4: a gift hatchling outside the incubator (calendar day 7: Rare, the element by choice) - the hatch scene, the name window, the Index
function Incubation.hatchGift(player: Player, egg: any): Reply
	local nest = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not data then
		return { ok = false, reason = "loading" }
	end
	return hatchEgg(player, nest, data, egg, nil)
end

-- on join: the eggs in the incubators back onto the rings
function Incubation.restore(player: Player)
	local nest = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not data then
		return
	end
	local now = os.time()
	for slot = 1, SLOTS do
		local rec = data.eggs.incubating[tostring(slot)]
		showEgg(nest, slot, rec and rec.egg)
		syncRing(nest, slot, data, player.UserId, now)
	end
	syncShelf(nest, data)
end

-- 2.1: after Hatch Now (endsAt changed in the profile) - the ring and the ReadyToHatch tag anew
-- the shelf after buying +2 for coins (Nest.buy)
function Incubation.syncShelfOf(player: Player)
	local nest = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if nest and data then
		syncShelf(nest, data)
	end
end

function Incubation.resync(player: Player, slotKey: string?)
	local nest = services.Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not data then
		return
	end
	local slot = tonumber(slotKey or "") or 0
	local now = os.time()
	if slot >= 1 and slot <= SLOTS then
		syncRing(nest, slot, data, player.UserId, now)
	else
		for s = 1, SLOTS do
			syncRing(nest, s, data, player.UserId, now)
		end
	end
end

function Incubation.clearNest(nest: Model)
	for slot = 1, SLOTS do
		showEgg(nest, slot, nil)
		syncRing(nest, slot, nil, nil, 0)
	end
	syncShelf(nest, nil)
end

function Incubation.init(s: { [string]: any })
	services = s
end

function Incubation.start()
	while #services.WorldBuilder.nests < Config.World.nests.count do -- the nests are built by WorldBuilder.start (~6 s), the starts run in parallel
		task.wait(0.25)
	end
	for i = 1, Config.World.nests.count do
		local nest = services.WorldBuilder.getNest(i)
		if nest then
			for slot = 1, SLOTS do
				syncRing(nest, slot, nil, nil, 0)
			end
		end
	end
	services.Net.handle("PlaceEgg", function(player: Player, slot: number): Reply
		local nest = services.Nest.of(player)
		local r = nest and ring(nest, slot)
		local pos = services.Nest.rootPos(player)
		if not r or not pos or (pos - r.Position).Magnitude > LP.placeDistance then
			return { ok = false, reason = "too_far" }
		end
		local reply = Incubation.place(player, slot)
		if not reply.ok then
			services.Nest.toast(player, Strings.Errors[reply.reason or ""] or Strings.Loop.needEgg)
		end
		return reply
	end)
	services.Net.handle("HatchReady", function(player: Player, slot: number): Reply
		local nest = services.Nest.of(player)
		local r = nest and ring(nest, slot)
		local pos = services.Nest.rootPos(player)
		if not r or not pos or (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude > LP.hatchDistance then
			services.Nest.toast(player, Strings.Errors.too_far) -- hatching only at the incubator
			return { ok = false, reason = "too_far" }
		end
		return Incubation.hatchSlot(player, slot)
	end)
	-- since when the bowl is free (per player and ring) and whether the owner stands on his lot
	local SA = Config.Loop.shelfAuto
	local FE = Config.Loop.firstEgg
	local freeSince: { [Player]: { [number]: number } } = {}
	-- the player's join (protection of the auto-hatch by join), the egg flying into the bowl (placed on arrival), warn once
	local joinedAt: { [Player]: number } = {}
	local flying: { [Player]: boolean } = {}
	local autoWarned = false
	local PlayersService = game:GetService("Players")
	for _, p in PlayersService:GetPlayers() do
		joinedAt[p] = os.clock()
	end
	PlayersService.PlayerAdded:Connect(function(p)
		joinedAt[p] = os.clock()
	end)
	PlayersService.PlayerRemoving:Connect(function(p)
		freeSince[p] = nil
		joinedAt[p] = nil
		flying[p] = nil
	end)
	-- the auto calls in the shared ring tick - under pcall (an error in hatchEgg does not stop the whole server's tick)
	local function auto(what: string, fn: () -> Reply): Reply?
		local ok, res = pcall(fn)
		if not ok then
			if not autoWarned then
				autoWarned = true
				warn("[Incubation] first egg " .. what .. ": " .. tostring(res))
			end
			return nil
		end
		return res
	end
	local inLot = Incubation.inLot
	-- the egg from the hands in an arc into a free bowl, like the first egg (Services/Raid at the SAFE line
	-- / at the lot gate); no free bowl - false, Raid puts the egg onto the shelf
	function Incubation.flyHome(owner: Player): boolean
		local data = services.PlayerData.get(owner)
		local nest = services.Nest.of(owner)
		if not data or not nest or data.eggs.carry == nil then
			return false
		end
		-- (P8 day1: the newcomer at the bowl - the egg is already flying into it ("just walk up", first_egg_auto), and the raid in the same moment put it onto
		-- the shelf with the banner "Incubators are full" instead of "SAFE!"): the flight is already on - the egg is home, do not touch the shelf
		if flying[owner] then
			return true
		end
		for slot = 1, math.min(SLOTS, data.incubators or 1) do
			local r = ring(nest, slot)
			if r and not data.eggs.incubating[tostring(slot)] and not ((sceneUntil[r :: any] or 0) > os.clock()) then
				local ch = owner.Character
				local ce = ch and ch:FindFirstChild("CarriedEgg")
				local from = if ce and ce:IsA("Model") then ce:GetPivot().Position else nil
				flying[owner] = true
				if from then
					services.Net.notice(owner, { kind = "eggFly", from = from, to = r.Position, seconds = FE.fly })
				end
				local s, egg = slot, data.eggs.carry
				task.delay(if from then FE.fly else 0, function()
					flying[owner] = nil
					local d2 = services.PlayerData.get(owner)
					-- "just walk up" may have already placed this egg - then place would take an egg from the shelf bypassing shelfAuto
					if owner.Parent == PlayersService and d2 and d2.eggs.carry == egg then
						auto("raid place", function()
							return Incubation.place(owner, s)
						end)
					end
				end)
				return true
			end
		end
		return false
	end
	-- once a second: the ring states (warming -> ready) and "just walk up" with an egg in hand
	task.spawn(function()
		while true do
			task.wait(LP.tickSeconds)
			local now = os.time()
			for i = 1, Config.World.nests.count do
				local owner = services.Nest.ownerOf(i)
				local data = owner and services.PlayerData.get(owner)
				local nest = services.WorldBuilder.getNest(i)
				if owner and data and nest then
					local pos = services.Nest.rootPos(owner)
					syncShelf(nest, data) -- 2.4: gifts and rewards put eggs onto the shelf from different services
					local hasEgg = data.eggs.carry ~= nil or (data.eggs.shelf ~= nil and #data.eggs.shelf > 0)
					local fs = freeSince[owner]
					if not fs then
						fs = {}
						freeSince[owner] = fs
					end
					local clock = os.clock()
					local home = SA.on and pos ~= nil and data.eggs.carry == nil and data.eggs.shelf ~= nil and #data.eggs.shelf > 0 and inLot(nest, pos)
					local autoDone = false
					-- the first egg goes into the bowl by itself placeAfter s after the pickup and hatches by itself when ready and the owner is near
					local carry = data.eggs.carry
					local atHome = pos ~= nil and inLot(nest, pos)
					local firstAuto = FE ~= nil and FE.on and not firstEggManual and data.onboarding.firstHatch ~= true and atHome
						and clock - (joinedAt[owner] or clock) >= FE.afterJoin
					local firstPlace = firstAuto and carry ~= nil and not flying[owner] and now - (tonumber(carry.foundAt) or now) >= FE.placeAfter
					for slot = 1, SLOTS do
						syncRing(nest, slot, data, owner.UserId, now)
						local r = ring(nest, slot)
						local free = slot <= (data.incubators or 1) and not data.eggs.incubating[tostring(slot)]
						fs[slot] = if free then (fs[slot] or clock) else nil
						local rec = data.eggs.incubating[tostring(slot)]
						local flat = if pos and r then (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(r.Position.X, 0, r.Position.Z)).Magnitude else math.huge
						if firstAuto and rec and now >= rec.endsAt and flat <= FE.hatchWithin and not ((sceneUntil[r :: any] or 0) > clock) then
							local rep = auto("hatch", function()
								return Incubation.hatchSlot(owner, slot)
							end)
							if rep and rep.ok and services.Analytics then
								services.Analytics.custom(owner, "first_egg_auto", 2)
							end
							firstAuto, firstPlace = false, false -- one per tick; firstHatch is already set
						elseif firstPlace and r and free then
							-- the egg does not "teleport" - the client pulls it in an arc from the hands into the bowl, the server places it on arrival
							firstPlace = false
							flying[owner] = true
							local ch = owner.Character
							local ce = ch and ch:FindFirstChild("CarriedEgg")
							local from = if ce and ce:IsA("Model") then ce:GetPivot().Position else nil
							if from then
								services.Net.notice(owner, { kind = "eggFly", from = from, to = r.Position, seconds = FE.fly })
							end
							local who, s = owner, slot
							task.delay(if from then FE.fly else 0, function()
								flying[who] = nil
								if who.Parent ~= PlayersService then
									return
								end
								local rep = auto("place", function()
									return Incubation.place(who, s)
								end)
								local A = services.Analytics
								if rep and rep.ok and A then
									A.custom(who, "first_egg_auto", 1)
								end
							end)
						elseif pos and r and hasEgg and free and flat <= LP.placeRadius then
							Incubation.place(owner, slot)
						elseif home and r and free and not autoDone and clock - (fs[slot] or clock) >= SA.freeFor then
							-- an egg from the shelf by itself into a free bowl (one per tick; a hatch scene in the bowl - place refuses, a retry on the next tick)
							autoDone = true
							local rep = Incubation.place(owner, slot)
							if rep.ok and services.Analytics then
								services.Analytics.custom(owner, "shelf_auto", slot)
							end
						end
					end
				end
			end
		end
	end)
end

return Incubation
