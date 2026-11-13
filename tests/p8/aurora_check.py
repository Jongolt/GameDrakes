#!/usr/bin/env python3
"""The acceptance of update 1 Aurora in the LOCAL file on P8 (the window 834x630 = a phone 812x375, a newcomer).
Before the date: 15 errands, no scrolls visible. LiveOpsDebug update 1: UpdatesLive=1, KEEPER 16/20, only the scroll of the current
errand is visible, the 📜 icon; scrolls 1-5 in turn (a frame of each, reading, the rewards, the note, the finale - a Cliffs egg, a foreign one cannot be read);
Aurora (the curtains on the client, the bar, frames by day and night); Glacier (Frost from Summit hatched in Aurora); the code AURORA (ok, already,
a foreign one); Settings with the Code field (a full check 812x375); the daily pool B (the day after Aurora); the console.
Run: python3 tests/p8/aurora_check.py (after tools/p8/open_local.sh). The output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("aurora_check")
from p8lib import *  # noqa: F401,F403

def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def wd(cmd): return S(f"return game.ServerStorage.WeatherDebug:Invoke('{cmd}')")
QP = ("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Quests') local c=q and q:FindFirstChild('Cat',true) local t=q and q:FindFirstChild('Title',true) "
      "return tostring(c and c.ContentText)..' | '..tostring(t and t.ContentText)")
VIS = ("local f=workspace.World:FindFirstChild('Scrolls') local t={} if not f then return '' end for _,m in f:GetChildren() do local p=m.PrimaryPart if p and p.Transparency<1 then "
       "local pr=p:FindFirstChildWhichIsA('ProximityPrompt') table.insert(t,m.Name..(pr and pr.Enabled and '+' or '-')) end end table.sort(t) return table.concat(t,',')")
def look(frm, at, secs=6):
    C("local cam=workspace.CurrentCamera game:GetService('RunService'):BindToRenderStep('shot',2001,function() cam.CFrame=CFrame.lookAt(Vector3.new(%s),Vector3.new(%s)) end) "
      "task.delay(%d,function() game:GetService('RunService'):UnbindFromRenderStep('shot') end) return 'ok'" % (frm, at, secs))

stop(); start()
S(LD + "return ld('firstegg off')")  # the manual first egg path (the automatic one - firstegg_check.py)
time.sleep(3)
st0 = lo("state")
P("start:", st0)
ok("before the date: live=0", st0.startswith("live=0"), st0)
ok("before the date: no scrolls in the world (review)", st0.count("@") == 0 and S("return tostring(workspace.World:FindFirstChild('Scrolls') ~= nil)") == "false", st0)
ok("before the date: the client has UpdatesLive 0", C("return tostring(game.ReplicatedStorage:GetAttribute('UpdatesLive'))") == "0")
lo("step 16"); time.sleep(1.5)
q0 = C(QP); P("the plate before the date:", q0)
ok("before the date: at the 16th - ALL TALES TOLD / More tales next week", "ALL TALES TOLD" in q0 and "More tales" in q0, q0)
v0 = C(VIS)
ok("before the date: no scrolls visible", v0 == "", v0)

# ------------------------------------------------------------------------------------------------ update 1
st1 = lo("update 1")
for i in range(40):  # the scrolls are placed with update 1 (after the decor)
    if st1.count("@") == 5: break
    time.sleep(1.5); st1 = lo("state")
P("update 1:", st1); time.sleep(1.5)
ok("with update 1 the scrolls are built (5)", st1.count("@") == 5, st1)
ok("update 1: live=1, the clock at 08.11", st1.startswith("live=1") and "2026-11-08" in st1, st1)
q1 = C(QP); P("the plate:", q1)
ok("after: KEEPER 16/20 Lost notes", "16/20" in q1 and "Lost notes" in q1, q1)
v1 = C(VIS); P("the visible scrolls:", v1)
ok("after: only scroll 1 is visible, the Read button is enabled", v1 == "Scroll1+", v1)
tg = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('ScrollTag') return tostring(g and g.Enabled)..' '..tostring(g and g.T.ContentText)")
ok("the 📜 icon with the distance", tg.startswith("true 📜"), tg)
shot("quests_16")
C(CD + "cd('menu quests') task.wait(1.5) return 'ok'")
r = sweep("quests_tab_20")
ok("the Quests tab: 20 rows without overflow", "ISSUES[0]" in r, r[:300])
qrows = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local n=0 if b then for _,o in b:GetDescendants() do if o:IsA('Frame') and o.Name:match('^Q%d+$') then n+=1 end end end return tostring(n)")
ok("the Quests tab: 20 errand rows", qrows == "20", qrows)
C(CD + "cd('back') task.wait(0.4) cd('back') return 'ok'"); time.sleep(0.8)

COMP = "local p=game.Players:GetPlayers()[1] p:SetAttribute('CompanionStage', 2) return 'ok'"  # the Springs guard lets through with a teen companion
for n in range(1, 6):
    S(COMP)
    lo(f"go {n}"); time.sleep(2.5)
    pos = re.search(rf"{n}@(-?\d+),(-?\d+),(-?\d+)", st1)
    if pos:
        x, y, z = map(int, pos.groups())
        look(f"{x + 9},{y + 6},{z + 9}", f"{x},{y + 2},{z}")
        time.sleep(1.2)
    shot(f"scroll_{n}")
    d0 = dump(); c0 = d0["coins"]; sh0 = len(d0["eggs"]["shelf"])
    if n < 5:
        bad = lo(f"read {n + 1}"); time.sleep(0.8)
        ok(f"scroll {n + 1} cannot be read ahead of time", dump()["quests"]["keeper"]["step"] == 15 + n)
    S(COMP); lo(f"go {n}"); time.sleep(0.5)
    lo(f"read {n}"); time.sleep(2.2)
    d1 = dump(); step = d1["quests"]["keeper"]["step"]
    P(f"scroll {n}: step {step}, coins {c0}->{d1['coins']}, shelf {sh0}->{len(d1['eggs']['shelf'])}")
    ok(f"scroll {n}: errand {15 + n} closed -> step {16 + n}", step == 16 + n, str(step))
    ok(f"scroll {n}: the coins arrived", d1["coins"] > c0, f"{c0}->{d1['coins']}")
    if n == 5:
        egg = d1["eggs"]["shelf"][-1] if d1["eggs"]["shelf"] else {}
        ok("scroll 5: the finale - a Cliffs egg on the shelf", len(d1["eggs"]["shelf"]) == sh0 + 1 and egg.get("zone") == "Cliffs", json.dumps(egg)[:120])
    if n == 1:
        shot("note_1")
        time.sleep(3.5)
        nt = C("local t='' for _,o in game.Players.LocalPlayer.PlayerGui:GetDescendants() do if o:IsA('TextLabel') and o.Visible and o.ContentText:find('Note 1:',1,true) then t=o.ContentText end end return t")
        ok("note 1 is visible after the Done! banner", nt.startswith("Note 1:"), nt)
        shot("note_1_text")
    ok(f"scroll {n}: a repeat gives nothing", (lo(f"read {n}") and dump()["quests"]["keeper"]["step"]) == 16 + n)
q2 = C(QP); P("the plate after 20:", q2)
ok("after the 20th: ALL TALES TOLD, no scrolls visible", "ALL TALES TOLD" in q2 and C(VIS) == "", q2)

# ------------------------------------------------------------------------------------------------ Aurora
wa = wd("aurora"); P("aurora:", wa); time.sleep(5)
ok("Aurora: the weather on the server", "kind=aurora" in wa, wa)
ac = C("local f=workspace.CurrentCamera:FindFirstChild('LocalAurora') local n,vis=0,0 if f then for _,p in f:GetChildren() do n+=1 for _,fr in p:GetDescendants() do if fr:IsA('Frame') and fr.BackgroundTransparency<0.9 then vis+=1 end end end end "
       "local b=game.Players.LocalPlayer.PlayerGui.Topbar:FindFirstChild('Top_Weather',true) local c=game.Lighting:FindFirstChild('WeatherCC') "
       "return string.format('panels=%d rays=%d bar=%s %s cc=%.2f', n, vis, tostring(b.Visible), b.T.ContentText, c and c.Brightness or 9)")
P("Aurora on the client:", ac)
ok("Aurora on the client: 9 curtains, the rays visible, the bar with a timer", "panels=9" in ac and int(re.search(r"rays=(\d+)", ac).group(1)) >= 30 and ("bar=true Aurora" in ac or "bar=true Storm shards" in ac), ac)  # at :00/:30 the bar is taken by the Storm dragon
S(LD + "return ld('go pile')"); time.sleep(1.5)
look("0,45,40", "0,170,-520", 8); time.sleep(1.5)
shot("aurora_day")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','night') task.wait(3) return 'night'")
look("0,45,40", "0,170,-520", 8); time.sleep(2)
shot("aurora_night")
look("-120,60,-120", "60,160,-520", 6); time.sleep(1.5)
shot("aurora_night_side")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")

# ------------------------------------------------------------------------------------------------ Glacier
# the scroll 5 egg goes from the shelf into a free bowl by itself while the player is at home with empty hands (the Aurora
# frames at the nest) - the Frost egg has no bowl, hatch 1 hatched the scroll egg. First hatch what is in the bowl
S(LD + "return ld('go inc')"); time.sleep(2)
for i in range(2):
    S(LD + "return ld('time 9999999')"); time.sleep(1.5)
P("bowl 1 before Glacier:", S(LD + "return ld('hatch 1')")[:80]); time.sleep(3)
eg = lo("egg frost Summit"); P("the egg:", eg)
S(LD + "return ld('go inc')"); time.sleep(3)
for i in range(2):
    S(LD + "return ld('time 9999999')"); time.sleep(1.5)
nb0 = set(dump()["dragons"].keys())
wd("aurora")  # another 3 minutes in case the first one has already ended
S(LD + "return ld('hatch 1')"); time.sleep(2.5)
d3 = dump(); newd = [v for k, v in d3["dragons"].items() if k not in nb0]
P("hatched:", json.dumps(newd)[:300])
ok("Glacier: Frost from Summit in Aurora - variant glacier", len(newd) == 1 and newd[0].get("variant") == "glacier" and newd[0].get("element") == "frost", json.dumps(newd)[:200])
time.sleep(2); shot("glacier_hatch")

# ------------------------------------------------------------------------------------------------ the code of the week
k1 = lo("code aurora"); P("the code:", k1)
ok("the code AURORA: ok + coins", k1.startswith("code true/nil/") and int(k1.rsplit("/", 1)[1]) >= 100, k1)
time.sleep(1.2)
k2 = C("local r=game.ReplicatedStorage.Remotes.Code:InvokeServer(' Aurora ') return tostring(r.ok)..'/'..tostring(r.reason)")
ok("the code: the second time from the client - already", k2 == "false/already", k2)
time.sleep(1.2)
k3 = C("local r=game.ReplicatedStorage.Remotes.Code:InvokeServer('FREE') return tostring(r.ok)..'/'..tostring(r.reason)")
ok("the code: a foreign one - bad_code", k3 == "false/bad_code", k3)
time.sleep(1.2)
k4 = C("local r=game.ReplicatedStorage.Remotes.Code:InvokeServer(string.rep('A',30)) return tostring(r.ok)..'/'..tostring(r.reason)")
ok("the code: too long - bad_request", k4 == "false/bad_request", k4)
C(CD + "cd('menu settings') task.wait(1.5) return 'ok'")
r = sweep("settings_code")
ok("Settings: the Code row without overflow and overlaps (812x375)", "ISSUES[0]" in r, r[:300])
cb = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local box=b and b:FindFirstChild('CodeBox',true) local rd=b and b:FindFirstChild('Redeem',true) "
       "return tostring(box and box.AbsoluteSize.Y)..' '..tostring(rd and rd.AbsoluteSize.Y)..' '..tostring(rd and rd.ContentText)")
ok("Settings: the field and the Redeem button not lower than 38 px", re.match(r"(\d+)\S* (\d+)\S* Redeem", cb) is not None and min(float(x) for x in cb.split()[:2]) >= 38, cb)
C(CD + "cd('back') task.wait(0.4) cd('back') return 'ok'"); time.sleep(0.6)

# ------------------------------------------------------------------------------------------------ the daily pool B
lo("offset %d" % (1794164400 - int(time.time()) + 86400))  # the day after Aurora: 09.11 19:00
time.sleep(1)
S(LD + "return ld('reward daily ping 1')"); time.sleep(1.5)
pb = S("local R=require(game.ReplicatedStorage.Shared.Core.Rewards) local Cfg=require(game.ReplicatedStorage.Shared.Config) "
       "local t=1794164400+86400 local ids=R.dailyPicks(R.dayIndex(t), Cfg.Rewards) local B=0 for _,tier in R.TIERS do for _,x in R.pool(Cfg.Rewards,tier,R.dayIndex(t)) do if x.from then B+=1 end end end "
       "return table.concat(ids,',')..' poolB='..B")
d4 = dump(); P("pool B:", pb, "the profile:", d4["quests"]["daily"].get("date"), d4["quests"]["daily"].get("ids"))
ok("pool B: 7 B tasks in the pool from 09.11", pb.endswith("poolB=7"), pb)
ok("pool B: the profile at 09.11 with the tasks of this day", d4["quests"]["daily"].get("date") == "2026-11-09" and ",".join(d4["quests"]["daily"].get("ids") or []) == pb.split(" ")[0], json.dumps(d4["quests"]["daily"])[:200])

# ------------------------------------------------------------------------------------------------ the console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[LiveOps\]|\[Weather\]|\[Quest|\[Net\]|failed|Error", l) and "not authorized" not in l and "TexturePack" not in l]
ok("the console without errors", not errs, " ;; ".join(errs[:6]))
stop()
P("RESULT:", f"{sum(1 for r in res if r[1])}/{len(res)} OK")
for r in res:
    if not r[1]:
        P("  FAIL", r[0], "|", r[2][:300])
write_result()
s.close()
