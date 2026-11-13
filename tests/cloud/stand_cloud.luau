-- A cloud test: what is in the published version - the number, the badge ids, the Dragon of the Week stand (the DragonStand service
-- Config.World.dragonStand, Core/Shop.standSku, the strings) and that now (until 15.11) it is empty by date; read only
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Content = require(Shared:WaitForChild("Content"))
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Shop = require(Shared:WaitForChild("Core"):WaitForChild("Shop"))
local LiveOps = require(Shared:WaitForChild("Core"):WaitForChild("LiveOps"))
local sss = game:GetService("ServerScriptService"):FindFirstChild("Services", true)
local badges, zero = 0, {}
for k, b in Content.Badges do
	if (b :: any).id and (b :: any).id > 0 then badges += 1 else table.insert(zero, k) end
end
table.sort(zero)
local now = os.time()
local live = LiveOps.live(Content.Updates, now)
local st = if (Shop :: any).standSku then (Shop :: any).standSku(live, now, Content.Updates) else nil
return string.format("placeVersion=%d badges=%d zero=[%s] DragonStand=%s config=%s standSku=%s strings=%s now_live=%d now_stand=%s",
	game.PlaceVersion, badges, table.concat(zero, ","), tostring(sss and sss:FindFirstChild("DragonStand") ~= nil),
	tostring((Config.World :: any).dragonStand ~= nil), tostring((Shop :: any).standSku ~= nil),
	tostring((Strings.World :: any).standTitle), live, if st then st.key else "-")
