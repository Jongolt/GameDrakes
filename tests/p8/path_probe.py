#!/usr/bin/env python3
"""Why the chevron chain while riding goes straight through the fence (P8 day1_walkthrough: dev=0.0, onFence=2 at F4 and G8).
Computes PathfindingService paths on the client with different agent parameters: from a rider in the own plot to the golden nest on the slope
and back (from the slope to the gap line), foot parameters / riding (as in Hints.startTrail) / riding with a jump / start from the ground.
    python3 tests/p8/path_probe.py   (after open_local; starts the game itself, gives a dragon, mounts)"""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("path_probe")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(8)
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:60]); time.sleep(8)
P("setcomp:", S(LD + "local r=ld('setcomp moss1') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
P("time:", S(LD + "return ld('time 9999999')")[:30]); time.sleep(4)
P("mount:", S(LD + "local r=ld('mount') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:60]); time.sleep(2)
# targets: the golden nest on the slope (the point from the day run: 200.9,2.0,-53.8) and the line of the own gap
CODE = ("local PS=game:GetService('PathfindingService') local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart "
        "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end local hb=hn.Base "
        "local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "local P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 local G=Vector3.new(200.9,2.0,-53.8) "
        "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude pr.FilterDescendantsInstances={me.Character} "
        "for _,c in game:GetService('CollectionService'):GetTagged('Companion') do table.insert(pr.FilterDescendantsInstances,c) end "
        "local function ground(p) local h=workspace:Raycast(p+Vector3.new(0,5,0),Vector3.new(0,-60,0),pr) return h and h.Position or p end "
        "local function try(name,a,b,params) local ok,res=pcall(function() local path=PS:CreatePath(params) path:ComputeAsync(a,b) local n=#path:GetWaypoints() local j=0 for _,w in path:GetWaypoints() do if w.Action==Enum.PathWaypointAction.Jump then j+=1 end end return tostring(path.Status)..' wp='..n..' jumps='..j end) return name..': '..(ok and res or ('ERR '..tostring(res))) end "
        "local o={} local rp=r.Position local gp=ground(rp) table.insert(o,string.format('rider y=%.1f ground y=%.1f dy=%.1f', rp.Y, gp.Y, rp.Y-gp.Y)) "
        "local FOOT={AgentRadius=2.5,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4} local RIDE={AgentRadius=4.5,AgentHeight=9,AgentCanJump=false,WaypointSpacing=4} "
        "local RIDEJ={AgentRadius=4.5,AgentHeight=9,AgentCanJump=true,WaypointSpacing=4} local RIDE3={AgentRadius=3,AgentHeight=7,AgentCanJump=true,WaypointSpacing=4} "
        "table.insert(o,try('lot->slope ride(rider)',rp,G,RIDE)) table.insert(o,try('lot->slope ride(ground)',gp,G,RIDE)) table.insert(o,try('lot->slope ride+jump(ground)',gp,G,RIDEJ)) "
        "table.insert(o,try('lot->slope ride3+jump(ground)',gp,G,RIDE3)) table.insert(o,try('lot->slope foot(ground)',gp,G,FOOT)) "
        "local S2=P local Gg=ground(G) table.insert(o,try('slope->gate ride(ground)',Gg,S2,RIDE)) table.insert(o,try('slope->gate ride+jump',Gg,S2,RIDEJ)) table.insert(o,try('slope->gate ride3+jump',Gg,S2,RIDE3)) table.insert(o,try('slope->gate foot',Gg,S2,FOOT)) "
        "local function near(path) local fence={} local hn2=hn for _,d in hn2.Fence:GetDescendants() do if d:IsA('BasePart') then table.insert(fence,d) end end "
        "local out={} for i,w in path:GetWaypoints() do local q=w.Position local best=1e9 for _,d in fence do local lp=d.CFrame:PointToObjectSpace(q) local c=Vector3.new(math.clamp(lp.X,-d.Size.X/2,d.Size.X/2),math.clamp(lp.Y,-d.Size.Y/2,d.Size.Y/2),math.clamp(lp.Z,-d.Size.Z/2,d.Size.Z/2)) best=math.min(best,(d.CFrame:PointToWorldSpace(c)-q).Magnitude) end "
        "local dg=(Vector3.new(q.X,0,q.Z)-Vector3.new(P.X,0,P.Z)).Magnitude if w.Action==Enum.PathWaypointAction.Jump or best<2.5 then table.insert(out,string.format('%d:%s fence=%.1f gate=%.1f y=%.1f', i, w.Action==Enum.PathWaypointAction.Jump and 'JUMP' or 'near', best, dg, q.Y)) end end return table.concat(out,'; ') end "
        "local pj=PS:CreatePath(RIDEJ) pj:ComputeAsync(gp,G) table.insert(o,'lot->slope ride+jump waypoints near fence/jumps: '..near(pj)) "
        "local pf=PS:CreatePath(FOOT) pf:ComputeAsync(gp,G) table.insert(o,'lot->slope foot waypoints near fence/jumps: '..near(pf)) "
        "local pb=PS:CreatePath(RIDE) pb:ComputeAsync(Gg,S2) table.insert(o,'slope->gate ride waypoints near fence: '..near(pb)) "
        "return table.concat(o,' | ')")
res = C(CODE)
for part in res.split(" | "):
    P(part)
stop()
write_result("PathfindingService paths riding / on foot (plot <-> slope)")
