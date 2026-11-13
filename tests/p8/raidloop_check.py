#!/usr/bin/env python3
"""Exact measurements of the first egg by a raid on the glow-egg test build.
0 clean profile, day: spawn in the own pen at the gap facing the square (HomeSpawn), the step 'Steal an egg from the sleeping Gloom -
  your first dragon!' from spawn. 1 nests: ring 0 - 3 on the square edge (r 47 +-4, wedges 30/150/270), an egg in each, the warden sleeps
  5 inward; no rings 1-2 (open off). 1b the newcomer is assigned the FARTHEST nest (FirstNest, >= 80 from the gap), the eggs of the others are
  hidden on the client. 2 the chevron chain and the arrow. 3 the near nest does not give its egg; the far one: took and stands - '!', the warden moved after
  1.2 s (first.wake), CAUGHT <= 1.8 s, RUN!, the egg back, sleeps, rearm. 4 second attempt: the run home ~100 studs at 16 studs/s - warden 0.75
  (12 +-1.8) strictly behind, gap >= 8, chevrons not on the fence, at the line it stopped and went back to sleep, 'SAFE!', the egg into the bowl and hatched by itself,
  raid.home = 1; the egg in the nest again <= 25 s. 5 with a dragon: the nests do not give or show eggs, the step does not call to them. 6 console.
Run: python3 tests/p8/raidloop_check.py (after open_local with the glow-egg build). Frames - with a camera computed before the shot.
History: the 29.10 morning version (newcomer table, rings 0-1, the near nest) - in git before 30.10."""
import os, sys, time, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("raidloop_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
def ldr(c):
    return S(LD + f"local r=ld('{c}') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
FL = "local function fl(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end "
HOME = ("local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end "
        "local function inside(p) if not hb then return false end local lp=hb.CFrame:PointToObjectSpace(p) return math.abs(lp.X)<=hb.Size.X/2 and math.abs(lp.Z)<=hb.Size.Z/2 end ")
NESTS = ("local CS=game:GetService('CollectionService') "
         "local function nests(ring) local o={} for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==ring then table.insert(o,m) end end return o end "
         "local function nestById(id) for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('NestId')==id then return m end end return nil end "
         "local function guardOf(m) for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='raid:'..tostring(m:GetAttribute('NestId')) then return g end end return nil end "
         "local function mk(g) local b=g and g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') return b and b.T and b.T.Text or '-' end "
         "local function dump() return game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) end ")
GL = ("local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
      "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('RaidNests'), workspace:FindFirstChild('GlowRaidFx'), workspace:FindFirstChild('HintTrail')} "
      "local h=workspace:Raycast(p+Vector3.new(0,30,0),Vector3.new(0,-80,0),pr) return h and h.Position.Y or p.Y end ")
def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t or "")
    return float(m.group(1)) if m else default

def frame(name, pos_expr, tgt_expr):
    r_ = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local tgt={tgt_expr} local p0={pos_expr} "
           "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude local sk={me.Character} "
           "for _,n in {'Gloom','RaidNests','GlowRaidFx','HintTrail'} do local x=workspace:FindFirstChild(n) if x then table.insert(sk,x) end end "
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
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find([[" + sub + "]],1,true) then table.insert(o,d.Text) end end return table.concat(o,' | ')")

def trail():
    return C("local me=game.Players.LocalPlayer local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
             "local f=workspace:FindFirstChild('HintTrail') if not f then return 'trail=0' end local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Include "
             "op.FilterDescendantsInstances={hn and hn:FindFirstChild('Fence') or workspace} local hit,n=0,0 "
             "for _,q in f:GetChildren() do if q:IsA('BasePart') and q.Transparency<1 and q.Material==Enum.Material.Neon and q:GetAttribute('Side')==1 then n+=1 "
             "if hn and #workspace:GetPartBoundsInRadius(q.Position+Vector3.new(0,1,0),1.2,op)>0 then hit+=1 end end end "
             "local arrow=workspace:FindFirstChild('HintArrow',true) or game.Players.LocalPlayer.PlayerGui:FindFirstChild('HintArrow',true) "
             "return string.format('trail=%d onFence=%d arrow=%s', n, hit, tostring(arrow~=nil))")

# ------------------------------------------------- 0 clean profile, day, spawn
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)  # Raid.start: points + 1.5 s, the Gloom models
P("raid:", ld("raid")[:300])
a = S(ME + FL + HOME + NESTS + "local hs=hn and hn:FindFirstChild('HomeSpawn') local p=r.Position local look=r.CFrame.LookVector local toP=Vector3.new(P.X-p.X,0,P.Z-p.Z) toP=toP.Magnitude>0.1 and toP.Unit or look "
      "local d=dump() local dr=0 for _ in d.dragons do dr+=1 end return string.format('inside=%s d=%.1f face=%.2f hs=%s dragons=%d', tostring(inside(p)), fl(p,P), look:Dot(toP), tostring(hs~=nil), dr)")
ok("0. clean profile (0 dragons), spawned in the own pen: 5-14 from the gap, facing the square (HomeSpawn)",
   num(a, "dragons", 9) == 0 and "inside=true" in a and 5 <= num(a, "d", 99) <= 14 and num(a, "face", -1) >= 0.6 and "hs=true" in a, a)
hint = ""
for _ in range(28):
    hint = labels("Steal an egg from the sleeping Gloom")
    if hint: break
    time.sleep(0.5)
ok("0a. from spawn the step 'Steal an egg from the sleeping Gloom - your first dragon!' (no table)", bool(hint), hint[:140])

# ------------------------------------------------- 1 nests and wardens
s1 = S(ME + FL + HOME + NESTS + "local c0,c1,c2=#nests(0),#nests(1),#nests(2) local eggs,zz,rs,angs,leads,inw=0,0,{},{},{},{} "
       "for _,m in nests(0) do if m:GetAttribute('HasEgg')==true then eggs+=1 end local g=guardOf(m) if g and mk(g)=='Zz' then zz+=1 end local a=m:GetAttribute('At') "
       "table.insert(rs,string.format('%.1f',Vector3.new(a.X,0,a.Z).Magnitude)) table.insert(angs,string.format('%.0f',math.deg(math.atan2(-a.Z,a.X))%360)) "
       "local gp=g and g:GetPivot().Position if gp then table.insert(leads,string.format('%.1f',fl(gp,a))) table.insert(inw,string.format('%.1f',Vector3.new(a.X,0,a.Z).Magnitude-Vector3.new(gp.X,0,gp.Z).Magnitude)) end end "
       "local free=0 for _,a in CS:GetTagged('EggPoint') do if a:FindFirstChild('Egg') and not a:GetAttribute('Secret') then free+=1 end end "
       "return string.format('c0=%d c1=%d c2=%d eggs=%d zz=%d r=%s ang=%s lead=%s inward=%s free=%d', c0,c1,c2,eggs,zz,table.concat(rs,'/'),table.concat(angs,'/'),table.concat(leads,'/'),table.concat(inw,'/'),free)")
rs = [float(x) for x in (re.findall(r"r=([\d./]+)", s1) or ["0"])[0].split("/") if x]
angs = [float(x) for x in (re.findall(r"ang=([\d./]+)", s1) or ["0"])[0].split("/") if x]
leads = [float(x) for x in (re.findall(r"lead=([\d./]+)", s1) or [""])[0].split("/") if x]
inw = [float(x) for x in (re.findall(r"inward=([\d./]+)", s1) or [""])[0].split("/") if x]
ok("1. ring 0 - 3 nests at r 47.5 +-4 in the wedges 30/150/270 (+-12), each with an egg and a sleeping warden 5 +-1.2 inward; no rings 1-2 (off)",
   num(s1, "c0") == 3 and num(s1, "c1") == 0 and num(s1, "c2") == 0 and num(s1, "eggs") == 3 and num(s1, "zz") == 3 and bool(rs) and all(43.5 <= v <= 51.5 for v in rs)
   and sorted(round(a / 60) % 6 for a in angs) == [0, 2, 4] and all(abs(((a - 30) + 30) % 60 - 30) <= 12 for a in angs) and len(leads) == 3 and all(3.8 <= v <= 6.2 for v in leads) and all(v > 2 for v in inw), s1)
P("free eggs at the points (rings 1-2 off - free eggs remain):", num(s1, "free", -1))
b = S(ME + FL + HOME + NESTS + "local fid=me:GetAttribute('FirstNest') local m=fid and nestById(fid) if not m then return 'first=nil' end local a=m:GetAttribute('At') "
      "local ds={} for _,x in nests(0) do table.insert(ds,string.format('%.0f',fl(x:GetAttribute('At'),P))) end "
      "return string.format('first=%s d=%.1f at=%.2f,%.2f,%.2f all=%s', tostring(fid), fl(a,P), a.X,a.Y,a.Z, table.concat(ds,'/'))")
dists = [float(x) for x in (re.findall(r"all=([\d./]+)", b) or [""])[0].split("/") if x]
ok("1b. the newcomer is assigned the farthest ring 0 nest (FirstNest), >= 80 from the gap", "first=nil" not in b and num(b, "d", 0) >= 80 and dists and abs(num(b, "d", 0) - max(dists)) < 1, b)
if "first=nil" in b:
    stop(); write_result("Newcomer first egg: FirstNest not assigned"); sys.exit(1)
NP = re.search(r"at=(-?[\d.]+,-?[\d.]+,-?[\d.]+)", b).group(1)
FID = re.search(r"first=(\S+)", b).group(1)
hid = C("local me=game.Players.LocalPlayer local CS=game:GetService('CollectionService') local fid=me:GetAttribute('FirstNest') local vis,hid,n={}, {}, 0 "
        "for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==0 and m:GetAttribute('HasEgg')==true then local e=m:FindFirstChild('Egg') or m:FindFirstChild('Egg',true) "
        "local t=1 if e then for _,d in e:GetDescendants() do if d:IsA('BasePart') then t=math.min(t,d.LocalTransparencyModifier) end end end "
        "n+=1 if m:GetAttribute('NestId')==fid then table.insert(vis,string.format('%.0f',t)) else table.insert(hid,string.format('%.0f',t)) end end end "
        "return string.format('n=%d firstT=%s otherT=%s', n, table.concat(vis,','), table.concat(hid,','))")
ok("1c. on the client only the assigned nest egg is visible (the other two have LocalTransparencyModifier 1)", "firstT=0" in hid and re.search(r"otherT=1,1$", hid) is not None, hid)
frame("1_far_nest", f"(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local N=Vector3.new({NP}) local u=Vector3.new(r.Position.X-N.X,0,r.Position.Z-N.Z).Unit return N+u*18+Vector3.new(0,8,0) end)()",
      f"Vector3.new({NP})+Vector3.new(0,1.5,0)")

# ------------------------------------------------- 2 the chain and the arrow from spawn
tr = trail()
ok("2. the chevron chain from the feet to the far nest (>= 3) and the arrow above the target", num(tr, "trail", 0) >= 3 and "arrow=true" in tr, tr)
desk("2_spawn_trail")

# ------------------------------------------------- 3 the near one does not give; the far one: took and stands
near = S(ME + FL + HOME + NESTS + f"local b,bd for _,m in nests(0) do if m:GetAttribute('NestId')~='{FID}' and m:GetAttribute('HasEgg')==true then local d=fl(m:GetAttribute('At'),P) if not bd or d<bd then b,bd=m,d end end end "
         "if not b then return 'none' end local a=b:GetAttribute('At') local u=Vector3.new(P.X-a.X,0,P.Z-a.Z).Unit ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) task.wait(2) "
         "local d=dump() return string.format('d=%.0f carry=%s mark=%s', bd, tostring(d.eggs.carry~=nil), mk(guardOf(b)))")
ok("3. at the near nest (there is an egg) the newcomer does not get the egg, the warden sleeps", "carry=false" in near and "mark=Zz" in near, near)
S(ME + FL + HOME + "ch:PivotTo(CFrame.new(P+Vector3.new(0,4,0))) return 1"); time.sleep(0.5)
tw = S(ME + FL + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit local T=N+u*9 local c0=os.clock() local t=0 while t<14 do local p=r.Position if fl(p,T)<1.2 then break end "
       "local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(T.X,gl(q)+3,T.Z))) task.wait(0.1) t=os.clock()-c0 end return string.format('%.1f',t)")
P("from the gap to the far nest on foot:", tw, "s")
banner_watch("RUN!", "SawRun")
c3 = S(ME + FL + HOME + NESTS + f"local N=Vector3.new({NP}) local m=nestById('{FID}') local g=guardOf(m) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit "
       "ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) local c0=os.clock() local t=0 local t0,tm,tc local L0 local ex='' while t<8 do "
       "local d=dump() local carry=d.eggs.carry if not t0 and carry and carry.raid~=nil then t0=t L0=g:GetPivot().Position end "
       "if t0 and ex=='' and mk(g)=='!' then ex='!' end "
       "if t0 and not tm and fl(g:GetPivot().Position,L0)>0.3 then tm=t end if t0 and not tc and not (d.eggs.carry and d.eggs.carry.raid~=nil) then tc=t end "
       "if tc then break end task.wait(0.05) t=os.clock()-c0 end "
       "return string.format('take=%s move=%s caught=%s mark=%s', tostring(t0), tm and string.format('%.2f',tm-t0) or 'nil', tc and string.format('%.2f',tc-t0) or 'nil', ex)")
mv3, cg3 = num(c3, "move"), num(c3, "caught")
ok("3a. took: '!', the warden moved after 1.2 +-0.35 s (first.wake); stood - CAUGHT <= 1.8 s", "take=nil" not in c3 and "mark=!" in c3 and mv3 is not None and 0.85 <= mv3 <= 1.55 and cg3 is not None and cg3 <= 1.8, c3)
ok("3b. a huge 'RUN!' on the screen", C("return tostring(workspace:GetAttribute('SawRun'))") == "true")
time.sleep(1.5)
P("screen after the capture:", labels("CAUGHT")[:100], "|", labels("again")[:100])
sl = "?"
for _ in range(16):
    sl = S(ME + NESTS + f"local m=nestById('{FID}') return mk(guardOf(m))..' egg='..tostring(m:GetAttribute('HasEgg'))")
    if sl.startswith("Zz") and "egg=true" in sl: break
    time.sleep(0.5)
ok("3c. the warden came back and sleeps, the egg is in the nest again (<= 8 s)", sl.startswith("Zz") and "egg=true" in sl, sl)
time.sleep(2)
re3 = S(NESTS + "local d=dump() return tostring(d.eggs.carry and d.eggs.carry.raid)")
ok("3d. stood nearby - the egg is not given right away (rearm: step 15 away)", re3 == "nil", re3)

# ------------------------------------------------- 4 second attempt: the run home ~100 studs
S(ME + FL + HOME + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*22+Vector3.new(0,4,0))) return 1")
time.sleep(1.8)
banner_watch("SAFE!", "SawSafe", 40)
S(ME + FL + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local m=nestById('{FID}') local g=guardOf(m) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit workspace:SetAttribute('RaidRun',nil) workspace:SetAttribute('RaidTaken',nil) task.spawn(function() "
  "ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) local w=0 while not (dump().eggs.carry or {}).raid and w<3 do task.wait(0.05) w+=0.05 end "
  "if not (dump().eggs.carry or {}).raid then workspace:SetAttribute('RaidRun','not taken') return end workspace:SetAttribute('RaidTaken',true) task.wait(0.6) "
  "local c0=os.clock() local t,minG,spd,lastL,lastT=0,1e9,{},g:GetPivot().Position,0 local angMax=0 "
  "local T=P+u*8 while t<14 do local p=r.Position if inside(p) then break end local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) "
  "local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(P.X,gl(q)+3,P.Z))) task.wait(0.1) t=os.clock()-c0 "
  "local L=g:GetPivot().Position local gp=fl(L,r.Position) if t>0.8 then minG=math.min(minG,gp) local a=math.deg(math.acos(math.clamp(Vector3.new(r.Position.X-L.X,0,r.Position.Z-L.Z).Unit:Dot(to.Unit),-1,1))) angMax=math.max(angMax,a) end "
  "if t-lastT>=0.5 and t>0.8 then table.insert(spd,string.format('%.1f',fl(L,lastL)/(t-lastT))) lastL,lastT=L,t elseif t<=0.8 then lastL,lastT=L,t end end "
  "local arr=t local entry=r.Position local gate1,still,run,prev=1e9,0,0,nil for k=1,40 do task.wait(0.1) local L=g:GetPivot().Position local gp=fl(L,entry) gate1=math.min(gate1,gp) "
  "if prev and fl(L,prev)<0.06 and gp<6 then run+=0.1 still=math.max(still,run) else run=0 end prev=L end "
  "local slept=false for k=1,60 do task.wait(0.2) if mk(g)=='Zz' then slept=true break end end "
  "local d=dump() local inc=d.eggs.incubating['1'] local left=inc and (inc.endsAt-os.time()) or -1 local dr=0 for _ in d.dragons do dr+=1 end "
  "workspace:SetAttribute('RaidRun',string.format('run=%.1f minGap=%.1f ang=%.0f speeds=%s gateGap=%.1f still=%.2f slept=%s inc=%s left=%d dragons=%d home=%d carry=%s', "
  "arr,minG,angMax,table.concat(spd,','),gate1,still,tostring(slept),tostring(inc~=nil),left,dr,tonumber(d.raid and d.raid.home) or -1,tostring(d.eggs.carry~=nil))) end) return 'started'")
for _ in range(30):
    if S("return tostring(workspace:GetAttribute('RaidTaken'))") == "true": break
    time.sleep(0.1)
time.sleep(0.4)
tr4 = trail()
ok("4-trail. with the egg in the hands: the chevron chain to the gap (>= 3), none on the fence, the arrow above the line", num(tr4, "trail", 0) >= 3 and num(tr4, "onFence", 99) == 0 and "arrow=true" in tr4, tr4)
time.sleep(1.2)
frame("4_chase_side",
      "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
      "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end local a=r.Position local b=L and L:GetPivot().Position or a "
      "local mid=(a+b)/2 local ln=Vector3.new(a.X-b.X,0,a.Z-b.Z) ln=if ln.Magnitude>0.1 then ln.Unit else Vector3.xAxis return mid+Vector3.new(-ln.Z,0,ln.X)*22+Vector3.new(0,9,0) end)()",
      "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
      "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end return (r.Position+(L and L:GetPivot().Position or r.Position))/2 end)()")
res = "?"
for _ in range(80):
    res = S("return tostring(workspace:GetAttribute('RaidRun'))")
    if res != "nil": break
    time.sleep(0.4)
P("run home:", res)
spd = [float(x) for x in (re.findall(r"speeds=([\d.,]*)", res) or [""])[0].split(",") if x]
ok("4. run ~100 studs (0.6 s standing + 16 studs/s): home in 5-9 s, the warden at 0.75 speed (12 +-1.8) strictly behind (angle <= 25), not closer than 8",
   5 <= num(res, "run", 99) <= 9 and num(res, "minGap", 0) >= 7.5 and num(res, "ang", 99) <= 25 and bool(spd) and all(10.2 <= v <= 13.8 for v in spd[1:]), res[:220])
ok("4b. stopped at the line (<= 6 from the entry point, >= 0.5 s), went back to its lair and sleeps", 0 <= num(res, "gateGap", -1) <= 6 and num(res, "still", 0) >= 0.5 and "slept=true" in res, res[-220:])
ok("4c. at home 'SAFE!'", C("return tostring(workspace:GetAttribute('SawSafe'))") == "true")
ok("4d. the egg in bowl 1 (or already hatched), raid.home = 1, the hands are empty", ("inc=true" in res or num(res, "dragons", 0) >= 1) and num(res, "home", 0) == 1 and "carry=false" in res, res[-160:])
hat = "?"; waited = 0.0
for i in range(50):
    hat = S(ME + NESTS + "local d=dump() local dr=0 for _ in d.dragons do dr+=1 end return string.format('dragons=%d inc=%s comp=%s stage=%s', dr, tostring(d.eggs.incubating['1']~=nil), tostring(d.companion), tostring(me:GetAttribute('CompanionStage')))")
    if num(hat, "dragons", 0) >= 1: waited = i * 0.5; break
    time.sleep(0.5); waited = (i + 1) * 0.5
ok("4e. the first egg hatched by itself (<= 25 s after the line), 1 dragon, the companion assigned", num(hat, "dragons", 0) >= 1 and "comp=nil" not in hat, hat + f" | waited {waited:.1f} s")
frame("4_hatched_home", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*12+Vector3.new(0,6,0) end)()",
      "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*4 end)()")
rsp = "?"
for _ in range(30):
    rsp = S(ME + NESTS + f"local m=nestById('{FID}') return 'egg='..tostring(m:GetAttribute('HasEgg'))..' ready='..string.format('%.0f',(tonumber(m:GetAttribute('ReadyAt')) or 0)-workspace:GetServerTimeNow())")
    if "egg=true" in rsp: break
    time.sleep(1)
ok("4f. the egg in the far nest again (respawn 20 s, <= 25 s after the theft)", "egg=true" in rsp, rsp)

# ------------------------------------------------- 5 with a dragon: the nests are silent, the step does not call
stp = labels("Sneak to the Gloom") or labels("Steal an egg")
P("step after the hatch:", (labels("NEXT") or "-")[:120])
ok("5. after the first dragon the step does not call to the Gloom nests", not stp, stp[:120])
lock = S(ME + FL + HOME + NESTS + "local b,bd for _,m in nests(0) do if m:GetAttribute('HasEgg')==true then local d=fl(m:GetAttribute('At'),P) if not bd or d<bd then b,bd=m,d end end end "
         "if not b then return 'noegg' end local a=b:GetAttribute('At') local u=Vector3.new(P.X-a.X,0,P.Z-a.Z).Unit local p0=r.Position ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) task.wait(2) "
         "local d=dump() local c=tostring(d.eggs.carry~=nil) ch:PivotTo(CFrame.new(p0)) return 'carry='..c..' mark='..mk(guardOf(b))")
hid5 = C("local CS=game:GetService('CollectionService') local t=1 local n=0 for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('HasEgg')==true then local e=m:FindFirstChild('Egg') or m:FindFirstChild('Egg',true) "
         "if e then n+=1 for _,d in e:GetDescendants() do if d:IsA('BasePart') then t=math.min(t,d.LocalTransparencyModifier) end end end end end return string.format('eggs=%d minT=%.0f', n, t)")
ok("5a. with a dragon a ring 0 nest does not give its egg (the warden sleeps) and the client does not show the nest eggs", "carry=false" in lock and "mark=Zz" in lock and num(hid5, "minT", 0) == 1, lock + " | " + hid5)
q = labels("A second egg")
ok("5b. Keeper without the 'A second egg' step", not q, (q or "-")[:80])

# ------------------------------------------------- 6 console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Raid]" in l or "[Combat]" in l or "[Glow]" in l or "[Movement]" in l or "[Incubation]" in l or "[Hints]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("6. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
write_result("Newcomer first egg by a raid (spec 27 sec. 14/25/26): far nest, spawn at home, no table")
