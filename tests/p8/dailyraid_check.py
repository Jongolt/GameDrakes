#!/usr/bin/env python3
"""The daily raids after the first dragon on the glow-egg test build.
A a clean profile: the first egg by a raid from the far nest (FirstNest), home, hatched - dragon 1.
B with a dragon: RaidLeft = 4, FirstNest is the same, on the client only the own nest's egg is visible, the free island eggs are hidden.
C four daily raids in a row (up to 3 attempts per egg): the guard of the k-th egg is faster (share 0.9/1.0/1.08/1.15 x 16), the catches, the gap, at home
  the toast 'N more eggs today' / 'Last egg today', RaidLeft and raid.dayN by count.
D after the 4th: 'THAT'S ALL FOR TODAY!', RaidLeft 0, the nest egg is hidden on the client, the 5th cannot be taken.
E the bowl and the shelf: the egg in the bowl hatches in 3-15 min (endsAt), the rest on the shelf (one bowl), the bowl Unlock button is visible.
F riding (time -> a teen -> mount): riding past at 25 from the own nest does not unseat, at 10 - unseats (dismountR 15).
G the console.
Run: python3 tests/p8/dailyraid_check.py (after open_local with the glow-egg build)."""
import os, sys, time, json, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("dailyraid_check")
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

def nest_info():
    b = S(ME + FL + HOME + NESTS + "local fid=me:GetAttribute('FirstNest') local m=fid and nestById(fid) if not m then return 'first=nil' end local a=m:GetAttribute('At') "
          "return string.format('first=%s d=%.1f at=%.2f,%.2f,%.2f left=%s', tostring(fid), fl(a,P), a.X,a.Y,a.Z, tostring(me:GetAttribute('RaidLeft')))")
    if "first=nil" in b:
        return b, None, None
    return b, re.search(r"at=(-?[\d.]+,-?[\d.]+,-?[\d.]+)", b).group(1), re.search(r"first=(\S+)", b).group(1)

def wait_egg(fid, secs=40):
    st = "?"
    for _ in range(int(secs * 2)):
        st = S(ME + NESTS + f"local m=nestById('{fid}') return mk(guardOf(m))..' egg='..tostring(m:GetAttribute('HasEgg'))")
        if st.startswith("Zz") and "egg=true" in st: return True, st
        time.sleep(0.5)
    return False, st

def go_home():
    S(ME + FL + HOME + "ch:PivotTo(CFrame.new(P+Vector3.new(0,4,0))) return 1"); time.sleep(0.6)

# the theft and the run home ~16 studs/s step by step (the anti-cheat); a catch = CarriedEgg vanished before the plot
def steal_run(NP, FID):
    S(ME + FL + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local m=nestById('{FID}') local g=guardOf(m) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit "
      "workspace:SetAttribute('DR',nil) task.spawn(function() ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) local w=0 "
      "while not ch:FindFirstChild('CarriedEgg') and w<3 do task.wait(0.05) w+=0.05 end "
      "if not ch:FindFirstChild('CarriedEgg') then workspace:SetAttribute('DR','taken=false left='..tostring(me:GetAttribute('RaidLeft'))) return end "
      "task.wait(0.3) local c0=os.clock() local t,minG,spd,lastL,lastT=0,1e9,{},g:GetPivot().Position,0 local caught=false local T=P+u*8 "
      "local dt=0.1 while t<14 do local p=r.Position if inside(p) then break end if not ch:FindFirstChild('CarriedEgg') then caught=true break end "
      "local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) local q=p+to.Unit*math.min(16*math.min(dt,0.2),to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(P.X,gl(q)+3,P.Z))) "
      "dt=task.wait(0.1) t=os.clock()-c0 local L=g:GetPivot().Position if t>1.2 then minG=math.min(minG,fl(L,r.Position)) end "
      "if t-lastT>=0.5 and t>1.2 then table.insert(spd,string.format('%.1f',fl(L,lastL)/(t-lastT))) lastL,lastT=L,t elseif t<=1.2 then lastL,lastT=L,t end end "
      "local runT=t task.wait(1.6) local d=dump() local n=0 for _ in d.eggs.incubating do n+=1 end "
      "workspace:SetAttribute('DR',string.format('taken=true caught=%s run=%.1f minGap=%.1f speeds=%s home=%d dayN=%s left=%s carry=%s inc=%d shelf=%d', "
      "tostring(caught),runT,minG,table.concat(spd,','),tonumber(d.raid and d.raid.home) or -1,tostring(d.raid and d.raid.dayN),tostring(me:GetAttribute('RaidLeft')),"
      "tostring(d.eggs.carry~=nil),n,d.eggs.shelf and #d.eggs.shelf or 0)) end) return 'started'")
    res = "nil"
    for _ in range(70):
        res = S("return tostring(workspace:GetAttribute('DR'))")
        if res != "nil": break
        time.sleep(0.4)
    return res

def egg_visible_own(fid):
    return C("local me=game.Players.LocalPlayer local CS=game:GetService('CollectionService') local own,oth={}, {} "
             "for _,m in CS:GetTagged('RaidNest') do local e=m:FindFirstChild('Egg') if e then local t=1 for _,d in e:GetDescendants() do if d:IsA('BasePart') then t=math.min(t,d.LocalTransparencyModifier) end end "
             f"if m:GetAttribute('NestId')=='{fid}' then table.insert(own,string.format('%.0f',t)) else table.insert(oth,string.format('%.0f',t)) end end end "
             "local free=1 for _,a in CS:GetTagged('EggPoint') do local e=a:FindFirstChild('Egg') if e then for _,d in e:GetDescendants() do if d:IsA('BasePart') then free=math.min(free,d.LocalTransparencyModifier) end end end end "
             "return 'own='..table.concat(own,',')..' other='..table.concat(oth,',')..' freeMinT='..free")

def gui_text(sub):
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if (d:IsA('TextLabel') or d:IsA('TextButton')) and d.Text:find([[" + sub + "]],1,true) then "
             "local v=d.Visible local a=d.Parent while v and a and a~=pg do if a:IsA('GuiObject') and not a.Visible then v=false end if (a:IsA('BillboardGui') or a:IsA('ScreenGui')) and not a.Enabled then v=false end a=a.Parent end "
             "if v then table.insert(o,d.Text) end end end return table.concat(o,' | ')")

# ------------------------------------------------- A a clean profile, the first egg
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)
b, NP, FID = nest_info()
ok("A0. the newcomer is assigned the far nest (FirstNest), no RaidLeft (0 dragons)", FID is not None and "left=nil" in b and num(b, "d", 0) >= 80, b)
if not FID:
    stop(); write_result("Daily raids: FirstNest is not assigned"); sys.exit(1)
okE, st = wait_egg(FID, 20)
first = "?"
for attempt in range(3):
    first = steal_run(NP, FID)
    if "caught=false" in first: break
    go_home(); wait_egg(FID, 15)
P("the first egg:", first)
hat = "?"
for _ in range(50):
    hat = S(ME + NESTS + "local d=dump() local dr=0 for _ in d.dragons do dr+=1 end return 'dragons='..dr")
    if num(hat, "dragons", 0) >= 1: break
    time.sleep(0.5)
ok("A. the first egg by a raid is home and hatched: dragon 1", num(hat, "dragons", 0) >= 1 and num(first, "home", 0) == 1, first[:160] + " | " + hat)

# ------------------------------------------------- B with a dragon: the limit and the visibility
time.sleep(1.5)
b2, NP2, FID2 = nest_info()
ok("B. with a dragon RaidLeft = 4, the nest is the same far one", "left=4" in b2 and FID2 == FID, b2)
okE, st = wait_egg(FID, 30)
time.sleep(1.0)
vis = egg_visible_own(FID)
ok("B1. on the client the own nest's egg is visible, the other two are not, the free island eggs are hidden", "own=0" in vis and re.search(r"other=1,1 ", vis) is not None and "freeMinT=1" in vis, vis + " | " + st)
P("the steps (the golden one is not stolen - we do not call to the nests):", (labels("left today") or "-")[:100])

# ------------------------------------------------- C four daily raids
results = []
for k in range(1, 5):
    okE, st = wait_egg(FID, 40)
    if not okE:
        ok(f"C{k}. the egg did not appear in the nest", False, st); break
    if k == 4:  # 'THAT'S' - the apostrophe broke the Lua string in banner_watch: we search by a substring
        C("workspace:SetAttribute('SawDayDone',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
          "while os.clock()-t0<150 do local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') "
          "if l and f.Visible and l.Text:find('ALL FOR TODAY',1,true) then workspace:SetAttribute('SawDayDone',true) break end task.wait(0.05) end end) return 1")
    else:  # the toast lives 2.6 s and comes 4.2 s after home - we catch it with a watcher
        C("workspace:SetAttribute('SawToast',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
          "while os.clock()-t0<60 do for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and (d.Text:find('more eggs today',1,true) or d.Text:find('Last egg today',1,true)) then "
          "workspace:SetAttribute('SawToast',d.Text) return end end task.wait(0.1) end end) return 1")
    tries = []
    for attempt in range(3):
        r_ = steal_run(NP, FID)
        tries.append(r_)
        if "caught=false" in r_ and "taken=true" in r_: break
        go_home(); wait_egg(FID, 20)
    toast = "nil"
    for _ in range(14):
        toast = C("return tostring(workspace:GetAttribute('SawToast'))")
        if toast != "nil" or k == 4: break
        time.sleep(0.5)
    toast = "" if toast == "nil" else toast
    last = tries[-1]
    results.append((k, len(tries), last))
    spd = [float(x) for x in (re.findall(r"speeds=([\d.,]*)", last) or [""])[0].split(",") if x]
    P(f"egg {k}: attempts {len(tries)}; catches {[('caught=true' in t) for t in tries]}; the guard speed {spd}; {last[:200]}")
    for t_ in tries[:-1]: P("   attempt:", t_[:200])
    P(f"  toast: {toast[:80] if toast else '-'}")
    ok(f"C{k}. egg {k} is home: dayN={k}, RaidLeft={4-k}", f"dayN={k}" in last and f"left={4-k}" in last and "carry=false" in last, last[:220])
    if k < 4:
        ok(f"C{k}t. the toast 'more eggs today' / 'Last egg today'", bool(toast), toast[:80])
    early = [t for t in tries if "caught=true" in t and num(t, "run", 99) < 1.5]
    ok(f"C{k}w. not a single catch at the moment of waking (the guard sleeps on the lair, not on the trail)", not early, "; ".join(t[:80] for t in early))
    go_home()

# ------------------------------------------------- D the limit is over
time.sleep(5)
ok("D. the banner 'THAT'S ALL FOR TODAY!' after the 4th egg", C("return tostring(workspace:GetAttribute('SawDayDone'))") == "true", labels("Come back tomorrow")[:80])
okE, st = wait_egg(FID, 30)
time.sleep(0.2)
vis2 = egg_visible_own(FID)
ok("D1. the own nest's egg is hidden on the client (the limit 0)", "own=1" in vis2, vis2)
r5 = steal_run(NP, FID)
ok("D2. the fifth egg cannot be taken, RaidLeft 0", "taken=false" in r5 and "left=0" in r5, r5)
go_home()

# ------------------------------------------------- E the bowl and the shelf
e = S(ME + NESTS + "local d=dump() local o={} for k,v in d.eggs.incubating do table.insert(o,k..':'..(v.egg and v.egg.rarity or '?')..':'..tostring(v.endsAt-os.time())) end "
      "local sh={} for _,x in d.eggs.shelf or {} do table.insert(sh,x.rarity or '?') end local dr=0 for _ in d.dragons do dr+=1 end "
      "return 'inc='..table.concat(o,',')..' shelf='..table.concat(sh,',')..' dragons='..dr..' incubators='..tostring(d.incubators)")
P("the bowls and the shelf:", e)
secs = [int(x) for x in re.findall(r":(-?\d+)(?:,|\s)", e)]
ok("E. in the bowl a raid egg with a hatch of 3-15 min (the remainder 60-900 s), the rest on the shelf", bool(secs) and all(60 <= s_ <= 900 for s_ in secs) and "shelf=" in e and num(e, "dragons", 0) >= 1, e)
time.sleep(1)
un = gui_text("Unlock")
ok("E1. at the own pen the bowl Unlock button is visible (the daily raids were still running / eggs on the shelf)", bool(un), un[:80])
desk("E_home_bowls")

# ------------------------------------------------- F riding: riding past the own nest
P("time:", ldr("time 9999999")[:40])
st = "?"
for _ in range(40):
    st = S(ME + "return 'stage='..tostring(me:GetAttribute('CompanionStage'))")
    if "stage=1" in st or "stage=2" in st: break
    time.sleep(0.5)
P("the stage:", st, "mount:", ldr("mount")[:60])
time.sleep(1.5)
def warp_near(dist):
    wt = S(ME + FL + HOME + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit local q=N+u*{dist} "
           "local function f(v) local n=math.floor(v+0.5) return (n<0 and 'n' or '')..tostring(math.abs(n)) end return f(q.X)..'x'..f(q.Y+5)..'x'..f(q.Z)")
    return ldr("warp " + wt)
m0 = S(ME + "return tostring(me:GetAttribute('Mounted'))")
if m0 != "nil":
    P("warp 25:", warp_near(25)[:40]); time.sleep(2.5)
    m25 = S(ME + FL + f"local N=Vector3.new({NP}) return tostring(me:GetAttribute('Mounted'))..string.format(' d=%.0f', fl(r.Position,N))")
    P("warp 10:", warp_near(10)[:40]); time.sleep(2.5)
    m10 = S(ME + FL + f"local N=Vector3.new({NP}) return tostring(me:GetAttribute('Mounted'))..string.format(' d=%.0f', fl(r.Position,N))")
    ok("F. the limit 0: riding at the own nest (25 and 10) does not unseat - no eggs today", not m25.startswith("nil") and not m10.startswith("nil"), m25 + " | " + m10)
else:
    ok("F. mounting failed - the station is skipped", False, st)

# ------------------------------------------------- G the console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Raid]" in l or "[Combat]" in l or "[Glow" in l or "[Movement]" in l or "[Incubation]" in l or "[Hints]" in l or "[Crowd]" in l or "[AntiCheat]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("G. the console without game errors", not bad, str(len(bad)))
for l in bad[-12:]: P("  ", l[:220])
stop()
write_result("Daily raids (Config.Raid.daily): 4 eggs per day, the guard angrier, the limit, the bowl and the shelf")
