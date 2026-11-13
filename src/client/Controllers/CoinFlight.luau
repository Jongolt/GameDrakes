--!strict
-- Coin flight to the counter (02 §2, 0:18-0:30): on a coins Notice, up to 10 icons fly from the pickup spot along a 1 s parabola to the
-- coin icon in the HUD; each arrival makes the counter "catch" (HUD.catch), a sound with random pitch; "+N" once, with the first one.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Content = require(Shared:WaitForChild("Content"))
local Core = Shared:WaitForChild("Core")
local HintsCore = require(Core:WaitForChild("Hints"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local CoinFlight = {}

local C = Config.UI.coinFlight
local hud: any = nil
local layer: Frame? = nil
local rng = Random.new()

local function flyOne(from: Vector2, to: Vector2, plus: number)
	local f = layer
	if not f then
		return
	end
	local origin = f.AbsolutePosition
	local icon = UIKit.coin(f, 0, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(C.iconPx, C.iconPx) })
	local side = rng:NextNumber(-28, 28) -- the icons covered the counter digits
	local arc = math.clamp((to - from).Magnitude * 0.22, 30, 90) -- a 30% arc overshot the counter from above
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.clamp((os.clock() - t0) / C.seconds, 0, 1)
		local e = 1 - (1 - t) * (1 - t) -- easeOutQuad
		local p = from:Lerp(to, e) + Vector2.new(side * math.sin(math.pi * t), -arc * math.sin(math.pi * t))
		icon.Position = UDim2.fromOffset(p.X - origin.X, p.Y - origin.Y)
		icon.Size = UDim2.fromOffset(C.iconPx * (1 - 0.55 * t), C.iconPx * (1 - 0.55 * t))
		if t >= 1 then
			conn:Disconnect()
			icon:Destroy()
			hud.catch(plus)
			Sounds.play("coin_plus", { pitch = true })
		end
	end)
end

function CoinFlight.fly(n: number, from: Vector3?)
	local to = hud and hud.coinAnchor()
	if not to then
		if hud then
			hud.catch(n)
		end
		return
	end
	local cam = workspace.CurrentCamera
	local start: Vector2? = nil
	if typeof(from) == "Vector3" then
		local v, on = cam:WorldToViewportPoint(from)
		if on then
			start = Vector2.new(v.X, v.Y)
		end
	end
	if not start then
		start = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y * 0.72)
	end
	local icons = HintsCore.coinIcons(n, C.maxIcons)
	for i = 1, icons do
		task.delay((i - 1) * C.stagger, flyOne, start :: Vector2, to, if i == 1 then n else 0)
	end
end

function CoinFlight.init(_snapshot: any, loaded: any)
	hud = loaded.HUD
	local g = UIKit.screen("CoinFlight", 1) -- below the HUD: the coins go behind the counter, not over the digits
	local f = Instance.new("Frame")
	f.Name = "Layer"
	f.BackgroundTransparency = 1
	f.Size = UDim2.fromScale(1, 1)
	f.Parent = g
	layer = f
end

function CoinFlight.start()
	Net.on("coins", function(p)
		if typeof(p.n) == "number" and p.n > 0 then
			CoinFlight.fly(p.n, p.from)
		end
	end)
end

return CoinFlight
