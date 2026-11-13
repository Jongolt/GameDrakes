-- A WRITE (one-off): restores the game owner's profile -> the Data of the
-- DataStore version with 460,332 coins. The ProfileStore MetaData stays current; the owner is in the game
-- (MetaData.ActiveSession) - the write is cancelled. The check before the write - profile_restore_dry.luau.
local WANT_COINS = 460332
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local key = "11774991821"
local pages = ds:ListVersionsAsync(key, Enum.SortDirection.Descending, (os.time() - 8 * 3600) * 1000)
local old = nil
for _, info in pages:GetCurrentPage() do
	local v = ds:GetVersionAsync(key, info.Version)
	if type(v) == "table" and type(v.Data) == "table" and math.floor(v.Data.coins or 0) == WANT_COINS then
		old = v.Data
		break
	end
end
if not old then
	return { err = "the version with coins " .. WANT_COINS .. " not found" }
end
local _, info = ds:GetAsync(key)
local userIds = if info then info:GetUserIds() else { tonumber(key) }
local result = "not_written"
ds:UpdateAsync(key, function(now: any)
	if type(now) ~= "table" or type(now.MetaData) ~= "table" then
		result = "bad_current"
		return nil
	end
	if now.MetaData.ActiveSession ~= nil then
		result = "owner_in_game"
		return nil
	end
	now.Data = old
	now.MetaData.LastUpdate = os.time()
	result = "written"
	return now, userIds
end)
local after = ds:GetAsync(key)
local d = type(after) == "table" and after.Data or {}
local n = 0
for _ in d.dragons or {} do
	n += 1
end
return { result = result, afterCoins = math.floor(d.coins or 0), afterDragons = n, afterCompanion = d.companion }
