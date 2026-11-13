--!strict
-- :
-- the zone of an island point for the visit map (Services/Analytics, the profile analytics.zones). Pure logic without Roblox API.
-- The check order: flight riding and gliding (by the height above the ground) and water (swimming) - before the places; then by the coordinates from
-- Config.World: the plaza (r <= plaza.radius), the own nest and others' on the terrace (r <= terrace.radius, at its height), Summit (south, high),
-- the islets (high), Springs (west), Cliffs (north), the meadow (the ring under the terrace up to 300), the shore (up to the island edge), beyond - far.

local Zones = {}

export type Ctx = {
	flying: boolean, -- riding and high above the ground
	gliding: boolean, -- on foot and high above the ground (gliding, a fall from the ledge)
	swimming: boolean,
	ownNest: boolean, -- inside the own nest plot
}

Zones.LIST = { "plaza", "nest", "terrace", "meadow", "cliffs", "springs", "summit", "islets", "shore", "water", "sky", "glide", "far" }

function Zones.of(x: number, y: number, z: number, ctx: Ctx, W: any): string
	if ctx.flying then
		return "sky"
	end
	if ctx.gliding then
		return "glide"
	end
	if ctx.swimming then
		return "water"
	end
	local r = math.sqrt(x * x + z * z)
	local onTerrace = y >= W.terrace.y - 6
	if onTerrace and r <= W.plaza.radius + 5 then
		return "plaza"
	end
	if onTerrace and r <= W.terrace.radius + 5 then
		return if ctx.ownNest then "nest" else "terrace"
	end
	-- the mountain is wide (the base r ~104, the shoulders at 90-108 from the center of height 52-76) - otherwise the slopes go into "shore",
	-- the shoulder top - into "islets"; Summit is checked before the islets: r <= 150 from the center, from 25 to the top + 25
	local sc = W.zones.Summit.center
	if (x - sc[1]) ^ 2 + (z - sc[3]) ^ 2 <= 150 ^ 2 and y >= 25 and y <= sc[2] + 25 then
		return "summit"
	end
	if y >= W.islets.ring.yMin - 15 then
		return "islets"
	end
	if x <= -225 and z >= -120 and z <= 160 then
		return "springs"
	end
	if z <= -280 and math.abs(x) <= 220 then
		return "cliffs"
	end
	if r <= 300 then
		return "meadow"
	end
	if r <= W.islandSize / 2 + 40 then
		return "shore"
	end
	return "far"
end

-- the player's progress - hatched, placed an egg, the dragon grew, an onboarding
-- or Keeper step (and the combat stage when it appears). Coins do not count - they drip by themselves. The same meaning as the boredom ambush in combat
function Zones.progressKey(data: any): string
	local n, st = 0, 0
	for _, d in (if typeof(data.dragons) == "table" then data.dragons else {}) :: any do
		n += 1
		st += if typeof(d) == "table" then (tonumber(d.stage) or 0) else 0
	end
	-- incubating - a dictionary by slot ("1", "2"...), # is always 0 - we count by iteration; onboarding - flags and stage
	local function count(t: any): number
		local c = 0
		for _ in (if typeof(t) == "table" then t else {}) :: any do
			c += 1
		end
		return c
	end
	local eggs = if typeof(data.eggs) == "table" then data.eggs else {}
	local inc = count(eggs.incubating)
	local shelf = count(eggs.shelf)
	local onb = if typeof(data.onboarding) == "table" then data.onboarding else {}
	local ob = 0
	for _, v in onb :: any do
		if v == true then
			ob += 1
		end
	end
	local q = if typeof(data.quests) == "table" and typeof(data.quests.keeper) == "table" then data.quests.keeper.step else 0
	local cb = if typeof(data.combat) == "table" then tonumber(data.combat.stage) or 0 else 0
	return string.format("%d|%d|%d|%d|%d|%s|%s|%d", n, st, inc, shelf, ob, tostring(onb.stage), tostring(q), cb)
end

-- one mark in the profile: seconds in the zone (s), of them without progress longer than the boredom threshold (b), the play time (playSeconds) of the first
-- visit (f), the last zone (at the leave - where he left), idle - seconds without progress at the last mark (at the leave - the boredom before leaving)
function Zones.record(z: any, zone: string, seconds: number, playSeconds: number, bored: boolean?, idle: number?): any
	z = if typeof(z) == "table" then z else {}
	z.s = if typeof(z.s) == "table" then z.s else {}
	z.f = if typeof(z.f) == "table" then z.f else {}
	z.b = if typeof(z.b) == "table" then z.b else {}
	z.s[zone] = (tonumber(z.s[zone]) or 0) + seconds
	if bored then
		z.b[zone] = (tonumber(z.b[zone]) or 0) + seconds
	end
	if z.f[zone] == nil then
		z.f[zone] = playSeconds
	end
	z.last = zone
	z.lastAt = playSeconds
	z.idle = math.floor(idle or 0)
	return z
end

return Zones
