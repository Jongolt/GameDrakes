--!strict
-- A/B experiments: the group is derived from the UserId and is the same on the server (the Analytics slice) and on the client
-- (what to draw). Without storing in the profile - the player cannot change the group by rejoining.

local Experiments = {}

-- the captions above the Meadow eggs: an odd UserId - with a caption, an even one - without; abByUserId = false - a caption for everyone
function Experiments.eggLabels(userId: number, cfg: { abByUserId: boolean }): boolean
	if not cfg.abByUserId then
		return true
	end
	return userId % 2 ~= 0
end

-- the value for the Analytics slice (Analytics.fields): "on" | "off"
function Experiments.tag(userId: number, cfg: { abByUserId: boolean }): string
	return if Experiments.eggLabels(userId, cfg) then "on" else "off"
end

-- the firstborn growth group (Config.Balance.firstDragon.ab): "B" (3/9 min) - the second bit of the UserId = 1 and the test
-- is running (now >= from); otherwise "A" (2/6). The second bit, not the parity: the parity already splits the egg captions, the experiment groups do not coincide
function Experiments.growGroup(userId: number, cfg: { on: boolean, from: number, force: string? }?, now: number): string
	if not cfg or not cfg.on then
		return "A"
	end
	if cfg.force then
		return cfg.force
	end
	if now < cfg.from then
		return "A"
	end
	return if math.floor(userId / 2) % 2 == 1 then "B" else "A"
end

-- the calendar day 2 gift - "B" a Rare dragon, "A" a Cliffs egg (as before).
-- The third bit of the UserId - does not coincide with the egg captions (the parity) and the growth groups (the second bit). force - one group for everyone.
function Experiments.d2Group(userId: number, cfg: { on: boolean, force: string? }?): string
	if not cfg or not cfg.on then
		return "A"
	end
	if cfg.force then
		return cfg.force
	end
	return if math.floor(userId / 4) % 2 == 1 then "B" else "A"
end

-- the element of the day 2 dragon: from the UserId (the bits above the groups) - the same in the "tomorrow" banner, in the notification and in the reward
function Experiments.d2Element(userId: number, elements: { string }): string
	return elements[math.floor(userId / 8) % #elements + 1]
end

return Experiments
