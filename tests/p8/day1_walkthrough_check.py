#!/usr/bin/env python3
"""The full newcomer walkthrough on the glow-egg test build in one script, by day and by night, the day phase as an argument.
python3 tests/p8/day1_walkthrough_check.py day     (after open_local with the glow-egg HEAD build)
python3 tests/p8/day1_walkthrough_check.py night
The stations (each in its own wrapper - a failure of one does not break the others; the frames as desk shots, the camera is computed before the frame):
A the spawn in the own pen at the gap facing the plaza (HomeSpawn), not at the Keeper
B the step 'Steal an egg from the sleeping Gloom - your first dragon!', the target = the FAR ring 0 nest (FirstNest, >= 80 from the gate),
the HintTrail chevron chain, the arrow above the nest, the near nests' eggs are not visible to the newcomer (LocalTransparencyModifier 1)
C the near nest does not give the egg; the far one: took it and stands - '!', the guard moved after 1.2 s (first.wake), CAUGHT <= 1.8 s, RUN!,
the egg back, the guard sleeps, rearm
D the second attempt: the run home 16 studs/s across the plaza, the guard 0.75 (12 +-1.5) behind, the gap >= 8; the chevrons along the ground, none on the fence;
the edge pointer when the target is behind; SAFE!; the egg into the bowl, the hatch (<= 20 s), raid.home = 1
E after the first dragon: the ring 0 nests do not give or show the egg; the Keeper without 'A second egg'; the first ambush ~10 s after
the hatch on the ground runs (a frame, the Gloom with the violet shell and Highlight), then clear
F coins -> growth to a teen (time) -> riding -> 'A GOLDEN NEST WITH A GLOWING EGG!' on the slope (r 196-232), Warden x1.5 sleeps
G the golden raid: riding closer than 35 on the ground - dismounted, the dragon at D, the saddle at the nest - a refusal; took it and stood - CAUGHT; the second - the run to the dragon,
mounted = SAFE!, the guard stopped and melted; home riding, the chain along a passable path (not through the fence), the stand 20 h
H the stand: the board with buttons on foot nearby; Warm takes an hour and coins; 'shop HatchNow glow' -> the bowl -> the hatch, 2 dragons
I an adult -> takeoff -> a flyover of the zones (the meadow, the cliffs, the baths, the summit, the islets) ~3 min on ClientDebug fly: growth in the air (time) and feeding -
Mounted is not removed, no jerk at the ceiling, no hunt in the sky; landing at home riding: the stand board, the pass chips, the bowl buttons are hidden
J a storm (WeatherDebug storm): the hunt is silent; the windows 'gift / invite / favorite' never opened during the action
K the bots: the riders workspace.Bots and the walkers workspace.Crowd (Config.Admin.auto.studio = true for the probe - an edit of the Config Source in
Edit, restored at the end), all AvatarKeys differ, not a single owner account; a walker not on the counter; the demo raid at
the copy nest (<= 60 s with a live player nearby)
L the console: not a single 'dismount IN AIR', 0 game errors; the Perf line (FPS)
Pitfalls: move the character step by step 1.6 studs / 0.1 s (a one-hop teleport is rolled back by the anti-cheat); riding - move with ld warp;
the time - os.clock(), not the sum of task.wait. The output: $P8_OUT_ROOT/roblox_build_<date>/day1_walkthrough_<phase>/."""
import os, sys, time, json, re, traceback
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
PHASE = (sys.argv[1] if len(sys.argv) > 1 else "day").strip().lower()
assert PHASE in ("day", "night", "dusk", "dawn"), "the phase: day | night | dusk | dawn"
import p8lib
p8lib.begin("day1_walkthrough_" + PHASE)
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
def ldr(c):
    return S(LD + f"local r=ld('{c}') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t or "")
    return float(m.group(1)) if m else default
def jnum(t, key, default=None):  # a number from a JSON string ("key":N)
    m = re.search('"' + key + r'":(-?[\d.]+)', t or "")
    return float(m.group(1)) if m else default

ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
FL = "local function fl(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end "
HOME = ("local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local i1=hn and hn:FindFirstChild('Incubators') i1=i1 and i1:FindFirstChild('Incubator1') "
        "local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end "
        "local function inside(p) if not hb then return false end local lp=hb.CFrame:PointToObjectSpace(p) return math.abs(lp.X)<=hb.Size.X/2 and math.abs(lp.Z)<=hb.Size.Z/2 end ")
NESTS = ("local CS=game:GetService('CollectionService') "
         "local function nests(ring) local o={} for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==ring then table.insert(o,m) end end return o end "
         "local function nestById(id) for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('NestId')==id then return m end end return nil end "
         "local function guardOf(m) for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='raid:'..tostring(m:GetAttribute('NestId')) then return g end end return nil end "
         "local function mk(g) local b=g and g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') return b and b.T and b.T.Text or '-' end "
         "local function dump() return game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) end ")
GL = ("local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude "
      "pr.FilterDescendantsInstances={ch, workspace:FindFirstChild('Gloom'), workspace:FindFirstChild('RaidNests'), workspace:FindFirstChild('GlowRaidFx'), workspace:FindFirstChild('GlowEggs'), workspace:FindFirstChild('HintTrail'), workspace:FindFirstChild('Bots'), workspace:FindFirstChild('Crowd')} "
      "local h=workspace:Raycast(p+Vector3.new(0,30,0),Vector3.new(0,-80,0),pr) return h and h.Position.Y or p.Y end ")
GLOW = "local gm=workspace:FindFirstChild('GlowEggs') gm=gm and gm:FindFirstChild('GlowEgg_'..me.UserId) local N=gm and gm:GetAttribute('At') "
PACK = ("local pk={} for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do if x:GetAttribute('OwnerId')==me.UserId then table.insert(pk,x) end end "  # as in glowraid_check: the golden nest pack - by OwnerId; the ring guards sleep without OwnerId
        "local function mkp(x) local b=x.PrimaryPart and x.PrimaryPart:FindFirstChild('Mark') return b and b.T and b.T.Text or '-' end ")
COMP = "local comp for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then comp=x end end "
# the character's step-by-step run to point T (1.6 studs / 0.1 s = 16 studs/s) on the server; stop by the condition stopExpr (a Luau string) or by time
def walk_code(target_expr, stop_expr="false", max_sec=12):
    return (f"local T={target_expr} local c0=os.clock() local t=0 while t<{max_sec} do local p=r.Position if ({stop_expr}) or fl(p,T)<1.2 then break end "
            "local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) local q=p+to.Unit*math.min(1.6,to.Magnitude) "
            "ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(T.X,gl(q)+3,T.Z))) task.wait(0.1) t=os.clock()-c0 end return t ")

def frame(name, pos_expr, tgt_expr):
    r_ = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local tgt={tgt_expr} local p0={pos_expr} "
           "local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude local sk={me.Character} "
           "for _,n in {'Gloom','RaidNests','GlowRaidFx','GlowEggs','HintTrail','Bots','Crowd'} do local x=workspace:FindFirstChild(n) if x then table.insert(sk,x) end end "
           "for _,x in game:GetService('CollectionService'):GetTagged('Companion') do table.insert(sk,x) end pr.FilterDescendantsInstances=sk "
           "local pos for k=0,11 do local a=math.rad(k*30) local off=CFrame.Angles(0,a,0):VectorToWorldSpace(p0-tgt) local cp=tgt+off "
           "if not workspace:Raycast(cp,tgt-cp,pr) then pos=cp break end end if not pos then return 'no clear view' end "
           "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(pos,tgt) return 'ok'")
    time.sleep(0.5)
    desk(name)
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
    P("frame", name, r_)

def banner_watch(text, attr, secs=40, sub=None):
    extra = f" and (function() local l2=f:FindFirstChild('L2') return l2 and l2.Text:find('{sub}')~=nil end)()" if sub else ""
    C(f"workspace:SetAttribute('{attr}',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
      f"local seen=workspace:GetAttribute('SeenL1') or '' while os.clock()-t0<{secs} do local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') "
      f"if l and f.Visible and l.Text~='' and not seen:find(l.Text,1,true) then seen=seen..' || '..l.Text workspace:SetAttribute('SeenL1',seen) end "  # all the banners during the wait (the F4 diagnostics)
      f"if l and f.Visible and l.Text=='{text}'{extra} then workspace:SetAttribute('{attr}',true) break end task.wait(0.05) end end) return 1")

def labels(sub):
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find([[" + sub + "]],1,true) then table.insert(o,d.Text) end end return table.concat(o,' | ')")

def wait_label(sub, secs=12):
    t = ""
    for _ in range(int(secs * 2)):
        t = labels(sub)
        if t: return t
        time.sleep(0.5)
    return t

def trail(fence=True):
    """The client's chevron chain: how many, how many on the own plot's fence, the curvature (the deviation from the first-last straight line)."""
    return C("local me=game.Players.LocalPlayer local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
             "local f=workspace:FindFirstChild('HintTrail') if not f then return 'trail=0' end local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Include "
             "op.FilterDescendantsInstances={hn and hn:FindFirstChild('Fence') or workspace} local pts,hit,n={},0,0 "
             "for _,q in f:GetChildren() do if q:IsA('BasePart') and q.Transparency<1 and q.Material==Enum.Material.Neon and q:GetAttribute('Side')==1 then n+=1 table.insert(pts,q.Position) "
             "if hn and #workspace:GetPartBoundsInRadius(q.Position+Vector3.new(0,1,0),1.2,op)>0 then hit+=1 end end end "
             "local dev=0 if #pts>=3 then local a,b=pts[1],pts[#pts] local ab=Vector3.new(b.X-a.X,0,b.Z-a.Z) if ab.Magnitude>1 then local u=ab.Unit for _,p in pts do local ap=Vector3.new(p.X-a.X,0,p.Z-a.Z) dev=math.max(dev,(ap-u*ap:Dot(u)).Magnitude) end end end "
             # cross - how many segments between neighboring chevrons pass through the own plot's fence (a ray), whether the trail is straight is not a criterion
             "local cross=0 local at='' local fe=hn and hn:FindFirstChild('Fence') if fe then local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Include rp.FilterDescendantsInstances={fe} "
             "for i=1,#pts-1 do local a,b=pts[i]+Vector3.new(0,1.5,0),pts[i+1]+Vector3.new(0,1.5,0) local rc=workspace:Raycast(a,b-a,rp) if rc then cross+=1 at=at..string.format('%d:%s@%.0f,%.0f,%.0f;', i, rc.Instance.Name, rc.Position.X, rc.Position.Y, rc.Position.Z) end end end "
             "local arrow=workspace:FindFirstChild('HintArrow',true) or game.Players.LocalPlayer.PlayerGui:FindFirstChild('HintArrow',true) "
             "return string.format('trail=%d onFence=%d cross=%d crossAt=%s dev=%.1f count=%s arrow=%s', n, hit, cross, at, dev, tostring(f:GetAttribute('Count')), tostring(arrow~=nil))")

def windows():
    """The asking windows and the 'favorite' banner on the screen now (they must be silent during the action)."""
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,n in {'FreeGiftCard','InviteCard','FavoriteCard','PassCard'} do local g=pg:FindFirstChild(n) if g and g.Enabled then table.insert(o,n) end end "
             "local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') if l and f.Visible and (l.Text:find('avorite') or l.Text:find('LIKE')) then table.insert(o,'likeBanner') end return table.concat(o,',')")

def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()

def phase():
    S(f"game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','{PHASE}') return 1")

STOP_AFTER = os.environ.get("P8_STOP_AFTER", "")  # the run up to a station (the G4 diagnostics), then the console and stop

def glow_console():
    for l in console_lines():
        if "[GlowEgg]" in l or "[Combat] pack" in l:
            P("  console:", l[:220])

def station(name, fn):
    try:
        phase()
        fn()
    except SystemExit:
        raise
    except Exception as e:  # a probe failure, not the game's - into the journal and on
        ok(f"{name}: the probe without a failure", False, repr(e)[:200])
        P(traceback.format_exc()[-800:])
    if STOP_AFTER and name == STOP_AFTER:
        P(f"P8_STOP_AFTER={STOP_AFTER}: the GlowEgg console and stop")
        glow_console()
        stop()
        run("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'checkEvery = 12, studio = true',1,true) if a then m.Source=string.sub(s,1,a-1)..'checkEvery = 12, studio = false'..string.sub(s,b+1) end return 1", "Edit")
        write_result(f"Day 1 ({PHASE}) up to station {STOP_AFTER}")
        sys.exit(0)

seen_windows = set()
def note_windows(tag):
    w = windows()
    if w:
        seen_windows.add(f"{tag}:{w}")
        P("A WINDOW during the action:", tag, w)

# ------------------------------------------------- preparation: a clean profile, the bots in Studio, the phase
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
CFG_PATCH = run("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'checkEvery = 12, studio = false',1,true) "
                "if not a then return 'nopatch' end m.Source=string.sub(s,1,a-1)..'checkEvery = 12, studio = true'..string.sub(s,b+1) return 'patched'", "Edit")
P("Config.Admin.auto.studio -> true (Edit):", CFG_PATCH)
start()
# (F4: the nest appears when the firstborn grows into a teen by itself, before
# station F): the journal of the WHOLE walkthrough - the glowEgg events and all the large banners with the time since the start; F4 looks at the whole journal
def session_log():
    C("workspace:SetAttribute('GEvHook',true) workspace:SetAttribute('GEv','') workspace:SetAttribute('BANALL','') local t0=os.clock() "
      "game.ReplicatedStorage.Remotes.Notice.OnClientEvent:Connect(function(p) if type(p)=='table' and p.kind=='glowEgg' then "
      "workspace:SetAttribute('GEv',(workspace:GetAttribute('GEv') or '')..string.format(' %s@%.0f',tostring(p.ev),os.clock()-t0)) end end) "
      "task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local last='' while workspace:GetAttribute('GEvHook') do "
      "local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') "
      "local tx=(l and f.Visible) and l.Text or '' if tx~=last then last=tx if tx~='' then "
      "workspace:SetAttribute('BANALL',(workspace:GetAttribute('BANALL') or '')..string.format(' | %s@%.0f',tx,os.clock()-t0)) end end task.wait(0.05) end end) return 1")
S(f"game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','{PHASE}') task.wait(1) return '{PHASE}'")
T0 = time.time()
time.sleep(10)  # Raid.start: the spots + the Gloom models; Crowd/Admin auto
P("raid:", ld("raid")[:300])
P("the phase:", PHASE, "| the time since the start", f"{time.time() - T0:.0f} s")

# ------------------------------------------------- A the spawn in the own pen
def st_A():
    P("the walkthrough journal:", session_log())
    a = S(ME + FL + HOME + "local hs=hn and hn:FindFirstChild('HomeSpawn') local p=r.Position local look=r.CFrame.LookVector local toP=Vector3.new(P.X-p.X,0,P.Z-p.Z) toP=toP.Magnitude>0.1 and toP.Unit or look "
          "local kp=workspace:FindFirstChild('Keeper',true) local dk=kp and fl(p,kp:GetPivot().Position) or -1 "
          "return string.format('inside=%s d=%.1f face=%.2f hs=%s dKeeper=%.0f', tostring(inside(p)), fl(p,P), look:Dot(toP), tostring(hs~=nil), dk)")
    ok("A. spawned in the own pen: inside the plot, 5-14 from the gap, facing the plaza (HomeSpawn), not at the Keeper",
       "inside=true" in a and 5 <= num(a, "d", 99) <= 14 and num(a, "face", -1) >= 0.6 and "hs=true" in a and (num(a, "dKeeper", 99) < 0 or num(a, "dKeeper", 0) > 25), a)
    frame("A_spawn", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*14+Vector3.new(0,7,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*8 end)()")
station("A", st_A)

# ------------------------------------------------- B the step and the far nest
FAR = {"id": None, "pos": None}
def st_B():
    hint = wait_label("Steal an egg from the sleeping Gloom", 14)
    ok("B. from the spawn the step 'Steal an egg from the sleeping Gloom - your first dragon!'", bool(hint), hint[:140])
    b = S(ME + FL + HOME + NESTS + "local fid=me:GetAttribute('FirstNest') local m=fid and nestById(fid) if not m then return 'first=nil' end local a=m:GetAttribute('At') "
          "local ds={} for _,x in nests(0) do table.insert(ds,string.format('%s:%.0f',tostring(x:GetAttribute('NestId')),fl(x:GetAttribute('At'),P))) end "
          "local c1,c2=#nests(1),#nests(2) local g=guardOf(m) "
          "return string.format('first=%s d=%.1f at=%.2f,%.2f,%.2f egg=%s zz=%s c1=%d c2=%d all=%s', tostring(fid), fl(a,P), a.X,a.Y,a.Z, tostring(m:GetAttribute('HasEgg')), mk(g), c1, c2, table.concat(ds,'/'))")
    P("the nests:", b)
    m = re.search(r"at=(-?[\d.]+,-?[\d.]+,-?[\d.]+)", b)
    if m:
        FAR["pos"] = m.group(1); FAR["id"] = re.search(r"first=(\S+)", b).group(1)
    dists = [float(x.split(":")[1]) for x in (re.findall(r"all=(\S+)", b) or [""])[0].split("/") if ":" in x]
    ok("B1. the FAR ring 0 nest is assigned (>= 80 from the gap, the farthest of the three), the egg exists, the guard sleeps; no rings 1-2",
       FAR["pos"] is not None and num(b, "d", 0) >= 80 and dists and abs(num(b, "d", 0) - max(dists)) < 1 and "egg=true" in b and "zz=Zz" in b and num(b, "c1", 9) == 0 and num(b, "c2", 9) == 0, b)
    time.sleep(1.5)
    tr = trail()
    ok("B2. the chevron chain from the feet to the nest (>= 3) and the arrow above the target", num(tr, "trail", 0) >= 3 and "arrow=true" in tr, tr)
    hid = C("local me=game.Players.LocalPlayer local CS=game:GetService('CollectionService') local fid=me:GetAttribute('FirstNest') local vis,hid,n={}, {}, 0 "
            "for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==0 and m:GetAttribute('HasEgg')==true then local e=m:FindFirstChild('Egg') or m:FindFirstChild('Egg',true) "
            "local t=1 if e then for _,d in e:GetDescendants() do if d:IsA('BasePart') then t=math.min(t,d.LocalTransparencyModifier) end end end "
            "n+=1 if m:GetAttribute('NestId')==fid then table.insert(vis,string.format('%.0f',t)) else table.insert(hid,string.format('%.0f',t)) end end end "
            "return string.format('n=%d firstT=%s otherT=%s', n, table.concat(vis,','), table.concat(hid,','))")
    ok("B3. the newcomer sees the egg only in the assigned nest (the others have LocalTransparencyModifier 1)",
       "firstT=0" in hid and hid.count("1") >= 2 and "otherT=0" not in hid and ",0" not in hid.split("otherT=")[-1], hid)
    frame("B_first_nest", f"(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local N=Vector3.new({FAR['pos'] or '0,0,0'}) local u=Vector3.new(r.Position.X-N.X,0,r.Position.Z-N.Z).Unit return N+u*20+Vector3.new(0,9,0) end)()",
          f"Vector3.new({FAR['pos'] or '0,0,0'})+Vector3.new(0,1.5,0)")
station("B", st_B)
if not FAR["pos"]:
    ok("B. without the far nest we cannot go on", False, "FirstNest is not assigned")
    run("local m=game.ReplicatedStorage.Shared.Config m.Source=string.gsub(m.Source,'checkEvery = 12, studio = true','checkEvery = 12, studio = false') return 1", "Edit")
    stop(); write_result(f"Day 1 as a whole ({PHASE}): stopped at B"); sys.exit(1)
NP = FAR["pos"]

# ------------------------------------------------- C the near one does not give; the far one: took it and stood - CAUGHT
def st_C():
    near = S(ME + FL + HOME + NESTS + f"local fid=me:GetAttribute('FirstNest') local b,bd for _,m in nests(0) do if m:GetAttribute('NestId')~=fid and m:GetAttribute('HasEgg')==true then local d=fl(m:GetAttribute('At'),P) if not bd or d<bd then b,bd=m,d end end end "
             "if not b then return 'none' end local a=b:GetAttribute('At') local u=Vector3.new(P.X-a.X,0,P.Z-a.Z).Unit ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) task.wait(2) "
             "local d=dump() return string.format('d=%.0f carry=%s mark=%s', bd, tostring(d.eggs.carry~=nil), mk(guardOf(b)))")
    ok("C. at the near nest (the egg exists on the server) the newcomer is not given the egg, the guard sleeps", "carry=false" in near and "mark=Zz" in near, near)
    note_windows("C-near")
    # to the far nest - running across the plaza (like the player), from the gap
    S(ME + FL + HOME + "ch:PivotTo(CFrame.new(P+Vector3.new(0,4,0))) return 1"); time.sleep(0.5)
    tw = S(ME + FL + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit " + walk_code("N+u*9", "false", 14))
    P("reached the far nest in", tw, "s")
    banner_watch("RUN!", "SawRun")
    c3 = S(ME + FL + HOME + NESTS + f"local N=Vector3.new({NP}) local m=nestById(me:GetAttribute('FirstNest')) local g=guardOf(m) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit "
           "ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) local c0=os.clock() local t=0 local t0,tm,tc local L0 local ex='' while t<8 do "
           "local d=dump() local carry=d.eggs.carry if not t0 and carry and carry.raid~=nil then t0=t L0=g:GetPivot().Position end "
           "if t0 and ex=='' and mk(g)=='!' then ex='!' end "
           "if t0 and not tm and fl(g:GetPivot().Position,L0)>0.3 then tm=t end if t0 and not tc and not (d.eggs.carry and d.eggs.carry.raid~=nil) then tc=t end "
           "if tc then break end task.wait(0.05) t=os.clock()-c0 end "
           "return string.format('take=%s move=%s caught=%s mark=%s', tostring(t0), tm and string.format('%.2f',tm-t0) or 'nil', tc and string.format('%.2f',tc-t0) or 'nil', ex)")
    mv, cg = num(c3, "move"), num(c3, "caught")
    ok("C1. took it: '!' above the guard; stood - CAUGHT after 1.2 +-0.35 s (first.wake; the guard lies 2-4 studs away - catches on the first tick, the shift may be 0)",
       "take=nil" not in c3 and "mark=!" in c3 and cg is not None and 0.85 <= cg <= 1.8 and (mv is None or 0.85 <= mv <= 1.55), c3)
    ok("C2. a huge 'RUN!' on the screen", C("return tostring(workspace:GetAttribute('SawRun'))") == "true")
    time.sleep(1)
    P("the screen after the catch:", labels("CAUGHT")[:80], "|", labels("again")[:80])
    sl = "?"
    for _ in range(16):
        sl = S(ME + NESTS + "local m=nestById(me:GetAttribute('FirstNest')) return mk(guardOf(m))..' egg='..tostring(m:GetAttribute('HasEgg'))")
        if sl.startswith("Zz") and "egg=true" in sl: break
        time.sleep(0.5)
    ok("C3. the guard returned and sleeps, the egg is in the nest again (<= 8 s)", sl.startswith("Zz") and "egg=true" in sl, sl)
    time.sleep(1.5)
    re3 = S(ME + NESTS + "local d=dump() return tostring(d.eggs.carry and d.eggs.carry.raid)")
    ok("C4. stood nearby - the egg is not given at once (rearm: move 15 away)", re3 == "nil", re3)
station("C", st_C)

# ------------------------------------------------- D the second attempt: the run home, the chevrons, the edge pointer, SAFE!, the hatch
HATCH = {"at": None}
def st_D():
    S(ME + FL + HOME + f"local N=Vector3.new({NP}) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*22+Vector3.new(0,4,0))) return 1"); time.sleep(1.8)
    banner_watch("SAFE!", "SawSafe")
    S(ME + FL + HOME + NESTS + GL + f"local N=Vector3.new({NP}) local m=nestById(me:GetAttribute('FirstNest')) local g=guardOf(m) local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit workspace:SetAttribute('RaidRun',nil) task.spawn(function() "
      "ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) local w=0 while not (dump().eggs.carry or {}).raid and w<3 do task.wait(0.05) w+=0.05 end "
      "if not (dump().eggs.carry or {}).raid then workspace:SetAttribute('RaidRun','not taken') return end "
      "workspace:SetAttribute('RaidTaken',true) "  # run at once: at the far nest the guard lies on the home side 2-4 studs away, a second standing = a catch at 1.2 s
      "local c0=os.clock() local t,minG,spd,lastL,lastT=0,1e9,{},g:GetPivot().Position,0 "
      "local T=P+u*8 while t<14 do local p=r.Position if inside(p) then break end local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) "
      "local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(P.X,gl(q)+3,P.Z))) task.wait(0.1) t=os.clock()-c0 "
      "local L=g:GetPivot().Position local gp=fl(L,r.Position) if t>0.6 then minG=math.min(minG,gp) end "
      "if t-lastT>=0.5 and t>0.6 then table.insert(spd,string.format('%.1f',fl(L,lastL)/(t-lastT))) lastL,lastT=L,t elseif t<=0.6 then lastL,lastT=L,t end end "
      "local arr=t local entry=r.Position local gate1,still,run,prev=1e9,0,0,nil for k=1,40 do task.wait(0.1) local L=g:GetPivot().Position local gp=fl(L,entry) gate1=math.min(gate1,gp) "
      "if prev and fl(L,prev)<0.06 and gp<6 then run+=0.1 still=math.max(still,run) else run=0 end prev=L end "
      "local slept=false for k=1,60 do task.wait(0.2) if mk(g)=='Zz' then slept=true break end end "
      "local d=dump() local inc=d.eggs.incubating['1'] local left=inc and (inc.endsAt-os.time()) or -1 local dr=0 for _ in d.dragons do dr+=1 end "
      "workspace:SetAttribute('RaidRun',string.format('run=%.1f minGap=%.1f speeds=%s gateGap=%.1f still=%.2f slept=%s inc=%s left=%d dragons=%d home=%d carry=%s', "
      "arr,minG,table.concat(spd,','),gate1,still,tostring(slept),tostring(inc~=nil),left,dr,tonumber(d.raid and d.raid.home) or -1,tostring(d.eggs.carry~=nil))) end) return 'started'")
    for _ in range(30):
        if S("return tostring(workspace:GetAttribute('RaidTaken'))") == "true": break
        time.sleep(0.1)
    # the edge pointer first (closer than ~20 m to home the step target changes and the pointer goes out - the check at the start of the run), then
    # the chase frame and the chain; the run ~7 s
    time.sleep(0.6)
    # the edge pointer: the camera looks away from home (the target is behind)
    edge = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local N=Vector3.new({NP}) "
             "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(r.Position+Vector3.new(0,6,0), N+Vector3.new(0,2,0)) task.wait(0.35) "
             "local g=me.PlayerGui:FindFirstChild('HintEdge') local on=g and g.Enabled local d=g and g:FindFirstChild('Dist',true) local txt=d and d.Text or '' "
             "return string.format('edge=%s dist=%s', tostring(on), txt)")
    desk("D_edge_pointer")
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
    ok("D-edge. the target is behind - the edge pointer with meters (HintEdge)", "edge=true" in edge and re.search(r"\d+\s*m", edge) is not None, edge)
    # the client switches the target to the SAFE line (created by the raid take event) and builds the path not instantly; the run lasts ~7 s -
    # we take samples at 1, 2, 3, 4 s: the chain must appear in at least one of them
    samples = []
    tr = "trail=0"
    for k in range(2):  # the run ~7 s, the chase frame and the pointer are also needed with the egg in the hands - the samples every 0.7 s, not 1 s
        time.sleep(0.7)
        t_ = trail(); samples.append(f"{k + 1}:{t_}")
        if num(t_, "trail", 0) >= 3:
            tr = t_; break
    ok("D-trail. with the egg in the hands (1-4 s of the run): the chevron chain to the gap (>= 3), none on the fence, the arrow above the line", num(tr, "trail", 0) >= 3 and num(tr, "onFence", 99) == 0 and "arrow=true" in tr, " | ".join(samples)[:300])
    frame("D_chase_side",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
          "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end local a=r.Position local b=L and L:GetPivot().Position or a "
          "local mid=(a+b)/2 local ln=Vector3.new(a.X-b.X,0,a.Z-b.Z) ln=if ln.Magnitude>0.1 then ln.Unit else Vector3.xAxis return mid+Vector3.new(-ln.Z,0,ln.X)*22+Vector3.new(0,9,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do "
          "if x:GetAttribute('OwnerId')==me.UserId and x:GetAttribute('Awake') then L=x break end end return (r.Position+(L and L:GetPivot().Position or r.Position))/2 end)()")
    note_windows("D-run")
    res = "?"
    for _ in range(80):
        res = S("return tostring(workspace:GetAttribute('RaidRun'))")
        if res != "nil": break
        time.sleep(0.4)
    P("the run home:", res)
    HATCH["at"] = time.time()
    spd = [float(x) for x in (re.findall(r"speeds=([\d.,]*)", res) or [""])[0].split(",") if x]
    ok("D. the run home ~100 studs: home in 5-8 s, the guard at 0.75 speed (12 +-1.8) behind, not closer than 8",
       5 <= num(res, "run", 99) <= 8 and num(res, "minGap", 0) >= 8 and len(spd) >= 4 and all(10.2 <= v <= 13.8 for v in spd[2:]), res[:200])  # the first two windows of 0.5 s - the guard's acceleration
    ok("D1. stopped at the line (<= 6, >= 0.5 s), returned to the lair and sleeps", 0 <= num(res, "gateGap", -1) <= 6 and num(res, "still", 0) >= 0.5 and "slept=true" in res, res[-220:])
    ok("D2. at home 'SAFE!'", C("return tostring(workspace:GetAttribute('SawSafe'))") == "true")
    ok("D3. the egg in bowl 1 or already hatched; raid.home = 1; the hands are empty", ("inc=true" in res or num(res, "dragons", 0) >= 1) and num(res, "home", 0) == 1 and "carry=false" in res, res[-160:])
    hat = "?"
    for i in range(50):
        hat = S(ME + NESTS + "local d=dump() local dr=0 for _ in d.dragons do dr+=1 end local inc=d.eggs.incubating['1'] return string.format('dragons=%d inc=%s comp=%s stage=%s', dr, tostring(inc~=nil), tostring(d.companion), tostring(me and me:GetAttribute('CompanionStage')))")
        if num(hat, "dragons", 0) >= 1: break
        time.sleep(0.5)
    HATCH["at"] = time.time()
    ok("D4. the first egg hatched by itself (<= 25 s after the line), dragon 1, the companion is assigned", num(hat, "dragons", 0) >= 1 and "comp=nil" not in hat, hat + f" | waited {i * 0.5:.1f} s")
    frame("D_hatched_home", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*12+Vector3.new(0,6,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*4 end)()")
station("D", st_D)

# ------------------------------------------------- E with a dragon: the nests are silent, the Keeper, the first ambush, the Gloom is visible
def st_E():
    stp = wait_label("Sneak to the Gloom", 2)
    nxt = labels("NEXT")
    ok("E. after the first dragon the step does not call to the Gloom nests (the one-dragon day arrow)", not stp, (stp or nxt)[:140])
    q = labels("A second egg"); qb = labels("Berries")
    ok("E1. the Keeper without 'A second egg' (the day 1 step is skipped)", not q, (q or qb or "the Keeper panel is not expanded")[:120])
    # with a dragon only the own far nest (FirstNest) gives the egg - a foreign near one is silent
    lock = S(ME + FL + HOME + NESTS + "local fid=me:GetAttribute('FirstNest') local b,bd for _,m in nests(0) do if m:GetAttribute('HasEgg')==true and m:GetAttribute('NestId')~=fid then local d=fl(m:GetAttribute('At'),P) if not bd or d<bd then b,bd=m,d end end end "
             "if not b then return 'noegg' end local a=b:GetAttribute('At') local u=Vector3.new(P.X-a.X,0,P.Z-a.Z).Unit local p0=r.Position ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) task.wait(2) "
             "local d=dump() local c=tostring(d.eggs.carry~=nil) ch:PivotTo(CFrame.new(p0)) return 'carry='..c..' mark='..mk(guardOf(b))")
    hid = C("local CS=game:GetService('CollectionService') local fid=game.Players.LocalPlayer:GetAttribute('FirstNest') local t=1 local n=0 for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('HasEgg')==true and m:GetAttribute('NestId')~=fid then local e=m:FindFirstChild('Egg') or m:FindFirstChild('Egg',true) "
            "if e then n+=1 for _,d in e:GetDescendants() do if d:IsA('BasePart') then t=math.min(t,d.LocalTransparencyModifier) end end end end end return string.format('eggs=%d minT=%.0f', n, t)")
    ok("E2. with a dragon a foreign ring 0 nest does not give the egg and the client does not show it (the own one - the daily raids, dailyraid_check)", "carry=false" in lock and num(hid, "minT", 0) == 1, lock + " | " + hid)
    # the first ambush ~10 s after the hatch on the ground (Config.Combat.ambush.afterHatch)
    amb = "?"
    for _ in range(40):
        amb = ld("combat info")
        if '"meadow"' in amb and '"enemies":[{' in amb: break
        time.sleep(1)
    ok("E3. the first ambush on the ground came (<= 40 s after the hatch), a meadow wave with enemies", '"meadow"' in amb and '"enemies":[{' in amb, amb[:220])
    vis = S("local f=workspace:FindFirstChild('Gloom') if not f then return 'noGloom' end local n,hl,sh,neon,lt=0,0,0,0,0 for _,m in f:GetChildren() do if m:IsA('Model') then n+=1 "
            "if m:FindFirstChildOfClass('Highlight') then hl+=1 end local s2,nn=0,0 for _,d in m:GetDescendants() do if d:IsA('BasePart') and string.sub(d.Name,1,5)=='Glow_' then s2+=1 if d.Material==Enum.Material.Neon then nn+=1 end end "
            "if d:IsA('PointLight') then lt=math.max(lt,d.Brightness) end end if s2>0 then sh+=1 end if nn>0 then neon+=1 end end end "
            "return string.format('gloom=%d highlight=%d shells=%d neon=%d light=%.1f', n, hl, sh, neon, lt)")
    ok("E4. the Gloom is visible: every enemy has a Highlight and a neon violet shell, the light is boosted", num(vis, "gloom", 0) >= 1 and num(vis, "highlight", 0) == num(vis, "gloom", 0) and num(vis, "neon", 0) == num(vis, "gloom", 0), vis)
    frame("E_gloom_60m",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local f=workspace:FindFirstChild('Gloom') local m=f and f:FindFirstChildOfClass('Model') local g=m and m:GetPivot().Position or r.Position "
          "local u=Vector3.new(r.Position.X-g.X,0,r.Position.Z-g.Z) u=if u.Magnitude>1 then u.Unit else Vector3.xAxis return g+u*60+Vector3.new(0,10,0) end)()",
          "(function() local f=workspace:FindFirstChild('Gloom') local m=f and f:FindFirstChildOfClass('Model') return (m and m:GetPivot().Position or Vector3.zero)+Vector3.new(0,3,0) end)()")
    note_windows("E-ambush")
    P("clear:", ldr("combat clear")[:60]); time.sleep(2)
station("E", st_E)

# ------------------------------------------------- F coins -> a teen -> riding -> the golden nest
GN = {"pos": None}
def st_F():
    P("go pile:", ldr("go pile")[:40]); time.sleep(2)
    nxt = labels("NEXT"); P("the step at the pile:", nxt[:120])
    for _ in range(12):  # the gift is shown when idle (showAt ~165 s) - by the rule; we close it like the player
        w = windows()
        if "FreeGiftCard" in w:
            P("the idle gift at the pile - closing:", w, press("FreeGiftCard", "X", name="F-gift-X")); time.sleep(1.5)
            P("the windows after X:", windows())  # frame H showed the card open - we check whether it closed from the click
            break
        time.sleep(1)
    # all the glowEgg events on the client with the time - whether 'spawn' came from the server
    C("if not workspace:GetAttribute('GEvHook') then workspace:SetAttribute('GEvHook',true) workspace:SetAttribute('GEv','') "
      "game.ReplicatedStorage.Remotes.Notice.OnClientEvent:Connect(function(p) if type(p)=='table' and p.kind=='glowEgg' then "
      "workspace:SetAttribute('GEv',(workspace:GetAttribute('GEv') or '')..string.format(' %s@%.1f',tostring(p.ev),os.clock())) end end) end return 1")
    banner_watch("A GOLDEN NEST WITH A GLOWING EGG!", "SawGold", 90)  # the nest comes with the teen (stage >= 1), i.e. right after time - arm it before that
    P("time:", ldr("time 9999999")[:40])
    st = "?"
    for _ in range(40):
        st = S(ME + "return 'stage='..tostring(me:GetAttribute('CompanionStage'))")
        if "stage=1" in st or "stage=2" in st: break
        time.sleep(0.5)
    ok("F. after time the dragon is a teen (CompanionStage 1)", "stage=1" in st or "stage=2" in st, st)
    time.sleep(3)
    none = S(ME + GLOW + "return N and 'yes' or 'none'")
    P("the golden one before the first ride:", none)
    m1 = ldr("mount")
    mounted = "nil"
    for _ in range(12):
        time.sleep(0.25)
        mounted = S(ME + "return tostring(me:GetAttribute('Mounted'))")
        if mounted != "nil": break
    ok("F1. mounted in the own plot", mounted != "nil", m1[:60] + " " + mounted)
    gn = "none"
    for _ in range(45):
        gn = S(ME + GLOW + "if not N then return 'none' end return string.format('%.1f,%.1f,%.1f', N.X,N.Y,N.Z)")
        if gn != "none": break
        time.sleep(1)
    ok("F2. the golden nest appeared after the first dragon and the first ride (<= 45 s)", gn != "none", gn)
    GN["pos"] = gn if gn != "none" else None
    if not GN["pos"]: return
    g1 = S(ME + FL + HOME + GLOW + PACK + GL + "local hp=hn:GetPivot().Position "
           "local d=math.deg(math.abs(math.atan2(math.sin(math.atan2(N.Z,N.X)-math.atan2(hp.Z,hp.X)),math.cos(math.atan2(N.Z,N.X)-math.atan2(hp.Z,hp.X))))) "
           "local L=pk[1] and pk[1]:GetPivot().Position local nm=pk[1] and pk[1].PrimaryPart and pk[1].PrimaryPart:FindFirstChild('Mark') nm=nm and nm:FindFirstChild('N') nm=nm and nm.Text or '-' "
           "return string.format('r=%.1f ang=%.0f y=%.1f pack=%d lead=%.1f mark=%s name=%s path=%.0f', Vector3.new(N.X,0,N.Z).Magnitude, d, N.Y, #pk, L and fl(L,N) or -1, pk[1] and mkp(pk[1]) or '-', nm, fl(N,P))")
    ok("F3. the nest beyond the firs on the meadow (31.10): r 240-285, <= 62 deg from the plot axis, y < 12; the Gloom Warden sleeps at 5", 240 <= num(g1, "r", 0) <= 285 and num(g1, "ang", 99) <= 62 and num(g1, "y", 99) < 12 and num(g1, "pack", 0) >= 1 and 3.5 <= num(g1, "lead", 0) <= 6.5 and "mark=Zz" in g1, g1)
    for _ in range(20):
        if C("return tostring(workspace:GetAttribute('SawGold'))") == "true": break
        time.sleep(0.5)
    banall = C("return tostring(workspace:GetAttribute('BANALL'))")
    P("the walkthrough banners:", banall[:900]); P("the glowEgg events:", C("return tostring(workspace:GetAttribute('GEv'))")[:300])
    ok("F4. the banner 'A GOLDEN NEST WITH A GLOWING EGG!' and the arrow to it", C("return tostring(workspace:GetAttribute('SawGold'))") == "true" or "A GOLDEN NEST" in banall, labels("GOLDEN")[:80] + " | " + trail() + " | seen=" + C("return tostring(workspace:GetAttribute('SeenL1'))")[-200:] + " | glowEgg ev:" + C("return tostring(workspace:GetAttribute('GEv'))")[:120])
    time.sleep(2.5); trF = trail()
    ok("F5. riding in the plot the chain to the golden nest goes through the gap, not through the fence (on the fence 0, cross 0)", num(trF, "trail", 0) >= 3 and num(trF, "onFence", 99) == 0 and num(trF, "cross", 99) == 0, trF)
    frame("F_trail_from_lot", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*24+Vector3.new(0,18,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*14 end)()")
    frame("F_golden_nest", f"(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local N=Vector3.new({GN['pos']}) local u=Vector3.new(r.Position.X-N.X,0,r.Position.Z-N.Z).Unit return N+u*20+Vector3.new(0,9,0) end)()",
          f"Vector3.new({GN['pos']})+Vector3.new(0,1.5,0)")
station("F", st_F)

# ------------------------------------------------- G the golden raid riding: the dismount, D, the catch, the finish at the dragon, home, the stand
def st_G():
    if not GN["pos"]:
        ok("G. no golden nest - the station is skipped", False); return
    NPg = GN["pos"]
    wt = S(ME + FL + HOME + f"local Nv=Vector3.new({NPg}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local q=Nv+u*20 "
           "local function f(v) local n=math.floor(v+0.5) return (n<0 and 'n' or '')..tostring(math.abs(n)) end return f(q.X)..'x'..f(q.Y+6)..'x'..f(q.Z)")
    P("warp to the nest:", ldr("warp " + wt)[:60], wt)
    t0 = time.time(); off = "?"
    for _ in range(16):
        off = S(ME + "return tostring(me:GetAttribute('Mounted'))..' wait='..tostring(me:GetAttribute('GlowWait'))")
        if off.startswith("nil") and "wait=nil" not in off: break
        time.sleep(0.15)
    ok("G. riding at the golden one (closer than 35, on the ground) - jumped off (<= 1.5 s), the dragon is given point D", off.startswith("nil") and "wait=nil" not in off, f"{off}; {time.time() - t0:.1f} s")
    dp = S(ME + FL + HOME + GL + f"local Nv=Vector3.new({NPg}) local w=me:GetAttribute('GlowWait') if not w then return 'none' end "
           "local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local v=Vector3.new(w.X-Nv.X,0,w.Z-Nv.Z) local a=math.deg(math.acos(math.clamp(u:Dot(v.Unit),-1,1))) "
           "return string.format('dN=%.1f toHome=%.0f ground=%.1f', v.Magnitude, a, math.abs(w.Y-gl(w)))")
    ok("G1. point D: 22-37 from the nest toward home (<= 65 deg), on the ground", 22 <= num(dp, "dN", 0) <= 37 and num(dp, "toHome", 99) <= 65 and num(dp, "ground", 99) <= 2.5, dp)
    time.sleep(4)
    cw = S(ME + COMP + "local w=me:GetAttribute('GlowWait') if not (w and comp) then return 'none' end local q=comp:GetPivot().Position return string.format('dW=%.1f', (Vector3.new(q.X,0,q.Z)-Vector3.new(w.X,0,w.Z)).Magnitude)")
    ok("G2. the dragon reached D and stands (<= 5)", num(cw, "dW", 99) <= 5, cw)
    rm = ldr("mount")
    ok("G3. the saddle at the nest - a refusal (glow_raid)", "glow_raid" in rm, rm)
    frame("G_dragon_at_D", f"(function() local me=game.Players.LocalPlayer local N=Vector3.new({NPg}) local w=me:GetAttribute('GlowWait') or N local u=Vector3.new(w.X-N.X,0,w.Z-N.Z).Unit local mid=(N+w)/2 return mid+Vector3.new(-u.Z,0,u.X)*30+Vector3.new(0,12,0) end)()",
          f"(function() local me=game.Players.LocalPlayer local N=Vector3.new({NPg}) local w=me:GetAttribute('GlowWait') or N return (N+w)/2+Vector3.new(0,2,0) end)()")
    # took it and stood - CAUGHT
    P("glow before taking:", ld("glow")[:200]); glow_console()
    # the egg is given only after an own step (the Humanoid.MoveDirection input + a shift), not by a teleport - we stand at 12 and walk on foot
    S(ME + FL + HOME + f"local Nv=Vector3.new({NPg}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit ch:PivotTo(CFrame.new(Nv+u*12+Vector3.new(0,4,0))) return 1"); time.sleep(0.8)
    C(f"local me=game.Players.LocalPlayer local ch=me.Character local r=ch.HumanoidRootPart local Nv=Vector3.new({NPg}) local P=r.Position local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit "
      "local hum=ch:FindFirstChildOfClass('Humanoid') hum:MoveTo(Nv+u*2) return 'walk'")  # a step from the client (the server does not walk the player's character)
    c4 = S(ME + FL + HOME + GLOW + PACK + f"local Nv=Vector3.new({NPg}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit "
           "local c0=os.clock() local t=0 local t0,tm,tc local L0 local ex='' while t<9 do if not t0 and gm:GetAttribute('Empty') then t0=t L0=pk[1]:GetPivot().Position end "
           "if t0 and ex=='' and mkp(pk[1])=='!' then ex='!' end if t0 and not tm and fl(pk[1]:GetPivot().Position,L0)>0.3 then tm=t end "
           "if t0 and not tc then local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) if not (d.eggs.carry and d.eggs.carry.glow) then tc=t end end "
           "if tc then break end task.wait(0.05) t=os.clock()-c0 end return string.format('take=%s move=%s caught=%s mark=%s', tostring(t0), tm and string.format('%.2f',tm-t0) or 'nil', tc and string.format('%.2f',tc-t0) or 'nil', ex)")
    P("glow after:", ld("glow")[:200])
    ok("G4. the golden one: took it and stood - '!', the Warden moved after 0.8 +-0.3 s, CAUGHT <= 1.8 s", "take=nil" not in c4 and "mark=!" in c4 and num(c4, "move") is not None and 0.5 <= num(c4, "move", 9) <= 1.1 and num(c4, "caught") is not None and num(c4, "caught", 9) <= 1.8, c4)
    sl = "?"
    for _ in range(16):
        sl = S(ME + GLOW + PACK + "return (pk[1] and mkp(pk[1]) or '-')..' egg='..tostring(gm:FindFirstChild('Egg')~=nil)")
        if sl.startswith("Zz") and "egg=true" in sl: break
        time.sleep(0.5)
    ok("G5. the Warden went back to sleep, the egg is in the nest again", sl.startswith("Zz") and "egg=true" in sl, sl)
    S(ME + FL + HOME + f"local Nv=Vector3.new({NPg}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit ch:PivotTo(CFrame.new(Nv+u*22+Vector3.new(0,4,0))) return 1"); time.sleep(1.8)
    banner_watch("SAFE!", "SawSafe2")
    S(ME + FL + HOME + GLOW + PACK + COMP + GL + f"local Nv=Vector3.new({NPg}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit workspace:SetAttribute('GlowRun',nil) task.spawn(function() "
      "ch:PivotTo(CFrame.new(Nv+u*3+Vector3.new(0,4,0))) local w=0 while not gm:GetAttribute('Empty') and w<3 do task.wait(0.05) w+=0.05 end "
      "if not gm:GetAttribute('Empty') then workspace:SetAttribute('GlowRun','not taken') return end if not comp then workspace:SetAttribute('GlowRun','no dragon') return end "
      "local c0=os.clock() local t,minG,tM=0,1e9,nil while t<12 do local p=r.Position if me:GetAttribute('Mounted')~=nil then tM=t break end local cq=comp:GetPivot().Position "
      "local to=Vector3.new(cq.X-p.X,0,cq.Z-p.Z) if to.Magnitude>2 then local q=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(cq.X,gl(q)+3,cq.Z))) end "
      "task.wait(0.1) t=os.clock()-c0 if t>1.1 and pk[1] and pk[1].Parent then minG=math.min(minG,fl(pk[1]:GetPivot().Position,r.Position)) end end "
      "local gateD,still,run,prev=1e9,0,0,nil for k=1,40 do task.wait(0.1) if pk[1] and pk[1].Parent then local L=pk[1]:GetPivot().Position local g=fl(L,comp:GetPivot().Position) gateD=math.min(gateD,g) "
      "if prev and fl(L,prev)<0.06 and g<12 then run+=0.1 still=math.max(still,run) else run=0 end prev=L end end task.wait(2.5) "
      "local gone=0 for _,x in pk do if not x.Parent then gone+=1 end end local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
      "workspace:SetAttribute('GlowRun',string.format('mountAt=%s minGap=%.1f guardStop=%.1f still=%.2f gone=%d carry=%s mounted=%s wait=%s', tM and string.format('%.1f',tM) or 'nil', minG, gateD, still, gone, tostring(d.eggs.carry and d.eggs.carry.glow==true), tostring(me:GetAttribute('Mounted')~=nil), tostring(me:GetAttribute('GlowWait')))) end) return 'started'")
    time.sleep(0.5)  # the trail now goes from the feet only forward - at the dragon itself (the run ~1.6 s) there are almost no chevrons; measure at the start of the run
    tr = trail(); lbl = labels("your dragon")
    note_windows("G-run")
    res = "?"
    for _ in range(50):
        res = S("return tostring(workspace:GetAttribute('GlowRun'))")
        if res != "nil": break
        time.sleep(0.3)
    P("the run to the dragon:", res)
    ok("G6. the second attempt: the step 'Run to your dragon!', the chain to the dragon; reached it - mounted by itself (<= 5 s), the Warden not closer than 7.5", bool(lbl) and num(tr, "trail", 0) >= 2 and "mountAt=nil" not in res and num(res, "mountAt", 99) <= 5 and num(res, "minGap", 0) >= 7.5, res[:160] + " | " + tr)
    ok("G7. at the dragon 'SAFE!'; the Warden stopped at the dragon (<= 12), stood, melted; the egg in the hands, riding", C("return tostring(workspace:GetAttribute('SawSafe2'))") == "true" and 0 <= num(res, "guardStop", -1) <= 12 and num(res, "gone", 0) >= 1 and "carry=true" in res and "mounted=true" in res, res[-160:])
    time.sleep(1.0)
    tr2 = trail(); time.sleep(1.5); tr3 = trail()  # the path is computed not instantly: the second check 2.5 s after the mount
    ok("G8. home riding with the egg: the chain along a passable path - not a single segment through the fence (after 2.5 s: on the fence 0, cross 0)", num(tr3, "trail", 0) >= 3 and num(tr3, "onFence", 99) == 0 and num(tr3, "cross", 99) == 0, tr2 + " -> " + tr3)  # a straight trail over the meadow is not an error (frame G_ride_home_trail)
    frame("G_ride_home_trail", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*26+Vector3.new(0,16,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*12 end)()")
    P("home riding (raid home - into the plot):", ld("raid home")[:60])
    home = "?"
    for _ in range(16):
        home = S(ME + "local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
                 "local ra=d.glowEgg and tonumber(d.glowEgg.readyAt) or 0 return string.format('ped=%s carry=%s hours=%.1f wait=%s', tostring(pd~=nil), tostring(d.eggs.carry and d.eggs.carry.glow==true), (ra-os.time())/3600, tostring(me:GetAttribute('GlowWait')))")
        if "ped=true" in home and "carry=true" not in home: break
        time.sleep(0.5)
    ok("G9. at home: the stand, the egg out of the hands, the timer ~20 h, the waiting is lifted", "ped=true" in home and "carry=true" not in home and 19.5 <= num(home, "hours", 0) <= 20.5 and "wait=nil" in home, home)
station("G", st_G)

# ------------------------------------------------- H the stand: the board hidden when riding, on foot - the buttons; Warm; HatchNow glow
def st_H():
    # the 'Welcome gift' window is open - the stand board hides under it (one request at a time); the player closes it with the cross
    if gui_on("FreeGiftCard"):
        P("the gift is open at the stand - closing:", press("FreeGiftCard", "X", name="H-gift-X")); time.sleep(1.5)
    bm = C("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('GlowBoard') return 'board='..tostring(g~=nil and g.Enabled)..' mounted='..tostring(game.Players.LocalPlayer:GetAttribute('Mounted')~=nil)")
    ok("H. riding at the stand the board with buttons is hidden", "board=false" in bm or "board=nil" in bm, bm)
    P("dismount:", ldr("dismount")[:40]); time.sleep(1.5)
    if gui_on("FreeGiftCard"):
        P("the gift is open after dismounting - closing:", press("FreeGiftCard", "X", name="H-gift-X2")); time.sleep(1.5)
    S(ME + "local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] if pd then local q=pd:GetPivot().Position local d=(r.Position-q) d=Vector3.new(d.X,0,d.Z) d=if d.Magnitude>1 then d.Unit else Vector3.xAxis ch:PivotTo(CFrame.lookAt(q+d*7+Vector3.new(0,3,0),q)) end return 1")
    time.sleep(2)
    # up to 8 s
    for _ in range(16):
        if C("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('GlowBoard') local c=pg:FindFirstChild('GlowCard') return tostring(g~=nil and g.Enabled and c~=nil and c.Enabled)") == "true": break
        time.sleep(0.5)
    # the Warm / Hatch now buttons live in the side card GlowCard, the GlowBoard board - only the timer
    bd = C("local pg=game.Players.LocalPlayer.PlayerGui local g=pg:FindFirstChild('GlowBoard') if not g then return 'board=nil' end local c=pg:FindFirstChild('GlowCard') local w=c and c:FindFirstChild('Warm',true) local h=c and c:FindFirstChild('HatchNow',true) "
           "return string.format('board=%s warm=%s hatch=%s wtxt=%s htxt=%s', tostring(g.Enabled), tostring(w and w.Visible), tostring(h and h.Visible), w and w.Text or '-', h and h.Text or '-')")
    ok("H1. on foot at the stand: the board and the two buttons Warm / Hatch now are visible", "board=true" in bd and "warm=true" in bd and "hatch=true" in bd, bd)
    desk("H_pedestal_board")
    P("give:", ldr("give 100000")[:30]); time.sleep(0.8)
    before = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return string.format('ready=%d coins=%d', tonumber(d.glowEgg.readyAt) or 0, math.floor(d.coins or 0))")
    desk("H_before_warm")
    click_xy(325, 410)  # 'Cancel' of the system dialog 'Turn on Notifications' if it is on the screen (otherwise a click on the ground)
    time.sleep(1.2)
    press("GlowCard", "Warm", name="H2-press")  # a real click on the board button (a BillboardGui in PlayerGui)
    time.sleep(1.5)
    after = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return string.format('ready=%d coins=%d', tonumber(d.glowEgg.readyAt) or 0, math.floor(d.coins or 0))")
    cut = num(before, "ready", 0) - num(after, "ready", 0); paid = num(before, "coins", 0) - num(after, "coins", 0)
    ok("H2. 'Warm the egg': the timer is 1 h less (3600 +-5 s), the coins are charged (>= 1,000)", 3595 <= cut <= 3605 and paid >= 1000, f"{before} -> {after} (cut {cut:.0f}, paid {paid:.0f})")
    if not (3595 <= cut <= 3605 and paid >= 1000):
        # the probe's click on the board missed (H2 x6 with the stand code unchanged) - the mechanics itself: the same call as the Warm button
        rr = C("local r=game.ReplicatedStorage.Remotes:FindFirstChild('GlowWarm') if not r then return 'noremote' end local x=r:InvokeServer() return typeof(x)=='table' and (tostring(x.ok)..'/'..tostring(x.reason)) or tostring(x)")
        time.sleep(1.0)
        after2 = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) return string.format('ready=%d coins=%d', tonumber(d.glowEgg.readyAt) or 0, math.floor(d.coins or 0))")
        cut2 = num(after, "ready", 0) - num(after2, "ready", 0); paid2 = num(after, "coins", 0) - num(after2, "coins", 0)
        ok("H2b. warming by the server (Remote GlowWarm, like the button): -1 h, the coins are charged", 3595 <= cut2 <= 3605 and paid2 >= 1000, f"{rr} | {after} -> {after2} (cut {cut2:.0f}, paid {paid2:.0f})")
    hn = ldr("shop HatchNow glow"); P("HatchNow glow:", hn[:80])
    res = "?"
    for i in range(40):
        res = S(ME + "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) local dr=0 for _ in d.dragons do dr+=1 end local pd=game:GetService('CollectionService'):GetTagged('GlowPedestal')[1] "
                "return string.format('dragons=%d hatched=%s ped=%s inc=%s', dr, tostring(d.glowEgg and d.glowEgg.hatched), tostring(pd~=nil), tostring(d.eggs.incubating['1']~=nil))")
        if num(res, "dragons", 0) >= 2: break
        if i == 8 and "inc=true" in res:
            P("the egg is in the bowl - hatching, like the player at the bowl:", ldr("hatch 1")[:60])
        time.sleep(1)
    ok("H3. 'Hatch now' (a Studio receipt): the egg from the stand into the bowl and hatched (<= 40 s), 2 dragons, no stand", num(res, "dragons", 0) >= 2 and "ped=false" in res, res + f" | {i} s")
    frame("H_glow_hatched", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position-r.CFrame.LookVector*12+Vector3.new(0,6,0) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart return r.Position+r.CFrame.LookVector*4 end)()")
station("H", st_H)

# ------------------------------------------------- I an adult -> takeoff -> a flyover of the zones -> growth and feeding in the air -> the ceiling -> landing at home
FLY = {"ok": False}
def st_I():
    comp = S(NESTS + "local d=dump() return tostring(d.companion)")
    P("the companion:", comp)
    P("time:", ldr("time 9999999")[:30])
    st = "?"
    for _ in range(40):
        st = S(ME + "return 'stage='..tostring(me:GetAttribute('CompanionStage'))")
        if "stage=2" in st or "stage=3" in st: break
        time.sleep(0.5)
    ok("I. the dragon is an adult (CompanionStage 2)", "stage=2" in st or "stage=3" in st, st)
    P("mount:", ldr("mount")[:50]); time.sleep(1.5)
    y0 = num(S(ME + "return 'y='..string.format('%.1f', r.Position.Y)"), "y", 0)
    P("fly up:", C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') if not g then return 'noMovementGui' end g:SetAttribute('Up',true) return 'up'")[:60]); time.sleep(4)
    C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') if g then g:SetAttribute('Up',false) end return 1")
    y1 = S(ME + "return string.format('y=%.1f mounted=%s', r.Position.Y, tostring(me:GetAttribute('Mounted')~=nil))")
    ok("I1. took off (y +15 in 4 s), riding", num(y1, "y", 0) - y0 >= 15 and "mounted=true" in y1, f"y0 {y0:.1f} -> {y1}")
    if "mounted=true" not in y1: return
    # Dismount in the air - the server refuses in_air, the saddle stays
    da = C("local f=game.ReplicatedStorage:FindFirstChild('Remotes') f=f and f:FindFirstChild('Dismount') if not f then return 'noRemote' end "
           "local ok2,r=pcall(function() return f:InvokeServer() end) return tostring(ok2)..' '..tostring(r and r.ok)..'/'..tostring(r and r.reason)")
    time.sleep(0.8)
    m2 = S(ME + "return 'mounted='..tostring(me:GetAttribute('Mounted')~=nil)..string.format(' y=%.0f', r.Position.Y)")
    ok("I1d. Dismount in the air: the server refuses in_air, the rider is in the saddle (does not fall out of the sky)", "in_air" in da and "mounted=true" in m2, da + " | " + m2)
    FLY["ok"] = True
    # the flyover: a client loop - the course to the target, the height to the target (Up/Down), the journal: the saddle loss, height jerks, min/max y
    legs = "{ {150,45,0}, {0,80,-300}, {-300,50,20}, {0,150,310}, {200,170,200}, {0,235,0} }"  # the meadow, the cliffs, the baths, the summit, the islets, the ceiling above the plaza
    C("local me=game.Players.LocalPlayer local fg=me.PlayerGui:WaitForChild('Movement',5) local function cd(c) local v,a=string.match(c,'^fly (%a+)%s*(.*)$') "
      "if v=='up' or v=='down' then fg:SetAttribute(v=='up' and 'Up' or 'Down', a=='on') elseif v=='move' then local x,z=string.match(a,'^(%-?[%d%.]+),(%-?[%d%.]+)$') fg:SetAttribute('Move', x and Vector3.new(tonumber(x) or 0,0,tonumber(z) or 0) or nil) end end "
      "workspace:SetAttribute('FlyLog',nil) workspace:SetAttribute('FlyErr',nil) task.spawn(function() local okF,errF=pcall(function() local legs=" + legs + " local r=me.Character.HumanoidRootPart "
      "local lost,jerk,maxUp,maxDown,miny,maxy,n=0,0,0,0,1e9,-1e9,0 local prevY=r.Position.Y local t0=os.clock() local reached={} "
      "for i,L in legs do local T=Vector3.new(L[1],L[2],L[3]) local c0=os.clock() while os.clock()-c0<40 do local p=r.Position "
      "if me:GetAttribute('Mounted')==nil then lost+=1 break end local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) if to.Magnitude<25 and math.abs(T.Y-p.Y)<30 then table.insert(reached,i) break end "
      "if i==#legs then if to.Magnitude<40 then table.insert(reached,i) break end end "
      "cd('fly move '..string.format('%.3f,%.3f',to.Unit.X,to.Unit.Z)) cd('fly up '..(p.Y<T.Y-8 and 'on' or 'off')) cd('fly down '..(p.Y>T.Y+8 and 'on' or 'off')) "
      "workspace:SetAttribute('FlyAt',string.format('leg=%d d=%.0f pos=%.0f,%.0f,%.0f', i, to.Magnitude, p.X, p.Y, p.Z)) task.wait(0.25) local dy=r.Position.Y-prevY prevY=r.Position.Y if dy>0 then maxUp=math.max(maxUp,dy) else maxDown=math.max(maxDown,-dy) end n+=1 miny=math.min(miny,r.Position.Y) maxy=math.max(maxy,r.Position.Y) "
      "if i==#legs and -dy>12 then jerk+=1 end end if me:GetAttribute('Mounted')==nil then break end end "
      "cd('fly move 0,0') cd('fly up off') cd('fly down off') "
      "workspace:SetAttribute('FlyLog',string.format('reached=%s lost=%d jerk=%d maxUp=%.1f maxDown=%.1f miny=%.0f maxy=%.0f ticks=%d sec=%.0f', table.concat(reached,'/'), lost, jerk, maxUp, maxDown, miny, maxy, n, os.clock()-t0)) end) "
      "if not okF then workspace:SetAttribute('FlyErr',tostring(errF)) workspace:SetAttribute('FlyLog','ERR '..tostring(errF)) end end) return 1")
    time.sleep(20)
    P("growth in the air (time):", ldr("time 9999999")[:30]); time.sleep(6)
    g = S(ME + "return 'stage='..tostring(me:GetAttribute('CompanionStage'))..' mounted='..tostring(me:GetAttribute('Mounted')~=nil)")
    ok("I2. the dragon's growth in flight (an adult -> an elder) does not unseat the rider", "mounted=true" in g, g)
    P("feeding in the air:", ldr("feed")[:60]); time.sleep(3)
    f2 = S(ME + "return 'mounted='..tostring(me:GetAttribute('Mounted')~=nil)..' y='..string.format('%.0f',r.Position.Y)")
    ok("I3. feeding in the air does not unseat", "mounted=true" in f2, f2)
    note_windows("I-fly")
    desk("I_flight_mid")
    sky = "?"
    for k in range(100):
        sky = ld("combat info")
        fl_ = C("return tostring(workspace:GetAttribute('FlyLog'))")
        if fl_ != "nil": break
        if k % 10 == 0: P("the flyover is running:", C("return tostring(workspace:GetAttribute('FlyAt'))")[:80])
        time.sleep(3)
    ok("I4. no hunt in the sky (createdAt today, skyFromDay 3): no sky wave in combat info", '"sky"' not in sky, sky[:160])
    fl_ = C("return tostring(workspace:GetAttribute('FlyLog'))")
    P("the flyover:", fl_)
    reached = (re.findall(r"reached=([\d/]*)", fl_) or [""])[0]
    ok("I5. the flyover meadow -> cliffs -> baths -> summit -> islets -> ceiling: all points reached, the saddle not lost", reached.count("/") >= 5 and num(fl_, "lost", 9) == 0, fl_)
    ok("I6. at the ceiling (235) without a jerk: not a single rollback down > 12 studs per tick", num(fl_, "jerk", 9) == 0 and num(fl_, "maxy", 0) >= 200, fl_)
    desk("I_ceiling")
    # home: the course to the own gap, the descent, landing riding
    C("local me=game.Players.LocalPlayer local fg=me.PlayerGui:WaitForChild('Movement',5) local function cd(c) local v,a=string.match(c,'^fly (%a+)%s*(.*)$') "
      "if v=='up' or v=='down' then fg:SetAttribute(v=='up' and 'Up' or 'Down', a=='on') elseif v=='move' then local x,z=string.match(a,'^(%-?[%d%.]+),(%-?[%d%.]+)$') fg:SetAttribute('Move', x and Vector3.new(tonumber(x) or 0,0,tonumber(z) or 0) or nil) end end "
      "workspace:SetAttribute('FlyHome',nil) task.spawn(function() local r=me.Character.HumanoidRootPart local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
      "local T=hn:GetPivot().Position local c0=os.clock() while os.clock()-c0<60 do local p=r.Position local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) if to.Magnitude<10 then break end "
      "cd('fly move '..string.format('%.3f,%.3f',to.Unit.X,to.Unit.Z)) cd('fly down '..(p.Y>T.Y+25 and 'on' or 'off')) cd('fly up off') task.wait(0.25) end cd('fly move 0,0') "
      "cd('fly down on') local c1=os.clock() local last=r.Position.Y local stillN=0 while os.clock()-c1<25 do task.wait(0.25) if math.abs(r.Position.Y-last)<0.2 then stillN+=1 else stillN=0 end last=r.Position.Y if stillN>=6 then break end end cd('fly down off') "
      "workspace:SetAttribute('FlyHome',string.format('y=%.0f mounted=%s', r.Position.Y, tostring(me:GetAttribute('Mounted')~=nil))) end) return 1")
    fh = "nil"
    for _ in range(40):
        fh = C("return tostring(workspace:GetAttribute('FlyHome'))")
        if fh != "nil": break
        time.sleep(2.5)
    ins = S(ME + FL + HOME + "return 'inside='..tostring(inside(r.Position))..' mounted='..tostring(me:GetAttribute('Mounted')~=nil)")
    ok("I7. landed at home riding (in the plot, the saddle in place)", "inside=true" in ins and "mounted=true" in ins, fh + " | " + ins)
    ui = C("local pg=game.Players.LocalPlayer.PlayerGui local function en(n) local g=pg:FindFirstChild(n) return g and g.Enabled end local bb=0 for _,g in pg:GetChildren() do if g:IsA('BillboardGui') and g.Enabled and g.Name~='GlowBoard' and (g.Name:find('Inc') or g.Name:find('Shelf') or g.Name:find('bb')) then bb+=1 end end "
           "return string.format('board=%s pass=%s wbb=%d fly=%s', tostring(en('GlowBoard')), tostring(en('PassCard')), bb, tostring(en('Fly')))")
    ok("I8. landing at home riding: the stand board and the pass chips are hidden, the bowl/shelf buttons do not hang; Fly exists", "board=true" not in ui and "pass=true" not in ui and num(ui, "wbb", 9) == 0, ui)
    desk("I_landed_home_ui")
station("I", st_I)

# ------------------------------------------------- J the storm: the hunt is silent; the windows were silent
def st_J():
    P("dismount:", ldr("dismount")[:40]); time.sleep(1)
    st = S("local w=game.ServerStorage:FindFirstChild('WeatherDebug') if not w then return 'noWeatherDebug' end return tostring(w:Invoke('storm'))")
    time.sleep(3)
    k = S("local w=game.ServerStorage:FindFirstChild('WeatherDebug') return w and tostring(w:Invoke('state')) or 'noWeatherDebug'")
    info = ld("combat info")
    # s.waves may hold an unfinished wave of the previous ambush (enemies left) - that is not a hunt in the storm; the criterion - no new waves during the storm
    # (the profile's wavesAll does not grow) and no wave has live enemies that appeared after the storm started
    wv = (re.findall(r'"waves":(\{.*?\})[,}]', info) or ["?"])[0]
    ok("J. the storm switched on (WeatherDebug state: storm)", "storm" in k, k[:80] + " | " + st[:40] + " | waves=" + wv[:160])
    desk("J_storm")
    time.sleep(8)
    info2 = ld("combat info")
    wv2 = (re.findall(r'"waves":(\{.*?\})[,}]', info2) or ["?"])[0]
    ok("J1. after 8 s of the storm there is no new wave (wavesAll did not grow, huntIn -1)", jnum(info2, "wavesAll", -1) == jnum(info, "wavesAll", -2) and '"huntIn":-1' in info2, f"wavesAll {jnum(info, 'wavesAll', -1)} -> {jnum(info2, 'wavesAll', -1)} waves=" + wv2[:160])
    ok("J2. the asking windows / the 'favorite' banner never opened during the action", not seen_windows, "; ".join(sorted(seen_windows))[:200])
station("J", st_J)

# ------------------------------------------------- K the bots: the riders, the walkers, the avatars, the counter, the demo raid
def st_K():
    b = S("local A=require(game.ReplicatedStorage.Shared.Config).AdminUserIds or {} local adm={} for _,id in A do adm[tostring(id)]=true end "
          "local keys,dup,own,n={},0,0,0 local function scan(f) if not f then return end for _,m in f:GetDescendants() do if m:IsA('Model') and m:GetAttribute('AvatarKey')~=nil then n+=1 local k=tostring(m:GetAttribute('AvatarKey')) if keys[k] then dup+=1 end keys[k]=true for id in adm do if k:find(id,1,true) then own+=1 end end end end end "
          "scan(workspace:FindFirstChild('Bots')) scan(workspace:FindFirstChild('Crowd')) local riders=workspace:FindFirstChild('Bots') riders=riders and #riders:GetChildren() or 0 "
          "local stall for _,d in workspace:GetDescendants() do if d:IsA('Model') and (d.Name:find('Stall') or d.Name:find('stall')) then stall=d break end end "
          "local onStall=0 local cw=workspace:FindFirstChild('Crowd') if cw and stall then local sp=stall:GetPivot().Position for _,m in cw:GetChildren() do if m:IsA('Model') then local q=m:GetPivot().Position if (Vector3.new(q.X,0,q.Z)-Vector3.new(sp.X,0,sp.Z)).Magnitude<6 then onStall+=1 end end end end "
          "return string.format('avatars=%d dup=%d owner=%d riders=%d walkers=%s onStall=%d stall=%s', n, dup, own, riders, tostring(workspace:GetAttribute('Walkers')), onStall, tostring(stall and stall.Name))")
    ok("K. the bots: >= 3 riders + walkers, all avatars differ, not a single owner account, a walker not on the counter", num(b, "riders", 0) >= 3 and num(b, "walkers", 0) >= 2 and num(b, "dup", 9) == 0 and num(b, "owner", 9) == 0 and num(b, "onStall", 9) == 0, b)
    # the demo raid: a live player at the copy nest (at the plaza spawn point), we wait for '!' at the demo:1 pack and the egg at the walker
    dn = S(ME + GL + "local cw=workspace:FindFirstChild('Crowd') local dnm=cw and cw:FindFirstChild('DemoNest') local at=dnm and dnm:GetAttribute('At') if not at then return 'noDemoNest' end "
           "local q=at+Vector3.new(24,0,0) ch:PivotTo(CFrame.new(q.X,gl(q)+3,q.Z)) return string.format('demo at %.0f,%.0f,%.0f', at.X,at.Y,at.Z)")
    P("the copy nest:", dn)
    dm = "?"
    for i in range(110):
        dm = S("local CS=game:GetService('CollectionService') local st,eg='-',false for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='demo:1' then local b=g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') st=b and b.T and b.T.Text or '?' end end "
                "local cw=workspace:FindFirstChild('Crowd') if cw then for _,m in cw:GetDescendants() do if m.Name=='Egg' or m.Name=='CarryEgg' then eg=true end end end return 'mark='..st..' carry='..tostring(eg)")
        if "mark=!" in dm: break
        time.sleep(1)
    ok("K1. the demo raid at the copy nest: the demo guard '!' with a live player nearby (<= 110 s)", "mark=!" in dm, dm + f" | {i} s")
    frame("K_demo_raid", "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do if x:GetAttribute('PackKey')=='demo:1' then L=x end end local g=L and L:GetPivot().Position or r.Position return g+Vector3.new(18,10,18) end)()",
          "(function() local me=game.Players.LocalPlayer local r=me.Character.HumanoidRootPart local L for _,x in game:GetService('CollectionService'):GetTagged('GloomChase') do if x:GetAttribute('PackKey')=='demo:1' then L=x end end return (L and L:GetPivot().Position or r.Position)+Vector3.new(0,2,0) end)()")
    time.sleep(6)
    dm2 = S("local CS=game:GetService('CollectionService') local st='-' for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='demo:1' then local b=g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') st=b and b.T and b.T.Text or '?' end end return 'mark='..st")
    P("the demo guard after 6 s:", dm2)
station("K", st_K)

# ------------------------------------------------- L the console and Perf
def st_L():
    perf = ldr("perf"); P("Perf:", perf[:200])
    ok("L. the Perf line exists (FPS)", "fps" in perf, perf[:120])
    lines = console_lines()
    open(f"{OUT}/console.txt", "w").write("\n".join(lines))
    air = [l for l in lines if "dismount IN AIR" in l or "dismount_air" in l]
    bad = [l for l in lines if ("rror" in l or "[Raid]" in l or "[Combat]" in l or "[Glow]" in l or "[GlowEgg]" in l or "[Movement]" in l or "[Incubation]" in l or "[Hints]" in l or "[Crowd]" in l or "[Admin]" in l)
           and "errors 0" not in l and "TexturePack" not in l and "dismount IN AIR" not in l]
    ok("L1. not a single 'dismount IN AIR' over the whole walkthrough", not air, str(len(air)) + (" | " + air[0][:160] if air else ""))
    ok("L2. the console without game errors", not bad, str(len(bad)))
    for l in (air + bad)[-12:]: P("  ", l[:220])
station("L", st_L)

# ------------------------------------------------- end: Config back, stop
stop()
P("restore:", run("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'checkEvery = 12, studio = true',1,true) if a then m.Source=string.sub(s,1,a-1)..'checkEvery = 12, studio = false'..string.sub(s,b+1) return 'restored' end return 'nochange'", "Edit"))
write_result(f"Full day 1, phase {PHASE} (spec 27 sec. 27): stations A-L")
