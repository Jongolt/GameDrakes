--!strict
-- The ocean to the horizon and the mist at the world edge. With streaming the terrain water exists for the player
-- only within ~1,400-2,000 studs, and the server "sea" strips (WorldBuilder seaPlane) do not reach the client at all (they are streamed and
-- a part is never larger than 2,048 studs) - beyond that is emptiness, and the haze paints it in the sky color.
-- (1) The sea tiles are created HERE, on the client (local parts are not streamed): inside the terrain water square - a grid of ocean.inner,
-- a tile hides while the terrain under it is loaded (the water near the player is drawn by the terrain - the shallows by the shore do not darken); outside - up to
-- ocean.outerTo in pieces no larger than ocean.piece. (2) The mist at the edge: the Atmosphere density grows from mist.from to mist.to of the flight limit
-- (as in Fly: waterSize/2 - margin) - at the very edge the world dissolves into sea mist; the turnBack banner already exists (Fly).

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Ocean = {}

local W = Config.World
local O = W.ocean
local SP = W.seaPlane
local inner: { { part: BasePart, x: number, z: number } } = {}
local folder: Folder? = nil
local baseDensity = (Config.Lighting.atmosphere and Config.Lighting.atmosphere.density) or 0.33
local mistK = -1

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function tile(x: number, z: number, sx: number, sz: number, y: number): BasePart
	local p = Instance.new("Part")
	p.Name = "Sea"
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.Material = Enum.Material.SmoothPlastic
	p.Color = rgb(SP.color)
	p.Reflectance = SP.reflectance or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.Size = Vector3.new(sx, 1, sz)
	p.CFrame = CFrame.new(x, y - 0.5, z)
	p.Parent = folder
	return p
end

-- a strip [x1,x2] x [z1,z2] in pieces no larger than piece
local function strip(x1: number, x2: number, z1: number, z2: number, y: number)
	local nx = math.ceil((x2 - x1) / O.piece)
	local nz = math.ceil((z2 - z1) / O.piece)
	local sx, sz = (x2 - x1) / nx, (z2 - z1) / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			tile(x1 + (i + 0.5) * sx, z1 + (j + 0.5) * sz, sx, sz, y)
		end
	end
end

local function build()
	local f = Instance.new("Folder")
	f.Name = "OceanClient"
	f.Parent = workspace
	folder = f
	local y = W.island2.seaLevel - (SP.below or 0.35)
	local half = W.waterSize / 2
	local R = O.outerTo
	-- outside the terrain water square: 4 strips
	strip(-R, R, -R, -half, y)
	strip(-R, R, half, R, y)
	strip(-R, -half, -half, half, y)
	strip(half, R, -half, half, y)
	-- inside: a grid, visibility by the terrain
	local n = math.max(1, math.floor(W.waterSize / O.inner + 0.5))
	local s = W.waterSize / n
	for i = 0, n - 1 do
		for j = 0, n - 1 do
			local x, z = -half + (i + 0.5) * s, -half + (j + 0.5) * s
			local p = tile(x, z, s, s, y)
			p.Transparency = 1
			table.insert(inner, { part = p, x = x, z = z })
		end
	end
end

-- the terrain under the tile is loaded (water, bottom, land) - the terrain draws; otherwise the tile
local function loadedAt(x: number, z: number): boolean
	local ok, solid = pcall(function()
		local sea = W.island2.seaLevel
		local region = Region3.new(Vector3.new(x - 2, sea - 4, z - 2), Vector3.new(x + 2, sea, z + 2)):ExpandToGrid(4)
		local mats = workspace.Terrain:ReadVoxels(region, 4)
		return mats[1][1][1] ~= Enum.Material.Air
	end)
	return ok and solid == true
end

local function refreshInner()
	for _, t in inner do
		t.part.Transparency = if loadedAt(t.x, t.z) then 1 else 0
	end
end

-- the mist at the edge: the fraction of the way from mist.from to mist.to of the flight limit by the camera position
local function mist()
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local cam = workspace.CurrentCamera
	if not atmo or not cam then
		return
	end
	local B = W.bounds
	local limit = W.waterSize / 2 - B.margin
	local p = cam.CFrame.Position
	local r = math.max(math.abs(p.X), math.abs(p.Z)) / limit
	local M = O.mist
	local k = math.clamp((r - M.from) / (M.to - M.from), 0, 1)
	k = k * k * (3 - 2 * k)
	if math.abs(k - mistK) < 0.002 then
		return
	end
	mistK = k
	atmo.Density = baseDensity + (M.density - baseDensity) * k
end

-- for Studio probes
function Ocean.state(): string
	local shown = 0
	for _, t in inner do
		if t.part.Transparency < 1 then
			shown += 1
		end
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	return string.format("ocean parts=%d inner=%d shown=%d mist=%.2f density=%.2f", folder and #folder:GetChildren() or 0, #inner, shown, math.max(mistK, 0), atmo and atmo.Density or -1)
end

function Ocean.init(_snapshot: any, _loaded: any)
	if not O or not SP then
		return
	end
	local ok, err = pcall(build)
	if not ok then
		warn("[Ocean] " .. tostring(err))
	end
end

function Ocean.start()
	if not O or not SP then
		return
	end
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		baseDensity = atmo.Density
	end
	task.spawn(function()
		while true do
			pcall(refreshInner)
			task.wait(O.check)
		end
	end)
	RunService.Heartbeat:Connect(function()
		pcall(mist)
	end)
	Players.LocalPlayer.CharacterAdded:Connect(function()
		task.delay(2, function()
			pcall(refreshInner)
		end)
	end)
end

return Ocean
