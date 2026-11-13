-- Prints Config.World.materials for build.py (the terrain MaterialVariants in the place file): enabled, then per variant
-- name|base|texture|studsPerTile|r,g,b
local Config = require("../src/shared/Config")
local M = Config.World.materials
print("enabled=" .. tostring(M ~= nil and M.enabled == true))
if M then
	for _, v in M.variants do
		local t = v.tint or { 255, 255, 255 }
		print(string.format("variant=%s|%s|%s|%s|%d,%d,%d", v.name, v.base, v.texture, tostring(v.studsPerTile), t[1], t[2], t[3]))
	end
end
