-- Read only: the game owner's profile in the live store - how many dragons, the elements, the companion. GetAsync does not take the session and
-- writes nothing. Run: python3 cloud_test.py owner_profile_read
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local ok, v = pcall(function()
	return ds:GetAsync("11774991821")
end)
if not ok then
	return { err = tostring(v) }
end
local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
if type(d) ~= "table" then
	return { err = "no data", t = typeof(v) }
end
local dragons = {}
for u, x in d.dragons or {} do
	table.insert(dragons, string.format("%s %s %s %s s%d", u, tostring(x.name), tostring(x.rarity), tostring(x.element), x.stage or -1))
end
return { companion = d.companion, nestOrder = d.nestOrder, sessions = d.sessions, lastSeenAgo = os.time() - (d.lastSeen or 0), coins = math.floor(d.coins or 0), dragons = dragons }
