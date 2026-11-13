--!strict
-- the pass buttons at the coin counter. In Tame An Animal
-- Auto Tame / Auto Command / Teleport stand right on the screen with the Robux icon, a tap - the "what you get" card (Controllers/PassChips).
-- Pure logic: which buttons are visible. Not earlier than Shop.robuxAllowed (3:00 of the first session), not riding (menus do not open in flight,
-- 02 §1), only when the nest already brings coins (the income passes before the first dragon in the nest are pointless), a bought one is not shown.
-- blocked - a Roblox window is on the screen (the favorite): no buttons, so the card does not open together with it.
-- The placement (layout): all the buttons to the right of the pill in a row. at the top left on PC the Roblox chat window (CoreGui, above ours) -
-- a click on a button on the left went into the chat; at the top right on PC the player list (~240 px). The API does not give the chat and list sizes (zeros), so
-- a button that does not fit the screen or touches a forbidden zone is not shown at all (it can be bought in the shop) - no overlaps.
-- The test: tests/passchips_spec.luau.
local Shop = require("./Shop")

local PassChips = {}

export type Ctx = { robuxOk: boolean, mounted: boolean, rate: number, blocked: boolean? }

-- the SKU keys of the visible buttons in the order cfg.list; data - the player's profile (owned), cfg - Config.UI.passChips
function PassChips.visible(data: any, ctx: Ctx, cfg: any): { string }
	local out: { string } = {}
	if typeof(cfg) ~= "table" or cfg.on ~= true or not ctx.robuxOk or ctx.mounted or ctx.blocked or ctx.rate <= 0 then
		return out
	end
	for _, c in cfg.list or {} do
		local sku = Shop.get(c.key)
		if sku and sku.kind == "pass" and not Shop.owned(data, sku) then
			table.insert(out, c.key)
		end
	end
	return out
end

export type Rect = { number } -- { x0, y0, x1, y1 } in HUD px

local function hit(a: Rect, b: Rect): boolean
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end

-- the button places keys (in order) to the right of the pill: the height - the pill, not lower than cfg.minPx, the top not higher than 2 px; the width = the height * cfg.aspect;
-- the gap cfg.gap. A button that goes off the screen (W, H) or touches a zone of zones is not placed, and all after it too (they are to the right)
function PassChips.layout(pill: Rect, W: number, H: number, keys: { string }, cfg: any, zones: { Rect }): { [string]: Rect }
	local out: { [string]: Rect } = {}
	local h = math.max(cfg.minPx, pill[4] - pill[2])
	local w = math.floor(h * cfg.aspect)
	local top = math.max((pill[2] + pill[4]) / 2 - h / 2, 2)
	local x = pill[3] + cfg.gap
	for _, key in keys do
		local r = { x, top, x + w, top + h }
		if r[3] > W - 2 or r[4] > H then
			break
		end
		for _, z in zones do
			if hit(r, z) then
				return out
			end
		end
		out[key] = r
		x += w + cfg.gap
	end
	return out
end

-- the forbidden Roblox CoreGui zones (HUD px): on PC (without touch) - the player list at the top right of width cfg.playerListW
function PassChips.zones(W: number, H: number, touch: boolean, playerList: boolean, cfg: any): { Rect }
	local z: { Rect } = {}
	if playerList and not touch then
		table.insert(z, { W - cfg.playerListW, 0, W, H * 0.5 })
	end
	return z
end

return PassChips
