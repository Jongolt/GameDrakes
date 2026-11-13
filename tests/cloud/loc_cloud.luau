-- the localization in the published version - the Loc module and LocaleData (our es/pt/de/fr), there is no table in the place
-- (the static labels - the game's cloud table). Luau Execution does NOT load the cloud table (verified: even es without
-- the place table = English) - machine translation cannot be checked here, only on a player. Read only.
local RS = game:GetService("ReplicatedStorage")
local LS = game:GetService("LocalizationService")
local Shared = RS:WaitForChild("Shared")
local Loc = require(Shared:WaitForChild("Loc"))
local D = require(Shared:WaitForChild("LocaleData"))
local Strings = require(Shared:WaitForChild("Strings"))
local Content = require(Shared:WaitForChild("Content"))
local out = { placeTable = LS:FindFirstChild("GameStrings") ~= nil, es = 0 }
for _ in D.es do
	out.es += 1
end
Loc.setLang("es")
out.esFeed = Loc.t(Strings.Hints.feed)
out.esShop = Loc.t(Strings.HUD.shop) -- a standard word: not ours (there is no cloud in Luau Execution - English)
out.esNeeds = Loc.fill(Strings.Errors.not_enough, { n = 37 })
out.esEmber = Loc.fill(Strings.Social.hatchAnnounce, { name = "Zap", rarity = Loc.text(Strings.Rarity.Rare), element = Content.Elements.ember.name })
Loc.setLang("de")
out.deFeed = Loc.t(Strings.Hints.feed)
Loc.setLang(nil)
-- es: ~569 lines (the standard words and the untranslatable are outside D.es)
out.ok = not out.placeTable and out.es >= 560 and out.esFeed == "Alimentar" and out.esShop == "Shop" and out.esNeeds == "Faltan 37 monedas" and out.esEmber == "¡Zap eclosionó un Ember Raro!"
return out
