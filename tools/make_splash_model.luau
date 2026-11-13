-- the splash 3D baby as a model file (the Open Cloud key does not download assets - 403 Scope; Studio Ctrl+S on P8 got stuck on a dialog).
-- One MeshPart with the properties of the ember s0 model (asset 78838233837073: mesh 138960038776022, texture 94120130742913, size
-- from Studio); no bones - the mesh is drawn in the bind pose. -> assets_src/splash/LoadingDragon.rbxmx (run from roblox_game/)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame = roblox.Instance, roblox.Vector3, roblox.CFrame
local size = Vector3.new(1.001299, 0.517715, 0.971303)
local m = Instance.new("Model")
m.Name = "LoadingDragon"
local p = Instance.new("MeshPart")
p.Name = "geometry_0"
p.MeshId = "rbxassetid://138960038776022"
p.TextureID = "rbxassetid://94120130742913"
p.Size = size
pcall(function()
	(p :: any).InitialSize = size
end)
p.CFrame = CFrame.new(0, 0, 0)
p.Anchored = true
p.CanCollide = false
p.CanQuery = false
p.CanTouch = false
p.CastShadow = false
p.Parent = m
m.PrimaryPart = p
fs.writeDir("assets_src/splash")
fs.writeFile("assets_src/splash/LoadingDragon.rbxmx", roblox.serializeModel({ m }, true)) -- XML: build.py inserts it as is
print("ok")
