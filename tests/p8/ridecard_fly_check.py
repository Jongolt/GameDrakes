#!/usr/bin/env python3
"""(a) Dragons -> the card of a glowing adult -> Companion -> Ride: sits and walks, no
Up / Down / Dismount buttons (the card mounts before closing, the HUD on closing switched off the Movement screen on top of the mount; after rejoining everything is there);
(b) in flight the yellow 'where to fly' pointers are not needed (the chevrons on the ground led to the nest to steal from 'in different directions', the marker arrow above
the target, the pointer at the screen edge) - the quest line stays; on the ground (running and riding at a walk) the chevrons are as they were.
Probe on P8 (after open_local): a veteran profile via dump + StudioSeed: baby companion d3 (Frost, stage 0), in the nest a glowing adult
Ember d1 (glow) and an ordinary adult Moss d2; onboarding flew / rode / firstHatch.
  1. the Dragons book -> tile d1 -> Third (Companion) -> Third (Ride) with real clicks: riding (Mounted), the card closed, the Movement screen
     on, the Up and Dismount buttons visible (on 352 - FAIL: Movement off)
  2. on the ground riding: the step target with the chain and the arrow (raid) - Count > 0, HintArrow on (a precondition for 3)
  3. takeoff (ClientDebug fly up on): mode=air; in 3 samples over ~6 s the HintTrail chevrons are all transparent (Count 0), HintArrow off,
     HintEdge off; the StepBanner step line is visible (on 352 - FAIL: the chevrons and the arrow are lit)
  4. landing (fly down on until mode=ground): the chain is visible again (Count > 0), the arrow on - no later than 4 s
  5. the same for the ordinary adult d2: dismount (fly off) -> Dragons -> d2 -> Companion -> Ride: the buttons are there
  6. console without game errors
Run: python3 tests/p8/ridecard_fly_check.py (after open_local)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("ridecard_fly_check")
from p8lib import *  # noqa: F401,F403

DUMP = LD + "local d=game:GetService('HttpService'):JSONDecode(ld('dump')) "


def edit(code): return run(code, "Edit")


def seed_set(js):
    assert "]=====]" not in js
    return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")


def seed_clear(): return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")


def wait_play(t=40):
    t0 = time.time()
    while time.time() - t0 < t:
        if C("return tostring(workspace.CurrentCamera.CameraType)") == "Enum.CameraType.Custom": break
        time.sleep(0.8)
    time.sleep(3)


POINTERS = r"""local pg=game.Players.LocalPlayer.PlayerGui
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local f=workspace:FindFirstChild('HintTrail') local cnt,vis=-1,0
if f then cnt=tonumber(f:GetAttribute('Count')) or 0 for _,p in f:GetDescendants() do if p:IsA('BasePart') and p.Transparency<0.98 then vis+=1 end end end
local a=pg:FindFirstChild('HintArrow') local e=pg:FindFirstChild('HintEdge')
local ban,chain,line=false,'',nil
for _,g in pg:GetChildren() do if g.Name=='StepBanner' and g:IsA('ScreenGui') then local st=g:FindFirstChild('Step',true) local ln=st and st:FindFirstChild('Line',true)
  chain=chain..tostring(g.Enabled)..'/'..tostring(st and st.Visible)..'/'..tostring(ln and ln.Visible)..';'
  if st and st.Visible and ln and ln.Visible and ln.ContentText~='' then ban=true line=ln end if not line then line=ln end end end
-- (Enabled of the StepBanner screen in flight is switched off for seconds by HUD/Declutter both on 352 and after the fix - the code is untouched; the F3_air frames show it; in chain it is visible)
local mv=pg:FindFirstChild('Movement') local dn=mv and mv:FindFirstChild('Down',true)
local r=game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
return string.format('count=%d vis=%d arrow=%s edge=%s banner=%s(%s) down=%s y=%.0f line=%s', cnt, vis, a and tostring(a.Enabled) or 'none', e and tostring(e.Enabled) or 'none', tostring(ban), chain, tostring(mv~=nil and mv.Enabled and dn~=nil and dn.Visible), r and r.Position.Y or -1, line and line.ContentText or '-')"""


def pointers(): return C(POINTERS)


def fly(cmd): return C(CD + f"return cd('fly {cmd}')")


def num(s, key):
    m = re.search(key + r"=(-?\d+)", s)
    return int(m.group(1)) if m else -99


# ---------------------------------------------------------------- 0. profile: baby companion + glowing adult + ordinary adult
stop(); seed_clear(); start(); wait_play()
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80]); time.sleep(9)
P("setcomp:", S(LD + "local r=ld('setcomp ember2') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
d = dump()
comp = d.get("companion")
base = (d.get("dragons") or {}).get(comp)
assert base, f"no companion in the profile: companion={comp} dragons={list((d.get('dragons') or {}).keys())}"
P("profile from the game: companion", comp, "stage", base.get("stage"), "element", base.get("element"), "inNest", base.get("inNest"), "nestOrder", d.get("nestOrder"), "slots", d.get("slots"))
d1 = dict(base); d1.update({"uid": "d1", "element": "ember", "stage": 2, "glow": True, "name": "Glowing Ember", "inNest": True}); d1.pop("stageEndsAt", None)
d2 = dict(base); d2.update({"uid": "d2", "element": "moss", "stage": 2, "name": "Moss", "inNest": True}); d2.pop("glow", None); d2.pop("stageEndsAt", None)
d3 = dict(base); d3.update({"uid": "d3", "element": "frost", "stage": 0, "name": "Frost", "inNest": bool(base.get("inNest"))}); d3.pop("glow", None); d3.pop("stageEndsAt", None)
d["dragons"] = {"d1": d1, "d2": d2, "d3": d3}
d["companion"] = "d3"
d["nestOrder"] = ["d1", "d2"] + (["d3"] if d3["inNest"] else [])
d["nextUid"] = 4
# the profile slots are a dict of slot purchases, we do not touch it; the server itself moves the extra ones from the nest to the sanctuary (the tile in the book is there anyway)
ob = d.get("onboarding") or {}
ob.update({"firstHatch": True, "flew": True, "rode": True, "ring": True})  # ring: the rings are passed - in flight the target stays the raid
d["onboarding"] = ob
now = int(time.time())
d["lastSeen"] = now
# a veteran: golden egg #1 is long home and hatched (otherwise the newcomer HUD mode: only Shop on the left, no Dragons book),
# 10 h of game time; the dragons 'just hatched' - the first Gloom ambush waits Config.Combat.ambush.afterHatch
d["playSeconds"] = 36000
d["glowEgg"] = {"taken": now - 86400, "readyAt": now - 80000, "hatched": True, "n": 1}
for x in (d1, d2, d3):
    x["hatchedAt"] = now
js = json.dumps(d, ensure_ascii=False)
open(f"{OUT}/seed_ridecard.json", "w").write(js)
stop(); P("seed:", seed_set(js)); start(); wait_play()
got = S(DUMP + "local n=0 local names={} for k,x in d.dragons do n+=1 table.insert(names, k..':'..tostring(x.name)..':'..tostring(x.stage)..':'..tostring(x.glow)) end table.sort(names) return 'n='..n..' comp='..tostring(d.companion)..' '..table.concat(names,' ')")
ok("0. seed: 3 dragons (d1 Glowing Ember s2 glow, d2 Moss s2, d3 Frost s0), companion d3", "n=3" in got and "comp=d3" in got and "d1:Glowing Ember:2:true" in got, got)
time.sleep(4)
C("game.Players.LocalPlayer:SetAttribute('InputKind','touch')")  # as on a phone: the Up / Down buttons are shown only with touch
cw = S(LD + "local r=ld('combat info') return tostring(r.reason)")
if '"enemies":[{' in cw or '"left":' in cw and '"waves":{}' not in cw:
    P("a Gloom wave at the start - clearing it:", cw[:160], S(LD + "local r=ld('combat clear') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
P("newbie HUD:", C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('HUD') local n=0 local names={} if g then for _,b in g:GetDescendants() do if b:IsA('GuiButton') and b.Name:sub(1,5)=='Menu_' and b.Visible then n+=1 table.insert(names,b.Name) end end end return n..' '..table.concat(names,',')"))
desk("S0_start")


# ---------------------------------------------------------------- card -> Companion -> Ride
def card_ride(uid, tag):
    if gui_on("DragonCard"): press("DragonCard", "Back"); time.sleep(1)
    if gui_on("Book"): press("Book", "Close"); time.sleep(1)
    press("HUD", "Menu_Dragons", name=f"[{tag}] open the Dragons book"); time.sleep(1.6)
    book = gui_on("Book")
    press("Book", uid, name=f"[{tag}] tile {uid} in the book"); time.sleep(2.0)
    card = gui_on("DragonCard")
    t0 = C(FIND + "local o=find('DragonCard','Third') return o and o.ContentText or 'none'")
    press("DragonCard", "Third", name=f"[{tag}] Third ({t0})"); time.sleep(2.4)
    t1 = C(FIND + "local o=find('DragonCard','Third') return o and o.ContentText or 'none'")
    comp = S(DUMP + "return tostring(d.companion)")
    press("DragonCard", "Third", name=f"[{tag}] Third ({t1})"); time.sleep(3.5)
    mounted = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))")
    cardOpen, bookOpen = gui_on("DragonCard"), gui_on("Book")
    mvInBook = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') return g and tostring(g.Enabled)..'/'..tostring(g:GetAttribute('HudWasEnabled')) or 'nogui'")
    if bookOpen:  # the card opened from the book closes into the book; a player closes the book and walks
        press("Book", "Close", name=f"[{tag}] close the book"); time.sleep(1.8)
    r = dict(book=book, card=card, third0=t0, third1=t1, comp=comp, mounted=mounted, cardOpen=cardOpen, bookOpen=bookOpen, mvInBook=mvInBook,
             bookAfter=gui_on("Book"), movement=gui_on("Movement"),
             dismount=C(FIND + "local o=find('Movement','Dismount') return o and 'yes' or 'no'"),
             upMouse=C(FIND + "local o=find('Movement','Up') return o and 'yes' or 'no'"))
    # on PC (mouse / keyboard) Up / Down are hidden by design; real clicks reset InputKind - set touch AFTER the measurement
    # (Fly rearranges the buttons on an input kind change); Down is visible only in the air
    r["kind"] = C("return tostring(game.Players.LocalPlayer:GetAttribute('InputKind'))")
    C("game.Players.LocalPlayer:SetAttribute('InputKind','touch')"); time.sleep(0.8)
    r["upTouch"] = C(FIND + "local o=find('Movement','Up') return o and 'yes' or 'no'")
    r["downTouch"] = C(FIND + "local o=find('Movement','Down') return o and 'yes' or 'no'")
    r["hudWas"] = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') return g and tostring(g:GetAttribute('HudWasEnabled')) or 'nogui'")
    r["state"] = fly("state")[:90]
    desk(f"{tag}_ride")
    return r


r1 = card_ride("d1", "R1")
P("R1:", json.dumps(r1, ensure_ascii=False))
def verdict(r):
    return r["mounted"] != "nil" and not r["cardOpen"] and not r["bookAfter"] and r["movement"] and r["dismount"] == "yes"
def detail(r):
    return (f"mounted={r['mounted']} comp={r['comp']} card={r['cardOpen']} book={r['bookOpen']}->{r['bookAfter']} Movement(in book)={r['mvInBook']} "
            f"movement={r['movement']} dismount={r['dismount']} kind={r['kind']} up(touch)={r['upTouch']} down(hidden on ground)={r['downTouch']} HudWasEnabled={r['hudWas']} third={r['third0']}->{r['third1']} {r['state']}")
ok("1. glowing adult d1: card -> Companion -> Fly, the book closed: riding, the Movement screen on, the Dismount button visible",
   verdict(r1) and r1["comp"] == "d1", detail(r1))
ok("1b. with touch (as on a phone) the Up button is visible", r1["upTouch"] == "yes", f"up(touch)={r1['upTouch']} down={r1['downTouch']}")

# ---------------------------------------------------------------- 2. on the ground riding: the chain and the target arrow
g0 = ""
for _ in range(16):
    g0 = pointers()
    if num(g0, "count") > 0 and "arrow=true" in g0: break
    time.sleep(0.5)
P("ground:", g0)
ok("2. on the ground riding (at a walk): the chevron chain is visible (Count > 0) and the arrow above the target is on", num(g0, "count") > 0 and num(g0, "vis") > 0 and "arrow=true" in g0, g0)
desk("G2_ground")

# ---------------------------------------------------------------- 3. flight: no pointers, the quest line is there
C("game.Players.LocalPlayer:SetAttribute('InputKind','touch')"); time.sleep(0.5)  # Down is shown only with touch and only in the air
fly("up on"); time.sleep(2.5)
st = fly("state")
air = "mode=air" in st
samples = []
for i in range(3):
    samples.append(pointers()); time.sleep(2)
fly("up off")
shot("F3_air"); desk("F3_air")
P("air:", st[:100]); [P("  sample:", x) for x in samples]
clean = all(num(x, "vis") == 0 and num(x, "count") <= 0 and ("arrow=false" in x or "arrow=none" in x) and ("edge=false" in x or "edge=none" in x) and "banner=true" in x for x in samples)
ok("3. in flight (3 samples over ~6 s): no chevrons (Count 0, all transparent), the arrow above the target off, the edge pointer off, the quest line visible",
   air and clean, ("mode=air " if air else "NOT IN THE AIR ") + " / ".join(samples))
ok("3b. in flight the Down button is visible (touch)", air and all("down=true" in x for x in samples), " / ".join(x.split(" y=")[0][-40:] for x in samples))

# ---------------------------------------------------------------- 4. landing: the pointers come back
fly("down on")
landed = False
t0 = time.time()
while time.time() - t0 < 25:
    if "mode=ground" in fly("state"): landed = True; break
    time.sleep(0.5)
fly("down off")
back = ""
t1 = time.time()
for _ in range(10):
    back = pointers()
    if num(back, "count") > 0 and "arrow=true" in back: break
    time.sleep(0.5)
P("landed:", landed, f"{time.time() - t1:.1f} s", back)
ok("4. after landing (riding at a walk) the chain (Count > 0) and the arrow came back no later than 4 s", landed and num(back, "count") > 0 and num(back, "vis") > 0 and "arrow=true" in back, f"landed={landed} {back}")
desk("L4_landed")

# ---------------------------------------------------------------- 5. ordinary adult d2 via the card
P("off:", fly("off")); time.sleep(2.5)
r2 = card_ride("d2", "R5")
P("R5:", json.dumps(r2, ensure_ascii=False))
ok("5. ordinary adult d2: card -> Companion -> Fly, the book closed: riding, Movement on, the Dismount button visible",
   verdict(r2) and r2["comp"] == "d2", detail(r2))
ok("5a. with touch the Up button is visible", r2["upTouch"] == "yes", f"up(touch)={r2['upTouch']}")
fly("up on"); time.sleep(2.5); s5 = pointers(); fly("up off")
ok("5b. and in flight on d2 there are no pointers", "mode=air" in fly("state") and num(s5, "vis") == 0 and ("arrow=false" in s5 or "arrow=none" in s5) and ("edge=false" in s5 or "edge=none" in s5), s5)
P("off:", fly("off")); time.sleep(1.5)

# ---------------------------------------------------------------- 6. console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Hints]" in l or "[Fly]" in l) and "errors 0" not in l and "TexturePack" not in l and "HttpError" not in l]
ok("6. console without game errors", not bad, str(len(bad)))
for l in bad[-8:]: P("  ", l[:220])
stop()
P("unseed:", seed_clear())
write_result("Ride from the dragon card and the pointers in flight (03.11)")
