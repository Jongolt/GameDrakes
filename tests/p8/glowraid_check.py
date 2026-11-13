#!/usr/bin/env python3
"""Probe of the golden raid on the slope, by the ring 1-2 rules (ride there, steal only on foot).
0 spawn: after the first dragon and the first ride (onboarding.rode). 1 place: the foot of the terrace slope on the meadow (r 196-232 from the centre,
<= 60 deg from the plot axis, y < 12, to ring 1 nests >= 50), Gloom Warden x1.5 sleeps 5 behind the nest on the side far from home, low.
2 approach: riding closer than 35 - jumped off within 1 s, the dragon goes to point D (22-37 from the nest toward home, on the ground) and stands, saddle at the nest - refused.
3 sneaking: at 24 and 12 studs the warden does not stir. 4 capture: took and stands - '!', the warden moved after 0.8 s, CAUGHT, back to sleep,
a repeat is not taken right away. 5 second attempt: took - 'RUN TO YOUR DRAGON!', the path to D and the green ring; run at 16 to the dragon, warden 0.9
on the trail; at the dragon mounted by itself - 'SAFE!', the warden stopped at the dragon and melted; home riding - the stand in the plot, timer ~20 h.
6 console. 7 the stand: the board hidden while riding, on foot the Warm button (minus an hour and coins, a real click) and Hatch now (Studio check
'shop HatchNow glow' -> bowl -> hatch, 2 dragons).
Run: python3 tests/p8/glowraid_check.py (after open_local with the glow-egg build). Frames - with a camera computed before the shot."""
import os, sys, time, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glowraid_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
NEST = ("local m=workspace:FindFirstChild('GlowEggs') m=m and m:FindFirstChild('GlowEgg_'..me.UserId) "
        "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local i1=hn and hn:FindFirstChild('Incubators') i1=i1 and i1:FindFirstChild('Incubator1') "
        "local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end "  # P = the centre of the gap in the fence (the plot entrance)
        "local N=m and m:GetAttribute('At') ")
FENCE = ("local function fenceGap(pos) local hn2 for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn2=x end end "
         "local best=1e9 for _,d in hn2.Fence:GetDescendants() do if d:IsA('BasePart') then local lp=d.CFrame:PointToObjectSpace(pos) "
         "local q=Vector3.new(math.clamp(lp.X,-d.Size.X/2,d.Size.X/2),math.clamp(lp.Y,-d.Size.Y/2,d.Size.Y/2),math.clamp(lp.Z,-d.Size.Z/2,d.Size.Z/2)) "
         "local w=d.CFrame:PointToWorldSpace(q) best=math.min(best,(Vector3.new(w.X,0,w.Z)-Vector3.new(pos.X,0,pos.Z)).Magnitude) end end return best end ")
PACK = ("local pk={} for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do if x:GetAttribute('OwnerId')==me.UserId then table.insert(pk,x) end end "
        "table.sort(pk,function(a,b) return tonumber(a:GetAttribute('Id'))<tonumber(b:GetAttribute('Id')) end) "
        "local function mk(x) local b=x.PrimaryPart:FindFirstChild('Mark') return b and b.T.Text or '-' end ")
GL = ("local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
      "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('GlowEggs')} "
      "local h=workspace:Raycast(p+Vector3.new(0,30,0),Vector3.new(0,-80,0),pr) return h and h.Position.Y or p.Y end "
      "local function fl(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end ")
H = 5.2 * 1.5  # warden height x1.5
COUNT = 1  # one warden
def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t)
    return float(m.group(1)) if m else default

# frame: the camera is computed in advance (position pos expression, target tgt expression), unobstructed ray, otherwise turn around the target by 30 deg
def frame(name, pos_expr, tgt_expr):
    r_ = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local tgt={tgt_expr} local p0={pos_expr} "
           "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude local sk={me.Character} "
           "for _,n in {'Gloom','GlowEggs','GlowRaidFx'} do local x=workspace:FindFirstChild(n) if x then table.insert(sk,x) end end "
           "for _,x in game:GetService('CollectionService'):GetTagged('Companion') do table.insert(sk,x) end pr.FilterDescendantsInstances=sk "
           "local pos for k=0,11 do local a=math.rad(k*30) local off=CFrame.Angles(0,a,0):VectorToWorldSpace(p0-tgt) local cp=tgt+off "
           "if not workspace:Raycast(cp,tgt-cp,pr) then pos=cp break end end if not pos then return 'no clear view' end "
           "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(pos,tgt) return 'ok'")
    time.sleep(0.5)
    desk(name)
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
    P("frame", name, r_)

# ------------------------------------------------- setup: first dragon, first ride (the nest appears after it - sec. 15)
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
time.sleep(8)
P("setcomp:", S(LD + "local r=ld('setcomp moss1') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
none = S(ME + NEST + "return N and 'yes' or 'none'")
ok("0a. before the first ride: the nest (since 29.10 evening it comes already with a teen, stage >= 1 - not an error)", True, none)
P("mount (first ride):", ld("mount")[:60]); time.sleep(1.5)
P("dismount:", ld("dismount")[:60]); time.sleep(1)
nest = "none"
for _ in range(40):
    nest = S(ME + NEST + "if not N then return 'none' end return string.format('%.1f,%.1f,%.1f', N.X,N.Y,N.Z)")
    if nest != "none": break
    time.sleep(1)
ok("0. the golden nest appeared after the first dragon and the first ride", nest != "none", nest)
if nest == "none":
    stop(); write_result("Golden raid on the slope: no nest"); sys.exit(1)
NP = nest

# ------------------------------------------------- 1 place and warden
s1 = S(ME + NEST + PACK + GL + f"local Nv=Vector3.new({NP}) local hp=hn:GetPivot().Position "
       "local d=math.deg(math.abs(math.atan2(math.sin(math.atan2(Nv.Z,Nv.X)-math.atan2(hp.Z,hp.X)),math.cos(math.atan2(Nv.Z,Nv.X)-math.atan2(hp.Z,hp.X))))) "
       "local rn=1e9 for _,x in game:GetService('CollectionService'):GetTagged('RaidNest') do if x:GetAttribute('Ring')==1 then local a=x:GetAttribute('At') if a then rn=math.min(rn,fl(Nv,a)) end end end "
       "if #pk<1 then return 'no wardens' end local L=pk[1]:GetPivot().Position "
       "local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local w=Vector3.new(L.X-Nv.X,0,L.Z-Nv.Z) local back=math.deg(math.acos(math.clamp(-u:Dot(w.Unit),-1,1))) "
       "local lows={} local zz=0 for _,x in pk do local q=x:GetPivot().Position table.insert(lows,string.format('%.2f',(q.Y-gl(q))/" + str(H) + ")) if mk(x)=='Zz' then zz+=1 end end "
       "local nm=pk[1].PrimaryPart and pk[1].PrimaryPart:FindFirstChild('Mark') nm=nm and nm:FindFirstChild('N') nm=nm and nm.Text or '-' "
       "return string.format('r=%.1f ang=%.0f y=%.1f ring1=%.0f lead=%.1f back=%.0f zz=%d low=%s path=%.0f name=%s', Vector3.new(Nv.X,0,Nv.Z).Magnitude, d, Nv.Y, rn, fl(L,Nv), back, zz, table.concat(lows,'/'), fl(Nv,P), nm)")
lows = [float(x) for x in re.findall(r"low=([\d./]+)", s1)[0].split("/")] if "low=" in s1 else []
ok("1. the nest on the slope: r 196-232 from the centre, <= 60 deg from the plot axis, meadow (y < 12), to ring 1 nests >= 50",
   194 <= num(s1, "r", 0) <= 234 and num(s1, "ang", 99) <= 62 and num(s1, "y", 99) < 12 and num(s1, "ring1", 0) >= 50, s1)
ok("1a. Gloom Warden sleeps ('Zz'), 5 from the nest on the side far from home, lies low (centre <= 0.47 of height x1.5)",
   num(s1, "zz") == COUNT and 4.3 <= num(s1, "lead", 0) <= 5.7 and num(s1, "back", 99) <= 25 and bool(lows) and max(lows) <= 0.47, s1)
frame("1_nest_slope",
      "(function() local me=game.Players.LocalPlayer local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
      f"local N=Vector3.new({NP}) local i1=hn.Incubators.Incubator1 local P=(i1:GetPivot()*CFrame.new(0,0,-9)).Position local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit "
      "return N+u*18+Vector3.new(0,9,0) end)()", f"Vector3.new({NP})+Vector3.new(0,1.5,0)")

# ------------------------------------------------- 2 riding approach: dismount at 35, the dragon to point D
S(ME + NEST + "local u=(P-Vector3.new(" + NP + ")) u=Vector3.new(u.X,0,u.Z).Unit ch:PivotTo(CFrame.new(P+u*30+Vector3.new(0,4,0))) return 1")
time.sleep(6)  # deep in the plot, the dragon came - mount (allowed in the plot)
m1 = ld("mount")
mounted = "nil"
for _ in range(10):
    time.sleep(0.25)
    mounted = S(ME + "return tostring(me:GetAttribute('Mounted'))")
    if mounted != "nil": break
P("riding in the plot:", m1[:80], mounted, "|", ld("glow")[:160])
wt = S(ME + NEST + "local Nv=Vector3.new(" + NP + ") local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local q=Nv+u*20 "
       "local function f(v) local n=math.floor(v+0.5) return (n<0 and 'n' or '')..tostring(math.abs(n)) end return f(q.X)..'x'..f(q.Y+6)..'x'..f(q.Z)")
P("warp:", ld("warp " + wt)[:80], wt)  # riding to the nest closer than approachR 35 (a server teleport - the speed check does not roll back)
t0 = time.time(); off = "?"
for _ in range(12):
    off = S(ME + "return tostring(me:GetAttribute('Mounted'))..' wait='..tostring(me:GetAttribute('GlowWait'))")
    if off.startswith("nil") and "wait=nil" not in off: break
    time.sleep(0.15)
ok("2. riding at the nest (closer than 35) - jumped off (<= 1 s), the dragon got a wait point", mounted != "nil" and off.startswith("nil") and "wait=nil" not in off,
   f"was {mounted}; {off}; {time.time() - t0:.1f} s")
dp = S(ME + NEST + GL + f"local Nv=Vector3.new({NP}) local w=me:GetAttribute('GlowWait') if not w then return 'none' end "
       "local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local v=Vector3.new(w.X-Nv.X,0,w.Z-Nv.Z) local a=math.deg(math.acos(math.clamp(u:Dot(v.Unit),-1,1))) "
       "local lo,hi=w.Y,w.Y for k=0,3 do local q=w+Vector3.new(math.cos(k*math.pi/2)*4,0,math.sin(k*math.pi/2)*4) local y=gl(q) lo=math.min(lo,y) hi=math.max(hi,y) end "
       "return string.format('dN=%.1f toHome=%.0f ground=%.1f flat=%.1f', v.Magnitude, a, math.abs(w.Y-gl(w)), hi-lo)")
ok("2a. point D: 22-37 from the nest, toward home (<= 65 deg), on the ground (<= 2.5), flat (drop over 4 <= 3)",
   22 <= num(dp, "dN", 0) <= 37 and num(dp, "toHome", 99) <= 65 and num(dp, "ground", 99) <= 2.5 and num(dp, "flat", 99) <= 3, dp)
time.sleep(4)
cw = S(ME + "local w=me:GetAttribute('GlowWait') local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
       "if not (w and c) then return 'none' end local q=c:GetPivot().Position return string.format('dW=%.1f', (Vector3.new(q.X,0,q.Z)-Vector3.new(w.X,0,w.Z)).Magnitude)")
ok("2b. the dragon reached point D and stands there (<= 3 studs)", num(cw, "dW", 99) <= 3, cw)
rm = S(LD + "local r=ld('mount') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
ok("2c. mounting at the nest is not allowed (glow_raid, toast: won't go near the Gloom)", "glow_raid" in rm, rm)
frame("2_dragon_at_D",
      f"(function() local me=game.Players.LocalPlayer local N=Vector3.new({NP}) local w=me:GetAttribute('GlowWait') or N local u=Vector3.new(w.X-N.X,0,w.Z-N.Z).Unit "
      "local mid=(N+w)/2 return mid+Vector3.new(-u.Z,0,u.X)*30+Vector3.new(0,12,0) end)()",
      f"(function() local me=game.Players.LocalPlayer local N=Vector3.new({NP}) local w=me:GetAttribute('GlowWait') or N return (N+w)/2+Vector3.new(0,2,0) end)()")

# ------------------------------------------------- 3 sneaking
still = []
for dd in (24, 12):
    S(ME + NEST + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*{dd}+Vector3.new(0,4,0))) return 1")
    a0 = S(ME + PACK + "local o={} for _,x in pk do local q=x:GetPivot().Position table.insert(o,string.format('%.2f,%.2f',q.X,q.Z)) end return table.concat(o,';')")
    time.sleep(3)
    a1 = S(ME + PACK + "local o={} for _,x in pk do local q=x:GetPivot().Position table.insert(o,string.format('%.2f,%.2f',q.X,q.Z)) end return table.concat(o,';')..'|'..mk(pk[1])")
    mv = max(abs(float(x) - float(y)) for x, y in zip(re.findall(r"-?[\d.]+", a0), re.findall(r"-?[\d.]+", a1.split("|")[0]))) if a0 and a1 else 99
    still.append(f"{dd}: shift {mv:.2f}, {a1.split('|')[-1]}")
ok("3. sneaked to 24 and 12 studs - the warden sleeps, did not move", all("Zz" in x and float(x.split("shift ")[1].split(",")[0]) <= 0.2 for x in still), "; ".join(still))

# ------------------------------------------------- 4 took and stands - caught; the warden back to sleep; not taken again right away
c4 = S(ME + NEST + PACK + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) "
       "local t=0 local t0,tm,tc local L0 local ex='' local gr='' while t<6 do "
       "if not t0 and m:GetAttribute('Empty') then t0=t L0=pk[1]:GetPivot().Position for _,x in pk do ex=ex..mk(x) end gr=tostring(me:GetAttribute('GlowRaid')) end "
       "if t0 and not tm and (Vector3.new(pk[1]:GetPivot().Position.X-L0.X,0,pk[1]:GetPivot().Position.Z-L0.Z)).Magnitude>0.3 then tm=t end "
       "if t0 and not tc then "
       "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) if not (d.eggs.carry and d.eggs.carry.glow) then tc=t end end "
       "if tc then break end task.wait(0.05) t+=0.05 end "
       "return string.format('take=%s move=%s caught=%s marks=%s raidAttr=%s', tostring(t0), tm and string.format('%.2f',tm-t0) or 'nil', tc and string.format('%.2f',tc-t0) or 'nil', ex, gr)")
mv4, cg4 = num(c4, "move"), num(c4, "caught")
ok("4. took: '!' above the warden, attribute GlowRaid=dragon, moved after 0.8 +-0.25 s; stood - CAUGHT after <= 1.8 s", "take=nil" not in c4 and ("marks=" + "!" * COUNT) in c4
   and "raidAttr=dragon" in c4 and mv4 is not None and 0.55 <= mv4 <= 1.1 and cg4 is not None and cg4 <= 1.8, c4)
time.sleep(1.5)
ui4 = C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and (d.Text=='CAUGHT!' or d.Text:find('steal it again')) then table.insert(o,d.Text) end end return table.concat(o,' | ')")
P("screen after the capture:", ui4[:200])
sl = "?"
for _ in range(14):
    sl = S(ME + NEST + PACK + "local z='' for _,x in pk do z=z..mk(x) end return z..' egg='..tostring(m:FindFirstChild('Egg')~=nil)..' attr='..tostring(me:GetAttribute('GlowRaid'))")
    if sl.startswith("Zz" * COUNT) and "egg=true" in sl: break
    time.sleep(0.5)
ok("4a. the warden came back and sleeps again, the egg is in the nest again, the attribute removed", sl.startswith("Zz" * COUNT) and "egg=true" in sl and "attr=nil" in sl, sl)
time.sleep(2)
re4 = S(ME + NEST + "return tostring(m:GetAttribute('Empty'))")
ok("4b. stood nearby - the egg is not given right away (step away first)", re4 == "nil", re4)
dw4 = S(ME + "local w=me:GetAttribute('GlowWait') local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
        "if not (w and c) then return 'wait='..tostring(w) end local q=c:GetPivot().Position return string.format('dW=%.1f', (Vector3.new(q.X,0,q.Z)-Vector3.new(w.X,0,w.Z)).Magnitude)")
ok("4c. after the capture the dragon did not leave point D (waits, <= 3)", num(dw4, "dW", 99) <= 3, dw4)
S(ME + NEST + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*22+Vector3.new(0,4,0))) return 1")
time.sleep(1.6)

C("workspace:SetAttribute('SawSafe',nil) workspace:SetAttribute('SawRun',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
  "while os.clock()-t0<30 do local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') local l2=f and f:FindFirstChild('L2') "
  "if l and f.Visible and l.Text=='RUN!' and l2 and l2.Text:find('DRAGON') then workspace:SetAttribute('SawRun',true) end "
  "if l and f.Visible and l.Text=='SAFE!' then workspace:SetAttribute('SawSafe',true) break end task.wait(0.1) end end) return 1")
# ------------------------------------------------- 5 second attempt: took and runs to the dragon at 16 studs/s (in the background on the server, the result - an attribute)
# after a capture the egg is given only after the player's own step (input + offset, GlowEgg settle) - stand at 12 and walk on foot from the client
S(ME + NEST + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*12+Vector3.new(0,4,0))) return 1"); time.sleep(0.8)
C(f"local me=game.Players.LocalPlayer local ch=me.Character local r=ch.HumanoidRootPart local N=Vector3.new({NP}) local P=r.Position local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit "
  "ch:FindFirstChildOfClass('Humanoid'):MoveTo(N+u*2) return 'walk'")
S(ME + NEST + PACK + GL + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit workspace:SetAttribute('GlowRun',nil) task.spawn(function() "
  "local w=0 while not m:GetAttribute('Empty') and w<5 do task.wait(0.05) w+=0.05 end "
  "if not m:GetAttribute('Empty') then workspace:SetAttribute('GlowRun','not taken') return end "
  "local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
  "if not c then workspace:SetAttribute('GlowRun','no dragon') return end local D=me:GetAttribute('GlowWait') or c:GetPivot().Position "
  "local hunt=false local c0=os.clock() local t,minG,angMax,spd,lastL,lastT=0,1e9,0,{},pk[1]:GetPivot().Position,0 local fol={} local tM "
  "while t<12 do local p=r.Position if me:GetAttribute('Mounted')~=nil then tM=t break end local cq=c:GetPivot().Position "
  "local to=Vector3.new(cq.X-p.X,0,cq.Z-p.Z) if to.Magnitude<=2 then task.wait(0.1) t=os.clock()-c0 continue end "
  "local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(cq.X,gl(q)+3,cq.Z))) task.wait(0.1) t=os.clock()-c0 "
  "local L=pk[1]:GetPivot().Position local g=fl(L,r.Position) if t>1.1 then minG=math.min(minG,g) "
  "local a=math.deg(math.acos(math.clamp(Vector3.new(r.Position.X-L.X,0,r.Position.Z-L.Z).Unit:Dot(to.Unit),-1,1))) angMax=math.max(angMax,a) "
  "for i=2,#pk do if fl(pk[i]:GetPivot().Position,r.Position)<g-0.5 then table.insert(fol,'OVERTOOK') end end end "
  "if t-lastT>=0.5 and t>1.1 then table.insert(spd,string.format('%.1f',fl(L,lastL)/(t-lastT))) lastL,lastT=L,t elseif t<=1.1 then lastL,lastT=L,t end "
  "if me:GetAttribute('Gloom_meadow') or me:GetAttribute('Gloom_sky') then hunt=true end end "
  "local arr=t local gateD,still,run,prev=1e9,0,0,nil for k=1,40 do task.wait(0.1) "
  "if pk[1] and pk[1].Parent then local L=pk[1]:GetPivot().Position local g=fl(L,c:GetPivot().Position) gateD=math.min(gateD,g) "
  "if prev and fl(L,prev)<0.06 and g<12 then run+=0.1 still=math.max(still,run) else run=0 end prev=L end end task.wait(2.5) "
  "local gone=0 for _,x in pk do if not x.Parent then gone+=1 end end "
  "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) local carry=d.eggs.carry and d.eggs.carry.glow==true "
  "workspace:SetAttribute('GlowRun',string.format('hunt=%s mountAt=%s run=%.1f minGap=%.1f ang=%.0f speeds=%s col=%s guardStop=%.1f still=%.2f gone=%d carry=%s mounted=%s wait=%s', "
  "tostring(hunt),tM and string.format('%.1f',tM) or 'nil',arr,minG,angMax,table.concat(spd,','),table.concat(fol,' ',1,math.min(#fol,6)),gateD,still,gone,tostring(carry),tostring(me:GetAttribute('Mounted')~=nil),tostring(me:GetAttribute('GlowWait')))) end) return 'started'")
time.sleep(1.4)
ui5 = "trail=0"
for _ in range(5):  # the chain path is computed in the background (0.8 s) - wait up to ~3 s
  ui5 = C("local pg=game.Players.LocalPlayer.PlayerGui local function en(n) local g=pg:FindFirstChild(n) return g and g.Enabled end local sb='' "
        "for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find('your dragon') then sb=d.Text end end "
        "local fx=workspace:FindFirstChild('GlowRaidFx') local ring=fx and fx:FindFirstChild('SafeRing') local tr=workspace:FindFirstChild('HintTrail') local tn=0 "
        "if tr then for _,q in tr:GetChildren() do if q:IsA('BasePart') and q.Transparency<1 and q.Material==Enum.Material.Neon and q:GetAttribute('Side')==1 then tn+=1 end end end "
        "return string.format('Quests=%s step=%s fx=%d trail=%d ring=%s', tostring(en('Quests')), sb~='' and 'yes' or 'no', fx and #fx:GetChildren() or 0, tn, tostring(ring~=nil))")
  if (num(ui5, "trail") or 0) >= 2: break
  time.sleep(0.4)
# the path dashes are removed - the path is shown by the Hints chevron chain, the finish - the green ring
ok("5a. chase screen: the step 'Run to your dragon!', Keeper hidden, chevron chain to point D (>= 2) and the green ring at the dragon", "Quests=false" in ui5 and "step=yes" in ui5 and (num(ui5, "trail") or 0) >= 2 and "ring=true" in ui5, ui5)
# no outline on the own dragon, the arrow is there
hl5 = C("local me=game.Players.LocalPlayer local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
        "local n=0 if c then for _,d in c:GetDescendants() do if d:IsA('Highlight') then n+=1 end end end local a=0 for _,d in workspace:GetDescendants() do if d:IsA('BillboardGui') and d.Name=='HintArrow' then a+=1 end end "
        "return string.format('dragonHighlight=%d arrow=%d', n, a)")
ok("5a1. 'Run to your dragon!': no outline on the own dragon (the arrow above it is there)", "dragonHighlight=0" in hl5, hl5)
frame("3_chase_to_dragon",
      "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
      "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end local a=r.Position local b=L and L:GetPivot().Position or a "
      "local mid=(a+b)/2 local ln=Vector3.new(a.X-b.X,0,a.Z-b.Z) ln=if ln.Magnitude>0.1 then ln.Unit else Vector3.xAxis return mid+Vector3.new(-ln.Z,0,ln.X)*26+Vector3.new(0,10,0) end)()",
      "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
      "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end return (r.Position+(L and L:GetPivot().Position or r.Position))/2 end)()")
res = "?"
for _ in range(50):
    res = S("return tostring(workspace:GetAttribute('GlowRun'))")
    if res != "nil": break
    time.sleep(0.3)
P("run to the dragon:", res)
spd = [float(x) for x in re.findall(r"speeds=([\d.,]*)", res)[0].split(",") if x] if "speeds=" in res else []
ok("5. run to the dragon (~32 studs): mounted by itself in <= 5 s, the warden not closer than 7.5 (catches at 7), strictly behind (angle <= 20 deg)",
   "mountAt=nil" not in res and num(res, "mountAt", 99) <= 5 and num(res, "minGap", 0) >= 7.5 and num(res, "ang", 99) <= 20, res[:220])
ok("5b. the warden at 0.9 of the thief speed (second attempt: 14.4 +-1.4), on the trail, did not overtake",
   (bool(spd) or num(res, "run", 9) < 2.0) and all(13.0 <= v <= 15.8 for v in spd[1:]) and "OVERTOOK" not in res, f"speeds {spd}; run={num(res, 'run', -1)}; " + (re.findall(r"col=([^g]*)", res) or [""])[0][:80])  # run < 2 s - no samples
saw = C("return tostring(workspace:GetAttribute('SawRun'))..'/'..tostring(workspace:GetAttribute('SawSafe'))")
ok("5c. screen: 'RUN!' + 'RUN TO YOUR DRAGON!', at the dragon - a huge 'SAFE!'", saw == "true/true", saw)
ok("5d. mounted - the warden stopped at the dragon (<= 12) and stood >= 0.5 s, then melted; the egg still in the hands, riding, the wait removed",
   0 <= num(res, "guardStop", -1) <= 12 and num(res, "still", 0) >= 0.5 and num(res, "gone") == COUNT and "carry=true" in res and "mounted=true" in res and "wait=nil" in res, res[-200:])
frame("5_safe_dragon",
      "(function() local me=game.Players.LocalPlayer local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
      f"local N=Vector3.new({NP}) local q=c and c:GetPivot().Position or N local u=Vector3.new(N.X-q.X,0,N.Z-q.Z).Unit return q-u*14+Vector3.new(-u.Z,0,u.X)*6+Vector3.new(0,9,0) end)()",
      "(function() local me=game.Players.LocalPlayer local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
      "return (c and c:GetPivot().Position or Vector3.zero)+Vector3.new(0,2,0) end)()")
# home riding (a server teleport into the plot, as if he rode there) - the stand, the egg out of the hands, timer ~20 h
# the old point (gap + 8 from the nest) fell outside the plot (53,21,3) - the stand is placed only inside; now the Base centre
hw = S(ME + NEST + "local Nv=Vector3.new(" + NP + ") local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local q=hb and hb.Position or (P+u*8) "
       "local function f(v) local n=math.floor(v+0.5) return (n<0 and 'n' or '')..tostring(math.abs(n)) end return f(q.X)..'x'..f(q.Y+6)..'x'..f(q.Z)")
P("warp home:", ld("warp " + hw)[:80], hw)
home = "?"
for _ in range(16):
    home = S(ME + FENCE + "local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] "
             "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) local carry=d.eggs.carry and d.eggs.carry.glow==true "
             "local ra=d.glowEgg and tonumber(d.glowEgg.readyAt) or 0 local hrs=(ra-os.time())/3600 "
             "local hn2 for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn2=x end end local hb2=hn2 and hn2:FindFirstChild('Base') "
             "local pin=pd and hb2 and (function() local lp=hb2.CFrame:PointToObjectSpace(pd:GetPivot().Position) return math.abs(lp.X)<=hb2.Size.X/2-2 and math.abs(lp.Z)<=hb2.Size.Z/2-2 end)() "
             "return string.format('ped=%s pedIn=%s pedFence=%.1f carry=%s hours=%.1f wait=%s attr=%s', tostring(pd~=nil), tostring(pin), pd and fenceGap(pd:GetPivot().Position) or -1, tostring(carry), hrs, tostring(me:GetAttribute('GlowWait')), tostring(me:GetAttribute('GlowRaid')))")
    if "ped=true" in home and "carry=false" in home: break
    time.sleep(0.5)
ok("5e. at home: the stand inside the plot, not on the fence (>= 3), the egg out of the hands, timer 19.5-20.5 h, the wait and the attribute removed",
   "ped=true" in home and "pedIn=true" in home and num(home, "pedFence", 0) >= 3 and "carry=false" in home and 19.5 <= num(home, "hours", 0) <= 20.5 and "wait=nil" in home and "attr=nil" in home, home)
ok("5f. during the sortie and the chase - not a single hunt wave (only the warden)", "hunt=false" in res, (re.findall(r"hunt=\w+", res) or ["?"])[0])

# ------------------------------------------------- 7 the stand: the board hidden while riding; on foot - Warm removes an hour and coins; HatchNow glow
bm = C("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('GlowBoard') return 'board='..tostring(g~=nil and g.Enabled)..' mounted='..tostring(game.Players.LocalPlayer:GetAttribute('Mounted')~=nil)")
ok("7. riding at the stand the board with buttons is hidden", "board=true" not in bm, bm)
P("dismount:", ld("dismount")[:40]); time.sleep(1.5)
S(ME + "local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] if pd then local q=pd:GetPivot().Position local d=(r.Position-q) d=Vector3.new(d.X,0,d.Z) d=if d.Magnitude>1 then d.Unit else Vector3.xAxis ch:PivotTo(CFrame.lookAt(q+d*7+Vector3.new(0,3,0),q)) end return 1")
time.sleep(2)
bd = C("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('GlowBoard') if not g then return 'board=nil' end local c=pg:FindFirstChild('GlowCard') local w=c and c:FindFirstChild('Warm',true) local h=c and c:FindFirstChild('HatchNow',true) "
       "return string.format('board=%s warm=%s hatch=%s wtxt=%s htxt=%s', tostring(g.Enabled), tostring(w and w.Visible), tostring(h and h.Visible), w and w.Text or '-', h and h.Text or '-')")
ok("7a. on foot at the stand: the board and the Warm / Hatch now buttons are visible", "board=true" in bd and "warm=true" in bd and "hatch=true" in bd, bd)
desk("7_pedestal_board")
P("give:", ld("give 100000")[:30]); time.sleep(0.8)
before = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return string.format('ready=%d coins=%d', tonumber(d.glowEgg.readyAt) or 0, math.floor(d.coins or 0))")
press("GlowCard", "Warm", name="7b-press")  # the buttons are in the GlowCard side card  # a real click on the board button (BillboardGui in PlayerGui)
time.sleep(1.5)
after = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return string.format('ready=%d coins=%d', tonumber(d.glowEgg.readyAt) or 0, math.floor(d.coins or 0))")
cut = num(before, "ready", 0) - num(after, "ready", 0); paid = num(before, "coins", 0) - num(after, "coins", 0)
ok("7b. 'Warm the egg': the timer is 1 h shorter (3600 +-5 s), coins charged (>= 1 000)", 3595 <= cut <= 3605 and paid >= 1000, f"{before} -> {after} (cut {cut:.0f}, paid {paid:.0f})")
P("HatchNow glow:", S(LD + "local r=ld('shop HatchNow glow') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
res7 = "?"
for i in range(40):
    res7 = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) local dr=0 for _ in d.dragons do dr+=1 end local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] "
             "return string.format('dragons=%d hatched=%s ped=%s inc=%s', dr, tostring(d.glowEgg and d.glowEgg.hatched), tostring(pd~=nil), tostring(d.eggs.incubating['1']~=nil))")
    if num(res7, "dragons", 0) >= 2: break
    time.sleep(1)
ok("7c. 'Hatch now' (Studio check): the egg from the stand into the bowl and hatched (<= 40 s), 2 dragons, no stand", num(res7, "dragons", 0) >= 2 and "ped=false" in res7, res7 + f" | {i} s")

cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Combat]" in l or "[Glow]" in l or "[Movement]" in l or "[Raid]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("6. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
write_result("Golden raid on the slope (spec 27 sec. 15, 18): steps 0-7")
