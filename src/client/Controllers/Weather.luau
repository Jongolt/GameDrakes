--!strict
-- 2.7: the weather and the Storm dragon on the client (spec 04 §7-8). Reads the ReplicatedStorage.WeatherState attributes
-- (the server Services/Weather). Storm: darker (ColorCorrection), rain - one emitter at the camera, lightning flashes; starfall: falling
-- stars (local sparks with a tail); 2.9 Aurora: curtains of light in the north of the sky; the strip at the top: the weather timer and the shard scale
-- of the Storm dragon "Storm shards k/12".
-- Everything is local to the player (rain - 1 emitter per player, the spec 04 §9 budget).
-- the Storm dragon (the scale, the silhouette, the shards) is seen only by a player with at least one dragon of stage >=
-- Config.Balance.stormDragon.minStage (Core/Weather.eligible by Store.dragons); by the same rule the server sends no banner and counts no pickup.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local WeatherCore = require(Core:WaitForChild("Weather"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))

local Weather = {}

local eligible = false -- there is a dragon of stage >= stormDragon.minStage (recomputed on Store "dragons")

local function shardVisibility(part: Instance)
	if part.Name == "StormShard" and part:IsA("BasePart") then
		part.LocalTransparencyModifier = if eligible then 0 else 1
	end
end

local function recomputeEligible()
	local was = eligible
	eligible = WeatherCore.eligible(Store.get("dragons"), Config.Balance.stormDragon)
	if eligible ~= was then
		for _, c in workspace:GetChildren() do
			shardVisibility(c)
		end
	end
end

local WV = Config.Weather
local T = Strings.Weather
local state: Folder? = nil
local cc: ColorCorrectionEffect? = nil
local rainPart: Part? = nil
local bar: GuiObject? = nil
local barText: TextLabel? = nil
local barFill: Frame? = nil
local barIcon: TextLabel? = nil -- 2.9: the icon by weather (⛈ storm and dragon, 🌠 starfall, 🌌 aurora)
local ICON = { storm = "⛈", starfall = "🌠", aurora = "🌌" }
local lastKind = ""
local lastText = ""
local dragon: Model? = nil -- the Storm dragon silhouette - a local copy of the template from WeatherState, driven by us
-- 2.9: Aurora - curtains in the sky (local only); alpha - the overall visibility 0..1 (smooth), stripes - rays with a shimmer phase
local auroraFolder: Folder? = nil
local auroraStripes: { { f: Frame, phase: number, speed: number } } = {}
local auroraAlpha = 0
local auroraTick = 0

-- the Storm dragon on the client: the same circle the server computed (the center Old Ash, the radius, the height, circles per event time)
local function flyDragon(st: Folder, now: number)
	local on = st:GetAttribute("Dragon") == true and eligible
	local tpl = st:FindFirstChild("StormDragonModel")
	if not on or not tpl then
		if dragon then
			dragon:Destroy()
			dragon = nil
		end
		return
	end
	if not dragon then
		dragon = (tpl :: Model):Clone()
		dragon.Parent = workspace.CurrentCamera
	end
	local D = WV.dragon
	local t = now - ((st:GetAttribute("DragonStartAt") :: number?) or now)
	local a = t / Config.Balance.stormDragon.duration * D.laps * math.pi * 2
	local c = Vector3.new(Config.World.keeper.x, 0, Config.World.keeper.z)
	local pos = c + Vector3.new(math.cos(a) * D.radius, D.altitude, math.sin(a) * D.radius)
	local ahead = c + Vector3.new(math.cos(a + 0.05) * D.radius, D.altitude, math.sin(a + 0.05) * D.radius)
	local dm = dragon :: Model
	dm:PivotTo(CFrame.lookAt(pos, ahead))
end

local function setText(t: string)
	if t ~= lastText and barText then
		lastText = t
		barText.Text = t
	end
end
local nextFlash = 0
local nextStar = 0

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function ensureRain(): Part
	if rainPart and rainPart.Parent then
		return rainPart
	end
	local p = Instance.new("Part")
	p.Name = "LocalRain"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(WV.rain.area, 1, WV.rain.area)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Rain"
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = WV.rain.rate
	pe.Lifetime = NumberRange.new(0.9, 1.2)
	pe.Speed = NumberRange.new(60, 70)
	pe.EmissionDirection = Enum.NormalId.Bottom
	pe.Size = NumberSequence.new(0.15)
	pe.Squash = NumberSequence.new(-3)
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 215, 235))
	pe.Transparency = NumberSequence.new(0.35)
	pe.LightInfluence = 1
	pe.Enabled = false
	pe.Parent = p
	p.Parent = workspace.CurrentCamera
	rainPart = p
	return p
end

-- the aurora curtains: invisible panels in an arc over the north of the sky, on each a SurfaceGui with vertical rays of different width and height;
-- a gradient by height (purple and transparent at the top, a bright green edge at the bottom)
local function buildAurora(): Folder
	local A = WV.aurora
	local f = Instance.new("Folder")
	f.Name = "LocalAurora"
	local rng = Random.new(2026)
	local function c3(c: { number }): Color3
		return Color3.fromRGB(c[1], c[2], c[3])
	end
	local colors = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c3(A.top)), ColorSequenceKeypoint.new(0.45, c3(A.mid)),
		ColorSequenceKeypoint.new(0.8, c3(A.low)), ColorSequenceKeypoint.new(1, c3(A.edge)),
	})
	local alpha = NumberSequence.new({ -- the top was invisible - the purple fringe now reads
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.18, 0.72), NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(0.88, 0.12), NumberSequenceKeypoint.new(1, 0.85),
	})
	local center = Vector3.new(Config.World.keeper.x, 0, Config.World.keeper.z)
	for i = 1, A.panels do
		local t = (i - 1) / math.max(A.panels - 1, 1)
		local ang = math.rad(A.arc[1] + (A.arc[2] - A.arc[1]) * t)
		local y = A.altitude[1] + (A.altitude[2] - A.altitude[1]) * (0.5 + 0.5 * math.sin(t * math.pi * 2.3))
		local pos = center + Vector3.new(math.sin(ang) * A.radius, y + A.size[2] / 2, -math.cos(ang) * A.radius)
		local p = Instance.new("Part")
		p.Name = "Curtain" .. i
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 1
		p.Size = Vector3.new(A.size[1], A.size[2], 0.2)
		p.CFrame = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4)))
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = A.brightness
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = A.pps
		sg.Parent = p
		local x = 0
		for k = 1, A.stripes do
			local w = rng:NextNumber(0.07, 0.2)
			local h = rng:NextNumber(0.55, 1)
			local fr = Instance.new("Frame")
			fr.Name = "Ray" .. k
			fr.BorderSizePixel = 0
			fr.BackgroundColor3 = Color3.new(1, 1, 1)
			fr.BackgroundTransparency = 1
			fr.AnchorPoint = Vector2.new(0, 1)
			fr.Position = UDim2.fromScale(x, 1 - rng:NextNumber(0, 0.12))
			fr.Size = UDim2.fromScale(w, h)
			local g = Instance.new("UIGradient")
			g.Rotation = 90
			g.Color = colors
			g.Transparency = alpha
			g.Parent = fr
			fr.Parent = sg
			table.insert(auroraStripes, { f = fr, phase = rng:NextNumber(0, math.pi * 2), speed = rng:NextNumber(0.6, 1.6) })
			x += w * rng:NextNumber(0.4, 0.75) -- overlapping rays: the curtain is continuous, no gaps between the bundles (P8 frame)
			if x > 0.92 then
				x = rng:NextNumber(0, 0.1)
			end
		end
		p.Parent = f
	end
	return f
end

-- the smooth appearance and shimmer of the rays; at zero - the folder is removed from the world (no rendering by day without an aurora)
local function stepAurora(on: boolean, dt: number)
	local A = WV.aurora
	auroraAlpha = math.clamp(auroraAlpha + (if on then dt else -dt) / A.fade, 0, 1)
	if auroraAlpha <= 0 then
		if auroraFolder then
			auroraFolder.Parent = nil
		end
		return
	end
	if not auroraFolder then
		auroraFolder = buildAurora()
	end
	local af = auroraFolder :: Folder
	if af.Parent ~= workspace.CurrentCamera then
		af.Parent = workspace.CurrentCamera
	end
	local t = os.clock()
	if auroraAlpha >= 1 and t - auroraTick < WV.aurora.tick then -- at full strength the shimmer is 20 Hz, not every frame (the appearance - smooth)
		return
	end
	auroraTick = t
	for _, s in auroraStripes do
		local flicker = 0.5 + 0.5 * math.sin(t * s.speed + s.phase)
		s.f.BackgroundTransparency = 1 - auroraAlpha * (0.55 + 0.45 * flicker)
	end
end

local function star(cam: Camera)
	local from = cam.CFrame.Position + cam.CFrame.LookVector * 120 + Vector3.new(math.random(-90, 90), math.random(50, 90), math.random(-90, 90))
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = Color3.fromRGB(255, 240, 200)
	p.Size = Vector3.new(0.4, 0.4, 6)
	local dir = Vector3.new(math.random(-10, 10) / 10, -1, math.random(-10, 10) / 10).Unit
	p.CFrame = CFrame.lookAt(from, from + dir)
	p.Parent = workspace.CurrentCamera
	local tw = TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Linear), { CFrame = p.CFrame + dir * 90, Transparency = 1 })
	tw:Play()
	tw.Completed:Once(function()
		p:Destroy()
	end)
end

-- a pill in the Roblox bar after 🎁 and 👋 - the fill of the shard scale
-- / the remaining weather and the text
local function buildBar(hud: any)
	if not hud or not hud.addTopbarButton then
		return
	end
	local b: TextButton = hud.addTopbarButton("Weather", "⛈", function() end)
	b.Size = UDim2.fromScale(4.2, 1)
	local lim = b:FindFirstChildOfClass("UISizeConstraint")
	if lim then
		lim.MaxSize = Vector2.new(Config.UI.topbar.size * 4.2, Config.UI.topbar.size)
	end
	local icon = b:FindFirstChild("Icon") :: TextLabel?
	if icon then
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.fromScale(0.04, 0.5)
		icon.Size = UDim2.fromScale(0.16, 0.56)
		icon.ZIndex = 3
	end
	b.ClipsDescendants = true
	barIcon = icon
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Color3.fromRGB(110, 85, 220)
	fill.BackgroundTransparency = 0.25
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	UIKit.corner(fill, 1)
	fill.Parent = b
	barText = UIKit.text(b, "", Color3.new(1, 1, 1), { Name = "T", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.22, 0.5), Size = UDim2.fromScale(0.74, 0.5), ZIndex = 3 })
	b.Visible = false
	bar = b :: any
	barFill = fill
end

local function update(dt: number)
	local st = state
	if not st then
		return
	end
	local now = workspace:GetServerTimeNow()
	local kind = (st:GetAttribute("Kind") :: string?) or ""
	local endsAt = (st:GetAttribute("EndsAt") :: number?) or 0
	if kind ~= "" and now >= endsAt then
		kind = ""
	end
	local cam = workspace.CurrentCamera
	-- storm: darker, rain, flashes
	local storm = kind == "storm"
	local aurora = kind == "aurora"
	if cc then
		if kind ~= lastKind then
			local A = WV.aurora
			TweenService:Create(cc, TweenInfo.new(2), { Brightness = if storm then WV.storm.brightness elseif aurora then A.dim else 0, Saturation = if storm then WV.storm.saturation else 0,
				TintColor = if storm then Color3.fromRGB(WV.storm.tint[1], WV.storm.tint[2], WV.storm.tint[3]) elseif aurora then Color3.fromRGB(A.tint[1], A.tint[2], A.tint[3]) else Color3.new(1, 1, 1) }):Play()
		end
		if storm and os.clock() >= nextFlash then
			nextFlash = os.clock() + WV.storm.flashEvery[1] + math.random() * (WV.storm.flashEvery[2] - WV.storm.flashEvery[1])
			local c = cc
			task.spawn(function()
				c.Brightness = 0.35
				task.wait(0.08)
				c.Brightness = WV.storm.brightness
				task.wait(0.12)
				c.Brightness = 0.25
				task.wait(0.06)
				c.Brightness = WV.storm.brightness
			end)
		end
	end
	local rain = ensureRain()
	local pe = rain:FindFirstChild("Rain") :: ParticleEmitter
	pe.Enabled = storm
	if storm and cam then
		rain.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, WV.rain.height, 0))
	end
	-- starfall: falling stars
	if kind == "starfall" and cam and os.clock() >= nextStar then
		nextStar = os.clock() + WV.starfall.every
		star(cam)
	end
	lastKind = kind
	stepAurora(aurora, dt)
	flyDragon(st, now)
	-- the strip: the dragon scale outranks the weather timer
	local dragonOn = st:GetAttribute("Dragon") == true and eligible -- without an adult the event is not on screen
	if barIcon then
		-- an Update Party without weather - its own icon (used to be ⛈ by default; the condition as for the strip text below)
		local party = kind == "" and ((st:GetAttribute("PartyEndsAt") :: number?) or 0) > now
		local ic = if dragonOn then "⛈" elseif party then "🎉" else (ICON[kind] or "⛈")
		if barIcon.Text ~= ic then
			barIcon.Text = ic
		end
	end
	if bar and barText and barFill then
		if dragonOn then
			local k = (st:GetAttribute("Shards") :: number?) or 0
			local n = (st:GetAttribute("ShardsTotal") :: number?) or 12
			local left = ((st:GetAttribute("DragonEndsAt") :: number?) or now) - now
			bar.Visible = not (hud ~= nil and hud.newbie ~= nil and hud.newbie()) -- a newcomer is not shown the event pill
			barFill.Size = UDim2.fromScale(math.clamp(k / math.max(n, 1), 0, 1), 1)
			setText(fmt(T.stormDragonShards, { k = k, n = n }) .. "  " .. Format.clock(left))
		elseif ((st:GetAttribute("PartyEndsAt") :: number?) or 0) > now and kind == "" then -- Update Party (09 §1)
			local pe2 = (st:GetAttribute("PartyEndsAt") :: number) - now
			bar.Visible = not (hud ~= nil and hud.newbie ~= nil and hud.newbie()) -- a newcomer is not shown the event pill
			barFill.Size = UDim2.fromScale(math.clamp(pe2 / (Config.LiveOps.updatePartyMinutes * 60), 0, 1), 1)
			setText(fmt(T.partyTimer, { time = Format.clock(pe2) }))
		elseif kind ~= "" then
			bar.Visible = not (hud ~= nil and hud.newbie ~= nil and hud.newbie()) -- a newcomer is not shown the event pill
			barFill.Size = UDim2.fromScale(math.clamp((endsAt - now) / Config.Balance.weather.duration, 0, 1), 1)
			setText(fmt(if storm then T.timerStorm elseif aurora then T.timerAurora else T.timerStarfall, { time = Format.clock(endsAt - now) }))
		else
			bar.Visible = false
		end
	end
end

function Weather.init(_snapshot: any, loaded: any)
	local e = Instance.new("ColorCorrectionEffect")
	e.Name = "WeatherCC"
	e.Parent = Lighting
	cc = e
	local ok, err = pcall(buildBar, loaded.HUD)
	if not ok then
		warn("[Weather] bar: " .. tostring(err))
	end
end

-- for Studio probes (ClientDebug "weather"): whether the player sees the event
function Weather.state(): string
	local st = state
	local n = 0
	for _, c in workspace:GetChildren() do
		if c.Name == "StormShard" and c:IsA("BasePart") and c.LocalTransparencyModifier < 0.5 then
			n += 1
		end
	end
	return string.format("eligible=%s dragon=%s bar=%s silhouette=%s shardsVisible=%d", tostring(eligible), tostring(st and st:GetAttribute("Dragon")),
		tostring(bar ~= nil and bar.Visible), tostring(dragon ~= nil and dragon.Parent ~= nil), n)
end

function Weather.start()
	state = ReplicatedStorage:WaitForChild("WeatherState", 30) :: Folder?
	recomputeEligible()
	Store.on("dragons", recomputeEligible)
	workspace.ChildAdded:Connect(shardVisibility)
	local warned = false
	RunService.Heartbeat:Connect(function(dt: number)
		local ok, err = pcall(update, dt)
		if not ok and not warned then
			warned = true
			warn("[Weather] " .. tostring(err))
		end
	end)
end

return Weather
