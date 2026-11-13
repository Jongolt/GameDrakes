--!strict
-- the Index on the client (spec 03 §5; craft/04 §7.12 Index: silhouettes of the undiscovered, bars with a reward, Claim).
-- The `Index N%` plaque on the left under Dragons (opens the book tab), a toast for a new entry, "Meadow set 2/10" at the Keeper's gift.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local IndexCore = require(Shared:WaitForChild("Core"):WaitForChild("Index"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local Store = require(script.Parent:WaitForChild("Store"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))

local Index = {}

local banners: any = nil
local menu: any = nil
local button: TextButton? = nil

IndexCore.setup(Config.Elements, Config.Rarities)

local function fmt(s: string, t: { [string]: any }): string
	return Loc.fill(s, t, nil, "") -- the template in the player's language, then substitution
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function renderButton()
	local b = button
	if not b then
		return
	end
	local word = b:FindFirstChild("Word")
	if word and word:IsA("TextLabel") then
		local pct = math.floor(IndexCore.pct(Store.get("index")) * 100 + 0.5)
		word.Text = fmt(Strings.Index.button, { pct = pct })
	end
end

local function onNew(p: any)
	local key = tostring(p.key or "")
	local el, r = string.match(key, "^(%a+):(%a+)$")
	local name = if el and r then IndexCore.display(el) .. " " .. r else key
	if banners then
		banners.toast(fmt(Strings.Index.newEntry, { name = name, k = p.count or 0, n = p.total or IndexCore.total() }))
	end
	Sounds.play("egg_pick")
end

function Index.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
	menu = loaded.Menu
	local hud = loaded.HUD
	if hud and hud.addMenuButton then
		button = hud.addMenuButton("left", Strings.HUD.index, rgb(Config.UI.tabs.index), function()
			if menu and menu.open then
				menu.open("index")
			end
		end, UIKit.ICON.index)
	end
end

function Index.start()
	renderButton()
	Store.on("index", renderButton)
	Net.on("index", onNew)
end

return Index
