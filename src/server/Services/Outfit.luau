--!strict
-- The character look (P20; craft/04 §7.9): a woven egg basket on the back - one item, and the hero is "from this game".
-- The basket is made of parts (a wicker cylinder, a dark rim, handles), welded to UpperTorso (R15) or Torso (R6).
-- Later: an egg in the basket while carrying (EggSpawner 1.7), basket skins (07).
-- looks (07 add. 2.6): the rider's scarf from Starter Pack (owned.scarf) - a collar on the neck and a tail on the chest, the colors and torso fractions -
-- Config.Looks.scarf; after every respawn and right after a purchase (Outfit.refresh from Looks.refresh).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local LooksCore = require(Shared:WaitForChild("Core"):WaitForChild("Looks"))

local Outfit = {}

local services: { [string]: any } = {}

local WICKER = Color3.fromRGB(190, 135, 75)
local WICKER_DARK = Color3.fromRGB(135, 90, 50)

local function piece(parent: Model, name: string, shape: Enum.PartType, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.Fabric
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, offset: CFrame)
	b.CFrame = a.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = b
end

local function buildBasket(torso: BasePart): Model
	local m = Instance.new("Model")
	m.Name = "Basket"
	-- the cylinder lies along X: rotate so the axis becomes vertical
	local back = CFrame.new(0, -0.1, 0.95)
	local body = piece(m, "Body", Enum.PartType.Cylinder, Vector3.new(1.5, 1.6, 1.6), WICKER)
	weld(torso, body, back * CFrame.Angles(0, 0, math.rad(90)))
	local rim = piece(m, "Rim", Enum.PartType.Cylinder, Vector3.new(0.25, 1.75, 1.75), WICKER_DARK)
	weld(torso, rim, back * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local inner = piece(m, "Inner", Enum.PartType.Cylinder, Vector3.new(0.3, 1.35, 1.35), Color3.fromRGB(110, 70, 40))
	weld(torso, inner, back * CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)))
	for _, side in { -1, 1 } do
		local strap = piece(m, "Strap", Enum.PartType.Block, Vector3.new(0.25, 1.3, 0.2), WICKER_DARK)
		strap.Material = Enum.Material.SmoothPlastic
		weld(torso, strap, CFrame.new(side * 0.55, 0.3, 0.45) * CFrame.Angles(math.rad(-25), 0, 0))
	end
	m.PrimaryPart = body
	m.Parent = torso.Parent
	return m
end

-- looks: the scarf - a collar (a cylinder with the axis up) at the torso top, the tail on the chest to the side, fringe at the tail end
local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function buildScarf(torso: BasePart): Model
	local SC = Config.Looks.scarf
	local m = Instance.new("Model")
	m.Name = "Scarf"
	local sz = torso.Size
	local main, fringe = rgb(SC.color), rgb(SC.fringe)
	local d = sz.X * SC.collarWidth
	local h = sz.Y * SC.collarHeight
	local top = sz.Y / 2 + SC.collarLift
	local collar = piece(m, "Collar", Enum.PartType.Cylinder, Vector3.new(h, d, d), main)
	weld(torso, collar, CFrame.new(0, top, 0) * CFrame.Angles(0, 0, math.rad(90)))
	local tw, tl, tt = sz.X * SC.tail[1], sz.Y * SC.tail[2], SC.tail[3]
	-- the character's face is at -Z: the tail in front, slightly to the side, tilted outward
	local tailCf = CFrame.new(sz.X * SC.tailX, top - tl / 2, -(sz.Z / 2 + tt / 2 + 0.02)) * CFrame.Angles(0, 0, math.rad(-SC.tailTiltDeg))
	local tail = piece(m, "Tail", Enum.PartType.Block, Vector3.new(tw, tl, tt), main)
	weld(torso, tail, tailCf)
	local fh = tl * SC.fringeHeight
	local fr = piece(m, "Fringe", Enum.PartType.Block, Vector3.new(tw * 1.04, fh, tt * 1.1), fringe)
	weld(torso, fr, tailCf * CFrame.new(0, -tl / 2 + fh / 2, 0))
	m.PrimaryPart = collar
	m.Parent = torso.Parent
	return m
end

local function wantsScarf(character: Model): boolean
	local player = Players:GetPlayerFromCharacter(character)
	local data = player and services.PlayerData and services.PlayerData.get(player)
	return data ~= nil and LooksCore.scarf(data)
end

local function dressScarf(character: Model, torso: BasePart)
	local old = character:FindFirstChild("Scarf")
	if old then
		old:Destroy()
	end
	if wantsScarf(character) then
		buildScarf(torso)
	end
end

local function torsoOf(character: Model): BasePart?
	local torso = character:WaitForChild("UpperTorso", 5) or character:WaitForChild("Torso", 5)
	return if torso and torso:IsA("BasePart") then torso else nil
end

local function onCharacter(character: Model)
	local torso = torsoOf(character)
	if torso then
		local old = character:FindFirstChild("Basket")
		if old then
			old:Destroy()
		end
		buildBasket(torso)
		local ok, err = pcall(dressScarf, character, torso)
		if not ok then
			warn("[Outfit] scarf: " .. tostring(err))
		end
	end
end

-- looks: the scarf on the current character by the profile flag (after buying Starter Pack or a gift)
function Outfit.refresh(player: Player)
	local ch = player.Character
	local torso = ch and torsoOf(ch)
	if ch and torso then
		dressScarf(ch, torso)
	end
end

function Outfit.init(s: { [string]: any })
	services = s
end

function Outfit.start()
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(ch)
			task.defer(function()
				local ok, err = pcall(onCharacter, ch)
				if not ok then
					warn("[Outfit] basket: " .. tostring(err))
				end
			end)
		end)
		if player.Character then
			task.defer(onCharacter, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
end

return Outfit
