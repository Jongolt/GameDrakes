--!strict
-- Ascension (spec 05 §6, 02 §3 8:00, 06 §1 item 10). Before this the Remote Ascend had no handler - the Keeper's
-- quest 10 "Ascend" and funnel step 13 never closed. The price - Economy.ascensionCost (5K, x50, x50, then x20), the requirement -
-- Economy.ascensionNeed (I-III any adult, IV+ an elder, from VII two elements of elders, from X three). The reward: +1x to the income
-- (ascension in Economy.nestRate), the sanctuary +sanctuaryPlus. Dragons and coins are not reset (P4 item 7). The nest tint and the title
-- "Ascended N" - with the looks system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Strings = require(Shared:WaitForChild("Strings"))
local Loc = require(Shared:WaitForChild("Loc"))
local Core = Shared:WaitForChild("Core")
local Economy = require(Core:WaitForChild("Economy"))
local Dragons = require(Core:WaitForChild("Dragons"))
local Format = require(Core:WaitForChild("Format"))

local Ascension = {}

local services: { [string]: any } = {}
local B = Config.Balance

-- whether it is possible now: (yes/no, the reason, the price of the next step)
function Ascension.check(data: any): (boolean, string?, number)
	local step = (data.ascension or 0) + 1
	local cost = Economy.ascensionCost(step, B)
	local need = Economy.ascensionNeed(step, B)
	if Dragons.elementsAtStage(data :: any, need.stage) < need.elements then
		return false, if need.stage >= 3 then "needs_elder" elseif need.elements > 1 then "needs_elements" else "needs_adult", cost
	end
	if (data.coins or 0) < cost then
		return false, "not_enough", cost
	end
	return true, nil, cost
end

function Ascension.ascend(player: Player): { ok: boolean, reason: string?, [string]: any }
	local data = services.PlayerData.get(player)
	if not data then
		return { ok = false, reason = "loading" }
	end
	local ok, why, cost = Ascension.check(data)
	if not ok then
		if why == "not_enough" then
			services.Nest.toast(player, Loc.text(Strings.Errors.not_enough, { n = Format.number(cost - math.floor(data.coins or 0)) }))
		else
			local need = Economy.ascensionNeed((data.ascension or 0) + 1, B)
			services.Nest.toast(player, Loc.text(Strings.Errors[why or ""] or tostring(why), { n = need.elements }))
		end
		return { ok = false, reason = why }
	end
	local step = 0
	services.PlayerData.update(player, { "coins", "ascension", "sanctuaryCap" }, function(_, d)
		d.coins = (d.coins or 0) - cost
		d.ascension = (d.ascension or 0) + 1
		d.sanctuaryCap = (d.sanctuaryCap or B.sanctuary.start) + B.ascension.sanctuaryPlus
		step = d.ascension
		return nil
	end)
	services.Nest.addCoins(player, 0, "Ascension") -- leaderboard/counter
	if services.Analytics then
		services.Analytics.coins(player, "Sink", cost, data.coins or 0, "Ascension")
		if step == 1 then
			services.Analytics.onboard(player, "ascension_first")
		end
		services.Analytics.custom(player, "ascension", step)
	end
	if services.Quest then -- 06 §1 item 10 "Ascension"
		services.Quest.event(player, "ascension")
	end
	services.Net.notice(player, { kind = "reward", title = Loc.text(Strings.Weather.ascended, { roman = Format.roman(step), n = step + 1 }), coins = 0, color = "calendar" })
	services.Nest.refresh(player)
	if services.Looks then -- the nest tint and the Ascended title at once
		pcall(services.Looks.refreshNest, player)
		pcall(services.Looks.refreshTag, player)
	end
	return { ok = true, step = step }
end

function Ascension.init(s: { [string]: any })
	services = s
end

function Ascension.start()
	services.Net.handle("Ascend", function(player: Player)
		return Ascension.ascend(player)
	end)
end

return Ascension
