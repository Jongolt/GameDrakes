--!strict
-- Remote calls (10 §4): one handler per name, argument validation by the shared/Remotes schema (Validate), a rate limit
-- (Config.RateLimit; exceeding - "too_fast", 50 excesses per minute - Kick), the reply { ok, reason?, ... }. Notice - scenes,
-- banners, toasts and the server feed (server -> client). Money, rarities and timers are not accepted from the client.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Validate = require(Shared:WaitForChild("Validate"))

local Net = {}

export type Reply = { ok: boolean, reason: string?, [string]: any }

local folder: Folder? = nil
local services: { [string]: any } = {} -- Analytics for anticheat_kick
local last: { [Player]: { [string]: number } } = {}
local strikes: { [Player]: { count: number, since: number } } = {}

local function remote(name: string): Instance?
	return folder and folder:FindFirstChild(name)
end

local function allowed(player: Player, name: string): boolean
	local per = Config.RateLimit[name]
	if not per then
		return true
	end
	local now = os.clock()
	local t = last[player]
	if not t then
		t = {}
		last[player] = t
	end
	if t[name] and now - t[name] < 1 / per then
		local s = strikes[player]
		if not s or now - s.since > 60 then
			s = { count = 0, since = now }
			strikes[player] = s
		end
		s.count += 1
		if s.count >= Config.KickAfterTooFastPerMinute then
			if services.Analytics then -- anticheat_kick
				pcall(services.Analytics.custom, player, "anticheat_kick", 1, { reason = "too_fast" })
			end
			player:Kick("Too many requests")
		end
		return false
	end
	t[name] = now
	return true
end

-- a RemoteFunction handler: fn(player, ...) -> Reply
function Net.handle(name: string, fn: (Player, ...any) -> Reply)
	local r = remote(name)
	local def = (Remotes.List :: any)[name]
	assert(r and r:IsA("RemoteFunction") and def, "Net.handle: no RemoteFunction " .. name)
	r.OnServerInvoke = function(player: Player, ...: any): Reply
		if not allowed(player, name) then
			return { ok = false, reason = "too_fast" }
		end
		local args = table.pack(...)
		args.n = nil
		local ok, why = Validate.args(args :: any, def.args or {})
		if not ok then
			return { ok = false, reason = "bad_request", detail = why }
		end
		local okCall, reply = pcall(fn, player, ...)
		if not okCall then
			warn("[Net] " .. name .. ": " .. tostring(reply))
			return { ok = false, reason = "bad_request" }
		end
		return reply
	end
end

-- a scene/banner/toast to one player: { kind = "toast" | "hatch" | "stage_up" | "coins" | ..., ... }
function Net.notice(player: Player, payload: { [string]: any })
	local r = remote("Notice")
	if r and r:IsA("RemoteEvent") and player.Parent == Players then
		r:FireClient(player, payload)
	end
end

function Net.noticeAll(payload: { [string]: any })
	local r = remote("Notice")
	if r and r:IsA("RemoteEvent") then
		r:FireAllClients(payload)
	end
end

function Net.init(_services: { [string]: any })
	services = _services
	folder = ReplicatedStorage:WaitForChild(Remotes.Folder) :: Folder
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
		strikes[p] = nil
	end)
end

return Net
