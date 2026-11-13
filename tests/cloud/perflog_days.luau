-- Read only: the admin client measurement journal for 8 days, a summary by version - the line count, mem, lua (LuaHeap),
-- tex, trn (min-max). We look for the version from which the memory grows. Run: python3 cloud_test.py perflog_days
local ds = game:GetService("DataStoreService"):GetDataStore("PerfLog_v1")
local out = {}
for back = 0, 7 do
	local key = "perf_" .. os.date("!%Y%m%d", os.time() - back * 86400)
	local ok, v = pcall(function()
		return ds:GetAsync(key)
	end)
	if ok and type(v) == "table" then
		local by = {}
		for _, l in v do
			local ver = string.match(l, " (v%d+) ") or "?"
			local s = by[ver] or { n = 0 }
			by[ver] = s
			s.n += 1
			for _, f in { "mem", "lua", "tex", "trn" } do
				local x = tonumber(string.match(l, " " .. f .. "=?(%d+)"))
				if x then
					s[f .. "Min"] = math.min(s[f .. "Min"] or x, x)
					s[f .. "Max"] = math.max(s[f .. "Max"] or x, x)
				end
			end
		end
		local lines = {}
		for ver, s in by do
			table.insert(lines, string.format("%s n=%d mem %s-%s lua %s-%s tex %s-%s trn %s-%s", ver, s.n, tostring(s.memMin), tostring(s.memMax),
				tostring(s.luaMin), tostring(s.luaMax), tostring(s.texMin), tostring(s.texMax), tostring(s.trnMin), tostring(s.trnMax)))
		end
		table.sort(lines)
		out[key] = lines
	else
		out[key] = if ok then "empty" else "err"
	end
end
return out
