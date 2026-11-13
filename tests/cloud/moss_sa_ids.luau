-- Read only: the SurfaceAppearance texture ids inside the moss model ph_rock_moss_set_02 (119835695649000) and in all ph_* DecorAssets models.
local ok, m = pcall(function() return game:GetService("InsertService"):LoadAsset(119835695649000) end)
if not ok then return { err = tostring(m) } end
local out = {}
for _, d in m:GetDescendants() do
	if d:IsA("SurfaceAppearance") then
		table.insert(out, { path = d:GetFullName():sub(1, 80), color = d.ColorMap, normal = d.NormalMap, rough = d.RoughnessMap, metal = d.MetalnessMap })
	elseif d:IsA("MeshPart") then
		table.insert(out, { mesh = d.Name:sub(1, 40), meshId = d.MeshId, textureId = d.TextureID })
	end
end
return { n = #out, items = out }
