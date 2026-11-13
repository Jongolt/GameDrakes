-- A cloud test: the "a dragon has one model" safeguard in Movement (the server), the release number.
local Movement = require(game:GetService("ServerScriptService"):FindFirstChild("Movement", true) :: any)
return { placeVersion = game.PlaceVersion, dupGuard = type(Movement.dupCount) == "function" }
