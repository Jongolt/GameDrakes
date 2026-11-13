-- A cloud test (2.9): update 1 Aurora in the published version - the LiveOps service and controller are in place, the updates
-- are not running yet (UpdatesLive 0 until 08.11), the scrolls in the world, the Remote Code, the Glacier/Pearl variant meshes load (InsertService, MeshPart).
local RS = game:GetService("ReplicatedStorage")
local InsertService = game:GetService("InsertService")
local Shared = RS:WaitForChild("Shared", 10)
local Content = require(Shared:WaitForChild("Content"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local LiveOps = require(Shared:WaitForChild("Core"):WaitForChild("LiveOps"))
local Quests = require(Shared:WaitForChild("Core"):WaitForChild("Quests"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
local sss = game:GetService("ServerScriptService"):FindFirstChild("Services", true)
local meshes = {}
for id, v in Content.Variants do
	for i, a in v.stages do
		local ok, res = pcall(function()
			local c = InsertService:LoadAsset(a)
			local mp = c:FindFirstChildWhichIsA("MeshPart", true)
			local n = mp and #mp.MeshId or 0
			c:Destroy()
			return n > 0
		end)
		table.insert(meshes, id .. i .. "=" .. (if ok and res then "ok" else ("FAIL " .. tostring(res))))
	end
end
table.sort(meshes)
return {
	placeVersion = game.PlaceVersion,
	live = LiveOps.live(Content.Updates, os.time()),
	quests = Quests.total(LiveOps.live(Content.Updates, os.time())),
	service = sss ~= nil and sss:FindFirstChild("LiveOps") ~= nil,
	controller = ctl ~= nil and ctl:FindFirstChild("LiveOps") ~= nil,
	codeRemote = Remotes.List.Code ~= nil,
	updates = #Content.Updates,
	meshes = table.concat(meshes, ","),
}
