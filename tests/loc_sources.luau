--!strict
-- all the English source texts of the game for the localization table - the path and the text tab-separated, one line per entry
-- (the list - tests/loc_list.luau). Read by tools/locales.py (the translations locales/<lang>.csv, LocaleData, the LocalizationTable in the place).
-- luau tests/loc_sources.luau

local list = require("./loc_list")

local function esc(s: string): string
	return (string.gsub(string.gsub(string.gsub(s, "\\", "\\\\"), "\n", "\\n"), "\t", "\\t"))
end

for _, row in list do
	print(row[1] .. "\t" .. esc(row[2]))
end
