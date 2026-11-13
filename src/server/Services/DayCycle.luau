--!strict
-- The day cycle (P16; craft/04 §7.9 Ride A Pet): the phases from Config.World.dayCycle - dawn, day, sunset, night.
-- The server drives ClockTime and the lighting (Lighting replicates by itself), switches the lanterns (tag NightLight) on at sunset and night, writes
-- the attributes Phase / PhaseEndsAt / CycleSeconds into ReplicatedStorage/DayCycle for the icon and the timer in the HUD (1.8).
-- The weather (2.7 Weather: Storm, Starfall) goes on top: Starfall at night - more often. All lighting changes are here, not in Main.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local DC = Config.World.dayCycle
local L = Config.Lighting

local DayCycle = {}
local state = { phaseIndex = 1, elapsed = 0, lightsOn = false }
local folder: Folder? = nil

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function lerpColor(a: { number }, b: { number }, t: number): Color3
	return rgb(a):Lerp(rgb(b), t)
end

local function phaseByIndex(i: number)
	return DC.phases[((i - 1) % #DC.phases) + 1]
end

local function applyNightLight(inst: Instance, on: boolean)
	if inst:IsA("Light") or inst:IsA("ParticleEmitter") then -- emitters too (fireflies over the Springs brook)
		inst.Enabled = on
	elseif inst:IsA("BasePart") then
		inst.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
end

local function applyNightGlow(inst: Instance, on: boolean)
	if inst:IsA("BasePart") then
		local dayMat = (Enum.Material :: any)[inst:GetAttribute("DayMaterial") or "Slate"] or Enum.Material.Slate
		inst.Material = if on then Enum.Material.Neon else dayMat
		local c = inst:GetAttribute(if on then "NightColor" else "DayColor")
		if typeof(c) == "Color3" then
			inst.Color = c
		end
	end
end

local function setLights(on: boolean)
	if state.lightsOn == on then
		return
	end
	state.lightsOn = on
	for _, inst in CollectionService:GetTagged("NightLight") do
		applyNightLight(inst, on)
	end
	-- glows at night, by day - its own material and color (the plaza stone runes - carving)
	for _, inst in CollectionService:GetTagged("NightGlow") do
		applyNightGlow(inst, on)
	end
end

-- t in [0, 1] within a phase: the lighting interpolates from the current phase to the next over the last 25% of the phase (a smooth transition)
local function applyLighting(ph: any, nxt: any, t: number)
	local k = math.clamp((t - 0.75) / 0.25, 0, 1)
	Lighting.ClockTime = (ph.clock[1] + (ph.clock[2] - ph.clock[1]) * t) % 24
	Lighting.Ambient = lerpColor(ph.ambient, nxt.ambient, k)
	Lighting.OutdoorAmbient = lerpColor(ph.outdoor, nxt.outdoor, k)
	Lighting.Brightness = ph.brightness + (nxt.brightness - ph.brightness) * k
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Color = lerpColor(ph.atmoColor, nxt.atmoColor, k)
		atmo.Decay = lerpColor(ph.atmoDecay, nxt.atmoDecay, k)
		atmo.Haze = ph.haze + (nxt.haze - ph.haze) * k
		atmo.Glare = ph.glare + (nxt.glare - ph.glare) * k
	end
end

local function publish(ph: any)
	local f = folder
	if not f then
		return
	end
	f:SetAttribute("Phase", ph.id)
	f:SetAttribute("PhaseSeconds", ph.seconds)
	f:SetAttribute("PhaseEndsAt", os.time() + math.max(0, ph.seconds - state.elapsed))
	local nxtIndex = (state.phaseIndex % #DC.phases) + 1
	f:SetAttribute("NextPhase", phaseByIndex(nxtIndex).id)
end

function DayCycle.init(_services: { [string]: any })
	local f = Instance.new("Folder")
	f.Name = "DayCycle"
	local total = 0
	for _, ph in DC.phases do
		total += ph.seconds
	end
	f:SetAttribute("CycleSeconds", total)
	f.Parent = ReplicatedStorage
	folder = f
	-- a forced phase: the ForcePhase attribute on the folder
	f:GetAttributeChangedSignal("ForcePhase"):Connect(function()
		local want = f:GetAttribute("ForcePhase")
		if typeof(want) == "string" and want ~= "" then
			DayCycle.setPhase(want)
			f:SetAttribute("ForcePhase", "")
		end
	end)
	for i, ph in DC.phases do
		if ph.id == DC.startPhase then
			state.phaseIndex = i
		end
	end
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if sky then
		pcall(function()
			sky.StarCount = DC.starCount
		end)
	end
end

-- the phase by name (for admin commands and frame checks): DayCycle.setPhase("night")
function DayCycle.setPhase(id: string)
	for i, ph in DC.phases do
		if ph.id == id then
			state.phaseIndex = i
			state.elapsed = 0
			publish(ph)
			return true
		end
	end
	return false
end

function DayCycle.phase(): string
	return phaseByIndex(state.phaseIndex).id
end

function DayCycle.start()
	if not DC.enabled then
		return
	end
	-- the phase from world time - the same on all servers, joins are spread evenly around the cycle; before, the server started
	-- by day and the ad wave joined at minute 3-5 = night. In Studio - startPhase, as before
	if DC.worldClock == true and not RunService:IsStudio() then
		local total = 0
		for _, ph in DC.phases do
			total += ph.seconds
		end
		local t = os.time() % total
		for i, ph in DC.phases do
			if t < ph.seconds then
				state.phaseIndex = i
				state.elapsed = t
				break
			end
			t -= ph.seconds
		end
	end
	-- the server now starts at sunset/night too, and the Decor lights (InsertService) finish loading after the first setLights -
	-- new objects get the current state at once, otherwise the fires and lanterns stay dark until the next sunset
	CollectionService:GetInstanceAddedSignal("NightLight"):Connect(function(inst)
		applyNightLight(inst, state.lightsOn)
	end)
	CollectionService:GetInstanceAddedSignal("NightGlow"):Connect(function(inst)
		applyNightGlow(inst, state.lightsOn)
	end)
	publish(phaseByIndex(state.phaseIndex))
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		-- the Freeze attribute (0..1) on the folder holds the phase at this fraction - the light does not move
		local fz = folder and folder:GetAttribute("Freeze")
		if typeof(fz) == "number" then
			state.elapsed = phaseByIndex(state.phaseIndex).seconds * math.clamp(fz, 0, 0.999)
		else
			state.elapsed += dt
		end
		local ph = phaseByIndex(state.phaseIndex)
		if state.elapsed >= ph.seconds then
			state.elapsed -= ph.seconds
			state.phaseIndex = (state.phaseIndex % #DC.phases) + 1
			ph = phaseByIndex(state.phaseIndex)
			publish(ph)
		end
		local nxt = phaseByIndex(state.phaseIndex + 1)
		local t = state.elapsed / ph.seconds
		-- ClockTime every frame (the sun moves smoothly), the rest of the lighting and the lanterns 10 times a second
		Lighting.ClockTime = (ph.clock[1] + (ph.clock[2] - ph.clock[1]) * t) % 24
		acc += dt
		if acc >= 0.1 then
			acc = 0
			applyLighting(ph, nxt, t)
			setLights(ph.lights == true)
		end
	end)
end

return DayCycle
