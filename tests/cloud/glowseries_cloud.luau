-- the golden egg series (read only): the place version, the server errors and warnings since the start, the series in Config, the module
-- Core/GlowSeries loads and gives the elements by number, the glow templates - how many per element and whether all have the Texture attribute
local RS = game:GetService("ReplicatedStorage")
local LogService = game:GetService("LogService")
local Shared = RS:WaitForChild("Shared")
local C = require(Shared:WaitForChild("Config"))
task.wait(14) -- the services start: the world ~6 s, Raid waits for the spots, the Gloom models load
local errs = {}
for _, m in LogService:GetLogHistory() do
	if m.messageType == Enum.MessageType.MessageError or m.messageType == Enum.MessageType.MessageWarning then
		table.insert(errs, string.sub(m.message, 1, 160))
	end
end
local okS, GS = pcall(function()
	return require(Shared:WaitForChild("Core"):WaitForChild("GlowSeries"))
end)
local byN = {}
if okS then
	for n = 1, 7 do
		byN[n] = GS.element({ n = n }, C.Glow.egg)
	end
end
local per, noTex, total = {}, 0, 0
local f = RS:FindFirstChild("GlowTemplates")
if f then
	for _, t in f:GetChildren() do
		if t:IsA("SurfaceAppearance") then
			total += 1
			local el = string.match(t.Name, "^(%a+)_")
			if el then
				per[el] = (per[el] or 0) + 1
			end
			if typeof(t:GetAttribute("Texture")) ~= "string" then
				noTex += 1
			end
		end
	end
end
return { placeVersion = game.PlaceVersion, series = C.Glow.egg.series, seriesModule = okS, byN = byN, templates = total, perElement = per,
	noTexture = noTex, nErr = #errs, errs = errs }
