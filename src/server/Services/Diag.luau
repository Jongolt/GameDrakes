--!strict
-- a journal of the REAL server - only in the test game (universe independent of Config: TEST_GAME), in the live
-- game it does nothing. Every every s: the version, the players (dragons, FirstNest, RaidLeft, the golden egg), the Gloom nests, the guardians, the golden
-- nests, server errors and warnings since the start -> the DataStore Diag_v1 (keys srv_<JobId> and last). Read by tests/cloud/diag_read.luau.
local CollectionService = game:GetService("CollectionService")
local DataStoreService = game:GetService("DataStoreService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local TEST_GAME = 10773092486 -- the test game (place 113442730664291); the live one 10769731146 - does not write
local EVERY = 30

local Diag = {}
local services: { [string]: any } = {}

function Diag.init(s: { [string]: any })
	services = s
end

function Diag.start()
	if game.GameId ~= TEST_GAME or RunService:IsStudio() then
		return
	end
	local errs: { string } = {}
	local function add(msg: string, t: Enum.MessageType)
		if t == Enum.MessageType.MessageError or t == Enum.MessageType.MessageWarning then
			table.insert(errs, os.date("!%H:%M:%S") .. " " .. string.sub(msg, 1, 220))
			if #errs > 40 then
				table.remove(errs, 1)
			end
		end
	end
	for _, m in LogService:GetLogHistory() do
		add(m.message, m.messageType)
	end
	LogService.MessageOut:Connect(add)
	local ds = DataStoreService:GetDataStore("Diag_v1")
	while true do
		local ok, rec = pcall(function()
			local pl = {}
			for _, p in Players:GetPlayers() do
				local data = services.PlayerData and services.PlayerData.get(p)
				local dr = if data and typeof(data.nestOrder) == "table" then #data.nestOrder else -1
				local ge = if data and typeof(data.glowEgg) == "table" then data.glowEgg else nil
				table.insert(pl, {
					uid = p.UserId, dragons = dr, first = p:GetAttribute("FirstNest"), left = p:GetAttribute("RaidLeft"),
					glowWait = p:GetAttribute("GlowWait") ~= nil, glowRaid = p:GetAttribute("GlowRaid"),
					ge = if ge then { taken = ge.taken, readyAt = ge.readyAt, hatched = ge.hatched, n = ge.n } else nil,
				})
			end
			local nests, withEgg = 0, 0
			for _, m in CollectionService:GetTagged("RaidNest") do
				nests += 1
				if m:GetAttribute("HasEgg") == true then
					withEgg += 1
				end
			end
			local gf = workspace:FindFirstChild("GlowEggs")
			return {
				t = os.time(), v = game.PlaceVersion, job = game.JobId, players = pl, raidFolder = workspace:FindFirstChild("RaidNests") ~= nil,
				nests = nests, withEgg = withEgg, guards = #CollectionService:GetTagged("GloomChase"),
				gold = if gf then #gf:GetChildren() else -1, errs = errs,
			}
		end)
		if ok then
			pcall(function()
				ds:SetAsync("srv_" .. game.JobId, rec)
			end)
			pcall(function()
				ds:SetAsync("last", rec)
			end)
		end
		task.wait(EVERY)
	end
end

return Diag
