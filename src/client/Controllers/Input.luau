--!strict
-- Input (02 §4): a tap/click on the own dragon opens the card (ScreenPointToRay accounts for the interface inset). The input type -
-- by UserInputService.LastInputTypeChanged (the InputKind attribute on the player for other controllers). Flight/ride buttons - 1.9.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIStack = require(script.Parent:WaitForChild("UIStack"))
local DragonCard = require(script.Parent:WaitForChild("DragonCard"))

local Input = {}

local me = Players.LocalPlayer
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local function dragonAt(x: number, y: number): Model?
	local cam = workspace.CurrentCamera
	local ray = cam:ScreenPointToRay(x, y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { me.Character :: Instance }
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 160, params)
	local inst: Instance? = hit and hit.Instance
	while inst and inst ~= workspace do
		if inst:IsA("Model") and inst:GetAttribute("Uid") ~= nil then
			return if inst:GetAttribute("OwnerId") == me.UserId then inst else nil
		end
		inst = inst.Parent
	end
	return nil
end

local function tryOpen(x: number, y: number)
	if UIStack.depth() > 0 then
		return
	end
	local m = dragonAt(x, y)
	if m then
		DragonCard.open(m:GetAttribute("Uid") :: string)
	end
end

local function kindOf(t: Enum.UserInputType): string
	if t == Enum.UserInputType.Touch then
		return "touch"
	elseif t == Enum.UserInputType.Gamepad1 or t == Enum.UserInputType.Gamepad2 then
		return "gamepad"
	end
	return "keyboard"
end

-- the device slice for analytics (11 §1): Remote Analytics "device" on an input kind change, no more often than once per 5 s
local lastSent, lastSentAt = "", 0
local function sendDevice(kind: string)
	local d = if kind == "keyboard" then "kbm" else kind
	if d == lastSent or os.clock() - lastSentAt < 5 then
		return
	end
	lastSent, lastSentAt = d, os.clock()
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer("device", { device = d })
	end
end

-- the Roblox PlayerModule highlights the dynamic thumbstick zone background for ~2 s on join
-- (PlayerGui.TouchGui.TouchControlFrame.DynamicThumbstickFrame, DoFadeInBackground) - on the light plaza it is a gray film over 40% of the screen
-- on the left. The zone and the thumbstick circle keep working, only the background is dimmed: we hold BackgroundTransparency = 1 (the PlayerModule tween writes
-- every frame, our reset - in the same frame, before rendering). Config.UI.touch.thumbstickZoneFade = true brings the Roblox highlight back.
local function muteThumbstickZone(inst: Instance)
	if inst.Name ~= "DynamicThumbstickFrame" or not inst:IsA("GuiObject") then
		return
	end
	local f = inst :: GuiObject
	f.BackgroundTransparency = 1
	f:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		if f.BackgroundTransparency < 1 then
			f.BackgroundTransparency = 1
		end
	end)
end

local function watchTouchGui()
	local pg = me:WaitForChild("PlayerGui")
	pg.DescendantAdded:Connect(muteThumbstickZone)
	for _, d in pg:GetDescendants() do
		muteThumbstickZone(d)
	end
end

function Input.start()
	if not Config.UI.touch.thumbstickZoneFade then
		task.spawn(watchTouchGui)
	end
	me:SetAttribute("InputKind", kindOf(UserInputService:GetLastInputType()))
	sendDevice(kindOf(UserInputService:GetLastInputType()))
	UserInputService.LastInputTypeChanged:Connect(function(t)
		me:SetAttribute("InputKind", kindOf(t))
		sendDevice(kindOf(t))
	end)
	UserInputService.TouchTap:Connect(function(positions: { Vector2 }, processed: boolean)
		if processed or #positions == 0 then
			return
		end
		tryOpen(positions[1].X, positions[1].Y)
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		local p = input.Position
		tryOpen(p.X, p.Y)
	end)
end

return Input
