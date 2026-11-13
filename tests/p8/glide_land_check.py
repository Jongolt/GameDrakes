#!/usr/bin/env python3
"""A newcomer with a baby
on the shoulder steps off the nest ledge, glides and RUNS on without releasing movement (like a live player). Before, the run window started at the moment
of touching the ground and the 2 s average (40 studs/s glider -> 16 running) exceeded groundAvgMax 22 - the server sent the player 2 s back. Now
AC.landGrace 2.5 s after landing the window does not start, groundAvgMax 30. Check: (1) over the whole trace not a single jump back (> 12
studs in 0.1 s), (2) no '[AntiCheat] ... walk' in the console, (3) ran >= 20 studs after landing, (4) the glider happened (Gliding >= 1 s).
Run: python3 tests/p8/glide_land_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glide_land_check")
from p8lib import *  # noqa: F401,F403


def ld(c): return S(LD + f"return ld('{c}')")
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()

NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")
# trace on the client: position every 0.1 s + the Gliding flag, {secs} seconds; moving forward all the time (like a finger on the joystick)
TRACE = ("local me=game.Players.LocalPlayer local sv=game.ReplicatedStorage:FindFirstChild('GL') or Instance.new('StringValue') sv.Name='GL' sv.Value='' sv.Parent=game.ReplicatedStorage "
         "local h=me.Character:FindFirstChildOfClass('Humanoid') local f=Vector3.new({fwd}).Unit "
         "task.spawn(function() local t0=os.clock() local r=me.Character.HumanoidRootPart local out={} local conn conn=game:GetService('RunService').RenderStepped:Connect(function() "
         "if os.clock()-t0<{secs} then h:Move(f,false) else h:Move(Vector3.zero,false) conn:Disconnect() end end) "
         "while os.clock()-t0<{secs} do local p=r.Position out[#out+1]=string.format('%.1f,%.1f,%.1f,%s', p.X,p.Y,p.Z, me:GetAttribute('Gliding') and 'g' or (h.FloorMaterial==Enum.Material.Air and 'a' or 'l')) task.wait(0.1) end "
         "sv.Value=table.concat(out,';') end) return 'trace'")

stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(6)
cs = C("return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))")
ok("baby on the shoulder (CompanionStage 0)", cs == "0", cs)
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ok'"); time.sleep(1.5)
fwd = S(NEST + "local z=n:GetPivot():VectorToWorldSpace(Vector3.new(0,0,1)) return string.format('%.3f,0,%.3f', z.X, z.Z)")
C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local f=Vector3.new({fwd}).Unit c.CFrame=CFrame.lookAt(r.Position-f*12+Vector3.new(0,5,0), r.Position+f*30) return 'cam'")
time.sleep(0.5)
n0 = len([l for l in console_lines() if "[AntiCheat]" in l])
C(TRACE.replace("{fwd}", fwd).replace("{secs}", "18"))
time.sleep(19.5)
raw = C("local v=game.ReplicatedStorage:FindFirstChild('GL') return v and v.Value or 'none'")
pts = []
for tok in raw.split(";"):
    m = re.match(r"(-?[\d.]+),(-?[\d.]+),(-?[\d.]+),(\w)", tok)
    if m:
        pts.append((float(m.group(1)), float(m.group(2)), float(m.group(3)), m.group(4)))
P("trace points:", len(pts))
glide_s = sum(1 for p in pts if p[3] == "g") * 0.1
# landing = the first 'l' point after the glider
land_i = None
seen_g = False
for i, p in enumerate(pts):
    if p[3] == "g":
        seen_g = True
    elif seen_g and p[3] == "l":
        land_i = i
        break
jumps = []
for i in range(1, len(pts)):
    a, b = pts[i - 1], pts[i]
    d = ((a[0] - b[0]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5
    if d > 12:
        jumps.append((round(i * 0.1, 1), round(d, 1)))
run_d = 0.0
if land_i is not None and land_i + 1 < len(pts):
    a, b = pts[land_i], pts[-1]
    run_d = ((a[0] - b[0]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5
P(f"glider {glide_s:.1f} s, landing at {land_i and land_i * 0.1} s, run after landing {run_d:.0f} studs, jumps back/teleports: {jumps}")
shot("L1_after_landing_run")
lines = console_lines()
ac = [l for l in lines if "[AntiCheat]" in l][n0:]
walk = [l for l in ac if "walk" in l]
P("anticheat during the probe:", ac[:5])
ok("1. the glider happened (Gliding >= 1 s)", glide_s >= 1, f"{glide_s:.1f} s")
ok("2. landing and running on without a rollback: no jumps > 12 studs in 0.1 s", land_i is not None and not jumps, f"land={land_i} jumps={jumps}")
ok("3. no '[AntiCheat] walk' in the console (before - a rollback at the moment of landing)", not walk, " ;; ".join(walk[:3]))
ok("4. after landing ran >= 20 studs over the rest of the trace", run_d >= 20, f"{run_d:.0f}")
errs = [l for l in lines if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("5. console without game errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Landing after the glider: running without a rollback (A1)")
s.close()
