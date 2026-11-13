-- the button overlaps for players (Config.Analytics.uiOverlap, Controllers/Declutter -> Services/Analytics): the pairs over the last 3 UTC days
-- from the DataStore UiOverlap_v1 (the key d_YYYYMMDD), by descending count. Read only. Run: python3 cloud_test.py uioverlap_read
local DSS = game:GetService("DataStoreService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))
local UO = Config.Analytics.uiOverlap
local store = DSS:GetDataStore(UO.store)
local out = {}
for back = 0, 2 do
	local key = "d_" .. os.date("!%Y%m%d", os.time() - back * 86400)
	local ok, t = pcall(function()
		return store:GetAsync(key)
	end)
	local rows = {}
	if ok and typeof(t) == "table" then
		for k, e in t do
			table.insert(rows, { pair = k, n = tonumber(e.n) or 0, screen = e.s, dev = e.d })
		end
		table.sort(rows, function(a, b)
			return a.n > b.n
		end)
	end
	table.insert(out, { day = key, ok = ok, pairs = rows })
end
return out
