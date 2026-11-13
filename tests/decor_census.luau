local DecorLayout = require("../src/shared/Core/DecorLayout")
local by = {}
local total = 0
for _, it in DecorLayout.items() do
	total += 1
	local b = by[it.kind] or { n = 0, hmin = 1e9, hmax = 0 }
	b.n += 1
	b.hmin = math.min(b.hmin, it.h or 0)
	b.hmax = math.max(b.hmax, it.h or 0)
	by[it.kind] = b
end
local rows = {}
for k, b in by do table.insert(rows, { k, b }) end
table.sort(rows, function(a, c) return a[2].n > c[2].n end)
print("items", total)
for _, r in rows do print(string.format("%-22s n=%4d h=%.1f-%.1f", r[1], r[2].n, r[2].hmin, r[2].hmax)) end
