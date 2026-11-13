-- Read only: the game owner's profile in detail - the dragons with the stage, growAs and the timer remainder, the coins, the pile, onboarding.
local ds = game:GetService("DataStoreService"):GetDataStore("Profile_v2")
local v = ds:GetAsync("11774991821")
local d = type(v) == "table" and v.Data or {}
local now = os.time()
local dr = {}
for u, x in d.dragons or {} do
	table.insert(dr, string.format("%s %s %s s%d growAs=%s left=%s fed=%s", u, tostring(x.rarity), tostring(x.element), x.stage or -1, tostring(x.growAs),
		tostring(x.stageEndsAt and x.stageEndsAt - now), tostring(x.fedUntil and x.fedUntil > now)))
end
local inc = {}
for k, r in (d.eggs and d.eggs.incubating) or {} do
	table.insert(inc, k .. "=" .. tostring(r.egg and r.egg.rarity) .. ":" .. tostring(r.endsAt and r.endsAt - now))
end
return { coins = math.floor(d.coins or 0), pot = math.floor(d.pot or 0), sessions = d.sessions, lastSeenAgo = now - (d.lastSeen or 0),
	companion = d.companion, dragons = dr, incubating = inc, carry = d.eggs and d.eggs.carry and d.eggs.carry.rarity or "-",
	inGame = type(v) == "table" and type(v.MetaData) == "table" and v.MetaData.ActiveSession ~= nil }
