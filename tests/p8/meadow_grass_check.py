#!/usr/bin/env python3
"""Roblox tall grass (Terrain.Decoration)
grows only on the Grass material; 40 LeafyGrass patches on the meadow (Config.World.leafyPatches, 11.10) - flat ground without grass,
the phone draws it in a flat colour. In a LOCAL file on P8: the terrain material over the meadow grid (a ray into Terrain) - the share of Grass and
LeafyGrass outside the nest pads; frames at eye level at the former large patches (4 sides) and from above.
Run: python3 tests/p8/meadow_grass_check.py before|after (after tools/p8/open_local.sh). Output: p8lib.OUT/<tag>_*."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
TAG = sys.argv[1] if len(sys.argv) > 1 else "after"
p8lib.begin("meadow_grass_check")
from p8lib import *  # noqa: F401,F403

# centres of the large patches before the fix (DecorLayout.leafyPatches: three patches near 20,-215 merged into a strip of ~100 studs)
SPOTS = [("A", 25, -215), ("B", -290, 390)]

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)

GRID = S(
    "local rp=RaycastParams.new() "
    "rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={workspace.Terrain} "
    "local c={} local n=0 "
    "for x=-520,520,12 do for z=-520,520,12 do local h=workspace:Raycast(Vector3.new(x,300,z),Vector3.new(0,-400,0),rp) "
    "if h and h.Position.Y>-1 and h.Position.Y<60 then local m=h.Material.Name c[m]=(c[m] or 0)+1 n+=1 "
    "end end end "
    "local t={} for m,k in c do t[#t+1]=m..'='..k end table.sort(t) return 'n='..n..' '..table.concat(t,' ')")
P(f"[{TAG}] terrain material over a 12-stud grid (land y 0-60):", GRID)
m = dict(re.findall(r"(\w+)=(\d+)", GRID))
grass, leafy = int(m.get("Grass", 0)), int(m.get("LeafyGrass", 0))
P(f"[{TAG}] Grass {grass}, LeafyGrass {leafy} ({100 * leafy / max(1, grass + leafy):.1f}% of grassy land)")
# nest pads (nestGround) - LeafyGrass on purpose: 6 circles; after the fix there must be no LeafyGrass outside them
NEST = S("local n,l=0,0 local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={workspace.Terrain} "
         "for _,s in {{25,-215},{-290,390},{20,-221},{-296,395},{197,62},{-116,207},{347,201}} do for dx=-12,12,6 do for dz=-12,12,6 do "
         "local h=workspace:Raycast(Vector3.new(s[1]+dx,300,s[2]+dz),Vector3.new(0,-400,0),rp) if h then n+=1 if h.Material==Enum.Material.LeafyGrass then l+=1 end end end end end "
         "return l..'/'..n")
P(f"[{TAG}] LeafyGrass at the centres of the former large patches (7 spots x 25 points):", NEST)
if TAG == "after":
    ok("no LeafyGrass in the former meadow patches", NEST.startswith("0/"), NEST)
else:
    ok("BEFORE the fix: LeafyGrass exists in the meadow patches (reproduction)", not NEST.startswith("0/"), NEST)

C("local p=game.Players.LocalPlayer if p.Character then p.Character:PivotTo(CFrame.new(0,40,-600)) end return 'away'")
def cam(eye, look):
    C("local c=workspace.CurrentCamera local cf=CFrame.lookAt(Vector3.new(%s),Vector3.new(%s)) local RunS=game:GetService('RunService') "
      "pcall(function() RunS:UnbindFromRenderStep('p8cam') end) RunS:BindToRenderStep('p8cam',Enum.RenderPriority.Last.Value+1,function() "
      "c.CameraType=Enum.CameraType.Scriptable c.CFrame=cf end) return 'ok'" % (eye, look))
    time.sleep(2.0)
for name, x, z in SPOTS:
    gy = S(f"local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={{workspace.Terrain}} "
           f"local h=workspace:Raycast(Vector3.new({x},300,{z}),Vector3.new(0,-400,0),rp) return h and string.format('%.1f %s',h.Position.Y,h.Material.Name) or 'none'")
    P(f"[{TAG}] point {name} ({x},{z}): ground {gy}")
    y = float(gy.split()[0]) if gy != "none" else 10.0
    for d, dx, dz in (("S", 0, 14), ("E", 14, 0), ("N", 0, -14), ("W", -14, 0)):
        cam(f"{x + dx},{y + 5},{z + dz}", f"{x - dx},{y + 3},{z - dz}"); shot(f"{TAG}_{name}_{d}")
    cam(f"{x + 2},{y + 60},{z + 2}", f"{x},{y},{z}"); shot(f"{TAG}_{name}_top")
C("game:GetService('RunService'):UnbindFromRenderStep('p8cam') workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|build failed|leafy", l) and "ExecuteLuau" not in l]
ok(f"[{TAG}] console without script and terrain errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result(f"Meadow grass: LeafyGrass patches ({TAG})")
s.close()
