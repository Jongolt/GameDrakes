-- Prints Config.Lighting as a flat key=value list for build.py (one source of the light numbers).
local Config = require("../src/shared/Config")
local function dump(prefix: string, t: { [string]: any })
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	for _, k in keys do
		local v = t[k]
		if type(v) == "table" then
			if #v == 3 and type(v[1]) == "number" then
				print(prefix .. k .. "=" .. v[1] .. "," .. v[2] .. "," .. v[3])
			else
				dump(prefix .. k .. ".", v)
			end
		else
			print(prefix .. k .. "=" .. tostring(v))
		end
	end
end
dump("", Config.Lighting)
