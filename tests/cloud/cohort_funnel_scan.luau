-- Read only: the newcomer funnel over all Profile_v2 profiles created after SINCE (unix UTC): the onboarding flags, sessions, time
-- devices, purchases. Writes nothing. Run: python3 cloud_test.py cohort_funnel_scan
local SINCE, LIMIT_S = 1792785600, 210 -- the cohort start (UTC)
local DSS = game:GetService("DataStoreService")
local ds = DSS:GetDataStore("Profile_v2")
local t0 = os.clock()
local keys = {}
while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end -- the listing budget without players is small, otherwise StandardListGameServerThrottled
local ok, pages = pcall(function() return ds:ListKeysAsync("", 100) end)
if not ok then return { err = tostring(pages) } end
while true do
	for _, k in pages:GetCurrentPage() do table.insert(keys, k.KeyName) end
	if pages.IsFinished then break end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end
	local ok2, e = pcall(function() pages:AdvanceToNextPageAsync() end)
	if not ok2 then return { err = tostring(e) } end
end
table.sort(keys)
local flags = { "eggFound", "firstHatch", "fedOnce", "coinsCollected", "rode", "glided", "ring", "flew" }
local agg = { n = 0, old = 0, errs = 0, scanned = 0, flagCounts = {}, favAsked = 0, vip = 0, starter = 0, payers = 0, robux = 0,
	devices = {}, sources = {}, sessions = {}, play = {}, returned = 0, dragons = {} }
for _, f in flags do agg.flagCounts[f] = 0 end
local rows = {}
for i, k in keys do
	if os.clock() - t0 > LIMIT_S then agg.cut = i break end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) < 3 do task.wait(1) end
	local okg, v = pcall(function() return ds:GetAsync(k) end)
	agg.scanned += 1
	if not okg then agg.errs += 1 continue end
	local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
	if type(d) ~= "table" then continue end
	if (d.createdAt or 0) < SINCE then agg.old += 1 continue end
	agg.n += 1
	local ob = d.onboarding or {}
	local fs = ""
	for _, f in flags do
		if ob[f] then agg.flagCounts[f] += 1; fs ..= f:sub(1, 2) .. " " end
	end
	if ob.favAsked then agg.favAsked += 1 end
	local ow = d.owned or {}
	if ow.vip then agg.vip += 1 end
	if ow.starter then agg.starter += 1 end
	local spent = 0
	for _, r in d.purchaseLog or {} do spent += tonumber(r.robux) or 0 end
	if spent > 0 or ow.vip then agg.payers += 1 end
	agg.robux += spent
	local dev, src = tostring(d.device or "?"), tostring(d.source or "?")
	agg.devices[dev] = (agg.devices[dev] or 0) + 1
	agg.sources[src] = (agg.sources[src] or 0) + 1
	local s = tonumber(d.sessions) or 0
	local sb = if s <= 1 then "1" elseif s == 2 then "2" elseif s <= 4 then "3-4" else "5+"
	agg.sessions[sb] = (agg.sessions[sb] or 0) + 1
	local p = tonumber(d.playSeconds) or 0
	local pb = if p < 60 then "<1m" elseif p < 180 then "1-3m" elseif p < 600 then "3-10m" elseif p < 1200 then "10-20m" else "20m+"
	agg.play[pb] = (agg.play[pb] or 0) + 1
	if (d.lastSeen or 0) - (d.createdAt or 0) > 6 * 3600 then agg.returned += 1 end
	local nd = 0
	for _ in d.dragons or {} do nd += 1 end
	agg.dragons[tostring(math.min(nd, 5))] = (agg.dragons[tostring(math.min(nd, 5))] or 0) + 1
	table.insert(rows, string.format("%s c%s l%s s%d p%d %s %s %s %s", k, os.date("!%H:%M", d.createdAt or 0), os.date("!%d/%H:%M", d.lastSeen or 0), s, p, dev, src, fs, if spent > 0 or ow.vip then "PAY" .. spent else ""))
end
table.sort(rows)
agg.keysTotal = #keys; agg.seconds = math.floor(os.clock() - t0)
return { agg = agg, rows = rows }
