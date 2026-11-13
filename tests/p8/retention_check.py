#!/usr/bin/env python3
"""Acceptance on P8 in a LOCAL file (after
tools/p8/open_local.sh), phone window 812x375, fresh profile, then a profile via StudioSeed.
  1) growth of a group B firstborn (LoopDebug 'abgrow B'): the mark growGroup=B, H->J 180 s, J->A 540 s; without force before D0 - group A: 120 s,
     no mark;
  2) the NEXT line: while the step banner is visible - not visible; a profile with the tutorial done - visible under the coins, cycling the nearest timer
     '<name>: Adult in m:ss', tomorrow's calendar day 'Tomorrow, Day 2: ...' (day 1 claimed) and the update 'Aurora update in ... 🔔';
     not visible while riding;
  3) calendar: day 2 - a Cliffs egg (a tile of the Gifts tab), after claiming day 1 the line 'Come back tomorrow for Day 2: ...';
  4) the Gifts tab: the block 'Next update: Aurora in ...' with the Notify me button; a real click - the Roblox RSVP window (in Studio - what
     it shows; a measurement, not a gate);
  5) console without game errors.
Run: python3 tests/p8/retention_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/retention_check/ (frames R*.jpg, result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("retention_check")
from p8lib import *  # noqa: F401,F403


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def cd(c): return C(CD + f"return cd('{c}')")
def nextup():  # ClientDebug replies 'ok | <Hints> | banner=... | ERR <command reply>' - take the reply itself
    r = cd("nextup")
    m = re.search(r"(visible=\w+ kind=\S+ text=.*? rsvp=\S+)", r)
    return m.group(1) if m else r
def first_dragon():
    d = dump()
    return next(iter((d.get("dragons") or {}).values()), None), d
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def game_errors(lines):
    return [l for l in lines if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l
            and "TexturePack" not in l and "errors 0" not in l and "RSVP" not in l]
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def hatch_first():
    P("table 2:", ld("table 2")[:80]); time.sleep(0.6)
    P("place 1:", ld("place 1")[:80]); time.sleep(3.5)
    P("hatch 1:", ld("hatch 1")[:80]); time.sleep(2)


edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
# ---------------------------------------------------------------------------------------------- 1a. group A (the live rule before D0)
stop(); start(); wait_world()
P("abgrow off:", ld("abgrow off")[:80])
hatch_first()
fa, _ = first_dragon()
P("firstborn A:", json.dumps({k: fa.get(k) for k in ("rarity", "stage", "growAs", "growGroup", "hatchedAt", "stageEndsAt")} if fa else None))
ok("1. before D0 group A: no growGroup mark, H->J 60 s (24.10: growMin 1)", fa is not None and fa.get("growGroup") is None and (fa.get("stageEndsAt") or 0) - (fa.get("hatchedAt") or 0) == 60, str(fa and {k: fa.get(k) for k in ("growGroup", "hatchedAt", "stageEndsAt")}))
# ---------------------------------------------------------------------------------------------- 1b. group B
stop(); start(); wait_world()
gb = ld("abgrow B"); P("abgrow B:", gb[:80])
ok("1. debug abgrow B with the test off (24.10, ab.on = false): group A", "group=A" in gb, gb[:80])
time.sleep(4); nu_new = nextup(); P("NEXT for a newcomer before hatching:", nu_new)
st0 = cd("state"); P("before hatching:", st0[:200])
nu0 = nextup(); P("NEXT with the step banner:", nu0)
ok("2. a newcomer before the first dragon: no NEXT line", nu_new.startswith("visible=false"), nu_new)
ok("2. while the step banner is visible, no NEXT line", "banner=" in st0 and "banner=hidden" not in st0 and nu0.startswith("visible=false"), f"{st0[:100]} | {nu0}")
shot("R0_step_banner")
hatch_first()
fb, _ = first_dragon()
P("firstborn B:", json.dumps({k: fb.get(k) for k in ("rarity", "stage", "growAs", "growGroup", "hatchedAt", "stageEndsAt")} if fb else None))
ok("1. group B with the test off: no mark, H->J 60 s", fb is not None and fb.get("growGroup") is None and fb.get("growAs") == "Common" and (fb.get("stageEndsAt") or 0) - (fb.get("hatchedAt") or 0) == 60, str(fb and {k: fb.get(k) for k in ("growGroup", "hatchedAt", "stageEndsAt")}))
ld("time 56"); time.sleep(6)
fb, _ = first_dragon()
now = int(S("return tostring(os.time())"))
left = (fb.get("stageEndsAt") or 0) - now if fb else -1
P("after time 56:", fb and fb.get("stage"), "left", left)
ok("1. firstborn teen: J->A 180 s (24.10)", fb is not None and fb.get("stage") == 1 and 168 <= left <= 181, f"stage={fb and fb.get('stage')} left={left}")
# ---------------------------------------------------------------------------------------------- 3. calendar: claim day 1
P("reward:", rw()[:200])
cl = claim("calendar"); P("claim calendar:", cl)
time.sleep(1)
C(CD + "cd('menu gifts') task.wait(1.5) return 'ok'")
note = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local o=b and b:FindFirstChild('CalNote',true) return o and o.ContentText or '-'")
P("calendar line:", note)
ok("3. day 1 claimed: 'Come back tomorrow for Day 2: <reward>'", note.startswith("Come back tomorrow for Day 2:") and len(note) > len("Come back tomorrow for Day 2: "), note)
tiles = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local out={} if b then for _,o in b:GetDescendants() do if (o:IsA('TextLabel')) and o.ContentText:find('Day 2',1,true) then out[#out+1]=o.ContentText end end end return table.concat(out,' || ')")
P("day 2 labels:", tiles)
shot("R1_gifts_calendar")
# ---------------------------------------------------------------------------------------------- 4. the Next update block and RSVP
card = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local c=b and b:FindFirstChild('NextUpdate',true) if not c then return 'none' end "
         "local h=c:FindFirstChild('Head') local r=c:FindFirstChild('Rsvp') local g=c:FindFirstChild('Going') return (h and h.ContentText or '-')..' | rsvp='..tostring(r~=nil)..' going='..tostring(g~=nil)")
P("update block:", card)
ok("4. the Gifts tab has the block 'Next update: Aurora in ...' and the Notify me button", card.startswith("Next update: Aurora in") and ("rsvp=true" in card or "going=true" in card), card)
C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local c=b and b:FindFirstChild('NextUpdate',true) if c then local l=c:FindFirstAncestorWhichIsA('ScrollingFrame') if l then l.CanvasPosition=Vector2.new(0, math.max(0, c.AbsolutePosition.Y - l.AbsolutePosition.Y + l.CanvasPosition.Y - 20)) end end return 'ok'")
time.sleep(1); shot("R2_gifts_next_update")
before = len(console_lines())
if "rsvp=true" in card:
    press("Book", "Notify me", name="click Notify me")
    time.sleep(3); desk("R3_rsvp_click"); shot("R3_rsvp_click_studio")
    after = console_lines()[before:]
    rs = [l for l in after if "RSVP" in l or "Rsvp" in l or "Social" in l]
    P("RSVP MEASUREMENT in Studio (console after the click):", " ;; ".join(rs[:4]) or "empty")
    P("NEXT after the click:", nextup())
C(CD + "cd('back') return 'ok'"); time.sleep(1)
# ---------------------------------------------------------------------------------------------- 2. NEXT in a profile without the tutorial
prof = dump()
ob = prof.setdefault("onboarding", {})
ob.update({"glided": True, "coinsCollected": True, "eggFound": True, "fedOnce": True, "rode": True, "flew": True, "ring": True})
prof["lastSeen"] = int(time.time())
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world(); time.sleep(2)
seen = {}
for i in range(40):
    nu = nextup()
    m = re.match(r"visible=(\w+) kind=(\S+) text=(.*) rsvp=(\S+)$", nu)
    if m and m.group(1) == "true" and m.group(2) not in seen:
        seen[m.group(2)] = m.group(3)
        shot(f"R4_next_{m.group(2)}")
    if len(seen) >= 3:
        break
    time.sleep(1)
P("NEXT cycling:", json.dumps(seen, ensure_ascii=False))
stb = cd("state"); P("step banner in a profile without the tutorial:", stb[:160])
ok("2. tutorial done: no step banner, the NEXT line is visible", "banner=hidden" in stb and len(seen) >= 1, f"{stb[:80]} | {seen}")
ok("2. NEXT: the nearest timer '<name>: Adult in m:ss'", re.search(r": Adult in \d+:\d\d", seen.get("grow", "")) is not None, seen.get("grow", "-"))
ok("2. NEXT: tomorrow 'Tomorrow, Day 2: ...'", seen.get("tomorrow", "").startswith("Tomorrow, Day 2:"), seen.get("tomorrow", "-"))
ok("2. NEXT: the update 'Aurora update in Nd Nh' (less than 21 days to Aurora)", re.match(r"Aurora update in \d+d \d+h", seen.get("update", "")) is not None, seen.get("update", "-"))
pos = C("local g=game.Players.LocalPlayer.PlayerGui local n=g.StepBanner:FindFirstChild('Next') local c=g.HUD:FindFirstChild('Coins') "
        "return string.format('next y=%d h=%d x=%d w=%d | coins bottom=%d', n.AbsolutePosition.Y, n.AbsoluteSize.Y, n.AbsolutePosition.X, n.AbsoluteSize.X, c.AbsolutePosition.Y + c.AbsoluteSize.Y)")
P("line position:", pos)
mm = re.search(r"next y=(-?\d+).*coins bottom=(-?\d+)", pos)
ok("2. the NEXT line right under the coins, not on them", mm is not None and 0 <= int(mm.group(1)) - int(mm.group(2)) <= 12, pos)
# the Old Ash bubble took the same slot under the coins and covered the NEXT line
ov = C("local g=game.Players.LocalPlayer.PlayerGui local n=g.StepBanner:FindFirstChild('Next') local q=g:FindFirstChild('Quests') local k=q and q:FindFirstChild('KeeperSays') "
       "if not (n and n.Visible) then return 'next hidden' end if not (k and k.Visible) then return 'bubble hidden' end "
       "local a,b=n.AbsolutePosition,n.AbsolutePosition+n.AbsoluteSize local c,d=k.AbsolutePosition,k.AbsolutePosition+k.AbsoluteSize "
       "local hit=a.X<d.X and c.X<b.X and a.Y<d.Y and c.Y<b.Y return string.format('%s next %d..%d bubble %d..%d', hit and 'OVERLAP' or 'apart', a.Y, b.Y, c.Y, d.Y)")
P("NEXT and the Old Ash bubble:", ov); shot("R5_next_and_bubble")
ok("2. the Old Ash bubble does not cover the NEXT line", not ov.startswith("OVERLAP") and ov != "next hidden", ov)
mt = S(LD + "return ld('mount')"); P("mount:", mt[:60]); time.sleep(3)
num = nextup(); P("NEXT while riding:", num)
ok("2. no NEXT line while riding", num.startswith("visible=false"), num)
S(LD + "return ld('dismount')"); time.sleep(2)
errs = game_errors(console_lines())
ok("5. console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("Retention pack (20.10 evening): growth 2/6 - 3/9 by UserId, the NEXT line, calendar day 2, Next update and RSVP")
s.close()
