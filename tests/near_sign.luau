-- which decor items stand at the Springs sign (-196, 30)
local Layout = require("../src/shared/Core/Layout")
local DecorLayout = require("../src/shared/Core/DecorLayout")
local items = DecorLayout.items()
for _, it in items do
	local d = math.sqrt((it.x + 196) ^ 2 + (it.z - 30) ^ 2)
	if d < 14 then
		print(string.format("%s at %.1f,%.1f h=%.1f d=%.1f collide=%s", it.kind, it.x, it.z, it.h, d, tostring(it.collide)))
	end
end
