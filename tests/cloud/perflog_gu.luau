-- Read only: the GUI census lines ("gu=j ...", "gu=m ...", Controllers/Perf census) from the PerfLog_v1 journal
-- for today and yesterday, in full (perflog_read cuts the output at 6000 characters, perflog_tail does not show detail). Run:
-- python3 cloud_test.py perflog_gu
local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
local out = {}
for back = 0, 1 do
	local key = "perf_" .. os.date("!%Y%m%d", os.time() - back * 86400)
	local ok, v = pcall(function()
		return ds:GetAsync(key)
	end)
	if ok and type(v) == "table" then
		for _, line in v do
			if type(line) == "string" and string.find(line, "gu=", 1, true) then
				table.insert(out, line)
			end
		end
	end
end
return out
