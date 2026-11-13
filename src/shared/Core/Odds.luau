--!strict
-- "1 in N" (03 §3): N = 1 / (P(the rarity in the zone) x P(the variants)). The element is not part of N. Pure logic.

local Eggs = require("./Eggs")
local Format = require("./Format")

local Odds = {}

function Odds.rarityP(zone: string, rarity: string, rareNest: boolean, B: any): number
	local t = Eggs.rarityTable(zone, rareNest, B)
	local sum, w = 0, 0
	for _, o in t do
		sum += o.weight
		if o.id == rarity then
			w = o.weight
		end
	end
	return if sum > 0 then w / sum else 0
end

-- The probability of the egg's variant set (shiny independently; the size - one roll)
function Odds.variantP(egg: { shiny: boolean?, size: string? }, B: any): number
	local p = 1
	if egg.shiny then
		p *= B.variants.shiny.p
	end
	if egg.size == "huge" then
		p *= B.variants.huge.p
	elseif egg.size == "big" then
		p *= B.variants.big.p
	end
	return p
end

function Odds.outcomeP(egg: { zone: string, rarity: string, rareNest: boolean?, shiny: boolean?, size: string? }, B: any): number
	return Odds.rarityP(egg.zone, egg.rarity, egg.rareNest == true, B) * Odds.variantP(egg, B)
end

function Odds.oneIn(egg: { zone: string, rarity: string, rareNest: boolean?, shiny: boolean?, size: string? }, B: any): string
	return Format.oneIn(Odds.outcomeP(egg, B))
end

-- The zone odds for the shield at the entrance: { {rarity, percent} ... }
function Odds.zoneBoard(zone: string, B: any): { { string | number } }
	local out = {}
	for _, o in Eggs.rarityTable(zone, false, B) do
		if o.weight > 0 then
			table.insert(out, { o.id, o.weight })
		end
	end
	return out
end

return Odds
