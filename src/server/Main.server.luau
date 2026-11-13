--!strict
-- The server entry point (10 §2): settings, lighting (a safeguard for build.py), remotes by Remotes.List, services by an explicit
-- list: init(services) for all, then start() for all. The world and the players - in services (stages 1.4-1.7).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

Players.CharacterAutoLoads = false -- the character appears after the data and the nest (10 §2)

-- lighting: build.py writes the recipe into the file, but on load the engine recomputes Brightness for the style (1.5 -> 2.98),
-- so the server sets the whole recipe once more at start
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local L = Config.Lighting
pcall(function()
	(Lighting :: any).LightingStyle = (Enum :: any).LightingStyle[L.style]
	;(Lighting :: any).PrioritizeLightingQuality = L.prioritizeQuality
end)
pcall(function() -- C1: Technology lives only in the place file (build.py); here a safeguard in case the engine allows it
	(Lighting :: any).Technology = (Enum :: any).Technology[L.technology]
end)
pcall(function()
	Lighting.GeographicLatitude = L.geographicLatitude
	Lighting.ShadowSoftness = L.shadowSoftness
end)
Lighting.Brightness = L.brightness
Lighting.Ambient = rgb(L.ambient)
Lighting.OutdoorAmbient = rgb(L.outdoorAmbient)
Lighting.ColorShift_Top = rgb(L.colorShiftTop)
Lighting.EnvironmentDiffuseScale = L.envDiffuse
Lighting.EnvironmentSpecularScale = L.envSpecular
Lighting.ExposureCompensation = L.exposure
Lighting.GlobalShadows = L.globalShadows
Lighting.ClockTime = L.clockTime

-- remotes: the server creates the objects, the client waits for them to appear
local remotes = Instance.new("Folder")
remotes.Name = Remotes.Folder
for name, def in Remotes.List :: { [string]: any } do
	local r = Instance.new(def.kind)
	r.Name = name
	r.Parent = remotes
end
remotes.Parent = ReplicatedStorage

-- services: an explicit order (stage 1.4+: "PlayerData", "WorldBuilder", "Nest", "EggSpawner", "Incubation", "GrowthService",
-- "IncomeService", "DragonVisuals", "Movement", "QuestService", "Analytics", "Admin")
-- looks: Looks after Shop - color presets, the trail, the nest skin and aura, the tag above the head (07 add. 2.6)
-- 2.9: LiveOps - updates by date, the quest scrolls 16-20, the codes of the week (09 §1-3)
-- DragonStand - the Dragon of the Week stand on the plaza (after LiveOps: its clock)
local ORDER: { string } = { "Net", "AntiCheat", "ModelLibrary", "PlayerData", "WorldBuilder", "DragonVisuals", "Decor", "DayCycle", "Outfit", "Nest", "EggSpawner", "Incubation", "Movement", "Quest", "Index", "Shop", "Looks", "Reward", "Social", "Weather", "Badges", "Ascension", "LiveOps", "DragonStand", "Combat", "GlowEgg", "Raid", "Analytics", "Notify", "Admin", "Crowd", "Diag" } -- 2.1: Shop - ProcessReceipt, passes, intents, gifts -- 1.9: Movement - the companion, riding, flight, rings -- loop 1.7 (PlayerData, Nest, EggSpawner, Incubation) -- the library first: nest fences from meshes -- 1.5-1.6; then "PlayerData", "Nest", ... (1.7)
local folder = ServerScriptService:FindFirstChild("Services")
local services: { [string]: any } = {}
if folder then
	for _, name in ORDER do
		services[name] = require(folder:WaitForChild(name)) :: any
	end
	-- a failure of one service must not stop the server or keep players on the loading screen (1.5)
	for _, name in ORDER do
		local s = services[name]
		if s.init then
			local ok, err = pcall(s.init, services)
			if not ok then
				warn("[DragonNest] init " .. name .. " failed: " .. tostring(err))
			end
		end
	end
	for _, name in ORDER do
		local s = services[name]
		if s.start then
			task.spawn(function()
				local ok, err = pcall(s.start)
				if not ok then
					warn("[DragonNest] start " .. name .. " failed: " .. tostring(err))
				end
			end)
		end
	end
end

-- Temporary, until PlayerData and Nest exist: an empty snapshot to the client and the character at the SpawnLocation
if services.PlayerData == nil then
	local state = remotes:FindFirstChild("State") :: RemoteEvent
	local function onPlayer(player: Player)
		state:FireClient(player, { full = true, data = {} })
		task.wait(0.5)
		if player.Parent == Players then
			player:LoadCharacter()
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		task.spawn(onPlayer, p)
	end
end

print("[DragonNest] server up, " .. Config.GameVersion .. ", services: " .. #ORDER)
