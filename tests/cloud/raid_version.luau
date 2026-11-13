-- read only - the test place: the version, the raids are on, the Raid service, the Gloom nests and the guards are built
-- no free eggs on the meadow/cliff/bath spots, the server errors and warnings since the start
local RS = game:GetService("ReplicatedStorage")
local CS = game:GetService("CollectionService")
local LogService = game:GetService("LogService")
local SSS = game:GetService("ServerScriptService")
local C = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
task.wait(14) -- the services start: the world ~6 s, Raid waits for the spots + 1.5 s, the Gloom models load
local errs = {}
for _, m in LogService:GetLogHistory() do
	if m.messageType == Enum.MessageType.MessageError or m.messageType == Enum.MessageType.MessageWarning then
		table.insert(errs, string.sub(m.message, 1, 160))
	end
end
local rings = { [0] = 0, [1] = 0, [2] = 0 }
local withEgg = 0
for _, m in CS:GetTagged("RaidNest") do
	local r = tonumber(m:GetAttribute("Ring")) or -1
	rings[r] = (rings[r] or 0) + 1
	if m:GetAttribute("HasEgg") == true then
		withEgg += 1
	end
end
local guards, zz = 0, 0
for _, m in CS:GetTagged("GloomChase") do
	guards += 1
	local b = m.PrimaryPart and m.PrimaryPart:FindFirstChild("Mark")
	local t = b and b:FindFirstChild("T")
	if t and t:IsA("TextLabel") and t.Text == "Zz" then
		zz += 1
	end
end
local freeMeadow, freeSummit = 0, 0
for _, a in CS:GetTagged("EggPoint") do
	if a:FindFirstChild("Egg") then
		local z = a:GetAttribute("Zone")
		if z == "Meadow" or z == "Cliffs" or z == "Springs" then
			freeMeadow += 1
		elseif z == "Summit" then
			freeSummit += 1
		end
	end
end
local svc = SSS:FindFirstChild("Services")
return { placeVersion = game.PlaceVersion, raidOn = C.Raid and C.Raid.on, raidService = svc and svc:FindFirstChild("Raid") ~= nil,
	ring0 = rings[0], ring1 = rings[1], ring2 = rings[2], withEgg = withEgg, guards = guards, sleeping = zz,
	freeOnRaidPoints = freeMeadow, freeSummit = freeSummit, nests = workspace:FindFirstChild("RaidNests") ~= nil,
	slot4 = C.Balance.slots.coins[1], hatchRare = C.Raid and C.Raid.hatchSeconds.Rare, nErr = #errs, errs = errs }
