--!strict
-- The look of numbers and time for the interface (02 §6, 03 §3): K / M / B / T / Qa, "1 in N", the timer m:ss. Pure logic.

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

-- 1234 -> "1.23K", 847e15 -> "847Qa". Up to 1000 - an integer. Round hundreds do not lose zeros (100K, not 1K).
function Format.number(n: number): string
	if n ~= n then
		return "0" -- NaN
	end
	local sign = if n < 0 then "-" else ""
	n = math.abs(n)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local tier = math.min(math.floor(math.log10(n) / 3), #SUFFIXES - 1)
	local v = n / 10 ^ (tier * 3)
	local s
	if v >= 100 then
		s = string.format("%d", math.floor(v))
	elseif v >= 10 then
		s = string.format("%.1f", math.floor(v * 10) / 10)
	else
		s = string.format("%.2f", math.floor(v * 100) / 100)
	end
	if string.find(s, ".", 1, true) then
		s = s:gsub("0+$", ""):gsub("%.$", "")
	end
	return sign .. s .. SUFFIXES[tier + 1]
end

-- 1234567 -> "1,234,567" (the thousands separator, US)
function Format.commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- A probability p (0..1] -> "1 in N". The rule 03 §3: N < 2 - one decimal (1 in 1.4); N < 10 - an integer
-- (1 in 4, 1 in 6); further two significant digits with the thousands separator (1 in 220, 1 in 5,000).
function Format.oneIn(p: number): string
	if p <= 0 then
		return "-"
	end
	local n = 1 / p
	if n < 2 then
		return string.format("1 in %.1f", n)
	elseif n < 10 then
		return "1 in " .. tostring(math.floor(n + 0.5))
	end
	local digits = math.floor(math.log10(n))
	local step = 10 ^ (digits - 1)
	return "1 in " .. Format.commas(math.floor(n / step + 0.5) * step)
end

-- seconds -> "2:59", "1:02:03"; negative -> "0:00"
function Format.clock(seconds: number): string
	local s = math.max(0, math.floor(seconds + 0.5))
	local h = s // 3600
	local m = (s % 3600) // 60
	local sec = s % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, sec)
	end
	return string.format("%d:%02d", m, sec)
end

-- 1 -> "I" ... 12 -> "XII", further a number (the ascension steps)
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII" }
function Format.roman(n: number): string
	return ROMAN[n] or tostring(n)
end

function Format.rate(n: number): string
	return Format.number(n) .. "/s"
end

function Format.plus(n: number): string
	return "+" .. Format.number(n)
end

-- "ember" -> "Ember"
function Format.title(s: string): string
	return (s:gsub("^%l", string.upper))
end

return Format
