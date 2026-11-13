-- Read only: the journal of the admin client FPS measurement (Admin, Controllers/Perf -> the DataStore PerfLog_v1, the key
-- perf_YYYYMMDD). A line: the UTC time, the version, the player, the mean fps over 15 s, low - the worst second, mem MB, dr - dragons in the world, bots,
-- pl - players, the screen (t - touch). Run: python3 cloud_test.py perflog_read
local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
local out = {}
for back = 0, 1 do
	local key = "perf_" .. os.date("!%Y%m%d", os.time() - back * 86400)
	local ok, v = pcall(function()
		return ds:GetAsync(key)
	end)
	out[key] = if ok then (if type(v) == "table" then v else "empty") else ("err " .. tostring(v))
end
return out
