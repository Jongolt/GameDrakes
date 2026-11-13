-- Read only: the game owner's nest look in the live profile - the skin choice, the Ascension step, the ownership flags.
-- GetAsync does not take the session and writes nothing. Run: python3 cloud_test.py owner_looks_read
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
local owned = {}
for k, x in (type(d.owned) == "table" and d.owned or {}) :: { [string]: any } do
	if type(x) == "table" then
		local ids = {}
		for id, on in x do
			if on == true then
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		owned[k] = table.concat(ids, ",")
	else
		owned[k] = tostring(x)
	end
end
return { looks = d.looks, ascension = d.ascension, owned = owned, sessions = d.sessions, lastSeenAgo = os.time() - (d.lastSeen or 0),
	inGame = type(v) == "table" and type(v.MetaData) == "table" and v.MetaData.ActiveSession ~= nil }
