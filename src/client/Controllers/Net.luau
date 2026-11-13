--!strict
-- The client side of remote calls (10 §4): Net.call(name, ...) -> the server reply { ok, reason? } (a connection failure -
-- { ok = false, reason = "loading" }); Net.on(kind, fn) - a subscription to Notice (scenes, banners, toasts, coins).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loc = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Loc"))

local Net = {}

local remotes: Folder? = nil
local handlers: { [string]: { (any) -> () } } = {}

function Net.call(name: string, ...: any): { ok: boolean, reason: string?, [string]: any }
	local r = remotes and remotes:FindFirstChild(name)
	if not r or not r:IsA("RemoteFunction") then
		return { ok = false, reason = "loading" }
	end
	local args = table.pack(...)
	local ok, reply = pcall(function()
		return (r :: RemoteFunction):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok or typeof(reply) ~= "table" then
		return { ok = false, reason = "loading" }
	end
	return reply
end

function Net.on(kind: string, fn: (any) -> ())
	local l = handlers[kind]
	if not l then
		l = {}
		handlers[kind] = l
	end
	table.insert(l, fn)
end

function Net.init(_snapshot: any, _loaded: any)
	remotes = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	local notice = (remotes :: Folder):WaitForChild("Notice") :: RemoteEvent
	notice.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.kind) ~= "string" then
			return
		end
		Loc.resolve(payload) -- server templates (Loc.text) and static text/title/sub - into the player's language
		for _, fn in handlers[payload.kind] or {} do
			task.spawn(fn, payload)
		end
		for _, fn in handlers["*"] or {} do
			task.spawn(fn, payload)
		end
	end)
end

return Net
