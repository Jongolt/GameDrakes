--!strict
-- The players' nests (1.7-1.8; 10 §3-4, 02 §1-2): the first free nest on join (the OwnerId attribute, the sign "<name>'s nest")
-- the character after the data and the nest, the dragons in their spots (DragonVisuals) with state attributes (Uid, OwnerId, Stage,
-- StageEndsAt, FedUntil, Income, FeedPrice) and the CanFeed tag, growth on a 1 s tick (Core/Growth), the income into the pile (Core/Economy,
-- a 60 min ceiling; the Pot attribute on the pile, Rate on the nest). Collecting the pile and the trail coins - "just walk up" (02 §1). Feeding - the
-- Feed call (uid | "all"). Messages to the player - Notice (Net): toast, coins, stage_up. The nest is released on leaving.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local IndexCore = require(Core:WaitForChild("Index"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Growth = require(Core:WaitForChild("Growth"))
local Economy = require(Core:WaitForChild("Economy"))
local Offline = require(Core:WaitForChild("Offline")) -- 2.5

local Nest = {}

local B = Config.Balance
local LP = Config.Loop
local services: { [string]: any } = {}
local owners: { [Player]: number } = {}
local byIndex: { [number]: Player } = {}

local function fmt(s: string, t: { [string]: any }): string
	return (string.gsub(s, "{(%w+)}", function(k) -- loc-ok: an English string for the server (a bot's name); for the player - Loc.text
		local v = t[k]
		return if v ~= nil then tostring(v) else "{" .. k .. "}"
	end))
end
Nest.fmt = fmt

-- one toast line (02 §1: a refusal is visible, a success is visible)
function Nest.toast(player: Player, text: any) -- a string or a Loc.text template (the client translates)
	services.Net.notice(player, { kind = "toast", text = text })
end

function Nest.of(player: Player): (Model?, number?)
	local i = owners[player]
	if not i then
		return nil, nil
	end
	return services.WorldBuilder.getNest(i), i
end

function Nest.ownerOf(index: number): Player?
	return byIndex[index]
end

function Nest.slotsTotal(data: any): number
	local n = (data.slots and data.slots.coins) or B.slots.start
	if services.Shop then -- 2.1: slots from passes I-III and VIP (07 §2 no. 3, no. 6)
		n += services.Shop.passSlots(data)
	end
	return math.min(n, math.max(10, #(Config.World.nestLayout.slots or {}))) -- the supports Slot1..10 in the nest template (10 §3)
end

-- the position of the player's live character (nil - no character)
function Nest.rootPos(player: Player): Vector3?
	if services.AntiCheat then -- a position that can be trusted (a teleport and running acceleration on foot do not pass)
		return services.AntiCheat.pos(player)
	end
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if root and hum and hum.Health > 0 then
		return root.Position
	end
	return nil
end

-- text - a string or a Loc.text template; the sign is seen by everyone - the translation is applied by every player's client (Loc.tag)
local function setSign(nest: Model, text: any)
	local sp = nest:FindFirstChild("SignPost")
	local gui = sp and sp:FindFirstChild("SignGui")
	local tl = gui and gui:FindFirstChildWhichIsA("TextLabel")
	if tl then
		if Loc.isText(text) then
			Loc.tag(tl, "Text", text.loc, text.v)
		else
			Loc.tag(tl, "Text", tostring(text))
		end
	end
end

-- 1.14: the nest sign (Admin writes "Bot N's Nest" and restores "Free Nest N")
function Nest.setSign(nest: Model, text: any)
	setSign(nest, text)
end

-- THE HOME SPAWN POINT - an invisible
-- SpawnLocation inside the own lot 9 studs from the gate, facing the plaza (Config.Loop.spawnHome): in the first seconds the player sees
-- his pen (the sign, the bowls), the arrow leads from the gate to the far nest, and "run home" after the theft - to where he came out from.
-- Set as player.RespawnLocation before LoadCharacter (join and respawns); after Reset the character is moved there too
local function homeSpawn(nest: Model): SpawnLocation?
	local base = nest:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return nil
	end
	local old = nest:FindFirstChild("HomeSpawn")
	if old and old:IsA("SpawnLocation") then
		return old
	end
	local cf, sz = base.CFrame, base.Size
	local hd, top = sz.Z / 2, sz.Y / 2
	local zf = -hd -- the front face - the one closer to the plaza center (0, 0), as for the GlowEgg.gateFor gate
	local f1, f2 = cf:PointToWorldSpace(Vector3.new(0, top, -hd)), cf:PointToWorldSpace(Vector3.new(0, top, hd))
	if Vector3.new(f2.X, 0, f2.Z).Magnitude < Vector3.new(f1.X, 0, f1.Z).Magnitude then
		zf = hd
	end
	local inward = if zf < 0 then 1 else -1
	local at = cf:PointToWorldSpace(Vector3.new(0, top + 0.5, zf + inward * 9))
	local look = cf:PointToWorldSpace(Vector3.new(0, top + 0.5, zf - inward * 10))
	local s = Instance.new("SpawnLocation")
	s.Name = "HomeSpawn"
	s.Size = Vector3.new(6, 1, 6)
	s.CFrame = CFrame.lookAt(at, look)
	s.Anchored = true
	s.CanCollide = false
	s.CanQuery = false
	s.CanTouch = false
	s.Transparency = 1
	s.Neutral = true
	s.Duration = 0
	s.Parent = nest
	return s
end

function Nest.homeSpawn(player: Player): SpawnLocation?
	local nest = Nest.of(player)
	return if nest then homeSpawn(nest) else nil
end

local function leaderCoins(player: Player, coins: number)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local v = ls:FindFirstChild(Strings.Loop.coinStat) :: IntValue?
	if not v then
		local nv = Instance.new("IntValue")
		nv.Name = Strings.Loop.coinStat
		nv.Parent = ls
		v = nv
	end
	(v :: IntValue).Value = math.floor(coins)
end

local function dragonModel(nest: Model, uid: string): Model?
	local f = nest:FindFirstChild("Dragons")
	if not f then
		return nil
	end
	for _, m in f:GetDescendants() do
		if m:IsA("Model") and m:GetAttribute("Uid") == uid then
			return m
		end
	end
	return nil
end

-- the income label above a dragon = the base income (the Income attribute) x the nest multiplier (RateMult: ascension, the Index, passes
-- friends, weather); dragons not in the nest (the sanctuary) have no multiplier
local function labelIncome(m: Model, mult: number)
	local body = m.PrimaryPart
	local bb = body and body:FindFirstChild("Label")
	local t = bb and bb:FindFirstChild("Income")
	local base = m:GetAttribute("Income")
	if t and t:IsA("TextLabel") and typeof(base) == "number" then
		local txt = Format.rate(base * mult)
		if t.Text ~= txt then
			t.Text = txt
		end
	end
end

function Nest.relabelIncome(player: Player, nest: Model)
	local mult = nest:GetAttribute("RateMult")
	local k = if typeof(mult) == "number" and mult > 0 then mult else 1
	local f = nest:FindFirstChild("Dragons")
	if f then
		for _, m in f:GetDescendants() do
			if m:IsA("Model") and m:GetAttribute("Uid") then
				labelIncome(m, k)
			end
		end
	end
	for _, m in CollectionService:GetTagged("Companion") do
		if m:IsA("Model") and m:GetAttribute("OwnerId") == player.UserId then
			labelIncome(m, k)
		end
	end
end

-- the attributes and the CanFeed tag of a dragon model from the record (the client draws the icons and timers itself)
local function syncDragon(m: Model, d: any, data: any, now: number)
	m:SetAttribute("Stage", d.stage)
	m:SetAttribute("StageEndsAt", d.stageEndsAt)
	m:SetAttribute("FedUntil", d.fedUntil)
	m:SetAttribute("Income", Economy.dragonIncome(d, B))
	m:SetAttribute("FeedPrice", Economy.feedPrice(d, data.ascension or 0, B))
	local owner = m:GetAttribute("OwnerId") -- the income label with the nest multiplier at once (not waiting for a multiplier change)
	local pl = if typeof(owner) == "number" then Players:GetPlayerByUserId(owner) else nil
	local nest = if pl then (Nest.of(pl)) else nil
	local mult = nest and nest:GetAttribute("RateMult")
	local inNest = typeof(data.nestOrder) == "table" and table.find(data.nestOrder, d.uid) ~= nil
	labelIncome(m, if inNest and typeof(mult) == "number" and mult > 0 then mult else 1)
	if d.stage < 3 and not Growth.isFed(d, now) then
		CollectionService:AddTag(m, "CanFeed")
	else
		CollectionService:RemoveTag(m, "CanFeed")
	end
end

-- the companion is not duplicated in the nest - its model
-- is one, with the player (Movement); the attributes and the CanFeed tag are set on it by this same sync
function Nest.syncModel(m: Model, d: any, data: any, now: number)
	syncDragon(m, d, data, now)
end

-- where the dragon hatched from (the incubator ring) - the model first stands there, looks at the player and jumps to its spot
-- (Nest.refresh for the copy in the nest, Movement.buildCompanion for the companion); the record lives until the first build of a model of this uid
local hatchOrigin: { [Player]: { uid: string, pos: Vector3 } } = {}
local HH = Config.Dragon.hatchHop

function Nest.setHatchOrigin(player: Player, uid: string, pos: Vector3)
	hatchOrigin[player] = { uid = uid, pos = pos }
end

function Nest.takeHatchOrigin(player: Player, uid: string): Vector3?
	local o = hatchOrigin[player]
	if o and o.uid == uid then
		hatchOrigin[player] = nil
		return o.pos
	end
	return nil
end

-- the copy in the nest (anchored): to the ring, after sitSeconds in an arc home onto the pad
local function hopFromRing(player: Player, m: Model, origin: Vector3)
	local home = m:GetPivot()
	local cf0, size = m:GetBoundingBox()
	local lift = home.Position.Y - (cf0.Position.Y - size.Y / 2)
	local at = origin + Vector3.new(0, 0.5 + lift, 0)
	local root = Nest.rootPos(player)
	local look = if root then Vector3.new(root.X - at.X, 0, root.Z - at.Z) else home.LookVector
	if look.Magnitude < 0.1 then
		look = home.LookVector
	end
	m:PivotTo(CFrame.lookAt(at, at + look.Unit))
	task.delay(HH.sitSeconds, function()
		if not m.Parent then
			return
		end
		local start = m:GetPivot()
		local t0 = os.clock()
		while m.Parent do
			local t = math.min(1, (os.clock() - t0) / HH.hopSeconds)
			m:PivotTo(start.Rotation:Lerp(home.Rotation, t) + (start.Position:Lerp(home.Position, t) + Vector3.new(0, HH.height * math.sin(t * math.pi), 0)))
			if t >= 1 then
				break
			end
			task.wait()
		end
		if m.Parent then
			m:PivotTo(home)
		end
	end)
end

-- the sign on the empty pad of the companion "<name> is out with the rider" (removed by DragonVisuals.clearSlot by the Slot attribute)
local function awayMark(nest: Model, slot: number, d: any)
	local base = nest.PrimaryPart
	local att = base and base:FindFirstChild("Slot" .. slot)
	local f = nest:FindFirstChild("Dragons")
	if not att or not att:IsA("Attachment") or not f then
		return
	end
	local p = Instance.new("Part")
	p.Name = "AwayMark"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = att.WorldPosition + Vector3.new(0, 1.5, 0)
	p:SetAttribute("Slot", slot)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Label"
	bb.Size = UDim2.fromOffset(250, 40) -- wider, with wrapping
	bb.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	bb.MaxDistance = 60
	bb.AlwaysOnTop = false
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.TextScaled = true
	t.TextWrapped = true
	t.Font = (Enum.Font :: any)[Config.UI.font] or Enum.Font.FredokaOne
	t.TextColor3 = Color3.fromRGB(225, 220, 205)
	t.TextStrokeTransparency = 0.3
	Loc.tag(t, "Text", Strings.Loop.withRider, { name = if Config.Names.publicNames == false and d.element then string.upper(string.sub(d.element, 1, 1)) .. string.sub(d.element, 2) else (d.name or "") }) -- the dragon's name is not translated
	t.Parent = bb
	bb.Parent = p
	p.Parent = f
end

-- the player's dragon model: the copy in the nest or the companion (if uid is the companion, there is no copy in the nest)
local function anyModel(player: Player, nest: Model, data: any, uid: string): Model?
	local m = dragonModel(nest, uid)
	if not m and data.companion == uid and services.Movement and services.Movement.companionOf then
		m = services.Movement.companionOf(player)
	end
	return m
end

-- rebuild the player's nest dragons: spot i = nestOrder[i]
function Nest.refresh(player: Player)
	local nest = Nest.of(player)
	local data = services.PlayerData.get(player)
	if not nest or not data then
		return
	end
	local DV = services.DragonVisuals
	for i = 1, 10 do
		DV.clearSlot(nest, i)
	end
	local now = os.time()
	for i, uid in data.nestOrder do
		local d = data.dragons[uid]
		if d and uid ~= data.companion then -- the companion walks with the player, the nest spot is empty (the income goes by nestOrder)
			local m = DV.build(d, true)
			m:SetAttribute("Uid", uid)
			m:SetAttribute("OwnerId", player.UserId)
			DV.placeInSlot(nest, i, m)
			syncDragon(m, d, data, now)
			local origin = Nest.takeHatchOrigin(player, uid)
			if origin then
				hopFromRing(player, m, origin) -- just hatched: from the ring onto the pad
			end
		elseif d then
			DV.clearSlot(nest, i)
			awayMark(nest, i, d)
		end
	end
	if services.Movement then -- 1.9: the companion next to the player from the same data
		local ok, err = pcall(services.Movement.refresh, player)
		if not ok then
			warn("[Nest] Movement.refresh: " .. tostring(err))
		end
	end
end

-- coin purchases per 05 §1-3 - incubators 2 / 3 (5,000 / 250,000)
-- slots 4-6 (2,500 / 60,000 / 1,500,000), shelf +2 (10,000). The Remote Buy was declared without a handler - buying was impossible.
-- A slot: the first dragon from the sanctuary moves into the nest at once.
local BUY_TX = { incubator = "Incubator", slot = "Slot", shelf = "Shelf" }
function Nest.buy(player: Player, key: string): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local price: number?
	if key == "incubator" then
		price = Economy.incubatorPrice(data.incubators or B.incubators.start, B)
	elseif key == "slot" then
		price = Economy.slotPrice((data.slots and data.slots.coins) or B.slots.start, B)
	elseif key == "shelf" then
		price = Economy.shelfPrice(data.shelfCap or B.shelf.start, B)
	else
		return { ok = false, reason = "bad_request" }
	end
	if not price then
		return { ok = false, reason = "already" }
	end
	local coins = data.coins or 0
	if coins < price then
		return { ok = false, reason = "not_enough", n = math.ceil(price - coins) }
	end
	local moved: string? = nil
	services.PlayerData.update(player, { "coins", "incubators", "slots", "shelfCap", "dragons", "nestOrder" }, function(_, d)
		d.coins = (d.coins or 0) - price
		if key == "incubator" then
			d.incubators = (d.incubators or B.incubators.start) + 1
		elseif key == "slot" then
			d.slots = if typeof(d.slots) == "table" then d.slots else {}
			d.slots.coins = (d.slots.coins or B.slots.start) + 1
			for _, x in Dragons.sanctuaryList(d) do
				if Dragons.moveToNest(d, x.uid, Nest.slotsTotal(d)) then
					moved = x.uid
				end
				break
			end
		else
			d.shelfCap = math.min(B.shelf.max, (d.shelfCap or B.shelf.start) + 2)
		end
		return nil
	end)
	leaderCoins(player, data.coins)
	if services.Analytics then
		services.Analytics.coins(player, "Sink", price, data.coins or 0, BUY_TX[key], key)
	end
	if key == "incubator" and services.Incubation then
		services.Incubation.resync(player)
	elseif key == "shelf" and services.Incubation and services.Incubation.syncShelfOf then
		services.Incubation.syncShelfOf(player)
	elseif key == "slot" then
		Nest.refresh(player)
	end
	Nest.toast(player, (Strings.Buy :: any)[key] or "")
	return { ok = true, price = price, moved = moved }
end

-- (spec 03 add. 1.3 "Move (nest / sanctuary)", 10 §4 MoveDragon): the Remote had no handler - with a full nest a new dragon
-- stayed in the sanctuary forever. to = "nest": there is room - move; none - swap with the weakest in the nest (not the companion).
-- to = "sanctuary": not the companion, the sanctuary is not full
function Nest.moveDragon(player: Player, uid: string, to: string): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local d = data.dragons[uid]
	if not d then
		return { ok = false, reason = "no_dragon" }
	end
	local swapped: string? = nil
	local okMove, why = false, nil :: string?
	services.PlayerData.update(player, { "dragons", "nestOrder" }, function(_, inv)
		if to == "nest" then
			okMove, why = Dragons.moveToNest(inv, uid, Nest.slotsTotal(inv))
			if not okMove and why == "nest_full" then
				local w = Dragons.weakestInNest(inv, B, inv.companion)
				if w then
					local cap = math.huge -- a swap: the sanctuary keeps as many dragons as it had
					okMove, why = Dragons.moveToSanctuary(inv, w.uid, cap)
					if okMove then
						okMove, why = Dragons.moveToNest(inv, uid, Nest.slotsTotal(inv))
						if okMove then
							swapped = w.uid
						else
							Dragons.moveToNest(inv, w.uid, Nest.slotsTotal(inv)) -- rollback
						end
					end
				end
			end
		elseif to == "sanctuary" then
			okMove, why = Dragons.moveToSanctuary(inv, uid, inv.sanctuaryCap or B.sanctuary.start)
		else
			why = "bad_request"
		end
		return nil
	end)
	if not okMove then
		return { ok = false, reason = why or "bad_request" }
	end
	Nest.refresh(player)
	local sw = swapped and data.dragons[swapped]
	if sw then
		Nest.toast(player, Loc.text(Strings.Card.swapped, { name = sw.name or "" }))
	end
	if services.Analytics then
		services.Analytics.custom(player, "dragon_move", 1, { to = to, swap = if swapped then "1" else "0" })
	end
	return { ok = true, swapped = swapped }
end

-- releasing a dragon - 120 s of its income in coins, only with a confirmation, not the companion; the Index entry
-- stays (index is separate from dragons), a worn looks preset frees itself (the wearer is determined by dragons)
function Nest.release(player: Player, uid: string, confirm: boolean): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	if confirm ~= true then
		return { ok = false, reason = "bad_request" }
	end
	if uid == "common" then -- all Commons in the sanctuary except the companion
		local total, n = 0, 0
		services.PlayerData.update(player, { "dragons", "nestOrder" }, function(_, inv)
			for _, x in Dragons.sanctuaryList(inv) do
				if x.rarity == "Common" and x.uid ~= inv.companion then
					local okR, ref = Dragons.release(inv, x.uid, B)
					if okR then
						total += ref
						n += 1
					end
				end
			end
			return nil
		end)
		if n == 0 then
			return { ok = false, reason = "no_dragon" }
		end
		if total > 0 then
			Nest.addCoins(player, total, "Release")
		end
		Nest.refresh(player)
		if services.Analytics then
			services.Analytics.custom(player, "dragon_release", total, { n = tostring(n), kind = "common" })
		end
		Nest.toast(player, Loc.text(Strings.Card.releasedAll, { k = n, n = Format.number(total) }))
		return { ok = true, coins = total, n = n }
	end
	if not data.dragons[uid] then
		return { ok = false, reason = "no_dragon" }
	end
	local okRel, refund, why = false, 0, nil :: string?
	services.PlayerData.update(player, { "dragons", "nestOrder" }, function(_, inv)
		okRel, refund, why = Dragons.release(inv, uid, B)
		return nil
	end)
	if not okRel then
		return { ok = false, reason = why or "bad_request" }
	end
	if refund > 0 then
		Nest.addCoins(player, refund, "Release")
	end
	Nest.refresh(player)
	if services.Analytics then
		services.Analytics.custom(player, "dragon_release", refund)
	end
	Nest.toast(player, Loc.text(Strings.Card.released, { n = Format.number(refund) }))
	return { ok = true, coins = refund }
end

function Nest.addCoins(player: Player, n: number, txType: string?)
	services.PlayerData.update(player, "coins", function(c)
		return (c or 0) + n
	end)
	local data = services.PlayerData.get(player)
	if data then
		leaderCoins(player, data.coins)
		if services.Analytics then -- the coin economy (Source)
			services.Analytics.coins(player, "Source", n, data.coins or 0, txType or "Income")
		end
	end
end

-- a coin charge with the leaderboard and Sink analytics (warming the golden egg); false - not enough
function Nest.spend(player: Player, price: number, txType: string, item: string?): boolean
	local data = services.PlayerData.get(player)
	if not data or math.floor(data.coins or 0) < price then
		return false
	end
	services.PlayerData.update(player, "coins", function(c)
		return (c or 0) - price
	end)
	leaderCoins(player, data.coins)
	if services.Analytics then
		services.Analytics.coins(player, "Sink", price, data.coins or 0, txType, item)
	end
	return true
end

-- feeding: x2 growth for 5 min at the balance price (Core/Growth.feed, Economy.feedPrice); uid = "all" - everyone who can be fed
function Nest.feed(player: Player, uid: string): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	local nest = Nest.of(player)
	if not data or not nest then
		return { ok = false, reason = "loading" }
	end
	local now = os.time()
	local pos = Nest.rootPos(player) -- feeding only at the nest (02 §4), otherwise too_far
	local base = nest.PrimaryPart or nest:FindFirstChild("Base")
	local atNest = pos ~= nil and base ~= nil and base:IsA("BasePart")
		and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(base.Position.X, 0, base.Position.Z)).Magnitude <= LP.feedDistance
	-- berries at the Keeper's stall too - feeds every hungry dragon in the nest
	local stall = CollectionService:GetTagged("Stall")[1]
	local atStall = pos ~= nil and stall ~= nil and stall:IsA("BasePart")
		and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(stall.Position.X, 0, stall.Position.Z)).Magnitude <= LP.stallFeedDistance
	if not atNest and not atStall then
		Nest.toast(player, Strings.Errors.too_far)
		return { ok = false, reason = "too_far" }
	end
	local list = if uid == "all" then table.clone(data.nestOrder) else { uid }
	local fed, spent, lastReason = 0, 0, nil
	for _, u in list do
		local d = data.dragons[u]
		if not d or not table.find(data.nestOrder, u) then
			lastReason = "no_dragon"
			continue
		end
		local price = Economy.feedPrice(d, data.ascension or 0, B)
		if (data.coins or 0) < price then
			lastReason = "not_enough"
			if uid ~= "all" then
				Nest.toast(player, Loc.text(Strings.Errors.not_enough, { n = Format.number(price - math.floor(data.coins or 0)) }))
				return { ok = false, reason = "not_enough" }
			end
			continue
		end
		local ok, reason = Growth.feed(d, now, B)
		if ok then
			services.PlayerData.update(player, { "coins", "dragons" }, function(c)
				return (c or 0) - price
			end)
			fed += 1
			spent += price
			local m = anyModel(player, nest, data, u)
			if m then
				syncDragon(m, d, data, now)
			end
		else
			lastReason = reason
		end
	end
	if fed == 0 then
		local r = lastReason or "no_dragon"
		Nest.toast(player, Loc.text(Strings.Errors[r] or r, { n = "" }))
		return { ok = false, reason = r }
	end
	leaderCoins(player, data.coins)
	if not data.onboarding.fedOnce then
		services.PlayerData.update(player, "onboarding", function(o)
			o.fedOnce = true
			return nil
		end)
	end
	if services.Quest then -- "feeding"
		services.Quest.event(player, "feed")
	end
	if services.Analytics then -- funnel 7 + the coin spend
		services.Analytics.onboard(player, "feed_first")
		services.Analytics.coins(player, "Sink", spent, data.coins or 0, "Feed")
	end
	Nest.toast(player, Strings.Hatch.fed)
	return { ok = true, fed = fed, spent = spent }
end

-- 2.4: gift berries (06 §3 15 min, §4 day 2) - feeding without a price for up to n nest dragons, the most profitable first
-- returns how many were fed (0 - nobody: everyone is fed or the nest is empty)
function Nest.feedFree(player: Player, n: number): number
	local data = services.PlayerData.get(player)
	local nest = Nest.of(player)
	if not data or not nest then
		return 0
	end
	local now = os.time()
	local list = table.clone(data.nestOrder)
	table.sort(list, function(a, b)
		local da, db = data.dragons[a], data.dragons[b]
		return (da and Economy.dragonIncome(da, B) or 0) > (db and Economy.dragonIncome(db, B) or 0)
	end)
	local fed = 0
	for _, u in list do
		if fed >= n then
			break
		end
		local d = data.dragons[u]
		if d and Growth.feed(d, now, B) then
			fed += 1
			local m = anyModel(player, nest, data, u)
			if m then
				syncDragon(m, d, data, now)
			end
		end
	end
	if fed > 0 then
		services.PlayerData.replicate(player, { "dragons" })
	end
	return fed
end

-- the dragon's name (02 §2 the name window; 2.11): 2-20 characters, letters/digits/space/hyphen/apostrophe, a TextService filter before showing to others
local function cleanName(raw: string): string?
	local t = string.gsub(raw, "^%s+", "")
	t = string.gsub(t, "%s+$", "")
	t = string.gsub(t, "%s+", " ")
	if #t < 2 or #t > Config.Dragon.nameMaxLength or not string.match(t, "^[%w][%w%s'%-]*$") then
		return nil
	end
	return t
end

-- the last successful rename by UserId (not cleared on leaving - a rejoin to the same server does not lift the limit)
local lastRename: { [number]: number } = {}

function Nest.rename(player: Player, uid: string, raw: string): { ok: boolean, reason: string?, [string]: any }
	local cd = Config.Names.renameCooldown or 60
	local last = lastRename[player.UserId]
	if last and os.clock() - last < cd then
		return { ok = false, reason = "name_cooldown", n = math.ceil(cd - (os.clock() - last)) }
	end
	local data = services.PlayerData.get(player)
	local nest = Nest.of(player)
	if not data or not nest then
		return { ok = false, reason = "loading" }
	end
	local d = data.dragons[uid]
	if not d then
		return { ok = false, reason = "no_dragon" }
	end
	local text = cleanName(raw)
	if not text then
		return { ok = false, reason = "bad_name" }
	end
	local ok, filtered = pcall(function()
		local r = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if not ok then
		warn("[Nest] name filter: " .. tostring(filtered))
		return { ok = false, reason = "bad_name" }
	end
	if filtered ~= text then
		return { ok = false, reason = "bad_name" }
	end
	services.PlayerData.update(player, "dragons", function()
		d.name = text
		return nil
	end)
	lastRename[player.UserId] = os.clock()
	local m = dragonModel(nest, uid)
	if m then
		services.DragonVisuals.relabel(m, d)
	end
	if services.Movement then
		pcall(services.Movement.refresh, player) -- the same label on the companion
	end
	return { ok = true, name = text }
end

-- after a profile reset (Admin "reset"): the nest, the incubators, the table, the egg in hand and the coins anew from the data
function Nest.reapply(player: Player)
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	Nest.refresh(player)
	if services.Incubation and services.Incubation.restore then
		services.Incubation.restore(player)
	end
	if services.EggSpawner then
		services.EggSpawner.showCarry(player, data.eggs and data.eggs.carry)
		services.EggSpawner.tableEggs(player)
	end
	local nest = Nest.of(player)
	local pile = nest and nest:FindFirstChild("CoinPile")
	if pile then
		pile:SetAttribute("Pot", math.floor(data.pot or 0))
	end
	leaderCoins(player, data.coins or 0)
	if LP.spawnHome ~= false then -- after Reset - into the own pen, like a newcomer on join
		local hs = Nest.homeSpawn(player)
		local ch = player.Character
		if hs and ch then
			ch:PivotTo(hs.CFrame + Vector3.new(0, 3.5, 0))
			if services.AntiCheat then
				services.AntiCheat.moved(player)
			end
		end
	end
end

-- collecting the pile: "just walk up"; the coins fly to the counter (Notice coins, the client CoinFlight)
local lastCollect: { [Player]: number } = {}
local atPile: { [Player]: boolean } = {} -- the coin flight only on
-- ENTERING the pile radius (what accumulated while away); while standing nearby - the income goes straight to the counter, without a stream of icons

-- silent = true: without the coin flight and "+N" (standing by the pile)
local function collect(player: Player, nest: Model, data: any, silent: boolean?)
	local got = math.floor(data.pot or 0)
	if got <= 0 then
		return
	end
	local now = os.clock()
	if not silent and lastCollect[player] and now - lastCollect[player] < LP.collectEvery then
		return
	end
	lastCollect[player] = now
	services.PlayerData.update(player, "pot", function()
		return 0
	end)
	if not data.onboarding.coinsCollected then -- the "coins" step (02 §2 step 4) once
		services.PlayerData.update(player, "onboarding", function(o)
			o.coinsCollected = true
			return nil
		end)
		if services.Analytics then
			services.Analytics.onboard(player, "coins_first_collect")
		end
	end
	Nest.addCoins(player, got)
	if not silent and services.Analytics and services.Analytics.action then -- the returning player's first action - taking the pile
		services.Analytics.action(player, "collect")
	end
	local pile = nest:FindFirstChild("CoinPile") :: BasePart?
	if not silent then
		services.Net.notice(player, { kind = "coins", n = got, from = pile and pile.Position })
	end
	if pile then
		pile:SetAttribute("Pot", 0)
	end
end

-- once a second: growth, feeding expired -> CanFeed, the income into the pile, collection on approach
local function tick()
	local now = os.time()
	for player, idx in owners do
		local data = services.PlayerData.get(player)
		local nest = services.WorldBuilder.getNest(idx)
		if data and nest then
			local grew: { string } = {}
			for _, uid in data.nestOrder do
				local d = data.dragons[uid]
				if d and Growth.tick(d, now, B) then
					table.insert(grew, uid)
				end
			end
			if #grew > 0 then
				services.PlayerData.replicate(player, { "dragons" })
				Nest.refresh(player)
				for _, uid in grew do
					local d = data.dragons[uid]
					services.Net.notice(player, { kind = "stage_up", uid = uid, stage = d.stage, name = d.name, element = d.element })
					-- the firstborn's hatchling stage is now 60 s, the window of step 2 "Wings of a hatchling" is narrow.
					-- The firstborn grew while the player never glided - close the step by the counter (Quest.set: without the Glider badge, without onboarding.glided),
					-- otherwise the Keeper's chain stays at step 2 and rewards 3-8 are unreachable (gliding only with a stage-0 companion)
					if d.stage == 1 and d.growAs and services.Quest and not (data.onboarding and data.onboarding.glided) then
						task.delay(3, function() -- review: one banner, "Done!" wiped "Your dragon grew up! Ride it!" - growth first
							if player.Parent == Players and services.Quest then
								services.Quest.set(player, "glide", 1)
							end
						end)
					end
					if d.stage >= 3 and services.Quest then -- the first elder
						services.Quest.event(player, "elder")
					end
					if services.Reward then -- 2.4: the daily "Grow a dragon one stage"
						services.Reward.event(player, "grow")
						services.Reward.event(player, "growEl_" .. tostring(d.element)) -- the weekly quest Cinder (spec 06 add. 21.10)
					end
					if services.Analytics then -- stage progression, funnel 8/11
						services.Analytics.stage(player, d.stage, (now - (d.hatchedAt or now)) / 60)
						if d.stage == 1 then
							services.Analytics.onboard(player, "juvenile_first", { minutes = math.floor((now - (d.hatchedAt or now)) / 60) })
						elseif d.stage == 2 then
							services.Analytics.onboard(player, "adult_first", { minutes = math.floor((now - (d.hatchedAt or now)) / 60) })
						end
					end
				end
			else
				for _, uid in data.nestOrder do
					local d = data.dragons[uid]
					local m = d and anyModel(player, nest, data, uid)
					if m and (m:HasTag("CanFeed") ~= (d.stage < 3 and not Growth.isFed(d, now))) then
						syncDragon(m, d, data, now)
					end
				end
			end
			-- the Index bonus; 2.1: VIP, x2, the boost (Shop.rateMods), auto-collect without a pile and a ceiling (07 §2 no. 5), the boost seconds
			local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) }
			-- the income for the "N minutes of income" rewards (Reward.minutesCoins: without friends and weather) - the client writes the number on the tiles
			nest:SetAttribute("GiftRate", Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B))
			-- friends on the server +10%/friend up to +40% (08 §1, Social), a storm and an Update Party x2 (04 §7, 09 §1, Weather)
			mods.friends = if services.Social then services.Social.friendsOf(player) else 0
			mods.weatherMult = if services.Weather then services.Weather.coinsMult() else 1
			local rate = Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
			nest:SetAttribute("Rate", rate)
			-- the nest multiplier = the income / the sum of the base values; the labels are real
			local baseSum = 0
			for _, d in Dragons.nestList(data) do
				baseSum += Economy.dragonIncome(d :: any, B)
			end
			local mult = if baseSum > 0 then rate / baseSum else 1
			local oldMult = nest:GetAttribute("RateMult")
			if typeof(oldMult) ~= "number" or math.abs(oldMult - mult) > 1e-3 then
				nest:SetAttribute("RateMult", mult)
				Nest.relabelIncome(player, nest)
			end
			if services.Shop then
				services.Shop.tick(player, data, LP.tickSeconds)
			end
			if rate > 0 then
				if services.Shop and services.Shop.hasAutoCollect(data) then
					Nest.addCoins(player, rate * LP.tickSeconds)
				else
					local cap = Economy.potCap(rate, B)
					services.PlayerData.update(player, "pot", function(p)
						return math.min((p or 0) + rate * LP.tickSeconds, cap)
					end)
				end
			end
			local pile = nest:FindFirstChild("CoinPile") :: BasePart?
			if pile then
				pile:SetAttribute("Pot", math.floor(data.pot or 0))
				local pos = Nest.rootPos(player)
				local near = pos ~= nil and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(pile.Position.X, 0, pile.Position.Z)).Magnitude <= LP.collectRadius
				if near then
					collect(player, nest, data, atPile[player] == true) -- entering: with a flight; standing: quietly into the counter
					atPile[player] = true
				else
					atPile[player] = false
				end
			end
		end
	end
end

-- 2.5 (spec 05 §8, 06 §9): the "while you were away" summary on join - before the first tick pass (the rate before growth, Growth.tick
-- raises the stages by itself); coins not taken last time carry over into the new record; the coins to the account - on Collect (claimAway)
local function awayOnJoin(player: Player, data: any)
	if not services.PlayerData.canSave(player) then
		return -- a template without saving: neither income nor a card
	end
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0, indexPct = IndexCore.pct(data.index) }
	local s = Offline.summary(data, services.PlayerData.joinLastSeen(player), os.time(), mods, B)
	local rec = Offline.merge(data.away, s)
	services.PlayerData.update(player, "away", function()
		return rec
	end)
	if s and services.Analytics then -- 11 §2: away_screen (value = hours away)
		services.Analytics.custom(player, "away_screen", math.floor(s.seconds / 360) / 10, { coins = s.coins, eggs = s.eggs, grew = #s.grew })
	end
end

function Nest.claimAway(player: Player): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local n = if type(data.away) == "table" then math.max(0, math.floor(tonumber(data.away.coins) or 0)) else 0
	services.PlayerData.update(player, "away", function()
		return Offline.empty()
	end)
	if n > 0 then
		Nest.addCoins(player, n, "Offline")
		services.Net.notice(player, { kind = "coins", n = n })
	end
	return { ok = true, coins = n }
end

local function assign(player: Player)
	services.PlayerData.waitProfileOrLeave(player, 15) -- the profile or a refusal (a template without saving)
	local data = services.PlayerData.get(player)
	if player.Parent ~= Players then
		return
	end
	if data then
		local okA, errA = pcall(awayOnJoin, player, data)
		if not okA then
			warn("[Nest] away: " .. tostring(errA))
		end
	end
	-- 1.14: bot nests (Admin, FPS measurement) are not given to live players; none free - a bot gives up its own (a live player outranks the load)
	local pick: number? = nil
	for i = 1, Config.World.nests.count do
		local n = services.WorldBuilder.getNest(i)
		if byIndex[i] == nil and not (n and n:GetAttribute("Bot")) then
			pick = i
			break
		end
	end
	if not pick and services.Admin and services.Admin.yieldBot then
		pick = services.Admin.yieldBot()
	end
	if pick and byIndex[pick] == nil then
		local i = pick
		byIndex[i] = player
		owners[player] = i
		local nest = services.WorldBuilder.getNest(i)
		if nest then
			nest:SetAttribute("OwnerId", player.UserId)
			nest:SetAttribute("OwnerName", player.DisplayName)
			setSign(nest, Loc.text(Strings.Loop.yourNest, { player = player.DisplayName }))
		end
	end
	if data then
		leaderCoins(player, data.coins or 0)
	end
	if LP.spawnHome ~= false then -- spawning in the own pen (join and respawns)
		local hs = Nest.homeSpawn(player)
		if hs then
			player.RespawnLocation = hs
		end
	end
	player:LoadCharacter()
	-- every step separately under pcall - a failure of one (e.g. a dragon model) must not leave the table without eggs
	for name, fn in { refresh = function()
		Nest.refresh(player)
	end, restore = function()
		if services.Incubation and services.Incubation.restore then
			services.Incubation.restore(player)
		end
	end, table = function()
		if services.EggSpawner and services.EggSpawner.tableEggs then
			services.EggSpawner.tableEggs(player)
		end
	end } do
		local ok, err = pcall(fn)
		if not ok then
			warn("[Nest] assign " .. name .. ": " .. tostring(err))
		end
	end
end

local function release(player: Player)
	local i = owners[player]
	owners[player] = nil
	lastCollect[player] = nil
	atPile[player] = nil
	if not i then
		return
	end
	byIndex[i] = nil
	local nest = services.WorldBuilder.getNest(i)
	if nest then
		nest:SetAttribute("OwnerId", nil)
		nest:SetAttribute("OwnerName", nil)
		nest:SetAttribute("Rate", nil)
		setSign(nest, Loc.text(Strings.World.freeNest, { n = i }))
		for s = 1, 10 do
			services.DragonVisuals.clearSlot(nest, s)
		end
		if services.Incubation and services.Incubation.clearNest then
			services.Incubation.clearNest(nest)
		end
		if services.EggSpawner and services.EggSpawner.resetTable then
			services.EggSpawner.resetTable(nest)
		end
		local pile = nest:FindFirstChild("CoinPile")
		if pile then
			pile:SetAttribute("Pot", nil)
		end
	end
end

-- the trail coins: the first to touch gets them, the coin hides until respawnSeconds
local function hookTrailCoin(coin: Instance)
	if not coin:IsA("BasePart") then
		return
	end
	local busy = false
	coin.CanTouch = true
	coin.Touched:Connect(function(hit)
		if busy then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent)
		if not player or not owners[player] then
			return
		end
		-- a touch counts only if the honest position is near (a teleport onto the coin and a touch from afar do not pass)
		local at = Nest.rootPos(player)
		if not at or (at - coin.Position).Magnitude > coin.Size.Magnitude / 2 + Config.World.coins.touchSlack then
			return
		end
		if services.AntiCheat then -- the collection rate (a mark only)
			services.AntiCheat.note(player, "coin")
		end
		busy = true
		local parts = { coin }
		for _, d in coin:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(parts, d)
			end
		end
		local old: { [BasePart]: number } = {}
		for _, p in parts do
			old[p] = p.Transparency
			p.Transparency = 1
		end
		local gui = coin:FindFirstChildWhichIsA("BillboardGui")
		if gui then
			gui.Enabled = false
		end
		Nest.addCoins(player, Config.World.coins.value)
		services.Net.notice(player, { kind = "coins", n = Config.World.coins.value, from = coin.Position })
		task.delay(Config.World.coins.respawnSeconds, function()
			for p, t in old do
				p.Transparency = t
			end
			if gui then
				gui.Enabled = true
			end
			busy = false
		end)
	end)
end

-- Studio only (like Admin 1.14 "/give", "/time"): ServerStorage.LoopDebug:Invoke("table 1" | "place 1" | "hatch 1" |
-- "time 600" | "feed 1" | "feed all" | "go pile" | "go table" | "go inc" | "state") - a loop check from execute_luau without presses
local function debugHook()
	if not game:GetService("RunService"):IsStudio() then
		return
	end
	local bf = Instance.new("BindableFunction")
	bf.Name = "LoopDebug"
	bf.OnInvoke = function(cmd: string)
		local player = Players:GetPlayers()[1]
		if not player then
			return "no player"
		end
		local data = services.PlayerData.get(player)
		local nest, idx = Nest.of(player)
		local verb, arg = string.match(cmd, "^(%a+)%s*(%-?%w*)")
		local n = tonumber(arg) or 1
		local reply: any = nil
		if verb == "table" then
			reply = services.EggSpawner.pickTable(player, n)
		elseif verb == "place" then
			reply = services.Incubation.place(player, n)
		elseif verb == "hatch" then
			reply = services.Incubation.hatchSlot(player, n)
		elseif verb == "feed" and data then
			reply = Nest.feed(player, if arg == "all" then "all" else (data.nestOrder[n] or ""))
		elseif verb == "go" and nest then -- teleport the character to a nest object (a "just walk up" check)
			local inc = nest:FindFirstChild("Incubators")
			local target = if arg == "pile" then nest:FindFirstChild("CoinPile") elseif arg == "table" then nest:FindFirstChild("EggTable") elseif arg == "inc" and inc then inc:FindFirstChild("Incubator1") else nil
			local ch = player.Character
			if target and ch and target:IsA("BasePart") then
				local at = target.Position
				if arg == "inc" then -- the bowl has an invisible stop along the rim - stand next to it on the entrance side (toward the nest center - the table)
					at += nest:GetPivot():VectorToWorldSpace(Vector3.new(0, 0, -3.3))
				end
				ch:PivotTo(CFrame.new(at + Vector3.new(0, 3, 0)))
				if services.AntiCheat then -- a server relocation (probes with the protection on)
					services.AntiCheat.moved(player)
				end
			end
		elseif (verb == "mount" or verb == "dismount" or verb == "comp" or verb == "shore" or verb == "land" or verb == "warp" or verb == "dupguard" or verb == "regroup") and services.Movement then -- 1.9; shore; regroup
			reply = services.Movement.debug(player, verb, arg)
		elseif verb == "abgrow" then -- the firstborn growth test in Studio before D0: "abgrow B" / "abgrow A" - the group forced, "abgrow off" - as live
			local ab = Config.Balance.firstDragon.ab
			ab.force = if arg == "A" or arg == "B" then arg else nil
			reply = { ok = true, reason = string.format("force=%s group=%s", tostring(ab.force), require(Shared:WaitForChild("Core"):WaitForChild("Experiments")).growGroup(player.UserId, ab, os.time())) }
		elseif verb == "firstegg" and services.Incubation then -- "firstegg off" - the manual path of the first egg for probes (hatch_check)
			reply = (services.Incubation :: any).debugFirstEgg(arg)
		elseif verb == "gc" then -- the Lua heap of the server VM
			reply = { ok = true, reason = string.format("gc=%.1fMB", collectgarbage("count") / 1024) }
		elseif verb == "combat" and services.Combat then -- "combat info" | "combat stage 4"
			local sub, subArg = string.match(cmd, "^/?combat%s*(%a*)%s*(.-)%s*$")
			reply = services.Combat.debug(player, sub or "info", subArg or "")
		elseif verb == "raid" and services.Raid then -- "raid" | "raid go 0" | "raid home" | "raid reset" | "raid off" | "raid on"
			local sub, subArg = string.match(cmd, "^/?raid%s*(%a*)%s*(.-)%s*$")
			local g = services.Raid.debug(player, sub or "info", subArg or "")
			reply = if typeof(g) == "table" then g else { ok = true, reason = tostring(g) }
		elseif verb == "glow" and services.GlowEgg then -- "glow" | "glow ready" | "glow reset" (Services/GlowEgg)
			local g = services.GlowEgg.debug(player, arg)
			reply = if typeof(g) == "table" then g else { ok = true, reason = tostring(g) } -- a string - into reason (visible in probes)
		elseif verb == "quest" and services.Quest then -- "quest" | "quest hatch" | "quest reset"
			reply = services.Quest.debug(player, arg)
		elseif verb == "reward" and services.Reward then -- 2.4: "reward" | "reward time 600" | "reward day" | "reward daily eggFound 3" | "reward reset"
			reply = services.Reward.debug(player, string.match(cmd, "^reward%s*(.*)$") or "")
		elseif verb == "index" and services.Index then -- "index" | "index ember" (open all rarities of the element)
			reply = services.Index.debug(player, arg)
		elseif verb == "shop" and services.Shop then -- 2.1: "shop state" | "shop <sku> [pick]" | "shop HatchNow 1" | "shop pass VIP_299" (the whole argument: keys with "_")
			reply = services.Shop.debug(player, string.match(cmd, "^shop%s*(.*)$") or "")
		elseif verb == "looks" and services.Looks then -- looks: "looks" | "looks give all" | "looks preset 1 sunset" | "looks skin royal" | "looks trail" | "looks reset"
			reply = services.Looks.debug(player, string.match(cmd, "^looks%s*(.*)$") or "")
		elseif verb == "setcomp" and data then -- "setcomp ember3" - the companion's element and stage (for showcase shots)
			local el, st, rr = string.match(arg or "", "^(%a-)(%d)(%a?)$") -- "setcomp ember1c" - the Common rarity too
			local stage = tonumber(st)
			if el and table.find(Config.Elements, el) and stage and stage <= 3 and data.companion and data.dragons[data.companion] then
				services.PlayerData.update(player, "dragons", function(ds)
					local d = ds[data.companion or ""]
					if d then
						d.element = el
						d.stage = stage :: number
						d.stageEndsAt = nil
						if rr == "c" then
							d.rarity = "Common"
						end
					end
					return nil
				end)
				if services.Movement then
					services.Movement.refresh(player)
				end
				Nest.refresh(player)
				reply = { ok = true, reason = el .. tostring(st) }
			else
				reply = { ok = false, reason = "bad_request" }
			end
		elseif verb == "showcase" then -- all elements and stages side by side on the glade (a check of rigs and looks)
			local old = workspace:FindFirstChild("Showcase")
			if old then
				old:Destroy()
			end
			local f = Instance.new("Folder")
			f.Name = "Showcase"
			f.Parent = workspace
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.FilterDescendantsInstances = { f }
			params.IgnoreWater = true
			local count = 0
			for si, stage in { 0, 1, 2, 3 } do
				for ei, el in Config.Elements do
					local x = -75 + (ei - 1) * 30
					local z = -205 - (si - 1) * 28 -- the northern glade (in the south z 215+ is water)
					local hit = workspace:Raycast(Vector3.new(x, 80, z), Vector3.new(0, -120, 0), params)
					local gy = if hit then hit.Position.Y else 2
					local ok, err = pcall(function()
						local m = services.DragonVisuals.build({ uid = "show_" .. el .. stage, element = el, rarity = "Rare", stage = stage, name = el .. " " .. tostring(stage) }, true)
						m:SetAttribute("Showcase", true)
						m:PivotTo(CFrame.lookAt(Vector3.new(x, gy + 10, z), Vector3.new(x, gy + 10, z + 50))) -- the snout toward the terrace
						local cf, size = m:GetBoundingBox()
						m:PivotTo(m:GetPivot() + Vector3.new(0, gy + size.Y / 2 - cf.Position.Y, 0))
						m.Parent = f
						count += 1
					end)
					if not ok then
						warn("[Nest] showcase " .. el .. stage .. ": " .. tostring(err))
					end
				end
			end
			reply = { ok = true, reason = "placed " .. count }
		elseif (verb == "bots" or verb == "give" or verb == "perf") and services.Admin then -- 1.14: Admin commands from Studio probes
			reply = services.Admin.run(player, cmd)
		elseif verb == "yieldbot" and services.Admin then -- 1.14: a bot's nest to a live player (as in assign on a full server)
			reply = { ok = true, reason = tostring(services.Admin.yieldBot()) }
		elseif verb == "dump" and data then -- the whole profile (JSON) for the "leave - return" probe (ServerStorage.StudioSeed)
			data.lastSeen = os.time()
			return game:GetService("HttpService"):JSONEncode(data)
		elseif verb == "time" and data then
			for _, rec in data.eggs.incubating do
				rec.endsAt -= n
			end
			for _, d in data.dragons do
				if d.stageEndsAt then
					d.stageEndsAt -= n
				end
			end
		end
		task.wait(0.1)
		data = services.PlayerData.get(player)
		if not data then
			return "no data"
		end
		local parts = { "reply=" .. (if reply then (tostring(reply.ok) .. "/" .. tostring(reply.reason)) else "-"), "nest=" .. tostring(idx), "coins=" .. math.floor(data.coins or 0), "pot=" .. math.floor(data.pot or 0), "carry=" .. (if data.eggs.carry then data.eggs.carry.rarity .. "/" .. data.eggs.carry.element else "-") }
		for k, rec in data.eggs.incubating do
			table.insert(parts, "inc" .. k .. "=" .. rec.egg.element .. ":" .. (rec.endsAt - os.time()))
		end
		for _, uid in data.nestOrder do
			local d = data.dragons[uid]
			table.insert(parts, uid .. "=" .. d.rarity .. "/" .. d.element .. "/s" .. d.stage .. "/" .. tostring(d.stageEndsAt and d.stageEndsAt - os.time()) .. (if Growth.isFed(d, os.time()) then "/fed" else ""))
		end
		return table.concat(parts, " ")
	end
	bf.Parent = game:GetService("ServerStorage")
end

function Nest.init(s: { [string]: any })
	services = s
end

function Nest.start()
	while #services.WorldBuilder.nests < Config.World.nests.count do -- the nests are built by WorldBuilder.start (~6 s), the starts run in parallel
		task.wait(0.25)
	end
	-- CharacterAutoLoads is off (10 §2), and after the character's death nobody respawned it (P8 probe: after 6 s neither a character nor
	-- a companion). After respawnSeconds - LoadCharacter; the companion is rebuilt by Movement on CharacterAdded
	local function hookRespawn(player: Player)
		local function onChar(ch: Model)
			local hum = ch:WaitForChild("Humanoid", 10)
			if hum and hum:IsA("Humanoid") then
				hum.Died:Connect(function()
					task.delay(LP.respawnSeconds, function()
						if player.Parent == Players and owners[player] and player.Character == ch then
							player:LoadCharacter()
						end
					end)
				end)
			end
		end
		player.CharacterAdded:Connect(onChar)
		if player.Character then
			task.spawn(onChar, player.Character)
		end
	end
	Players.PlayerAdded:Connect(hookRespawn)
	for _, p in Players:GetPlayers() do
		hookRespawn(p)
	end
	services.Net.handle("Feed", function(player: Player, uid: string)
		return Nest.feed(player, uid)
	end)
	services.Net.handle("NameDragon", function(player: Player, uid: string, text: string)
		return Nest.rename(player, uid, text)
	end)
	services.Net.handle("Buy", function(player: Player, key: string) -- an incubator / a slot / the shelf for coins
		return Nest.buy(player, key)
	end)
	services.Net.handle("MoveDragon", function(player: Player, uid: string, to: string) -- nest <-> sanctuary
		return Nest.moveDragon(player, uid, to)
	end)
	services.Net.handle("Release", function(player: Player, uid: string, confirm: boolean) -- a release for 120 s of income
		return Nest.release(player, uid, confirm)
	end)
	debugHook()
	for _, c in CollectionService:GetTagged("TrailCoin") do
		hookTrailCoin(c)
	end
	Players.PlayerAdded:Connect(function(p)
		task.spawn(assign, p)
	end)
	Players.PlayerRemoving:Connect(release)
	for _, p in Players:GetPlayers() do
		task.spawn(assign, p)
	end
	task.spawn(function()
		while true do
			task.wait(LP.tickSeconds)
			local ok, err = pcall(tick)
			if not ok then
				warn("[Nest] tick: " .. tostring(err))
			end
		end
	end)
end

return Nest
