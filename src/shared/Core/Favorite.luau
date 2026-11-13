--!strict
-- when to show the Roblox "favorite" window (AvatarEditorService:PromptSetFavorite).
-- Once per account lifetime, after the first flight, when the player got off the dragon and cfg.delay s passed. Without a reward: the Roblox rule
-- forbids a reward for a like/favorite, asking is allowed (DevForum 2926286). A pure function - tests/favorite_spec.luau.

local Favorite = {}

-- onboarding - the player's data (flew, favAsked); mounted - riding now; landedAt - when he got off (os.clock), nil - did not get off this session;
-- glowSeenAt - when a glowing dragon hatched on the client (os.clock), nil - not yet.
-- cfg.moment = "glow" - once per account lifetime, cfg.delay s after the glowing dragon hatches (day 2), not riding; "flight" - the previous rule
function Favorite.due(onboarding: any, mounted: boolean, landedAt: number?, now: number, cfg: any, glowSeenAt: number?): boolean
	if typeof(cfg) ~= "table" or cfg.on ~= true then
		return false
	end
	if typeof(onboarding) ~= "table" or onboarding.favAsked ~= nil then
		return false
	end
	if mounted then
		return false
	end
	if cfg.moment == "glow" then
		if glowSeenAt == nil then
			return false
		end
		return now - glowSeenAt >= (cfg.delay or 0)
	end
	if onboarding.flew ~= true or landedAt == nil then
		return false
	end
	return now - landedAt >= (cfg.delay or 0)
end

return Favorite
