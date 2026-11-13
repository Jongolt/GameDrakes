#!/usr/bin/env python3
"""(A5) how many 'PBR textures' lines in the Studio Output on join; (B3) the second dragon grew up IN THE NEST - the banner
'Your dragon grew up! / Take it out and ride' (not 'Ride it!'), and when there is no companion (the firstborn was let go with Release) - the TAKE step plate
'Open Dragons - make it your companion' with an arrow at the dragon in the nest; (C) after the first ride in session 1 the shop (Nest) has the
Starter Pack card; (B2) after the ride, while the firstborn grows to an adult, the NEXT line shows '... grows up in ... - then you can fly' right away;
(B4) the NEXT line sometimes has 'Storm Dragon in ...'; (D) frames of the four day phases at the nest (ForcePhase). Run: python3 tests/p8/nest_grow_check.py
(after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("nest_grow_check")
from p8lib import *  # noqa: F401,F403


def ld(c): return S(LD + f"return ld('{c}')")
def cd(c): return C(CD + f"return cd('{c}')")
def nextup():
    r = cd("nextup")
    m = re.search(r"(visible=\w+ kind=\S+ text=.*? rsvp=\S+)", r)
    return m.group(1) if m else r
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def dragons():
    d = dump()
    return d.get("dragons") or {}, d.get("companion"), d
def remote(name, *args):
    a = ",".join(args)
    return C(f"local r=game.ReplicatedStorage.Remotes.{name}:InvokeServer({a}) return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
# collect the banner texts for N s (client): all visible TextLabels inside the Banner frame
WATCH = ("local me=game.Players.LocalPlayer local sv=game.ReplicatedStorage:FindFirstChild('BW') or Instance.new('StringValue') sv.Name='BW' sv.Value='' sv.Parent=game.ReplicatedStorage "
         "task.spawn(function() local t0=os.clock() local seen={} local order={} while os.clock()-t0<{secs} do for _,o in me.PlayerGui:GetDescendants() do "
         "if o:IsA('TextLabel') and o.Visible and o.Text~='' and o:FindFirstAncestor('Banner') then local k=o.Text if not seen[k] then seen[k]=true order[#order+1]=k end end end task.wait(0.2) end "
         "sv.Value=table.concat(order,' || ') end) return 'watch'")
def watch(secs): C(WATCH.replace("{secs}", str(secs)))
def watched(): return C("local v=game.ReplicatedStorage:FindFirstChild('BW') return v and v.Value or 'none'")
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")

stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
# ---------------------------------------------------------------------------------------------- A5: PBR in Output
pbr = [l for l in console_lines() if "PBR" in l]
P(f"A5: 'PBR textures' lines in Output after join: {len(pbr)}", pbr[:2])
# ---------------------------------------------------------------------------------------------- firstborn + second dragon in the nest
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(6)
ds, comp, _ = dragons()
first = comp
ok("the firstborn hatched and became the companion", first is not None and first in ds and C("return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))") == "0", f"comp={comp} n={len(ds)}")
# ---------------------------------------------------------------------------------------------- firstborn teen, ride, Starter, NEXT
watch(12)
P("time 56:", ld("time 56")[:60]); time.sleep(13.5)
bw1 = watched(); P("firstborn growth banners:", bw1)
ok("B3: for the companion on the shoulder after growing - 'Ride it!'", "Ride it!" in bw1, bw1)
mt = remote("Mount", f"'{first}'"); P("Mount the firstborn:", mt); time.sleep(3)
ok("riding the firstborn (teen)", mt.startswith("true"), mt)
dm = remote("Dismount"); P("Dismount:", dm); time.sleep(2)
d = dump(); ob = d.get("onboarding") or {}
ok("onboarding.rode after the ride", ob.get("rode") is True, json.dumps(ob)[:160])
press("HUD", "Menu_Shop"); time.sleep(1); press("Book", "Nest"); time.sleep(1.5)
starter = C(FIND + "local g=pg:FindFirstChild('Book') local c=g and g:FindFirstChild('Card_StarterPack_49',true) return tostring(c~=nil and shown(c))")
ok("C: in session 1 after the first ride the shop (Nest) has the Starter Pack card", starter == "true", f"sessions={d.get('sessions')} card={starter}")
shot("N3_shop_starter")
for _ in range(2):
    if gui_on("Book"): press("Book", "Close")
P("go pile:", ld("go pile")[:60]); time.sleep(3)
P("feed all:", ld("feed all")[:80]); time.sleep(1)
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,-30)) return 'ok'"); time.sleep(6)  # further from the table eggs: the EGG step does not interfere
nu = nextup(); P("NEXT after the ride:", nu, "| state:", cd("state")[:160])
ok("B2: the NEXT line about the firstborn 'then you can fly' (visible when there is no step; otherwise it waits under the step banner)", "then you can fly" in nu, nu)
shot("N4_nextup")
seen_storm = False
for _ in range(5):
    time.sleep(2); t = nextup()
    if "Storm Dragon" in t: seen_storm = True
P("B4: Storm Dragon in the NEXT line within 10 s (with urgent growth the line stays on the firstborn - expected no):", seen_storm, "| DragonAt:", S("local w=game.ReplicatedStorage:FindFirstChild('WeatherState') return tostring(w and w:GetAttribute('DragonAt'))"))
# ---------------------------------------------------------------------------------------------- the second dragon grows IN THE NEST
P("give egg Common:", ld("give egg Meadow Common")[:60]); time.sleep(1)
P("place 1:", ld("place 1")[:60]); time.sleep(2)
P("time 400:", ld("time 400")[:60]); time.sleep(4)
P("hatch 1:", ld("hatch 1")[:80]); time.sleep(8)
ds, comp, _ = dragons()
second = next((u for u in ds if u != first), None)
ok("the second dragon in the nest, the companion unchanged", second is not None and comp == first, f"comp={comp} dragons={list(ds)}")
watch(12)
P("time 300:", ld("time 300")[:60]); time.sleep(13.5)
bw = watched(); P("growth banners of the second:", bw)
ds, comp, _ = dragons()
st = {u: (d.get("stage"), d.get("growAs")) for u, d in ds.items()}
P("stages:", st)
ok("B3: the second dragon grew into a teen in the nest", second is not None and st.get(second, (0,))[0] == 1, json.dumps(st))
ok("B3: the one grown in the nest has the second line 'Take it out and ride'", "Take it out and ride" in bw, bw)
shot("N1_after_grow")
P("TAKE (target companion) is unreachable by debug on P8: Release of the companion is forbidden (reason companion); the target logic - tests/run.luau")
# ---------------------------------------------------------------------------------------------- D: phase frames
for ph in ("dawn", "day", "dusk", "night"):
    S(f"game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','{ph}') task.wait(0.3) return '{ph}'"); time.sleep(2.5)
    shot(f"D_{ph}")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
lines = console_lines()
errs = [l for l in lines if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l and "PBR" not in l]
ok("console without game errors (except PBR)", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Dragon grew up in the nest, Starter after the ride, firstborn NEXT, day phases")
s.close()
