#!/usr/bin/env python3
"""The whole golden egg series for one player, for real - for each element Ember, Frost, Moss, Storm, Dusk, Tide:
the nest of this element (attribute and egg) -> theft -> the stand with an egg of this element, ~20 h -> 'ready' -> into the bowl -> hatched
'Glowing <element>' (glow = true). After Tide there is no new nest (the series is over). At night each of the 6 glowing ones has GlowSA on its meshes,
a close-up frame of each (the camera is held by BindToRenderStep - the game does not override it) and a general frame of the plot. Console without errors.
Slots: 3 for coins + the slot1 pass (Studio) - 7 dragons in the plot.
Run: python3 tests/p8/glowseries_all_check.py (after open_local with the glow-egg build)."""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("glowseries_all_check")
from p8lib import *  # noqa: F401,F403

SERIES = ["ember", "frost", "moss", "storm", "dusk", "tide"]
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

def frame_model(name, el):
    """Close-up of the glowing dragon of element el: the camera is held every frame (BindToRenderStep), the target - the model (it walks)"""
    r_ = C("local RS=game:GetService('RunService') local CS=game:GetService('CollectionService') local cam=workspace.CurrentCamera "
           f"local function find() for _,m in CS:GetTagged('Dragon') do if m:IsDescendantOf(workspace) and m:GetAttribute('Glow')==true and m:GetAttribute('Element')=='{el}' then return m end end end "
           "local m=find() if not m then return 'no model' end local _,sz=m:GetBoundingBox() local k=math.max(sz.X,sz.Y,sz.Z) "
           "local off=Vector3.new(1,0.55,1).Unit*(k*2.2+4) pcall(function() RS:UnbindFromRenderStep('probeCam') end) "
           "RS:BindToRenderStep('probeCam', Enum.RenderPriority.Last.Value+10, function() local mm=find() if not mm then return end local c=mm:GetBoundingBox().Position "
           "cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(c+off,c) end) return string.format('ok size=%.1f', k)")
    time.sleep(1.2)
    desk(name)
    C("pcall(function() game:GetService('RunService'):UnbindFromRenderStep('probeCam') end) workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
    P("frame", name, r_)
    return r_

# ------------------------------------------------- 0 setup: first dragon, teen, first ride, slots for 7 dragons
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
buys = C("local B=game.ReplicatedStorage:WaitForChild('Remotes'):WaitForChild('Buy') local o={} for i=1,3 do local ok,rep=pcall(function() return B:InvokeServer('slot') end) "
         "table.insert(o, ok and typeof(rep)=='table' and tostring(rep.ok)..'/'..tostring(rep.reason) or tostring(rep)) task.wait(0.5) end return table.concat(o,' ')")
P("slots for coins:", buys, "| pass:", ld("shop pass slot1")[:60])
P("mount:", ld("mount")[:60]); time.sleep(1.5)
P("dismount:", ld("dismount")[:60]); time.sleep(1)

# ------------------------------------------------- 1-6 the whole series
hatched = []
for i, el in enumerate(SERIES, 1):
    st = wait_nest(el, 40)
    ok(f"{i}.1 nest #{i}: {el} (attribute), egg {el}, n = {i}, not taken",
       "nest=true" in st and f"el={el}" in st and f"egg={el}" in st and (f"n={i}" in st or (i == 1 and "n=nil" in st)) and "taken=0" in st, st)
    if "nest=true" not in st:
        break
    NP = S(ME + NEST + "return N and string.format('%.1f,%.1f,%.1f', N.X,N.Y,N.Z) or 'none'")
    c = S(ME + NEST + "local Nv=Vector3.new(" + NP + ") local u=Vector3.new(P.X-Nv.X,0,P.Z-Nv.Z).Unit ch:PivotTo(CFrame.new(Nv+u*3+Vector3.new(0,4,0))) "
          "local t=0 while t<6 and not m:GetAttribute('Empty') do task.wait(0.05) t+=0.05 end "
          "local took=m:GetAttribute('Empty')==true if took and hb then ch:PivotTo(CFrame.new(hb.Position+Vector3.new(0,5,0))) end task.wait(0.3) "
          + DUMP + GE + "local cc=d.eggs.carry return string.format('took=%s carry=%s el=%s', tostring(took), tostring(cc and cc.element), tostring(ge.n))")
    home = "?"
    for _ in range(20):
        home = S(ME + DUMP + GE + "local pd for _,x in game:GetService('CollectionService'):GetTagged('GlowPedestal') do if x:GetAttribute('OwnerId')==me.UserId then pd=x end end "
                 "local pe for _,x in (pd and pd:GetDescendants() or {}) do if x:IsA('Model') and x:GetAttribute('Element') then pe=x:GetAttribute('Element') end end "
                 "local cc=d.eggs.carry return string.format('ped=%s pedEl=%s carry=%s hours=%.1f', tostring(pd~=nil), tostring(pe), tostring(cc and cc.glow), "
                 "((tonumber(ge.readyAt) or 0)-os.time())/3600)")
        if "ped=true" in home and "carry=nil" in home: break
        time.sleep(0.5)
    ok(f"{i}.2 stole {el} and carried it home: the stand with egg {el}, timer 19.5-20.5 h", "took=true" in c and "ped=true" in home and f"pedEl={el}" in home
       and 19.5 <= num(home, "hours", 0) <= 20.5, c + " | " + home)
    if i == len(SERIES):  # the ordinary first one - to the sanctuary
        # second run: the ordinary first one is the companion and does not go to the sanctuary ('companion'); move the already checked Glowing Ember instead
        cu = S(DUMP + "for _,x in d.dragons do if x.glow and x.element=='ember' and x.inNest then return x.uid end end return 'none'")
        P("Glowing Ember to the sanctuary:", cu, C(f"local a=game.ReplicatedStorage.Remotes.MoveDragon:InvokeServer('{cu}','sanctuary') return tostring(a and a.ok)..'/'..tostring(a and a.reason)"))
        time.sleep(1)
    P("glow ready:", ld("glow ready")[:50])
    r3 = "?"
    for _ in range(20):
        r3 = S(DUMP + GE + "local inc=d.eggs.incubating['1'] return string.format('hatched=%s inc=%s', tostring(ge.hatched), tostring(inc and inc.egg and inc.egg.element))")
        if "hatched=true" in r3: break
        time.sleep(1)
    time.sleep(4)
    P("hatch 1:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:60])
    time.sleep(3)
    dr = S(DUMP + "local o={} for _,x in d.dragons do if x.glow then table.insert(o,x.element..':'..tostring(x.name)..':'..tostring(x.inNest)) end end return 'glow='..table.concat(o,',')")
    name = "Glowing " + el.capitalize()
    ok(f"{i}.3 '{name}' hatched (glow = true) in the plot", f"{el}:{name}:true" in dr, r3 + " | " + dr)
    hatched.append(el)

time.sleep(6)
end = nest_state()
ok("7. after Tide there is no new golden nest (the series of 6 is over), n = 6", "nest=false" in end and "n=6" in end and "hatched=true" in end, end)

# ------------------------------------------------- 8 night: glow on all 6, frames
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','night') task.wait(1) return 'night'")
time.sleep(4)
g = "?"
for _ in range(15):
    g = C("local CS=game:GetService('CollectionService') local o={} for _,m in CS:GetTagged('Dragon') do if m:IsDescendantOf(workspace) and m:GetAttribute('Glow')==true then "
          "local c,t=0,0 for _,x in m:GetDescendants() do if x:IsA('MeshPart') then t+=1 if x:FindFirstChild('GlowSA') then c+=1 end end end "
          "table.insert(o, tostring(m:GetAttribute('Element'))..'='..c..'/'..t) end end table.sort(o) return table.concat(o,' ')")
    if all(re.search(rf"{el}=([1-9]\d*)/", g) for el in SERIES[1:]): break
    time.sleep(1)
# Ember went to the sanctuary before Tide (slot) - its light was checked by an earlier run
ok("8. night: GlowSA on the meshes of Frost, Moss, Storm, Dusk, Tide (Ember - in the sanctuary, checked by the previous run)", all(re.search(rf"{el}=([1-9]\d*)/", g) for el in SERIES[1:]), g)
for el in SERIES[1:]:
    frame_model(f"8_{el}_night", el)
C("local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
  "local c=hn and hn:FindFirstChild('Base') and hn.Base.Position or Vector3.zero pcall(function() game:GetService('RunService'):UnbindFromRenderStep('probeCam') end) "
  "game:GetService('RunService'):BindToRenderStep('probeCam', Enum.RenderPriority.Last.Value+10, function() cam.CameraType=Enum.CameraType.Scriptable "
  "cam.CFrame=CFrame.lookAt(c+Vector3.new(0,34,-46),c) end) return 1")
time.sleep(1.5); desk("8_all_lot_night")
C("pcall(function() game:GetService('RunService'):UnbindFromRenderStep('probeCam') end) workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 1")
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase',nil) return 1")

# ------------------------------------------------- 9 console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Glow]" in l or "[Raid]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("9. console without game errors", not bad, str(len(bad)))
for l in bad[-10:]: P("  ", l[:220])
stop()
write_result("The whole golden egg series for one player (02.11)")
