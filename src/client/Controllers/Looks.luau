--!strict
-- Looks on the client (spec 07 add. 2.6). A dragon's color preset (the Preset attribute is set by the server, DragonVisuals.applyPreset):
-- on v4b meshes the texture is in TextureID and the part color does not change it, so the coloring is drawn with a Highlight - a fill in the preset color with
-- transparency Config.Looks.highlight.fill, no outline, not visible behind obstacles. The Highlight budget (04 §9) - only the max nearest to
-- the camera within distance studs, recomputed every every s; models hidden locally (DragonLife P37, HatchScene) and those already tinted by the server
-- (PresetTinted - SurfaceAppearance) are not highlighted. The own tag above the head (VIP / title) is hidden locally, like the Roblox name
-- (showToSelf; on the server also PlayerToHideFrom) - so Declutter does not count an invisible label.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Looks = {}

local L = Config.Looks
local H = L.highlight
local me = Players.LocalPlayer
local active: { [Model]: Highlight } = {}
local lastCands = 0

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function hiddenHere(m: Model): boolean
	local body = m.PrimaryPart
	return body ~= nil and body.LocalTransparencyModifier >= 0.99
end

local function pass()
	local cam = workspace.CurrentCamera
	if not cam then
		return
	end
	local from = cam.CFrame.Position
	local cands: { { m: Model, d: number, id: string } } = {}
	for _, inst in CollectionService:GetTagged("Dragon") do
		if inst:IsA("Model") and inst.Parent then
			local id = inst:GetAttribute("Preset")
			if typeof(id) == "string" and (L.presets :: any)[id] and not inst:GetAttribute("PresetTinted") and not hiddenHere(inst) then
				local d = (inst:GetPivot().Position - from).Magnitude
				if d <= H.distance then
					table.insert(cands, { m = inst, d = d, id = id })
				end
			end
		end
	end
	lastCands = #cands
	table.sort(cands, function(a, b)
		return a.d < b.d
	end)
	local keep: { [Model]: boolean } = {}
	for i = 1, math.min(#cands, H.max) do
		local c = cands[i]
		keep[c.m] = true
		local h = active[c.m]
		if not h or not h.Parent then
			h = Instance.new("Highlight")
			h.Name = "PresetTint"
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.OutlineTransparency = 1
			h.FillTransparency = H.fill
			h.Adornee = c.m
			h.Parent = c.m
			active[c.m] = h
		end
		h.FillColor = rgb((L.presets :: any)[c.id].tint)
	end
	for m, hl in active do
		if not keep[m] then
			hl:Destroy()
			active[m] = nil
		end
	end
	if not L.tag.showToSelf then
		local head = me.Character and me.Character:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("LookTag")
		if tag and tag:IsA("BillboardGui") and tag.Enabled then
			tag.Enabled = false
		end
	end
end

-- for Studio probes (ClientDebug "looks"): how many highlights are on and how many tinted models are nearby
function Looks.state(): string
	local n = 0
	for _ in active do
		n += 1
	end
	return string.format("highlights=%d candidates=%d max=%d", n, lastCands, H.max)
end

function Looks.init(_snapshot: any, _loaded: any) end

function Looks.start()
	task.spawn(function()
		while true do
			task.wait(H.every)
			local ok, err = pcall(pass)
			if not ok then
				warn("[Looks] " .. tostring(err))
				task.wait(5)
			end
		end
	end)
end

return Looks
