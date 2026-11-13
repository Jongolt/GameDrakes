--!strict
-- 2.6: the social core spec (spec 08). Run from the repository root: luau tests/social_spec.luau
local Config = require("../src/shared/Config")
local Economy = require("../src/shared/Core/Economy")
local Social = require("../src/shared/Core/Social")

local B = Config.Balance
local passed, failed = 0, 0
local function check(name: string, cond: boolean, detail: any?)
	if cond then
		passed += 1
	else
		failed += 1
		print("FAIL " .. name .. (if detail ~= nil then (" | " .. tostring(detail)) else ""))
	end
end

-- friends: +10% for each, cap +40% (08 §1)
check("friends: 0 -> 0%", Economy.friendsBonus(0, B) == 0)
check("friends: 2 -> +20%", math.abs(Economy.friendsBonus(2, B) - 0.2) < 1e-9)
check("friends: 5 -> cap +40%", math.abs(Economy.friendsBonus(5, B) - 0.4) < 1e-9)

-- Hatch Party (08 §2): remainder / 2, a friend / 3, once per egg
local now = 1000
local rec: any = { egg = {}, endsAt = now + 600 }
check("party: allowed at a warming egg", Social.partyAllowed(rec, now, 5))
check("divisor: a stranger x2, a friend x3", Social.partyDiv(false, B) == 2 and Social.partyDiv(true, B) == 3)
local saved = Social.applyParty(rec, now, Social.partyDiv(false, B), 42)
check("party: 600 s -> 300 s, 300 saved", rec.endsAt == now + 300 and saved == 300 and rec.party == 42)
check("party: not a second time", not Social.partyAllowed(rec, now, 5))
local rec2: any = { egg = {}, endsAt = now + 100 }
Social.applyParty(rec2, now, Social.partyDiv(true, B), 7)
check("friend: 100 s -> 34 s (rounded up to a second)", rec2.endsAt == now + 34)
check("party: a ready or almost ready egg - not allowed", not Social.partyAllowed({ egg = {}, endsAt = now + 3 }, now, 5) and not Social.partyAllowed(nil, now, 5))

-- invitation (08 §2): LaunchData
check("invitation: party:<id>", Social.inviter("party:123456") == 123456 and Social.launchData(123456) == "party:123456")
check("invitation: garbage - nil", Social.inviter("src=ads") == nil and Social.inviter(nil) == nil and Social.inviter("party:abc") == nil)

-- the invitation reward (Config.Social.invite)
local SI = Config.Social.invite
check("invitation: an account of 60 days - yes, 59 - no", Social.inviteAged(60, SI) and not Social.inviteAged(59, SI))
check("invitation: 10 min in the game - yes, 599 s - no", Social.inviteReady(600, SI) and not Social.inviteReady(599, SI))
check("invitation: without the signs - Epic", Social.inviteRarity(false, false, false, SI) == "Epic")
check("invitation: Premium / IsVerified / age check - Legendary", Social.inviteRarity(true, false, false, SI) == "Legendary"
	and Social.inviteRarity(false, true, false, SI) == "Legendary" and Social.inviteRarity(false, false, true, SI) == "Legendary")
local slot = Social.inviterSlot(nil, "2026-10-31", SI, nil)
check("inviter: the first reward of the day", slot ~= nil and slot.n == 1 and slot.d == "2026-10-31" and slot.p == nil)
local full: any = { d = "2026-10-31", n = SI.perDay }
check("inviter: the daily limit - nil", Social.inviterSlot(full, "2026-10-31", SI, nil) == nil)
local nextDay = Social.inviterSlot({ d = "2026-10-31", n = SI.perDay, p = { { f = 1, r = "Epic" } } }, "2026-11-01", SI, { f = 2, r = "Legendary" })
check("inviter: a new day - the count from zero, the queue accumulates", nextDay ~= nil and nextDay.n == 1 and #nextDay.p == 2 and nextDay.p[2].f == 2)
local q = {}
for i = 1, SI.pendingCap do
	table.insert(q, { f = i, r = "Epic" })
end
check("inviter: a full queue - nil", Social.inviterSlot({ d = "2026-10-30", n = 0, p = q }, "2026-10-31", SI, { f = 99, r = "Epic" }) == nil)
local src: any = { d = "2026-10-31", n = 1, p = { { f = 1, r = "Epic" } } }
Social.inviterSlot(src, "2026-10-31", SI, { f = 2, r = "Epic" })
check("inviter: the old record does not change (UpdateAsync may repeat the call)", src.n == 1 and #src.p == 1)

-- Top nests (08 §4)
local top = Social.top({ { name = "b", rate = 5, userId = 2 }, { name = "a", rate = 5, userId = 1 }, { name = "c", rate = 50, userId = 3 } }, 2)
check("top: by income, ties by name, trimming", #top == 2 and top[1].name == "c" and top[2].name == "a")

-- Epic+ announcements (08 §4)
check("announcement: Epic, Legendary, Mythic - yes; Rare - no", Social.announceHatch("Epic", Config.Rarities) and Social.announceHatch("Mythic", Config.Rarities) and not Social.announceHatch("Rare", Config.Rarities))

print(string.format("social layer spec: %d passed, %d failed", passed, failed))
if failed > 0 then
	error("there are failed checks")
end
