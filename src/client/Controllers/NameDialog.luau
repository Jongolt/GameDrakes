--!strict
-- The name window (02 §2, 0:13-0:18): a field with a suggested name and two buttons Done / Skip; after a hatch it closes by itself
-- after 5 s if the player has not started typing. The name goes through the NameDragon call, the server filters (TextService) and answers
-- bad_name - the button shakes, a toast. The same dialog is opened by the dragon card (Rename, no auto-close).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Net = require(script.Parent:WaitForChild("Net"))
local Sounds = require(script.Parent:WaitForChild("Sounds"))
local Store = require(script.Parent:WaitForChild("Store"))

local NameDialog = {}

local banners: any = nil
local gui: ScreenGui? = nil
local seq = 0
local renamedAt: number? = nil -- the time of the last successful name (the Config.Names.renameCooldown limit, the server checks by itself)

-- how many seconds the name still cannot be changed (0 - allowed); HatchScene does not open the window after a hatch while > 0
function NameDialog.cooldownLeft(): number
	if not renamedAt then
		return 0
	end
	return math.max(0, (Config.Names.renameCooldown or 60) - (os.clock() - (renamedAt :: number)))
end

local function trim(s: string): string
	return (string.gsub(s, "^%s+", ""):gsub("%s+$", ""))
end

local function destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

-- opts.auto - seconds until auto-close without input; opts.onDone(name) - after success
function NameDialog.open(uid: string, current: string, opts: { auto: number?, onDone: ((string) -> ())? }?)
	local o = opts or {}
	if gui then
		return
	end
	seq += 1
	local my = seq
	local g = UIKit.screen("NameDialog", 8)
	gui = g
	local function close()
		if my == seq then
			destroy()
		end
	end
	if not UIStack.open("name", close) then
		destroy()
		return
	end
	local panel, body = UIKit.panel(g, Strings.Hatch.named, 0.5, 0.52, function()
		UIStack.close("name")
	end)
	panel.Name = "NamePanel"
	local box = Instance.new("TextBox")
	box.Name = "Field"
	box.Text = current
	box.PlaceholderText = current
	box.ClearTextOnFocus = false
	box.Font = UIKit.FONT
	box.TextScaled = true
	box.TextColor3 = Color3.new(1, 1, 1)
	box.BackgroundColor3 = UIKit.PANEL_LIGHT
	box.Position = UDim2.fromScale(0.08, 0.08)
	box.Size = UDim2.fromScale(0.66, 0.36)
	UIKit.corner(box, 0.25)
	local st = Instance.new("UIStroke")
	st.Color = UIKit.GOLD
	st.Thickness = 2
	st.Parent = box
	box.Parent = body
	local typed = false
	box.Focused:Connect(function()
		typed = true
	end)
	-- a random name by element
	local dice = UIKit.button(body, UIKit.ICON.dice, UIKit.PANEL_LIGHT, function()
		local dragons = Store.get("dragons")
		local rec = typeof(dragons) == "table" and dragons[uid]
		local pool = (rec and (Strings.Names :: any)[rec.element]) or Strings.Names.any
		local all = table.clone(pool)
		for _, n in Strings.Names.any do
			table.insert(all, n)
		end
		local pick = all[math.random(1, #all)]
		if pick == box.Text and #all > 1 then
			pick = all[math.random(1, #all)]
		end
		box.Text = pick
		typed = true
	end, { minSize = Vector2.new(44, 44) })
	dice.Name = "Dice"
	dice.Position = UDim2.fromScale(0.77, 0.08)
	dice.Size = UDim2.fromScale(0.15, 0.36)
	local dar = Instance.new("UIAspectRatioConstraint")
	dar.AspectRatio = 1
	dar.Parent = dice
	box:GetPropertyChangedSignal("Text"):Connect(function()
		typed = true
		if #box.Text > Config.Dragon.nameMaxLength then
			box.Text = string.sub(box.Text, 1, Config.Dragon.nameMaxLength)
		end
	end)
	local function submit(btn: TextButton)
		local text = trim(box.Text)
		if text == "" or text == current then
			UIStack.close("name")
			return
		end
		local reply = Net.call("NameDragon", uid, text)
		if reply.ok then
			renamedAt = os.clock()
			Sounds.play("quest_done")
			UIStack.close("name")
			if o.onDone then
				o.onDone(text)
			end
		else
			UIKit.shake(btn)
			if banners then
				if reply.reason == "name_cooldown" then
					banners.toast(Loc.fill(Strings.Errors.name_cooldown, { n = reply.n or 60 }))
				else
					banners.toast(Strings.Errors.bad_name)
				end
			end
		end
	end
	local done = UIKit.button(body, Strings.Hatch.done, UIKit.GREEN, submit)
	done.Position = UDim2.fromScale(0.08, 0.56)
	done.Size = UDim2.fromScale(0.4, 0.34)
	local skip = UIKit.button(body, Strings.Hatch.skip, UIKit.GREY, function()
		UIStack.close("name")
	end)
	skip.Position = UDim2.fromScale(0.52, 0.56)
	skip.Size = UDim2.fromScale(0.4, 0.34)
	box.ReturnPressedFromOnScreenKeyboard:Connect(function()
		submit(done)
	end)
	box.FocusLost:Connect(function(enter)
		if enter then
			submit(done)
		end
	end)
	if o.auto then
		task.delay(o.auto, function()
			if my == seq and gui and not typed then
				UIStack.close("name")
			end
		end)
	end
end

function NameDialog.init(_snapshot: any, loaded: any)
	banners = loaded.Banners
end

return NameDialog
