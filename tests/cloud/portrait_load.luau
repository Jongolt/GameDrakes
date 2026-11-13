-- A cloud test: whether the portrait images load on the live server
-- (PreloadAsync), for comparison - the item images (visible on the phone) and the bowl mesh.
local RS = game:GetService("ReplicatedStorage")
local CP = game:GetService("ContentProvider")
local Content = require(RS:WaitForChild("Shared"):WaitForChild("Content"))
local icons = require(RS:WaitForChild("Shared"):WaitForChild("ShopIcons"))
local out = {}
local function try(label: string, id: number)
	local status = "?"
	local img = Instance.new("ImageLabel")
	img.Image = "rbxassetid://" .. tostring(id)
	pcall(function()
		CP:PreloadAsync({ img }, function(_, st)
			status = st.Name
		end)
	end)
	table.insert(out, label .. "=" .. status)
end
try("ember1", Content.Assets.portraits.ember[1])
try("storm4", Content.Assets.portraits.storm[4])
try("moss3", Content.Assets.portraits.moss[3])
try("shop_auto", icons.AutoCollect_149)
return table.concat(out, " ")
