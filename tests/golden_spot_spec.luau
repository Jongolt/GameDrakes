--!strict
-- the golden nest spot choice
-- (Services/GlowEgg.slopeSpot) offline for all 6 plots - the terrain Island.height + Layout.hills, the decor DecorLayout (the crown ~ height/3,
-- the rocks by height), the Zones zone; in the world the part check (clearR) is added to this. Run: luau tests/golden_spot_spec.luau
local Config = require("../src/shared/Config")
local Layout = require("../src/shared/Core/Layout")
local Island = require("../src/shared/Core/Island")
local DecorLayout = require("../src/shared/Core/DecorLayout")
local Zones = require("../src/shared/Core/Zones")

local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then " | " .. tostring(detail) else ""))
	end
end

local GE = Config.Glow.egg
local SP, SL = GE.spot, GE.spot.slope
local H = (Config.World :: any).decor.height
local hills = Layout.hills()
local obs = {}
for _, it in DecorLayout.items() do
	if not string.find(it.kind, "^under_") and not it.sea then
		local hr = H[it.kind]
		local h = if hr then (hr[1] + hr[2]) / 2 * (it.h or 1) else 4
		if h > 3 then
			table.insert(obs, { x = it.x, z = it.z, r = math.min(h / 3, 14) })
		end
	end
end
local function clearance(x: number, z: number): number
	local best = math.huge
	for _, o in obs do
		best = math.min(best, math.sqrt((o.x - x) ^ 2 + (o.z - z) ^ 2) - o.r)
	end
	return best
end
local function ground(x: number, z: number): number
	return (Island.height(hills, x, z))
end
local eggPts = Layout.eggPoints()
local function pick(np: any, flatMax: number, decorGap: number): any
	local la = math.atan2(np.center[3], np.center[1])
	local best, bs = nil :: any, math.huge
	for _, da in SL.arcs do
		for _, rr in SL.radii do
			local a = la + math.rad(da)
			local x, z = math.cos(a) * rr, math.sin(a) * rr
			local ok = true
			for _, e in eggPts do
				if math.sqrt((x - e.pos[1]) ^ 2 + (z - e.pos[3]) ^ 2) < SP.eggGap then
					ok = false
				end
			end
			local clr = clearance(x, z)
			if ok and clr >= decorGap then
				local y = ground(x, z)
				local lo, hi = y, y
				for k = 0, 7 do
					local b = k / 8 * math.pi * 2
					local hh = ground(x + math.cos(b) * SP.flatR, z + math.sin(b) * SP.flatR)
					lo, hi = math.min(lo, hh), math.max(hi, hh)
				end
				local dh = hi - lo
				local zone = Zones.of(x, y, z, { flying = false, gliding = false, swimming = false, ownNest = false }, Config.World)
				if dh <= flatMax and zone == "meadow" then
					local score = dh * 10 + math.abs(da) / 15 - math.min(clr, 24) / 3
					if score < bs then
						bs, best = score, { r = rr, da = da, clr = clr, dh = dh, x = x, z = z }
					end
				end
			end
		end
	end
	return best
end
for _, np in Layout.nestPivots() do
	local best = pick(np, SL.flatMax, SL.decorGap)
	local pass = "strict"
	if not best then -- as in GlowEgg: the second pass is softer
		best, pass = pick(np, SL.relax.flatMax, SL.relax.decorGap), "soft"
	end
	if best then
		print(string.format("plot %d (%s): r=%d angle %+d, to the decor %.0f, drop %.1f, point %.0f,%.0f", np.index, pass, best.r, best.da, best.clr, best.dh, best.x, best.z))
	end
	check("plot " .. np.index .. ": there is a spot beyond the firs (r >= 244, decor >= decorGap of the soft pass, flat, meadow, <= 60 deg)",
		best ~= nil and best.r >= 244 and best.clr >= SL.relax.decorGap and math.abs(best.da) <= 60)
end
print(string.format("golden_spot_spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("golden_spot_spec failed")
end
