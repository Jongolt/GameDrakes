--!strict
-- 2.8: badges (spec 06 §5). The ids are in Content.Badges
-- id = 0 - no badge yet, the award is silently skipped. The award BadgeService:AwardBadgeAsync in pcall, once per session per key
-- (a repeated award is harmless - Roblox does not give a second one, but the call is not wasted), a mark in the profile badges[key] = os.time().
-- Events: from Quest.event (hatch, glide, ride, fly, ascension, elder), Social (party), Index (index25), Incubation (ancient).

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared:WaitForChild("Content"))

local Badges = {}

local services: { [string]: any } = {}
local sent: { [Player]: { [string]: boolean } } = {}
local failedAt: { [Player]: { [string]: number } } = {} -- an API failure - a retry no sooner than RETRY s (Glider/Sky Rider call award every flight tick)
local RETRY = 60

-- a Quest.event event -> a badge key (06 §5)
local FROM_EVENT: { [string]: string } = { hatch = "hatch", glide = "glide", ride = "rider", fly = "flyer", ascension = "ascend", elder = "elder" }

function Badges.award(player: Player, key: string)
	local def = (Content.Badges :: any)[key]
	if not def or (def.id or 0) == 0 then
		return
	end
	local s = sent[player]
	if not s then
		s = {}
		sent[player] = s
	end
	local data = services.PlayerData.get(player)
	if s[key] or (data and typeof(data.badges) == "table" and data.badges[key]) then
		return
	end
	local f = failedAt[player]
	if f and f[key] and os.clock() - f[key] < RETRY then
		return
	end
	s[key] = true
	task.spawn(function()
		local ok, res = pcall(function()
			return BadgeService:AwardBadgeAsync(player.UserId, def.id)
		end)
		if ok and res then
			services.PlayerData.update(player, "badges", function(b)
				b = if typeof(b) == "table" then b else {}
				b[key] = os.time()
				return b
			end)
			if services.Analytics then
				services.Analytics.custom(player, "badge", 1, { key = key })
			end
		elseif not ok then
			s[key] = nil -- an API failure: try on the next event, but no sooner than RETRY s
			failedAt[player] = failedAt[player] or {}
			failedAt[player][key] = os.clock()
		end
	end)
end

-- from Quest.event: the quest event name
function Badges.event(player: Player, name: string)
	local key = FROM_EVENT[name]
	if key then
		Badges.award(player, key)
	end
end

function Badges.init(s: { [string]: any })
	services = s
	game:GetService("Players").PlayerRemoving:Connect(function(p)
		sent[p] = nil
		failedAt[p] = nil
	end)
end

return Badges
