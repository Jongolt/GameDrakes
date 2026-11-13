-- Read only: the firstborn growth test groups (A 2/6 min / B 3/9 min) against the funnel: mounted, flew, play time. Writes nothing.
local SINCE, LIMIT_S = 1792785600, 210
local DSS = game:GetService("DataStoreService"); local ds = DSS:GetDataStore("Profile_v2"); local t0 = os.clock()
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
local G = {}
local function grp(g) G[g] = G[g] or { n = 0, hatched = 0, rode = 0, flew = 0, play = {}, ride10 = 0, stage2 = 0 } return G[g] end
local sampleKeys = {}
for i, k in keys do
	if os.clock() - t0 > LIMIT_S then break end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) < 3 do task.wait(1) end
	local okg, v = pcall(function() return ds:GetAsync(k) end)
	if not okg then continue end
	local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
	if type(d) ~= "table" or (d.createdAt or 0) < SINCE then continue end
	local g = "none"
	for _, dr in d.dragons or {} do
		if dr.growGroup then g = tostring(dr.growGroup) break end
	end
	if g == "none" and d.growGroup then g = tostring(d.growGroup) end
	if #sampleKeys < 3 and g == "none" and d.dragons and next(d.dragons) then
		local _, dr = next(d.dragons); local ks = {}
		for kk in dr do table.insert(ks, kk) end
		table.insert(sampleKeys, table.concat(ks, ","))
	end
	local r = grp(g); r.n += 1
	local ob = d.onboarding or {}
	if ob.firstHatch then r.hatched += 1 end
	if ob.rode then r.rode += 1 end
	if ob.flew then r.flew += 1 end
	table.insert(r.play, tonumber(d.playSeconds) or 0)
	if (tonumber(d.playSeconds) or 0) >= 600 then r.ride10 += 1 end
	for _, dr in d.dragons or {} do if (dr.stage or 0) >= 2 then r.stage2 += 1 break end end
end
for g, r in G do
	table.sort(r.play); r.playMedian = r.play[math.max(1, math.floor(#r.play / 2))]; r.play = nil
end
return { groups = G, dragonFields = sampleKeys, seconds = math.floor(os.clock() - t0) }
