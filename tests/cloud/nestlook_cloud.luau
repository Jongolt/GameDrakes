-- the nest look in the published version - the modules are in place and the palette is new.
-- Run: python3 cloud_test.py nestlook_cloud
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Looks = require(Shared.Core.Looks)
local Config = require(Shared.Config)
local Strings = require(Shared.Strings)
local L = Config.Looks
local d = { ascension = 6, owned = { vip = true }, looks = { nestSkin = "classic" } }
local skin, tint = Looks.nestLook(d, L)
local out = {
	hasNestLook = typeof(Looks.nestLook) == "function",
	ascendedConst = Looks.ASCENDED,
	classicPlain = skin == nil and tint == nil,
	gildedFence = table.concat(L.nestSkins.gilded.colors.fence, ","),
	gildedMat = L.nestSkins.gilded.materials.fence,
	bowlRole = Looks.nestRole("Bowl", "Bowl"),
	bowlInRoles = table.find(L.nestRoles, "bowl") ~= nil,
	ascendedName = Strings.Looks.skins.ascended,
	toast = Strings.Looks.skinSet,
	lagoonLine = Strings.Shop.lines.NestSkin_Lagoon_299,
}
d.looks.nestSkin = "ascended"
local s2, t2 = Looks.nestLook(d, L)
out.ascendedTint = (s2 == nil and t2 == 6)
d.looks.nestSkin = "gilded"
out.gildedChosen = (Looks.nestLook(d, L)) == "gilded"
return out
