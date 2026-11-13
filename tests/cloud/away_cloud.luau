-- A cloud test: 2.5 "while you were away" in the published version - Core/Offline is in place and counts as in the tests
-- Claim accepts "away", the Away controller is in the list, the card lines.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Offline = require(Shared:WaitForChild("Core"):WaitForChild("Offline"))
local now = os.time()
local data = { dragons = { d1 = { rarity = "Common", stage = 0, name = "Moss", stageEndsAt = now - 10 } }, nestOrder = { "d1" }, eggs = { incubating = { ["1"] = { endsAt = now - 5 } } } }
local s = Offline.summary(data, now - 3600, now, { ascension = 0 }, Config.Balance)
local claimKinds = table.concat(Remotes.List.Claim.args[1].values, ",")
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
return { placeVersion = game.PlaceVersion, coins = s and s.coins, eggs = s and s.eggs, grew = s and #s.grew, claimKinds = claimKinds,
	awayController = ctl ~= nil and ctl:FindFirstChild("Away") ~= nil, title = Strings.Rewards.awayTitle, offline = Config.Balance.offline.share,
	wallTop = Config.World.terraceTerrain.wallTop }
