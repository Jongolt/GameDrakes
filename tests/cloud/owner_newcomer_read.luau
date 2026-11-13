-- read only: the game owner's profile after a reset and a newcomer walkthrough on live - the onboarding steps (seconds from createdAt), the raid,
-- the golden one, combat, the zones, the touches, the dragons
local HttpService = game:GetService("HttpService")
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local v = ds:GetAsync("11774991821")
local d = type(v) == "table" and v.Data or {}
local c = tonumber(d.createdAt) or 0
local on = {}
local an = type(d.analytics) == "table" and d.analytics or {}
for k, t in (type(an.onboard) == "table" and an.onboard or {}) do
	on[tostring(k)] = (tonumber(t) or 0) - c
end
local dr = {}
for u, x in d.dragons or {} do
	table.insert(dr, string.format("%s %s %s s%d", u, tostring(x.rarity), tostring(x.element), x.stage or -1))
end
return {
	createdAt = c, now = os.time(), sinceCreate = os.time() - c, play = d.playSeconds, sessions = d.sessions,
	onboardSec = on, onboarding = d.onboarding, raid = d.raid, glowEgg = d.glowEgg, combat = d.combat, coins = d.coins,
	dragons = dr, companion = d.companion, eggs = d.eggs and { carry = d.eggs.carry ~= nil, shelf = d.eggs.shelf and #d.eggs.shelf or 0 },
	zones = an.zones, taps = an.taps,
}
