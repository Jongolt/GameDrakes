#!/usr/bin/env python3
"""The companion leash after the fix (measures the center of mass, after catching up stands at the leash point).
The profile with an elder - seed_stage3.json, written by tests/p8/companion_spawn_check.py (run it first on the same UTC day)
or the path in SEED. P8 after open_local.sh: the player walks 40 studs away and 30 more sideways -> at the stops the camera is not inside the dragon,
the center of mass at the leash point (leash 20.5), the dragon does not crawl away from the player, walked up to the dragon - the Fly button is visible. The frames W*.jpg.
20.10 evening (Config.Dragon.regroup): the server moves a stuck companion in an arc to a free flat spot (the model attributes Regroups /
RegroupWhy / RegroupMiss). The probe: on the open plaza there are no false moves; a forced move (LoopDebug regroup) puts
the dragon on a support nearby, the camera is clear; after walking - at the leash point or (if there was a move) nearby and at rest; not more than 6 moves."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("companion_walk_check")
from p8lib import *  # noqa: F401,F403
def edit(code): return run(code, "Edit")
SEEDF = os.environ.get("SEED") or os.path.join(os.path.dirname(OUT), "companion_spawn_check", "seed_stage3.json")
d0 = json.load(open(SEEDF)); d0["lastSeen"] = int(time.time()); js = json.dumps(d0, ensure_ascii=False)
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
stop(); start(); time.sleep(3)
for _ in range(40):
    if C("return tostring(workspace.CurrentCamera.CameraType)") == "Enum.CameraType.Custom": break
    time.sleep(0.5)
CAM = ("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end "
       "local cam=workspace.CurrentCamera local b=Instance.new('Part') b.Anchored=true b.CanQuery=false b.CanCollide=false b.Size=Vector3.new(0.6,0.6,0.6) b.CFrame=cam.CFrame b.Parent=workspace "
       "local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Include op.FilterDescendantsInstances={m} local n=#workspace:GetPartsInPart(b,op) b:Destroy() "
       "return string.format('%s %s', n>0 and 'INSIDE' or 'clear', tostring(cam.CameraType))")
D = ("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end "
     "local r=me.Character.HumanoidRootPart local b=m.PrimaryPart local c=b.AssemblyCenterOfMass "
     "return string.format('com %.1f body %.1f v %.1f', Vector2.new(c.X-r.Position.X,c.Z-r.Position.Z).Magnitude, Vector2.new(b.Position.X-r.Position.X,b.Position.Z-r.Position.Z).Magnitude, b.AssemblyLinearVelocity.Magnitude)")
RGQ = ("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end "
       "return string.format('%d %d %s', m:GetAttribute('Regroups') or 0, m:GetAttribute('RegroupMiss') or 0, tostring(m:GetAttribute('RegroupWhy') or '-'))")
def regroups(): return int(C(RGQ).split()[0])
P("start:", C(D), "| moves:", C(RGQ))
def walk(x, z, secs=7):
    C(f"local h=game.Players.LocalPlayer.Character.Humanoid h:MoveTo(Vector3.new({x},19,{z})) return 'go'")
    for i in range(secs):
        time.sleep(1); P(f"  {x},{z} t{i+1}:", C(D))
walk(0, 20)        # forward to Old Ash (past the plaza)
time.sleep(3); c1 = C(CAM); P("the camera after stop 1:", c1, C(D)); shot("W0_stop1")
ok("stop 1: the camera is not inside the dragon", c1.startswith("clear"), c1)
rg1 = C(RGQ); ok("on the open plaza there are no false moves", rg1.split()[0] == "0", rg1)
rg_before = regroups()
walk(-30, 10)      # left-forward
shot("W1_after_walk")
time.sleep(4); P("standing for 4 s:", C(D))
c2 = C(CAM); P("the camera after stop 2:", c2)
ok("stop 2: the camera is not inside the dragon", c2.startswith("clear"), c2)
r1 = C(D)
time.sleep(5); r2 = C(D)
P("standing 5 s more:", r2)
com1 = float(r1.split()[1]); com2 = float(r2.split()[1])
rg_walk = regroups() - rg_before; P("moves on the leg to -30,10:", rg_walk, C(RGQ))
v2 = float(r2.split()[5])
if rg_walk == 0:
    ok("after walking the companion stands at the leash point (the center of mass 18.5..21.5 at leash 20.5)", 18.5 <= com2 <= 21.5, r2)
else:  # got stuck on the way and moved: the spot to the side of the player (spawnSpot), not necessarily on the leash
    ok("after walking the companion got stuck and was moved: stands nearby (the center of mass <= 21.5) and at rest (v < 0.3)", com2 <= 21.5 and v2 < 0.3, f"{r2} | {C(RGQ)}")
ok("at the stop the companion does not crawl away from the player (the center of mass does not recede by more than 1.5; catching up is allowed)", com2 <= com1 + 1.5, f"{r1} -> {r2}")  # the first version required |shift| < 1.5 and caught the catch-up 24.2 -> 20.6
# walk up to the dragon: the Fly button
C("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end local p=m.PrimaryPart.AssemblyCenterOfMass me.Character.Humanoid:MoveTo(Vector3.new(p.X,19,p.Z)) return 'go'")
time.sleep(3)
P("walked up:", C(D))
ok("walked up to the dragon - the Fly button is visible", has("HUD", "Fly"), C(D))
shot("W2_near")
# the bottom above the ground on the way and at the stops; stairs 1 (the terrace top -> the glade -> back)
G = ("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end "
     "local cf,size=m:GetBoundingBox() local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={m,me.Character} rp.RespectCanCollide=true "
     "local gh=workspace:Raycast(cf.Position, Vector3.new(0,-(size.Y/2+40),0), rp) local b=m.PrimaryPart "
     "local gmax=gh and gh.Position.Y for _,o in {{1,0},{-1,0},{0,1},{0,-1}} do local off=cf.Rotation*Vector3.new(o[1]*size.X*0.35,0,o[2]*size.Z*0.35) "
     "local h=workspace:Raycast(cf.Position+off, Vector3.new(0,-(size.Y/2+40),0), rp) if h and (gmax==nil or h.Position.Y>gmax) then gmax=h.Position.Y end end "
     "return string.format('%.2f %.2f %s center=%.2f', gmax and (cf.Position.Y-size.Y/2-gmax) or 99, b.AssemblyLinearVelocity.Magnitude, gh and gh.Instance.Name or 'none', gh and (cf.Position.Y-size.Y/2-gh.Position.Y) or 99)")
# a forced move on the plaza (the arc mechanics and the spot without getting stuck)
LD = "local function ld(c) return game.ServerStorage.LoopDebug:Invoke(c) end "
n0 = regroups()
rr = S(LD + "return ld('regroup')")  # the line 'reply=<ok>/<reason> nest=...' (Nest, LoopDebug)
P("the forced move:", rr)
time.sleep(3)
g_rg = C(G); d_rg = C(D); c_rg = C(CAM); P("after the move:", g_rg, "|", d_rg, "|", c_rg, "|", C(RGQ)); shot("W2b_regroup")
ok("the forced move: the server answered ok and the counter grew by 1", "reply=true/" in rr and regroups() == n0 + 1, f"{rr[:60]} | {C(RGQ)}")
ok("after the move the companion is on a support (the bottom above the support -0.3..0.6), at rest (v < 0.3), nearby (the center of mass <= 21.5), the camera is clear",
   -0.3 <= float(g_rg.split()[0]) <= 0.6 and float(d_rg.split()[5]) < 0.3 and float(d_rg.split()[1]) <= 21.5 and c_rg.startswith("clear"), f"{g_rg} | {d_rg} | {c_rg}")
ST = S("local w for _,x in game:GetService('CollectionService'):GetTagged('Stairs') do if x.Name=='Stairs1' then w=x end end if not w then return '-' end "
       "local top=w.CFrame.Position-w.CFrame.LookVector*(w.Size.Z/2) local bot=w.CFrame.Position+w.CFrame.LookVector*(w.Size.Z/2) "
       "return string.format('%.1f,%.1f,%.1f|%.1f,%.1f,%.1f', top.X, top.Y, top.Z, bot.X, bot.Y, bot.Z)")
P("stairs 1 top|bottom:", ST)
samples = []
def walk_to(x, y, z, secs):
    C(f"local h=game.Players.LocalPlayer.Character.Humanoid h:MoveTo(Vector3.new({x},{y},{z})) return 'go'")
    for i in range(secs):
        time.sleep(1); g = C(G); samples.append(g); P(f"  -> {x:.0f},{z:.0f} t{i+1}: ground/v/hit {g} | {C(D)}")
tx, ty, tz = (float(v) for v in ST.split("|")[0].split(","))
bx, by, bz = (float(v) for v in ST.split("|")[1].split(","))
px, pz = (float(v) for v in C("local r=game.Players.LocalPlayer.Character.HumanoidRootPart return string.format('%.1f,%.1f', r.Position.X, r.Position.Z)").split(","))
# to the top of the stairs in steps of ~60 studs (MoveTo fades after 8 s)
import math as _m
n = max(1, int(_m.hypot(tx - px, tz - pz) // 60) + 1)
for k in range(1, n + 1):
    walk_to(px + (tx - px) * k / n, 19, pz + (tz - pz) * k / n, 5)
walk_to(bx, by + 1, bz, 6); shot("W3_stairs_down")
walk_to(tx, 19, tz, 7); time.sleep(4); g_top = C(G); samples.append(g_top); P("at the top, standing for 4 s:", g_top); shot("W4_stairs_up")
vals = [(float(a.split()[0]), float(a.split()[1])) for a in samples if not a.startswith("99")]
# the sinking is measured by the ground under the center (center=); by the highest of the five points on a slope the bottom of a wide body is legitimately below
# the upper edge (P8 retention2: -1.46 at center=+1.88 at the bottom of the stairs - the body above the ground, the wing at the slope)
cents = [float(a.split("center=")[1]) for a in samples if "center=" in a and not a.startswith("99")]
ok("on the way and on the stairs the companion does not sink underground (the bottom not below the ground under the center by 0.5)", all(v >= -0.5 for v in cents), str(cents))
P("for the record: the bottom above the highest support on the way:", [v[0] for v in vals])
# the support = the highest ground under the body (5 rays, like the leash target); under the center at the terrace edge there may be a slope (center= in the details)
ok("at the top of the stairs the companion stands on a support (the bottom above the support <= 0.6) and does not shake (v < 0.3)", -0.3 <= float(g_top.split()[0]) <= 0.6 and float(g_top.split()[1]) < 0.3, g_top)
rg_end = C(RGQ); P("moves over the run:", rg_end)
ok("not more than 6 moves over the run (no storm of hops)", int(rg_end.split()[0]) <= 6, rg_end)
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("The companion leash: walking and stops (20.10)")
s.close()
