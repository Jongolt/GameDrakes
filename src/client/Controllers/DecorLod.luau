--!strict
-- Distant decor: on the own client small decor models (`World.Meshes/<kind>/<model>`)
-- beyond a threshold from the camera are not drawn (LocalTransparencyModifier on their parts, nothing goes to the server). The threshold by model height:
-- Config.World.decor.lod.levels[level] = { { maxH, dist }, ... } - the first row where height < maxH; no row - the model is always visible
-- (trees, rocks, islands: the island silhouette from above stays). Levels: off - everything visible; normal - default; strong - stronger.
-- The Perf test experiment switches the level through DecorLod.setLevel. New models (streaming) are picked up by rebuilding the list.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local DecorLod = {}

local L = Config.World.decor.lod
type Item = { model: Model, pos: Vector3, h: number, parts: { BasePart }, hidden: boolean? } -- hidden nil - not applied yet
local items: { Item } = {}
local level: string = L.level
local dirty = true
local _ = Players

local function limitFor(h: number): number?
	local rows = L.levels[level]
	if not rows then
		return nil
	end
	for _, r in rows do
		if h < r[1] then
			return r[2]
		end
	end
	return nil
end

local function setHidden(it: Item, hide: boolean)
	it.hidden = hide
	local v = if hide then 1 else 0
	for _, p in it.parts do
		if p.Parent then
			p.LocalTransparencyModifier = v
		end
	end
end

-- rebuild the list (streaming delivers models and parts in pieces): old hiding is removed, the next pass applies the threshold
local function rescan(meshes: Instance)
	for _, it in items do
		if it.hidden then
			setHidden(it, false)
		end
	end
	items = {}
	for _, kf in meshes:GetChildren() do
		for _, m in kf:GetChildren() do
			if m:IsA("Model") then
				local ok, cf, size = pcall(function()
					return m:GetBoundingBox()
				end)
				if ok then
					local parts: { BasePart } = {}
					for _, d in m:GetDescendants() do
						if d:IsA("BasePart") then
							table.insert(parts, d)
						end
					end
					table.insert(items, { model = m, pos = cf.Position, h = size.Y, parts = parts, hidden = nil })
				end
			end
		end
	end
end

local function pass()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local pos = cam.CFrame.Position
	for _, it in items do
		local lim = limitFor(it.h)
		local hide = lim ~= nil and (it.pos - pos).Magnitude > lim
		if hide ~= it.hidden then
			setHidden(it, hide)
		end
	end
end

-- level: "off" | "normal" | "strong" (Perf test); redraw at once
function DecorLod.setLevel(name: string)
	if L.levels[name] or name == "off" then
		level = name
		pass()
	end
end

function DecorLod.level(): string
	return level
end

function DecorLod.start()
	if not L.on then
		return
	end
	task.spawn(function()
		local world = workspace:WaitForChild("World", 60)
		local meshes = world and world:WaitForChild("Meshes", 60)
		if not meshes then
			return
		end
		meshes.DescendantAdded:Connect(function(d)
			if d:IsA("Model") or d:IsA("BasePart") then
				dirty = true
			end
		end)
		meshes.DescendantRemoving:Connect(function(d)
			if d:IsA("Model") then
				dirty = true
			end
		end)
		local sinceScan = 0
		while true do
			task.wait(L.every)
			sinceScan += L.every
			if dirty and sinceScan >= L.rescanEvery then
				dirty = false
				sinceScan = 0
				rescan(meshes)
			end
			pass()
		end
	end)
end

return DecorLod
