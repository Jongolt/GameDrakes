#!/usr/bin/env python3
"""Scroll 12 at the edge of the Cliffs ledge (cliffs_7, update 4) - can it be reached on foot. In a LOCAL file on P8:
LiveOpsDebug update 4 -> the scrolls are in place; PathfindingService (an R15 character agent: radius 2, height 5, jump) from every other
Cliffs egg point to the ground under the scroll; the character walks along the waypoints with a real Humanoid:MoveTo from the farthest reachable
point and must end up within the prompt radius (promptDistance 10); then the real E key - the scroll is read. Frames of the scroll
from four sides and from above. Run: python3 tests/p8/scroll12_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("scroll12_check")
from p8lib import *  # noqa: F401,F403

def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
SC = ("local sc for _,m in workspace:GetDescendants() do if m:GetAttribute('Scroll')==12 then sc=m end end if not sc then return 'none' end "
      "local p=sc:IsA('Model') and sc:GetPivot().Position or sc.Position ")

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
r = lo("update 4"); P("update 4:", r[:300])
for _ in range(20):
    if S(SC + "return 'ok'") != "none": break
    time.sleep(2)
pos = S(SC + "local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={sc} "
        "local h=workspace:Raycast(p,Vector3.new(0,-40,0),rp) return string.format('%.1f,%.1f,%.1f ground=%.1f on=%s', p.X,p.Y,p.Z, h and h.Position.Y or -1, h and h.Instance.Name or '-')")
P("scroll 12:", pos)
ok("scroll 12 stands in the world (update 4)", pos != "none" and "ground=" in pos, pos)
m = re.match(r"(-?[\d.]+),(-?[\d.]+),(-?[\d.]+) ground=(-?[\d.]+)", pos)
sx, sy, sz, gy = (float(x) for x in m.groups()) if m else (0, 0, 0, 0)
if gy < 0:  # the rays do not see the decor boulder (CanQuery = false, pitfall 6): support = the scroll minus the lift (Config.LiveOps.scrolls.lift 2.5)
    gy = sy - 2.5

# paths from the other Cliffs points
PATHS = S(f"local PFS=game:GetService('PathfindingService') local goal=Vector3.new({sx},{gy}+2.5,{sz}) local out={{}} "
          "for _,a in workspace:GetDescendants() do if a:IsA('BasePart') and a:GetAttribute('PointId') and a:GetAttribute('Zone')=='Cliffs' and a.Name~='cliffs_7' and not a:GetAttribute('Secret') then "
          "local path=PFS:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=6}) "
          "local okp=pcall(function() path:ComputeAsync(a.Position+Vector3.new(0,3,0),goal) end) "
          "local n=okp and path.Status==Enum.PathStatus.Success and #path:GetWaypoints() or 0 "
          "out[#out+1]=string.format('%s:%s:%d:%.0f', a.Name, okp and path.Status.Name or 'err', n, (a.Position-goal).Magnitude) end end table.sort(out) return table.concat(out,' ')")
P("paths from the Cliffs points (point:status:waypoints:distance):", PATHS)
good = [x.split(":") for x in PATHS.split() if ":Success:" in x]
ok("a walking path to scroll 12 found from at least one Cliffs point", len(good) > 0, PATHS[:300])
ok("a path found from most Cliffs points", len(good) * 2 >= max(1, len(PATHS.split())), f"{len(good)} of {len(PATHS.split())}")

# a real walk: from the farthest reachable point along the waypoints
if good:
    far = max(good, key=lambda g: float(g[3]))[0]
    walk = run(f"local PFS=game:GetService('PathfindingService') local p=game.Players:GetPlayers()[1] local ch=p.Character local hum=ch:FindFirstChildOfClass('Humanoid') "
             f"local a for _,x in workspace:GetDescendants() do if x:IsA('BasePart') and x.Name=='{far}' and x:GetAttribute('PointId') then a=x end end "
             f"local goal=Vector3.new({sx},{gy}+2.5,{sz}) ch:PivotTo(CFrame.new(a.Position+Vector3.new(0,4,0))) task.wait(1.5) "
             "local path=PFS:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=6}) path:ComputeAsync(ch.HumanoidRootPart.Position,goal) "
             "if path.Status~=Enum.PathStatus.Success then return 'nopath '..path.Status.Name end local t0=os.clock() "
             "for _,w in path:GetWaypoints() do if w.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end hum:MoveTo(w.Position) local done=false local c=hum.MoveToFinished:Connect(function() done=true end) "
             "local t1=os.clock() while not done and os.clock()-t1<6 do task.wait(0.1) end c:Disconnect() end "
             f"local d=(ch.HumanoidRootPart.Position-Vector3.new({sx},{sy},{sz})).Magnitude return string.format('from=%s wp=%d sec=%.0f dist=%.1f y=%.1f', '{far}', #path:GetWaypoints(), os.clock()-t0, d, ch.HumanoidRootPart.Position.Y)", "Server", 300)
    P("walk:", walk)
    md = re.search(r"dist=([\d.]+)", walk)
    ok("the character walked within the prompt radius (<= 10)", md is not None and float(md.group(1)) <= 10, walk)
    shot("W_after_walk")
    before = dump().get("quests", {})
    C("local best,bd for _,p in workspace:GetDescendants() do if p:IsA('ProximityPrompt') and p.Enabled and p.Parent and p.Parent:IsA('BasePart') then "
      "local d=(p.Parent.Position-game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude if d<=p.MaxActivationDistance and (not bd or d<bd) then best,bd=p,d end end end "
      "if best then best:InputHoldBegin() task.wait(best.HoldDuration+0.2) best:InputHoldEnd() return best.ActionText end return 'noprompt'")  # the nearest prompt, like a phone button
    time.sleep(3)
    rd = lo("")
    P("after E:", rd[:200])
    shot("W_after_E")
    reader = C("local g=game.Players.LocalPlayer.PlayerGui local t={} for _,x in g:GetDescendants() do if x:IsA('TextLabel') and x.Visible and x.ContentText:find('Scroll') then t[#t+1]=x.ContentText:sub(1,60) end end return table.concat(t,' / ')")
    P("texts with Scroll on the screen:", reader)

# frames
for name, dx, dz in (("C1_south", 0, 22), ("C2_east", 22, 0), ("C3_north", 0, -22), ("C4_west", -22, 0)):
    C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable c.CFrame=CFrame.lookAt(Vector3.new({sx + dx},{sy + 10},{sz + dz}),Vector3.new({sx},{sy},{sz})) return 'ok'")
    time.sleep(1.5); shot(name)
C(f"local c=workspace.CurrentCamera c.CFrame=CFrame.lookAt(Vector3.new({sx + 2},{sy + 45},{sz + 2}),Vector3.new({sx},{sy},{sz})) return 'ok'"); time.sleep(1.5); shot("C5_top")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'")
lo("offset 0")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"LiveOps|Stack Begin|attempt to", l) and "not authorized" not in l and "ExecuteLuau" not in l]
ok("console without LiveOps and script errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Scroll 12 (cliffs_7) on foot")
s.close()
