-- Read only: the game owner's purchase journal in the live store - what was bought, how many Robux Roblox charged by the receipt
-- (receipt.CurrencySpent, the robux field in purchaseLog). GetAsync does not take the session and writes nothing. Run: python3 cloud_test.py owner_purchases_read
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
local out = {}
for _, r in d.purchaseLog or {} do
	table.insert(out, string.format("%s UTC %s robux=%s giftTo=%s dup=%s", os.date("!%d.%m %H:%M:%S", r.t or 0), tostring(r.sku), tostring(r.robux), tostring(r.giftTo), tostring(r.duplicate)))
end
local n = 0
for _ in d.purchases or {} do
	n += 1
end
return { log = out, receipts = n, items = d.items, lastSeenAgo = os.time() - (d.lastSeen or 0) }
