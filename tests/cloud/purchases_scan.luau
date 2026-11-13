-- Read only: all purchases over the last SINCE_H hours over all Profile_v2 profiles (ListKeysAsync + GetAsync within the budget).
-- Writes nothing, does not take sessions. The parameters: OFFSET - how many keys to skip (to continue), LIMIT_S - the task time limit.
-- Run: python3 cloud_test.py purchases_scan
local OFFSET, LIMIT_S, SINCE_H = 0, 210, 40
local DSS = game:GetService("DataStoreService")
local ds = DSS:GetDataStore("Profile_v2")
local t0, since = os.clock(), os.time() - SINCE_H * 3600
local keys = {}
while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end -- the listing budget without players is small, otherwise StandardListGameServerThrottled
local ok, pages = pcall(function() return ds:ListKeysAsync("", 100) end)
if not ok then return { err = "list: " .. tostring(pages) } end
while true do
	for _, k in pages:GetCurrentPage() do table.insert(keys, k.KeyName) end
	if pages.IsFinished then break end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end
	local ok2, e = pcall(function() pages:AdvanceToNextPageAsync() end)
	if not ok2 then return { err = "page: " .. tostring(e), keys = #keys } end
end
table.sort(keys)
local out, payers, scanned, errs, lastIdx = {}, {}, 0, 0, OFFSET
local total = { robux = 0, n = 0 }
for i = OFFSET + 1, #keys do
	if os.clock() - t0 > LIMIT_S then break end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) < 3 do task.wait(1) end
	local k = keys[i]
	local okg, v = pcall(function() return ds:GetAsync(k) end)
	scanned += 1; lastIdx = i
	if not okg then errs += 1; continue end
	local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
	if type(d) == "table" and type(d.purchaseLog) == "table" then
		for _, r in d.purchaseLog do
			if (r.t or 0) >= since then
				table.insert(out, string.format("%s UTC uid=%s %s robux=%s", os.date("!%d.%m %H:%M", r.t or 0), k, tostring(r.sku), tostring(r.robux)))
				payers[k] = (payers[k] or 0) + (tonumber(r.robux) or 0)
				total.robux += tonumber(r.robux) or 0; total.n += 1
			end
		end
	end
end
local np = 0
for _ in payers do np += 1 end
table.sort(out)
return { keysTotal = #keys, scannedFrom = OFFSET + 1, scannedTo = lastIdx, done = lastIdx >= #keys, errs = errs,
	purchases = out, payers = np, totalRobux = total.robux, receipts = total.n, seconds = math.floor(os.clock() - t0) }
