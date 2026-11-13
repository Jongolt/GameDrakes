--!strict
-- 2.6: the social layer on the client (spec 08). The server announcement banner (Notice "announce": rare nest, Epic+ hatch)
-- the "Friends on server: N (+X%)" line under the coin counter, the invite button in the Roblox bar (👋) and the hint card at
-- the inviteAt second of the first session (08 §2): CanSendGameInviteAsync -> PromptGameInvite with LaunchData "party:<UserId>".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SocialService = game:GetService("SocialService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local SocialCore = require(Core:WaitForChild("Social"))
local Economy = require(Core:WaitForChild("Economy"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Social = {}

local me = Players.LocalPlayer
local SC = Config.Social
local T = Strings.Social
local banners: any = nil
local hud: any = nil
local quiet: any = nil -- the invite card - only in idle
local friendsLabel: TextLabel? = nil

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function analytics(name: string)
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, {})
	end
end

-- friend invites (08 §2): only if Roblox allows it for this player
function Social.invite()
	Sounds.play("button")
	local okCan, can = pcall(function()
		return SocialService:CanSendGameInviteAsync(me)
	end)
	if not okCan or not can then
		if banners then
			banners.toast(T.inviteUnavailable)
		end
		return
	end
	local opts = Instance.new("ExperienceInviteOptions")
	opts.LaunchData = SocialCore.launchData(me.UserId)
	opts.PromptMessage = T.invitePrompt
	-- sent - the egg conditions as a toast (10 minutes, the friend's account 60+ days, Premium/verified - Legendary)
	pcall(function()
		SocialService.GameInvitePromptClosed:Once(function(_p, ids)
			if banners and typeof(ids) == "table" and #ids > 0 then
				banners.toast(T.inviteHow)
			end
		end)
	end)
	pcall(function()
		SocialService:PromptGameInvite(me, opts)
	end)
	analytics("invite")
end

-- the hint card (02 §3 7:30): top right, a cross, not a window over everything
local cardShown = false -- the invite card - no more than once per session
local inviteNow = false -- the first delivered trophy of the daily raid - an occasion to invite a friend (the "together" layer)
local function inviteCard()
	if cardShown then
		return
	end
	cardShown = true
	if quiet and quiet.asked then
		quiet.asked() -- a request was shown - the next ones wait askGap
	end
	local g = UIKit.screen("InviteCard", 4)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UIKit.PANEL
	-- the text on the left, Invite, the cross inside the corner
	-- under the Keeper plaque
	-- (UIKit.sideCard), 72 px; mounted and in flight hidden - shown after landing
	f.Size = UDim2.fromOffset(350, 72)
	UIKit.corner(f, 0.12)
	UIKit.stroke(f, UIKit.BORDER, 2)
	UIKit.text(f, T.inviteTitle, UIKit.GOLD, { Position = UDim2.new(0, 10, 0, 3), Size = UDim2.new(0, 180, 0, 18), TextXAlignment = Enum.TextXAlignment.Left })
	UIKit.text(f, T.inviteBonus, UIKit.CREAM, { Position = UDim2.new(0, 10, 0, 20), Size = UDim2.new(0, 180, 0, 50), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left })
	local b = UIKit.button(f, T.invite, UIKit.GREEN, function()
		g:Destroy()
		Social.invite()
	end)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, -54, 0.5, 0)
	b.Size = UDim2.fromOffset(100, 46)
	local x = UIKit.button(f, "X", UIKit.GREY, function()
		g:Destroy()
	end, { minSize = Vector2.new(44, 44) })
	x.AnchorPoint = Vector2.new(1, 0)
	x.Position = UDim2.new(1, -4, 0, 4)
	x.Size = UDim2.fromOffset(44, 44)
	f.Parent = g
	UIKit.sideCard(g, f)
	analytics("invite_shown")
	task.delay(SC.inviteCardSeconds, function()
		if g.Parent then
			g:Destroy()
		end
	end)
end

local friendsPill: TextButton? = nil
local function renderFriends()
	local n = (me:GetAttribute("FriendsOn") :: number?) or 0
	local pct = math.floor(Economy.friendsBonus(n, Config.Balance) * 100 + 0.5)
	if friendsLabel then
		friendsLabel.Text = fmt(T.friendsPill, { pct = pct })
	end
	if friendsPill then
		friendsPill.Visible = n > 0
	end
end

function Social.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	hud = loaded.HUD
	quiet = loaded.Quiet
	-- players under the China policy get no invites - the Invite button is not placed
	local okPol, pol = pcall(function()
		return game:GetService("PolicyService"):GetPolicyInfoForPlayerAsync(me)
	end)
	local china = okPol and typeof(pol) == "table" and (pol :: any).IsSubjectToChinaPolicies == true
	if hud and hud.addTopbarButton then
		if not china then
			pcall(hud.addTopbarButton, "Invite", "👋", Social.invite)
		end
		-- "friends on the server" - a 👥 +20% pill in the Roblox bar, a tap - a toast with the full line
		local ok, b = pcall(hud.addTopbarButton, "Friends", "👥", function()
			local n = (me:GetAttribute("FriendsOn") :: number?) or 0
			if banners then
				banners.toast(fmt(T.friendsOn, { n = n, pct = math.floor(Economy.friendsBonus(n, Config.Balance) * 100 + 0.5) }))
			end
		end)
		if ok and b then
			b.Size = UDim2.fromScale(2, 1)
			local lim = b:FindFirstChildOfClass("UISizeConstraint")
			if lim then
				lim.MaxSize = Vector2.new(Config.UI.topbar.size * 2, Config.UI.topbar.size)
			end
			local icon = b:FindFirstChild("Icon") :: TextLabel?
			if icon then
				icon.AnchorPoint = Vector2.new(0, 0.5)
				icon.Position = UDim2.fromScale(0.08, 0.5)
				icon.Size = UDim2.fromScale(0.36, 0.6)
			end
			friendsLabel = UIKit.text(b, "", Color3.fromRGB(150, 230, 160), { Name = "Pct", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.46, 0.5), Size = UDim2.fromScale(0.48, 0.5) })
			b.Visible = false
			friendsPill = b
		end
	end
end

function Social.start()
	Net.on("announce", function(p)
		if banners and typeof(p.text) == "string" then
			banners.banner(p.text, UIKit.GOLD, if typeof(p.sub) == "string" then p.sub else nil, 3.2)
		end
		Sounds.play("stage_up")
	end)
	me:GetAttributeChangedSignal("FriendsOn"):Connect(renderFriends)
	renderFriends()
	-- the first session: the invite card at the inviteAt second, or right after the first daily raid egg (Social.inviteSoon)
	-- in any session if there are no friends on the server
	local sessions = Store.get("sessions")
	local first = typeof(sessions) == "number" and sessions <= 1
	task.spawn(function()
		while not inviteNow and not (first and ((me:GetAttribute("GiftSec") :: number?) or 0) >= SC.inviteAt) do
			task.wait(2)
		end
		if ((me:GetAttribute("FriendsOn") :: number?) or 0) > 0 then
			return -- a friend is already here - nobody to invite
		end
		do
			if quiet then -- not in the middle of a raid / flight / fight - in idle (first standing, then simply not busy)
				quiet.wait(nil, (Config.Quiet and Config.Quiet.strictFor) or 60)
			end
			local ok, err = pcall(inviteCard)
			if not ok then
				warn("[Social] invite card: " .. tostring(err))
			end
		end
	end)
end

-- invite a friend - +10% coins for each (Balance.friends)
function Social.inviteSoon()
	inviteNow = true
end

return Social
