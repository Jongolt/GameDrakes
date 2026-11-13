-- the dragon name limit in the published version (Config.Names.renameCooldown >= 60, the refusal code and the string)
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local cd = Config.Names.renameCooldown
return { ok = typeof(cd) == "number" and cd >= 60 and table.find(Remotes.Reasons, "name_cooldown") ~= nil and Strings.Errors.name_cooldown ~= nil,
	cooldown = cd, text = Strings.Errors.name_cooldown }
