-- Read only: the last 45 lines of today's measurement journal, briefly (without the memory breakdown, except lua/tex/trn).
local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
local v = ds:GetAsync("perf_" .. os.date("!%Y%m%d"))
local out = {}
if type(v) == "table" then
	for i = math.max(1, #v - 44), #v do
		local l = v[i]
		local short = string.match(l, "^(.-) u%d+") or l
		local rest = string.match(l, "(fps%d+ low%d+ mem%d+ dr%d+ bots%d+)") or ""
		local m = string.match(l, "m=(%S+)") or ""
		local ph = string.match(l, "ph=(%S+)") or ""
		out[#out + 1] = short .. " " .. rest .. " m=" .. m .. " " .. ph
	end
end
return out
