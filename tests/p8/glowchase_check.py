#!/usr/bin/env python3
"""The glowing egg path in Play through the client's eyes (the chase). The golden nest after the first skirmish (egg in the nest, is it visible on screen), the guard
(where the enemies are relative to the player, are they visible in the camera), removing the guard (LoopDebug combat clear), took -> chase (GloomChase model, '!'),
stands still -> CAUGHT, the egg back to the nest; took again and runs home at 16 studs/s -> not caught, the stand at home; the arrow and the step during
the chase, the fight music; console. Run: python3 tests/p8/glowchase_check.py (after open_local with the glow-egg build)."""
import os, sys, time, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glowchase_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
NEST = ("local m=workspace:FindFirstChild('GlowEggs') m=m and m:FindFirstChildWhichIsA('Model') "
        "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') ")
GROUND = ("local function gy(x,z) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
          "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('GlowEggs')} "
          "local h=workspace:Raycast(Vector3.new(x,400,z),Vector3.new(0,-800,0),pr) return h and h.Position.Y or 0 end ")

stop()
P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end "
               "s.Value='{\"coins\":0,\"onboarding\":{\"flew\":true,\"firstHatch\":true,\"rode\":true},\"combat\":{\"stage\":1},"
               "\"eggs\":{\"carry\":{\"id\":\"meadow_1\",\"element\":\"moss\",\"rarity\":\"Common\",\"shiny\":false,\"size\":\"normal\",\"zone\":\"Meadow\",\"foundAt\":0}}}' return #s.Value", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")

# 1. the golden nest with an egg (server) and what the client sees
nest = "none"
for _ in range(30):
    nest = S(ME + NEST + "if not m then return 'none' end local e=m:FindFirstChild('Egg') local p=m:GetPivot().Position local z='-' "
             "if e then local _,s=e:GetBoundingBox() z=string.format('%.1f',s.Y) end "
             "return string.format('%.1f,%.1f,%.1f|egg=%s|home=%.0f', p.X,p.Y,p.Z,z, hb and (hb.Position-p).Magnitude or -1)")
    if nest != "none": break
    time.sleep(1)
ok("1. the golden nest on the meadow, an egg in it (egg model height)", nest != "none" and "egg=-" not in nest, nest)
if nest == "none":
    stop(); write_result("Chase: no nest"); sys.exit(1)
NP = nest.split("|")[0]
sq = S(ME + NEST + f"local np=Vector3.new({NP}) local RS=game.ReplicatedStorage.Shared local Z=require(RS.Core.Zones) local CF=require(RS.Config) local W=CF.World "
       "local zone=Z.of(np.X,np.Y,np.Z,{flying=false,gliding=false,swimming=false,ownNest=false},W) "
       "local hp=hn:GetPivot().Position local d=math.deg(math.abs(math.atan2(math.sin(math.atan2(np.Z,np.X)-math.atan2(hp.Z,hp.X)),math.cos(math.atan2(np.Z,np.X)-math.atan2(hp.Z,hp.X))))) "
       "local function f(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end "
       "local sp=workspace:FindFirstChildWhichIsA('SpawnLocation',true) local bp=CF.Social.board.pos "
       "local hub=math.min(f(np,Vector3.new(W.keeper.x,0,W.keeper.z)), f(np,Vector3.new(W.stall.x,0,W.stall.z)), f(np,Vector3.new(bp[1],0,bp[3])), sp and f(np,sp.Position) or 999) "
       "local e=Vector3.new(hp.X,0,hp.Z).Unit*60 local a0=Vector3.new(np.X,0,np.Z) local seg=e-a0 local t=math.clamp(-a0:Dot(seg)/seg:Dot(seg),0,1) local route=(a0+seg*t).Magnitude "
       "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude pr.FilterDescendantsInstances={ch, workspace.GlowEggs, workspace:FindFirstChild('Gloom')} "
       "local lo,hi=1e9,-1e9 for k=0,7 do local a=k/8*math.pi*2 local h=workspace:Raycast(np+Vector3.new(math.cos(a)*6,30,math.sin(a)*6),Vector3.new(0,-80,0),pr) "
       "if h then lo=math.min(lo,h.Position.Y) hi=math.max(hi,h.Position.Y) end end "
       "return string.format('zone %s, from own plot %.0f deg, to Old Ash/stall/board/spawn %.0f, path home past Old Ash %.0f, drop %.2f, to the plot entrance %.0f', zone, d, hub, route, hi-lo, (e-a0).Magnitude)")
import re as _re0
mq = _re0.search(r"zone (\w+), from own plot (\d+) deg, to Old Ash/stall/board/spawn (\d+), path home past Old Ash (\d+), drop ([\d.]+)", sq)
ok("1a. the square edge to the side of the plot (85-140 deg), Old Ash/stall/board/spawn >= 20, path home past Old Ash >= 20, flat",
   bool(mq) and mq.group(1) == "plaza" and 85 <= int(mq.group(2)) <= 140 and int(mq.group(3)) >= 20 and int(mq.group(4)) >= 20 and float(mq.group(5)) <= 1.5, sq)

# 2. walked up to 15 studs from the home side - the guard; where it is and is it visible in the camera
S(ME + NEST + GROUND + f"local np=Vector3.new({NP}) local d=Vector3.new(hb.Position.X-np.X,0,hb.Position.Z-np.Z).Unit*15 "
  "local q=np+d ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gy(q.X,q.Z)+3,q.Z), Vector3.new(np.X,gy(q.X,q.Z)+3,np.Z))) return 'tp'")
time.sleep(4)
GL = ("local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
      "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('GlowEggs')} "
      "local h=workspace:Raycast(p+Vector3.new(0,40,0),Vector3.new(0,-100,0),pr) return h and h.Position.Y or 0 end ")
gs = S(ME + GROUND + GL + "local o={} for _,m in game:GetService('CollectionService'):GetTagged('Gloom') do if m:GetAttribute('OwnerId')==me.UserId then "
       "local p=m:GetPivot().Position table.insert(o, string.format('%s/%s d=%.0f above ground %.1f', tostring(m:GetAttribute('Arena')), tostring(m:GetAttribute('Kind')), "
       "(p-r.Position).Magnitude, p.Y-gl(p))) end end return #o..': '..table.concat(o,'; ')")
import re as _re
hs = [float(x) for x in _re.findall(r"above ground (-?[\d.]+)", gs)]
ok("2. the guard at the nest 3-9 studs above ground (not in the grass and not in the sky)", "glow/" in gs and hs and all(3 <= h <= 9 for h in hs), gs)
mat = S(ME + f"local np=Vector3.new({NP}) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Include pr.FilterDescendantsInstances={{workspace.Terrain}} "
        "local h=workspace:Raycast(np+Vector3.new(0,20,0),Vector3.new(0,-60,0),pr) return h and h.Material.Name or 'none'")
P("under the nest (terrain):", mat)
# frame: the camera is computed in advance - from the home side (where the player comes from), 18 studs from the nest, 9 up; camera -> egg ray unobstructed,
# otherwise turn by 30 degrees; Scriptable camera lookAt the egg, one frame, then Custom
cv = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local np=Vector3.new({NP}) "
       "local g=workspace:FindFirstChild('GlowEggs') g=g and g:FindFirstChildWhichIsA('Model') local e=g and g:FindFirstChild('Egg') "
       "local tgt=(e and e:GetPivot().Position) or np+Vector3.new(0,2,0) local base=Vector3.new(r.Position.X-np.X,0,r.Position.Z-np.Z) "
       "base=if base.Magnitude>0.1 then base.Unit else Vector3.xAxis local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
       "pr.FilterDescendantsInstances={me.Character, g, workspace:FindFirstChild('Gloom')} local pos,ang=nil,0 "
       "for k=0,11 do local a=math.rad(35+k*30) local d=CFrame.Angles(0,a,0):VectorToWorldSpace(base) local cp=np+d*18+Vector3.new(0,9,0) "
       "if not workspace:Raycast(cp,tgt-cp,pr) then pos,ang=cp,k*30 break end end "
       "if not pos then return 'no clear view' end cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(pos,tgt) task.wait(0.3) "
       "local o={} local n=0 for _,m in game:GetService('CollectionService'):GetTagged('Gloom') do if m:GetAttribute('OwnerId')==me.UserId then "
       "local _,on=cam:WorldToViewportPoint(m:GetPivot().Position) if on then n+=1 end end end "
       "local _,eon=cam:WorldToViewportPoint(tgt) return n..' guards in frame | egg in frame='..tostring(eon)..' | turn '..ang")
ok("2b. a frame with a clear view: the egg and the guard in frame", cv[:1] not in ("0", "n") and "egg in frame=true" in cv, cv)
time.sleep(1.2)
desk("nest_guards")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")

# 3. remove the guard (as by a victory) -> the egg is open
P("clear:", ld("combat clear")[:80]); time.sleep(3)
g = S(ME + NEST + "return tostring(m and m:GetAttribute('Unlocked'))")
ok("3. the guard removed - the egg is open (Unlocked)", g == "true", g)

# 4. took the egg, stands still -> chase, caught, the egg back to the nest
ck = S(ME + f"local np=Vector3.new({NP}) ch:PivotTo(CFrame.new(np+Vector3.new(0,4,3))) "
       "local t=0 while t<3 do local m=game:GetService('CollectionService'):GetTagged('GloomChase')[1] if m then "
       "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
       "return string.format('chase after %.1f s d=%.1f alert=%s carry=%s', t, (m:GetPivot().Position-r.Position).Magnitude, tostring(m:FindFirstChild('Alert',true)~=nil), tostring(d.eggs.carry and d.eggs.carry.glow)) end "
       "task.wait(0.1) t+=0.1 end return 'none'")
ok("4. took: egg in the hands, the chase Gloom rose from the nest with '!'", ck.startswith("chase") and "alert=true" in ck and "carry=true" in ck, ck)
sh_ = S(LD + "local d=game:GetService('HttpService'):JSONDecode(ld('dump')) local n=0 local el='' for _,x in d.eggs.shelf or {} do n+=1 el=el..tostring(x.element)..' ' end return n..' '..el")
ok("4a. the ordinary egg from the hands went to the home shelf (moss)", "moss" in sh_, sh_)
ui = C("local pg=game.Players.LocalPlayer.PlayerGui task.wait(0.3) local function en(n) local g=pg:FindFirstChild(n) return g and g.Enabled end "
       "local ha=pg:FindFirstChild('HintArrow') "
       "return string.format('Quests=%s StepBanner=%s HintArrow=%s WorldTimers=%s', tostring(en('Quests')), tostring(en('StepBanner')), tostring(ha and ha.Enabled), tostring(en('WorldTimers')))")
ok("4b. the chase screen - one task: Keeper lines/cards hidden, the step and the arrow home visible",
   "Quests=false" in ui and "StepBanner=true" in ui and "HintArrow=false" not in ui, ui)
# side frame: the camera is computed in advance - midway between the player and the Gloom, 24 studs to the side of the line, 10 up, unobstructed ray
fr = C("local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart "
       "local m=game:GetService('CollectionService'):GetTagged('GloomChase')[1] if not m then return 'no Gloom' end "
       "local mp=m:GetPivot().Position local mid=(mp+r.Position)/2 local line=Vector3.new(mp.X-r.Position.X,0,mp.Z-r.Position.Z) "
       "line=if line.Magnitude>0.1 then line.Unit else Vector3.xAxis local side=Vector3.new(-line.Z,0,line.X) "
       "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude pr.FilterDescendantsInstances={me.Character, m} local pos "
       "for _,sgn in {1,-1} do local cp=mid+side*sgn*24+Vector3.new(0,10,0) if not workspace:Raycast(cp,mid-cp,pr) then pos=cp break end end "
       "if not pos then return 'no clear view' end cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(pos,mid) return 'ok'")
time.sleep(0.4)
desk("chase_side")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
P("chase frame:", fr)
mus = C("local me=game.Players.LocalPlayer return 'Fight='..tostring(me:GetAttribute('Fight'))")
P("music:", mus)
time.sleep(3)
prof2 = S(LD + "local d=game:GetService('HttpService'):JSONDecode(ld('dump')) return tostring(d.eggs.carry and d.eggs.carry.glow)..' taken='..tostring(d.glowEgg and d.glowEgg.taken)")
ok("5. stood still - caught: no egg in the hands, not taken", prof2.startswith("nil") and "taken=0" in prof2, prof2)
time.sleep(2.5)
back = S(ME + NEST + "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
         "return tostring(m and m:FindFirstChild('Egg')~=nil)..' empty='..tostring(m and m:GetAttribute('Empty'))..' carry='..tostring(d.eggs.carry and d.eggs.carry.glow)")
ok("6. the egg returned to the nest and is not given by itself to someone standing nearby", back.startswith("true") and "carry=nil" in back, back)

# 7. walked away, came back, took it and runs home at 16 studs/s on the ground (the server moves the character in 0.1 s steps) - not caught, the stand at home
S(ME + f"local np=Vector3.new({NP}) ch:PivotTo(CFrame.new(np+Vector3.new(22,4,0))) return 'away'")
time.sleep(1.6)
run_res = S(ME + NEST + GROUND + f"local np=Vector3.new({NP}) ch:PivotTo(CFrame.new(np+Vector3.new(0,4,3))) "
            "local cs=game:GetService('CollectionService') local minD,t,lost=1e9,0,'' "
            "local function carry() local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return d.eggs.carry and d.eggs.carry.glow end "
            "local w=0 while not carry() and w<2.5 do task.wait(0.1) w+=0.1 end "
            "if not carry() then return 'not taken' end "
            "local inside=function(p) local lp=hb.CFrame:PointToObjectSpace(p) return math.abs(lp.X)<=hb.Size.X/2 and math.abs(lp.Z)<=hb.Size.Z/2 end "
            "while t<30 do local p=r.Position local to=Vector3.new(hb.Position.X-p.X,0,hb.Position.Z-p.Z) if inside(p) then break end "
            "local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gy(q.X,q.Z)+3,q.Z), Vector3.new(hb.Position.X,gy(q.X,q.Z)+3,hb.Position.Z))) "
            "local c=cs:GetTagged('GloomChase')[1] if c then minD=math.min(minD,(Vector3.new(c:GetPivot().Position.X,0,c:GetPivot().Position.Z)-Vector3.new(q.X,0,q.Z)).Magnitude) end "
            "if math.floor(t*10)%10==0 and not carry() then lost='caught at '..string.format('%.1f',t)..' s' break end task.wait(0.1) t+=0.1 end "
            "task.wait(2.5) local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
            "return string.format('run %.1f s, closest Gloom %.1f studs, %s readyAt=%s', t, minD, lost, tostring(d.glowEgg and d.glowEgg.readyAt))")
ok("7. ran home - not caught, at home the egg is on the stand (readyAt)", "caught at" not in run_res and "readyAt=0" not in run_res and "readyAt=nil" not in run_res, run_res)
hint = C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text~='' then table.insert(o,d.Text) end end return table.concat(o,' | ')")
P("screen after home:", hint[:400])
desk("home")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Combat]" in l or "[Glow]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("8. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
write_result("Chase for the glowing egg: the path in Play")
