-- A cloud test: the data fingerprint of the published version - a hash of every section of Config, Strings, Content (a sorted traversal
-- of the tables). The same code without Roblox (tests/fingerprint_local.luau) gives the repo fingerprint - the sections with a different hash differ; read only


local function ser(v: any, out: { string }, depth: number)
	local t = typeof(v)
	if t == "table" and depth < 12 then
		local keys = {}
		for k in v do table.insert(keys, tostring(k)) end
		table.sort(keys)
		for _, k in keys do
			local val = v[k]
			if val == nil then val = v[tonumber(k)] end
			table.insert(out, k .. "=")
			ser(val, out, depth + 1)
			table.insert(out, ";")
		end
	elseif t == "number" then
		table.insert(out, string.format("%.6g", v))
	elseif t == "EnumItem" or t == "Color3" or t == "Vector3" then
		table.insert(out, tostring(v))
	else
		table.insert(out, tostring(v))
	end
end
local function hash(s: string): string
	local h = 5381
	for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
	return string.format("%08x", h)
end
local res = {}
for _, name in { "Config", "Strings", "Content" } do
	local m = (if name == "Config" then require("../src/shared/Config") elseif name == "Strings" then require("../src/shared/Strings") else require("../src/shared/Content")) :: any
	local keys = {}
	for k in m do table.insert(keys, tostring(k)) end
	table.sort(keys)
	for _, k in keys do
		local out = {}
		ser(m[k], out, 0)
		table.insert(res, name .. "." .. k .. ":" .. hash(table.concat(out)))
	end
end
print(table.concat(res, " "))
