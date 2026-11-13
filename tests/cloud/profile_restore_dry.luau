-- Read only: what the restore of the game owner's profile would return - the DataStore version with
-- 460,332 coins, its dragons; the current state and whether the owner is in the game. Writes nothing.
local WANT_COINS = 460332
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local key = "11774991821"
local pages = ds:ListVersionsAsync(key, Enum.SortDirection.Descending, (os.time() - 8 * 3600) * 1000)
local pick, pickTime = nil, 0
for _, info in pages:GetCurrentPage() do
	local v = ds:GetVersionAsync(key, info.Version)
	if type(v) == "table" and type(v.Data) == "table" and math.floor(v.Data.coins or 0) == WANT_COINS then
		pick, pickTime = v, info.CreatedTime
		break
	end
end
if not pick then
	return { err = "the version with coins " .. WANT_COINS .. " not found" }
end
local old = pick.Data
local dr = {}
for u, x in old.dragons or {} do
	table.insert(dr, string.format("%s %s %s %s s%d", u, tostring(x.name), tostring(x.rarity), tostring(x.element), x.stage or -1))
end
local cur = ds:GetAsync(key)
local sess = type(cur) == "table" and type(cur.MetaData) == "table" and cur.MetaData.ActiveSession
return {
	versionTime = os.date("!%H:%M:%S", math.floor(pickTime / 1000)), oldCoins = math.floor(old.coins or 0), oldSessions = old.sessions,
	oldDragons = dr, oldCompanion = old.companion, curCoins = type(cur) == "table" and type(cur.Data) == "table" and cur.Data.coins or "?",
	ownerInGame = sess ~= nil,
}
