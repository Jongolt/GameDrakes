-- Read only: the version history of the game owner's profile in Profile_v2 (the DataStore keeps versions for 30 days) - the write time,
-- the coins, the dragons, the sessions; writes nothing. Run: python3 cloud_test.py profile_versions
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local key = "11774991821"
local from = (os.time() - 6 * 3600) * 1000
local pages = ds:ListVersionsAsync(key, Enum.SortDirection.Descending, from)
local out = {}
local n = 0
while n < 40 do
	for _, info in pages:GetCurrentPage() do
		n += 1
		local ok, v = pcall(function()
			return ds:GetVersionAsync(key, info.Version)
		end)
		local d = ok and type(v) == "table" and (v.Data or v) or nil
		local dr, coins, ses = -1, -1, -1
		if type(d) == "table" then
			dr = 0
			for _ in d.dragons or {} do
				dr += 1
			end
			coins = math.floor(d.coins or 0)
			ses = d.sessions or -1
		end
		out[#out + 1] = string.format("%s v=%s dragons=%d coins=%d sessions=%d", os.date("!%H:%M:%S", math.floor(info.CreatedTime / 1000)), string.sub(info.Version, 1, 22), dr, coins, ses)
		if n >= 40 then
			break
		end
	end
	if pages.IsFinished or n >= 40 then
		break
	end
	pages:AdvanceToNextPageAsync()
end
return out
