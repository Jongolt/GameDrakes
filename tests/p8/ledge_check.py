#!/usr/bin/env python3
"""The nest ledge -> updraft -> gliding (02 §2 0:50-1:00, quest 2 'Jump off the ledge';
an updraft at the ledge: WorldBuilder LedgeUpdraft + Controllers/Updraft). In a LOCAL file on P8: (1) 7 updrafts (6 nests + Cliffs);
(2) a newcomer with a baby on the shoulder steps off the ledge (Humanoid:Move every frame - like the joystick control module; ssh keys on P8
do not always arrive): the updraft lifts above the edge, then Gliding no shorter than 2 s, landing on land (meadow, not the sea), the onboarding step
glide_first, the Keeper quest 2 done; (3) the updraft at Cliffs lifts to the egg platforms (40-60); (4) updraft frames; console.
Run: python3 tests/p8/ledge_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("ledge_check")
from p8lib import *  # noqa: F401,F403

NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")
# trace on the client every 0.1 s: rise above the start, the first Gliding, duration, where it landed
TRACE = ("local me=game.Players.LocalPlayer local sv=game.ReplicatedStorage:FindFirstChild('LT') or Instance.new('StringValue') sv.Name='LT' sv.Value='' sv.Parent=game.ReplicatedStorage "
         "task.spawn(function() local t0=os.clock() local r=me.Character.HumanoidRootPart local y0=r.Position.Y local maxUp=0 local first=nil local gl=0 local upd=0 "
         "while os.clock()-t0<{secs} do maxUp=math.max(maxUp,r.Position.Y-y0) if me:GetAttribute('Gliding') then gl+=0.1 if not first then first=os.clock()-t0 end end "
         "if me:GetAttribute('Updraft') then upd+=0.1 end task.wait(0.1) end local p=r.Position "
         "sv.Value=string.format('maxUp=%.1f firstGlide=%s glideSec=%.1f updraftSec=%.1f end=%.0f,%.0f,%.0f r=%.0f', maxUp, first and string.format('%.1f',first) or 'nil', gl, upd, p.X,p.Y,p.Z, math.sqrt(p.X*p.X+p.Z*p.Z)) end) return 'trace'")
def trace(secs): return C(TRACE.replace("{secs}", str(secs)))
def trace_read(): return C("local v=game.ReplicatedStorage:FindFirstChild('LT') return v and v.Value or 'none'")

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
cnt = S("local n,ns=0,{} for _,p in game:GetService('CollectionService'):GetTagged('Updraft') do n+=1 ns[#ns+1]=(p.Parent and p.Parent.Name or '?')..'/'..p.Name end table.sort(ns) return n..' '..table.concat(ns,' ')")
P("updrafts:", cnt)
ok("7 updrafts: at the ledge of each of the 6 nests and at Cliffs", cnt.startswith("7 ") or cnt.startswith("8 "), cnt)  # 8 - if the world has a NestTemplate

# the newcomer's first hatch, the baby on the shoulder
S(LD + "ld('go table') task.wait(1.5) ld('go inc') task.wait(5) return 'x'")
for _ in range(15):
    m = re.search(r"inc1=\w+:(-?\d+)", state())
    if m and int(m.group(1)) <= 0: break
    time.sleep(1)
C("local r=game.ReplicatedStorage.Remotes.HatchReady:InvokeServer(1) return tostring(r and r.ok)"); time.sleep(9)
P("companion:", C("return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))"), "| quest:", dump().get("quests", {}).get("keeper"))
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ok'"); time.sleep(1.5)
fwd = S(NEST + "local z=n:GetPivot():VectorToWorldSpace(Vector3.new(0,0,1)) return string.format('%.3f,0,%.3f', z.X, z.Z)")
# camera behind, looking forward (like a player walking to the ledge): the glide goes where the camera looks
C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local f=Vector3.new({fwd}).Unit c.CFrame=CFrame.lookAt(r.Position-f*12+Vector3.new(0,5,0), r.Position+f*30) return 'cam'")
time.sleep(0.5)
trace(12)
C("local me=game.Players.LocalPlayer local h=me.Character:FindFirstChildOfClass('Humanoid') local t0=os.clock() local c c=game:GetService('RunService').RenderStepped:Connect(function() "
  f"if os.clock()-t0<1.6 then h:Move(Vector3.new({fwd}).Unit,false) else h:Move(Vector3.zero,false) c:Disconnect() end end) return 'move'")
time.sleep(13)
tr = trace_read(); P("step off the ledge:", tr); shot("G1_after")
m = re.search(r"maxUp=([-\d.]+) firstGlide=(\S+) glideSec=([\d.]+) updraftSec=([\d.]+) end=(-?\d+),(-?\d+),(-?\d+) r=(\d+)", tr)
ok("the ledge updraft lifted above the edge (>= 8 studs)", m is not None and float(m.group(1)) >= 8, tr)
ok("then gliding no shorter than 2 s", m is not None and m.group(2) != "nil" and float(m.group(3)) >= 2, tr)
land = S(f"local ok=require(game.ReplicatedStorage.Shared.Core.Island).onLand({m.group(5)},{m.group(7)},0) return tostring(ok)") if m else "?"
ok("landing on land (meadow), not in the sea", land == "true" and m is not None and float(m.group(6)) > -1, f"{tr} onLand={land}")
d = dump()
ob = (d.get("analytics") or {}).get("onboard") or {}
ok("onboarding step glide_first recorded", "5" in ob, json.dumps(ob))
kp = (d.get("quests") or {}).get("keeper")
P("quest after gliding:", kp)
ok("Keeper quest 2 (gliding) done", isinstance(kp, dict) and kp.get("step", 0) >= 3, json.dumps(kp)[:200])

# a step off the side edge of the ledge (x = 20): the updraft across the whole ledge width also lifts
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(20,3,44)) return 'ok'"); time.sleep(1.5)
C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local f=Vector3.new({fwd}).Unit c.CFrame=CFrame.lookAt(r.Position-f*12+Vector3.new(0,5,0), r.Position+f*30) return 'cam'")
time.sleep(0.5); trace(10)
C("local me=game.Players.LocalPlayer local h=me.Character:FindFirstChildOfClass('Humanoid') local t0=os.clock() local c c=game:GetService('RunService').RenderStepped:Connect(function() "
  f"if os.clock()-t0<1.6 then h:Move(Vector3.new({fwd}).Unit,false) else h:Move(Vector3.zero,false) c:Disconnect() end end) return 'move'")
time.sleep(11)
ts = trace_read(); P("step off the side edge:", ts)
ms = re.search(r"maxUp=([-\d.]+) firstGlide=(\S+) glideSec=([\d.]+)", ts)
ok("step off the side edge of the ledge (x 20): lifted and glide >= 2 s", ms is not None and float(ms.group(1)) >= 8 and float(ms.group(3)) >= 2, ts)

# the Cliffs updraft
cl = S("local u=workspace.World:FindFirstChild('CliffsUpdraft',true) if not u then return 'none' end local p=game.Players:GetPlayers()[1] "
       "p.Character:PivotTo(CFrame.new(u.Position.X, u.Position.Y-u.Size.Y/2+4, u.Position.Z)) return string.format('%.0f,%.0f,%.0f top=%.0f', u.Position.X, u.Position.Y, u.Position.Z, u.Position.Y+u.Size.Y/2)")
P("Cliffs updraft:", cl); time.sleep(0.5)
trace(9); time.sleep(10)
tc = trace_read(); P("Cliffs updraft, trace:", tc); shot("C1_after_cliffs_updraft")
mc = re.search(r"maxUp=([-\d.]+)", tc)
ok("the Cliffs updraft lifts (>= 30 studs, to the platforms 40-60)", mc is not None and float(mc.group(1)) >= 30, tc)

# frames of the updraft at the own nest (the camera is held every frame - otherwise the camera controller takes it back)
cf = S(NEST + "local a=n:GetPivot() local function v(x,y,z) local q=(a*CFrame.new(x,y,z)).Position return string.format('%.0f,%.0f,%.0f',q.X,q.Y,q.Z) end "
       "return v(0,-6,120)..'|'..v(0,2,60)..'|'..v(-40,8,62)..'|'..v(0,2,60)..'|'..v(0,6,38)..'|'..v(0,0,75)")
pts = cf.split("|")
S("local p=game.Players:GetPlayers()[1] p.Character:PivotTo(CFrame.new(0,40,-300)) return 'away'"); time.sleep(1.5)
if len(pts) == 6:
    for i, name in enumerate(["F1_from_meadow", "F2_side", "F3_from_ledge"]):
        C(f"local c=workspace.CurrentCamera local t0=os.clock() local cn cn=game:GetService('RunService').RenderStepped:Connect(function() c.CameraType=Enum.CameraType.Scriptable "
          f"c.CFrame=CFrame.lookAt(Vector3.new({pts[2*i]}),Vector3.new({pts[2*i+1]})) if os.clock()-t0>5 then cn:Disconnect() c.CameraType=Enum.CameraType.Custom end end) return 'ok'")
        time.sleep(2.5); shot(name); time.sleep(3)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error|\[Updraft\]|\[Glide\]", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "errors 0" not in l and "TexturePack" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Nest ledge: updraft and gliding")
s.close()
