-- Content.Music and Content.Ambience in the published version - the states, the track count, the loading of every id (PreloadAsync)
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Content = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Content"))
local M = Content.Music
if not M then
	return { ok = false, err = "no Content.Music" }
end
local sounds, byId, states = {}, {}, {}
for state, list in M.states do
	states[state] = #list
	for _, t in list do
		local s = Instance.new("Sound")
		s.SoundId = "rbxassetid://" .. t.id
		s.Parent = workspace
		table.insert(sounds, s)
		byId[s.SoundId] = state
	end
end
local amb = {}
for k, t in (Content.Ambience and Content.Ambience.loops or {}) do
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. t.id
	s.Parent = workspace
	table.insert(sounds, s)
	amb[k] = t.id
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
return { ok = #bad == 0, ambience = amb, gap = M.gap, tracks = #sounds, loaded = ok, bad = bad, states = states, oldLoop = Content.Sounds.music, fade = M.fade }
