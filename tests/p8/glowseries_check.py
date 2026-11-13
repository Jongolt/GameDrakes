#!/usr/bin/env python3
"""Probe of the golden egg series by element.
0 setup: first dragon, teen, first ride - golden nest #1 (Ember, as in live before the series).
1 Ember 'hatched' (LoopDebug 'glow done', a profile like an old player without n) - nest #2 with the ELEMENT Frost: nest attribute, Frost egg
  in the nest, the banner 'A GOLDEN NEST WITH A GLOWING EGG!' again, profile n = 2, not taken.
2 theft of egg #2 (walked right up): a glowing Frost in the hands, profile n = 2 kept; home - the stand, the Frost egg, timer ~20 h.
3 'ready' (glow ready) - the egg into the bowl, 'Glowing Frost' hatched (glow = true); right away nest #3 - Moss, n = 3.
4 night: the Glowing Frost model meshes have GlowSA (bake templates of 6 elements), frame.
5 console without game errors.
Run: python3 tests/p8/glowseries_check.py (after open_local with the glow-egg build)."""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glowseries_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
NEST = ("local m=workspace:FindFirstChild('GlowEggs') m=m and m:FindFirstChild('GlowEgg_'..me.UserId) "
        "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
        "local hb=hn and hn:FindFirstChild('Base') local P if hb then local f1=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,-hb.Size.Z/2)) "
        "local f2=hb.CFrame:PointToWorldSpace(Vector3.new(0,hb.Size.Y/2,hb.Size.Z/2)) P=(Vector3.new(f2.X,0,f2.Z).Magnitude<Vector3.new(f1.X,0,f1.Z).Magnitude) and f2 or f1 end "
        "local N=m and m:GetAttribute('At') ")
DUMP = "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "
GE = "local ge=d.glowEgg or {} "

def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t)
    return float(m.group(1)) if m else default

def nest_state():
    return S(ME + NEST + DUMP + GE + "local e=m and m:FindFirstChild('Egg') "
             "return string.format('nest=%s el=%s egg=%s n=%s taken=%s hatched=%s', tostring(N~=nil), tostring(m and m:GetAttribute('Element')), "
             "tostring(e and e:GetAttribute('Element')), tostring(ge.n), tostring(ge.taken), tostring(ge.hatched))")

def wait_nest(el, secs=30):
    st = "?"
    for _ in range(secs):
        st = nest_state()
        if "nest=true" in st and f"el={el}" in st: break
        time.sleep(1)
    return st

def banner_watch():
    C("workspace:SetAttribute('SawSpawn',nil) task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local t0=os.clock() "
      "while os.clock()-t0<40 do for _,dd in pg:GetDescendants() do if dd:IsA('TextLabel') and dd.Visible and dd.Text:find('GOLDEN NEST') then "
      "workspace:SetAttribute('SawSpawn',true) return end end task.wait(0.2) end end) return 1")

# ------------------------------------------------- 0 setup (like glowraid_check): first dragon, teen, first ride
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
P("mount:", ld("mount")[:60]); time.sleep(1.5)
P("dismount:", ld("dismount")[:60]); time.sleep(1)
s0 = wait_nest("ember", 40)
ok("0. nest #1 - Ember (the old order is not broken), Ember egg in the nest, profile without n", "nest=true" in s0 and "el=ember" in s0 and "egg=ember" in s0 and "n=nil" in s0, s0)
if "nest=true" not in s0:
    stop(); write_result("Golden egg series: no nest #1"); sys.exit(1)

# ------------------------------------------------- 1 Ember 'hatched' - nest #2 Frost
banner_watch()
P("glow done:", ld("glow done")[:80])
s1 = wait_nest("frost", 20)
ok("1. after the Ember hatch - nest #2: Frost (attribute), Frost egg in the nest, n = 2, not taken", "el=frost" in s1 and "egg=frost" in s1 and "n=2" in s1 and "taken=0" in s1, s1)
time.sleep(2)
sp = C("return tostring(workspace:GetAttribute('SawSpawn'))")
ok("1a. the banner 'A GOLDEN NEST WITH A GLOWING EGG!' shown again", sp == "true", sp)
NP = S(ME + NEST + "return N and string.format('%.1f,%.1f,%.1f', N.X,N.Y,N.Z) or 'none'")
if NP != "none":
    C("local cam=workspace.CurrentCamera local N=Vector3.new(" + NP + ") cam.CameraType=Enum.CameraType.Scriptable "
      "cam.CFrame=CFrame.lookAt(N+Vector3.new(10,7,10),N+Vector3.new(0,1.5,0)) return 1")
    time.sleep(0.6); desk("1_nest2_frost")
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")

# ------------------------------------------------- 2 theft of egg #2 and home
c2 = S(ME + NEST + "local Nv=Vector3.new(" + NP + ") local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit ch:PivotTo(CFrame.new(Nv+u*3+Vector3.new(0,4,0))) "
       "local t=0 while t<6 and not m:GetAttribute('Empty') do task.wait(0.05) t+=0.05 end "
       # right after taking - to the centre of the own plot
       "local took=m:GetAttribute('Empty')==true if took and hb then ch:PivotTo(CFrame.new(hb.Position+Vector3.new(0,5,0))) end task.wait(0.3) "
       + DUMP + GE + "local c=d.eggs.carry "
       "return string.format('took=%s carry=%s el=%s n=%s ready=%s', tostring(took), tostring(c and c.glow), tostring(c and c.element), tostring(ge.n), tostring(ge.readyAt))")
ok("2. took egg #2: Frost taken (in the hands or already home on the stand), profile n = 2 kept", "took=true" in c2 and "n=2" in c2
   and (("carry=true" in c2 and "el=frost" in c2) or ("carry=nil" in c2 and "ready=0" not in c2)), c2)
home = "?"
for _ in range(20):
    home = S(ME + DUMP + GE + "local pd for _,x in game:GetService('CollectionService'):GetTagged('GlowPedestal') do if x:GetAttribute('OwnerId')==me.UserId then pd=x end end "
             "local pe for _,x in (pd and pd:GetDescendants() or {}) do if x:IsA('Model') and x:GetAttribute('Element') then pe=x:GetAttribute('Element') end end "
             "local c=d.eggs.carry return string.format('ped=%s pedEl=%s carry=%s hours=%.1f n=%s', tostring(pd~=nil), tostring(pe), tostring(c and c.glow), "
             "((tonumber(ge.readyAt) or 0)-os.time())/3600, tostring(ge.n))")
    if "ped=true" in home and "carry=nil" in home: break
    time.sleep(0.5)
ok("2a. at home: the stand with the Frost egg on it, gone from the hands, timer 19.5-20.5 h, n = 2", "ped=true" in home and "pedEl=frost" in home and "carry=nil" in home
   and 19.5 <= num(home, "hours", 0) <= 20.5 and "n=2" in home, home)

# ------------------------------------------------- 3 ready - Glowing Frost hatched, nest #3 Moss
P("glow ready:", ld("glow ready")[:60])
r3 = "?"
for _ in range(20):
    r3 = S(ME + DUMP + GE + "local inc=d.eggs.incubating['1'] return string.format('hatched=%s inc=%s', tostring(ge.hatched), tostring(inc and inc.egg and inc.egg.element))")
    if "hatched=true" in r3: break
    time.sleep(1)
ok("3. ready: the Frost egg from the stand into the bowl", "hatched=true" in r3 and "inc=frost" in r3, r3)
time.sleep(4)
P("hatch 1:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
time.sleep(3)
dr = S(DUMP + "local o={} for _,x in d.dragons do if x.glow then table.insert(o,x.element..':'..tostring(x.name)) end end return 'glow='..table.concat(o,',')")
ok("3a. 'Glowing Frost' hatched (glow = true)", "frost:Glowing Frost" in dr, dr)
s3 = wait_nest("moss", 20)
ok("3b. right away nest #3: Moss, Moss egg, n = 3", "el=moss" in s3 and "egg=moss" in s3 and "n=3" in s3, s3)

# ------------------------------------------------- 4 night: Glowing Frost glow (templates of 6 elements)
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','night') task.wait(1) return 'night'")
g4 = "?"
for _ in range(15):
    g4 = C("local me=game.Players.LocalPlayer local best,cnt,tot=nil,0,0 for _,m in game:GetService('CollectionService'):GetTagged('Dragon') do "
           "if m:IsDescendantOf(workspace) and m:GetAttribute('Glow')==true and m:GetAttribute('Element')=='frost' then local c,t=0,0 "
           "for _,x in m:GetDescendants() do if x:IsA('MeshPart') then t+=1 if x:FindFirstChild('GlowSA') then c+=1 end end end "
           "if c>=cnt then best,cnt,tot=m,c,t end end end "
           "if best then workspace:SetAttribute('GlowFrostAt',best:GetPivot().Position) end "
           "return string.format('model=%s sa=%d meshes=%d el=%s', tostring(best~=nil), cnt, tot, tostring(best and best:GetAttribute('Element')))")
    if num(g4, "sa", 0) >= 1: break
    time.sleep(1)
ok("4. night: GlowSA on the Glowing Frost model meshes (the Frost template from the 6-element bake)", "model=true" in g4 and num(g4, "sa", 0) >= 1, g4)
C("local at=workspace:GetAttribute('GlowFrostAt') if not at then return 'none' end local cam=workspace.CurrentCamera cam.CameraType=Enum.CameraType.Scriptable "
  "cam.CFrame=CFrame.lookAt(at+Vector3.new(9,6,9),at+Vector3.new(0,1.5,0)) return 1")
time.sleep(1.5); desk("4_glowing_frost_night")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase',nil) return 1")

# ------------------------------------------------- 5 console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Glow]" in l or "[Raid]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("5. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
write_result("Golden egg series by element (02.11)")
