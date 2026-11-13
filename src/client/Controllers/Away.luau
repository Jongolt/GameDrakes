--!strict
-- 2.5 (spec 06 §9, 05 §8): the "while you were away" card after the loading screen. Data - the profile key `away` (the server computes it
-- on join: Core/Offline): coins in large type, an explanation in small type, "N eggs ready to hatch", "<name> grew to <stage>", the
-- Collect button. No paid offers (P5 item 19). Any closing (Collect, the cross, the dim, "back") = take the coins
-- (Claim "away") so the coins are not lost; the server credits them and sends the coin flight.
-- the NEXT line above Collect - what is waiting and when (Controllers/NextUp: a dragon
-- or egg timer, tomorrow's calendar day, the update), cycling like under the coins; a tap on the update line - the RSVP window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Format = require(Core:WaitForChild("Format"))
local Offline = require(Core:WaitForChild("Offline"))

local UIKit = require(script.Parent:WaitForChild("UIKit"))
local UIStack = require(script.Parent:WaitForChild("UIStack"))
local Net = require(script.Parent:WaitForChild("Net"))
local Store = require(script.Parent:WaitForChild("Store"))

local Away = {}

local R = Strings.Rewards
local MAX_LINES = 3 -- egg and growth lines between the coins and Collect (more overlaps the button); the rest - "and N more"
local gui: ScreenGui? = nil
local nextUp: any = nil
local claimed = false
local ready = false -- the loading screen is gone

local function fill(t: string, v: { [string]: any }): string
	return Loc.fill(t, v, nil, "") -- the template in the player's language, then substitution
end

-- card lines from the profile record (pure text assembly, no interface)
function Away.lines(a: any): { string }
	local out: { string } = {}
	if type(a) ~= "table" then
		return out
	end
	local eggs = tonumber(a.eggs) or 0
	if eggs > 0 then
		table.insert(out, fill(R.awayEggs, { n = eggs, ew = Loc.t(Strings.Loading.eggWord[if eggs == 1 then 1 else 2]) }))
	end
	for _, g in (if type(a.grew) == "table" then a.grew else {}) do
		local name = if type(g.name) == "string" and g.name ~= "" then g.name else R.awayDragon
		table.insert(out, fill(R.awayGrew, { name = name, stage = (Strings.Stage :: any)[g.stage] or "" }))
	end
	if #out > MAX_LINES then
		local more = #out - (MAX_LINES - 1)
		out = table.move(out, 1, MAX_LINES - 1, 1, {})
		table.insert(out, fill(R.awayMore, { n = more }))
	end
	return out
end

local function claim()
	if claimed then
		return
	end
	claimed = true
	task.spawn(function()
		local r = Net.call("Claim", "away")
		if not r.ok then
			claimed = false -- connection failure: the record stays in the profile, the server adds it on the next join
		end
	end)
end

local function destroy()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

local function show()
	local a = Store.get("away")
	if gui or not ready or not Offline.hasNews(a) then
		return
	end
	claimed = false
	local g = UIKit.screen("AwayCard", 9)
	gui = g
	if not UIStack.open("away", function()
		claim()
		destroy()
	end) then
		destroy()
		return
	end
	-- with the NEXT line the card is taller - the news (eggs, growth) do not shrink (P8 frame A2: at 0.66 the lines shrank to ~9 px)
	local hasNext = nextUp ~= nil and nextUp.list ~= nil and #nextUp.list() > 0
	local panel, body = UIKit.panel(g, R.awayTitle, 0.5, if hasNext then 0.78 else 0.66, function()
		UIStack.close("away")
	end)
	panel.Name = "AwayPanel"
	local coins = math.floor(tonumber(a.coins) or 0)
	local y = 0.0
	if coins > 0 then
		local row = Instance.new("Frame")
		row.Name = "CoinsRow"
		row.BackgroundTransparency = 1
		row.Position = UDim2.fromScale(0, y)
		row.Size = UDim2.fromScale(1, 0.22)
		row.Parent = body
		UIKit.coin(row, nil, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.16, 0.5), Size = UDim2.fromScale(0.16, 0.86) })
		UIKit.goldText(row, fill(R.awayCoins, { coins = Format.number(coins) }), { Name = "Coins", Position = UDim2.fromScale(0.3, 0), Size = UDim2.fromScale(0.6, 1), TextXAlignment = Enum.TextXAlignment.Left })
		UIKit.text(body, R.awayNote, UIKit.CREAM, { Name = "Note", Position = UDim2.fromScale(0.05, y + 0.23), Size = UDim2.fromScale(0.9, 0.09), TextTransparency = 0.15 })
		y += 0.35
	end
	-- the button keeps a minimum of 44 px - the lines share the space above it in pixels; the body size is known
	-- only after the first layout, so place() runs on the AbsoluteSize signal (and on screen rotation)
	local labels: { TextLabel } = {}
	for i, line in Away.lines(a) do
		labels[i] = UIKit.text(body, line, UIKit.ONE, { Name = "Line" .. i, Position = UDim2.fromScale(0.05, y), Size = UDim2.fromScale(0.9, 0) })
	end
	-- the NEXT line (a pill like under the coins): one item at a time in a cycle, a tap on the update - RSVP
	local nextRow: TextButton? = nil
	if hasNext then
		local nb = Instance.new("TextButton")
		nb.Name = "Next"
		nb.Text = ""
		nb.AutoButtonColor = false
		nb.BackgroundColor3 = UIKit.PANEL
		nb.BackgroundTransparency = 0.25
		UIKit.corner(nb, 0.5)
		UIKit.text(nb, Loc.t(Strings.Next.label), Color3.fromRGB(150, 200, 255), { Name = "Category", Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.16, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		local line = UIKit.text(nb, "", Color3.fromRGB(235, 235, 240), { Name = "Line", Position = UDim2.fromScale(0.2, 0.1), Size = UDim2.fromScale(0.77, 0.8), TextXAlignment = Enum.TextXAlignment.Left })
		local shownIt: any = nil
		nb.Activated:Connect(function()
			local it = shownIt
			if it and it.kind == "update" and it.eventId and nextUp.rsvpStatus(it.eventId) ~= "Going" then
				nextUp.rsvp(it.eventId, "away")
			end
		end)
		nb.Parent = body
		nextRow = nb
		local mine = gui
		task.spawn(function()
			local rot, untilT = 0, 0
			while gui == mine and nb.Parent do
				local list = nextUp.list()
				if #list == 0 then
					nb.Visible = false
				else
					if os.clock() >= untilT then
						rot = rot % #list + 1
						untilT = os.clock() + nextUp.hold(list[math.clamp(rot, 1, #list)])
					end
					shownIt = list[math.clamp(rot, 1, #list)]
					line.Text = nextUp.text(shownIt)
					nb.Visible = true
				end
				task.wait(0.5)
			end
		end)
	end
	local btn = UIKit.button(body, R.collect, UIKit.GREEN, function()
		UIStack.close("away")
	end)
	btn.Name = "Collect"
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.fromScale(0.5, 1)
	btn.Size = UDim2.fromScale(0.46, 0.22)
	local function place()
		local H = body.AbsoluteSize.Y
		if H < 10 then
			return
		end
		local btnH = math.max(44, 0.22 * H)
		btn.Size = UDim2.new(0.46, 0, 0, btnH)
		local top, bottom = y * H, H - btnH - 4
		if nextRow then -- the NEXT line right above Collect, the news above it
			local nh = math.max(22, 0.12 * H)
			nextRow.Size = UDim2.new(0.86, 0, 0, nh)
			nextRow.AnchorPoint = Vector2.new(0.5, 0)
			nextRow.Position = UDim2.new(0.5, 0, 0, bottom - nh - 2)
			bottom -= nh + 6
		end
		local step = math.min(0.13 * H, (bottom - top) / math.max(#labels, 1))
		for i, l in labels do
			l.Position = UDim2.new(0.05, 0, 0, top + (i - 1) * step)
			l.Size = UDim2.new(0.9, 0, 0, step * 0.92)
		end
	end
	body:GetPropertyChangedSignal("AbsoluteSize"):Connect(place)
	place()
end

function Away.init(_snapshot: any, loaded: any)
	nextUp = loaded.NextUp
end

function Away.start()
	Store.on("away", function(a)
		if gui and not Offline.hasNews(a) then -- coins taken (Claim) - close
			UIStack.close("away")
		elseif not gui then
			show()
		end
	end)
	task.spawn(function()
		local pg = Players.LocalPlayer:WaitForChild("PlayerGui")
		local t0 = os.clock()
		while pg:FindFirstChild("LoadingScreen") and os.clock() - t0 < 60 do -- the loading screen (ReplicatedFirst) is still on
			task.wait(0.25)
		end
		task.wait(1.2) -- the world gets a moment to appear before the card
		ready = true
		show()
	end)
end

-- probe (ClientDebug): what is on the card right now
function Away.state(): string
	local a = Store.get("away")
	local nb = gui and gui:FindFirstChild("Next", true)
	local nl = nb and nb:FindFirstChild("Line")
	return string.format("open=%s news=%s coins=%s lines=%s next=%s", tostring(gui ~= nil), tostring(Offline.hasNews(a)), tostring(type(a) == "table" and a.coins), table.concat(Away.lines(a), " | "),
		if nb and (nb :: any).Visible and nl then (nl :: any).Text else "-")
end

return Away
