#!/usr/bin/env python3
"""The arrow above BREATH on P8, LOCAL file.
  1) newcomer: the first egg hatches by itself -> stage 1 ambush after ~10 s; the BREATH button is visible, without a shot after ui.pointAfter 2 s - FightArrow above it (frame);
  2) a shot (the button) - the arrow is removed; 3) the Gloom is cleared - no arrow; 4) console without game errors.
Run: python3 tests/p8/fight_arrow_check.py."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("fight_arrow_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ARROW = ("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('Combat') local b=g and g:FindFirstChild('Breath',true) "
         "if not b then return 'nobtn' end local a=b:FindFirstChild('FightArrow') local h=b:FindFirstChild('HintArrow2D') "
         "return 'vis='..tostring(b.Visible)..' arrow='..tostring(a~=nil)..' hint='..tostring(h~=nil)")
stop()
P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value='{\"coins\":0}' return #s.Value", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
ld("go inc"); time.sleep(1); P("table 1:", ld("table 1")[:50])
seen_btn = None
for _ in range(60):
    st = C(ARROW)
    if "vis=true" in st:
        seen_btn = time.time(); break
    time.sleep(0.5)
ok("1a. the ambush came, the BREATH button is visible", seen_btn is not None, C(ARROW))
time.sleep(0.8)
early = C(ARROW)
ok("1b. no arrow right away (waits for pointAfter)", "arrow=false" in early or "hint=true" in early, early)
time.sleep(2.2)
st = C(ARROW)
ok("1c. after 2 s without a shot - the arrow above BREATH (one)", ("arrow=true" in st) != ("hint=true" in st), st)
desk("arrow_on")
press("Combat", "Breath"); time.sleep(0.3)
st2 = C(ARROW)
ok("2. a shot - the FightArrow arrow is removed", "arrow=false" in st2, st2)
P("clear:", ld("combat clear")[:40]); time.sleep(1.5)
st3 = C(ARROW)
ok("3. the Gloom is cleared - no arrow", "arrow=false" in st3, st3)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Combat]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("4. console without game errors", not bad, str(len(bad)))
for l in bad[-6:]: P("  ", l[:200])
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
write_result("Arrow above BREATH")
