-- A cloud test (the decisions by the Ride A Pet teardown, spec 02 add. 2.11): the day timer is off, the splash not longer than 3 s, skip from 1.5 s.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared", 10):WaitForChild("Config"))
return { dayNight = Config.UI.worldTimers.dayNight, hold = Config.UI.splash.holdSeconds, skipAfter = Config.UI.splash.skipAfter, seaClient = Config.World.seaPlane.client }
