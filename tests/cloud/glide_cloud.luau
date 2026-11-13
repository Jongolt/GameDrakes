-- A cloud test: what of the fix "the nest ledge -> gliding" is in the published version - the cliff (terrace.ledgeCliff)
-- the Glide parameters (lookAhead, steepVy, grace) and the drop past the ledge of nest 1 by the terrain (Island.height); read only
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Island = require(Shared:WaitForChild("Core"):WaitForChild("Island"))
local Layout = require(Shared:WaitForChild("Core"):WaitForChild("Layout"))
local G = Config.Dragon.glide
local T = (Config.World :: any).island2 and (Config.World :: any).island2.terrace or {}
local hills = Layout.hills()
local pv = Layout.nestPivots()[1]
local a, b = Layout.localToWorld(pv, { 0, 0, 56 }), Layout.localToWorld(pv, { 0, 0, 63 })
return string.format("placeVersion=%d ledgeCliff=%s lookAhead=%s steepVy=%s grace=%s drop_at_8=%.1f",
	game.PlaceVersion, tostring(T.ledgeCliff ~= nil), tostring(G.lookAhead), tostring(G.steepVy), tostring(G.grace),
	Island.height(hills, a[1], a[3]) - Island.height(hills, b[1], b[3]))
