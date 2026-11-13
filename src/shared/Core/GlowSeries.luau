--!strict
-- golden eggs as a series -
-- one per element in the order Config.Glow.egg.series (Ember first - as it was in live). data.glowEgg.n - the number of the current egg of the series
-- (none - 1: old profiles with Ember). The next golden nest - when the previous egg hatched (hatched) and the glowing egg is no longer
-- in the hands or in a bowl. Pure logic without Roblox API (tests/glowegg_spec.luau), the service - Services/GlowEgg.

local GlowSeries = {}

-- the number of the current egg of the series (1..#series)
function GlowSeries.index(ge: any): number
	local n = if typeof(ge) == "table" then tonumber(ge.n) else nil
	if not n or n < 1 then
		return 1
	end
	return math.floor(n)
end

-- the element of the current egg: series[n], without a series or past its end - GE.element
function GlowSeries.element(ge: any, GE: any): string
	local s = GE and GE.series
	if typeof(s) == "table" and #s > 0 then
		local e = s[GlowSeries.index(ge)]
		if typeof(e) == "string" then
			return e
		end
	end
	return GE.element
end

-- the glowing egg is still in the game: in the hands or in a bowl (the hatch is not finished) - the next nest waits
function GlowSeries.glowBusy(eggs: any): boolean
	if typeof(eggs) ~= "table" then
		return false
	end
	if typeof(eggs.carry) == "table" and eggs.carry.glow == true then
		return true
	end
	if typeof(eggs.incubating) == "table" then
		for _, rec in eggs.incubating do
			if typeof(rec) == "table" and typeof(rec.egg) == "table" and rec.egg.glow == true then
				return true
			end
		end
	end
	return false
end

-- the next state of data.glowEgg after the hatch: a new egg of the series { taken = 0, n = n + 1 } or nil (too early / the series is over)
function GlowSeries.advance(ge: any, eggs: any, GE: any): any?
	if typeof(ge) ~= "table" or ge.hatched ~= true then
		return nil
	end
	local s = GE and GE.series
	local n = GlowSeries.index(ge)
	if typeof(s) ~= "table" or n >= #s then
		return nil
	end
	if GlowSeries.glowBusy(eggs) then
		return nil
	end
	return { taken = 0, n = n + 1 }
end

return GlowSeries
