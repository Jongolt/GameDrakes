-- A cloud test: the night package in the published version - the name, 24 portraits, 49 item images, the nest slots from
-- the middle, the coin purchase prices, the night lighter, the chest caption up close.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Strings = require(Shared:WaitForChild("Strings"))
local Economy = require(Shared:WaitForChild("Core"):WaitForChild("Economy"))
local icons = require(Shared:WaitForChild("ShopIcons"))
local n, p = 0, 0
for _ in icons do
	n += 1
end
for _, list in Content.Assets.portraits do
	for _, id in list do
		if id > 0 then
			p += 1
		end
	end
end
local night
for _, ph in Config.World.dayCycle.phases do
	if ph.id == "night" then
		night = ph.brightness
	end
end
local B = Config.Balance
return { placeVersion = game.PlaceVersion, name = Strings.GameName, portraits = p, shopIcons = n, firstSlotZ = Config.World.nestLayout.slots[1][3],
	prices = string.format("inc2=%s slot4=%s shelf=%s", tostring(Economy.incubatorPrice(1, B)), tostring(Economy.slotPrice(3, B)), tostring(Economy.shelfPrice(3, B))),
	nightBrightness = night, chestLabel = Config.Rewards.chest.labelDistance, buyRemote = require(Shared:WaitForChild("Remotes")).List.Buy ~= nil }
