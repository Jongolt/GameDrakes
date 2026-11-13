--!strict
-- 2.6: the social layer of spec 08 - pure logic without Roblox API (the Social service, the Social client).
-- Friends on the server (+10% per each, up to +40% - Economy.friendsBonus), Hatch Party (a foreign player at your warming egg
-- for 1 s -> the timer remainder / 2, a friend / 3, once per egg), the invite (LaunchData "party:<UserId>"), the Top nests table.

local Social = {}

export type IncRec = { egg: any, endsAt: number, party: number? }

-- the Hatch Party divisor: a friend - friendDiv (x3), otherwise div (x2)
function Social.partyDiv(isFriend: boolean, B: any): number
	return if isFriend then B.party.friendDiv else B.party.div
end

-- whether a party can be held for the egg: warming (not ready), not held yet, more than minLeft seconds left
function Social.partyAllowed(rec: IncRec?, now: number, minLeft: number): boolean
	return rec ~= nil and rec.party == nil and rec.endsAt - now > minLeft
end

-- apply: the new endsAt (the remainder / div, rounded up to a second) and who helped; returns the seconds saved
function Social.applyParty(rec: IncRec, now: number, div: number, helperId: number): number
	local left = math.max(0, rec.endsAt - now)
	local newLeft = math.ceil(left / math.max(div, 1))
	rec.endsAt = now + newLeft
	rec.party = helperId
	return left - newLeft
end

-- the invite LaunchData: "party:<UserId>" -> the inviter's UserId (or nil)
function Social.inviter(launchData: string?): number?
	if typeof(launchData) ~= "string" then
		return nil
	end
	local id = string.match(launchData, "^party:(%d+)$")
	return if id then tonumber(id) else nil
end

function Social.launchData(userId: number): string
	return "party:" .. tostring(math.floor(userId))
end

-- the friend's account not younger than minAccountDays
function Social.inviteAged(accountAge: number, cfg: any): boolean
	return accountAge >= cfg.minAccountDays
end

-- the friend stayed in the game without AFK for at least minActiveSec
function Social.inviteReady(activeSec: number, cfg: any): boolean
	return activeSec >= cfg.minActiveSec
end

-- the egg rarity: a Roblox subscription, IsVerified or the age check for the friend - top, otherwise base
function Social.inviteRarity(premium: boolean, verified: boolean, ageChecked: boolean, cfg: any): string
	return if premium or verified or ageChecked then cfg.top else cfg.base
end

-- the inviter's DataStore record { d = the UTC day, n = granted per day, p = the egg queue { f = the friend's UserId, r = the rarity } }:
-- a new day - the count from zero, the queue stays; the perDay limit or a full queue - nil (do not grant); otherwise a new record with n + 1 and,
-- if the inviter is not on the server (pending), an egg in the queue
function Social.inviterSlot(rec: any, day: string, cfg: any, pending: { f: number, r: string }?): any?
	local r = if typeof(rec) == "table" then table.clone(rec) else {}
	if r.d ~= day then
		r.d = day
		r.n = 0
	end
	local n = tonumber(r.n) or 0
	if n >= cfg.perDay then
		return nil
	end
	if pending then
		local list = if typeof(r.p) == "table" then table.clone(r.p) else {}
		if #list >= cfg.pendingCap then
			return nil
		end
		table.insert(list, pending)
		r.p = list
	end
	r.n = n + 1
	return r
end

-- Top nests: the players by income (descending), at a tie - by name; not more than n
export type Row = { name: string, rate: number, userId: number }
function Social.top(rows: { Row }, n: number): { Row }
	local list = table.clone(rows)
	table.sort(list, function(a, b)
		if a.rate ~= b.rate then
			return a.rate > b.rate
		end
		return a.name < b.name
	end)
	while #list > n do
		table.remove(list)
	end
	return list
end

-- whom to announce to the server at a hatch (08 §4): Epic and above
function Social.announceHatch(rarity: string, rarities: { string }): boolean
	local i = table.find(rarities, rarity) or 0
	local epic = table.find(rarities, "Epic") or math.huge
	return i >= epic
end

return Social
