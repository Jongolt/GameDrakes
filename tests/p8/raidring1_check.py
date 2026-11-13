#!/usr/bin/env python3
"""A quick probe of ring 1 (step 5) and the ring 0 path (4-fx); the character moves step by step (a teleport in one jump is rolled back by the anticheat).
1 nests: ring 0 - 3 on the square edge (r 47.5 +-2, angles 30/150/270 +-10), ring 1 - 10 (meadow), ring 2 - 14 (cliffs + springs);
  each with an egg, each with a sleeping warden 'Zz'; no free EggSpawner eggs at the meadow/cliff/spring points. 2 after the first hatch
  the RAID step ('Sneak to the Gloom nest'). 3 took a ring 0 egg and stands: '!', RUN!, the path and the SAFE line, CAUGHT <= 1.8 s, the egg back,
  the warden sleeps, not taken nearby (rearm). 4 second attempt: the run to the gap at 16 studs/s - home <= 4.5 s, the warden at 0.8 speed behind, stopped at the line
  and went back to sleep, the egg in the bowl (Common 15 s), 'SAFE!', raid.home = 1, the egg in the nest again after <= 40 s. 5 ring 1 riding: at the nest
  jumped off, the dragon waits at 35 (D), took - RUN TO YOUR DRAGON, ran there - mounted by itself, the warden stopped >= 6 from the dragon, 'SAFE!', at home the egg into the bowl/onto
  the shelf, raid.home = 2. 6 clean console. Frames - with a camera computed before the shot.
Run: python3 tests/p8/raidloop_check.py (after open_local with the glow-egg build)."""
import os, sys, time, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("raidring1_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
HOME = ("local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local i1=hn and hn:FindFirstChild('Incubators') i1=i1 and i1:FindFirstChild('Incubator1') "
        "local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end "
        "local function inside(p) local lp=hb.CFrame:PointToObjectSpace(p) return math.abs(lp.X)<=hb.Size.X/2 and math.abs(lp.Z)<=hb.Size.Z/2 end ")
NESTS = ("local CS=game:GetService('CollectionService') local function fl(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end "
         "local function nests(ring) local o={} for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==ring then table.insert(o,m) end end return o end "
         "local function nearest(ring,pos,egg) local b,bd for _,m in nests(ring) do if not egg or m:GetAttribute('HasEgg')==true then local d=fl(m:GetAttribute('At'),pos) if not bd or d<bd then b,bd=m,d end end end return b,bd end "
         "local function guardOf(m) for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='raid:'..tostring(m:GetAttribute('NestId')) then return g end end return nil end "
         "local function mk(g) local b=g and g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') return b and b.T.Text or '-' end "
         "local function dump() return game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) end ")
GL = ("local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
      "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('RaidNests'), workspace:FindFirstChild('GlowRaidFx')} "
      "local h=workspace:Raycast(p+Vector3.new(0,30,0),Vector3.new(0,-80,0),pr) return h and h.Position.Y or p.Y end ")
def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t)
    return float(m.group(1)) if m else default

def frame(name, pos_expr, tgt_expr):
    r_ = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local tgt={tgt_expr} local p0={pos_expr} "
           "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude local sk={me.Character} "
           "for _,n in {'Gloom','RaidNests','GlowRaidFx'} do local x=workspace:FindFirstChild(n) if x then table.insert(sk,x) end end "
           "for _,x in game:GetService('CollectionService'):GetTagged('Companion') do table.insert(sk,x) end pr.FilterDescendantsInstances=sk "
           "local pos for k=0,11 do local a=math.rad(k*30) local off=CFrame.Angles(0,a,0):VectorToWorldSpace(p0-tgt) local cp=tgt+off "
           "if not workspace:Raycast(cp,tgt-cp,pr) then pos=cp break end end if not pos then return 'no clear view' end "
           "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(pos,tgt) return 'ok'")
    time.sleep(0.5)
    desk(name)
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
    P("frame", name, r_)

def banner_watch(text, attr, secs=30):
    C(f"workspace:SetAttribute('{attr}',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
      f"while os.clock()-t0<{secs} do local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') "
      f"if l and f.Visible and l.Text=='{text}' then workspace:SetAttribute('{attr}',true) break end task.wait(0.05) end end) return 1")

def labels(sub):
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find('" + sub + "') then table.insert(o,d.Text) end end return table.concat(o,' | ')")


# ------------------------------------------------- setup: the first egg hatched, there was a ride (ring 1 open)
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)
S(LD + "return ld('give 1000000')"); S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2); S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:60]); time.sleep(8)
S(ME + HOME + "local pile=hn and hn:FindFirstChild('CoinPile') if pile then ch:PivotTo(CFrame.new(pile.Position+Vector3.new(0,3,0))) end return 1"); time.sleep(2)

# ------------------------------------------------- 4-fx: the ring 0 path through the gap (took at the near nest, read on the client, the run home step by step)
n0 = S(ME + HOME + NESTS + "local m,d=nearest(0,P,true) if not m then return 'none' end local a=m:GetAttribute('At') return string.format('%.2f,%.2f,%.2f|d=%.1f', a.X,a.Y,a.Z, d)")
NP = n0.split("|")[0]
S(ME + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit workspace:SetAttribute('Run0',nil) task.spawn(function() "
  "local p=r.Position for k=1,200 do local to=Vector3.new(N.X+u.X*3-p.X,0,N.Z+u.Z*3-p.Z) if to.Magnitude<1 then break end local q=p+to.Unit*math.min(1.6,to.Magnitude) "
  "ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(N.X,gl(q)+3,N.Z))) p=r.Position task.wait(0.1) end "
  "local w=0 while not (dump().eggs.carry or {}).raid and w<3 do task.wait(0.05) w+=0.05 end workspace:SetAttribute('Run0',(dump().eggs.carry or {}).raid and 'took' or 'not taken') "
  "task.wait(0.9) local c0=os.clock() local T=P+u*8 local t=0 while t<12 do local pp=r.Position if inside(pp) then break end local to=Vector3.new(T.X-pp.X,0,T.Z-pp.Z) "
  "local q=pp+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(P.X,gl(q)+3,P.Z))) task.wait(0.1) t=os.clock()-c0 end "
  "task.wait(1.5) local d=dump() workspace:SetAttribute('Run0',string.format('run=%.1f home=%d carry=%s', t, tonumber(d.raid and d.raid.home) or -1, tostring(d.eggs.carry~=nil))) end) return 'started'")
took = "?"
for _ in range(40):
    took = S("return tostring(workspace:GetAttribute('Run0'))")
    if took != "nil": break
    time.sleep(0.2)
time.sleep(0.5)
fx4 = C("local me=game.Players.LocalPlayer local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local fx=workspace:FindFirstChild('GlowRaidFx') if not fx then return 'fx=0' end local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Include op.FilterDescendantsInstances={hn.Fence} "
        "local hit,n=0,0 for _,q in fx:GetChildren() do if q:IsA('BasePart') and q.Name~='SafeLine' and q.Transparency<1 then n+=1 "
        "if #workspace:GetPartBoundsInRadius(q.Position+Vector3.new(0,1,0),1.2,op)>0 then hit+=1 end end end "
        "local sl=fx:FindFirstChild('SafeLine') return string.format('fx=%d onFence=%d safeLen=%.1f', n, hit, sl and sl.Size.Z or -1)")
ok("4-fx. the path home through the gap (client): >= 5 dashes, none on the fence, the SAFE line = gap width 12", took == "took" and num(fx4, "fx", 0) >= 5 and num(fx4, "onFence", 99) == 0 and 11 <= num(fx4, "safeLen", 0) <= 13, took + " " + fx4)
res0 = "?"
for _ in range(60):
    res0 = S("return tostring(workspace:GetAttribute('Run0'))")
    if res0.startswith("run="): break
    time.sleep(0.4)
ok("4. ring 0 step by step: home <= 4.5 s, the egg out of the hands, raid.home = 1", num(res0, "run", 99) <= 4.5 and num(res0, "home", 0) == 1 and "carry=false" in res0, res0)

# ------------------------------------------------- 5 ring 1 riding
S(LD + "return ld('time 9999999')"); time.sleep(3)
comp = S(ME + NESTS + "local d=dump() return tostring(d.companion)")
P("setcomp:", comp, S(LD + f"local r=ld('setcomp {comp}') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
h1 = S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
P("hatch 1:", h1[:60]); time.sleep(6)
m1 = S(LD + "local r=ld('mount') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
mounted = "nil"
for _ in range(12):
    time.sleep(0.25)
    mounted = S(ME + "return tostring(me:GetAttribute('Mounted'))")
    if mounted != "nil": break
P("riding:", m1[:60], mounted)
go1 = ld("raid go 1"); P("go 1:", go1[:80])
off = "?"
for _ in range(16):
    off = S(ME + "return tostring(me:GetAttribute('Mounted'))..' wait='..tostring(me:GetAttribute('GlowWait'))")
    if off.startswith("nil") and "wait=nil" not in off: break
    time.sleep(0.2)
ok("5. riding at a ring 1 nest - jumped off (<= 3 s), the dragon waits (GlowWait)", mounted != "nil" and off.startswith("nil") and "wait=nil" not in off, f"was {mounted}; {off}")
dw = S(ME + HOME + NESTS + "local w=me:GetAttribute('GlowWait') local m=nearest(1,r.Position,true) if not (w and m) then return 'none' end local a=m:GetAttribute('At') "
       "local toHome=Vector3.new(P.X-a.X,0,P.Z-a.Z).Unit local toW=Vector3.new(w.X-a.X,0,w.Z-a.Z) "
       "return string.format('dN=%.1f ang=%.0f', toW.Magnitude, math.deg(math.acos(math.clamp(toW.Unit:Dot(toHome),-1,1))))")
ok("5a. the wait point D at 35 +-3 from the nest toward home (angle <= 20)", 32 <= num(dw, "dN", 0) <= 38 and num(dw, "ang", 99) <= 20, dw)
time.sleep(4)
cw = S(ME + "local w=me:GetAttribute('GlowWait') local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
       "if not (w and c) then return 'none' end local q=c:GetPivot().Position return string.format('dW=%.1f', (Vector3.new(q.X,0,q.Z)-Vector3.new(w.X,0,w.Z)).Magnitude)")
ok("5b. the dragon reached D and stands (<= 5)", num(cw, "dW", 99) <= 5, cw)
rm = S(LD + "local r=ld('mount') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
ok("5c. at the nest without an egg in the hands mounting is not allowed (raid_foot)", "raid_foot" in rm, rm)
banner_watch("SAFE!", "SawSafe2")
S(ME + HOME + NESTS + GL + "local m=nearest(1,r.Position,true) local g=guardOf(m) local N=m:GetAttribute('At') local w=me:GetAttribute('GlowWait') or r.Position workspace:SetAttribute('RaidRun1',nil) task.spawn(function() "
  "local u=Vector3.new(w.X-N.X,0,w.Z-N.Z).Unit local p=r.Position for k=1,300 do local to=Vector3.new(N.X+u.X*3-p.X,0,N.Z+u.Z*3-p.Z) if to.Magnitude<1 then break end local q=p+to.Unit*math.min(1.6,to.Magnitude) "
  "ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(N.X,gl(q)+3,N.Z))) p=r.Position task.wait(0.1) end "
  "local k=0 while not (dump().eggs.carry or {}).raid and k<3 do task.wait(0.05) k+=0.05 end "
  "if not (dump().eggs.carry or {}).raid then workspace:SetAttribute('RaidRun1','not taken') return end "
  "local c for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then c=x end end "
  "task.wait(0.3) local c0=os.clock() local t,minG=0,1e9 local tm local dStart=fl(c:GetPivot().Position,r.Position) while t<10 do if me:GetAttribute('Mounted') then tm=t break end local pp=r.Position local cq=c:GetPivot().Position "
  "local to=Vector3.new(cq.X-pp.X,0,cq.Z-pp.Z) if to.Magnitude>2 then local q=pp+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(cq.X,gl(q)+3,cq.Z))) end "
  "task.wait(0.1) t=os.clock()-c0 if t>0.9 then minG=math.min(minG,fl(g:GetPivot().Position,r.Position)) end end "
  "local gstop=1e9 local still=0 local prev for k=1,30 do task.wait(0.1) local L=g:GetPivot().Position local cq=c:GetPivot().Position local d=fl(L,cq) if prev and fl(L,prev)<0.06 then still+=0.1 end prev=L gstop=math.min(gstop,d) end "
  "local slept=false for k=1,60 do task.wait(0.2) if mk(g)=='Zz' then slept=true break end end "
  "workspace:SetAttribute('RaidRun1',string.format('dStart=%.1f mounted=%s minGap=%.1f gstop=%.1f still=%.1f slept=%s wait=%s', dStart, tm and string.format('%.1f',tm) or 'nil', minG, gstop, still, tostring(slept), tostring(me:GetAttribute('GlowWait')))) end) return 'started'")
time.sleep(3.5)
run_lbl = labels("RUN TO YOUR DRAGON")
res1 = "?"
for _ in range(80):
    res1 = S("return tostring(workspace:GetAttribute('RaidRun1'))")
    if res1 != "nil": break
    time.sleep(0.4)
P("ring 1:", res1)
ok("5d. took a ring 1 egg (the dragon 30+ from the player): 'RUN TO YOUR DRAGON', ran there - mounted by itself in 1.5-5 s, the warden not closer than 5", bool(run_lbl) and num(res1, "dStart", 0) >= 28
   and num(res1, "mounted") is not None and 1.5 <= num(res1, "mounted", 99) <= 5 and num(res1, "minGap", 0) >= 5, res1[:200] + " | " + run_lbl[:60])
ok("5e. the warden stopped >= 6 from the dragon (stood >= 0.5 s), went back to its lair and sleeps; the wait removed", num(res1, "gstop", 0) >= 6 and num(res1, "still", 0) >= 0.5 and "slept=true" in res1 and "wait=nil" in res1, res1[-120:])
safe2 = C("return tostring(workspace:GetAttribute('SawSafe2'))")
ok("5f. at the dragon 'SAFE!' on the screen", safe2 == "true", safe2)
hm = ld("raid home"); time.sleep(3)
d5 = S(NESTS + "local d=dump() local inc=d.eggs.incubating['1'] return string.format('carry=%s inc=%s shelf=%d home=%d', tostring(d.eggs.carry~=nil), tostring(inc~=nil), d.eggs.shelf and #d.eggs.shelf or 0, tonumber(d.raid and d.raid.home) or -1)")
ok("5g. at home riding: the egg into the bowl or onto the shelf, raid.home = 2", "carry=false" in d5 and ("inc=true" in d5 or num(d5, "shelf", 0) >= 1) and num(d5, "home", 0) == 2, d5 + " | " + hm[:40])
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Raid]" in l or "[Combat]" in l or "[Glow]" in l or "[Movement]" in l or "[Incubation]" in l or "[Hints]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("6. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
write_result("Raid (spec 27, pack 1): ring 1 and the ring 0 path")
