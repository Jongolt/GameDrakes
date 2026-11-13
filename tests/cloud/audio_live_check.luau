-- whether the fight track A and its win phrase load in the live place (the Use rights for the audio); read only
local ContentProvider = game:GetService("ContentProvider")
local ids = { 70406877413972, 88533814202542, 76564938505756 }
local sounds, status = {}, {}
for _, id in ids do
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Parent = workspace
	table.insert(sounds, s)
end
ContentProvider:PreloadAsync(sounds, function(assetId, st)
	status[assetId] = tostring(st)
end)
local out = {}
for _, s in sounds do
	out[s.SoundId] = { status = status[s.SoundId], loaded = s.IsLoaded, len = s.TimeLength }
end
return out
