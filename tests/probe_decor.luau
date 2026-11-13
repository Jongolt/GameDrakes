local DecorLayout = require("../src/shared/Core/DecorLayout")
local items = DecorLayout.items()
local counts = {}
for _, it in items do counts[it.kind] = (counts[it.kind] or 0) + 1 end
local keys = {} for k in counts do table.insert(keys, k) end table.sort(keys)
for _, k in keys do print(k, counts[k]) end
print("total", #items, "kinds", #keys, "leafy", #DecorLayout.leafyPatches())
