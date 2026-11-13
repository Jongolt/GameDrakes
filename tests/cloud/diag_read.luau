-- read only - the journal of a real server of the test game (Services/Diag): the last entry and the entries by server
local ds = game:GetService("DataStoreService"):GetDataStore("Diag_v1")
local out = {}
local ok, v = pcall(function() return ds:GetAsync("last") end)
out.last = if ok then v else ("err " .. tostring(v))
local okL, pages = pcall(function() return ds:ListKeysAsync("srv_", 50) end)
out.servers = {}
if okL then
	for _, k in pages:GetCurrentPage() do
		local ok2, r = pcall(function() return ds:GetAsync(k.KeyName) end)
		if ok2 and type(r) == "table" then
			table.insert(out.servers, { key = k.KeyName, t = r.t, v = r.v, nests = r.nests, withEgg = r.withEgg, guards = r.guards, gold = r.gold, players = r.players, nErr = #(r.errs or {}) })
		end
	end
end
return out
