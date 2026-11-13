-- A check of the built place (Lune 0.10.5): the light by the recipe, CharacterAutoLoads, the script layout.
-- Run: tools/lune/lune run roblox_game/tests/inspect_place.luau roblox_game/build/place.rbxlx
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "roblox_game/build/place.rbxlx"
local game = roblox.deserializePlace(fs.readFile(path))
local failed = 0
local function expect(name, got, want)
	local ok = tostring(got) == tostring(want)
	print(string.format("%s %s: %s", if ok then "ok  " else "FAIL", name, tostring(got)))
	if not ok then
		failed += 1
	end
end
local function prop(inst, name)
	local ok, v = pcall(function()
		return inst[name]
	end)
	return if ok then v else "<no property: " .. tostring(v) .. ">"
end

local lighting = game:GetService("Lighting")
expect("Lighting.LightingStyle", prop(lighting, "LightingStyle"), "Enum.LightingStyle.Realistic") -- C1: realistic light
expect("Lighting.Technology", prop(lighting, "Technology"), "Enum.Technology.Future")
expect("Lighting.GeographicLatitude", prop(lighting, "GeographicLatitude"), 55)
expect("Lighting.Brightness", math.floor(prop(lighting, "Brightness") * 100 + 0.5) / 100, 1.7)
expect("Lighting.ClockTime", prop(lighting, "ClockTime"), 10.5)
expect("Lighting.GlobalShadows", prop(lighting, "GlobalShadows"), true)
expect("Lighting.ExposureCompensation", math.floor(prop(lighting, "ExposureCompensation") * 100 + 0.5) / 100, -0.15)
local a = prop(lighting, "Ambient")
expect("Lighting.Ambient", typeof(a) == "Color3" and string.format("%d,%d,%d", a.R * 255 + 0.5, a.G * 255 + 0.5, a.B * 255 + 0.5) or a, "70,72,80")
local kids = {}
for _, c in lighting:GetChildren() do
	kids[c.ClassName] = c
end
expect("Atmosphere.Density", kids.Atmosphere and math.floor(prop(kids.Atmosphere, "Density") * 100 + 0.5) / 100, 0.33)
expect("Bloom.Threshold", kids.BloomEffect and prop(kids.BloomEffect, "Threshold"), 2)
expect("SunRays", kids.SunRaysEffect ~= nil, true)
expect("ColorCorrection.Saturation", kids.ColorCorrectionEffect and math.floor(prop(kids.ColorCorrectionEffect, "Saturation") * 100 + 0.5) / 100, 0.1)
expect("Sky.SunAngularSize", kids.Sky and prop(kids.Sky, "SunAngularSize"), 12)
expect("Players.CharacterAutoLoads", prop(game:GetService("Players"), "CharacterAutoLoads"), false)
local ws = game:GetService("Workspace")
expect("Workspace.StreamingEnabled", prop(ws, "StreamingEnabled"), true) -- C3
expect("Workspace.StreamingTargetRadius", prop(ws, "StreamingTargetRadius"), 1400)
expect("Workspace.ModelStreamingBehavior", prop(ws, "ModelStreamingBehavior"), "Enum.ModelStreamingBehavior.Improved")
local terrain = ws:FindFirstChildOfClass("Terrain")
expect("Terrain.Decoration", terrain and prop(terrain, "Decoration"), true)
expect("Terrain.Clouds", terrain and terrain:FindFirstChildOfClass("Clouds") ~= nil, true)
-- C1: the terrain MaterialVariants in MaterialService and the base material overrides by name
local ms = game:GetService("MaterialService")
local variants = {}
for _, v in ms:GetChildren() do
	if v.ClassName == "MaterialVariant" then
		variants[v.Name] = tostring(prop(v, "BaseMaterial")) .. " x" .. tostring(prop(v, "StudsPerTile"))
	end
end
local nVariants = 0
for name, info in variants do
	nVariants += 1
	print("     variant " .. name .. ": " .. info)
end
expect("MaterialService: variants", nVariants, process.env.DN_EXPECT_VARIANTS or 5)
expect("MaterialService.LimestoneName", prop(ms, "LimestoneName"), nVariants > 0 and "DN_GraniteMoss" or "Limestone")
expect("MaterialService.GroundName", prop(ms, "GroundName"), nVariants > 0 and "DN_DarkEarth" or "Ground")

local rf = game:GetService("ReplicatedFirst")
expect("ReplicatedFirst/Main (LocalScript)", rf:FindFirstChild("Main") and rf.Main.ClassName, "LocalScript")
expect("ReplicatedFirst/LoadingScreen", rf:FindFirstChild("LoadingScreen") and rf.LoadingScreen.ClassName, "ModuleScript")
-- the splash 3D hatchling is baked into the place file (build.py baked_models)
local ld = rf:FindFirstChild("LoadingDragon")
local ldMesh = ld and ld:FindFirstChildWhichIsA("MeshPart")
expect("ReplicatedFirst/LoadingDragon - a model with a MeshPart", ldMesh ~= nil and ld.PrimaryPart == ldMesh, true)
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
-- the appearance: + Looks; + Social (2.6), + Weather (2.7) - 23 in total; 2.9: + LiveOps - 24; + IncubatorShape - 25
expect("Shared/Core modules", shared and shared:FindFirstChild("Core") and #shared.Core:GetChildren(), 34) -- the Core modules count
for _, n in { "Config", "Content", "Strings", "Remotes", "Validate", "DecorAssets" } do
	expect("Shared/" .. n, shared and shared:FindFirstChild(n) ~= nil, true)
end
local sss = game:GetService("ServerScriptService")
expect("ServerScriptService/Main (Script)", sss:FindFirstChild("Main") and sss.Main.ClassName, "Script")
expect("Vendor/ProfileStore", sss:FindFirstChild("Vendor") and sss.Vendor:FindFirstChild("ProfileStore") ~= nil, true)
expect("Services/WorldBuilder", sss:FindFirstChild("Services") and sss.Services:FindFirstChild("WorldBuilder") ~= nil and sss.Services.WorldBuilder.ClassName, "ModuleScript")
expect("Main starts WorldBuilder", string.find(sss.Main.Source, '"WorldBuilder"', 1, true) ~= nil, true)
for _, n in { "ModelLibrary", "DragonVisuals", "Decor", "DayCycle", "Outfit", "Looks", "LiveOps" } do -- Looks: the appearance; LiveOps: 2.9
	expect("Services/" .. n, sss:FindFirstChild("Services") and sss.Services:FindFirstChild(n) ~= nil, true)
	expect("Main starts " .. n, string.find(sss.Main.Source, '"' .. n .. '"', 1, true) ~= nil, true)
end
local dv = sss:FindFirstChild("Services") and sss.Services:FindFirstChild("DragonVisuals")
expect("DragonVisuals: require ModelLibrary is rewritten", dv and string.find(dv.Source, "require(script.Parent.ModelLibrary)", 1, true) ~= nil, true)
-- the rewritten requires: the Core/Odds source has require(script.Parent.Eggs)
local odds = shared and shared.Core:FindFirstChild("Odds")
expect("require is rewritten to script.Parent", odds and string.find(odds.Source, "require(script.Parent.Eggs)", 1, true) ~= nil, true)
expect("no relative requires are left", odds and string.find(odds.Source, 'require("./', 1, true) == nil, true)

local parts = 0
for _, d in game:GetService("Workspace"):GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end
print("parts in Workspace:", parts)
if failed > 0 then
	print("CHECKS FAILED: " .. failed)
	process.exit(1)
end
print("the place file is in order")
