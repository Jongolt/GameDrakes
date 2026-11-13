#!/usr/bin/env python3
"""An egg from the shelf goes into a free incubator by itself. P8, LOCAL file (after tools/p8/open_local.sh).
A profile via StudioSeed: 3 incubators empty, 3 eggs on the shelf, the tutorial done:
  1) outside the nest (plaza) - the eggs wait on the shelf;
  2) in the nest with an egg in the hands - they wait (a bowl for the found egg);
  3) put the egg from the hands into bowl 1 - the shelf eggs go into bowls 2 and 3 by themselves, one stays (no bowls);
  4) bowl 2 freed (a hatch) - after 8 s the egg is still on the shelf, after 25 s - in bowl 2;
  5) console without game errors.
Run: python3 tests/p8/shelf_auto_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/shelf_auto_check/ (frames S*.jpg, result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("shelf_auto_check")
from p8lib import *  # noqa: F401,F403


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def eggs():
    d = dump()
    e = d.get("eggs") or {}
    inc = e.get("incubating") or {}
    if isinstance(inc, list):
        inc = {str(i + 1): v for i, v in enumerate(inc) if v}
    return len(e.get("shelf") or []), sorted(inc.keys()), e.get("carry") is not None
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


edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
stop(); start(); wait_world()
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(4)
prof = dump()
prof["sessions"] = 5
prof["lastSeen"] = int(time.time())
prof["incubators"] = 3
ob = prof.setdefault("onboarding", {})
ob.update({"glided": True, "coinsCollected": True, "eggFound": True, "fedOnce": True, "rode": True, "flew": True, "ring": True})
e = prof.setdefault("eggs", {})
e["carry"] = None
e["incubating"] = {}
e["shelf"] = [{"id": f"probe{i}", "element": el, "rarity": "Common", "shiny": False, "size": "normal", "zone": "Meadow", "rareNest": False}
              for i, el in enumerate(("moss", "ember", "tide"), 1)]
js = json.dumps(prof, ensure_ascii=False).replace('"carry": null, ', "")
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world()
P("player position after join (the spawn slab on the plaza):", S("local p=game.Players:GetPlayers()[1] local r=p and p.Character and p.Character:FindFirstChild('HumanoidRootPart') return r and string.format('%.0f,%.0f,%.0f', r.Position.X, r.Position.Y, r.Position.Z) or '-'"))
time.sleep(25)
e1 = eggs(); P("plaza, 25 s:", e1)
ok("1. outside the nest the eggs wait on the shelf", e1[0] == 3 and e1[1] == [], str(e1))
P("egg into the hands:", lo("egg storm Cliffs")[:60])
ld("go pile"); time.sleep(25)
e2 = eggs(); P("nest, egg in the hands, 25 s:", e2)
ok("2. in the nest with an egg in the hands the shelf waits", e2[0] == 3 and e2[1] == [] and e2[2], str(e2))
P("place 1:", ld("place 1")[:60]); ld("go pile"); time.sleep(5)
e3 = eggs(); P("after place 1:", e3)
shot("S1_rings_filled")
ok("3. the shelf eggs go into bowls 2 and 3 by themselves, one on the shelf", e3[0] == 1 and e3[1] == ["1", "2", "3"] and not e3[2], str(e3))
for _ in range(2):
    ld("time 9999999"); time.sleep(1.5)
P("hatch 2:", ld("hatch 2")[:60])
ld("go pile"); time.sleep(8)
e4 = eggs(); P("8 s after the hatch in bowl 2:", e4)
ok("4. the freed bowl: after 8 s the egg is still on the shelf", e4[0] == 1 and "2" not in e4[1], str(e4))
time.sleep(18)
e5 = eggs(); P("after 26 s:", e5)
ok("4. after 26 s the shelf egg is in bowl 2", e5[0] == 0 and "2" in e5[1], str(e5))
shot("S2_ring2_refilled")
errs = game_errors(console_lines())
ok("5. console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("An egg from the shelf into a free incubator by itself (21.10, spec 06 Add. 21.10 (4))")
s.close()
