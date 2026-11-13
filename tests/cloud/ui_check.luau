-- A cloud test (spec 02 add. 2.12): the button in the Roblox row at the system height, standing on a dragon is not allowed.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared", 10):WaitForChild("Config"))
return { topLeft = Config.UI.topbar.left, topBottom = Config.UI.topbar.bottom, noStand = Config.Dragon.noStand ~= nil and Config.Dragon.noStand.push, dayNight = Config.UI.worldTimers.dayNight }
