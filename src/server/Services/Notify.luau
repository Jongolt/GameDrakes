--!strict
-- the queue of "calendar day ready" notifications. A player leaves -> a record Config.Notify.store[userId] =
-- Core/Notify.Entry (due, day, gift, dragon, left), the data snapshot is taken in PlayerData.onLeaving before EndSession; a join -> the record
-- is deleted (the player came back). The VPS sends hourly (tools/notify_send.py: Open Cloud user notifications, launch_data src=notify),
-- here only the queue: no keys and no HTTP. The notification consent is asked by the client (Gifts, the Roblox prompt), the server does not know it -
-- to those who did not consent Roblox simply does not deliver (FAILED_PRECONDITION at the sender).

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local NotifyCore = require(Shared:WaitForChild("Core"):WaitForChild("Notify"))

local Notify = {}

local services: { [string]: any } = {}
local N = Config.Notify
local store: DataStore? = nil
local lastWarn = 0
local pending = 0 -- queue records in flight: BindToClose waits for them (everyone leaves on a server restart after a release)

local function warnOnce(msg: string)
	local now = os.clock()
	if now - lastWarn >= 60 then -- a store failure on every leave does not flood the console
		lastWarn = now
		warn("[Notify] " .. msg)
	end
end

local function write(userId: number, entry: NotifyCore.Entry)
	if not store then
		return
	end
	pending += 1
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(tostring(userId), entry)
	end)
	pending -= 1
	if not ok then
		warnOnce("queue write failed for " .. userId .. ": " .. tostring(err))
	end
end

local function remove(userId: number)
	if not store then
		return
	end
	local ok, err = pcall(function()
		(store :: DataStore):RemoveAsync(tostring(userId))
	end)
	if not ok then
		warnOnce("queue remove failed for " .. userId .. ": " .. tostring(err))
	end
end

-- the snapshot on leaving: called by PlayerData before EndSession, does not yield (the write - as a separate task)
local function onLeaving(player: Player, data: any)
	local entry = NotifyCore.entry(data, os.time(), Config.Rewards, N, player.UserId, Config.Elements)
	if entry then
		task.spawn(write, player.UserId, entry)
	end
end

function Notify.init(s: { [string]: any })
	services = s
end

function Notify.start()
	if not (N and N.on) or RunService:IsStudio() then -- in Studio (P8) the queue of live players is not touched
		return
	end
	local ok, ds = pcall(function()
		return DataStoreService:GetDataStore(N.store)
	end)
	if not ok then
		warn("[Notify] no data store: " .. tostring(ds))
		return
	end
	store = ds
	services.PlayerData.onLeaving(onLeaving)
	Players.PlayerAdded:Connect(function(p)
		task.spawn(remove, p.UserId)
		-- a quick rejoin: the old server could have written the leave after our deletion; if the player left from here in the meantime too -
		-- do not touch: the record is already of his fresh leave
		task.delay(N.rejoinRemove, function()
			if p.Parent == Players then
				remove(p.UserId)
			end
		end)
	end)
	for _, p in Players:GetPlayers() do
		task.spawn(remove, p.UserId)
	end
	-- the server stop: wait for the queue writes started in PlayerRemoving (no longer than N.closeWait s of the 30 of BindToClose)
	game:BindToClose(function()
		local t0 = os.clock()
		while pending > 0 and os.clock() - t0 < N.closeWait do
			task.wait(0.2)
		end
		if pending > 0 then
			warn("[Notify] shutdown: " .. pending .. " queue writes not finished")
		end
	end)
end

return Notify
