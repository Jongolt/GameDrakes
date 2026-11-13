--!strict
-- The soft swimming ban (spec 04 §6, craft/04 §7.10 series 11 - HTTYD: "Swimming is cool, but... We recommend Dragon!").
-- Neither a wall nor a teleport back: after Config.World.swim.showAfter s in the water - a caption above the HUD action button. If a teen or
-- an adult is nearby - "ride your dragon!" (the Ride/Fly button is already in the HUD), otherwise - "head back to shore" and the Back to shore button (the server
-- Movement.shore: a teleport to the nearest land). The underwater haze is Roblox's built-in one (Terrain.WaterColor), no own one needed.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))

local Swim = {}

local SW = Config.World.swim
local me = Players.LocalPlayer
local companion: any = nil
local banners: any = nil
local gui: ScreenGui? = nil
local label: TextLabel? = nil
local button: TextButton? = nil
local since: number? = nil
local lastPoll = 0
local busy = false

local function swimming(): boolean
	local ch = me.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 or me:GetAttribute("Mounted") ~= nil then
		return false
	end
	return hum:GetState() == Enum.HumanoidStateType.Swimming
end

local function build()
	local g = UIKit.screen("Swim", 3)
	g.Enabled = false
	local box = Instance.new("Frame")
	box.Name = "Box"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 1)
	box.Position = UDim2.fromScale(0.5, 0.86) -- above the HUD action button (0.965)
	box.Size = UDim2.fromScale(0.7, 0.12)
	box.Parent = g
	label = UIKit.text(box, Strings.Hints.swimming, UIKit.CREAM, { Name = "Line", Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.42) })
	local b = UIKit.button(box, Strings.Hints.backToShore, UIKit.GREEN, function()
		if busy then
			return
		end
		busy = true
		local r = Net.call("Shore")
		busy = false
		if not r.ok and r.reason ~= "too_fast" and banners then
			banners.toast((Strings.Errors :: any)[r.reason or ""] or Strings.Errors.bad_request)
		end
	end, { minSize = Vector2.new(120, 36) })
	b.Name = "Shore"
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.fromScale(0.5, 0.5)
	b.Size = UDim2.fromScale(0.34, 0.5)
	button = b
	gui = g
end

local function poll()
	local g, l, b = gui, label, button
	if not g or not l or not b then
		return
	end
	local inWater = swimming()
	if inWater then
		since = since or os.clock()
	else
		since = nil
	end
	local show = since ~= nil and os.clock() - (since :: number) >= SW.showAfter
	if show then
		local uid = if companion then companion.near() else nil
		l.Text = if uid then Strings.Hints.swimming else Strings.Hints.swimNoDragon
		b.Visible = uid == nil
	end
	g.Enabled = show
end

function Swim.isSwimming(): boolean
	return since ~= nil
end

function Swim.init(_snapshot: any, loaded: any)
	companion = loaded.Companion
	banners = loaded.Banners
end

function Swim.start()
	build()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastPoll < SW.pollSeconds then
			return
		end
		lastPoll = now
		local ok, err = pcall(poll)
		if not ok then
			warn("[Swim] " .. tostring(err))
		end
	end)
end

return Swim
