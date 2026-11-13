--!strict
-- The player data on the client (10 §4): the first full snapshot from Main.client, then State packets { patch = { key = value } }.
-- Read-only for the interface; rewards and money are decided by the server. Subscription to a key: Store.on(key, fn).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Store = {}

local data: { [string]: any } = {}
local listeners: { [string]: { (any) -> () } } = {}

local function fire(key: string)
	for _, fn in listeners[key] or {} do
		task.spawn(fn, data[key])
	end
	for _, fn in listeners["*"] or {} do
		task.spawn(fn, key)
	end
end

function Store.get(key: string): any
	return data[key]
end

function Store.all(): { [string]: any }
	return data
end

function Store.on(key: string, fn: (any) -> ())
	local l = listeners[key]
	if not l then
		l = {}
		listeners[key] = l
	end
	table.insert(l, fn)
end

function Store.init(snapshot: any, _loaded: any)
	if typeof(snapshot) == "table" and typeof(snapshot.data) == "table" then
		data = snapshot.data
	end
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local state = remotes:WaitForChild("State") :: RemoteEvent
	state.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then
			return
		end
		if payload.full and typeof(payload.data) == "table" then
			data = payload.data
			for k in data do
				fire(k)
			end
		elseif typeof(payload.patch) == "table" then
			for k, v in payload.patch do
				data[k] = v
				fire(k)
			end
		end
	end)
end

return Store
