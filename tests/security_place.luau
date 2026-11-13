-- place file security (Lune). Run from the repository root:
-- lune run tests/security_place.luau build/place.rbxlx
-- Checks: LoadStringEnabled is off (backdoors execute code from a string), HttpEnabled is off; scripts only in our folders
-- (ServerScriptService, ReplicatedStorage.Shared, ReplicatedFirst, StarterPlayer), no scripts in Workspace; the sources have no
-- require(number) (a foreign module by id), getfenv / setfenv / loadstring, outbound HTTP requests; InsertService only in the known
-- services (ModelLibrary, WorldBuilder, Decor).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local path = process.args[1] or "roblox_game/build/place.rbxlx"
local game = roblox.deserializePlace(fs.readFile(path))
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

local sss = game:GetService("ServerScriptService")
local okL, loadstr = pcall(function()
	return sss.LoadStringEnabled
end)
check("LoadStringEnabled is off", okL and loadstr == false, tostring(loadstr))
local okH, http = pcall(function()
	return game:GetService("HttpService").HttpEnabled
end)
check("HttpEnabled is off (or not set)", (not okH) or http ~= true, tostring(http))

local roots = {
	sss,
	game:GetService("ReplicatedStorage"),
	game:GetService("ReplicatedFirst"),
	game:GetService("StarterPlayer"),
}
local function underRoot(inst: any): boolean
	for _, r in roots do
		if inst:IsDescendantOf(r) then
			return true
		end
	end
	return false
end
local INSERT_OK = { ModelLibrary = true, WorldBuilder = true, Decor = true }
local n = 0
for _, d in game:GetDescendants() do
	if d:IsA("LuaSourceContainer") then
		n += 1
		local full = d:GetFullName()
		check("script in our folder: " .. full, underRoot(d))
		check("script not in Workspace: " .. full, not d:IsDescendantOf(game:GetService("Workspace")))
		local src = d.Source or ""
		local noComments = string.gsub(src, "%-%-[^\n]*", "") -- without comments
		local code = string.gsub(noComments, '"[^"\n]*"', '""') -- and without quoted strings
		code = string.gsub(code, "'[^'\n]*'", "''")
		check("no require(number): " .. full, not string.find(code, "require%s*%(%s*%d"))
		-- require as a value (local x = require; x(48291)) - this is how backdoors hide the module id
		check("require only as a call: " .. full, not string.find(code, "%f[%w_]require%f[^%w_]%s*[^%(%s]"))
		check("no getfenv/setfenv: " .. full, not string.find(code, "[gs]etfenv"))
		check("no loadstring: " .. full, not string.find(code, "loadstring"))
		check("no outbound HTTP: " .. full, not (string.find(noComments, "GetAsync%s*%(%s*[\"']https?:") or string.find(code, "PostAsync") or string.find(code, "RequestAsync")))
		if string.find(code, "InsertService") then
			check("InsertService only in the known ones: " .. full, INSERT_OK[d.Name] == true)
		end
	end
end
check("scripts found", n > 50, n)
print(string.format("security_place: %d passed, %d failed (scripts %d)", passed, failed, n))
if failed > 0 then
	error("security_place: there are failures")
end
