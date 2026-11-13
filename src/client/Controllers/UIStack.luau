--!strict
-- The menu stack (02 §1, 10 §4): one menu at a time, "back" closes the top one; with a menu open Blur 12, character movement
-- off, the camera does not rotate, the HUD is hidden. A menu draws its own ScreenGui and hands its close function here.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local UIStack = {}

local me = Players.LocalPlayer
local stack: { { name: string, close: () -> () } } = {}
local hud: any = nil
local blur: BlurEffect? = nil
local savedCamType: Enum.CameraType? = nil
local controls: any = nil
local savedWalk: number? = nil

local function getControls(): any
	if controls ~= nil then
		return controls
	end
	local ok, c = pcall(function()
		local pm = me:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 5)
		return (require(pm :: any) :: any):GetControls()
	end)
	controls = if ok then c else false
	return controls
end

local function freeze(on: boolean)
	-- blur
	if on then
		if not blur then
			local b = Instance.new("BlurEffect")
			b.Name = "MenuBlur"
			b.Size = 0
			b.Parent = Lighting
			blur = b
		end
		TweenService:Create(blur :: BlurEffect, TweenInfo.new(0.25), { Size = Config.UI.menu.blur }):Play()
	elseif blur then
		local b = blur :: BlurEffect
		blur = nil
		TweenService:Create(b, TweenInfo.new(0.25), { Size = 0 }):Play()
		task.delay(0.3, function()
			b:Destroy()
		end)
	end
	-- movement: PlayerModule, the fallback - WalkSpeed 0
	local c = getControls()
	local hum = me.Character and me.Character:FindFirstChildOfClass("Humanoid")
	if c then
		if on then
			c:Disable()
		else
			c:Enable()
		end
	elseif hum then
		if on then
			savedWalk = hum.WalkSpeed
			hum.WalkSpeed = 0
		elseif savedWalk then
			hum.WalkSpeed = savedWalk
			savedWalk = nil
		end
	end
	-- the camera in place
	local cam = workspace.CurrentCamera
	if on then
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			savedCamType = cam.CameraType
			local cf = cam.CFrame
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = cf
		end
	elseif savedCamType then
		cam.CameraType = savedCamType
		if savedCamType == Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Custom
		end
		savedCamType = nil
	end
	-- HUD
	if hud and hud.setVisible then
		hud.setVisible(not on)
	end
end

function UIStack.depth(): number
	return #stack
end

function UIStack.isOpen(name: string?): boolean
	if not name then
		return #stack > 0
	end
	for _, e in stack do
		if e.name == name then
			return true
		end
	end
	return false
end

function UIStack.top(): string?
	local e = stack[#stack]
	return e and e.name
end

-- open the menu name; close() closes its interface (without calling UIStack). Reopening the same name - no.
function UIStack.open(name: string, close: () -> ()): boolean
	if UIStack.isOpen(name) then
		return false
	end
	if #stack == 0 then
		freeze(true)
	end
	table.insert(stack, { name = name, close = close })
	return true
end

-- close the top one
local Sounds = require(script.Parent:WaitForChild("Sounds"))

function UIStack.back(): boolean
	local e = table.remove(stack)
	if not e then
		return false
	end
	Sounds.play("menu_close")
	pcall(e.close)
	if #stack == 0 then
		freeze(false)
	end
	return true
end

-- close a specific menu (if it is on top - like back; otherwise pull it out of the stack)
function UIStack.close(name: string)
	for i = #stack, 1, -1 do
		if stack[i].name == name then
			local e = table.remove(stack, i) :: any
			pcall(e.close)
			break
		end
	end
	if #stack == 0 then
		freeze(false)
	end
end

function UIStack.closeAll()
	while #stack > 0 do
		UIStack.back()
	end
end

function UIStack.init(_snapshot: any, loaded: any)
	hud = loaded.HUD
end

function UIStack.start()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.ButtonB or input.KeyCode == Enum.KeyCode.Backspace then
			UIStack.back()
		end
	end)
	me.CharacterAdded:Connect(function()
		if #stack > 0 then
			task.wait(0.5)
			freeze(true)
		end
	end)
end

return UIStack
