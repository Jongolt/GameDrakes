--!strict
-- The dragon look (03 §1, §7; spec 1.2 P3; task 1.6): pure computations without Roblox API - the height by stage and size,
-- the stand color, the eye color, the body (a texture or a flat color), the overlay element signs and the caption. DragonVisuals
-- turns this into parts; the luau CLI tests check the numbers and the completeness over all elements and stages.

local Config = require("./../Config")
local Content = require("./../Content")

local DragonLook = {}

export type Rgb = { number }
export type Overlay = {
	name: string,
	at: string, -- the attachment name: Crest | Back | TailTip | WingL | WingR
	shape: string, -- "block" | "wedge" | "ellipsoid" | "ball"
	offset: { number }, -- the offset from the attachment in shares of the model height (x, y, z)
	size: { number }, -- the size in shares of the model height
	rot: { number }, -- the rotation (degrees) around X, Y, Z
	color: Rgb,
	neon: boolean,
	transparency: number?,
}

local D = Config.Dragon

-- The stage height with the size (03 §1.2: Big x1.35 and Huge x1.7 act for H/J always, for A/E - only in the nest)
function DragonLook.height(stage: number, size: string?, inNest: boolean?): number
	local st = D.stages[stage + 1]
	assert(st, "bad stage " .. tostring(stage))
	local h = st.height
	local v = Config.Balance.variants
	local mult = 1
	if size == "huge" then
		mult = v.huge.scale
	elseif size == "big" then
		mult = v.big.scale
	end
	if stage >= 2 and inNest == false then
		mult = 1
	end
	return h * mult
end

-- The slot stand: a contrast color to the element (04 §10)
function DragonLook.padColor(element: string): Rgb
	local el = Content.Elements[element]
	return if el then el.pad else { 160, 144, 124 }
end

function DragonLook.eyeColor(element: string): Rgb
	local el = Content.Elements[element]
	return if el then el.color2 else { 255, 255, 255 }
end

-- The body: nil = keep the model texture; otherwise the flat element color (J/A/E on the Ember mesh until own textures)
function DragonLook.bodyColor(element: string, stage: number): Rgb?
	if element == "ember" then
		return nil
	end
	if D.flatColorStages[stage] then
		local el = Content.Elements[element]
		return if el then el.color else nil
	end
	return nil
end

-- The stage attachments: shares of the extents (x of the width from the center, y of the height from the sole, z of the length from the center; the snout at -Z)
function DragonLook.attachments(stage: number): { [string]: { number } }
	return D.attach[stage] or D.attach[0]
end

-- The overlay element signs (03 §1.1): 2-3 shapes per element at the attachments Crest / Back / TailTip / WingL / WingR.
-- Ember - the flame crest is already in the mesh (v2 seed 1), no overlays. The sizes in shares of the model height.
function DragonLook.overlays(element: string, stage: number): { Overlay }
	if not D.overlays then
		return {}
	end
	local el = Content.Elements[element]
	if not el then
		return {}
	end
	local c1, c2 = el.color, el.color2
	local out: { Overlay } = {}
	local function add(o: Overlay)
		table.insert(out, o)
	end
	if element == "frost" then
		-- ice crystals on the back: three rhombi (a cube on an edge) along the spine
		for i, dz in { -0.14, 0.0, 0.14 } do
			local s = if i == 2 then 0.22 else 0.17
			add({ name = "Crystal" .. i, at = "Back", shape = "block", offset = { 0, s * 0.2, dz }, size = { s * 0.5, s, s * 0.5 }, rot = { 0, 45, 0 }, color = c1, neon = false, transparency = 0.1 })
		end
		add({ name = "CrystalTip", at = "Crest", shape = "block", offset = { 0, 0.02, 0 }, size = { 0.06, 0.11, 0.06 }, rot = { 0, 45, 0 }, color = c2, neon = false, transparency = 0.1 }) -- 0.2 of the height looked like a pillar
	elseif element == "moss" then
		-- leaves on the head and the tail
		add({ name = "LeafL", at = "Crest", shape = "ellipsoid", offset = { -0.07, 0.05, 0 }, size = { 0.16, 0.05, 0.3 }, rot = { 0, 0, 30 }, color = c2, neon = false })
		add({ name = "LeafR", at = "Crest", shape = "ellipsoid", offset = { 0.07, 0.05, 0 }, size = { 0.16, 0.05, 0.3 }, rot = { 0, 0, -30 }, color = c2, neon = false })
		add({ name = "LeafTail", at = "TailTip", shape = "ellipsoid", offset = { 0, 0.08, 0.02 }, size = { 0.14, 0.05, 0.28 }, rot = { 20, 0, 0 }, color = c1, neon = false })
	elseif element == "tide" then
		-- fin crests along the spine: thin semi-transparent wedges
		for i, dz in { -0.16, -0.02, 0.12 } do
			add({ name = "Fin" .. i, at = "Back", shape = "wedge", offset = { 0, 0.1, dz }, size = { 0.04, 0.26, 0.16 }, rot = { 0, 0, 0 }, color = c2, neon = false, transparency = 0.25 })
		end
	elseif element == "storm" then
		-- lightning horns: two glowing yellow slats, tilted outward; half the old size, only the tip glows
		add({ name = "HornL", at = "Crest", shape = "block", offset = { -0.08, 0.07, 0 }, size = { 0.04, 0.17, 0.04 }, rot = { 0, 0, 28 }, color = c2, neon = false })
		add({ name = "HornR", at = "Crest", shape = "block", offset = { 0.08, 0.07, 0 }, size = { 0.04, 0.17, 0.04 }, rot = { 0, 0, -28 }, color = c2, neon = false })
		add({ name = "HornL2", at = "Crest", shape = "block", offset = { -0.13, 0.16, 0 }, size = { 0.035, 0.1, 0.035 }, rot = { 0, 0, -20 }, color = c2, neon = true })
		add({ name = "HornR2", at = "Crest", shape = "block", offset = { 0.13, 0.16, 0 }, size = { 0.035, 0.1, 0.035 }, rot = { 0, 0, 20 }, color = c2, neon = true })
	elseif element == "dusk" then
		-- stars on the wings (a hatchling has no wings - on the back) and a night body
		local wingAt = if stage == 0 then { "Back", "Back" } else { "WingL", "WingR" }
		for i = 1, 2 do
			for k, dz in { -0.08, 0.06 } do
				local dx = if stage == 0 then (if i == 1 then -0.08 else 0.08) else (if i == 1 then -0.06 else 0.06)
				add({ name = "Star" .. i .. k, at = wingAt[i], shape = "ball", offset = { dx, 0.03, dz }, size = { 0.07, 0.07, 0.07 }, rot = { 0, 0, 0 }, color = c2, neon = true })
			end
		end
	end
	return out
end

-- The caption above the dragon: the name and the rarity (the income is added by IncomeService, 1.7)
-- publicNames = false (12 §1 Config.Names): the caption is visible to all - the player's name is replaced with the element name
function DragonLook.label(d: { name: string, rarity: string, shiny: boolean?, size: string?, element: string? }, publicNames: boolean?): (string, string)
	local tags = {}
	if d.size == "huge" then
		table.insert(tags, "HUGE")
	elseif d.size == "big" then
		table.insert(tags, "Big")
	end
	if d.shiny then
		table.insert(tags, "Shiny")
	end
	local sub = d.rarity
	if #tags > 0 then
		sub = table.concat(tags, " ") .. " " .. d.rarity
	end
	if publicNames == false and d.element then
		return string.upper(string.sub(d.element, 1, 1)) .. string.sub(d.element, 2), sub
	end
	return d.name, sub
end

function DragonLook.rarityColor(rarity: string): Rgb
	return Content.RarityColors[rarity] or { 255, 255, 255 }
end

-- The turn in the nest slot: the snout toward the passage and the entrance (04 §3); the side sign by the slot x
function DragonLook.slotFacing(slotX: number): { number } -- the gaze direction in the petal's local axes (x, z)
	local s = if slotX < 0 then 1 else -1
	local k = math.sqrt(0.5)
	return { s * k, -k }
end

return DragonLook
