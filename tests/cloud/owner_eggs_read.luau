-- Read only: the game owner's eggs in the live store - the shelf, the incubators (the remainder), in the hands; the number of incubators and shelf slots.
-- GetAsync does not take the session and writes nothing. Run: python3 cloud_test.py owner_eggs_read
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local v = ds:GetAsync("11774991821")
local d = type(v) == "table" and v.Data or {}
local now = os.time()
local e = type(d.eggs) == "table" and d.eggs or {}
local function egg(x)
	if type(x) ~= "table" then
		return tostring(x)
	end
	return string.format("%s %s %s zone=%s id=%s", tostring(x.element), tostring(x.rarity), x.shiny and "shiny" or "", tostring(x.zone), tostring(x.id))
end
local shelf = {}
for i, x in e.shelf or {} do
	shelf[i] = egg(x)
end
local inc = {}
for k, r in e.incubating or {} do
	inc[tostring(k)] = egg(r.egg) .. " left=" .. tostring((r.endsAt or 0) - now) .. "s"
end
return { incubators = d.incubators, shelfCap = d.shelfCap, carry = egg(e.carry), shelf = shelf, incubating = inc, sessions = d.sessions }
