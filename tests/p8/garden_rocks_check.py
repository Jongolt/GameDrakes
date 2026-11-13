#!/usr/bin/env python3
"""The terrace garden stones must be solid (Kenney rock_largeA: in Kenney only the wood/stone/dirt parts are solid and only with collide).
In a LOCAL file on P8: the garden stones - rock_largeA at their points, all
parts (dirt body and grass top) CanCollide; a real walk Humanoid:MoveTo into the stone - it stops or goes over the top,
not inside; frames of the stone from four sides.
Run: python3 tests/p8/garden_rocks_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("garden_rocks_check")
from p8lib import *  # noqa: F401,F403

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)

ROCKS = S(
    "local RS=game.ReplicatedStorage local W=require(RS.Shared.Config).World local DL=require(RS.Shared.Core.DecorLayout) "
    "local f=workspace.World.Meshes:FindFirstChild('rock_largeA') local out={} "
    "for _,it in DL.items() do if it.y==W.terrace.y and it.kind=='rock_largeA' then local best,bd "
    "if f then for _,m in f:GetChildren() do local cf=m:GetBoundingBox() local d=Vector2.new(cf.Position.X-it.x,cf.Position.Z-it.z).Magnitude if not bd or d<bd then best,bd=m,d end end end "
    "if best and bd<4 then local cf,sz=best:GetBoundingBox() local n,solid,names=0,0,{} "
    "for _,p in best:GetDescendants() do if p:IsA('BasePart') then n+=1 if p.CanCollide then solid+=1 end names[#names+1]=p.Name..(p.CanCollide and '+' or '-') end end "
    "out[#out+1]=string.format('%.1f,%.1f off=%.1f h=%.2f top=%.2f parts=%d solid=%d [%s]', it.x, it.z, bd, sz.Y, cf.Position.Y+sz.Y/2, n, solid, table.concat(names,' ')) "
    "else out[#out+1]=string.format('%.1f,%.1f MISSING', it.x, it.z) end end end return table.concat(out,' ;; ')")
P("garden stones:", ROCKS)
rows = [r for r in ROCKS.split(" ;; ") if r]
ok("garden stones rock_largeA 5 (6 wedges, one removed by the clearing at the campfire)", len(rows) == 5, str(len(rows)))
ok("each garden stone at its point", rows and all("MISSING" not in r for r in rows), ROCKS[:300])
ok("every garden stone has all parts solid (body and grass top)", rows and all(re.search(r"parts=(\d+) solid=\1 ", r) for r in rows), ROCKS[:400])

m = re.match(r"(-?[\d.]+),(-?[\d.]+) .*?top=([\d.]+)", rows[1] if len(rows) > 1 else "")
if m:
    rx, rz, top = float(m.group(1)), float(m.group(2)), float(m.group(3))
    walk = run(f"local p=game.Players:GetPlayers()[1] local ch=p.Character local hum=ch:FindFirstChildOfClass('Humanoid') "
               f"ch:PivotTo(CFrame.new(({rx}) - 9, 21.5, {rz})) task.wait(1.5) hum:MoveTo(Vector3.new(({rx}) + 9, 18, {rz})) local t0=os.clock() "
               f"local minD,yAt=1e9,0 while os.clock()-t0<5 do local q=ch.HumanoidRootPart.Position local d=Vector2.new(q.X-({rx}),q.Z-({rz})).Magnitude if d<minD then minD,yAt=d,q.Y end task.wait(0.05) end "
               "return string.format('minDist=%.2f yAtMin=%.2f', minD, yAt)", "Server", 60)
    P(f"walk into the stone ({rx},{rz}, top {top}):", walk)
    mm = re.search(r"minDist=([\d.]+) yAtMin=([\d.]+)", walk)
    # inside = near the stone centre, with the character root below the stone top + 1 (before the fix: ~21.9 with the top at ~21)
    inside = mm is not None and float(mm.group(1)) < 1.5 and float(mm.group(2)) < top + 1.0
    ok("the character does not pass through a garden stone (stopped or went over the top)", mm is not None and not inside, walk)
    C("local p=game.Players.LocalPlayer if p.Character then p.Character:PivotTo(CFrame.new(0,40,-600)) end return 'away'")
    for name, dx, dz in (("S", 0, 9), ("E", 9, 0), ("N", 0, -9), ("W", -9, 0)):
        C(f"local c=workspace.CurrentCamera local cf=CFrame.lookAt(Vector3.new(({rx}) + {dx},{top} + 2.5,({rz}) + {dz}),Vector3.new({rx},{top} - 1.5,{rz})) local RunS=game:GetService('RunService') "
          "pcall(function() RunS:UnbindFromRenderStep('p8cam') end) RunS:BindToRenderStep('p8cam',Enum.RenderPriority.Last.Value+1,function() c.CameraType=Enum.CameraType.Scriptable c.CFrame=cf end) return 'ok'")
        time.sleep(1.5); shot(f"R_{name}")
    C("game:GetService('RunService'):UnbindFromRenderStep('p8cam') workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|Decor\] build failed", l) and "ExecuteLuau" not in l]
ok("console without script errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Garden stone is solid (the same stone)")
s.close()
