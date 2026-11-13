-- A cloud test (tasks B + C): in the published version the new game name, the loading screen tips, the remote
-- call Setting (P37) and the Config fields for P34/P35/P33. Run: python3 cloud_test.py bc_check [--version N].
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Strings = require(Shared:WaitForChild("Strings"))
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local lf = game:GetService("ReplicatedFirst"):FindFirstChild("LoadingScreen", true)
return {
	gameName = Strings.GameName,
	title = Strings.Loading.title,
	tips = #Strings.Loading.tips,
	skip = Strings.Loading.skip,
	settingRemote = Remotes.List.Setting ~= nil,
	settingLimit = Config.RateLimit.Setting,
	distEvery = Config.UI.stepBanner.distEvery,
	worldTimers = Config.UI.worldTimers ~= nil,
	topbar = Config.UI.topbar ~= nil,
	othersKeep = Config.Dragon.lod.othersKeep,
	questPanelY = Config.Quests.panelY,
	splashHold = Config.UI.splash.holdSeconds,
	loadingScreenModule = lf ~= nil,
}
