--!strict
-- The client entry point (10 §2, craft/01 §1). Lives in ReplicatedFirst: reaches the client first. Order: the own
-- loading screen with the step line -> game loading -> remotes -> the first data snapshot -> controllers by an explicit
-- list -> the character -> remove the screen (not earlier than 1.5 s).

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local LoadingScreen = require(script.Parent:WaitForChild("LoadingScreen"))
local loadStart = os.clock() -- client loading time until the character -> Remote Analytics "load"

ReplicatedFirst:RemoveDefaultLoadingScreen()
-- P38: the game's name in Roblox (= Strings.Loading.title; Shared has not arrived yet), no subtitle
local screen = LoadingScreen.new("Find, Feed & Fly Dragons")
screen:show("Waiting for network...")
screen:setProgress(0.08)
-- the 3D hatchling from the game: the model is baked into the place file (ReplicatedFirst) and
-- arrives before the network; Shared is not awaited (the window size is a constant). There is no frame-drawn fallback picture:
-- the hatchling is 3D only, appears when the mesh and the texture are downloaded; no model or not downloaded - the bar without the hatchling.
-- The result - the attribute ReplicatedFirst.Splash3D (seconds until shown / late / none / bad / err), Perf writes it into the phone journal (sp=).
local SPLASH_SIZE = 2.8
task.spawn(function()
	local m = ReplicatedFirst:WaitForChild("LoadingDragon", 3)
	screen.gui:SetAttribute("SplashFound", if m then os.clock() - screen.shownAt else -1) -- probe: when the model was found (s)
	if not (m and m:IsA("Model")) then
		ReplicatedFirst:SetAttribute("Splash3D", "none")
		warn("[LoadingScreen] no ReplicatedFirst.LoadingDragon - the splash without the hatchling")
		return
	end
	-- the hatchling appears only when the mesh and the texture are downloaded
	local good, bad = 0, 0
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync({ m }, function(_id: string, status: Enum.AssetFetchStatus)
			if status == Enum.AssetFetchStatus.Success then
				good += 1
			else
				bad += 1
			end
		end)
	end)
	local t = os.clock() - screen.shownAt
	screen.gui:SetAttribute("Dragon3D", string.format("good=%d bad=%d t=%.1f", good, bad, t))
	if good == 0 or bad > 0 then
		ReplicatedFirst:SetAttribute("Splash3D", "bad")
		return
	end
	if screen.hidden then
		ReplicatedFirst:SetAttribute("Splash3D", string.format("late%.1f", t)) -- downloaded when the splash was already gone
		return
	end
	local ok, err = pcall(function()
		screen:useModel(m, SPLASH_SIZE)
	end)
	ReplicatedFirst:SetAttribute("Splash3D", if ok then string.format("%.1f", t) else "err")
	if not ok then
		warn("[LoadingScreen] 3D: " .. tostring(err))
	end
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
screen:setStep(Strings.Loading.findData)
screen:setProgress(0.35)
-- P38: the show time, tips in a cycle and "Tap to skip" (the world is already loaded - skipping is allowed after minSeconds)
pcall(function()
	local S = require(Shared:WaitForChild("Config")).UI.splash
	screen:setTiming(S.minSeconds, S.fade, S.holdSeconds, S.skipAfter)
	screen:setTips(Strings.Loading.tips, S.tipSeconds, Strings.Loading.skip)
	screen:allowSkip()
end)

-- the first full data snapshot comes through State on join (PlayerData); on a session conflict we wait up to 60 s
local remotes = ReplicatedStorage:WaitForChild("Remotes", 30)
local snapshot: any = nil
local stateEvent = remotes and remotes:WaitForChild("State", 30)
if stateEvent and stateEvent:IsA("RemoteEvent") then
	local got = Instance.new("BindableEvent")
	local conn = stateEvent.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and payload.full then
			snapshot = payload
			got:Fire()
		end
	end)
	task.delay(60, function()
		got:Fire()
	end)
	got.Event:Wait()
	conn:Disconnect()
	got:Destroy()
end

screen:setStep(Strings.Loading.buildNest)
screen:setProgress(0.6)
-- the splash - a line about the nest from the snapshot (HTTYD lobby: "Hatching / Busy Dragons" before entering) and the font from Config
do
	local Config = require(Shared:WaitForChild("Config"))
	pcall(function()
		screen:setFont(Config.UI.font)
	end)
	local data = snapshot and snapshot.data
	local function fill(t: string, v: { [string]: any }): string
		return Loc.fill(t, v, nil, "") -- the template in the player's language
	end
	local line = Loc.t(Strings.Loading.welcomeNew)
	if typeof(data) == "table" then
		local dragons = 0
		for _ in (data.dragons or {}) do
			dragons += 1
		end
		local eggs, ready = 0, 0
		local now = workspace:GetServerTimeNow()
		for _, rec in ((data.eggs or {}).incubating or {}) do
			if typeof(rec) == "table" and typeof(rec.endsAt) == "number" and rec.endsAt <= now then
				ready += 1
			else
				eggs += 1
			end
		end
		if dragons > 0 or eggs > 0 or ready > 0 then
			-- "1 egg hatching" was written about a ready egg too, "0 eggs hatching" - about an empty incubator
			local parts = { fill(Strings.Loading.nestSummary, { d = dragons, dw = Loc.t(Strings.Loading.dragonWord[if dragons == 1 then 1 else 2]) }) }
			if eggs > 0 then
				table.insert(parts, fill(Strings.Loading.eggsHatching, { e = eggs, ew = Loc.t(Strings.Loading.eggWord[if eggs == 1 then 1 else 2]) }))
			end
			if ready > 0 then
				table.insert(parts, fill(Strings.Loading.eggsReady, { e = ready, ew = Loc.t(Strings.Loading.eggWord[if ready == 1 then 1 else 2]) }))
			end
			line = fill(Strings.Loading.welcomeBack, { name = Players.LocalPlayer.DisplayName }) .. "  -  " .. table.concat(parts, ", ")
		else
			line = Loc.t(Strings.Loading.welcomeNew) .. "  -  " .. Loc.t(Strings.Loading.nestNew)
		end
	end
	screen:setSummary(line)
end

-- controllers: an explicit start order (stage 1.8 fills the list); init(snapshot) for all, then start() for all
-- 1.8: calls and Notice, data, sounds, the menu stack, toasts/banners, HUD, the coin flight, labels above objects, the name window,
-- the dragon card, the menu, hints, input, the hatch scene
-- 1.9: Companion (the leash, the Ride/Fly button), Glide (gliding), Fly (riding and flight) - after Input; before the hints does not matter: Hints takes them from loaded
-- Updraft - updrafts (at the nest ledge and at the Cliffs) lift the character, then Glide
-- looks: Looks - color presets by highlight (the nearest), the own tag above the head is hidden locally (07 add. 2.6)
local ORDER: { string } = { "Net", "Store", "Sounds", "UIStack", "Banners", "Quiet", "HUD", "StepBanner", "CoinFlight", "WorldUI", "NameDialog", "DragonCard", "Shop", "Menu", "Quests", "Index", "Gifts", "NextUp", "Social", "Favorite", "PassChips", "Weather", "LiveOps", "Hints", "Input", "Companion", "Glide", "Updraft", "Fly", "Combat", "Glow", "Swim", "DragonBones", "DragonLife", "Looks", "HatchScene", "Away", "DayPhase", "Ocean", "Curtain", "LightLod", "Declutter", "DecorLod", "Perf" } -- 2.2: Shop before Menu - the Shop plaque first on the left (02 §6) and the book tab through Menu.register
local player = Players.LocalPlayer
local controllers = player:WaitForChild("PlayerScripts"):WaitForChild("Controllers", 30)
local loaded: { [string]: any } = {}
-- a failure of one controller must not keep the player on the loading screen (like init/start of the server services): require,
-- init and start under pcall, the error goes to the console
if controllers then
	for _, name in ORDER do
		local ok, mod = pcall(function()
			return require(controllers:WaitForChild(name)) :: any
		end)
		if ok then
			loaded[name] = mod
		else
			warn("[DragonNest] require " .. name .. " failed: " .. tostring(mod))
		end
	end
	for _, name in ORDER do
		local c = loaded[name]
		if c and c.init then
			local ok, err = pcall(c.init, snapshot, loaded)
			if not ok then
				warn("[DragonNest] init " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	screen:setProgress(0.85)
	for _, name in ORDER do
		local c = loaded[name]
		if c and c.start then
			task.spawn(function()
				local ok, err = pcall(c.start)
				if not ok then
					warn("[DragonNest] start " .. name .. " failed: " .. tostring(err))
				end
			end)
		end
	end
end

-- Studio only: client probes from execute_luau (datamodel Client): PlayerGui.ClientDebug:Invoke("menu dragons" | "menu settings" |
-- "card d1" | "name d1" | "back" | "coins 120" | "state")
if game:GetService("RunService"):IsStudio() then
	local bf = Instance.new("BindableFunction")
	bf.Name = "ClientDebug"
	bf.OnInvoke = function(cmd: string): string
		local verb, arg = string.match(cmd, "^(%a+)%s*(%S*)")
		local ok, err = pcall(function()
			if verb == "menu" then
				if arg == "dragons" then
					loaded.Menu.openDragons()
				elseif arg == "quests" then
					loaded.Menu.open("quests")
				elseif arg == "index" then
					loaded.Menu.open("index")
				elseif arg == "gifts" then -- 2.4
					loaded.Menu.open("gifts")
				elseif string.sub(arg, 1, 4) == "shop" then -- 2.2: "menu shop" | "menu shop:nest" (sub-tab)
					loaded.Shop.open(string.match(arg, "^shop:(%a+)$"))
				else
					loaded.Menu.openSettings()
				end
			elseif verb == "card" then
				loaded.DragonCard.open(arg)
			elseif verb == "name" then
				loaded.NameDialog.open(arg, "Ember", {})
			elseif verb == "back" then
				loaded.UIStack.back()
			elseif verb == "coins" then
				loaded.CoinFlight.fly(tonumber(arg) or 100, nil)
			elseif verb == "phase" then -- "phase night" | "phase night 20" (hold for 20 s - P8 frames)
				loaded.DayPhase.show(if arg ~= "" then arg else "night", tonumber(string.match(cmd, "^%a+%s+%a+%s+(%d+)")))
			elseif verb == "ocean" then -- the sea tiles on the client and the mist at the edge
				error(loaded.Ocean.state(), 0)
			elseif verb == "gc" then -- the Lua heap of OUR client VM (execute_luau measures its own VM, not ours)
				error(string.format("gc=%.1fMB count=%.1fMB", gcinfo() / 1024, collectgarbage("count") / 1024), 0)
			elseif verb == "timer" then -- P35: the timer by the jump
				error(loaded.DayPhase.timerState(), 0)
			elseif verb == "others" then -- P37: "others off" | "others on" - like the toggle in Settings
				loaded.Menu.setOtherDragons(arg ~= "off")
			elseif verb == "weather" then -- whether the player sees the Storm dragon (the right by an adult dragon)
				error(loaded.Weather.state(), 0)
			elseif verb == "nextup" then -- the NEXT line (what is shown, the RSVP status)
				error(loaded.NextUp.state(), 0)
			elseif verb == "declutter" then -- how many world labels are tracked and how many are dimmed under the HUD
				error(loaded.Declutter.state() .. " bubble=" .. tostring(loaded.Quests.bubbleRect() ~= nil), 0)
			elseif verb == "slid" then -- how many times the character was pushed off a dragon
				error("slid=" .. loaded.DragonLife.slidCount(), 0)
			elseif verb == "lod" then -- P37: the setting from the profile (Store) and how many foreign models are hidden
				local s = loaded.Store.get("settings")
				error(string.format("show=%s hidden=%d profile.otherDragons=%s", tostring(loaded.DragonLife.showOthers()), loaded.DragonLife.hiddenCount(), tostring(typeof(s) == "table" and s.otherDragons)), 0)
			elseif verb == "splash" then -- "splash 8" (seconds until the end of the bar) | "splash 8@1280x720" (a phone screen at the center)
				local S = require(Shared:WaitForChild("Config")).UI.splash
				local secs = tonumber(string.match(arg, "^(%d+)")) or 6
				local sc = LoadingScreen.new(Strings.Loading.title)
				sc:setTiming(S.minSeconds, S.fade, S.holdSeconds, S.skipAfter)
				sc:setTips(Strings.Loading.tips, S.tipSeconds, Strings.Loading.skip)
				local w, h = string.match(arg, "@(%d+)x(%d+)")
				if w and h then
					sc:frameTo(tonumber(w) :: number, tonumber(h) :: number)
				end
				sc:show(Strings.Loading.findData)
				local LDm = ReplicatedFirst:FindFirstChild("LoadingDragon") or ReplicatedStorage:FindFirstChild("LoadingDragon") -- the 3D hatchling if present (as in the real splash)
				if LDm and LDm:IsA("Model") then
					sc:useModel(LDm, require(Shared:WaitForChild("Config")).UI.splashDragon.size)
				end
				sc:setSummary((string.gsub(Strings.Loading.welcomeBack, "{name}", player.DisplayName)) .. "  -  " .. (string.gsub(string.gsub(Strings.Loading.nestSummary, "{d} {dw}", "2 dragons"), "{e} {ew}", "1 egg"))) -- loc-ok: a debug splash display (Admin), not for players
				sc:allowSkip()
				task.spawn(function()
					for i = 1, 4 do
						sc:setProgress(i * 0.2)
						task.wait(secs / 5)
					end
					sc:hide()
				end)
			elseif verb == "hatchcall" then
				local reply = loaded.Net.call("HatchReady", tonumber(arg) or 1)
				error("reply " .. tostring(reply.ok) .. "/" .. tostring(reply.reason), 0)
			elseif verb == "feedcall" then
				local reply = loaded.Net.call("Feed", if arg ~= "" then arg else "all")
				error("reply " .. tostring(reply.ok) .. "/" .. tostring(reply.reason), 0)
			elseif verb == "mount" then -- 1.9: mount the companion (uid from the data)
				local reply = loaded.Net.call("Mount", if arg ~= "" then arg else tostring(loaded.Store.get("companion")))
				error("reply " .. tostring(reply.ok) .. "/" .. tostring(reply.reason), 0)
			elseif verb == "fly" then -- "fly up on" | "fly down on" | "fly move 0,1" | "fly off" | "fly state"
				error(loaded.Fly.debug(string.gsub(cmd, "^fly%s*", "")), 0)
			elseif verb == "bones" then -- the bone roles of the companion (DragonBones)
				local m = loaded.Companion.model()
				local n = 0
				if m and m.PrimaryPart then
					for _, d in m.PrimaryPart:GetDescendants() do
						if d:IsA("Bone") then
							n += 1
						end
					end
				end
				error(string.format("bones=%d %s", n, if m then loaded.DragonBones.describe(m) else "no companion"), 0)
			elseif verb == "rigs" then -- the bone roles of the showcase models ("rigs dusk" - one element)
				local lines = {}
				for _, m in game:GetService("CollectionService"):GetTagged("Dragon") do
					if m:IsA("Model") and m:GetAttribute("Showcase") and (arg == "" or m:GetAttribute("Element") == arg) then
						table.insert(lines, tostring(m:GetAttribute("Uid")) .. ": " .. loaded.DragonBones.describe(m))
					end
				end
				table.sort(lines)
				error(table.concat(lines, "\n"), 0)
			elseif verb == "away" then -- 2.5: the "while you were away" card
				error(loaded.Away.state(), 0)
			elseif verb == "looks" then -- looks: the coloring highlights nearby and the own tag above the head
				local head = player.Character and player.Character:FindFirstChild("Head")
				local tag = head and head:FindFirstChild("LookTag")
				error(loaded.Looks.state() .. " ownTag=" .. tostring(tag ~= nil) .. "/" .. tostring(tag and tag:IsA("BillboardGui") and tag.Enabled), 0)
			elseif verb == "comp" then
				local m = loaded.Companion.model()
				error(if m then string.format("companion %s s%s at %.0f,%.0f,%.0f", tostring(m:GetAttribute("Uid")), tostring(m:GetAttribute("Stage")), m:GetPivot().Position.X, m:GetPivot().Position.Y, m:GetPivot().Position.Z) else "no companion", 0)
			end
		end)
		local hud = player:FindFirstChild("PlayerGui") and (player.PlayerGui :: Instance):FindFirstChild("HUD")
		return string.format("%s | %s | banner=%s | stack=%d hud=%s", if ok then "ok" else "ERR " .. tostring(err), loaded.Hints and loaded.Hints.state() or "-", loaded.StepBanner and loaded.StepBanner.current() or "-", loaded.UIStack and loaded.UIStack.depth() or -1, tostring(hud and (hud :: ScreenGui).Enabled))
	end
	bf.Parent = player:WaitForChild("PlayerGui")
end

screen:setStep(Strings.Loading.spawn)
screen:setProgress(0.95)
if not player.Character then
	player.CharacterAdded:Wait()
end
task.spawn(function()
	local secs = os.clock() - loadStart
	local UIS = game:GetService("UserInputService")
	local kind = if UIS.TouchEnabled and not UIS.KeyboardEnabled then "touch" elseif UIS.GamepadEnabled and not UIS.KeyboardEnabled then "gamepad" else "kbm"
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer("load", { seconds = secs, device = kind })
	end
end)
screen:hide()
