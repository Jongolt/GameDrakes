-- Read only: the profile summary of one player (the UID below) - passes/flags, sessions, time, dragons, purchases. Writes nothing.
local UID = "YOUR_PLAYER_USER_ID"
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local ok, v = pcall(function() return ds:GetAsync(UID) end)
if not ok then return { err = tostring(v) } end
local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
if type(d) ~= "table" then return { err = "no data" } end
local scalars, tables = {}, {}
for k, x in d do
	if type(x) ~= "table" then scalars[k] = x else
		local n = 0
		for _ in x do n += 1 end
		tables[k] = n
	end
end
local log = {}
for _, r in d.purchaseLog or {} do table.insert(log, string.format("%s %s %s", os.date("!%d.%m %H:%M", r.t or 0), tostring(r.sku), tostring(r.robux))) end
local dragons = {}
for _, dr in d.dragons or {} do table.insert(dragons, string.format("%s %s st%s", tostring(dr.element or dr.el), tostring(dr.rarity or dr.r), tostring(dr.stage or dr.st))) end
return { scalars = scalars, tableSizes = tables, owned = d.owned, flags = d.flags, purchaseLog = log, dragons = dragons, onboarding = d.onboarding, stats = d.stats }
