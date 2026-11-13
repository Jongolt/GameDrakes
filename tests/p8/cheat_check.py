#!/usr/bin/env python3
"""The anti-cheat probe in the LOCAL file on P8 (after the Black Deck teardown: 'it was computed on the server').
The Studio client plays the cheater: everything an exploit does - it calls our Remotes with any arguments and moves its own character
(the network ownership is the client's). The server must refuse and grant nothing. Other people's Roblox servers are not touched: the server and the client are
one Studio program on P8.

The blocks (the result - the result.md table, FAIL - the number of failures):
  A  garbage arguments into all Remotes client -> server (types, NaN, inf, long strings, tables, Instance, extra arguments),
     with a pause by the rate limit of every call: not a single ok=true
  B  the logic: a foreign/made-up dragon, releasing the companion, a purchase without coins, double rewards (including in parallel), a gift for
     time ahead of schedule, the codes, Ascend without the conditions, a purchase intent without payment (nothing is granted)
  D  Admin in the live game mode (AntiCheatDebug "admin prod"): give -> forbidden, the coins are the same
  E  teleport and speed on foot (the protection is on): an egg from afar, feeding at the stall, a path coin, a jump up, speed x9,
     a chain of short jumps, mounting a teleported companion, teleporting the dragon while riding
  F  honest play with the protection on: walking, jumps, a server move + picking an egg, gliding, the updraft, death and
     respawn, mounting and dismounting, falling past the boundary - zero violations
  C  a flood: 30 Claims in a row, garbage events (Analytics, Active, Perf, FlightInput) - the server is alive; 60 Ascends in a row - a kick
  G  a restart: the profile via StudioSeed, a new server, calls in the first seconds before loading, the profile comparison, a teleport again
The console: handler errors ([Net] ...), Stack Begin, attempt to.

Run (after tools/p8/open_local.sh with the place from the copy with the protection): python3 tests/p8/cheat_check.py. ~12-15 min. The output: p8lib.OUT."""
import json, math, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("cheat_check")
from p8lib import *  # noqa: F401,F403

R = "local R=game.ReplicatedStorage.Remotes local H=game:GetService('HttpService') local me=game.Players.LocalPlayer "
ACD = "local function ac(c) return game.ServerStorage.AntiCheatDebug:Invoke(c) end "
ME_ROOT = "local r=me.Character and me.Character:FindFirstChild('HumanoidRootPart') "


def ac(cmd): return S(ACD + f"return ac([[{cmd}]])")
def edit(code): return run(code, "Edit")
def violations():
    m = re.search(r"player=(-?\d+)", ac("stats")); return int(m.group(1)) if m else -1
def spos():
    t = S("local p=game.Players:GetPlayers()[1] local r=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart') "
          "if not r then return '-' end return string.format('%.2f,%.2f,%.2f', r.Position.X, r.Position.Y, r.Position.Z)")
    return tuple(float(x) for x in t.split(",")) if "," in t else None
def cpos():
    t = C(R + ME_ROOT + "if not r then return '-' end return string.format('%.2f,%.2f,%.2f', r.Position.X, r.Position.Y, r.Position.Z)")
    return tuple(float(x) for x in t.split(",")) if "," in t else None
def dist(a, b, flat=False):
    if not a or not b: return 1e9
    return math.sqrt((a[0] - b[0]) ** 2 + (0 if flat else (a[1] - b[1]) ** 2) + (a[2] - b[2]) ** 2)
def ddump():
    d = json.loads(S(LD + "return ld('dump')"))
    if isinstance(d.get("dragons"), list): d["dragons"] = {}
    return d
def coins(): return int(ddump().get("coins", 0))
def whyd():
    """The violations by reason (AntiCheatDebug why): {'speed': 3, 'fly': 1, 'far': 2, ...}"""
    out = {}
    for kv in (ac("why") or "").split():
        k, _, v = kv.partition("=")
        if v.isdigit(): out[k] = int(v)
    return out
def wdiff(a, b, k): return b.get(k, 0) - a.get(k, 0)
NUM = r"-?\d+(?:\.\d+)?"
def nums(t, n):
    """N space-separated numbers from the server reply, otherwise None (a wrong reply - the check is skipped with FAIL, the probe does not crash)"""
    m = re.fullmatch(r"\s*" + r"\s+".join([f"({NUM})"] * n) + r"\s*", t or "")
    return tuple(float(x) for x in m.groups()) if m else None
def players(): return S("return tostring(#game.Players:GetPlayers())")

RL = {}
def gap(name): return 1.0 / RL[name] + 0.15 if name in RL else 0.2
LAST = {}
def inv(name, args=""):
    """InvokeServer with a pause by the rate limit of this call; -> (ok, reason)"""
    w = gap(name) - (time.time() - LAST.get(name, 0))
    if w > 0: time.sleep(w)
    t = C(R + f"local ok,res=pcall(function() return R.{name}:InvokeServer({args}) end) "
          "if not ok then return 'err/'..tostring(res):sub(1,80) end if type(res)~='table' then return 'nontable/'..typeof(res) end "
          "return tostring(res.ok==true)..'/'..tostring(res.reason)")
    LAST[name] = time.time()
    a, _, b = (t or "").partition("/")
    return a == "true", b


def start_play():
    s.call("start_stop_play", {"studio_id": sid, "is_start": True})
    t0 = time.time()
    while time.time() - t0 < 80:
        if C("return tostring(game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') ~= nil)") == "false": break
        time.sleep(0.8)
    time.sleep(5)


# ================================================================================================ preparation
P("the Studio state:", s.call("get_studio_state", {"studio_id": sid}).get("result", {}).get("content", [{}])[0].get("text", "")[:200])
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
start_play()
have = S("return tostring(game.ServerStorage:FindFirstChild('AntiCheatDebug') ~= nil)")
ok("the build with the protection (ServerStorage.AntiCheatDebug exists)", have == "true", have)
if have != "true":
    write_result("cheat_check: the place is built without the protection"); stop(); s.close(); sys.exit(1)
P("AntiCheat:", ac("stats"))
RL.update(json.loads(S("return game:GetService('HttpService'):JSONEncode(require(game.ReplicatedStorage.Shared.Config).RateLimit)") or "{}"))
P("the rate limits:", RL)
MYID = C("return tostring(game.Players.LocalPlayer.UserId)")
if not re.fullmatch(r"-?\d+", MYID or ""):
    ok("the client's UserId was read", False, MYID); MYID = "0"
# the first dragon (the companion): an egg from the table -> bowl 1 -> fast-forward -> the hatch
for cmd in ("table 1", "place 1", "time 900", "hatch 1"):
    P(" ld", cmd, "->", S(LD + f"return ld('{cmd}')")[:160]); time.sleep(1.2)
time.sleep(3)
d0 = ddump()
UID = d0.get("companion") or (list(d0.get("dragons", {}).keys()) or [""])[0]
ok("preparation: there is a companion dragon", bool(UID), f"companion={UID} dragons={list(d0.get('dragons', {}).keys())}")
P("the profile:", f"coins={d0.get('coins')} incubators={d0.get('incubators')} companion={UID}")

GIFT_SKU = S("local Sh=require(game.ReplicatedStorage.Shared.Core.Shop) for _,k in Sh.catalog() do if k.gift and not k.update and k.kind=='product' then return k.key end end return ''")
TG_MAX = S("local C=require(game.ReplicatedStorage.Shared.Config) local m=0 for _,g in C.Rewards.timeGifts.list do m=math.max(m, g.min or 0) end return tostring(m)")
LIVE_CODE = S("local LC=require(game.ReplicatedStorage.Shared.Core.LiveOps) local Ct=require(game.ReplicatedStorage.Shared.Content) "
              "for code in Ct.Codes do local d=LC.codeCheck(Ct.Codes, Ct.Updates, LC.normCode(code), os.time(), {}) if d then return code end end return ''")
SP = S("local s=workspace:FindFirstChildWhichIsA('SpawnLocation', true) if not s then return '' end return string.format('%.1f %.1f %.1f', s.Position.X, s.Position.Y, s.Position.Z)")
SPN = nums(SP, 3)
ok("preparation: the spawn is found", SPN is not None, SP)
P("the gift SKU:", GIFT_SKU, "| the latest gift for time, min:", TG_MAX, "| the live code:", LIVE_CODE or "-")

# ================================================================================================ A: garbage arguments
STR_BAD = [("empty", "''"), ("nil", "nil"), ("number", "123"), ("NaN", "0/0"), ("inf", "math.huge"), ("table", "{}"),
           ("Instance", "workspace"), ("Vector3", "Vector3.new(1,2,3)"), ("5000 characters", "string.rep('A',5000)"), ("bool", "true")]
INT_BAD = [("nil", "nil"), ("string", "'1'"), ("0", "0"), ("4", "4"), ("-1", "-1"), ("1.5", "1.5"), ("NaN", "0/0"),
           ("inf", "math.huge"), ("-inf", "-math.huge"), ("table", "{}"), ("Instance", "workspace")]
def plus(base, extra): return base + extra
CASES = {
    "PickEgg": plus(STR_BAD, [("17 characters", "string.rep('a',17)"), ("no spot", "'nope'"), ("extra argument", "'nope', 1")]),
    "PlaceEgg": INT_BAD, "HatchReady": INT_BAD,
    "Feed": plus(STR_BAD, [("foreign uid", "'nouid'"), ("extra argument", "'all', 'x'")]),
    "SetCompanion": plus(STR_BAD, [("foreign uid", "'nouid'")]),
    "Mount": plus(STR_BAD, [("foreign uid", "'nouid'")]),
    "Treat": plus(STR_BAD, [("foreign uid", "'nouid'")]),
    "MoveDragon": [("foreign uid", "'nouid','nest'"), ("wrong target", "'nouid','space'"), ("no target", "'nouid'"), ("numeric target", "'nouid', 5"), ("nil", "nil")],
    "Release": [("foreign uid", "'nouid', true"), ("confirm as a string", "'common', 'yes'"), ("no confirm", "'common'"), ("confirm as a number", "'x', 1")],
    "NameDragon": [("foreign uid", "'nouid','Bob'"), ("21 characters", f"'{UID}', string.rep('A',21)"), ("numeric name", f"'{UID}', 5")],
    "Buy": [("not an item", "'free'"), ("empty", "''"), ("table", "{}"), ("33 characters", "string.rep('a',33)")],
    "Claim": [("daily (granted by itself)", "'daily'"), ("not a kind", "'bogus'"), ("gift 999 min", "'timeGift','999'"), ("gift NaN", "'timeGift','nan'"),
              ("gift -5", "'timeGift','-5'"), ("gift inf", "'timeGift','inf'"), ("made-up index", "'index','ember:Mythic'"),
              ("season 99", "'season','99'"), ("keeper lava", "'keeper','lava'"), ("numeric kind", "5")],
    "Ascend": [("extra argument", "123")],
    "Dismount": [("not riding", ""), ("extra argument", "'x'")],
    "Shore": [("not in water", ""), ("extra argument", "1")],
    "ShopIntent": [("a gift directly", f"'Gift_{GIFT_SKU}'"), ("no item", "'NoSuch'"), ("a gift to oneself", f"'{GIFT_SKU}', {MYID}"),
                   ("a gift to a player not on the server", f"'{GIFT_SKU}', 1"), ("giftTo -5", f"'{GIFT_SKU}', -5"), ("giftTo 1.5", f"'{GIFT_SKU}', 1.5"),
                   ("HatchNow without an egg", "'HatchNow', nil, '9'"), ("GrowNow foreign", "'GrowNow', nil, 'nouid'")],
    "Code": [("empty", "''"), ("21 characters", "string.rep('Z',21)"), ("not a code", "'DROP TABLE'"), ("number", "123")],
    "SetLook": [("a preset to a foreign one", "'preset','sunset','nouid'"), ("skin not bought", "'nestSkin','royal'"), ("not a kind", "'bogus','x'"),
                ("17 characters", "'preset', string.rep('a',17)")],
    "Setting": [("a string instead of bool", "'otherDragons','yes'"), ("not a key", "'admin', true"), ("no value", "'otherDragons'")],
}
lua = [R, "local out={} local pending=0 ",
       "local function go(name, gap, cases) pending+=1 task.spawn(function() for _,c in cases do "
       "local ok,res=pcall(function() return R[name]:InvokeServer(table.unpack(c.a,1,c.n)) end) "
       "out[#out+1]={r=name,c=c.l,ok=(ok and type(res)=='table' and res.ok==true),why=(ok and (type(res)=='table' and tostring(res.reason) or 'nontable') or ('err:'..tostring(res):sub(1,60)))} "
       "task.wait(gap) end pending-=1 end) end "]
for name, cases in CASES.items():
    items = []
    for label, args in cases:
        n = 0 if args.strip() == "" else len(re.split(r",(?![^()]*\))", args))
        items.append("{l=[[%s]],n=%d,a={%s}}" % (label, n, args))
    lua.append(f"go('{name}', {gap(name):.2f}, {{{','.join(items)}}}) ")
lua.append("local t0=os.clock() while pending>0 and os.clock()-t0<240 do task.wait(0.25) end return H:JSONEncode(out)")
before = ddump()
P("A: garbage arguments,", sum(len(v) for v in CASES.values()), "calls in", len(CASES), "Remotes...")
raw = run("".join(lua), "Client", 300)
try:
    rows = json.loads(raw)
except Exception:
    rows = []; P("A: the reply is not JSON:", raw[:300])
bad = [r for r in rows if r.get("ok")]
fast = [r for r in rows if r.get("why") == "too_fast"]
ok("A: as many replies as calls", len(rows) == sum(len(v) for v in CASES.values()), f"{len(rows)}")
ok("A: not a single garbage call passed (ok=true)", not bad, "; ".join(f"{r['r']}:{r['c']}" for r in bad[:8]))
ok("A: the rate limit did not interfere with the check (no too_fast)", not fast, "; ".join(f"{r['r']}:{r['c']}" for r in fast[:8]))
errs = [r for r in rows if str(r.get("why", "")).startswith("err:")]
ok("A: the client did not get a server error instead of a reply", not errs, "; ".join(f"{r['r']}:{r['c']}={r['why']}" for r in errs[:6]))
with open(f"{OUT}/A_garbage.json", "w") as f: json.dump(rows, f, ensure_ascii=False, indent=0)
after = ddump()
for k in ("coins", "incubators", "slots", "shelfCap", "ascension", "companion"):
    ok(f"A: {k} did not change", json.dumps(before.get(k)) == json.dumps(after.get(k)), f"{before.get(k)} -> {after.get(k)}")
ok("A: the dragons are the same", sorted(before.get("dragons", {})) == sorted(after.get("dragons", {})), f"{len(before.get('dragons', {}))} -> {len(after.get('dragons', {}))}")

# ================================================================================================ B: the logic
b0 = ddump()
o, why = inv("Buy", "'incubator'")
ok("B: an incubator is not bought without coins", (not o) or b0.get("coins", 0) >= 5000, f"{o}/{why} coins={b0.get('coins')}")
o, why = inv("Release", f"'{UID}', true"); ok("B: the companion cannot be released", not o, why)
o, why = inv("Release", "'nouid', true"); ok("B: a made-up dragon cannot be released", not o, why)
o, why = inv("MoveDragon", "'nouid','sanctuary'"); ok("B: a made-up one cannot be moved", not o, why)
o, why = inv("NameDragon", "'nouid','Bob'"); ok("B: a made-up one cannot be named", not o, why)
o, why = inv("Treat", f"'{UID}'"); ok("B: a treat without a stock", not o, why)
o, why = inv("SetLook", f"'preset','sunset','{UID}'"); ok("B: an unbought preset cannot be put on", not o, why)
o, why = inv("SetLook", "'nestSkin','royal'"); ok("B: an unbought nest skin cannot be put on", not o, why)
if TG_MAX and TG_MAX != "0":
    o, why = inv("Claim", f"'timeGift','{TG_MAX}'"); ok(f"B: the gift for {TG_MAX} min ahead of schedule", not o, why)
o, why = inv("Claim", "'index','ember:Mythic'"); ok("B: an Index reward without the entry", not o, why)
o, why = inv("Claim", "'season','10'"); ok("B: a season step without points", not o, why)
o, why = inv("Code", "'NOTACODE'"); ok("B: a made-up code", not o, why)
o, why = inv("Ascend"); ok("B: Ascend without the conditions", not o, why)
b1 = ddump()
ok("B: ascension did not change", b0.get("ascension") == b1.get("ascension"), f"{b0.get('ascension')} -> {b1.get('ascension')}")
ok("B: the dragons are in place", sorted(b0.get("dragons", {})) == sorted(b1.get("dragons", {})), "")
ok("B: the coins did not grow from refusals", int(b1.get("coins", 0)) <= int(b0.get("coins", 0)) + 5, f"{b0.get('coins')} -> {b1.get('coins')}")

# double rewards: in a row and in parallel (IsInGroupAsync yields the thread)
for kind in ("calendar", "freeGift", "away"):
    r1 = inv("Claim", f"'{kind}'"); c1 = coins(); r2 = inv("Claim", f"'{kind}'"); c2 = coins()
    if kind == "away":  # Nest.claimAway is idempotent: the second Collect answers ok=true with coins=0 (the away record is already empty) - we measure the coins
        ok("B: away twice in a row - the second grant is 0 coins", c2 <= c1 + 5, f"{r1} {r2} coins {c1} -> {c2}")
    else:
        ok(f"B: {kind} twice in a row - not more than one grant", not (r1[0] and r2[0]), f"{r1} {r2}")
par = run(R + "local res={} for i=1,3 do task.spawn(function() local ok,x=pcall(function() return R.Claim:InvokeServer('freeGift') end) "
          "res[#res+1]=tostring(ok and type(x)=='table' and x.ok)..'/'..tostring(ok and type(x)=='table' and x.reason) end) task.wait(0.55) end "
          "local t0=os.clock() while #res<3 and os.clock()-t0<20 do task.wait(0.2) end return table.concat(res,' ')", "Client", 60)
ok("B: freeGift three times in parallel - not more than one grant", par.count("true/") <= 1, par)
if LIVE_CODE:
    r1 = inv("Code", f"'{LIVE_CODE}'"); r2 = inv("Code", f"'{LIVE_CODE.lower()}  '")
    ok("B: the live code the second time (another case, spaces) is not accepted", not r2[0], f"{r1} {r2}")
# a purchase intent is not a purchase: HatchNow on an egg in the bowl does not hatch without a receipt
P(" ld give egg ->", S(LD + "return ld('give egg Meadow')")[:120]); time.sleep(1)
P(" ld place 1 ->", S(LD + "return ld('place 1')")[:160]); time.sleep(1.5)
inc0 = ddump().get("eggs", {}).get("incubating", {})
o, why = inv("ShopIntent", "'HatchNow', nil, '1'")
time.sleep(2.5)
inc1 = ddump().get("eggs", {}).get("incubating", {})
ok("B: the HatchNow intent without payment did not hatch the egg", bool(inc0) and sorted(inc0) == sorted(inc1), f"intent={o}/{why} before={list(inc0)} after={list(inc1)}")
b2 = ddump()
for k in ("owned", "items", "purchases", "purchaseLog"):
    ok(f"B: {k} did not change without purchases", json.dumps(b1.get(k), sort_keys=True) == json.dumps(b2.get(k), sort_keys=True), "")

# ================================================================================================ D: Admin as in the live game
c0 = coins()
P("D:", ac("admin prod"))
o, why = inv("Admin", "'give 999999'")
ok("D: Admin give not from the owner - a refusal", not o, why)
ok("D: the coins did not grow", coins() <= c0 + 5, f"{c0} -> {coins()}")
P("D:", ac("admin studio"))

# ================================================================================================ E: teleport and speed (the protection is on)
P("E:", ac("enforce on")); ac("reset"); time.sleep(1)
FAR_EGG = S("local p=game.Players:GetPlayers()[1] local o=p.Character.HumanoidRootPart.Position local best,bd=nil,0 "
            "for _,a in workspace.World.EggPoints:GetChildren() do if a:FindFirstChild('Egg') then local d=(a.Position-o).Magnitude if d>bd then best,bd=a,d end end end "
            "if not best then return '' end return string.format('%s %.1f %.1f %.1f %.0f', best.Name, best.Position.X, best.Position.Y, best.Position.Z, bd)")
P("E1 the far egg:", FAR_EGG)
FAR_OK = bool(re.fullmatch(r"\S+ " + " ".join([NUM] * 4), FAR_EGG or ""))
ok("E1: the far egg is found", FAR_OK, FAR_EGG)
if not FAR_OK: FAR_EGG = ""
if FAR_EGG:
    eid, ex, ey, ez, ed = FAR_EGG.split()
    home = spos()
    t = C(R + ME_ROOT + f"r.CFrame=CFrame.new({ex},{float(ey) + 3},{ez}) task.wait(0.35) local a=R.PickEgg:InvokeServer('{eid}') return tostring(a.ok)..'/'..tostring(a.reason)")
    time.sleep(1.6)
    ok(f"E1: the egg {ed} studs away cannot be taken after a teleport", t.startswith("false/too_far"), t)
    ok("E1: the server returned the character back", dist(spos(), home) < 30, f"server {spos()} home {home}")
    ok("E1: the client returned too", dist(cpos(), home) < 30, f"client {cpos()}")
    ok("E1: the egg is not in the hands", not ddump().get("eggs", {}).get("carry"), "")
STALL = S("local s=game:GetService('CollectionService'):GetTagged('Stall')[1] if not s then return '' end return string.format('%.1f %.1f %.1f', s.Position.X, s.Position.Y, s.Position.Z)")
if nums(STALL, 3):
    x, y, z = STALL.split(); home = spos()
    # the server's honest point and the distances to the stall / the base of the own nest (Nest.feed: stallFeedDistance 14, feedDistance 55 horizontally)
    hm = re.search(r"honest=(%s),(%s),(%s)" % (NUM, NUM, NUM), ac("pos")); honest = tuple(float(v) for v in hm.groups()) if hm else home
    NB = S("local p=game.Players:GetPlayers()[1] local f=workspace:FindFirstChild('Nests',true) if f then for _,n in f:GetChildren() do if n:GetAttribute('OwnerId')==p.UserId then "
           "local b=n.PrimaryPart or n:FindFirstChild('Base') if b then return string.format('%.1f %.1f %.1f', b.Position.X, b.Position.Y, b.Position.Z) end end end end return ''")
    dS = dist(honest, tuple(float(v) for v in STALL.split()), flat=True); dN = dist(honest, nums(NB, 3), flat=True) if nums(NB, 3) else 1e9
    t = C(R + ME_ROOT + f"r.CFrame=CFrame.new({x},{float(y) + 4},{float(z) + 3}) task.wait(0.35) local a=R.Feed:InvokeServer('all') return tostring(a.ok)..'/'..tostring(a.reason)")
    time.sleep(1.6)
    if dS > 14 + 4 and dN > 55 + 4:
        ok("E2: feeding at the stall after a teleport - too_far", t.startswith("false/too_far"), f"{t}; honest {honest} to the stall {dS:.0f} to the nest {dN:.0f}")
    else:
        ok("E2: feeding at the stall after a teleport - by the honest point (within the nest/stall radius - the server may feed)", True, f"{t}; honest {honest} to the stall {dS:.0f} to the nest {dN:.0f} - no teleport needed, the check is uninformative")
COIN = S("local p=game.Players:GetPlayers()[1] local o=p.Character.HumanoidRootPart.Position "
         "for _,c in game:GetService('CollectionService'):GetTagged('TrailCoin') do if c:IsA('BasePart') and c.Transparency<1 and (c.Position-o).Magnitude>100 then "
         "c:SetAttribute('CheatProbe', true) return string.format('%.2f %.2f %.2f', c.Position.X, c.Position.Y, c.Position.Z) end end return ''")
P("E3 the path coin:", COIN)
ok("E3: the far path coin is found", nums(COIN, 3) is not None, COIN)
if nums(COIN, 3):
    x, y, z = COIN.split(); c0 = coins()
    C(R + ME_ROOT + f"r.CFrame=CFrame.new({x},{y},{z}) task.wait(1.2) return 'ok'")
    time.sleep(1.2)
    taken = S("for _,c in game:GetService('CollectionService'):GetTagged('TrailCoin') do if c:GetAttribute('CheatProbe') then return tostring(c.Transparency) end end return '?'")
    ok("E3: the path coin is not collected by a teleport", taken not in ("1", "?") and coins() <= c0 + 5, f"Transparency={taken} coins {c0} -> {coins()}")
time.sleep(2)  # the grace after the E3 return: the honest point and the client position converge
home = spos(); w4 = whyd()
C(R + ME_ROOT + "r.CFrame=r.CFrame+Vector3.new(0,400,0) task.wait(1) return 'ok'"); time.sleep(1.5)
ok("E4: the 400 jump up is noticed (up)", wdiff(w4, whyd(), "up") > 0, f"{whyd()}")
ok("E4: the 400 jump up is cancelled", dist(spos(), home) < 40, f"{spos()} home {home}; {ac('pos')}")
time.sleep(2)
home = spos(); v5 = violations()
C(R + "local h=me.Character.Humanoid h.WalkSpeed=150 local r=me.Character.HumanoidRootPart h:MoveTo(r.Position+r.CFrame.LookVector*600) task.wait(3) "
  "local p=r.Position h.WalkSpeed=16 h:MoveTo(p) return 'ok'")
cl, sv = cpos(), spos()
moved = dist(sv, home, flat=True)
ok("E5: speed x9: the server let through not farther than 60 studs/s", moved <= 60 * 3.5 + 24 + 10, f"the server {moved:.0f} studs, the client {dist(cl, home, flat=True):.0f}")
ok("E5: the speed-up is noticed (there are violations)", violations() > v5, f"{v5} -> {violations()}")
time.sleep(2)
home = spos(); v6 = violations()
C(R + ME_ROOT + "for i=1,30 do r.CFrame=r.CFrame+Vector3.new(20,0,0) task.wait(0.1) end return 'ok'"); time.sleep(1.5)
ok("E6: a chain of 20-stud jumps: not farther than 60 studs/s", dist(spos(), home, flat=True) <= 60 * 4.5 + 24 + 10, f"the server {dist(spos(), home, flat=True):.0f}")
ok("E6: the chain is noticed (there are violations)", violations() > v6, f"{v6} -> {violations()}")
time.sleep(2)
print(" ld setcomp ember1 ->", S(LD + "return ld('setcomp ember1')")[:80]); time.sleep(3)
home = spos()
t = C(R + ME_ROOT + "local f=r.Position+Vector3.new(250,0,0) local comp=nil for _,m in workspace.Companions:GetChildren() do if m:GetAttribute('OwnerId')==me.UserId then comp=m end end "
      f"r.CFrame=CFrame.new(f) if comp then comp:PivotTo(CFrame.new(f+Vector3.new(4,0,0))) end task.wait(0.35) local a=R.Mount:InvokeServer('{UID}') "
      "task.wait(1) return tostring(a.ok)..'/'..tostring(a.reason)..' comp='..tostring(comp~=nil)..' mounted='..tostring(me:GetAttribute('Mounted'))")
time.sleep(1.5)
ok("E7: mounting a teleported companion is rejected", t.startswith("false/") and "mounted=nil" in t, t)
ok("E7: the character did not stay there", dist(spos(), home) < 40, f"{spos()} home {home}")
time.sleep(9)  # the companion catches up with the owner (the leash 45 studs/s, it was carried 250 away)
o, why = inv("Mount", f"'{UID}'")
ok("E8: an honest mount next to the companion (the protection does not interfere)", o, why)
if o:
    time.sleep(2)
    home = spos()
    C(R + "local comp=nil for _,m in workspace.Companions:GetChildren() do if m:GetAttribute('OwnerId')==me.UserId then comp=m end end "
      "if comp then comp:PivotTo(comp:GetPivot()+Vector3.new(500,0,0)) end task.wait(1.2) return 'ok'")
    time.sleep(1.5)
    ok("E8: the dragon did not teleport away while ridden", dist(spos(), home) < 60, f"{spos()} home {home}")
    o2, why2 = inv("Dismount"); time.sleep(1.5)
    ok("E8: the dismount - next to the honest point", dist(spos(), home) < 60, f"{o2}/{why2} {spos()}")
SEA_PT = S("local C=require(game.ReplicatedStorage.Shared.Config) local SEA=C.World.island2.seaLevel "
            "local sp=workspace:FindFirstChildWhichIsA('SpawnLocation', true) if not sp then return '' end local o=sp.Position "
            "for r=200,1400,50 do for _,d in {Vector3.new(1,0,0),Vector3.new(-1,0,0),Vector3.new(0,0,1),Vector3.new(0,0,-1)} do "
            "local p=Vector3.new(o.X,SEA-7,o.Z)+d*r local reg=Region3.new(p-Vector3.new(4,4,4),p+Vector3.new(4,4,4)):ExpandToGrid(4) "
            "local m=workspace.Terrain:ReadVoxels(reg,4) local all=true local sz=m.Size for x=1,sz.X do for y=1,sz.Y do for z=1,sz.Z do if m[x][y][z]~=Enum.Material.Water then all=false end end end end "
            "if all then return string.format('%.1f %.1f %.1f', p.X, p.Y, p.Z) end end end return ''")
P("the point in the sea:", SEA_PT)
ok("E9/F9: a point in the open sea is found", nums(SEA_PT, 3) is not None, SEA_PT)
if nums(SEA_PT, 3):
    time.sleep(3.5)  # the Shore cooldown
    sx, sy, sz = nums(SEA_PT, 3); home = spos()
    t = C(R + ME_ROOT + f"r.CFrame=CFrame.new({sx},{sy + 1},{sz}) task.wait(0.35) local a=R.Shore:InvokeServer() return tostring(a.ok)..'/'..tostring(a.reason)")
    time.sleep(1.6)
    ok("E9: a teleport into the sea + Back to shore - the server does not move", t.startswith("false/") and dist(spos(), home) < 40, f"{t} {spos()} home {home}")
# E10: the 'Pick up' prompt from afar - like fireproximityprompt (the range and the hold are faked on the client)
w0 = whyd(); carry0 = ddump().get("eggs", {}).get("carry")
t = C(R + ME_ROOT + "local best,bd,ba=nil,0,nil for _,a in workspace.World.EggPoints:GetChildren() do local e=a:FindFirstChild('Egg') "
      "local pr=e and e:FindFirstChildWhichIsA('ProximityPrompt',true) if pr then local d=(a.Position-r.Position).Magnitude if d>bd then best,bd,ba=pr,d,a end end end "
      "if not best then return 'none' end best.MaxActivationDistance=math.huge best.RequiresLineOfSight=false best.HoldDuration=0 task.wait(0.3) "
      "local ok,err=pcall(function() best:InputHoldBegin() task.wait(0.15) best:InputHoldEnd() end) task.wait(1.2) "
      "return string.format('%s %s d=%.0f', tostring(ok), ba.Name, bd)")
time.sleep(1)
w1 = whyd(); pid = (t.split() + ["", ""])[1]
still = S(f"local a=workspace.World.EggPoints:FindFirstChild('{pid}') return tostring(a~=nil and a:FindFirstChild('Egg')~=nil)") if pid else "?"
ok("E10: the prompt from afar reached the server (otherwise the check is not proven)", wdiff(w0, w1, "far") > 0, f"{t}; far {w0.get('far', 0)} -> {w1.get('far', 0)}")
ok("E10: the egg is not taken from afar by the prompt", not ddump().get("eggs", {}).get("carry") or carry0, f"{t}; the egg in place={still}")
# E11: through the invisible Frost Isle wall (noclip) - in steps of 3 studs, the speed is honest, the zone is closed
WALL = S("local C=require(game.ReplicatedStorage.Shared.Config) local SEA=C.World.island2.seaLevel local X=C.World.frostIsle.wallX "
         "for z=-400,400,40 do local p=Vector3.new(X-20,SEA-7,z) local reg=Region3.new(p-Vector3.new(4,4,4),p+Vector3.new(4,4,4)):ExpandToGrid(4) "
         "local m=workspace.Terrain:ReadVoxels(reg,4) local all=true local sz=m.Size for x=1,sz.X do for y=1,sz.Y do for z=1,sz.Z do if m[x][y][z]~=Enum.Material.Water then all=false end end end end "
         "if all then return string.format('%.1f %.1f %.1f %.1f', p.X, p.Y, p.Z, X) end end return ''")
ok("E11: the water at the Frost Isle wall is found", nums(WALL, 4) is not None, WALL)
if nums(WALL, 4):
    wx, wy, wz, wallx = nums(WALL, 4); w0 = whyd()
    P("E11:", ac(f"tp {wx} {wy + 1} {wz}")); time.sleep(2.5)
    C(R + ME_ROOT + "for _,p in me.Character:GetDescendants() do if p:IsA('BasePart') then p.CanCollide=false end end "
      "for i=1,20 do r.CFrame=r.CFrame+Vector3.new(3,0,0) task.wait(0.1) end task.wait(1) return 'ok'")
    time.sleep(1.5)
    sp = spos()
    ok("E11: one cannot pass through the wall into the closed Frost Isle", sp is not None and sp[0] < wallx and wdiff(w0, whyd(), "zone") > 0, f"x={sp and sp[0]:.0f} the wall {wallx:.0f}; {whyd()}")
if SPN:
    x, y, z = SPN
    # E12: hovering in the air (BodyVelocity to zero) - flight without a dragon
    P("E12:", ac(f"tp {x + 25} {y + 4} {z}")); time.sleep(2.5); w0 = whyd(); g0 = spos()
    C(R + ME_ROOT + "local bv=Instance.new('BodyVelocity') bv.MaxForce=Vector3.new(1e7,1e7,1e7) bv.Velocity=Vector3.zero bv.Parent=r "
      "r.CFrame=r.CFrame+Vector3.new(0,15,0) task.wait(5) bv:Destroy() return 'ok'")
    time.sleep(1.5)
    ok("E12: hovering in the air is noticed (fly)", wdiff(w0, whyd(), "fly") > 0, f"{whyd()}")
    ok("E12: the server returned to the ground", spos() is not None and abs(spos()[1] - g0[1]) < 6, f"{spos()} the ground {g0}")
    # E13: running 1.6 times faster (WalkSpeed 26) - the mean on the ground above groundAvgMax
    P("E13:", ac(f"tp {x + 25} {y + 4} {z}")); time.sleep(2.5); w0 = whyd(); g0 = spos()
    C(R + "local h=me.Character.Humanoid local r=me.Character.HumanoidRootPart h.WalkSpeed=26 h:MoveTo(r.Position+r.CFrame.LookVector*200) task.wait(5) "
      "h.WalkSpeed=16 h:MoveTo(r.Position) return 'ok'")
    time.sleep(1)
    ok("E13: running x1.6 is noticed (walk)", wdiff(w0, whyd(), "walk") > 0, f"{whyd()}")
    ok("E13: the server did not let through farther than 22 studs/s on average", dist(spos(), g0, flat=True) <= 22 * 5 + 24 + 10, f"{dist(spos(), g0, flat=True):.0f} studs")
    # E14: bunny-hopping with a speed-up (WalkSpeed 30 + jumps) - a jump does not reset the run window
    P("E14:", ac(f"tp {x + 25} {y + 4} {z}")); time.sleep(2.5); w0 = whyd()
    C(R + "local h=me.Character.Humanoid local r=me.Character.HumanoidRootPart h.WalkSpeed=30 h:MoveTo(r.Position+r.CFrame.LookVector*250) "
      "for i=1,10 do h.Jump=true task.wait(0.5) end h.WalkSpeed=16 h:MoveTo(r.Position) return 'ok'")
    time.sleep(1)
    ok("E14: bunny-hopping with a speed-up is noticed", wdiff(w0, whyd(), "walk") + wdiff(w0, whyd(), "speed") > 0, f"{whyd()}")
    # E15: spinning the character (fling)
    P("E15:", ac(f"tp {x + 25} {y + 4} {z}")); time.sleep(2.5); w0 = whyd()
    C(R + ME_ROOT + "local b=Instance.new('BodyAngularVelocity') b.MaxTorque=Vector3.new(1e9,1e9,1e9) b.AngularVelocity=Vector3.new(0,200,0) b.Parent=r "
      "task.wait(1.2) b:Destroy() return 'ok'")
    time.sleep(1)
    ok("E15: spinning the character is noticed (spin)", wdiff(w0, whyd(), "spin") > 0, f"{whyd()}")
# E16: spinning the own companion on the leash (the client owns it)
P(" ld setcomp ember1 ->", S(LD + "return ld('setcomp ember1')")[:80]); time.sleep(4); w0 = whyd()
t = C(R + "local comp=nil for _,m in workspace.Companions:GetChildren() do if m:GetAttribute('OwnerId')==me.UserId then comp=m end end "
      "if not comp or not comp.PrimaryPart then return 'nocomp' end local b=comp.PrimaryPart "
      "for i=1,30 do b.AssemblyAngularVelocity=Vector3.new(0,150,0) task.wait(0.05) end return 'spun'")
time.sleep(0.8)
own = S("local p=game.Players:GetPlayers()[1] for _,m in workspace.Companions:GetChildren() do if m:GetAttribute('OwnerId')==p.UserId and m.PrimaryPart then "
        "local ok,o=pcall(function() return m.PrimaryPart:GetNetworkOwner() end) return tostring(ok and o) end end return '?'")
ok("E16: spinning the companion is noticed, the ownership is the server's", t == "spun" and wdiff(w0, whyd(), "companion") > 0 and own == "nil", f"{t}; owner={own}; {whyd()}")
time.sleep(6)
own2 = S("local p=game.Players:GetPlayers()[1] for _,m in workspace.Companions:GetChildren() do if m:GetAttribute('OwnerId')==p.UserId and m.PrimaryPart then "
         "local ok,o=pcall(function() return m.PrimaryPart:GetNetworkOwner() end) return tostring(ok and o and o.Name) end end return '?'")
ok("E16: after companionHold the ownership returned to the owner", own2 not in ("nil", "?", "false"), own2)
P("E result:", ac("stats"), "|", ac("why"))

# ================================================================================================ F: honest play with the protection
time.sleep(2); ac("reset")
P("F1 walking"); C(R + "local h=me.Character.Humanoid local r=me.Character.HumanoidRootPart h:MoveTo(r.Position+r.CFrame.LookVector*30) task.wait(4) return 'ok'")
P("F2 jumps"); C(R + "local h=me.Character.Humanoid for i=1,3 do h.Jump=true task.wait(1.2) end return 'ok'")
v_walk = violations()
ok("F1-2: walking and jumps - no violations", v_walk == 0, ac("stats"))
if FAR_EGG:
    eid, ex, ey, ez, _ = FAR_EGG.split()
    has_egg = S(f"local a=workspace.World.EggPoints:FindFirstChild('{eid}') return tostring(a and a:FindFirstChild('Egg')~=nil)")
    P("F3 the server move to the egg:", ac(f"tp {ex} {float(ey) + 3} {ez}")); time.sleep(1.5)
    pr = C(R + f"local a=workspace.World.EggPoints:FindFirstChild('{eid}') local pr=a and a:FindFirstChild('Egg') and a.Egg:FindFirstChildWhichIsA('ProximityPrompt',true) "
           "if not pr then return 'noprompt' end local ok=pcall(function() pr:InputHoldBegin() task.wait(pr.HoldDuration+0.2) pr:InputHoldEnd() end) task.wait(1) return tostring(ok)")
    got = bool(ddump().get("eggs", {}).get("carry"))
    path = "the prompt"
    if not got:
        o, why = inv("PickEgg", f"'{eid}'"); got = o; path = f"PickEgg {o}/{why}"
    ok("F3: after the server move the egg is taken honestly (by the prompt or PickEgg)", got and whyd().get("far", 0) == 0, f"{path}; prompt={pr}; egg={has_egg}; {whyd()}")
P(" ld setcomp ember0 ->", S(LD + "return ld('setcomp ember0')")[:80]); time.sleep(3)
if SPN:
    x, y, z = SPN
    P("F4 gliding:", ac(f"tp {x} {y + 90} {z}")); start_g = spos()
    C(R + "local cam=workspace.CurrentCamera local r=me.Character.HumanoidRootPart cam.CFrame=CFrame.lookAt(r.Position-Vector3.new(0,0,-10), r.Position+Vector3.new(0,0,50)) return 'ok'")
    time.sleep(7)
    g = dist(spos(), start_g, flat=True)
    ok("F4: gliding with the hatchling - no violations", violations() == 0, f"flew {g:.0f} studs horizontally; {ac('stats')}")
    if g < 40: P("F4: gliding did not start (less than 40 studs) - the check is incomplete")
UD = S("local u=workspace:FindFirstChild('CliffsUpdraft', true) if not u then return '' end return string.format('%.1f %.1f %.1f', u.Position.X, u.Position.Y - u.Size.Y/2 + 3, u.Position.Z)")
UDN = nums(UD, 3)
ok("F: the CliffsUpdraft stream is found", UDN is not None, UD)
if UDN:
    x, y, z = UDN
    P("F5 the updraft:", ac(f"tp {x} {y} {z}")); y0 = spos()
    time.sleep(4)
    ok("F5: the updraft - no violations", violations() == 0, f"rose by {(spos() or y0)[1] - y0[1]:.0f}; {ac('stats')}")
P("F6 death and respawn"); S("local p=game.Players:GetPlayers()[1] p.Character.Humanoid.Health=0 return 'ok'"); time.sleep(9)
ok("F6: the respawn - no violations", violations() == 0 and spos() is not None, ac("stats"))
P(" ld setcomp ember1 ->", S(LD + "return ld('setcomp ember1')")[:80]); time.sleep(4)
g_walk = ac("groups")
o, why = inv("Mount", f"'{UID}'"); time.sleep(2.5); g_ride = ac("groups"); o2, why2 = inv("Dismount"); time.sleep(1.5); g_back = ac("groups")
ok("F7: mounting and dismounting - no violations", o and o2 and violations() == 0, f"mount {o}/{why} dismount {o2}/{why2}; {ac('stats')}")
ok("F7: players on foot do not collide with each other and with riders", "PP=false" in g_walk and "PR=false" in g_walk and "PDef=true" in g_walk and "RDef=false" in g_walk, g_walk)
ok("F7: the character group Player -> Rider -> Player", "root=Player" in g_walk and "root=Rider" in g_ride and "root=Player" in g_back, f"{g_walk[-12:]} {g_ride[-12:]} {g_back[-12:]}")
if SPN:
    x, y, z = SPN
    P("F8 past the boundary down:", ac(f"tp {x + 40} -45 {z}")); time.sleep(5)
    ok("F8: the return by the WorldBuilder safeguard - no violations", violations() == 0 and dist(spos(), (x, y, z)) < 40, f"{spos()}; {ac('stats')}")
if nums(SEA_PT, 3):
    time.sleep(3.5)
    sx, sy, sz = nums(SEA_PT, 3)
    P("F9 honestly into the sea:", ac(f"tp {sx} {sy + 1} {sz}")); time.sleep(2.5)
    o, why = inv("Shore"); time.sleep(1.5)
    ok("F9: Back to shore from the sea works - no violations", o and violations() == 0 and dist(spos(), (sx, sy, sz), flat=True) > 8, f"{o}/{why} {spos()}; {ac('stats')}")
COL = S("local best=nil for _,d in workspace:GetDescendants() do if d:IsA('BasePart') and d.CanCollide and not d.CanQuery and d.Anchored "
        "and d.Size.Y>=2 and d.Size.Y<=30 and d.Size.X>=6 and d.Size.Z>=6 and d.Position.Y<200 and d.Transparency<1 "
        "and not d:FindFirstAncestorWhichIsA('Model') then best=d break end end "
        "if not best then for _,d in workspace:GetDescendants() do if d:IsA('BasePart') and d.CanCollide and not d.CanQuery and d.Anchored "
        "and d.Size.Y>=2 and d.Size.Y<=30 and d.Size.X>=6 and d.Size.Z>=6 and d.Position.Y<200 then best=d break end end end "
        "if not best then return '' end local top=best.CFrame*CFrame.new(0,best.Size.Y/2,0) "
        "return string.format('%.1f %.1f %.1f %s', top.Position.X, top.Position.Y, top.Position.Z, best:GetFullName():gsub(' ','_'))")
P("F12 a part without CanQuery:", COL)
if re.fullmatch(r"\S+ \S+ \S+ \S+", COL or "") and nums(" ".join(COL.split()[:3]), 3):
    cx, cy, cz = nums(" ".join(COL.split()[:3]), 3); w0 = whyd()
    P("F12:", ac(f"tp {cx} {cy + 3.5} {cz}")); time.sleep(5)
    ok("F12: standing on a step/rock without CanQuery is not flight", wdiff(w0, whyd(), "fly") == 0 and violations() == 0, f"{COL}; {spos()}; {whyd()}")
else:
    P("F12: no suitable part - the check is skipped")
P("F result:", ac("stats"), "|", ac("why"))
wf = whyd()
ok("F: for honest play no flight, no speed-up, no zone, no far presses", not any(wf.get(k, 0) for k in ("fly", "walk", "speed", "up", "zone", "spin", "seat", "spawn", "far", "companion")), json.dumps(wf))

# ================================================================================================ S: foreign scripts (backdoors)
S("local s=Instance.new('Script') s.Name='ProbeBackdoor' s.Parent=workspace.World "
  "local m=Instance.new('Model') m.Name='ProbeModel' local ms=Instance.new('ModuleScript') ms.Name='Util' ms.Parent=m m.Parent=workspace "
  "local ch=game.Players:GetPlayers()[1].Character local ls=Instance.new('LocalScript') ls.Name='ProbeKeep' ls.Disabled=true ls.Parent=ch return 'ok'")
time.sleep(1.5)
sg = S("local ch=game.Players:GetPlayers()[1].Character local pm=workspace:FindFirstChild('ProbeModel') "
       "local r=tostring(workspace.World:FindFirstChild('ProbeBackdoor')~=nil)..' '..tostring(pm~=nil and pm:FindFirstChildWhichIsA('ModuleScript')~=nil)..' '..tostring(ch:FindFirstChild('ProbeKeep')~=nil) "
       "if pm then pm:Destroy() end local k=ch:FindFirstChild('ProbeKeep') if k then k:Destroy() end return r")
sgp = (sg or "").split() + ["?", "?", "?"]
ok("S1: the planted Script in the world is removed", sgp[0] == "false", sg)
ok("S1: the ModuleScript in the model is removed", sgp[1] == "false", sg)
ok("S1: the script inside the character is untouched", sgp[2] == "true", sg)

# ================================================================================================ C: the flood and the kick
c0 = coins(); d_before = ddump()
flood = C(R + "local res={} for i=1,30 do local ok,x=pcall(function() return R.Claim:InvokeServer('calendar') end) res[#res+1]=ok and type(x)=='table' and tostring(x.ok)..'/'..tostring(x.reason) or 'err' end "
          "local n,f=0,0 for _,v in res do if v:sub(1,5)=='true/' then n+=1 end if v=='false/too_fast' then f+=1 end end return n..' '..f")
n_ok, n_fast = (int(v) for v in flood.split()) if re.match(r"^\d+ \d+$", flood or "") else (-1, -1)
ok("C1: 30 Claims in a row - not a single extra grant", n_ok == 0, f"ok={n_ok} too_fast={n_fast}")
ok("C1: the rate limit worked", n_fast >= 20, f"too_fast={n_fast}")
time.sleep(62)  # the violation count window (60 s) - nothing accumulates before the kick yet
C(R + "local A=R.Analytics for i=1,300 do A:FireServer('offer_impression', {sku='Fake'..i}) A:FireServer('shop_open', {by=string.rep('x',100)}) end "
  "for i=1,200 do R.Active:FireServer() R.Perf:FireServer(0/0, math.huge, -1, 1e9, string.rep('s',500)) R.FlightInput:FireServer(0/0, 5, -5) end return 'ok'")
time.sleep(3)
ok("C2: after 1,400 garbage events the server answers", players() == "1", players())
d_flood = ddump()
time.sleep(62)
kick = C(R + "for i=1,60 do task.spawn(function() pcall(function() R.Ascend:InvokeServer() end) end) task.wait(0.02) end return 'sent'")
time.sleep(5)
ok("C3: 60 Ascends in a row - a kick", players() == "0", f"players on the server: {players()}")

# ================================================================================================ G: the restart
stop()
js = json.dumps(d_flood, ensure_ascii=False)
assert "]=====]" not in js
P("G seed:", edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value"))
s.call("start_stop_play", {"studio_id": sid, "is_start": True})
early = ""
t0 = time.time()
while time.time() - t0 < 30 and not early:   # calls in the first seconds (the profile is still loading)
    early = C(R + "if not R:FindFirstChild('Claim') then return '' end local res={'EARLY'} "
              f"for _,c in {{{{'Claim',{{'calendar'}}}},{{'Claim',{{'timeGift','{TG_MAX}'}}}},{{'Buy',{{'free'}}}},{{'PickEgg',{{'{(FAR_EGG or 'x').split()[0]}'}}}},{{'Ascend',{{}}}},{{'ShopIntent',{{'HatchNow',nil,'1'}}}}}} do "
              "local ok,x=pcall(function() return R[c[1]]:InvokeServer(table.unpack(c[2],1,3)) end) res[#res+1]=c[1]..'='..(ok and type(x)=='table' and tostring(x.ok)..'/'..tostring(x.reason) or 'err') end "
              "return table.concat(res,' ')") or ""
    if not early.startswith("EARLY"): early = ""; time.sleep(0.3)
P("G early calls:", early)
start_t = time.time()
while time.time() - start_t < 80:
    if C("return tostring(game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') ~= nil)") == "false": break
    time.sleep(0.8)
time.sleep(5)
ok("G: the early calls granted nothing", bool(early) and "=true/" not in early.replace("ShopIntent=true/", "ShopIntent=intent/"), early)
g = ddump()
for k in ("coins", "incubators", "slots", "shelfCap", "ascension", "owned", "items", "purchases", "companion", "index"):
    a, b = d_flood.get(k), g.get(k)
    same = json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)
    if k == "coins" and not same:  # the 'while you were away' income goes into the pile/card, not into the coins; the coins can only not decrease
        same = int(b or 0) >= int(a or 0)
    ok(f"G: after the restart {k} is the same", same, f"{json.dumps(a)[:80]} -> {json.dumps(b)[:80]}")
ok("G: the dragons are the same", sorted(d_flood.get("dragons", {})) == sorted(g.get("dragons", {})), "")
P("G:", ac("enforce on")); ac("reset"); time.sleep(1)
FAR2 = S("local p=game.Players:GetPlayers()[1] local o=p.Character.HumanoidRootPart.Position local best,bd=nil,0 "
         "for _,a in workspace.World.EggPoints:GetChildren() do if a:FindFirstChild('Egg') then local d=(a.Position-o).Magnitude if d>bd then best,bd=a,d end end end "
         "if not best then return '' end return string.format('%s %.1f %.1f %.1f', best.Name, best.Position.X, best.Position.Y, best.Position.Z)")
if re.fullmatch(r"\S+ " + " ".join([NUM] * 3), FAR2 or ""):
    eid, ex, ey, ez = FAR2.split(); home = spos()
    t = C(R + ME_ROOT + f"r.CFrame=CFrame.new({ex},{float(ey) + 3},{ez}) task.wait(0.35) local a=R.PickEgg:InvokeServer('{eid}') return tostring(a.ok)..'/'..tostring(a.reason)")
    time.sleep(1.6)
    ok("G: on a fresh server a teleport to the egg does not pass", t.startswith("false/too_far") and dist(spos(), home) < 30, f"{t} {spos()} home {home}")

# ================================================================================================ the console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
net = [l for l in ctext.splitlines() if "[Net]" in l]
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[AntiCheat\] .*:\d+:|failed", l) and "not authorized" not in l and "TexturePack" not in l]
ok("console: the handlers did not crash on garbage ([Net])", not net, " ;; ".join(net[:6]))
ok("console: without script errors", not errs, " ;; ".join(errs[:6]))
P("the protection warnings:", sum(1 for l in ctext.splitlines() if "[AntiCheat]" in l))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
bad = write_result("cheat_check: the anti-cheat protection (19.10)")
s.close()
sys.exit(1 if bad else 0)
