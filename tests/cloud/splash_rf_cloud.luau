-- A cloud test: the splash does not wait for Shared - in the published version the hatchling model is baked into ReplicatedFirst
-- the splash client (Main.client) without require Config before the swap (the script text check is unavailable - only the model and the version).
local RF = game:GetService("ReplicatedFirst")
local ld = RF:FindFirstChild("LoadingDragon")
local mp = ld and ld:FindFirstChildWhichIsA("MeshPart", true)
return { placeVersion = game.PlaceVersion, model = ld and ld.ClassName or "none", mesh = mp and (mp.MeshId .. " " .. mp.TextureID) or "none",
	scripts = #RF:GetChildren() }
