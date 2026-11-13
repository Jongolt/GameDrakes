#!/usr/bin/env python3
"""The NEXT line on the 'while you were away' card. P8, the LOCAL file (after tools/p8/open_local.sh),
the phone window 812x375. A fresh profile -> the first dragon -> the profile via StudioSeed as returned after 2 h (sessions 3, the tutorial
passed) -> the entry:
  1) the card is open, the NEXT line is visible, the text is one of the elements (a timer / tomorrow / an update);
  2) in rotation over ~14 s at least two different elements;
  3) the layout: NEXT above Collect and under the news lines, nothing overlaps, everything inside the card;
  4) a tap on the update line - the RSVP window (in Studio - a console measurement, not a gate);
  5) Collect closes the card; the console without game errors.
Run: python3 tests/p8/away_next_check.py. The output: $P8_OUT_ROOT/roblox_build_<date>/away_next_check/ (frames A*.jpg, result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("away_next_check")
from p8lib import *  # noqa: F401,F403


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def away():
    r = C(CD + "return cd('away')")
    m = re.search(r"(open=.*)$", r)
    return m.group(1) if m else r
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
GEO = ("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('AwayCard') if not g then return 'nocard' end local p=g:FindFirstChild('AwayPanel',true) "
       "local n=g:FindFirstChild('Next',true) local c=g:FindFirstChild('Collect',true) local out={} "
       "local function r(o) return o.AbsolutePosition.Y, o.AbsolutePosition.Y+o.AbsoluteSize.Y, o.AbsolutePosition.X, o.AbsolutePosition.X+o.AbsoluteSize.X end "
       "local pt,pb,pl,pr=r(p) local nt,nb,nl,nr=r(n) local ct,cb=r(c) local lb=-1 for _,o in g:GetDescendants() do if o:IsA('TextLabel') and o.Name:match('^Line%d') then local _,b=r(o) lb=math.max(lb,b) end end "
       "local lh=999 for _,o in g:GetDescendants() do if o:IsA('TextLabel') and o.Name:match('^Line%d') then lh=math.min(lh,o.TextBounds.Y) end end "
       "local cr=n:FindFirstChild('Line') return string.format('panel %d..%d x%d..%d | next %d..%d x%d..%d fits=%s | collect %d..%d | lines bottom %d text %d', pt,pb,pl,pr,nt,nb,nl,nr,tostring(cr and cr.TextFits),ct,cb,lb,lh)")

edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
stop(); start(); wait_world()
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(4)
prof = dump()
prof["sessions"] = 3
now = int(time.time())
prof["lastSeen"] = now - 7200
# the card news: a dragon grew up while away, an egg in the incubator is ready (the lines '... grew to ...', '1 egg ready to hatch')
for d in (prof.get("dragons") or {}).values():
    if (d.get("stage") or 0) < 3:
        d["stageEndsAt"] = now - 60
prof.setdefault("eggs", {}).setdefault("incubating", {})
if isinstance(prof["eggs"]["incubating"], list):
    prof["eggs"]["incubating"] = {}
prof["eggs"]["incubating"]["1"] = {"egg": {"id": "probe", "element": "moss", "rarity": "Common", "shiny": False, "size": "normal", "zone": "Meadow", "rareNest": False}, "endsAt": now - 30}
ob = prof.setdefault("onboarding", {})
ob.update({"glided": True, "coinsCollected": True, "eggFound": True, "fedOnce": True, "rode": True, "flew": True, "ring": True})
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world()
st = "-"
for _ in range(20):
    st = away()
    if st.startswith("open=true"):
        break
    time.sleep(1)
P("the card:", st)
time.sleep(1); shot("A1_away_next")
kinds = {}
for _ in range(32):
    a = away()
    m = re.search(r"next=(.*)$", a)
    t = m.group(1) if m else "-"
    k = ("update" if re.match(r".+ update in \d+", t) else "grow" if re.search(r": \w+ in \d", t) else "hatch" if t.startswith("Egg hatches in")
         else "tomorrow" if t.startswith("Tomorrow, Day") else "-")
    if k != "-" and k not in kinds:
        kinds[k] = t
        shot(f"A2_next_{k}")
    if len(kinds) >= 2:
        break
    time.sleep(0.5)
P("the NEXT elements in rotation:", json.dumps(kinds, ensure_ascii=False))
ok("1. the 'while you were away' card is open, the NEXT line is visible", st.startswith("open=true news=true") and "next=-" not in st, st[:200])
ok("1. the news on the card: growth and a ready egg", "grew to" in st and "ready to hatch" in st, st[:200])
ok("1. the NEXT text - a timer, tomorrow or an update", len(kinds) >= 1, json.dumps(kinds, ensure_ascii=False))
ok("2. two different elements in rotation", len(kinds) >= 2, json.dumps(kinds, ensure_ascii=False))
geo = C(GEO); P("the layout:", geo)
mm = re.search(r"panel (\d+)\.\.(\d+) x(\d+)\.\.(\d+) \| next (\d+)\.\.(\d+) x(\d+)\.\.(\d+) fits=(\w+) \| collect (\d+)\.\.(\d+) \| lines bottom (-?\d+)", geo)
if mm:
    pt, pb, pl, pr, nt, nb, nl, nr, fits, ct, cb, lb = mm.groups()
    pt, pb, pl, pr, nt, nb, nl, nr, ct, cb, lb = map(int, (pt, pb, pl, pr, nt, nb, nl, nr, ct, cb, lb))
    ok("3. NEXT above Collect, no overlap", nb <= ct, geo)
    ok("3. NEXT under the news lines (the lines exist)", 0 < lb <= nt, geo)
    ok("3. NEXT inside the card, the text fits", pl <= nl and nr <= pr and pt <= nt and fits == "true", geo)
    th = re.search(r"text (\d+)", geo)
    ok("3. the news lines not smaller than 13 px (readable on a phone)", th is not None and int(th.group(1)) >= 13, geo)
else:
    ok("3. the layout was read", False, geo)
before = len(console_lines())
for _ in range(20):
    a = away()
    if re.search(r"next=.+ update in \d+", a):
        break
    time.sleep(0.5)
if re.search(r"next=.+ update in \d+", a):
    press("AwayCard", "Next", name="a tap on the update line")
    time.sleep(3); desk("A3_rsvp_tap")
    rs = [l for l in console_lines()[before:] if "RSVP" in l or "Rsvp" in l or "Social" in l]
    P("RSVP MEASUREMENT from the card (the console):", " ;; ".join(rs[:4]) or "empty")
press("AwayCard", "Collect", name="Collect")
time.sleep(2)
st2 = away(); P("after Collect:", st2)
ok("5. Collect closes the card", st2.startswith("open=false"), st2[:120])
errs = game_errors(console_lines())
ok("5. the console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("The NEXT line on the 'while you were away' card (21.10, spec 06 add. 21.10 (3))")
s.close()
