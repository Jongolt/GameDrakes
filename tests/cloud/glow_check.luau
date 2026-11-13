-- why the glowing dragon does not glow in live: the templates, their maps, the Ember hatchling mesh (InsertService) - read only
local RS = game:GetService("ReplicatedStorage")
local IS = game:GetService("InsertService")
local out = { templates = {}, mesh = {} }
local f = RS:FindFirstChild("GlowTemplates")
out.hasTemplates = f ~= nil
if f then
	for _, t in f:GetChildren() do
		if t:IsA("SurfaceAppearance") then
			table.insert(out.templates, { name = t.Name, tex = t:GetAttribute("Texture"), em = t.EmissiveStrength, color = tostring(t.Color) })
		end
	end
end
local ok, m = pcall(function() return IS:LoadAsset(78838233837073) end)
out.loadOk = ok
if ok and m then
	for _, d in m:GetDescendants() do
		if d:IsA("MeshPart") then
			local kids = {}
			for _, c in d:GetChildren() do table.insert(kids, c.ClassName .. ":" .. c.Name) end
			table.insert(out.mesh, { name = d.Name, tex = d.TextureID, mesh = d.MeshId, kids = kids })
		end
	end
else
	out.loadErr = tostring(m)
end
return out
