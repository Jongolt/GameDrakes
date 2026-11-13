#!/usr/bin/env python3
"""Where does the golden raid get tries=1 / rearm=true even before the first attempt (day1_walkthrough day+night: G4 take=nil).
Riding up to the golden nest, dismounting at 35 - and the ld('glow') log + the player distance to the nest every 0.5 s, for 10 s.
Then: the flight ceiling - adult, fly up 30 s: max y, rollbacks down > 12 per 0.25 s tick (I6 of the flyover in day1 did not get there).
    python3 tests/p8/glow_tries_probe.py   (after open_local)"""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glow_tries_probe")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
def ldr(c):
    return S(LD + f"local r=ld('{c}') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
GLOW = "local gm=workspace:FindFirstChild('GlowEggs') gm=gm and gm:FindFirstChild('GlowEgg_'..me.UserId) local N=gm and gm:GetAttribute('At') "
HOME = ("local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
        "P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end ")
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
BOTS = "--bots" in sys.argv  # as in day1_walkthrough: bots and walkers in Studio
if BOTS:
    P("Config.Admin.auto.studio -> true:", run("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'checkEvery = 12, studio = false',1,true) "
                                             "if not a then return 'nopatch' end m.Source=string.sub(s,1,a-1)..'checkEvery = 12, studio = true'..string.sub(s,b+1) return 'patched'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(8)
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", ldr("hatch 1")[:60]); time.sleep(8)
P("setcomp:", S(LD + "local r=ld('setcomp moss1') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
P("time:", ldr("time 9999999")[:30]); time.sleep(4)
P("mount:", ldr("mount")[:60]); time.sleep(2)
P("dismount:", ldr("dismount")[:40]); time.sleep(1)
gn = "none"
for _ in range(45):
    gn = S(ME + GLOW + "if not N then return 'none' end return string.format('%.1f,%.1f,%.1f', N.X,N.Y,N.Z)")
    if gn != "none": break
    time.sleep(1)
P("golden nest:", gn)
if gn == "none":
    stop(); write_result("glow_tries_probe: no nest"); sys.exit(1)
NP = gn
P("glow before the approach:", ld("glow")[:160])
if "--adult" in sys.argv:
    P("time (adult):", ldr("time 9999999")[:30]); time.sleep(5)
    P("stage:", S(ME + "return tostring(me:GetAttribute('CompanionStage'))"))
P("mount:", ldr("mount")[:40]); time.sleep(1.5)
wt = S(ME + HOME + f"local Nv=Vector3.new({NP}) local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit local q=Nv+u*20 "
       "local function f(v) local n=math.floor(v+0.5) return (n<0 and 'n' or '')..tostring(math.abs(n)) end return f(q.X)..'x'..f(q.Y+6)..'x'..f(q.Z)")
P("warp to the nest (20 studs):", ldr("warp " + wt)[:60], wt)
rows = []
for k in range(20):
    time.sleep(0.5)
    st = S(ME + GLOW + "local comp for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then comp=x end end "
           "local cq=comp and comp:GetPivot().Position local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
           "return string.format('dPlayer=%.1f dDragon=%.1f mounted=%s wait=%s carry=%s empty=%s', (r.Position-N).Magnitude, cq and (cq-N).Magnitude or -1, tostring(me:GetAttribute('Mounted')~=nil), tostring(me:GetAttribute('GlowWait')~=nil), tostring(d.eggs.carry and d.eggs.carry.glow), tostring(gm:GetAttribute('Empty')))")
    g = ld("glow")
    rows.append(f"{k * 0.5 + 0.5:.1f}s {st} | {g[:120]}")
    P(rows[-1])
first_try = next((r_ for r_ in rows if "tries=1" in r_), None)
ok("1. after dismounting at 35 the first attempt is not burnt by itself (tries stays 0, rearm=false, egg not in the hands)", first_try is None, first_try or rows[-1])
dmin = min(float(x) for x in re.findall(r"dPlayer=(-?[\d.]+)", "\n".join(rows)))
P("1a. player distance to the nest after dismounting:", f"min dPlayer {dmin:.1f}")
stp = S(ME + GLOW + HOME + "local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit local p0=r.Position local q=N+u*3 "
        "for k=1,8 do local p=r.Position local to=Vector3.new(q.X-p.X,0,q.Z-p.Z) if to.Magnitude<0.5 then break end local st=p+to.Unit*math.min(1.6,to.Magnitude) ch:PivotTo(CFrame.new(st.X,p.Y,st.Z)) task.wait(0.1) end "
        "local c0=os.clock() local tk while os.clock()-c0<6 do if gm:GetAttribute('Empty') then tk=os.clock()-c0 break end task.wait(0.05) end "
        "return string.format('moved=%.1f take=%s d=%.1f y=%.1f nestY=%.1f', (r.Position-p0).Magnitude, tk and string.format('%.2f',tk) or 'nil', (r.Position-gm:GetPivot().Position).Magnitude, r.Position.Y, gm:GetPivot().Position.Y)")
P("after the step:", stp, "|", ld("glow")[:160])
ok("1c. stepped to the egg himself - the egg was taken (<= 6 s after the step)", "take=nil" not in stp, stp)
desk("1_after_dismount")
# the exact day1_walkthrough sequence between dismounting and the first attempt: 4 s wait, check D, mount refusal, frame
time.sleep(4)
P("glow after 4 s:", ld("glow")[:140])
P("mount at the nest (glow_raid expected):", ldr("mount")[:60]); time.sleep(0.5)
P("glow after mount:", ld("glow")[:140])
r_ = C(f"local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local N=Vector3.new({NP}) local w=me:GetAttribute('GlowWait') or N local u=Vector3.new(w.X-N.X,0,w.Z-N.Z).Unit local mid=(N+w)/2 "
       "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(mid+Vector3.new(-u.Z,0,u.X)*30+Vector3.new(0,12,0), mid+Vector3.new(0,2,0)) return 'ok'")
time.sleep(0.5); desk("1b_frame"); C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
P("glow after the frame:", ld("glow")[:140])
time.sleep(3)
g3 = ld("glow")
P("glow 3 s after the frame:", g3[:140])
ok("1b. after the wait, the mount refusal and the frame the attempt is still not burnt (tries=0, rearm=false)", "tries=0" in g3 and "rearm=false" in g3, g3[:160])
# what GlowEgg printed (Studio-only print: pick / chase end)
cons0 = s.call("get_console_output", {"studio_id": sid}, 120)
for l in ((cons0.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines():
    if "[GlowEgg]" in l or "[Combat] pack" in l:
        P("  console:", l[:200])
# ceiling: adult, fly up 30 s
P("time:", ldr("time 9999999")[:30]); time.sleep(4)
P("dismount:", ldr("dismount")[:30]); time.sleep(1)
P("mount:", ldr("mount")[:40]); time.sleep(1.5)
C("local me=game.Players.LocalPlayer local fg=me.PlayerGui:WaitForChild('Movement',5) local function cd(c) local v,a=string.match(c,'^fly (%a+)%s*(.*)$') if v=='up' or v=='down' then fg:SetAttribute(v=='up' and 'Up' or 'Down', a=='on') end end "
  "workspace:SetAttribute('Ceil',nil) task.spawn(function() local ok,err=pcall(function() local r=me.Character.HumanoidRootPart cd('fly up on') "
  "local c0=os.clock() local prev=r.Position.Y local maxy,jerk,n=prev,0,0 while os.clock()-c0<30 do task.wait(0.25) local y=r.Position.Y if prev-y>12 then jerk+=1 end maxy=math.max(maxy,y) prev=y n+=1 "
  "if me:GetAttribute('Mounted')==nil then break end end cd('fly up off') workspace:SetAttribute('Ceil',string.format('maxy=%.0f jerk=%d ticks=%d mounted=%s', maxy, jerk, n, tostring(me:GetAttribute('Mounted')~=nil))) end) "
  "if not ok then workspace:SetAttribute('Ceil','ERR '..tostring(err)) end end) return 1")
ce = "nil"
for _ in range(40):
    ce = S("return tostring(workspace:GetAttribute('Ceil'))")
    if ce != "nil": break
    time.sleep(1)
P("ceiling:", ce)
def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t or "")
    return float(m.group(1)) if m else default
ok("2. ceiling: in 30 s of climbing reached >= 200, not a single rollback down > 12 per tick, saddle in place", num(ce, "maxy", 0) >= 200 and num(ce, "jerk", 9) == 0 and "mounted=true" in ce, ce)
desk("2_ceiling")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
air = [l for l in lines if "dismount IN AIR" in l]
ok("3. dismount IN AIR = 0", not air, str(len(air)))
if BOTS:
    stop()
    P("restore:", run("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'checkEvery = 12, studio = true',1,true) if a then m.Source=string.sub(s,1,a-1)..'checkEvery = 12, studio = false'..string.sub(s,b+1) return 'restored' end return 'nochange'", "Edit"))
else:
    stop()
write_result("Golden raid: the attempt before taking; flight ceiling")
