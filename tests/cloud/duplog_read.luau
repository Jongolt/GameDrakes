-- Read only: the journal of the "a dragon has one model" safeguard (Movement.dupGuard -> the DataStore DupLog_v1, the key dup_YYYYMMDD).
-- A line: the UTC time, the place version, the player, where (Companions / Nest / Workspace), uid, the reason. Run: python3 cloud_test.py duplog_read
local ds = game:GetService("DataStoreService"):GetDataStore("DupLog_v1")
local out = {}
for back = 0, 2 do
	local key = "dup_" .. os.date("!%Y%m%d", os.time() - back * 86400)
	local ok, v = pcall(function()
		return ds:GetAsync(key)
	end)
	out[key] = if ok then (if type(v) == "table" then v else "empty") else ("err " .. tostring(v))
end
return out
