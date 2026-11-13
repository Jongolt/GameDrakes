--!strict
-- Roblox analytics (spec 11 §1-2): the newcomer funnel of 13 steps (LogOnboardingFunnelStepEvent, each step
-- once per player - flags in profile.analytics.onboard), the coin economy (LogEconomyEvent Source/Sink "Coins", the transaction type from
-- 20), stage progression (LogProgressionCompleteEvent "DragonStages"), custom events. customFields slices: source (from GetJoinData),
-- device (the client sends Remote Analytics "device"), cohortWeek (the week from D0 Config.Analytics.d0). All calls in pcall - analytics
-- errors do not break the game; in Studio the service answers but accumulates no data.
local AnalyticsService = game:GetService("AnalyticsService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Experiments = require(Shared:WaitForChild("Core"):WaitForChild("Experiments"))
local ShopCore = require(Shared:WaitForChild("Core"):WaitForChild("Shop")) -- impressions only of a known SKU
local Zones = require(Shared:WaitForChild("Core"):WaitForChild("Zones")) -- the visit map

local Analytics = {}

local services: { [string]: any } = {}
local A = Config.Analytics
local joinedAt: { [Player]: number } = {}
local source: { [Player]: string } = {}
local device: { [Player]: string } = {}
local deviceAt: { [Player]: number } = {}
local loadSent: { [Player]: boolean } = {} -- the loading time is already recorded in this session
local lastBuy: { [Player]: { t: number, sku: string } } = {} -- a purchase in this session (exit_within_10min_after_purchase)
local firstAction: { [Player]: boolean } = {} -- the returning player's first action is already recorded
local evAt: { [Player]: { [string]: number } } = {} -- the time of the last Remote Analytics event by kind (and by impression SKU)

local STEPS: { [string]: number } = {
	onboard_spawn = 1, egg_first_pick = 2, hatch_first = 3, coins_first_collect = 4, glide_first = 5, egg_second = 6, feed_first = 7,
	juvenile_first = 8, ride_first = 9, hatch_second = 10, adult_first = 11, fly_first = 12, ascension_first = 13,
}
Analytics.Steps = STEPS

local function keyName(i: number): string
	local ok, name = pcall(function()
		return (Enum :: any).AnalyticsCustomFieldKeys["CustomField0" .. i].Name
	end)
	return if ok and typeof(name) == "string" then name else "CustomField0" .. i
end
local K1, K2, K3 = keyName(1), keyName(2), keyName(3)

local function cohortWeek(): string
	local d0 = A.d0 or 0
	local now = os.time()
	if d0 <= 0 or now < d0 then
		return "w0"
	end
	return "w" .. tostring(math.floor((now - d0) / (7 * 86400)) + 1)
end

-- the join source (11 §1): ads / share / home / event / other
local function sourceOf(player: Player): string
	local ok, s = pcall(function()
		local jd = player:GetJoinData()
		local ld = tostring(jd.LaunchData or "")
		if string.find(ld, "src=ads") or string.find(ld, "utm_source=ads") then
			return "ads"
		elseif string.find(ld, "src=event") then
			return "event"
		elseif string.find(ld, "src=notify") then -- came from a notification (tools/notify_send.py)
			return "notify"
		elseif (jd.ReferredByPlayerId or 0) > 0 or string.find(ld, "src=share") then
			return "share"
		elseif jd.SourceGameId then
			return "other"
		end
		return "home"
	end)
	return if ok and typeof(s) == "string" then s else "other"
end

local function fields(player: Player, extra: { [string]: any }?): { [string]: string }
	-- the A/B group of egg labels in the cohort slice ("w1|eggLabels=off") - Roblox has only three fields; and the
	-- firstborn growth group ("w1|eggLabels=off|grow=B", Config.Balance.firstDragon.ab)
	local f = { [K1] = source[player] or "other", [K2] = device[player] or "unknown",
		[K3] = cohortWeek() .. "|eggLabels=" .. Experiments.tag(player.UserId, Config.World.eggMarks) .. "|grow=" .. Experiments.growGroup(player.UserId, Config.Balance.firstDragon.ab, os.time())
		.. "|d2=" .. Experiments.d2Group(player.UserId, Config.Rewards.calendar.d2ab) } -- the day-2 gift experiment
	if extra then
		local parts = {}
		for k, v in extra do -- Roblox does not accept commas and quotes
			table.insert(parts, (string.gsub(tostring(k) .. "=" .. tostring(v), "[,\"']", "")))
		end
		table.sort(parts)
		if #parts > 0 then
			f[K2] = (device[player] or "unknown") .. "|" .. table.concat(parts, ";") -- small step parameters in the device slice (11 §2: element, zone, ...)
		end
	end
	return f
end

local function call(fn: () -> ())
	local ok, err = pcall(fn)
	if not ok and A.warn then
		warn("[Analytics] " .. tostring(err))
	end
end

-- a newcomer funnel step (once per player; the name from STEPS)
function Analytics.onboard(player: Player, name: string, extra: { [string]: any }?)
	local step = STEPS[name]
	if not step or not A.enabled then
		return
	end
	local data = services.PlayerData.get(player)
	if not data then
		return
	end
	data.analytics = data.analytics or {}
	data.analytics.onboard = data.analytics.onboard or {}
	if data.analytics.onboard[tostring(step)] then
		return
	end
	data.analytics.onboard[tostring(step)] = os.time()
	call(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name, fields(player, extra))
	end)
end

-- coins: flow "Source" | "Sink", txType from 11 §2 (Income, Quest, Index, Feed, ...)
function Analytics.coins(player: Player, flow: string, amount: number, ending: number, txType: string, sku: string?)
	if not A.enabled or amount <= 0 then
		return
	end
	call(function()
		local ft = if flow == "Sink" then Enum.AnalyticsEconomyFlowType.Sink else Enum.AnalyticsEconomyFlowType.Source
		AnalyticsService:LogEconomyEvent(player, ft, "Coins", math.floor(amount), math.floor(ending), txType, sku, fields(player))
	end)
end

-- the "Shop" funnel - 1 shop_open, 2 offer_impression, 3 purchase_prompt, 4 purchase
-- the funnel session - from opening the shop (without opening - its own one for a purchase from context)
local shopSession: { [Player]: string } = {}
function Analytics.shopStep(player: Player, step: number, name: string, extra: { [string]: any }?)
	if not A.enabled then
		return
	end
	if step == 1 then
		Analytics.action(player, "shop")
	end
	if step == 1 or not shopSession[player] then
		shopSession[player] = game:GetService("HttpService"):GenerateGUID(false)
	end
	local sid = shopSession[player]
	call(function()
		AnalyticsService:LogFunnelStepEvent(player, "Shop", sid, step, name, fields(player, extra))
	end)
end

-- 2.1 (07 §11, 11 §2): a purchase for Robux - its own event with the SKU and the amount (Roblox counts the Robux revenue itself); giftTo = a gift
function Analytics.purchase(player: Player, sku: string, robux: number, giftTo: number?)
	if not A.enabled then
		return
	end
	call(function()
		AnalyticsService:LogCustomEvent(player, "purchase", math.max(0, math.floor(robux or 0)), fields(player, { sku = sku, gift = if giftTo then "1" else "0" }))
	end)
	Analytics.shopStep(player, 4, "purchase", { sku = sku })
	lastBuy[player] = { t = os.time(), sku = sku }
	local data = services.PlayerData.get(player)
	if data and data.analytics and data.analytics.purchasesCount == 1 then -- 11 §2: the first purchase (seconds from joining)
		Analytics.custom(player, "first_purchase", os.time() - (joinedAt[player] or os.time()), { sku = sku })
	end
	if giftTo then
		Analytics.custom(player, "gift_sent", 1, { sku = sku })
	end
end

-- the first action in the session of a returning player (session >= 2): collect / hatch / feed / shop / egg / quest...; once
function Analytics.action(player: Player, action: string)
	if firstAction[player] ~= false then -- nil - the player is not loaded, true - already recorded
		return
	end
	firstAction[player] = true
	Analytics.custom(player, "return_first_action", 1, { action = action })
end

function Analytics.custom(player: Player, name: string, value: number?, extra: { [string]: any }?)
	if not A.enabled then
		return
	end
	call(function()
		AnalyticsService:LogCustomEvent(player, name, value or 1, fields(player, extra))
	end)
end

-- a dragon stage as the DragonStages progression (level = stage 1-3)
function Analytics.stage(player: Player, stage: number, minutes: number)
	if not A.enabled then
		return
	end
	call(function()
		AnalyticsService:LogProgressionCompleteEvent(player, "DragonStages", stage, Config.Stages[stage + 1] or tostring(stage), fields(player))
	end)
	Analytics.custom(player, "stage_up", stage, { minutes = math.floor(minutes) })
end

function Analytics.init(s: { [string]: any })
	services = s
end

-- :
-- every zones.every s the zone of each player (Core/Zones) - into the profile analytics.zones: seconds by zone (s), the play time of the first
-- visit (f, playSeconds), the last zone (last - on leaving that is the exit zone). The player sees nothing. Read: the cloud profile scan
local zoneProg: { [Player]: { key: string, at: number } } = {} -- the progress fingerprint (Zones.progressKey) and when it changed
local r1Pos: { [Player]: Vector3 } = {} -- the previous mark before the first dragon (in place / moving)
local zoneWarnAt = -math.huge
local function sampleOne(p: Player, now: number, params: RaycastParams)
	local Z = A.zones
	do
		local data = services.PlayerData.get(p)
		local ch = p.Character
		local r = ch and ch:FindFirstChild("HumanoidRootPart")
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if type(data) == "table" and r and r:IsA("BasePart") and hum then
			local skip: { Instance } = { ch :: Instance }
			local comp = workspace:FindFirstChild("Companions")
			if comp then
				table.insert(skip, comp)
			end
			params.FilterDescendantsInstances = skip
			local hit = workspace:Raycast(r.Position, Vector3.new(0, -400, 0), params)
			local alt = if hit then r.Position.Y - hit.Position.Y else 400
			local mounted = p:GetAttribute("Mounted") ~= nil
			local high = alt > (if mounted then Z.flyAbove else Z.highAbove)
			local own = false
			local nest = if services.Nest then services.Nest.of(p) else nil
			if nest then
				local lp = nest:GetPivot():PointToObjectSpace(r.Position)
				local NL = Config.World.nests
				own = math.abs(lp.X) <= NL.lotWidth / 2 + 4 and math.abs(lp.Z) <= NL.lotDepth / 2 + 6
			end
			local zone = Zones.of(r.Position.X, r.Position.Y, r.Position.Z, {
				flying = mounted and high,
				gliding = not mounted and high,
				swimming = hum:GetState() == Enum.HumanoidStateType.Swimming,
				ownNest = own,
			}, Config.World)
			if type(data.analytics) ~= "table" then
				data.analytics = { purchasesCount = 0 }
			end
			local key = Zones.progressKey(data)
			local pr = zoneProg[p]
			if not pr or pr.key ~= key then
				pr = { key = key, at = now }
				zoneProg[p] = pr
			end
			local idle = now - pr.at
			-- the profile is the same table profile.Data: an in-place edit goes into the ProfileStore save (the client does not need it)
			data.analytics.zones = Zones.record(data.analytics.zones, zone, Z.every, tonumber(data.playSeconds) or 0, idle >= Z.boredAfter, idle)
			-- :
			-- before the first dragon - seconds in place (st) / moving (mv), the closest approach to the own raid nest FirstNest (dmin, studs) and
			-- when they first came within 35 (near, playSeconds); thefts and captures are written there by Services/Raid; read by tools/zones_scan.py
			local dragons = if type(data.nestOrder) == "table" then #data.nestOrder else 0
			if dragons == 0 then
				local r1 = if type(data.analytics.r1) == "table" then data.analytics.r1 else {}
				data.analytics.r1 = r1
				local prev = r1Pos[p]
				r1Pos[p] = r.Position
				if prev then
					local moved = Vector3.new(r.Position.X - prev.X, 0, r.Position.Z - prev.Z).Magnitude > 3
					if moved then
						r1.mv = (tonumber(r1.mv) or 0) + Z.every
					else
						r1.st = (tonumber(r1.st) or 0) + Z.every
					end
				end
				local fid = p:GetAttribute("FirstNest")
				if fid ~= nil then
					for _, m in CollectionService:GetTagged("RaidNest") do
						if m:IsA("Model") and m:GetAttribute("NestId") == fid then
							local dd = (m:GetPivot().Position - r.Position).Magnitude
							r1.dmin = math.floor(math.min(tonumber(r1.dmin) or math.huge, dd))
							if dd <= 35 and not r1.near then
								r1.near = math.floor(tonumber(data.playSeconds) or 0)
							end
							break
						end
					end
				end
			end
		end
	end
end
-- one player's error does not break the mark for the others; a failure is visible in the server journal (once a minute), not silent
local function sampleZones()
	local now = os.clock()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _, p in Players:GetPlayers() do
		local ok, err = pcall(sampleOne, p, now, params)
		if not ok and now - zoneWarnAt >= 60 then
			zoneWarnAt = now
			warn("[Analytics] zones " .. p.Name .. ": " .. tostring(err))
		end
	end
end

-- button overlaps on players' screens (Config.Analytics.uiOverlap, the client - Controllers/Declutter): a pair count per UTC day, written to the DataStore
local UO = A.uiOverlap
local overlapBuf: { [string]: { n: number, s: string, d: string } } = {}
local overlapN: { [Player]: number } = {}
local overlapAt: { [Player]: number } = {}
local function cleanName(x: any): string?
	if typeof(x) ~= "string" or #x == 0 or #x > 60 then
		return nil
	end
	local c = string.gsub(x, "[^%w_/:%.%-]", "")
	return if #c > 0 then c else nil
end

local function onOverlap(player: Player, a: any, b: any, screen: any, dev: any)
	if not (UO and UO.on) then
		return
	end
	local now = os.clock()
	if (overlapN[player] or 0) >= UO.perSession or now - (overlapAt[player] or -math.huge) < 0.5 then
		return
	end
	local na, nb = cleanName(a), cleanName(b)
	local sc = if typeof(screen) == "string" and string.match(screen, "^%d+x%d+$") then screen else "?"
	local dv = if dev == "touch" or dev == "pc" or dev == "console" then dev else "?"
	if not na or not nb or na == nb then
		return
	end
	overlapN[player] = (overlapN[player] or 0) + 1
	overlapAt[player] = now
	local key = if na < nb then na .. "|" .. nb else nb .. "|" .. na
	local e = overlapBuf[key]
	if not e then
		local n = 0
		for _ in overlapBuf do
			n += 1
		end
		if n >= UO.cap then
			return
		end
		e = { n = 0, s = sc, d = dv }
		overlapBuf[key] = e
	end
	e.n += 1
	e.s = sc
	e.d = if string.find(e.d, dv, 1, true) then e.d else e.d .. "," .. dv
end

local function overlapFlush()
	if next(overlapBuf) == nil or game:GetService("RunService"):IsStudio() then
		overlapBuf = {}
		return
	end
	local batch = overlapBuf
	overlapBuf = {}
	local ok, err = pcall(function()
		game:GetService("DataStoreService"):GetDataStore(UO.store):UpdateAsync("d_" .. os.date("!%Y%m%d"), function(old: any)
			local t = if typeof(old) == "table" then old else {}
			local n = 0
			for _ in t do
				n += 1
			end
			for k, e in batch do
				local o = t[k]
				if o then
					o.n = (tonumber(o.n) or 0) + e.n
					o.s = e.s
					o.d = if string.find(tostring(o.d or ""), e.d, 1, true) then o.d else string.sub(tostring(o.d or "") .. "," .. e.d, 1, 40)
				elseif n < UO.cap then
					t[k] = { n = e.n, s = e.s, d = e.d }
					n += 1
				end
			end
			return t
		end)
	end)
	if not ok then
		warn("[Analytics] ui overlap flush: " .. tostring(err))
	end
end

function Analytics.start()
	if A.zones and A.zones.on then
		task.spawn(function()
			while true do
				task.wait(A.zones.every)
				local ok, err = pcall(sampleZones)
				if not ok and A.warn then
					warn("[Analytics] zones: " .. tostring(err))
				end
			end
		end)
	end
	services.PlayerData.Loaded:Connect(function(player: Player, data: any)
		joinedAt[player] = os.time()
		firstAction[player] = if (data and data.sessions or 0) >= 2 then false else true -- waiting for the returning player's first action
		source[player] = sourceOf(player)
		Analytics.onboard(player, "onboard_spawn")
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		local t0 = joinedAt[player]
		if t0 then
			Analytics.custom(player, "session_end", math.floor((os.time() - t0) / 60), { reason = "leave" })
		end
		local lb = lastBuy[player] -- left less than 10 minutes after a purchase in this session
		if lb and os.time() - lb.t < 600 then
			Analytics.custom(player, "exit_within_10min_after_purchase", os.time() - lb.t, { sku = lb.sku })
		end
		lastBuy[player] = nil
		zoneProg[player] = nil
		r1Pos[player] = nil
		evAt[player] = nil
		firstAction[player] = nil
		joinedAt[player] = nil
		shopSession[player] = nil
		source[player] = nil
		device[player] = nil
		deviceAt[player] = nil
		loadSent[player] = nil
	end)
	-- the device from the client (Remote Analytics "device"): no more often than once per deviceEvery s, values only from the list
	local folder = ReplicatedStorage:WaitForChild(Remotes.Folder, 30)
	local ro = folder and folder:FindFirstChild("UiOverlap") -- button overlaps
	if UO and UO.on and ro and ro:IsA("RemoteEvent") then
		ro.OnServerEvent:Connect(onOverlap)
		Players.PlayerRemoving:Connect(function(p: Player)
			overlapN[p] = nil
			overlapAt[p] = nil
		end)
		task.spawn(function()
			while true do
				task.wait(UO.flush)
				overlapFlush()
			end
		end)
		game:BindToClose(overlapFlush)
	end
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r.OnServerEvent:Connect(function(player: Player, name: any, f: any)
			-- the server repeats the client's limits (A.clientEvery, a SKU impression once per impressionServerEvery), the excess is silently
			-- dropped: a stream of forged events must not clutter the funnel or hit the AnalyticsService limits
			if typeof(name) ~= "string" then
				return
			end
			local t = evAt[player]
			if not t then
				t = {}
				evAt[player] = t
			end
			local now = os.clock()
			local every = A.clientEvery[name]
			if name == "offer_impression" then
				local sku = if typeof(f) == "table" and typeof(f.sku) == "string" then f.sku else ""
				if not ShopCore.resolve(sku) then
					return
				end
				local k = "imp:" .. sku
				if t[k] and now - t[k] < A.impressionServerEvery then
					return
				end
				t[k] = now
			elseif every then
				if t[name] and now - t[name] < every then
					return
				end
				t[name] = now
			end
			if name == "ui" then -- HUD button presses (k = "left_shop" ...): the ui_tap event + a counter in the profile analytics.taps
				local k = if typeof(f) == "table" and typeof(f.k) == "string" and #f.k <= 24 and string.match(f.k, "^[a-z_]+$") then f.k else nil
				if not k then
					return
				end
				Analytics.custom(player, "ui_tap", 1, { k = k })
				services.PlayerData.update(player, "analytics", function(a: any)
					a = if typeof(a) == "table" then a else {}
					a.taps = if typeof(a.taps) == "table" then a.taps else {}
					a.taps[k] = (tonumber(a.taps[k]) or 0) + 1
					return a
				end)
				return
			end
			if name == "invite" or name == "invite_shown" then -- 2.6 (08 §9): the invite button / the card at 7:30
				Analytics.custom(player, if name == "invite" then "invite_prompt_shown" else "invite_card_shown", 1)
				return
			end
			if name == "notify_prompt" or name == "notify_closed" then -- the Roblox "notifications" prompt shown / closed
				Analytics.custom(player, name, 1)
				return
			end
			if name == "tomorrow" then -- the steps of the "tomorrow" chain: shown / no_banner / stuck / claim_fail (+ the reason)
				local st = if typeof(f) == "table" then f.s else nil
				if st ~= "shown" and st ~= "no_banner" and st ~= "stuck" and st ~= "claim_fail" then
					return
				end
				local why = if st == "claim_fail" and typeof(f.why) == "string" then string.sub(f.why, 1, 24) else "-"
				Analytics.custom(player, "tomorrow_" .. st, 1, { why = why })
				return
			end
			if name == "rsvp_prompt" or name == "rsvp_going" then -- the Roblox event RSVP window shown / the player signed up
				local from = if typeof(f) == "table" and (f.from == "hud" or f.from == "gifts") then f.from else "other"
				Analytics.custom(player, name, 1, { from = from })
				return
			end
			if name == "fav_prompt" then -- the "favorite" prompt shown - once per account lifetime
				local data = services.PlayerData.get(player)
				local o = data and data.onboarding
				local ge = data and data.glowEgg
				local glowHatched = typeof(ge) == "table" and ((tonumber(ge.readyAt) or 0) > 0 or ge.hatched == true) -- the "glow" moment = the egg on the pedestal (Core/Favorite)
				if typeof(o) ~= "table" or (o.flew ~= true and not glowHatched) or o.favAsked ~= nil then
					return
				end
				services.PlayerData.update(player, "onboarding", function(ob)
					ob.favAsked = os.time()
					return nil
				end)
				Analytics.custom(player, "fav_prompt", 1)
				return
			end
			if name == "fav_done" then -- the prompt result (Enum.AvatarPromptResult): Success - added to favorites
				local r = if typeof(f) == "table" then f.result else nil
				local res = if r == "Success" or r == "PermissionDenied" or r == "Failed" then r else "other"
				Analytics.custom(player, "fav_done", 1, { result = res })
				return
			end
			if name == "shop_open" or name == "offer_impression" then -- the shop funnel (fields - short strings only)
				local by = if typeof(f) == "table" and typeof(f.by) == "string" then string.sub(f.by, 1, 16) else "player"
				local sku = if typeof(f) == "table" and typeof(f.sku) == "string" then string.sub(f.sku, 1, 32) else nil
				if name == "shop_open" then
					Analytics.shopStep(player, 1, "shop_open", { by = by })
				else
					Analytics.shopStep(player, 2, "offer_impression", { sku = sku or "-" })
				end
				return
			end
			-- the client loading time - once per session, into the profile and the load_time event (with the device)
			if name == "load" and typeof(f) == "table" then
				if loadSent[player] then
					return
				end
				local secs = tonumber(f.seconds)
				if not secs or secs < 0 or secs > 900 then
					return
				end
				loadSent[player] = true
				local d0 = tostring(f.device)
				if d0 == "touch" or d0 == "gamepad" or d0 == "kbm" then
					device[player] = d0
				end
				services.PlayerData.update(player, "loadSeconds", function()
					return math.floor(secs * 10 + 0.5) / 10
				end)
				Analytics.custom(player, "load_time", math.floor(secs + 0.5), { device = device[player] or "unknown" })
				return
			end
			if name ~= "device" or typeof(f) ~= "table" then
				return
			end
			local now = os.clock()
			if deviceAt[player] and now - deviceAt[player] < A.deviceEvery then
				return
			end
			deviceAt[player] = now
			local d = tostring(f.device)
			if d == "touch" or d == "gamepad" or d == "kbm" then
				device[player] = d
				local data = services.PlayerData.get(player)
				if data and data.device ~= d then -- the device in the profile (the cohort_funnel_scan funnel by device)
					services.PlayerData.update(player, "device", function()
						return d
					end)
				end
			end
		end)
	end
end

return Analytics
