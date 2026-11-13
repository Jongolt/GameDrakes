-- Read only (D6): the last 6 lines of today's journal IN FULL (detail with gc=/scr=/int=), without u<UserId>
local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
local v = ds:GetAsync("perf_" .. os.date("!%Y%m%d"))
local out = {}
if type(v) == "table" then
	for i = math.max(1, #v - 5), #v do
		out[#out + 1] = (string.gsub(v[i], " u%d+", ""))
	end
end
return out
