--!strict
-- 2.6: the social layer of spec 08 without chat. The logic - Core/Social, the numbers - Config.Social, the texts - Strings.Social.
-- §1 friends on the server: the number of Roblox friends among the other players (IsFriendsWithAsync, cached per session) - the player attribute
-- FriendsOn (Nest adds +10% per friend up to +40% to the income, the HUD shows the line).
-- §2 Hatch Party: a foreign player stands at your warming egg for partyHold s (r = partyRadius) -> the remainder / 2, a friend / 3, once per
-- egg; sparks above the ring, toasts to both, the day event party to the helper. One who came by an invite (LaunchData party:<UserId>
-- or ReferredByPlayerId) appears at the inviter's nest.
-- a friend with an account of minAccountDays stayed minActiveSec without AFK -> an egg to both
-- (base; the friend's Premium / IsVerified / AgeChecked -> top) onto the shelf; to the friend once, to the inviter perDay per day (the DataStore).
-- §3-4 server announcements: a rare nest on the island, who took it, an Epic+ hatch; the Top nests board at Old Ash (every boardEvery s);
-- the income on the nest sign.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local SocialCore = require(Core:WaitForChild("Social"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Eggs = require(Core:WaitForChild("Eggs"))
local Economy = require(Core:WaitForChild("Economy"))
local Format = require(Core:WaitForChild("Format"))

local Social = {}

local services: { [string]: any } = {}
local B = Config.Balance
local SC = Config.Social
local T = Strings.Social
local SI = SC.invite -- the invite reward
local rng = Random.new()

local friendCache: { [string]: boolean } = {} -- "<min UserId>:<max UserId>" -> friends (friendship is symmetric, one request per pair)
local near: { [string]: number } = {} -- "<helper>|<nest>|<slot>" -> seconds nearby


local function title(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

-- ---------------------------------------------------------------------------------------------- §1 friends
local function pairKey(a: number, b: number): string
	return if a < b then a .. ":" .. b else b .. ":" .. a
end

local function isFriend(a: Player, b: Player): boolean
	local k = pairKey(a.UserId, b.UserId)
	if friendCache[k] == nil then
		local ok, res = pcall(function()
			return (a :: any):IsFriendsWithAsync(b.UserId)
		end)
		if not ok then
			return false -- an API failure: not cached, we ask at the next recount
		end
		friendCache[k] = res == true
	end
	return friendCache[k] == true
end

function Social.isFriend(a: Player, b: Player): boolean
	return isFriend(a, b)
end

local recounting, again = false, false
local function recountNow()
	for _, p in Players:GetPlayers() do
		local n = 0
		for _, q in Players:GetPlayers() do
			if q ~= p and isFriend(p, q) then
				n += 1
			end
		end
		local old = p:GetAttribute("FriendsOn")
		if old ~= n then
			p:SetAttribute("FriendsOn", n)
			if services.Analytics and n > 0 then
				services.Analytics.custom(p, "friend_boost_active", n)
			end
		end
	end
end

-- one recount at a time; a join/leave during the recount - one more pass after
local function recount()
	if recounting then
		again = true
		return
	end
	recounting = true
	repeat
		again = false
		local ok, err = pcall(recountNow)
		if not ok then
			warn("[Social] friends: " .. tostring(err))
		end
	until not again
	recounting = false
end

-- for Economy.nestRate (mods.friends)
function Social.friendsOf(player: Player): number
	return (player:GetAttribute("FriendsOn") :: number?) or 0
end

-- ---------------------------------------------------------------------------------------------- §2 Hatch Party
local function sparkleRing(ring: BasePart)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "PartySparkle"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = SC.partyParticles
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Speed = NumberRange.new(3, 6)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 140, 200))
	pe.LightEmission = 1
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = ring
	task.delay(SC.partySeconds, function()
		pe.Enabled = false
		task.wait(1.5)
		pe:Destroy()
	end)
end

local function party(owner: Player, helper: Player, nest: Model, slot: number)
	local key = tostring(slot)
	local friend = isFriend(owner, helper)
	local div = SocialCore.partyDiv(friend, B)
	local now = os.time()
	local saved = 0
	local okUpd = services.PlayerData.update(owner, "eggs", function(e)
		local rec = e.incubating[key]
		if SocialCore.partyAllowed(rec, now, SC.partyMinLeft) then
			saved = SocialCore.applyParty(rec, now, div, helper.UserId)
		end
		return nil
	end)
	if not okUpd or saved <= 0 then
		return
	end
	if services.Incubation and services.Incubation.resync then
		services.Incubation.resync(owner, key)
	end
	local inc = nest:FindFirstChild("Incubators")
	local ring = inc and inc:FindFirstChild("Incubator" .. slot)
	if ring and ring:IsA("BasePart") then
		sparkleRing(ring)
	end
	local text = if friend then Loc.text(T.friendParty, { name = helper.DisplayName }) else Loc.text(T.partyDone, { name = helper.DisplayName })
	services.Nest.toast(owner, text)
	services.Nest.toast(helper, if friend then Loc.text(T.friendPartyHelper, { name = owner.DisplayName }) else Loc.text(T.partyHelper, { name = owner.DisplayName }))
	if services.Analytics then
		services.Analytics.custom(owner, "hatch_party_done", saved, { role = "owner", friend = if friend then "1" else "0" })
		services.Analytics.custom(helper, "hatch_party_done", saved, { role = "helper", friend = if friend then "1" else "0" })
	end
	if services.Reward then -- 06 §2 Hard: "Help in a Hatch Party" - to the helper
		services.Reward.event(helper, "party")
	end
	if services.Badges then -- 06 §5: the Hatch Party badge to both
		services.Badges.award(owner, "party")
		services.Badges.award(helper, "party")
	end
end

local function partyTick(dt: number)
	local seen: { [string]: boolean } = {}
	for i = 1, Config.World.nests.count do
		local owner = services.Nest.ownerOf(i)
		local nest = services.WorldBuilder.getNest(i)
		local data = owner and services.PlayerData.get(owner)
		local inc = nest and nest:FindFirstChild("Incubators")
		if owner and data and inc then
			local now = os.time()
			for key, rec in data.eggs.incubating do
				if SocialCore.partyAllowed(rec, now, SC.partyMinLeft) then
					local ring = inc:FindFirstChild("Incubator" .. key)
					if ring and ring:IsA("BasePart") then
						for _, p in Players:GetPlayers() do
							if p ~= owner then
								local pos = services.Nest.rootPos(p)
								if pos and (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(ring.Position.X, 0, ring.Position.Z)).Magnitude <= SC.partyRadius and math.abs(pos.Y - ring.Position.Y) < 8 then
									local k = p.UserId .. "|" .. i .. "|" .. key
									seen[k] = true
									near[k] = (near[k] or 0) + dt
									if near[k] >= SC.partyHold then
										near[k] = nil
										party(owner, p, nest :: Model, tonumber(key) or 1)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	for k in near do
		if not seen[k] then
			near[k] = nil
		end
	end
end

-- ---------------------------------------------------------------------------------------------- the invite reward
-- The friend's profile: data.invite = { by = the inviter's UserId (the first invite), sec = seconds in the game without AFK since, got = the rarity
-- of the granted egg ("" - not yet), at }. The inviter's counter - the DataStore record SI.store (Core/Social.inviterSlot).
local inviteBase: { [Player]: number } = {} -- seconds by invite before this session (GiftSec Reward counts from zero every session)
local inviteBusy: { [Player]: boolean } = {}
local inviteStore: DataStore? = nil

local function today(): string
	return os.date("!%Y-%m-%d") :: string
end

local function inviteOf(data: any): any?
	if typeof(data) ~= "table" then
		return nil
	end
	if typeof(data.invite) ~= "table" then
		data.invite = { by = 0, sec = 0, got = "", at = 0 }
	end
	return data.invite
end

-- the friend's account signs (pcall: the properties are new - HasRobloxSubscription instead of the deprecated MembershipType, AgeChecked; IsVerified
-- only on the server and always false in Studio)
local function premiumOf(p: Player): boolean
	local ok, v = pcall(function()
		return (p :: any).HasRobloxSubscription
	end)
	if ok and typeof(v) == "boolean" then
		return v
	end
	return p.MembershipType == Enum.MembershipType.Premium
end

local function verifiedOf(p: Player): boolean
	local ok, v = pcall(function()
		return p:IsVerified()
	end)
	return ok and v == true
end

local function ageCheckedOf(p: Player): boolean
	local ok, v = pcall(function()
		return (p :: any).AgeChecked == (Enum :: any).AgeCheckStatus.Checked
	end)
	return ok and v == true
end

local function rarityFor(p: Player): string
	return SocialCore.inviteRarity(premiumOf(p), verifiedOf(p), ageCheckedOf(p), SI)
end

local function eggText(rarity: string): any
	return Loc.text(if rarity == SI.top then T.inviteEggLegendary else T.inviteEggEpic)
end

-- an egg onto the shelf bypassing the "one-dragon day" (Reward.giveEgg would give coins); a free bowl takes it by itself (Incubation shelfAuto)
local function giveInviteEgg(p: Player, rarity: string): boolean
	local egg: any = Eggs.rollGuaranteed("invite", SI.zone, rarity, function()
		return rng:NextNumber()
	end, B, Config.Elements)
	egg.rarity = rarity -- exactly this rarity (rollGuaranteed gives "no lower than")
	egg.invite = true -- Incubation: hatching like a raid egg
	egg.foundAt = os.time()
	local ok = services.PlayerData.update(p, "eggs", function(e)
		e.shelf = e.shelf or {}
		table.insert(e.shelf, egg)
		return nil
	end)
	if ok and services.Incubation and services.Incubation.syncShelfOf then
		pcall(services.Incubation.syncShelfOf, p)
	end
	return ok
end

local function gotBanner(p: Player, rarity: string, otherName: any) -- a name or Loc.text(T.yourFriend)
	services.Net.notice(p, { kind = "announce", text = Loc.text(T.inviteGot), sub = Loc.text(T.inviteGotSub, { name = otherName, egg = eggText(rarity) }) })
end

-- the inviter's counter: "ok" (there was room; pending - the egg went into his queue), "limit" (the day is used up / the queue is full), "error"
local function inviterSlot(inviterId: number, pending: { f: number, r: string }?): string
	if not inviteStore then
		local okS, st = pcall(function()
			return DataStoreService:GetDataStore(SI.store)
		end)
		if not okS then
			warn("[Social] invite store: " .. tostring(st))
			return "error"
		end
		inviteStore = st
	end
	local store = inviteStore :: DataStore
	local day = today()
	for try = 1, 3 do
		local full = false
		local ok, err = pcall(function()
			store:UpdateAsync("u" .. inviterId, function(old)
				local rec = SocialCore.inviterSlot(old, day, SI, pending)
				full = rec == nil
				return rec -- nil - the record does not change
			end)
		end)
		if ok then
			return if full then "limit" else "ok"
		end
		warn("[Social] invite slot " .. try .. ": " .. tostring(err))
		task.wait(try * 2)
	end
	return "error"
end

-- the inviter joined: the eggs from the queue (the friend reached 10 minutes while he was away)
local function claimPending(player: Player)
	if not (SI and SI.on) then
		return
	end
	local okS, store = pcall(function()
		return inviteStore or DataStoreService:GetDataStore(SI.store)
	end)
	if not okS or not store then
		return
	end
	inviteStore = store
	local got: { any } = {}
	local ok, err = pcall(function()
		store:UpdateAsync("u" .. player.UserId, function(old)
			got = {}
			if typeof(old) ~= "table" or typeof(old.p) ~= "table" or #old.p == 0 then
				return nil
			end
			got = old.p
			local rec = table.clone(old)
			rec.p = nil
			return rec
		end)
	end)
	if not ok then
		warn("[Social] invite pending: " .. tostring(err))
		return
	end
	for _, it in got do
		if player.Parent ~= Players then
			warn("[Social] invite pending lost on leave: " .. player.UserId)
			return
		end
		local rarity = if it.r == SI.top then SI.top else SI.base
		if giveInviteEgg(player, rarity) then
			local okN, name = pcall(function()
				return Players:GetNameFromUserIdAsync(tonumber(it.f) or 0)
			end)
			gotBanner(player, rarity, if okN and typeof(name) == "string" then name else Loc.text(T.yourFriend))
			if services.Analytics then
				services.Analytics.custom(player, "invite_reward", 1, { role = "inviter", rarity = rarity, late = "1" })
			end
			task.wait(4)
		end
	end
end

-- the friend reached the time: an egg to both. test - the game owner on the test place is his own "friend" (without the got mark, Config ownerTest)
local function inviteGrant(p: Player, inviterId: number, test: boolean)
	local rarity = rarityFor(p)
	if p.Parent ~= Players then
		return
	end
	if test then
		services.Nest.toast(p, string.format("Invite test: account %d days, Premium %s, verified %s, age check %s -> %s",
			p.AccountAge, tostring(premiumOf(p)), tostring(verifiedOf(p)), tostring(ageCheckedOf(p)), rarity))
	else
		-- the mark before the egg: a failure between the steps does not give a second reward
		local okMark = services.PlayerData.update(p, "invite", function(iv)
			iv.got = rarity
			iv.at = os.time()
			return nil
		end)
		if not okMark then
			return
		end
	end
	local inviter = Players:GetPlayerByUserId(inviterId)
	giveInviteEgg(p, rarity)
	gotBanner(p, rarity, if inviter then inviter.DisplayName else Loc.text(T.yourFriend))
	if services.Analytics then
		services.Analytics.custom(p, "invite_reward", 1, { role = "friend", rarity = rarity, inviter = tostring(inviterId) })
	end
	local res = inviterSlot(inviterId, if inviter then nil else { f = p.UserId, r = rarity })
	if inviter and inviter.Parent == Players then
		if res == "limit" then
			services.Nest.toast(inviter, Loc.text(T.inviteLimit, { n = SI.perDay }))
		else -- "error": the DataStore did not answer - the egg anyway (the promise to both matters more than a rare extra beyond the limit)
			task.wait(if inviter == p then 4 else 0)
			giveInviteEgg(inviter, rarity)
			gotBanner(inviter, rarity, p.DisplayName)
		end
	end
	if services.Analytics then
		services.Analytics.custom(p, "invite_inviter", 1, { res = res, here = if inviter then "1" else "0", rarity = rarity })
	end
end

local function inviteTick()
	for _, p in Players:GetPlayers() do
		local base = inviteBase[p]
		local iv = base and inviteOf(services.PlayerData.get(p))
		if not iv or inviteBusy[p] then
			continue
		end
		local sec = (base :: number) + ((p:GetAttribute("GiftSec") :: number?) or 0)
		local test = (SI.ownerTest or 0) > 0 and not RunService:IsStudio() and services.Admin and services.Admin.allowed(p)
		if test and sec >= SI.ownerTest and not p:GetAttribute("InviteTested") then
			p:SetAttribute("InviteTested", true) -- once per session
			inviteBusy[p] = true
			task.spawn(function()
				local ok, err = pcall(inviteGrant, p, p.UserId, true)
				inviteBusy[p] = nil
				if not ok then
					warn("[Social] invite test: " .. tostring(err))
				end
			end)
			continue
		end
		local by = tonumber(iv.by) or 0
		if by <= 0 or (iv.got or "") ~= "" then
			continue
		end
		iv.sec = sec
		if SocialCore.inviteAged(p.AccountAge, SI) and SocialCore.inviteReady(sec, SI) then
			inviteBusy[p] = true
			task.spawn(function()
				local ok, err = pcall(inviteGrant, p, by, false)
				inviteBusy[p] = nil
				if not ok then
					warn("[Social] invite grant: " .. tostring(err))
				end
			end)
		end
	end
end

-- came by an invite: remember who invited (the reward - inviteTick); a promise to the friend and the inviter, or honestly "the account is young"
local function inviteJoined(player: Player, inviterId: number)
	if not (SI and SI.on) or inviterId == player.UserId then
		return
	end
	local iv = inviteOf(services.PlayerData.get(player))
	if not iv or (iv.got or "") ~= "" then
		return
	end
	if (tonumber(iv.by) or 0) <= 0 then
		iv.by = inviterId
	elseif iv.by ~= inviterId then
		return -- the reward goes to the first inviter
	end
	local aged = SocialCore.inviteAged(player.AccountAge, SI)
	local inviter = Players:GetPlayerByUserId(inviterId)
	task.wait(4) -- after the toast "You joined ..."
	if aged then
		local egg = eggText(rarityFor(player))
		services.Nest.toast(player, Loc.text(T.inviteStay, { name = if inviter then inviter.DisplayName else Loc.text(T.yourFriend), egg = egg }))
		if inviter and inviter.Parent == Players then
			services.Nest.toast(inviter, Loc.text(T.inviteFriendIn, { name = player.DisplayName, egg = egg }))
		end
	elseif inviter and inviter.Parent == Players then
		services.Nest.toast(inviter, Loc.text(T.inviteTooNew, { name = player.DisplayName }))
	end
end

-- came by an invite: appear at the inviter's nest (if he is on the server)
local function onJoin(player: Player)
	local ok, jd = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or typeof(jd) ~= "table" then
		return
	end
	local inviterId = SocialCore.inviter(jd.LaunchData) or (if (jd.ReferredByPlayerId or 0) > 0 then jd.ReferredByPlayerId else nil)
	if not inviterId then
		return
	end
	if services.Analytics then
		services.Analytics.custom(player, "invite_joined", 1, { referrer = tostring(inviterId), aged = if SI and SocialCore.inviteAged(player.AccountAge, SI) then "1" else "0" })
	end
	task.spawn(inviteJoined, player, inviterId)
	local function toInviter(ch: Model)
		task.wait(1.5)
		local inviter = Players:GetPlayerByUserId(inviterId)
		local nest = inviter and services.Nest.of(inviter)
		local sp = nest and nest:FindFirstChild("Spawn", true)
		if sp and sp:IsA("Attachment") and ch.Parent then
			ch:PivotTo(CFrame.new(sp.WorldPosition + Vector3.new(4, 4, 0)))
			if services.AntiCheat then -- a server relocation - a new honest point, otherwise the protection returns the guest to the spawn ("speed")
				services.AntiCheat.moved(player)
			end
			services.Nest.toast(player, Loc.text(T.joinedFriend, { name = inviter and inviter.DisplayName or "" }))
		end
	end
	if player.Character then
		task.spawn(toInviter, player.Character)
	else
		local conn: RBXScriptConnection? = nil
		conn = player.CharacterAdded:Connect(function(ch)
			if conn then
				conn:Disconnect()
			end
			toInviter(ch)
		end)
	end
end

-- ---------------------------------------------------------------------------------------------- §3-4 announcements
function Social.announce(text: any, sub: any) -- a string or a Loc.text template (the client translates)
	services.Net.noticeAll({ kind = "announce", text = text, sub = sub })
end

-- EggSpawner: a rare nest egg appeared at a spot
function Social.rareSpawned(zone: string, model: Model)
	Social.announce(Loc.text(T.rareAppeared, { zone = Loc.text(Strings.Zone[zone] or zone) }))
	local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if body then -- a golden shimmer above the spot (08 §3)
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "RareShimmer"
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = SC.rareParticles
		pe.Lifetime = NumberRange.new(1, 2)
		pe.Speed = NumberRange.new(2, 4)
		pe.EmissionDirection = Enum.NormalId.Top
		pe.SpreadAngle = Vector2.new(20, 20)
		pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
		pe.Color = ColorSequence.new(Color3.fromRGB(255, 215, 90))
		pe.LightEmission = 1
		pe.Parent = body
	end
	if services.Analytics then
		for _, p in Players:GetPlayers() do
			services.Analytics.custom(p, "rare_nest_spawn", 1, { zone = zone })
			break -- one event per server
		end
	end
end

-- EggSpawner: who took the rare nest
function Social.rareTaken(player: Player, seconds: number)
	services.Net.noticeAll({ kind = "toast", text = Loc.text(T.rareFound, { name = player.DisplayName }) })
	if services.Analytics then
		services.Analytics.custom(player, "rare_nest_taken", math.floor(seconds))
	end
end

-- Incubation: an Epic+ hatch (08 §4, 03 §2) - a server banner with "1 in N"
function Social.hatched(player: Player, rarity: string, element: string, oneIn: string?)
	if not SocialCore.announceHatch(rarity, Config.Rarities) then
		return
	end
	Social.announce(Loc.text(T.hatchAnnounce, { name = player.DisplayName, rarity = Loc.text(Strings.Rarity[rarity] or rarity), element = title(element) }),
		if oneIn and oneIn ~= "-" then oneIn else nil) -- «1 in 2,400» (Format.oneIn)
end

-- the Top nests board at Old Ash (08 §4): a board on two posts, labels on both sides
local boardLines: { TextLabel } = {}
local function buildBoard()
	local P = SC.board
	local center = Vector3.new(P.pos[1], P.pos[2], P.pos[3])
	local keeper = Vector3.new(Config.World.keeper.x, center.Y, Config.World.keeper.z)
	local cf = CFrame.lookAt(center, keeper)
	local m = Instance.new("Model")
	m.Name = "TopNests"
	local function part(props: { [string]: any }): Part
		local p = Instance.new("Part")
		p.Anchored = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Material = Enum.Material.Wood
		for k, v in props do
			(p :: any)[k] = v
		end
		p.Parent = m
		return p
	end
	local w, h = P.size[1], P.size[2]
	for _, x in { -w / 2 + 0.3, w / 2 - 0.3 } do
		part({ Name = "Post", Size = Vector3.new(0.5, h + P.lift, 0.5), CFrame = cf * CFrame.new(x, (h + P.lift) / 2, 0), Color = Color3.fromRGB(78, 52, 36) })
	end
	local plank = part({ Name = "Plank", Size = Vector3.new(w, h, 0.3), CFrame = cf * CFrame.new(0, P.lift + h / 2, 0), Color = Color3.fromRGB(120, 84, 52) })
	plank.CanCollide = true
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.MaxDistance = P.maxDistance
		sg.Parent = plank
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = sg
		local function line(order: number, text: string, size: number, color: Color3): TextLabel
			local t = Instance.new("TextLabel")
			t.LayoutOrder = order
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(1, 0, size, 0)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextColor3 = color
			t.TextStrokeTransparency = 0.4
			t.Text = text
			t.Parent = sg
			return t
		end
		line(0, T.topNests, 0.2, Color3.fromRGB(255, 214, 92))
		for r = 1, SC.boardRows do
			table.insert(boardLines, line(r, "", 0.8 / SC.boardRows, Color3.fromRGB(250, 240, 220)))
		end
	end
	m.Parent = workspace:FindFirstChild("World") or workspace
end

local function rateOf(player: Player, data: any): number
	local mods = if services.Shop then services.Shop.rateMods(data) else { ascension = data.ascension or 0 }
	mods.friends = Social.friendsOf(player)
	mods.weatherMult = if services.Weather then services.Weather.coinsMult() else 1 -- as in the nest tick
	return Economy.nestRate(Dragons.nestList(data) :: any, mods :: any, B)
end

local function refreshBoard()
	local rows: { SocialCore.Row } = {}
	for _, p in Players:GetPlayers() do
		local data = services.PlayerData.get(p)
		local nest = services.Nest.of(p)
		if data and nest then
			local rate = rateOf(p, data)
			table.insert(rows, { name = p.DisplayName, rate = rate, userId = p.UserId })
			-- the nest sign: the name and the income (08 §4)
			services.Nest.setSign(nest, Loc.text(T.signRate, { name = p.DisplayName, rate = Format.rate(rate) }))
		end
	end
	local top = SocialCore.top(rows, SC.boardRows)
	local per = SC.boardRows
	for i, lbl in boardLines do
		local r = ((i - 1) % per) + 1
		local row = top[r]
		lbl.Text = if row then string.format("%d. %s  %s", r, row.name, Format.rate(row.rate)) else "" -- Format.rate already has "/s"
	end
end

-- Studio only (ServerStorage.SocialDebug:Invoke(...)): "party <slot>" - a party at the own egg (the helper is the player himself, MCP does not
-- launch a second player); "rare" - the rare nest announcement; "hatch Legendary" - the hatch announcement; "board" - the board now;
-- "friends <n>" - the FriendsOn attribute
local function debugCmd(cmd: string): string
	local player = Players:GetPlayers()[1]
	if not player then
		return "no player"
	end
	local verb, arg = string.match(cmd, "^(%a+)%s*(%S*)")
	if verb == "party" then
		local nest = services.Nest.of(player)
		if nest then
			party(player, player, nest, tonumber(arg) or 1)
		end
		local data = services.PlayerData.get(player)
		local rec = data and data.eggs.incubating[arg ~= "" and arg or "1"]
		return string.format("party=%s left=%s", tostring(rec and rec.party), tostring(rec and (rec.endsAt - os.time())))
	elseif verb == "rare" then
		Social.announce(Loc.text(T.rareAppeared, { zone = Loc.text(Strings.Zone.Cliffs) }))
	elseif verb == "hatch" then
		Social.hatched(player, if arg ~= "" then arg else "Legendary", "ember", "1 in 2,400")
	elseif verb == "board" then
		refreshBoard()
		local out = {}
		for i = 1, SC.boardRows do
			table.insert(out, boardLines[i] and boardLines[i].Text or "")
		end
		return table.concat(out, " | ")
	elseif verb == "friends" then
		player:SetAttribute("FriendsOn", tonumber(arg) or 0)
	end
	return "ok"
end

function Social.init(s: { [string]: any })
	services = s
	if game:GetService("RunService"):IsStudio() then
		local bf = Instance.new("BindableFunction")
		bf.Name = "SocialDebug"
		bf.OnInvoke = debugCmd
		bf.Parent = game:GetService("ServerStorage")
	end
end

function Social.start()
	services.PlayerData.Loaded:Connect(function(player: Player)
		task.spawn(recount)
		if SI and SI.on then -- the seconds of past sessions, the inviter's egg queue
			local iv = inviteOf(services.PlayerData.get(player))
			if iv then
				inviteBase[player] = tonumber(iv.sec) or 0
			end
			task.spawn(claimPending, player)
		end
		task.spawn(onJoin, player)
	end)
	Players.PlayerRemoving:Connect(function(p)
		inviteBase[p] = nil
		inviteBusy[p] = nil
		for k in friendCache do -- the pairs with the one who left
			local a, b = string.match(k, "^(%d+):(%d+)$")
			if tonumber(a) == p.UserId or tonumber(b) == p.UserId then
				friendCache[k] = nil
			end
		end
		task.defer(recount)
	end)
	task.spawn(function()
		local ok, err = pcall(buildBoard)
		if not ok then
			warn("[Social] board: " .. tostring(err))
		end
		while true do
			local ok2, err2 = pcall(refreshBoard)
			if not ok2 then
				warn("[Social] board refresh: " .. tostring(err2))
			end
			task.wait(SC.boardEvery)
		end
	end)
	if SI and SI.on then
		task.spawn(function()
			while true do
				task.wait(SI.tick)
				local ok, err = pcall(inviteTick)
				if not ok then
					warn("[Social] invite: " .. tostring(err))
				end
			end
		end)
	end
	task.spawn(function()
		while true do
			task.wait(SC.partyTick)
			local ok, err = pcall(partyTick, SC.partyTick)
			if not ok then
				warn("[Social] party: " .. tostring(err))
			end
		end
	end)
end

return Social
