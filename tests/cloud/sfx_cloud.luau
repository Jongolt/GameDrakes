-- the hatch sounds by rarity and the dragon voices in the published version - Core/Voices is in place, a step for every
-- rarity, every id of Content.Sounds and Content.Voices loads (PreloadAsync: moderation + the game's Use right)
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Content = require(Shared:WaitForChild("Content"))
local Voices = require(Shared:WaitForChild("Core"):WaitForChild("Voices"))
local V = Content.Voices
if not V then
	return { ok = false, err = "no Content.Voices" }
end
local ladder = {}
for _, r in Voices.RARITIES do
	ladder[r] = Content.Sounds[Voices.hatchName(r)] or "NONE"
end
local sounds, seen = {}, {}
local function add(v, tag)
	if typeof(v) == "number" and v > 0 and not seen[v] then
		seen[v] = tag
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. v
		s.Parent = workspace
		table.insert(sounds, s)
	end
end
for k, v in Content.Sounds do
	add(v, k)
end
for st, set in V.stages do
	for kind, list in set do
		for _, e in list do
			add(e.id, "voice" .. st .. kind)
		end
	end
end
local status = {}
ContentProvider:PreloadAsync(sounds, function(assetId, st)
	status[assetId] = tostring(st)
end)
local ok, bad = 0, {}
for _, s in sounds do
	if (status[s.SoundId] or ""):find("Success") then
		ok += 1
	else
		table.insert(bad, s.SoundId .. " " .. tostring(status[s.SoundId]))
	end
	s:Destroy()
end
local pick = Voices.pick(V, 3, "roar", 0)
return { ok = #bad == 0, loaded = ok, total = #sounds, bad = bad, ladder = ladder, fanfare = Content.Sounds.fanfare,
	elderRoarSpeed = pick and pick.speed, roarCooldown = V.roarCooldown, idle = V.idle.every }
