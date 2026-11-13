#!/usr/bin/env python3
"""The fight with the Gloom in Studio. A newcomer hatches a baby, a Gloom wave appears at the own meadow; a real click
on the BREATH button hits it (the server removes Hp), stages 1-2 as a baby, 3-4 as a teen, warden I (timer 120 s) as a teen with food x2,
after the warden - the sky wave at the adult. Checks: (1) the wave at the own arena and on land, (2) the BREATH button is visible near the Gloom and does not
overlap the Roblox jump button and the flight buttons, (3) a click on BREATH removes Hp, (4) stages 1-2 as a baby fit the spec time,
(5) warden I as a teen within the timer, reward - an egg to the shelf, (6) the sky opens after the warden, (7) console without [Combat] errors.
Frames: F1 meadow Gloom, F2 damage numbers, F3 purification, F4 warden with bar, F5 pulse circle, F6 sky Gloom, F7 buttons at 812x375.
Run: python3 tests/p8/fight_check.py (after tools/p8/open_local.sh with the guardians branch build). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("fight_check")
from p8lib import *  # noqa: F401,F403


def ld(c): return S(LD + f"return ld('{c}')")
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def combat(cmd):
    raw = S(LD + f"return ld('combat {cmd}')")
    m = re.search(r"reply=\w+/(\{.*?\}) nest=", raw) or re.search(r"reply=\w+/(\S+) nest=", raw)
    return m.group(1) if m else raw
def info():
    raw = combat("info")
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw}
def stage_now(): return str(info().get("stage"))
def coins(): return str(info().get("coins"))
def shelf(): return str(info().get("shelf"))
def face(target):  # client camera: from behind the player onto the point
    C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local t=Vector3.new({target}) "
      "local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis c.CFrame=CFrame.lookAt(r.Position-f*14+Vector3.new(0,7,0), t) return 'cam'")
def tp(x, y, z):
    S(f"local p=game.Players:GetPlayers()[1] p.Character:PivotTo(CFrame.new({x},{y},{z})) "
      "local ac=require(game.ServerScriptService.Services.AntiCheat) if ac.moved then ac.moved(p) end return 'tp'")

def near_spot(pos, dist=12):
    """A point on the ground dist studs from pos toward the island centre (where the player comes from) - stand near the Gloom, like a player following the arrow"""
    x, y, z = pos
    l = (x * x + z * z) ** 0.5 or 1
    return x - x / l * dist, z - z / l * dist
def go_near(pos, dist=12):
    x, z = near_spot(pos, dist)
    S(f"local p=game.Players:GetPlayers()[1] local h=workspace:Raycast(Vector3.new({x},300,{z}),Vector3.new(0,-600,0)) "
      f"local y=(h and h.Position.Y or 2)+3 p.Character:PivotTo(CFrame.lookAt(Vector3.new({x},y,{z}),Vector3.new({pos[0]},y,{pos[2]}))) return 'go'")
    time.sleep(1.2)
    C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local t=Vector3.new({pos[0]},{pos[1]},{pos[2]}) "
      "local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis c.CFrame=CFrame.lookAt(r.Position-f*11+Vector3.new(0,6,0), t) return 'cam'")
def fight_until(stage_target, max_s, arena="meadow"):
    """Hit, walking up to the nearest remaining Gloom, while passed stages < stage_target; seconds or None"""
    t0 = time.time()
    while time.time() - t0 < max_s:
        inf = info()
        if int(inf.get("stage") or 0) >= stage_target:
            return time.time() - t0
        w = (inf.get("waves") or {}).get(arena)
        if w and w.get("enemies"):
            go_near(w["enemies"][0]["pos"], 12 if arena == "meadow" else 8)
            C(BREATH_LOOP.replace("{n}", "8"))
            time.sleep(4.6)
        else:
            time.sleep(1)
    return None

# a hit on the nearest Gloom via the Remote (like the AUTO button), n times every 0.55 s; client aim Core/Combat.pick
BREATH_LOOP = ("local me=game.Players.LocalPlayer local Core=require(game.ReplicatedStorage.Shared.Core.Combat) local Cfg=require(game.ReplicatedStorage.Shared.Config) "
               "local r=game.ReplicatedStorage.Remotes.Breath task.spawn(function() for i=1,{n} do local root=me.Character and me.Character:FindFirstChild('HumanoidRootPart') "
               "if root then local list={} for _,m in game:GetService('CollectionService'):GetTagged('Gloom') do if (m:GetAttribute('Hp') or 0)>0 then local p=m:GetPivot().Position "
               "table.insert(list,{id=m:GetAttribute('Id'),pos={x=p.X,y=p.Y,z=p.Z}}) end end local lk=workspace.CurrentCamera.CFrame.LookVector "
               "local id=Core.pick({x=root.Position.X,y=root.Position.Y,z=root.Position.Z},{x=lk.X,y=lk.Y,z=lk.Z},list,Cfg.Combat) if id then r:FireServer(id) end end task.wait(0.55) end end) return 'loop'")

stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
P("table 2:", ld("table 2")[:60]); time.sleep(0.6)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(6)
cs = C("return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))")
ok("baby on the shoulder (CompanionStage 0)", cs == "0", cs)

# 1. the wave at the own arena: the player at the ledge of the own nest (that is how he walks to the glider stream; in Studio the character spawns on the plaza, 208 studs)
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) local ac=require(game.ServerScriptService.Services.AntiCheat) return 'ledge'")
time.sleep(1)
for _ in range(15):
    inf = info()
    if (inf.get("waves") or {}).get("meadow"):
        break
    time.sleep(1)
if not isinstance(inf, dict):
    inf = {"raw": inf}
P("combat info:", json.dumps(inf)[:400])
mw = (inf.get("waves") or {}).get("meadow")
ok("1. stage 1 wave on the meadow (3 Gloom)", bool(mw) and mw.get("stage") == 1 and len(mw.get("enemies") or []) == 3, json.dumps(mw)[:200])
c0 = mw["enemies"][0]["pos"] if mw and mw.get("enemies") else [0, 0, 0]
gy = S(f"local h=workspace:Raycast(Vector3.new({c0[0]},300,{c0[2]}),Vector3.new(0,-600,0),(function() local p=RaycastParams.new() p.FilterType=Enum.RaycastFilterType.Exclude p.FilterDescendantsInstances={{workspace.Gloom}} return p end)()) "
       "return h and string.format('%.1f %s', h.Position.Y, h.Material.Name) or 'none'")
P("ground under the Gloom:", gy)
ok("1b. land under the Gloom, not water", "Water" not in gy and gy != "none", gy)

# 2. a frame from the ledge of the own nest down onto the meadow (how the player at the glider stream sees it) and the button
cx = sum(e["pos"][0] for e in mw["enemies"]) / len(mw["enemies"]) if mw else c0[0]
cz = sum(e["pos"][2] for e in mw["enemies"]) / len(mw["enemies"]) if mw else c0[2]
C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local t=Vector3.new({cx},{c0[1]},{cz}) "
  "local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis c.CFrame=CFrame.lookAt(r.Position-f*10+Vector3.new(0,6,0), t) return 'cam'")
time.sleep(4)
shot("F1_gloom_meadow")
lay = C("local g=game.Players.LocalPlayer.PlayerGui local b=g:FindFirstChild('Combat') and g.Combat:FindFirstChild('Breath') "
        "local jb=g:FindFirstChild('TouchGui') and g.TouchGui:FindFirstChild('JumpButton',true) "
        "if not b then return 'nobtn' end local s=string.format('breath %d,%d %dx%d vis=%s', b.AbsolutePosition.X,b.AbsolutePosition.Y,b.AbsoluteSize.X,b.AbsoluteSize.Y,tostring(b.Visible)) "
        "if jb then s=s..string.format(' jump %d,%d %dx%d', jb.AbsolutePosition.X,jb.AbsolutePosition.Y,jb.AbsoluteSize.X,jb.AbsoluteSize.Y) end "
        "local mv=g:FindFirstChild('Movement') if mv then for _,n in {'Up','Down','Dismount'} do local o=mv:FindFirstChild(n) if o then s=s..string.format(' %s %d,%d %dx%d', n, o.AbsolutePosition.X,o.AbsolutePosition.Y,o.AbsoluteSize.X,o.AbsoluteSize.Y) end end end "
        "local vp=workspace.CurrentCamera.ViewportSize return s..string.format(' vp %dx%d', vp.X, vp.Y)")
P("layout:", lay)
ok("2. the BREATH button is visible near the Gloom", "vis=true" in lay, lay[:120])
def rects(t):
    out = {}
    for m in re.finditer(r"(\w+) (-?\d+),(-?\d+) (\d+)x(\d+)", t):
        out[m.group(1)] = tuple(int(m.group(i)) for i in range(2, 6))
    return out
R = rects(lay)
def overlap(a, b):
    return not (a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])
bad = [k for k in R if k not in ("breath", "vp") and "breath" in R and overlap(R["breath"], R[k])]
ok("2b. BREATH does not overlap jump and the flight buttons", "breath" in R and not bad, f"overlaps {bad}")

# 3. a real click on BREATH removes Hp (after walking up to 12 studs from the Gloom, as by the arrow)
if mw:
    go_near(mw["enemies"][0]["pos"], 12)
    time.sleep(0.8)
mw = (info().get("waves") or {}).get("meadow") or mw
hp0 = sum(e["hp"] for e in mw["enemies"]) if mw else 0
pressed = press("Combat", "BREATH", name="click BREATH")
time.sleep(1.0)
shot("F2_hit_number")
mw2 = (info().get("waves") or {}).get("meadow")
hp1 = sum(e["hp"] for e in mw2["enemies"]) if mw2 else 0
ok("3. a click on BREATH removes Gloom health (server)", pressed and (hp1 < hp0 or not mw2), f"{hp0} -> {hp1}")

# 4. stages 1-2 as a baby (walking up to the Gloom, as a player by the arrow; hits - Remote every 0.55 s, like AUTO)
c_before = coins()
t1 = fight_until(1, 40)
shot("F3_purify")
P(f"stage 1 in {t1} s, coins {c_before} -> {coins()}")
ok("4. stage 1 as a baby <= 15 s (spec: 3 s of hits + approach)", t1 is not None and t1 <= 15, f"{t1} s stage={stage_now()}")
time.sleep(3)  # the next wave after nextDelay
t2 = fight_until(2, 60)
ok("4b. stage 2 as a baby <= 30 s", t2 is not None and t2 <= 30, f"{t2} s stage={stage_now()} hits={json.dumps(info().get('hits'))}")

# 5. warden I as a teen with food
P("setcomp:", ld("setcomp ember1c")[:60]); time.sleep(3)  # Common teen: the warden time does not depend on the rarity of the hatched one
P("stage 4:", combat("stage 4")[:120]); time.sleep(2)
P("feed:", ld("feed all")[:60])
time.sleep(2.5)
inf = info()
mw = (inf.get("waves") or {}).get("meadow")
ok("5a. after stage 4 the warden is on the meadow", bool(mw) and mw.get("stage") == 5, json.dumps(mw)[:160])
P("power:", inf.get("power"))
if mw and mw.get("enemies"):
    g = mw["enemies"][0]["pos"]
    S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ledge'"); time.sleep(2)
    C(f"local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart local t=Vector3.new({g[0]},{g[1]},{g[2]}) "
      "local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis c.CFrame=CFrame.lookAt(r.Position-f*10+Vector3.new(0,5,0), t) return 'cam'")
    time.sleep(1)
    shot("F4_guardian_bar")
    eggs0 = shelf()
    go_near(g, 24); time.sleep(0.5)  # outside the pulse circle (radius 18), like an attentive player
    shot("F4_guardian_bar")
    t0 = time.time()
    C(BREATH_LOOP.replace("{n}", "12"))
    time.sleep(6.8)
    shot("F5_pulse_ring")
    tg = fight_until(5, 125)
    tg = None if tg is None else tg + (time.time() - t0 - tg)
    ok("5b. warden I as a teen without food within the 120 s timer", stage_now() == "5", f"{tg} s stage={stage_now()} hits={json.dumps(info().get('hits'))}")
    ok("5c. warden reward: an egg to the shelf", shelf() != eggs0, f"{eggs0} -> {shelf()}")

# 6. the sky after the warden
P("setcomp:", ld("setcomp ember2")[:60]); time.sleep(3)
nest_i = re.search(r"nest=(\d+)", S(LD + "return ld('state')"))
nest_i = int(nest_i.group(1)) if nest_i else 1
sky = S("local Core=require(game.ReplicatedStorage.Shared.Core.Combat) local Cfg=require(game.ReplicatedStorage.Shared.Config) "
        f"local x,z,y=Core.arenaXZ(Cfg.Combat,Cfg.World.nests,{nest_i},'sky') return string.format('%.0f,%.0f,%.0f',x,y,z)")
P("sky centre:", sky)
time.sleep(4)  # the adult companion catches up after the rebuild
P("mount:", json.dumps(ld("mount"))[:80]); time.sleep(2)
xs, ys, zs = [float(v) for v in sky.split(",")]
wp = f"{int(xs + 20)}x{int(ys)}x{int(zs + 20)}".replace("-", "n")
P("warp:", json.dumps(ld("warp " + wp))[:80]); time.sleep(2.5)
inf = info()
sw = (inf.get("waves") or {}).get("sky")
face(f"{xs},{ys},{zs}"); time.sleep(0.8)
shot("F6_gloom_sky")
ok("6. the sky is open after the warden: stage 6 wave", bool(sw) and sw.get("stage") == 6, json.dumps(sw)[:160])
shot("F7_buttons_812x375")

lines = console_lines()
errs = [l for l in lines if ("[Combat]" in l) or (re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l)]
ok("7. console without game and [Combat] errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Fight with the Gloom: wave, button, stages, warden, sky (spec 19)")
s.close()
