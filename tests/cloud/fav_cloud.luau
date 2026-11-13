-- the "favorite" window in the published version - Config.FavPrompt, Core/Favorite, the client module, the analytics names
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Core = Shared:WaitForChild("Core")
local fav = Core:FindFirstChild("Favorite")
local due = fav and require(fav).due({ flew = true }, false, 0, 10, Config.FavPrompt)
local names = table.concat(Remotes.List.Analytics.args[1].values, ",")
local client = game:GetService("StarterPlayer"):FindFirstChild("Favorite", true) or game:GetService("ReplicatedStorage"):FindFirstChild("Favorite", true)
return string.format("FavPrompt on=%s delay=%s | Core.Favorite=%s due=%s | analytics fav=%s | client module=%s",
	tostring(Config.FavPrompt and Config.FavPrompt.on), tostring(Config.FavPrompt and Config.FavPrompt.delay), tostring(fav ~= nil),
	tostring(due), tostring(string.find(names, "fav_prompt", 1, true) ~= nil and string.find(names, "fav_done", 1, true) ~= nil),
	tostring(client ~= nil))
