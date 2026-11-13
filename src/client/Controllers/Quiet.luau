--!strict
-- THE SILENCE GATE for request and offer windows (notifications, "tomorrow", "favorite", friend invite): they must pop up only
-- when the player is idle. busy - what the player
-- is doing (an egg in hand, a raid, mounted, flight, combat, hatching, a large banner, our window); ok(strict) - quiet, and with strict also standing
-- still for idleFor s; wait - wait for silence: first strictFor s strictly (standing), then softly (simply not busy)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Store = require(script.Parent:WaitForChild("Store"))

local Quiet = {}
local me = Players.LocalPlayer
local Q = (Config :: any).Quiet or {}
local idleSince = os.clock()
local loadedRef: any = nil

function Quiet.busy(): string?
	if UIKit.worldUiHidden or UIStack.depth() > 0 then
		return "ui"
	end
	if me:GetAttribute("Flying") == true then
		return "flying"
	end
	if me:GetAttribute("Mounted") ~= nil then
		return "mounted"
	end
	if me:GetAttribute("Fight") ~= nil or me:GetAttribute("Gloom_meadow") ~= nil or me:GetAttribute("Gloom_sky") ~= nil then
		return "fight"
	end
	if me:GetAttribute("GlowRaid") ~= nil or me:GetAttribute("GlowChase") == true or me:GetAttribute("GlowWait") ~= nil then
		return "raid"
	end
	local eggs = Store.get("eggs")
	if typeof(eggs) == "table" and eggs.carry ~= nil then
		return "carry"
	end
	if os.clock() < ((UIKit :: any).bannerUntil or 0) + (Q.bannerGap or 1) then
		return "banner"
	end
	local hs = loadedRef and loadedRef.HatchScene
	if hs and hs.busy and hs.busy() then
		return "hatch"
	end
	return nil
end

-- how many seconds standing still
function Quiet.idleFor(): number
	return os.clock() - idleSince
end

local lastAskAt = -1e9 -- when the last request was shown (like, friends, group, notifications, pass chips)

-- a request was shown - the next one no sooner than askGap s
function Quiet.asked()
	lastAskAt = os.clock()
end

function Quiet.ok(strict: boolean?): boolean
	if Quiet.busy() ~= nil then
		return false
	end
	if os.clock() - lastAskAt < (Q.askGap or 0) then
		return false -- one request at a time, with a gap
	end
	if Q.strictAlways then
		strict = true -- only when stopped; there is no soft mode
	end
	return not strict or Quiet.idleFor() >= (Q.idleFor or 3)
end

-- wait for silence: the first strictFor s - only standing still, then - simply not busy; maxWait nil - wait as long as needed
function Quiet.wait(maxWait: number?, strictFor: number?): boolean
	local t0 = os.clock()
	local sf = strictFor or Q.strictFor or 60
	while true do
		local t = os.clock() - t0
		if Quiet.ok(t < sf) then
			return true
		end
		if maxWait and t > maxWait then
			return false
		end
		task.wait(0.5)
	end
end

function Quiet.init(_snapshot: any, loaded: any)
	loadedRef = loaded
end

function Quiet.start()
	task.spawn(function()
		while true do
			task.wait(0.25)
			local ch = me.Character
			local r = ch and ch:FindFirstChild("HumanoidRootPart")
			if r and r:IsA("BasePart") then
				local v = r.AssemblyLinearVelocity
				if Vector3.new(v.X, 0, v.Z).Magnitude > (Q.speed or 2) then
					idleSince = os.clock()
				end
			else
				idleSince = os.clock()
			end
		end
	end)
end

return Quiet
