-- Island 2.0 probe (C2): decor counters, sea pillar positions, shore radii, the height function timing.
-- luau tests/probe_island.luau
local Config = require("../src/shared/Config")
local Island = require("../src/shared/Core/Island")
local Layout = require("../src/shared/Core/Layout")
local DecorLayout = require("../src/shared/Core/DecorLayout")
local items = DecorLayout.items()
local granite, sea, stacks = 0, 0, {}
for _, it in items do
	if it.granite then granite += 1 end
	if it.sea then sea += 1 end
	if it.sea and it.granite and it.y and it.y < -10 then
		table.insert(stacks, { math.floor(it.x), math.floor(it.z) })
	end
end
print("items", #items, "granite", granite, "sea", sea, "stacks(base rocks)", #stacks)
for i, s in stacks do print("stack", i, s[1], s[2]) end
for _, deg in { 0, 20, 45, 90, 135, 180, 225, 270, 315 } do
	print("coast", deg, math.floor(Island.coastRadius(math.rad(deg))))
end
local hills = Layout.hills()
print("hills", #hills)
local t0 = os.clock()
local n = 0
for _, ch in Island.chunks() do
	for ix = 1, 24 do for iz = 1, 24 do
		local h = Island.height(hills, ch.x1 + ix * 4 - 2, ch.z1 + iz * 4 - 2)
		n += 1
	end end
end
print("height calls", n, "sec", os.clock() - t0)
