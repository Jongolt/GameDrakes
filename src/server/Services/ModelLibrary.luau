--!strict
-- The mesh library (10 §3, task 1.6): loads the models of the heroes, eggs and the Keeper by asset id (InsertService:LoadAsset -
-- only the game owner's assets), prepares them (anchored, no collisions or scripts), normalizes the height to 1 stud and keeps them in
-- ServerStorage/ModelLibrary. get() returns a clone; on a failure nil - DragonVisuals draws the fallback figure of parts.
-- The same id is not loaded twice: the second call waits for the first.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared:WaitForChild("Content"))
local Config = require(Shared:WaitForChild("Config"))

local ModelLibrary = {}

local folder: Folder? = nil
local cache: { [number]: Model | boolean } = {} -- Model | false (failure)
local pending: { [number]: boolean } = {}
local stats = { loaded = 0, failed = 0 }

local function prepare(model: Model)
	for _, d in table.clone(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = true
			d.Massless = true
			if d:IsA("MeshPart") then
				model.PrimaryPart = d
			end
		elseif d:IsA("LuaSourceContainer") then -- ModuleScripts too (a backdoor waits until someone requires it)
			d:Destroy()
		end
	end
	if not model.PrimaryPart then
		model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart", true)
	end
	local _, size = model:GetBoundingBox()
	if size.Y > 0 then
		model:ScaleTo(model:GetScale() / size.Y) -- the height exactly 1 stud; the stage sets the scale
	end
end

-- Load (with waiting) and cache; nil on a failure
function ModelLibrary.load(assetId: number): Model?
	if not assetId or assetId == 0 then
		return nil
	end
	while pending[assetId] do
		task.wait(0.1)
	end
	local c = cache[assetId]
	if c ~= nil then
		return if typeof(c) == "Instance" then c :: Model else nil
	end
	pending[assetId] = true
	local ok, container = pcall(function()
		return InsertService:LoadAsset(assetId)
	end)
	if not ok or not container then
		warn("[ModelLibrary] asset " .. tostring(assetId) .. " failed: " .. tostring(container))
		cache[assetId] = false
		pending[assetId] = nil
		stats.failed += 1
		return nil
	end
	local model = container:FindFirstChildWhichIsA("Model")
	if not model then
		model = Instance.new("Model")
		for _, ch in container:GetChildren() do
			ch.Parent = model
		end
	end
	model.Name = "Asset_" .. tostring(assetId)
	model.Parent = folder -- first take it out of the container, otherwise Destroy() of the container locks the Parent
	container:Destroy()
	prepare(model)
	cache[assetId] = model
	pending[assetId] = nil
	stats.loaded += 1
	return model
end

-- a clone only if the model is already loaded; without waiting (loading in progress or not started - nil)
function ModelLibrary.peek(assetId: number): Model?
	local c = cache[assetId]
	return if typeof(c) == "Instance" then (c :: Model):Clone() else nil
end

-- A clone of a ready model (height 1) or nil
function ModelLibrary.get(assetId: number): Model?
	local m = ModelLibrary.load(assetId)
	return if m then m:Clone() else nil
end

function ModelLibrary.stats(): { loaded: number, failed: number }
	return stats
end

function ModelLibrary.init(_services: { [string]: any })
	local old = ServerStorage:FindFirstChild("ModelLibrary")
	if old then
		old:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = "ModelLibrary"
	f.Parent = ServerStorage
	folder = f
end

-- All hero models in advance, so the first dragon appears without a delay
function ModelLibrary.start()
	local ids: { [number]: boolean } = {}
	for _, list in Content.Assets.dragons do
		for _, id in list do
			ids[id] = true
		end
	end
	for id in ids do
		task.spawn(ModelLibrary.load, id)
	end
	-- the hatchling for the splash - a copy in ReplicatedStorage (goes
	-- to the clients before the world); without poses or an animation controller - the splash moves the model as a whole. In Studio the server does not load the model
	-- (not authorized) - the probe places it from edit mode, then this copy is not needed
	task.spawn(function()
		local L = Config.UI.splashDragon
		local list = L and (Content.Assets.dragons :: any)[L.element]
		local m = list and ModelLibrary.get(list[L.stage + 1])
		if not m or ReplicatedStorage:FindFirstChild("LoadingDragon") or game:GetService("ReplicatedFirst"):FindFirstChild("LoadingDragon") then
			return -- the model is baked into the place file (ReplicatedFirst) - the copy is not needed
		end
		for _, d in m:GetDescendants() do
			if d:IsA("AnimationController") or (d:IsA("Folder") and d.Name == "InitialPoses") then
				d:Destroy()
			end
		end
		m.Name = "LoadingDragon"
		m.Parent = ReplicatedStorage
	end)
end

return ModelLibrary
