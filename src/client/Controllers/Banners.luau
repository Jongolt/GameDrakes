--!strict
-- Banners and toasts (02 §1-2): a toast is one line at the bottom center (server refusal, hint), a banner is large at the top
-- center for 2-3 s (hatch: "Common Ember" in the rarity color and "1 in N"; growth: "Your dragon grew up! Ride it.").
-- The source is a Notice from the server; texts only from Strings.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Config = require(Shared:WaitForChild("Config"))
local HatchFx = require(Shared:WaitForChild("Core"):WaitForChild("HatchFx")) -- the result after the crack of the own scene

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Net = require(script.Parent:WaitForChild("Net"))
local Store = require(script.Parent:WaitForChild("Store")) -- whether the companion grew

local Banners = {}

local gui: ScreenGui? = nil
local toastLabel: TextLabel? = nil
local bannerFrame: Frame? = nil
local toastSeq, bannerSeq = 0, 0
-- while the hatch scene plays, other banners and toasts wait (P8 frames: "Done! Keeper 1/15" and the Index toast over the egg)
local holdBanner, holdToast = 0, 0
-- held banners queue one after another, not
-- all at once at the end of the scene (only the last one was visible)
local heldNext = 0

local function title(s: string): string
	return string.upper(string.sub(s, 1, 1)) .. string.sub(s, 2)
end

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

function Banners.toast(text: string)
	local t = toastLabel
	if not t then
		return
	end
	local wait = holdToast - os.clock()
	if wait > 0 then
		task.delay(wait, Banners.toast, text)
		return
	end
	toastSeq += 1
	local my = toastSeq
	t.Text = text
	t.Visible = true
	t.TextTransparency = 0
	task.delay(2.6, function()
		if my == toastSeq then
			TweenService:Create(t, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
			task.wait(0.3)
			if my == toastSeq then
				t.Visible = false
			end
		end
	end)
end

-- (P8 F4 x6: the golden nest banner was covered by "Your dragon can fly!" / "grew into a Teen" in the same second - one frame
-- the last one wins): hold the other banners for seconds s - they queue up (as after the hatch scene)
function Banners.hold(seconds: number)
	local now = os.clock()
	holdBanner = math.max(holdBanner, now + seconds)
	heldNext = math.max(heldNext, holdBanner)
end

-- large at the top: line 1 (colored), line 2 (white), seconds; force - the hatch result (bypasses the hold)
function Banners.banner(line1: string, color: Color3?, line2: string?, seconds: number?, force: boolean?)
	local f = bannerFrame
	if not f then
		return
	end
	local now = os.clock()
	if holdBanner - now > 0 and not force then
		local at = math.max(holdBanner, heldNext)
		heldNext = at + (seconds or 2.5)
		task.delay(at - now, Banners.banner, line1, color, line2, seconds)
		return
	end
	bannerSeq += 1
	local my = bannerSeq
	local l1 = f:FindFirstChild("L1") :: TextLabel
	local l2 = f:FindFirstChild("L2") :: TextLabel
	l1.Text = line1
	l1.TextColor3 = color or Color3.new(1, 1, 1)
	l2.Text = line2 or ""
	f.Visible = true
	UIKit.bannerUntil = os.clock() + (seconds or 2.5) -- the step banner and the Keeper's line give way (StepBanner, Quests)
	local sc = f:FindFirstChildOfClass("UIScale") :: UIScale
	sc.Scale = 0.6
	TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(seconds or 2.5, function()
		if my == bannerSeq then
			f.Visible = false
		end
	end)
end

function Banners.init(_snapshot: any, _loaded: any)
	local g = UIKit.screen("Banners", 5)
	gui = g
	toastLabel = UIKit.text(g, "", Color3.fromRGB(255, 240, 190), {
		Name = "Toast",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.8),
		Size = UDim2.fromScale(0.6, 0.06),
		Visible = false,
	})
	local f = Instance.new("Frame")
	f.Name = "Banner"
	f.BackgroundTransparency = 1
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.fromScale(0.5, 0.2) -- below the step banner (0.108-0.183)
	f.Size = UDim2.fromScale(0.7, 0.16)
	f.Visible = false
	Instance.new("UIScale").Parent = f
	UIKit.text(f, "", nil, { Name = "L1", Size = UDim2.fromScale(1, 0.62) })
	UIKit.text(f, "", nil, { Name = "L2", Size = UDim2.fromScale(1, 0.36), Position = UDim2.fromScale(0, 0.64) })
	f.Parent = g
	bannerFrame = f
end

function Banners.start()
	Net.on("toast", function(p)
		if typeof(p.text) == "string" then
			Banners.toast(p.text)
		end
	end)
	-- no "Warm egg!" toast: StepBanner holds the step line (P10), a duplicate under the banner read as chaos
	Net.on("hatch", function(p)
		local el = if typeof(p.variant) == "string" then fmt(Strings.LiveOps.variant, { label = p.variant, element = title(p.element) }) else title(p.element) -- dragon names are not translated -- 2.9: "Glacier Frost"
		local line = fmt(Strings.Hatch.result, { rarity = Loc.t(Strings.Rarity[p.rarity] or p.rarity), element = el })
		local plan = HatchFx.plan(tostring(p.rarity), if typeof(p.n) == "number" then p.n else nil, Config.UI.hatchScene)
		local now = os.clock()
		holdBanner = math.max(holdBanner, now + plan.t.bannerAt + Config.UI.hatchScene.bannerHold)
		holdToast = math.max(holdToast, now + plan.total)
		task.delay(plan.t.bannerAt, function() -- after the crack and the flash of the scene (HatchScene)
			Banners.banner(line, UIKit.RARITY[p.rarity], p.oneIn, 3, true)
		end)
	end)
	-- on joining after an absence the growths arrive in a batch - the second banner wiped the first (the adult
	-- "can fly" was lost under "Ride it!"). Wait 0.4 s and show one - of the highest stage.
	local pending: any = nil
	local function showStage(p: any)
		if p.stage == 1 then
			-- grew in the nest, not on the shoulder - "Take it out and ride" instead of "Ride it!"
			local inNest = p.uid ~= nil and Store.get("companion") ~= p.uid
			Banners.banner(Strings.Hints.grewUp, UIKit.GOLD, if inNest then Strings.Hints.grewInNest else Strings.Hints.grewUpSub, 2.5) -- 1.9: «Ride it!» (02 §2)
		elseif p.stage == 2 then
			Banners.banner(Strings.Hints.canFly, UIKit.GOLD, Strings.Hints.canFlySub, 3)
		else
			Banners.banner(fmt(Strings.Loop.stageUp, { name = p.name, stage = Loc.t(Strings.Stage[p.stage]) }), UIKit.GOLD, nil, 2.5)
		end
	end
	Net.on("stage_up", function(p)
		if pending then
			if (p.stage or 0) > (pending.stage or 0) then
				pending = p
			end
			return
		end
		pending = p
		task.delay(0.4, function()
			local q = pending
			pending = nil
			if q then
				showStage(q)
			end
		end)
	end)
end

return Banners
