-- A cloud test: the admin commands and the bots in the published version - the Admin flag, the Remote Perf, the button strings,
-- the Perf controller on the client. Run: python3 cloud_test.py v114_check [--version N]
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local ctl = sps and sps:FindFirstChild("Controllers", true)
local sss = game:GetService("ServerScriptService")
local admin = sss:FindFirstChild("Admin", true)
return {
	placeVersion = game.PlaceVersion,
	adminEnabled = Config.Admin and Config.Admin.enabled,
	botsMax = Config.Admin and Config.Admin.bots.max,
	perfEvery = Config.Admin and Config.Admin.perf.every,
	perfRemote = Remotes.List.Perf ~= nil and Remotes.List.Perf.kind,
	botsText = Strings.Menu.bots,
	perfController = ctl ~= nil and ctl:FindFirstChild("Perf") ~= nil,
	adminModule = admin ~= nil and admin:IsA("ModuleScript"),
}
