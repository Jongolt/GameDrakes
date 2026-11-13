#!/usr/bin/env python3
"""What was walk-through - Poly Haven stones below 4 studs (9, incl.
the garden), Cliffs crystals (10), trees without a trunk (58: islets, ridge, the second island), the pier (the trunk-by-length rule). In a LOCAL
file on P8: every such item has a solid part (trees - TrunkCollider); the pier is solid, a ray from above hits
it; a real walk: the character walks Humanoid:MoveTo through a garden stone and stops (not closer to the centre than the stone radius).
Run: python3 tests/p8/solid_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("solid_check")
from p8lib import *  # noqa: F401,F403

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)

AUDIT = S(
    "local RS=game.ReplicatedStorage local Cfg=require(RS.Shared.Config) local D=Cfg.World.decor local DL=require(RS.Shared.Core.DecorLayout) "
    "local M=workspace.World.Meshes local res={rock={0,0},crystal={0,0},tree={0,0},pier={0,0}} local bad={} local skipped={} "
    "for _,it in DL.items() do local pre=string.sub(it.kind,1,3) local hr=D.height[it.kind] local cls "
    "if pre=='ph_' and string.find(it.kind,'rock',1,true) and it.h>=2 and it.h<4 then cls='rock' "
    "elseif string.find(it.kind,'crystal',1,true) then cls='crystal' "
    "elseif it.kind=='cs_pier' then cls='pier' "
    "elseif pre=='cs_' and hr and hr[1]>=14 and it.kind~='cs_vines' and not D.byLength[it.kind] and not it.collide and not table.find(D.solidKinds,it.kind) then cls='tree' end "
    "if cls then local f=M:FindFirstChild(it.kind) local best,bd if f then for _,m in f:GetChildren() do local p=m:GetPivot().Position "
    "local cf=m:GetBoundingBox() local d=math.min(Vector2.new(p.X-it.x,p.Z-it.z).Magnitude, Vector2.new(cf.Position.X-it.x,cf.Position.Z-it.z).Magnitude) "
    "local tc=m:FindFirstChild('TrunkCollider') if tc then d=math.min(d,Vector2.new(tc.Position.X-it.x,tc.Position.Z-it.z).Magnitude) end "
    "if not bd or d<bd then best,bd=m,d end end end "
    "if not f then skipped[it.kind]=(skipped[it.kind] or 0)+1 continue end "
    "res[cls][2]+=1 local ok=false if best and bd<6 then for _,p in best:GetDescendants() do if p:IsA('BasePart') and p.CanCollide then ok=true end end end "
    "if ok then res[cls][1]+=1 elseif #bad<12 then bad[#bad+1]=string.format('%s@%.0f,%.0f(%s)',it.kind,it.x,it.z,best and string.format('%.1f',bd) or 'no model') end end end "
    "local t={} for k,v in res do t[#t+1]=k..'='..v[1]..'/'..v[2] end table.sort(t) local sk={} for k,n in skipped do sk[#sk+1]=k..':'..n end "
    "return table.concat(t,' ')..' || '..table.concat(bad,' ')..' || not loaded in a local file: '..table.concat(sk,' ')")
P("solid (was walk-through):", AUDIT)
cnt = dict((k, (int(a), int(b))) for k, a, b in re.findall(r"(\w+)=(\d+)/(\d+)", AUDIT.split("||")[0]))
for k, (a, b) in cnt.items():
    ok(f"{k}: solid {a} of {b}", b > 0 and a == b, AUDIT.split("||")[1][:300])
P("not checked locally (Creator Store does not load in a file, checked in the cloud):", AUDIT.split("||")[-1])

PIER = S("local f=workspace.World.Meshes:FindFirstChild('cs_pier') local m=f and f:GetChildren()[1] if not m then return 'no pier' end "
         "local cf,sz=m:GetBoundingBox() local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={m} rp.RespectCanCollide=true "
         "local hit=workspace:Raycast(cf.Position+Vector3.new(0,30,0),Vector3.new(0,-60,0),rp) local tc=m:FindFirstChild('TrunkCollider') "
         "return string.format('hit=%s top=%.1f trunk=%s size=%.0fx%.0fx%.0f', hit and hit.Instance.Name or 'none', hit and hit.Position.Y or -1, tostring(tc~=nil), sz.X, sz.Y, sz.Z)")
P("pier:", PIER)
ok("pier: a ray from above (solid only) hits the deck, no trunk post", "hit=none" not in PIER and "trunk=false" in PIER, PIER)

# a real walk through a garden stone: start 8 studs away, the target - behind the stone
ROCK = S("local RS=game.ReplicatedStorage local W=require(RS.Shared.Config).World local DL=require(RS.Shared.Core.DecorLayout) "
         "for _,it in DL.items() do if it.y==W.terrace.y and string.sub(it.kind,1,7)=='ph_rock' and it.h<3 then return string.format('%s %.2f %.2f %.2f',it.kind,it.x,it.z,it.h) end end return 'none'")
P("garden stone for the walk:", ROCK)
if ROCK != "none":
    kind, rx, rz, rh = ROCK.split()
    rx, rz = float(rx), float(rz)
    walk = run(f"local p=game.Players:GetPlayers()[1] local ch=p.Character local hum=ch:FindFirstChildOfClass('Humanoid') "
               f"local f=workspace.World.Meshes:FindFirstChild('{kind}') local m,bd for _,x in f:GetChildren() do local c=x:GetBoundingBox() local d=Vector2.new(c.Position.X-({rx}),c.Position.Z-({rz})).Magnitude if not bd or d<bd then m,bd=x,d end end "
               f"local cf,sz=m:GetBoundingBox() local rad=math.min(sz.X,sz.Z)/2 "
               f"ch:PivotTo(CFrame.new({rx - 9},21.5,{rz})) task.wait(1.5) hum:MoveTo(Vector3.new({rx + 9},18,{rz})) local t0=os.clock() "
               f"local minD,yAt,yMax=1e9,0,0 while os.clock()-t0<5 do local q=ch.HumanoidRootPart.Position local d=Vector2.new(q.X-({rx}),q.Z-({rz})).Magnitude if d<minD then minD,yAt=d,q.Y end yMax=math.max(yMax,q.Y) task.wait(0.05) end "
               f"local q=ch.HumanoidRootPart.Position return string.format('minDist=%.2f rockHalf=%.2f rockTop=%.2f yAtMin=%.2f yMax=%.2f end=%.1f,%.1f,%.1f', minD, rad, cf.Position.Y+sz.Y/2, yAt, yMax, q.X-({rx}), q.Y, q.Z-({rz}))", "Server", 60)
    P("walk into the stone:", walk)
    m = re.search(r"minDist=([\d.]+) rockHalf=([\d.]+) rockTop=([\d.]+) yAtMin=([\d.]+)", walk)
    # a solid stone: the character either stops or walks ON it (a low stone with gentle sides - like a hill); inside - no
    inside = m is not None and float(m.group(1)) < float(m.group(2)) * 0.8 and float(m.group(4)) < float(m.group(3)) + 1.0
    ok("the character does not pass through a garden stone (stopped or went over the top)", m is not None and not inside, walk)
    C(f"local c=workspace.CurrentCamera local cf=CFrame.lookAt(Vector3.new({rx - 6},25,{rz + 8}),Vector3.new({rx},19,{rz})) local RunS=game:GetService('RunService') "
      "pcall(function() RunS:UnbindFromRenderStep('p8cam') end) RunS:BindToRenderStep('p8cam',Enum.RenderPriority.Last.Value+1,function() c.CameraType=Enum.CameraType.Scriptable c.CFrame=cf end) return 'ok'")
    time.sleep(2); shot("rock_walk")
    C("game:GetService('RunService'):UnbindFromRenderStep('p8cam') workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|build failed", l) and "ExecuteLuau" not in l]
ok("console without script errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Items that could be walked through (stones, crystals, trunks, pier)")
s.close()
