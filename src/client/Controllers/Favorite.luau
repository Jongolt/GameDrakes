--!strict
-- the Roblox "favorite" prompt once per account lifetime - after the first flight,
-- when the player dismounted (in the air the prompt would seize the controls). No reward and no own promises (Core/Favorite).
-- Called only on the client and only in the live game - in Studio there is no prompt: PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset,
-- true) (DevForum 2717433). The server sets onboarding.favAsked from the fav_prompt analytics; the prompt result - fav_done (Analytics.custom).
-- after the prompt - the community goal banner "At N likes, every rider gets a new code"
-- (Config.LiveOps.likeGoal; a code for everyone, no like check - Content.Codes). Once, like the prompt; no prompt in Studio - the banner at once.
-- the prompt and the banner not over our windows -
-- while any menu/card is open (UIStack), they wait for it to close; while the Roblox prompt is on screen - Favorite.busy() (pass buttons hide).

local AvatarEditorService = game:GetService("AvatarEditorService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local FavCore = require(Shared:WaitForChild("Core"):WaitForChild("Favorite"))

local Store = require(script.Parent:WaitForChild("Store"))
local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))

local Favorite = {}

local me = Players.LocalPlayer
local landedAt: number? = nil
local asked = false
local seq = 0 -- landing/takeoff number - the delayed check of a past landing does not multiply (P8: three 1 s chains while the card was open)
local goalWaiting = false
local banners: any = nil
local quiet: any = nil -- the "favorite" prompt - only in idle
local dueSince: number? = nil
local goalShown = false
local promptOpen = false -- the Roblox "favorite" prompt is on screen

local activeAt = -math.huge -- the last action of the prompt and the goal banner - "tomorrow" (Gifts) waits for silence after them

-- the Roblox prompt is on screen right now: other windows and pass buttons wait (Controllers/PassChips)
function Favorite.busy(): boolean
	return promptOpen
end

-- the prompt is still ahead: the player flew, was not asked and dismounted this session - "tomorrow" (Gifts) yields the turn to it
function Favorite.pending(): boolean
	if asked or landedAt == nil or not (Config.FavPrompt and Config.FavPrompt.on) then
		return false
	end
	local o = Store.get("onboarding")
	return typeof(o) == "table" and o.flew == true and o.favAsked == nil
end

-- how many seconds the "favorite" prompt and the like goal banner have been silent (0 - the prompt is open or the banner waits for the menu)
function Favorite.quietFor(): number
	if promptOpen or goalWaiting then
		return 0
	end
	return os.clock() - activeAt
end

local function analytics(name: string, fields: { [string]: any })
	local folder = ReplicatedStorage:FindFirstChild("Remotes")
	local r = folder and folder:FindFirstChild("Analytics")
	if r and r:IsA("RemoteEvent") then
		r:FireServer(name, fields)
	end
end

local function likeGoal()
	local n = Config.LiveOps.likeGoal
	if goalShown or not n or not banners then
		return
	end
	if UIStack.depth() > 0 then -- our window is open - the banner after it (one waiting chain)
		if not goalWaiting then
			goalWaiting = true
			task.delay(1, function()
				goalWaiting = false
				likeGoal()
			end)
		end
		return
	end
	goalShown = true
	activeAt = os.clock() + Config.FavPrompt.goalSeconds
	banners.banner(Loc.t(Strings.LiveOps.likeAsk), UIKit.GOLD, Loc.fill(Strings.LiveOps.likeGoal, { n = n }, nil, ""), Config.FavPrompt.goalSeconds)
end

local glowSeenAt: number? = nil -- when a glowing dragon hatched on this client

local function check(my: number)
	if asked or my ~= seq then
		return
	end
	local mounted = me:GetAttribute("Mounted") ~= nil
	if not FavCore.due(Store.get("onboarding"), mounted, landedAt, os.clock(), Config.FavPrompt, glowSeenAt) then
		return
	end
	if UIStack.depth() > 0 then -- our window is open (pass card, book, dragon card) - we ask when they close it
		task.delay(1, check, my)
		return
	end
	-- wait for silence - the first
	-- Config.Quiet.strictFor s strictly (standing still), then softly (not busy)
	dueSince = dueSince or os.clock()
	local strictFor = (Config.Quiet and Config.Quiet.strictFor) or 60
	if quiet and not quiet.ok(os.clock() - (dueSince :: number) < strictFor) then
		task.delay(1, check, my)
		return
	end
	asked = true
	analytics("fav_prompt", {})
	if RunService:IsStudio() then
		if quiet and quiet.asked then
			quiet.asked() -- in Studio it counts as a request too
		end
		task.delay(1, likeGoal) -- no prompt in Studio: the P8 probe sees fav_prompt, onboarding.favAsked and the goal banner
		return
	end
	promptOpen = true
	activeAt = os.clock()
	local ok = pcall(function()
		if quiet and quiet.asked then
			quiet.asked() -- a request was shown - the next ones wait askGap
		end
		AvatarEditorService:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if not ok then
		promptOpen = false
	end
	-- if PromptSetFavoriteCompleted never comes (focus loss, platform failure), promptOpen would hang true
	-- until the end of the session and Favorite.busy() would hide the pass buttons by the coins without a single log - a timer safeguard
	task.delay(15, function()
		if promptOpen then
			promptOpen = false
			warn("[Favorite] prompt timeout: the favorite prompt did not answer within 15 s")
		end
	end)
end

function Favorite.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	quiet = loaded.Quiet
	local F = Config.FavPrompt
	if not (F and F.on) then
		return
	end
	AvatarEditorService.PromptSetFavoriteCompleted:Connect(function(result: Enum.AvatarPromptResult)
		promptOpen = false
		activeAt = os.clock()
		analytics("fav_done", { result = result.Name })
		task.delay(0.6, likeGoal) -- the Roblox prompt closed - the banner is not under it
	end)
	-- only a landing (dismounted) starts the check: on joining the game there is no prompt;
	-- the moment - the golden egg was put on the pedestal (glowEgg.readyAt > 0, day 1, the peak of the win), after F.delay s, standing
	local function onGlow()
		local ge = Store.get("glowEgg")
		if typeof(ge) == "table" and (tonumber(ge.readyAt) or 0) > 0 and glowSeenAt == nil then
			glowSeenAt = os.clock()
			seq += 1
			task.delay(F.delay + 0.1, check, seq)
		end
	end
	Store.on("glowEgg", onGlow)
	task.defer(onGlow)
	me:GetAttributeChangedSignal("Mounted"):Connect(function()
		seq += 1
		if me:GetAttribute("Mounted") == nil then
			landedAt = os.clock()
			task.delay(F.delay + 0.1, check, seq)
		else
			landedAt = nil
		end
	end)
end

return Favorite
