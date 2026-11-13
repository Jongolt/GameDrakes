--!strict
-- the updraft - a column tagged
-- Updraft (right past the ledge of every nest, at the foot of the Cliffs). A character inside the column rises at the speed
-- Config.World.updraft.rise; left at the top or sideways - a normal fall, with the hatchling on the shoulder then gliding (Glide: Freefall,
-- height >= minHeight). While gliding the stream lifts through the player attribute Updraft (Glide reads it). Mounted - not touched
-- (Fly runs the flight). The column at the Cliffs has the caption "Jump in to rise up".
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local Updraft = {}

local U = Config.World.updraft
local me = Players.LocalPlayer

local function inside(p: BasePart, pos: Vector3): boolean
	local l = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2
	return math.abs(l.X) <= h.X and math.abs(l.Y) <= h.Y and math.abs(l.Z) <= h.Z
end

local function setFlag(on: boolean)
	if (me:GetAttribute("Updraft") == true) ~= on then
		me:SetAttribute("Updraft", if on then true else nil)
	end
end

local current: BasePart? = nil -- the column the character is in (for holding toward the center)

local function step()
	local ch = me.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not r or not r:IsA("BasePart") or not hum or hum.Sit or hum.Health <= 0 or me:GetAttribute("Mounted") ~= nil then
		setFlag(false)
		return
	end
	local inAny = false
	current = nil
	for _, p in CollectionService:GetTagged("Updraft") do
		if p:IsA("BasePart") and inside(p, r.Position) then
			inAny = true
			current = p
			break
		end
	end
	setFlag(inAny)
	if not inAny or me:GetAttribute("Gliding") then -- while gliding Glide lifts (it has its own LinearVelocity)
		return
	end
	local st = hum:GetState()
	if st == Enum.HumanoidStateType.Running or st == Enum.HumanoidStateType.RunningNoPhysics or st == Enum.HumanoidStateType.Landed then
		hum:ChangeState(Enum.HumanoidStateType.Freefall) -- detach from the ground, otherwise the walk controller damps the rise
	end
	local v = r.AssemblyLinearVelocity
	local hx, hz = v.X, v.Z
	local c = current
	if c and hum.MoveDirection.Magnitude < 0.1 then -- the player presses nothing: softly toward the column axis (without this one drifts sideways
		local to = c.Position - r.Position -- out of the narrow Cliffs column in ~1 s without reaching the platforms)
		hx, hz = to.X * U.center, to.Z * U.center
	end
	r.AssemblyLinearVelocity = Vector3.new(hx, math.max(v.Y, U.rise), hz)
end

function Updraft.start()
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			setFlag(false)
			warn("[Updraft] " .. tostring(err))
		end
	end)
end

return Updraft
