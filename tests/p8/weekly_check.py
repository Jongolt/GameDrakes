#!/usr/bin/env python3
"""Acceptance on P8 in a LOCAL file (after
tools/p8/open_local.sh), phone window 812x375, fresh profile, then a profile via StudioSeed (a returning player).
  1) before the date (live 0): no weekly quests - neither in the server state nor in the Quests tab;
  2) LiveOpsDebug 'update 1': the Aurora set (week 2966) - in the Quests tab the block 'Weekly quests: Aurora - new in 6d 23h' and two lines
     with the reward '+5 pts, Summit egg'; no toast for a newcomer;
  3) a real hatch from the incubator in Aurora - hatchSky_aurora 1/2; no new events go into the Keeper counters;
  4) closing W1 (the second event): +5 season points, a Summit egg on the shelf, the banner 'Weekly quest done! ...' / '+5 season points, Summit egg';
  5) Glacier by a real hatch (Frost with Summit in Aurora) - W2 closed, +5, the banner visible after the hatch scene (the banner queue);
     the Quests tab - both lines Done; the Gifts tab - the season line about the weekly quests;
  6) the next Sun 19:00 (offset +a week) - the Cinder set from zero; an Ember egg hatched - emberHatch 1/3, Ember growth - emberGrow;
  7) a returning player (sessions 5): after update 1 - the toast 'New weekly quests - see Quests' once;
  8) Nightfall after the season closes (04.12 19:00): a night Dusk hatch - nightHatch and duskHatch accumulate, closing - a Cliffs egg without
     points; the week after Nightfall - the same set from zero;
  9) console without game errors.
Run: python3 tests/p8/weekly_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/weekly_check/ (frames W*.jpg, result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("weekly_check")
from p8lib import *  # noqa: F401,F403

AURORA, CINDER, NIGHTFALL, SEASON_END = 1794164400, 1794769200, 1795978800, 1796410800


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def wd(cmd): return S(f"return game.ServerStorage.WeatherDebug:Invoke('{cmd}')")
def wk():  # 'u1 w2966 [auroraHatch 0/2, glacier 0/1] left=...' or 'off'
    r = rw()
    m = re.search(r"\| weekly (.*?) \| gifts", r)
    return m.group(1) if m else r
def offset_to(t):  # the live ops clock at the moment t (UTC)
    now = int(S("return tostring(os.time())"))
    return lo(f"offset {t - now}")
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
# banners and toasts the player saw (in order, without consecutive repeats) - the WkSeen attribute on PlayerGui
WATCH = ("local pg=game.Players.LocalPlayer.PlayerGui pg:SetAttribute('WkSeen','') pg:SetAttribute('WkRun',(pg:GetAttribute('WkRun') or 0)+1) local my=pg:GetAttribute('WkRun') "
         "task.spawn(function() local last='' while pg:GetAttribute('WkRun')==my do local g=pg:FindFirstChild('Banners') local b=g and g:FindFirstChild('Banner') local t=g and g:FindFirstChild('Toast') "
         "local cur='' if b and b.Visible then cur='B:'..b.L1.ContentText..' / '..b.L2.ContentText end if t and t.Visible and t.ContentText~='' then cur=cur..(cur~='' and ' + ' or '')..'T:'..t.ContentText end "
         "if cur~='' and cur~=last then pg:SetAttribute('WkSeen',(pg:GetAttribute('WkSeen') or '')..' || '..cur) end last=cur task.wait(0.1) end end) return 'watch'")
def watch(): return C(WATCH)
def seen(): return C("return game.Players.LocalPlayer.PlayerGui:GetAttribute('WkSeen') or ''")
QT = ("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local function row(n) local r=b and b:FindFirstChild(n,true) if not r then return '-' end local t={} "
      "for _,o in r:GetChildren() do if o:IsA('TextLabel') then table.insert(t,{o.AbsolutePosition.X,o.ContentText}) end end table.sort(t,function(a,c) return a[1]<c[1] end) "
      "local out={} for _,x in t do table.insert(out,x[2]) end return table.concat(out,' | ') end "
      "local h=b and b:FindFirstChild('WeeklyHeader',true) local g=b and b:FindFirstChild('WeeklyBadge',true) "
      "return (h and h.ContentText or 'nohead')..' ## '..row('Weekly1')..' ## '..row('Weekly2')..' ## badge='..(g and g.ContentText or '-')")
def quests_tab(name=None):
    C(CD + "cd('menu quests') task.wait(1.5) return 'ok'")
    r = C(QT)
    if name:
        shot(name)
    C(CD + "cd('back') return 'ok'"); time.sleep(0.8)
    return r
def progress(w):  # «auroraHatch 1/2» -> {"auroraHatch": 1}
    return {k: int(v) for k, v in re.findall(r"(\w+) (\d+)/\d+", w)}
def daily_pts(d):  # season points from the dailies on this day (1 per quest, 1 for all three)
    dl = d.get("quests", {}).get("daily", {})
    return sum(1 for v in (dl.get("done") or {}).values() if v) + (1 if dl.get("bonus") else 0)
def hatch_egg(el, zone, weather=None, phase=None):
    """Bowl 1 is free (hatch an occupied one by day without weather) -> an egg of element el of zone zone into the hands -> incubator 1 -> ready ->
    (weather / phase) -> Hatch; the new dragons"""
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
    ld("go pile"); time.sleep(1)
    if (dump()["eggs"].get("incubating") or {}).get("1"):
        for _ in range(2):
            ld("time 9999999"); time.sleep(1.5)
        P("bowl occupied - hatch:", ld("hatch 1")[:60]); time.sleep(5)
    P("egg:", lo(f"egg {el} {zone}")[:80])
    ld("go inc"); time.sleep(2)
    P("place 1:", ld("place 1")[:60]); time.sleep(2)
    for _ in range(2):
        ld("time 9999999"); time.sleep(1.5)
    nb0 = set(dump()["dragons"].keys())
    globals()["w_before"] = wk()
    if weather:
        P("weather:", wd(weather)[:60])
    if phase:
        S(f"game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','{phase}') task.wait(2) return 'ok'")
    P("hatch 1:", ld("hatch 1")[:80]); time.sleep(3)
    ld("go pile"); time.sleep(1)  # away from the bowl: at the ring (3.8 studs) a shelf egg goes into the incubator by itself
    d = dump()
    return [v for k, v in d["dragons"].items() if k not in nb0], d
def weekly_eggs(d):  # the weekly reward eggs: on the shelf or already in an incubator
    out = [e for e in (d["eggs"].get("shelf") or []) if e.get("id") == "weekly"]
    out += [r.get("egg") for r in (d["eggs"].get("incubating") or {}).values() if (r.get("egg") or {}).get("id") == "weekly"]
    return out


edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
# ---------------------------------------------------------------------------------------------- 1. before the date
stop(); start(); wait_world()
S(LD + "return ld('firstegg off')")  # the manual first egg path (auto - firstegg_check.py)
st0 = lo("state"); w0 = wk(); P("start:", st0[:60], "| weekly:", w0)
q0 = quests_tab("W0_quests_before")
P("tab before the date:", q0)
ok("1. before the date: live=0, no weekly quests (server)", st0.startswith("live=0") and w0 == "off", f"{st0[:30]} | {w0}")
ok("1. before the date: no weekly block in the Quests tab", q0.startswith("nohead"), q0[:80])
# ---------------------------------------------------------------------------------------------- 2. update 1
watch()
P("update 1:", lo("update 1")[:60]); time.sleep(12)  # the Reward tick every 10 s - the week reset
w1 = wk(); P("week:", w1)
ok("2. update 1: the Aurora set, week 2966, 0/2 and 0/1", w1.startswith("u1 w2966 [auroraHatch 0/2, glacier 0/1]"), w1)
q1 = quests_tab("W1_quests_aurora")
P("tab:", q1)
ok("2. tab: 'Weekly quests: Aurora  -  new in 6d 23h'", q1.startswith("Weekly quests: Aurora  -  new in 6d 23h"), q1[:60])
ok("2. line 1: Week | Hatch 2 dragons under the aurora | 0/2 | +5 pts, Summit egg", "## Week | Hatch 2 dragons under the aurora | 0/2 | +5 pts, Summit egg ##" in q1, q1)
ok("2. line 2: Hatch a Glacier dragon | 0/1", "Week | Hatch a Glacier dragon | 0/1 | +5 pts, Summit egg" in q1, q1)
ok("2. badge: 'Complete one: Aurora 2026 badge' (R9)", q1.endswith("badge=Complete one: Aurora 2026 badge"), q1[-60:])
ok("2. no weekly toast for a newcomer", "New weekly quests" not in seen(), seen()[-200:])
# ---------------------------------------------------------------------------------------------- 3. a real hatch in Aurora
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(1)
wd("aurora"); time.sleep(3)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(3)
ld("go pile"); time.sleep(1)
w3 = wk(); P("after the hatch in Aurora:", w3)
ok("3. a hatch from the incubator in Aurora: auroraHatch 1/2", "auroraHatch 1/2" in w3, w3)
qc = dump().get("quests", {}).get("counters", {})
ok("3. no new events go into the Keeper counters", not [k for k in qc if re.match(r"(hatchEl|hatchSky|hatchAt|growEl|variant)_", k)], json.dumps(qc)[:200])
# ---------------------------------------------------------------------------------------------- 4. closing W1
d4 = dump(); pts0 = d4["rewards"]["season"]["points"]; shelf0 = len(weekly_eggs(d4))
watch()
r4 = rw("weekly hatchSky_aurora 1"); time.sleep(1.2)
d4b = dump(); pts1 = d4b["rewards"]["season"]["points"]; shelf = weekly_eggs(d4b)
shot("W2_banner_w1")
time.sleep(1); sn4 = seen(); P("banners:", sn4)
w4 = wk(); P("week:", w4, "| points", pts0, "->", pts1, "| shelf", shelf0, "->", len(shelf), "| last", json.dumps(shelf[-1] if shelf else None)[:120])
ok("4. W1 closed: auroraHatch ✓", "auroraHatch 2/2✓" in w4, w4)
ok("4. +5 season points", pts1 - pts0 == 5, f"{pts0}->{pts1}")
ok("4. a Summit egg on the shelf", len(shelf) == shelf0 + 1 and shelf[-1].get("zone") == "Summit", json.dumps(shelf[-1] if shelf else None)[:120])
ok("4. the banner 'Weekly quest done! Hatch 2 dragons under the aurora / +5 season points, Summit egg'",
   "B:Weekly quest done! Hatch 2 dragons under the aurora / +5 season points, Summit egg" in sn4, sn4[-300:])
# ---------------------------------------------------------------------------------------------- 5. Glacier
watch()
dp1 = daily_pts(dump())
newd, d5 = hatch_egg("frost", "Summit", weather="aurora")
dp2 = daily_pts(d5)
P("hatched:", json.dumps(newd)[:200])
time.sleep(9); sn5 = seen(); P("banners after Glacier:", sn5)
shot("W3_after_glacier")
w5 = wk(); pts2 = d5["rewards"]["season"]["points"]
P("week:", w5, "| points", pts1, "->", pts2)
ok("5. Glacier hatched (Frost with Summit in Aurora)", len(newd) == 1 and newd[0].get("variant") == "glacier", json.dumps(newd)[:120])
ok("5. W2 closed, +5 points (without the daily points)", "glacier 1/1✓" in w5 and pts2 - pts1 - (dp2 - dp1) == 5, f"{w5} | {pts1}->{pts2}, dailies {dp1}->{dp2}")
ok("5. the W2 banner visible after the hatch scene", "B:Weekly quest done! Hatch a Glacier dragon" in sn5, sn5[-300:])
q5 = quests_tab("W4_quests_done")
P("tab:", q5)
bd = dump().get("badges") or {}
P("MEASUREMENT the Aurora 2026 badge in Studio: profile badges.aurora2026 =", bd.get("aurora2026"), "| line:", q5[q5.find("badge="):])
ok("5. the badge after closing: '✓ Aurora 2026 badge' (awarded) or 'Complete one' (Studio does not award) - no errors", q5.endswith("badge=✓ Aurora 2026 badge") or q5.endswith("badge=Complete one: Aurora 2026 badge"), q5[-60:])
ok("5. tab: both lines Done", q5.count("| Done |") == 2, q5)
C(CD + "cd('menu gifts') task.wait(1.5) return 'ok'")
sh = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local o=b and b:FindFirstChild('SeasonHead',true) return o and o.ContentText or '-'")
shot("W5_gifts_season"); C(CD + "cd('back') return 'ok'"); time.sleep(0.8)
P("season in the Gifts tab:", sh)
ok("5. the season line names the weekly quests (5 each)", "weekly quests 5 each" in sh and str(pts2) in sh, sh)
# ---------------------------------------------------------------------------------------------- 6. next week: Cinder
P("offset -> 15.11:", offset_to(CINDER + 5)[:60]); time.sleep(12)
w6 = wk(); P("week:", w6)
ok("6. Sun 19:00: the Cinder set from zero (week 2967)", w6.startswith("u2 w2967 [emberHatch 0/3, emberGrow 0/2]"), w6)
q6 = quests_tab("W6_quests_cinder")
ok("6. the Cinder week badge: 'Cinder 2026'", "Cinder 2026 badge" in q6, q6[-60:])
ok("6. tab: Cinder and Ember", q6.startswith("Weekly quests: Cinder") and "Hatch 3 Ember dragons | 0/3 | +5 pts, Springs egg" in q6, q6)
newe, _ = hatch_egg("ember", "Meadow")
P("Ember:", json.dumps(newe)[:160])
w6b = wk(); P("after Ember:", w6b)
ok("6. Ember hatched - emberHatch +1", len(newe) == 1 and newe[0].get("element") == "ember" and progress(w6b).get("emberHatch", 0) - progress(w_before).get("emberHatch", 0) == 1, f"{w_before} -> {w6b}")
if newe and not newe[0].get("inNest"):  # the nest is full (3 slots) - Ember goes to the sanctuary, they do not grow there: Move into the nest, like a player
    time.sleep(0.6)
    P("Ember into the nest:", C("local r=game.ReplicatedStorage.Remotes.MoveDragon:InvokeServer('%s','nest') return tostring(r.ok)..'/'..tostring(r.reason)" % newe[0]["uid"]))
ld("time 9999999"); time.sleep(5)
w6c = wk(); P("after the growth:", w6c)
ok("6. Ember growth - emberGrow accumulates", re.search(r"emberGrow [12]/2", w6c) is not None, w6c)
# ---------------------------------------------------------------------------------------------- 8. Nightfall after the season closes
P("offset -> 04.12 19:01:", offset_to(SEASON_END + 60)[:60]); time.sleep(12)
w8 = wk(); P("week:", w8)
ok("8. 04.12 after the season closes: the Nightfall set (week 2969)", w8.startswith("u4 w2969 [nightHatch 0/2, duskHatch 0/3]"), w8)
d8 = dump(); pts3 = d8["rewards"]["season"]["points"]
newn, d8b = hatch_egg("dusk", "Cliffs", phase="night")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
w8b = wk(); P("after the night Dusk:", w8b, json.dumps(newn)[:120])
pb, pa = progress(w_before), progress(w8b)
ok("8. a night Dusk hatch: nightHatch +1 and duskHatch +1", len(newn) == 1 and newn[0].get("element") == "dusk" and pa.get("nightHatch", 0) - pb.get("nightHatch", 0) == 1 and pa.get("duskHatch", 0) - pb.get("duskHatch", 0) == 1, f"{w_before} -> {w8b}")
watch()
rw("weekly hatchAt_night 2"); time.sleep(1.5)
d8c = dump(); sn8 = seen(); P("banners:", sn8)
shelf3, shelf8 = weekly_eggs(d8b), weekly_eggs(d8c)
ok("8. after 04.12: closing - a Cliffs egg without points", d8c["rewards"]["season"]["points"] == d8b["rewards"]["season"]["points"] and len(shelf8) == len(shelf3) + 1 and shelf8[-1].get("zone") == "Cliffs",
   f"points {d8b['rewards']['season']['points']}->{d8c['rewards']['season']['points']} weekly eggs {len(shelf3)}->{len(shelf8)}")
ok("8. the banner without points: '... / Cliffs egg'", "B:Weekly quest done! Hatch 2 dragons at night / Cliffs egg" in sn8, sn8[-200:])
P("offset -> 06.12 19:05:", offset_to(NIGHTFALL + 604800 + 5)[:60]); time.sleep(12)
w8d = wk(); P("week after Nightfall:", w8d)
ok("8. a week without a new update: Nightfall from zero (week 2970)", w8d.startswith("u4 w2970 [nightHatch 0/2, duskHatch 0/3]"), w8d)
q8 = quests_tab("W8_quests_after_nightfall")
ok("8. the week after Nightfall: no badge line", q8.endswith("badge=-"), q8[-60:])
errs = game_errors(console_lines())
ok("9. console without game errors (fresh profile)", not errs, " ;; ".join(errs[:4]))
# ---------------------------------------------------------------------------------------------- 7. a returning player: the toast
prof = dump()
prof["sessions"] = 5
prof.setdefault("quests", {}).pop("weekly", None)
ob = prof.setdefault("onboarding", {})
ob.update({"glided": True, "coinsCollected": True, "eggFound": True, "fedOnce": True, "rode": True, "flew": True, "ring": True})
prof["lastSeen"] = int(time.time())
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world(); watch()
S(LD + "return ld('firstegg off')")  # the manual first egg path (auto - firstegg_check.py)
P("update 1:", lo("update 1")[:60])
for _ in range(14):
    time.sleep(2)
    if "New weekly quests" in seen():
        break
shot("W7_toast")
time.sleep(14); sn7 = seen(); P("banners and toasts:", sn7)
ok("7. returning: the toast 'New weekly quests - see Quests'", "T:New weekly quests - see Quests" in sn7, sn7[-300:])
ok("7. the toast once", sn7.count("New weekly quests") == 1, str(sn7.count("New weekly quests")))
errs = game_errors(console_lines())
ok("9. console without game errors (returning)", not errs, " ;; ".join(errs[:4]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("Weekly quests x2 (21.10, spec 06 Add. 21.10): Aurora, Cinder, Nightfall, reset Sun 19:00, season points, toast")
s.close()
