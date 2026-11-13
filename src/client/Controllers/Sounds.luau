--!strict
-- Sounds (02 §1, 03 §10): every action gets a sound in the same frame; coins with a random pitch 1.0-1.35 (02 §2). The source -
-- Content.Sounds (a number = rbxassetid, a string = an rbxasset path of a built-in file, 0 = silence), the volume Content.SoundVolume.
-- Buttons and refusals - through the hooks UIKit.onPress / UIKit.onDeny; server events - Notice; incubator transitions - by attributes.

local CollectionService = game:GetService("CollectionService")
local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared:WaitForChild("Content"))
local Voices = require(Shared:WaitForChild("Core"):WaitForChild("Voices"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))

local Sounds = {}

local me = Players.LocalPlayer
local rng = Random.new()
local enabled = { sfx = true, music = true }
local lastPlay: { [string]: number } = {}

-- music by the moment of the game (Content.Music). The state: boss (the Storm dragon) > storm > starfall/aurora >
-- flight > the day phase; on join the intro once. A change - smoothly through two Sounds; the track ended - a pause of Content.Music.gap
-- and the next track of the same state; events - looped. Under the hatch sound the music ducks (Content.Music.duck).
local MUSIC = (Content :: any).Music
local cur: Sound? = nil
local curState = ""
local introDone = false
local flyingSince: number? = nil
local landedAt = 0
local endedAt: number? = nil
local gapSecs = 0
local duckUntil = 0
local quietUntil = 0 -- the victory phrase plays alone - the state music waits for its end (Sounds.fightWin)
local lastIndex: { [string]: number } = {}

function Sounds.isEnabled(kind: string): boolean
	return enabled[kind] ~= false
end

local function fadeTo(s: Sound, vol: number, secs: number)
	TweenService:Create(s, TweenInfo.new(math.max(secs, 0.05), Enum.EasingStyle.Sine), { Volume = vol }):Play()
end

local function stopMusic(secs: number)
	local s = cur
	cur = nil
	curState = ""
	endedAt = nil
	if s then
		fadeTo(s, 0, secs)
		task.delay(secs + 0.2, function()
			if s.Parent then
				s:Destroy()
			end
		end)
	end
end

local function startMusic(state: string, fade: number)
	local list = MUSIC and MUSIC.states[state]
	stopMusic(fade)
	curState = state
	if not list or #list == 0 then
		return
	end
	local i = rng:NextInteger(1, #list)
	if #list > 1 and i == lastIndex[state] then
		i = i % #list + 1
	end
	lastIndex[state] = i
	local t = list[i]
	local vol = (Content.MusicVolume or 0.18) * (t.gain or 1)
	local s = Instance.new("Sound")
	s.Name = "Music_" .. state
	s.SoundId = "rbxassetid://" .. t.id
	s.Looped = MUSIC.loop[state] == true
	s.Volume = 0
	s:SetAttribute("FullVolume", vol)
	s.Parent = SoundService
	s.Ended:Once(function()
		s:SetAttribute("Done", true)
	end)
	s:Play()
	fadeTo(s, if os.clock() < duckUntil then vol * MUSIC.duckLevel else vol, fade)
	cur = s
	-- a track started under ducking (duck at cur == nil, e.g. a hatch in the victory phrase window) -
	-- raise to full volume at the end of the duck, otherwise it stays quiet until the next state change
	if os.clock() < duckUntil then
		task.delay(duckUntil - os.clock() + 0.05, function()
			if cur == s and os.clock() >= duckUntil - 0.05 then
				fadeTo(s, vol, 0.8)
			end
		end)
	end
end

-- which music state is needed now (the attributes ReplicatedStorage.WeatherState / DayCycle, the player Flying)
local function wantedState(): string
	-- an escape with a stolen egg / the guardian chases (the Chase attribute from Controllers/Combat) -
	-- its own escape loop, above the combat music
	if (me:GetAttribute("Chase") == true or ((me:GetAttribute("ChaseNear") :: number?) or 0) > 0) and MUSIC.states.chase and #MUSIC.states.chase > 0 then
		return "chase" -- and while sneaking up to the own egg (ChaseNear) - quietly, the volume - chaseVolume
	end
	-- a fight with Gloom nearby or an announced wave (the Fight attribute from Controllers/Combat)
	if me:GetAttribute("Fight") == true then
		-- the fight has its own tense music (Content.Music.states.fight); no list - as before, the Storm dragon track
		return if MUSIC.states.fight then "fight" else "boss"
	end
	local ws = ReplicatedStorage:FindFirstChild("WeatherState")
	if ws then
		if ws:GetAttribute("Dragon") == true then
			return "boss"
		end
		local kind = ws:GetAttribute("Kind")
		if kind == "storm" then
			return "storm"
		elseif kind == "starfall" or kind == "aurora" then
			return "starfall"
		end
	end
	local now = os.clock()
	if me:GetAttribute("Flying") == true then
		flyingSince = flyingSince or now
		if now - (flyingSince :: number) >= MUSIC.flightDelay then
			return "flight"
		end
	else
		if flyingSince and curState == "flight" then
			landedAt = now
		end
		flyingSince = nil
		if curState == "flight" and now - landedAt < MUSIC.landDelay then
			return "flight"
		end
	end
	if not introDone then
		return "intro"
	end
	local dc = ReplicatedStorage:FindFirstChild("DayCycle")
	local ph = dc and dc:GetAttribute("Phase")
	if typeof(ph) == "string" and MUSIC.states[ph] then
		return ph
	end
	return "day"
end

-- the escape track volume by the closeness to the egg
-- (the ChaseNear attribute from Controllers/Combat) and full when the egg is in hand or the guardian chases (Chase)
local function chaseVolume()
	local s = cur
	local CN = MUSIC and MUSIC.chaseNear
	if curState ~= "chase" or not s or not CN or os.clock() < duckUntil then
		return
	end
	local full = (s:GetAttribute("FullVolume") :: number?) or s.Volume
	local grab = me:GetAttribute("Chase") == true
	local near = (me:GetAttribute("ChaseNear") :: number?) or 0
	local k = if grab then 1 else CN.min + (CN.max - CN.min) * math.clamp(near, 0, 1)
	local target = full * k
	if math.abs(((s:GetAttribute("ChaseVol") :: number?) or -1) - target) > 0.002 then
		s:SetAttribute("ChaseVol", target)
		fadeTo(s, target, if grab then CN.grabFade else CN.nearFade)
	end
end

local function musicTick()
	if not MUSIC or not enabled.music then
		return
	end
	if os.clock() < quietUntil and me:GetAttribute("Fight") ~= true then
		return -- after the victory until the end of the phrase only nature; a new wave (Fight) - the combat music at once
	end
	local want = wantedState()
	if curState == "intro" and want ~= "intro" then
		introDone = true -- the intro was interrupted by an event or a flight - not played again
	end
	if want ~= curState then
		startMusic(want, MUSIC.fade)
		chaseVolume()
		return
	end
	chaseVolume()
	local s = cur
	if s and s:GetAttribute("Done") then
		if curState == "intro" then
			-- the intro finished: then the day phase music, but first a pause with nature alone (as the studios do)
			introDone = true
			curState = wantedState()
		end
		if not endedAt then
			endedAt = os.clock()
			gapSecs = rng:NextNumber(MUSIC.gap[1], MUSIC.gap[2])
		end
		if os.clock() - (endedAt :: number) >= gapSecs then
			startMusic(curState, 0.5)
		end
	end
end

-- the nature background (Content.Ambience) - as the studios do (Zelda BotW, Minecraft): nature always plays, the music on top and
-- less often. A loop by the day phase (day and dawn - birds, sunset and night - crickets), in a storm - rain; in flight on top - wind.
-- The switch is sounds (sfx), not music.
local AMB = (Content :: any).Ambience
local VOICES = (Content :: any).Voices
local amb: Sound? = nil
local ambKey = ""
local wind: Sound? = nil

local function loopSound(name: string, t: any): Sound
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxassetid://" .. t.id
	s.Looped = true
	s.Volume = 0
	s.Parent = SoundService
	s:Play()
	return s
end

local function fadeOutAndDestroy(s: Sound, secs: number)
	fadeTo(s, 0, secs)
	task.delay(secs + 0.2, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function ambTick()
	if not AMB then
		return
	end
	local key = ""
	if enabled.sfx then
		local ws = ReplicatedStorage:FindFirstChild("WeatherState")
		local dc = ReplicatedStorage:FindFirstChild("DayCycle")
		local ph = dc and dc:GetAttribute("Phase")
		if ws and ws:GetAttribute("Kind") == "storm" then
			key = "rain"
		elseif ph == "night" or ph == "dusk" then
			key = "night"
		else
			key = "day"
		end
	end
	if key ~= ambKey then
		local old = amb
		amb = nil
		if old then
			fadeOutAndDestroy(old, AMB.fade)
		end
		local t = AMB.loops[key]
		if t then
			local s = loopSound("Amb_" .. key, t)
			fadeTo(s, AMB.volume * (t.gain or 1), AMB.fade)
			amb = s
		end
		ambKey = key
	end
	local w = AMB.loops.wind
	local flying = enabled.sfx and me:GetAttribute("Flying") == true
	if w and flying and not wind then
		local s = loopSound("Amb_wind", w)
		fadeTo(s, AMB.windVolume * (w.gain or 1), 1.2)
		wind = s
	elseif wind and not flying then
		local old = wind
		wind = nil
		fadeOutAndDestroy(old, 1.5)
	end
end

-- duck the music under an important sound (a hatch, a fanfare) for secs seconds
local function duck(secs: number)
	duckUntil = os.clock() + secs
	local s = cur
	if not s then
		return
	end
	local full = (s:GetAttribute("FullVolume") :: number?) or s.Volume
	fadeTo(s, full * MUSIC.duckLevel, 0.15)
	task.delay(secs, function()
		if cur == s and os.clock() >= duckUntil - 0.05 then
			fadeTo(s, full, 0.8)
		end
	end)
end

function Sounds.setEnabled(kind: string, on: boolean)
	enabled[kind] = on
	if kind == "music" then
		if on then
			musicTick()
		else
			stopMusic(0.6)
		end
	elseif kind == "sfx" then
		ambTick()
	end
end

-- one sound: at - a world part (3D, audible near it; Content.Voices.rolloff), without at - 2D in SoundService. Removed on Ended,
-- a 15 s safeguard (the Legendary/Mythic fanfares are ~9 s)
local function spawnSound(name: string, src: any, volume: number, speed: number?, at: BasePart?)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = if typeof(src) == "number" then "rbxassetid://" .. src else tostring(src)
	s.Volume = volume
	if speed then
		s.PlaybackSpeed = speed
	end
	if at then
		local ro = VOICES and VOICES.rolloff or { min = 10, max = 80 }
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = ro.min
		s.RollOffMaxDistance = ro.max
		s.Parent = at
	else
		s.Parent = SoundService
	end
	s:Play()
	local function gone()
		if s.Parent then
			s:Destroy()
		end
	end
	s.Ended:Once(gone)
	task.delay(15, gone)
end

-- opts.pitch = true: a random pitch Content.PitchRange; opts.volume - a multiplier; a minimum gap of 40 ms per name
function Sounds.play(name: string, opts: { pitch: boolean?, volume: number? }?)
	if not enabled.sfx then
		return
	end
	local src = (Content.Sounds :: any)[name]
	if src == nil or src == 0 or src == "" then
		return
	end
	if MUSIC and MUSIC.duck[name] then
		duck(MUSIC.duck[name])
	end
	local now = os.clock()
	if lastPlay[name] and now - lastPlay[name] < 0.04 then
		return
	end
	lastPlay[name] = now
	local o = opts or {}
	spawnSound(name, src, Content.SoundVolume * (o.volume or 1),
		if o.pitch then rng:NextNumber(Content.PitchRange[1], Content.PitchRange[2]) else nil, nil)
end

-- a Gloom wave cleared - the fight
-- ends with a victory phrase in the key of the combat track that was playing (Content.Music.states.fight[i].win), not with a cut into cheerful music:
-- the combat track fades over 0.6 s, the phrase plays alone, then the state music (musicTick waits for quietUntil). The volume - like the hatch
-- fanfares (sounds, Content.SoundVolume). No more often than once per winSec.
function Sounds.fightWin()
	if not enabled.sfx or not MUSIC then
		return
	end
	local list = MUSIC.states.fight
	if typeof(list) ~= "table" or #list == 0 then
		return
	end
	local t = (curState == "fight" and lastIndex.fight and list[lastIndex.fight]) or list[1]
	if not t or not t.win then
		return
	end
	local now = os.clock()
	if curState == "fight" or curState == "boss" then -- on a repeated victory within the phrase window the combat track fades too
		stopMusic(0.6)
	end
	if now < quietUntil then
		return
	end
	quietUntil = now + (t.winSec or 6)
	spawnSound("fight_win", t.win, Content.SoundVolume, nil, nil)
end

-- the crack sound by rarity (the ladder hatch_Common..hatch_Mythic, Core/Voices.hatchName); no own step - the shared hatch
function Sounds.hatch(rarity: string?, opts: { volume: number? }?)
	local name = Voices.hatchName(rarity)
	local src = (Content.Sounds :: any)[name]
	Sounds.play(if src == nil or src == 0 then "hatch" else name, opts)
end

-- the dragon's voice (Content.Voices): stage 0..3 (Config.Stages), kind birth/call/happy/roar. at - a part of its model
-- (3D), without at - 2D (a reply to the player's press wherever the dragon is). opts.cooldown - no more often than once per that many seconds per occasion.
-- Returns false if it did not play (sounds off, cooldown, no voice)
function Sounds.voice(stage: number?, kind: string, at: BasePart?, opts: { volume: number?, cooldown: number? }?): boolean
	if not enabled.sfx or not VOICES then
		return false
	end
	local o = opts or {}
	local key = "voice_" .. kind
	local now = os.clock()
	local cd = o.cooldown or (if kind == "roar" then VOICES.roarCooldown else nil)
	if cd and lastPlay[key] and now - lastPlay[key] < cd then
		return false
	end
	local e = Voices.pick(VOICES, stage, kind, rng:NextNumber())
	if not e then
		return false
	end
	lastPlay[key] = now
	local j = VOICES.jitter or 0
	spawnSound("Voice_" .. kind, e.id, Content.SoundVolume * (VOICES.volume or 1) * (o.volume or 1), e.speed * rng:NextNumber(1 - j, 1 + j), at)
	return true
end

-- a dragon by uid: the model (tag Dragon, own OwnerId) and the stage - for the voice on server events (growth)
local function myDragon(uid: any): (Model?, number?)
	for _, m in CollectionService:GetTagged("Dragon") do
		if m:IsA("Model") and m:GetAttribute("Uid") == uid and m:GetAttribute("OwnerId") == me.UserId then
			return m, m:GetAttribute("Stage") :: number?
		end
	end
	return nil, nil
end

-- "life" at the nest - occasionally (Content.Voices.idle.every) the voice of one own dragon near the character, 3D from its body
local function idleVoice()
	local char = me.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	local near: { Model } = {}
	for _, m in CollectionService:GetTagged("Dragon") do
		local body = m:IsA("Model") and m.PrimaryPart
		if body and m:GetAttribute("OwnerId") == me.UserId and (body.Position - root.Position).Magnitude <= VOICES.idle.range then
			table.insert(near, m)
		end
	end
	if #near == 0 then
		return
	end
	local m = near[rng:NextInteger(1, #near)]
	local kind = if rng:NextNumber() < VOICES.idle.happyShare then "happy" else "call"
	Sounds.voice(m:GetAttribute("Stage") :: number?, kind, m.PrimaryPart)
end

function Sounds.init(_snapshot: any, _loaded: any)
	UIKit.onPress = function()
		Sounds.play("button")
	end
	UIKit.onDeny = function()
		Sounds.play("deny")
	end
end

-- without preloading the first sound of each file is not ready even after 0.6 s (IsLoaded false) - the hatch
-- step, the roar and the first squeak were late. All short sounds and voices are downloaded in the background on join (~1.5 MB), as the studios do
local function preload()
	local seen: { [string]: boolean } = {}
	local list: { Sound } = {}
	local function add(v: any)
		if typeof(v) == "number" and v > 0 and not seen[tostring(v)] then
			seen[tostring(v)] = true
			local s = Instance.new("Sound")
			s.SoundId = "rbxassetid://" .. v
			table.insert(list, s)
		end
	end
	for _, v in Content.Sounds :: any do
		add(v)
	end
	-- the victory phrase (~6-7 s) - otherwise the first victory of the session: the combat track faded, the phrase still downloading
	for _, t in ((MUSIC and MUSIC.states.fight) or {}) :: any do
		add(t.win)
	end
	for _, st in (VOICES and VOICES.stages or {}) :: any do
		for _, kind in st do
			for _, e in kind do
				add(e.id)
			end
		end
	end
	pcall(function()
		ContentProvider:PreloadAsync(list)
	end)
	for _, s in list do
		s:Destroy()
	end
end

function Sounds.start()
	task.spawn(preload)
	task.spawn(function()
		while true do
			musicTick()
			ambTick()
			task.wait(0.5)
		end
	end)
	-- grabbed the egg / the guardian gave chase - the escape music at full at once, without waiting for the tick (it used to be audible 2-3 s later)
	me:GetAttributeChangedSignal("Chase"):Connect(function()
		if enabled.music ~= false then
			musicTick()
		end
	end)
	-- the hatch sound is played by HatchScene at the egg crack, not at the event arrival
	-- after the growth chord - the voice of the new stage from the dragon's body (2D if the model is not there yet)
	Net.on("stage_up", function(p)
		Sounds.play("stage_up")
		task.delay(0.6, function()
			local m, st = myDragon(p and p.uid)
			local stage = if typeof(p) == "table" and typeof(p.stage) == "number" then p.stage else st
			Sounds.voice(stage, "call", m and m.PrimaryPart)
		end)
	end)
	if VOICES then
		task.spawn(function()
			while true do
				task.wait(Voices.nextIdle(VOICES, rng:NextNumber()))
				idleVoice()
			end
		end)
		-- the dragon ate: FedUntil on the model of the own dragon grew (feeding only at the nest - the card, the button above the dragon, Feed all) ->
		-- one crunch per batch and a content voice from the body; for "Feed all" no more than fedMax voices staggered. The first 2 s after the model
		-- appears are not counted (attributes arrive after the build)
		local burst, burstAt = 0, 0
		local function watchFed(m: Instance)
			if not m:IsA("Model") then
				return
			end
			local addedAt = os.clock()
			local last = m:GetAttribute("FedUntil")
			m:GetAttributeChangedSignal("FedUntil"):Connect(function()
				local v = m:GetAttribute("FedUntil")
				local was = last
				last = v
				if typeof(v) ~= "number" or (typeof(was) == "number" and v <= was) or os.clock() - addedAt < 2
					or m:GetAttribute("OwnerId") ~= me.UserId then
					return
				end
				local now = os.clock()
				if now - burstAt > 1 then
					burst, burstAt = 0, now
					Sounds.play("feed")
				end
				burst += 1
				if burst > VOICES.fedMax then
					return
				end
				task.delay(VOICES.happyDelay + (burst - 1) * 0.35 + rng:NextNumber(0, 0.1), function()
					if m.Parent then
						Sounds.voice(m:GetAttribute("Stage") :: number?, "happy", m.PrimaryPart)
					end
				end)
			end)
		end
		CollectionService:GetInstanceAddedSignal("Dragon"):Connect(watchFed)
		for _, m in CollectionService:GetTagged("Dragon") do
			watchFed(m)
		end
	end
	Net.on("egg", function()
		Sounds.play("egg_pick")
	end)
	-- transitions of the own incubator rings: empty -> warming (an egg placed), warming -> ready (a chirp)
	local last: { [Instance]: string } = {}
	while true do
		task.wait(0.25)
		for _, r in CollectionService:GetTagged("Incubator") do
			if r:GetAttribute("OwnerId") ~= me.UserId then
				last[r] = nil
				continue
			end
			local st = (r:GetAttribute("State") :: string?) or "empty"
			local prev = last[r]
			if prev and prev ~= st then
				if st == "warming" then
					Sounds.play("egg_place")
				elseif st == "ready" then
					Sounds.play("hatch_rise")
				end
			end
			last[r] = st
		end
	end
end

return Sounds
