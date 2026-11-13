-- A cloud test: 2.4 the rewards and the egg captions in the published version - Core/Rewards counts as in the tests, the Reward service
-- and the Gifts controller are in place, the Remote Active, Config.Rewards (groupId), the captions only Meadow 28.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Rewards = require(Shared:WaitForChild("Core"):WaitForChild("Rewards"))
local Experiments = require(Shared:WaitForChild("Core"):WaitForChild("Experiments"))
local now = os.time()
local cal = { day = 0, lastDate = "", claimed = 0 }
local adv = Rewards.calendarAdvance(cal, now)
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
local sss = game:GetService("ServerScriptService"):FindFirstChild("Services", true)
return { placeVersion = game.PlaceVersion, today = Rewards.dateKey(now), picks = table.concat(Rewards.dailyPicks(Rewards.dayIndex(now), Config.Rewards), ","),
	calendarDay1 = adv and cal.day == 1, rewardService = sss ~= nil and sss:FindFirstChild("Reward") ~= nil, giftsController = ctl ~= nil and ctl:FindFirstChild("Gifts") ~= nil,
	activeRemote = Remotes.List.Active ~= nil, groupId = Config.Rewards.freeGift.groupId, meadowLabel = Config.World.eggMarks.labelDistance.Meadow,
	ab = Experiments.tag(2, Config.World.eggMarks) .. "/" .. Experiments.tag(3, Config.World.eggMarks),
	-- stage 2 (the appearance, the social layer, the weather, the badges, ascension) is in place
	services = (function()
		local out = {}
		for _, n in { "Looks", "Social", "Weather", "Badges", "Ascension" } do
			table.insert(out, n .. "=" .. tostring(sss ~= nil and sss:FindFirstChild(n) ~= nil))
		end
		for _, n in { "Looks", "Social", "Weather" } do
			table.insert(out, "c" .. n .. "=" .. tostring(ctl ~= nil and ctl:FindFirstChild(n) ~= nil))
		end
		return table.concat(out, ",")
	end)(), seasonEnds = Config.Rewards.season.endsAt, friendsMax = Config.Balance.friends.max }
