-- A cloud test (10 §10, 07 §1): all the pass and item numbers from ShopIds answer via GetProductInfoAsync - the price, for sale, the name.
-- Run: python3 cloud_test.py shop_products (substitutes the number table for the SHOP_IDS marker in double curly braces).
-- The result: { [key] = { ok, price, forSale, name } }.
local MarketplaceService = game:GetService("MarketplaceService")

local ids = {{SHOP_IDS}}

local out = {}
for key, rec in ids do
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfoAsync(rec.id, if rec.kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
	end)
	if ok and typeof(info) == "table" then
		out[key] = { ok = true, price = info.PriceInRobux, forSale = info.IsForSale == true, name = info.Name }
	else
		out[key] = { ok = false, err = tostring(info) }
	end
end
return out
