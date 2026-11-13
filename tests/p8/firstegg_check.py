#!/usr/bin/env python3
"""The first egg without extra steps on P8, LOCAL file (after tools/p8/open_local.sh). Newcomer (seed coins 0):
  1) took an egg from the table - after ~1-2 s it is in the bowl by itself (no 'bring it' step);
  2) the ready one (3 s) hatches by itself: the scene (HatchEggLocal on the client), the dragon in the profile, from pickup to dragon <= 8 s;
  3) second run: egg in the bowl, the owner left the plot - the ready first egg waits, came back - it hatched;
  4) a returning player (sessions 2) with a ready first egg in the bowl: does not hatch on the spawn square, at home - not earlier than afterJoin s;
  5) console without game errors.
Run: python3 tests/p8/firstegg_check.py."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("firstegg_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
def _dump():
    try:
        return dump()
    except Exception:
        return {}
def inc(): return (_dump().get("eggs", {}).get("incubating") or {})
def ndragons():  # LoopDebug state line (the dump of a returning seed after hatching is not always JSON)
    return 1 if " d1=" in ld("state") else 0
ARM = ("local me=game.Players.LocalPlayer local sv=game.ReplicatedStorage:FindFirstChild('EggSeen') or Instance.new('NumberValue') "
       "sv.Name='EggSeen' sv.Value=0 sv.Parent=game.ReplicatedStorage local t0=os.clock() "
       "me:SetAttribute('EggFly', nil) game.ReplicatedStorage.Remotes.Notice.OnClientEvent:Connect(function(p) if type(p)=='table' and p.kind=='eggFly' then me:SetAttribute('EggFly', true) end end) "
       "task.spawn(function() while os.clock()-t0<30 do if workspace:FindFirstChild('HatchEggLocal') then sv.Value=os.clock()-t0 return end task.wait() end end) return 'armed'")
def seed():
    P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value='{\"coins\":0}' return #s.Value", "Edit"))

# 1-2. nearby (the previous run may have crashed mid-Play - stop it first)
stop()
seed(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
ld("go inc"); time.sleep(1)
C(ARM)
t0 = time.time()
P("table 1:", ld("table 1")[:60])
placed = None
for _ in range(40):
    if "1" in inc():
        placed = time.time() - t0; break
    time.sleep(0.2)
ok("1. the egg is in bowl 1 by itself 1-3.5 s after pickup", placed is not None and 0.5 <= placed <= 3.5, f"{placed and round(placed, 1)} s")
ok("1b. the client got the egg arc into the bowl (eggFly)", C("return tostring(game.Players.LocalPlayer:GetAttribute('EggFly'))") == "true")
born = None
for _ in range(60):
    if ndragons() >= 1:
        born = time.time() - t0; break
    time.sleep(0.25)
seen = C("local v=game.ReplicatedStorage:FindFirstChild('EggSeen') return v and tostring(v.Value) or '-'")
ok("2a. the first egg hatched by itself (dragon in the profile)", born is not None, f"{born and round(born, 1)} s")
ok("2b. from pickup to dragon <= 8 s", born is not None and born <= 8, f"{born and round(born, 1)} s")
ok("2c. hatch scene on the client", seen not in ("-", "0"), seen)
time.sleep(6); desk("after_auto_hatch")
stop()

# 3. far away: the ready first egg waits for the owner
seed(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
ld("go inc"); time.sleep(1)
P("table 1:", ld("table 1")[:60])
for _ in range(40):
    if "1" in inc(): break
    time.sleep(0.2)
S("local p=game.Players:GetPlayers()[1] local r=p.Character.HumanoidRootPart p.Character:PivotTo(CFrame.new(r.Position+Vector3.new(0,0,150))) return 'far'")
time.sleep(7)
far = inc()
ok("3a. left the plot: egg in the bowl, not hatched", "1" in far and ndragons() == 0, json.dumps(far)[:120])
ld("go inc")
born2 = None
for _ in range(20):
    if ndragons() >= 1:
        born2 = True; break
    time.sleep(0.5)
ok("3b. came back to the nest - hatched by itself", born2 is True)
time.sleep(5)
stop()

# 4. a returning player with a ready first egg: spawn square - no, at home - not earlier than afterJoin
P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') or Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage "
               "s.Value='{\"coins\":0,\"sessions\":1,\"eggs\":{\"incubating\":{\"1\":{\"egg\":{\"element\":\"ember\",\"rarity\":\"Common\",\"zone\":\"Meadow\",\"id\":\"seed\",\"shiny\":false,\"cold\":false,\"foundAt\":0},\"endsAt\":0}}}}' return #s.Value", "Edit"))
s.call("start_stop_play", {"studio_id": sid, "is_start": True}); tj = time.time()
for _ in range(60):
    if ndragons() >= 1 or "1" in inc(): break
    time.sleep(0.5)
time.sleep(1)
ok("4a. on the spawn square the ready egg waits", ndragons() == 0 and "1" in inc(), f"t={time.time()-tj:.1f}")
ld("go inc")
tb = None
for _ in range(40):
    if ndragons() >= 1:
        tb = time.time() - tj; break
    time.sleep(0.5)
ok("4b. at home it hatched by itself, not earlier than 10 s after join", tb is not None and tb >= 10, f"{tb and round(tb, 1)} s from Play")
time.sleep(4)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Incubation]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("5. console without game errors", not bad, str(len(bad)))
for l in bad[-8:]: P("  ", l[:220])
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
write_result("First egg without extra steps")
