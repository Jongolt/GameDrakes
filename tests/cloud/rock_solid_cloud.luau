-- A cloud test: the garden rocks (Kenney rock_largeA) in the published version - collide in the layout and, if the world is built
-- in the session, all parts CanCollide (the body and the grass top), so the player cannot stand inside a rock.
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:WaitForChild("Shared", 10)
local W = require(Shared:WaitForChild("Config")).World
local DL = require(Shared:WaitForChild("Core"):WaitForChild("DecorLayout"))
local layout, layoutSolid = 0, 0
for _, it in DL.items() do
	if it.kind == "rock_largeA" and it.y == W.terrace.y then
		layout += 1
		if it.collide == true then
			layoutSolid += 1
		end
	end
end
local meshes = nil
local t0 = os.clock()
while os.clock() - t0 < 60 do
	local w = workspace:FindFirstChild("World")
	local m = w and w:FindFirstChild("Meshes")
	if m and m:FindFirstChild("rock_largeA") then
		meshes = m
		break
	end
	task.wait(1)
end
local models, parts, solidParts = 0, 0, 0
if meshes then
	for _, m in meshes.rock_largeA:GetChildren() do
		models += 1
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				parts += 1
				if p.CanCollide then
					solidParts += 1
				end
			end
		end
	end
end
return { placeVersion = game.PlaceVersion, layoutRocks = layout, layoutSolid = layoutSolid, worldBuilt = meshes ~= nil,
	models = models, parts = parts, solidParts = solidParts }
