-- A cloud test (the second part): in the published version the sea is built by the client (Ocean), the fog at the edge, the book on a low
-- screen, the Ocean controller in the client scripts. Run: python3 cloud_test.py edge_check [--version N].
local RS = game:GetService("ReplicatedStorage")
local Config = require(RS:WaitForChild("Shared", 10):WaitForChild("Config"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
return {
	seaClient = Config.World.seaPlane.client == true,
	seaColor = table.concat(Config.World.seaPlane.color, ","),
	ocean = Config.World.ocean ~= nil and Config.World.ocean.outerTo,
	mistFrom = Config.World.ocean and Config.World.ocean.mist.from,
	bookSmall = Config.UI.book.smallBelow,
	oceanController = ctl ~= nil and ctl:FindFirstChild("Ocean") ~= nil,
}
