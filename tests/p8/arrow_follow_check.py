#!/usr/bin/env python3
"""A newcomer bot that strictly follows the arrow (does the arrow lead one way after the hatch and the growth, or dart between targets).
The client: every 0.15 s the arrow target (PlayerGui.HintArrow.Adornee) and the step line (StepBanner Line); a record at a line change or
a target shift > 12 studs; on foot - a step of 16 studs/s toward the target along the ground, riding - ClientDebug 'fly move/up/down' toward the target. Python: the player's
actions by the step line (hatch, mount, take off, feed). The result: the step tape and the DARTING - A -> B -> A within <= 25 s.
python3 tests/p8/arrow_follow_check.py [seconds=480]   (after open_local with the glow-egg build)"""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("arrow_follow_check")
from p8lib import *  # noqa: F401,F403

DUR = int(sys.argv[1]) if len(sys.argv) > 1 else 480
WATCH = r"""
local me=game.Players.LocalPlayer local pg=me.PlayerGui local CD=pg:WaitForChild('ClientDebug')
local function cd(c) local ok,r=pcall(function() return CD:Invoke(c) end) return r end
local log={} local t0=os.clock() local lastLine,lastT='#',nil local lastDir,flips=nil,0
-- 31.10: the trail direction - the center of the visible chevrons 3-14 studs from the feet
local function trailDir(r) local tf=workspace:FindFirstChild('HintTrail') if not tf then return nil end local sx,sz,n=0,0,0
  for _,pp in tf:GetDescendants() do if pp:IsA('BasePart') and pp.Transparency<0.95 then local d=Vector3.new(pp.Position.X-r.Position.X,0,pp.Position.Z-r.Position.Z)
    if d.Magnitude>3 and d.Magnitude<14 then sx+=d.X sz+=d.Z n+=1 end end end
  if n==0 then return nil end local v=Vector3.new(sx,0,sz) return if v.Magnitude>0.1 then v.Unit else nil end
local function tgtPos() local a=pg:FindFirstChild('HintArrow') local ad=a and a.Adornee if not ad then return nil end
  if ad:IsA('Model') then return ad:GetPivot().Position elseif ad:IsA('BasePart') then return ad.Position elseif ad:IsA('Attachment') then return ad.WorldPosition end return nil end
local function line() local g=pg:FindFirstChild('StepBanner') local l=g and g:FindFirstChild('Line',true) if not (g and g.Enabled and l and l.Visible) then return '' end return l.Text end
workspace:SetAttribute('FollowOn',true) workspace:SetAttribute('FollowMove',true) workspace:SetAttribute('ArrowLog','')
task.spawn(function()
 while workspace:GetAttribute('FollowOn') do
  local dt=task.wait(0.1)
  local ch=me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart')
  local T=tgtPos() local L=line() local mounted=me:GetAttribute('Mounted')~=nil
  local moved=(T~=nil)~=(lastT~=nil) or (T and lastT and (Vector3.new(T.X,0,T.Z)-Vector3.new(lastT.X,0,lastT.Z)).Magnitude>12)
  if L~=lastLine or moved then
    table.insert(log,string.format('%.1f|%s|%s|%s|%s',os.clock()-t0,L,T and string.format('%.0f,%.0f,%.0f',T.X,T.Y,T.Z) or '-',mounted and 'M' or 'F',tostring(me:GetAttribute('CompanionStage'))))
    lastLine,lastT=L,T workspace:SetAttribute('ArrowLog',table.concat(log,'\n',math.max(1,#log-400)))
  end
  local td=r and trailDir(r) or nil
  if td and lastDir and T and lastT and (Vector3.new(T.X,0,T.Z)-Vector3.new(lastT.X,0,lastT.Z)).Magnitude<1 and td:Dot(lastDir)<-0.5 then
    flips+=1 workspace:SetAttribute('TrailFlips',flips)
    table.insert(log,string.format('%.1f|TRAILFLIP %d|%s|%s|%s',os.clock()-t0,flips,string.format('%.0f,%.0f,%.0f',r.Position.X,r.Position.Y,r.Position.Z),mounted and 'M' or 'F',tostring(me:GetAttribute('CompanionStage'))))
    workspace:SetAttribute('ArrowLog',table.concat(log,'\n',math.max(1,#log-400)))
  end
  lastDir=td or lastDir
  if r and T and workspace:GetAttribute('FollowMove') then
    local flat=Vector3.new(T.X-r.Position.X,0,T.Z-r.Position.Z)
    if td and flat.Magnitude>16 then flat=td*flat.Magnitude end -- we walk along the yellow trail, like the player
    if not mounted then
      if flat.Magnitude>5 then
        local q=r.Position+flat.Unit*math.min(16*math.min(dt,0.5),flat.Magnitude)
        local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude pr.FilterDescendantsInstances={ch}
        local h=workspace:Raycast(q+Vector3.new(0,40,0),Vector3.new(0,-120,0),pr) local y=h and h.Position.Y+3 or q.Y
        ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,y,q.Z),Vector3.new(T.X,y,T.Z)))
      end
    else
      if flat.Magnitude>8 then cd(string.format('fly move %.3f,%.3f',flat.Unit.X,flat.Unit.Z)) else cd('fly move 0,0') end
      local dy=T.Y-r.Position.Y cd('fly up '..(dy>10 and 'on' or 'off')) cd('fly down '..(dy< -10 and 'on' or 'off'))
    end
  end
 end
 cd('fly move 0,0') cd('fly up off') cd('fly down off')
end) return 'watch'
"""

stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)
# the first egg - by a server run (as in dailyraid_check: the bot's client steps are rolled back by the anti-cheat); then the bot
# walks along the yellow trail by itself - the path after the hatchling hatches
LDF = "local function ld(c) return game.ServerStorage.LoopDebug:Invoke(c) end local function dump() return game:GetService('HttpService'):JSONDecode(ld('dump')) end "
FE = (LDF + "local me=game.Players:GetPlayers()[1] local ch=me.Character local r=ch.HumanoidRootPart local CS=game:GetService('CollectionService') "
      "local function fl(a,b) return (Vector3.new(a.X,0,a.Z)-Vector3.new(b.X,0,b.Z)).Magnitude end "
      "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
      "local hb=hn.Base local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) "
      "local P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 "
      "local function inside(p) local lp=hb.CFrame:PointToObjectSpace(p) return math.abs(lp.X)<=hb.Size.X/2 and math.abs(lp.Z)<=hb.Size.Z/2 end "
      "local function gl(p) local pr=RaycastParams.new() pr.FilterType=Enum.RaycastFilterType.Exclude pr.FilterDescendantsInstances={ch,workspace:FindFirstChild('Gloom'),workspace:FindFirstChild('RaidNests'),workspace:FindFirstChild('HintTrail')} "
      "local h=workspace:Raycast(p+Vector3.new(0,30,0),Vector3.new(0,-80,0),pr) return h and h.Position.Y or p.Y end "
      "local fid=me:GetAttribute('FirstNest') local N for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('NestId')==fid then N=m:GetAttribute('At') end end "
      "if not N then return 'nofirst' end local u=Vector3.new(P.X-N.X,0,P.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) "
      "local w=0 while not ch:FindFirstChild('CarriedEgg') and w<4 do task.wait(0.05) w+=0.05 end if not ch:FindFirstChild('CarriedEgg') then return 'notaken' end "
      "task.wait(0.3) local T=P+u*8 local t,dt=0,0.1 local c0=os.clock() while t<14 do local p=r.Position if inside(p) then break end local to=Vector3.new(T.X-p.X,0,T.Z-p.Z) "
      "local q=p+to.Unit*math.min(16*math.min(dt,0.2),to.Magnitude) ch:PivotTo(CFrame.lookAt(Vector3.new(q.X,gl(q)+3,q.Z),Vector3.new(P.X,gl(q)+3,P.Z))) dt=task.wait(0.1) t=os.clock()-c0 end "
      "task.wait(5) local d=dump() local n=0 for _ in d.dragons do n+=1 end return 'home='..tostring(d.raid and d.raid.home)..' dragons='..n")
fe = "?"
for _ in range(4):
    fe = S(FE); P("the first egg (by the server):", fe)
    if "dragons=1" in fe: break
    time.sleep(18)
P("watch:", C(WATCH))
t0 = time.time(); acted = {}; last_shot = 0; up_until = 0
def act(tag, fn, every=6):
    if time.time() - acted.get(tag, 0) >= every:
        acted[tag] = time.time(); P(f"[{time.time()-t0:5.0f} s] action {tag}:", str(fn())[:80])
while time.time() - t0 < DUR:
    ln = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('StepBanner') local l=g and g:FindFirstChild('Line',true) return l and l.Text or ''")
    lo = ln.lower()
    if "hatch" in lo and "tap" in lo:
        act("hatch", lambda: C(CD + "local ok,r=pcall(cd,'hatchcall 1') return tostring(r)"))
    elif "ride" in lo and ("tap" in lo or "hop" in lo):
        act("mount", lambda: C(CD + "local ok,r=pcall(cd,'mount') return tostring(r)"))
    elif "take off" in lo or ("fly" in lo and "tap" in lo):
        if time.time() > up_until:
            up_until = time.time() + 4
            act("takeoff", lambda: C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') if g then g:SetAttribute('Up',true) task.delay(3,function() g:SetAttribute('Up',false) end) end return 'up'"), 8)
    elif "feed" in lo and ("tap" in lo or "berr" not in lo):
        act("feed", lambda: C(CD + "local ok,r=pcall(cd,'feedcall all') return tostring(r)"), 15)
    if time.time() - last_shot > 45:
        last_shot = time.time(); desk(f"t{int(time.time()-t0):03d}")
    time.sleep(1)
C("workspace:SetAttribute('FollowOn',false) return 1")
time.sleep(0.5)
raw = C("return tostring(workspace:GetAttribute('ArrowLog'))")
ev = []
for row in raw.split("\n"):
    if "TRAILFLIP" in row:
        P("  the trail reversal:", row); continue
    p = row.split("|")
    if len(p) >= 5:
        ev.append((float(p[0]), p[1], p[2], p[3], p[4]))
P("TAPE (s | step line | arrow target | M riding/F on foot | stage):")
for e in ev: P(f"  {e[0]:6.1f} | {e[1][:60]:60} | {e[2]:>14} | {e[3]} | {e[4]}")
def near(a, b):
    if a == "-" or b == "-": return a == b
    pa = [float(x) for x in a.split(",")]; pb = [float(x) for x in b.split(",")]
    return ((pa[0]-pb[0])**2 + (pa[2]-pb[2])**2) ** 0.5 < 12
flips = []
for i in range(2, len(ev)):
    a, b, c = ev[i-2], ev[i-1], ev[i]
    if c[0] - a[0] <= 25 and (a[1] == c[1] and near(a[2], c[2])) and not (b[1] == a[1] and near(b[2], a[2])):
        flips.append((a, b, c))
P(f"DARTING (A -> B -> A within <= 25 s): {len(flips)}")
for a, b, c in flips: P(f"  {a[0]:.0f}-{c[0]:.0f} s: '{a[1][:40]}' {a[2]} -> '{b[1][:40]}' {b[2]} -> back")
ok("no arrow darting (A -> B -> A within <= 25 s)", not flips, str(len(flips)))
tf = C("return tostring(workspace:GetAttribute('TrailFlips') or 0)")
ok("the chevron trail does not reverse at the same target", tf == "0", tf)
d = S("local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) local dr=0 for _ in d.dragons do dr+=1 end "
      "local on={} for k,v in (d.analytics and d.analytics.onboard or {}) do table.insert(on,k..'='..(v-d.createdAt)) end "
      "return string.format('dragons=%d raid=%s glow=%s onboard=%s', dr, tostring(d.raid and d.raid.home), tostring(d.glowEgg and d.glowEgg.taken), table.concat(on,' '))")
P("the profile result:", d)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Hints]" in l or "[Raid]" in l or "[Glow" in l) and "TexturePack" not in l and "errors 0" not in l]
ok("the console without game errors", not bad, str(len(bad)))
for l in bad[-8:]: P("  ", l[:200])
stop()
write_result("A newcomer follows the arrow: the step tape and the darting")
