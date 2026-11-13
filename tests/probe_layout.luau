-- a one-off probe of the polish layout (not a test): luau tests/probe_layout.luau
local Layout = require("../src/shared/Core/Layout")
local hills = Layout.hills()
print("hills", #hills)
for _, h in hills do print(string.format("  (%.0f, %.0f) r %.0f h %.1f", h.x, h.z, h.r, h.h)) end
for _, p in Layout.paths() do print(string.format("path %s from (%.0f,%.0f) to (%.0f,%.0f) len %.0f", p.zone, p.from[1], p.from[3], p.to[1], p.to[3], p.length)) end
local rocks = Layout.edgeRocks()
print("edge rocks", #rocks)
local rs = {}
for _, r in rocks do table.insert(rs, string.format("%.0f@%.0f", r.angleDeg, math.sqrt(r.x^2+r.z^2))) end
print(table.concat(rs, " "))
print("coins", #Layout.coins())
print("ground at hill1 center / origin:", Layout.groundHeight(hills, hills[1].x, hills[1].z), Layout.groundHeight(hills, 0, 0))
