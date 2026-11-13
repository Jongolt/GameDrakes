#!/usr/bin/env python3
"""The splash: no frame-drawn picture,
the baby - only 3D from ReplicatedFirst.LoadingDragon. In a LOCAL file on P8, polling the client from the first fractions of a second until the splash leaves:
A - the model in the file: nothing on the strip except the Dragon3D window, the 3D baby appears, Splash3D = seconds; B - the model removed in edit
mode: the strip is empty (neither a drawing nor 3D), Splash3D = none, a warning in the console, no errors. The model is put back.
Run: python3 tests/p8/splash_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("splash_check")
from p8lib import *  # noqa: F401,F403

STATE = ("local g = game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') if not g then return 'noscreen' end "
         "local r = g:FindFirstChild('Runner', true) local other = 0 "
         "if r then for _, d in r:GetDescendants() do if d:IsA('GuiObject') and d.Name ~= 'Dragon3D' and not d:FindFirstAncestor('Dragon3D') and d.Visible then other += 1 end end end "
         "local v = g:FindFirstChild('Dragon3D', true) "
         "return (v and '3d' or 'no3d') .. ' other=' .. other .. ' sp=' .. tostring(game:GetService('ReplicatedFirst'):GetAttribute('Splash3D')) "
         ".. ' found=' .. tostring(g:GetAttribute('SplashFound'))")


def run_once(tag):
    s.call("start_stop_play", {"studio_id": sid, "is_start": True})
    seen, t0, shots = [], time.time(), 0
    while time.time() - t0 < 40:
        st = C(STATE)
        if not seen or st != seen[-1][1]:
            seen.append((round(time.time() - t0, 1), st)); P(f"  {tag} {time.time() - t0:.1f} s: {st}")
        if st != "noscreen" and shots < 3:
            shot(f"{tag}_{shots}"); shots += 1
        if st == "noscreen" and len(seen) > 1:
            break
        time.sleep(0.3)
    sp = C("return tostring(game:GetService('ReplicatedFirst'):GetAttribute('Splash3D'))")
    P(f"  {tag} result Splash3D:", sp)
    return seen, sp


def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
    return ctext.splitlines()


stop()
A, spA = run_once("A")
trace = " / ".join(f"{t}:{st}" for t, st in A)
ok("A: nothing on the strip except the 3D window in any poll (no drawing)", all("other=0" in st for _, st in A if st != "noscreen"), trace)
ok("A: the 3D baby appeared", any(st.startswith("3d") for _, st in A), trace)
ok("A: Splash3D = seconds until shown", re.fullmatch(r"\d+\.\d", spA or "") is not None, spA)
errsA = [l for l in console_lines() if re.search(r"Stack Begin|attempt to|\[LoadingScreen\]", l)]
ok("A: console without splash errors and warnings", not errsA, " ;; ".join(errsA[:5]))
stop()
P("edit: the model from ReplicatedFirst to ServerStorage:", run("local m = game:GetService('ReplicatedFirst'):FindFirstChild('LoadingDragon') "
  "if m then m.Parent = game:GetService('ServerStorage') return 'moved' end return 'none'", "Edit"))
B, spB = run_once("B")
trace = " / ".join(f"{t}:{st}" for t, st in B)
ok("B (without the model): the strip is empty - neither a drawing nor 3D", all("other=0" in st and st.startswith("no3d") for _, st in B if st != "noscreen"), trace)
ok("B: Splash3D = none", spB == "none", spB)
linesB = console_lines()
ok("B: the warning 'no LoadingDragon', no errors", any("no ReplicatedFirst.LoadingDragon" in l for l in linesB)
   and not any(re.search(r"Stack Begin|attempt to", l) for l in linesB), " ;; ".join(l for l in linesB if "LoadingScreen" in l)[:300])
stop()
P("edit back:", run("local m = game:GetService('ServerStorage'):FindFirstChild('LoadingDragon') "
  "if m then m.Parent = game:GetService('ReplicatedFirst') return 'back' end return 'none'", "Edit"))
write_result("Splash: only the 3D baby, no drawing under any breakage")
s.close()
