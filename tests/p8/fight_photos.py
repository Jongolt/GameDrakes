#!/usr/bin/env python3
"""Fight frames - how it looks. Side camera (3/4) on the player, the dragon and the Gloom, real clicks on BREATH
(the game client draws the breath projectile only for its own hit), damage numbers, purification with light and petals, the warden with the bar and the pulse circle,
the Gloom in the sky from below. Purification strip frame by frame: P_purify_strip.jpg. Not a check - a shoot (checks: fight_check.py).
Run: python3 tests/p8/fight_photos.py (after tools/p8/open_local.sh with the guardians branch build)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("fight_photos")
from p8lib import *  # noqa: F401,F403


def ld(c): return S(LD + f"return ld('{c}')")
def combat(cmd):
    raw = S(LD + f"return ld('combat {cmd}')")
    m = re.search(r"reply=\w+/(\{.*?\}) nest=", raw) or re.search(r"reply=\w+/(\S+) nest=", raw)
    return m.group(1) if m else raw
def info():
    try:
        return json.loads(combat("info"))
    except Exception:
        return {}
def wave(arena="meadow"):
    return (info().get("waves") or {}).get(arena)
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def stand(pos, dist):
    """Stand on the ground dist from pos on the island centre side, facing pos"""
    x, y, z = pos
    l = (x * x + z * z) ** 0.5 or 1
    sx, sz = x - x / l * dist, z - z / l * dist
    S(f"local p=game.Players:GetPlayers()[1] local h=workspace:Raycast(Vector3.new({sx},300,{sz}),Vector3.new(0,-600,0)) "
      f"local y=(h and h.Position.Y or 2)+3 p.Character:PivotTo(CFrame.lookAt(Vector3.new({sx},y,{sz}),Vector3.new({x},y,{z}))) return 'stand'")
    time.sleep(1.0)
def cam_side(target, side=9.0, up=4.5, back=7.0):
    """Camera from the side and behind the player: the player, the dragon and the target are visible"""
    C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable local r=game.Players.LocalPlayer.Character.HumanoidRootPart "
      f"local t=Vector3.new({target[0]},{target[1]},{target[2]}) local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis "
      f"local rt=f:Cross(Vector3.yAxis) local mid=(r.Position+t)/2 c.CFrame=CFrame.lookAt(r.Position-f*{back}+rt*{side}+Vector3.new(0,{up},0), mid) return 'cam'")
def cam_free():
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'free'")
def click_breath():
    return press("Combat", "BREATH", name="BREATH")

stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
ld("table 2"); time.sleep(0.6); ld("place 1"); time.sleep(3.5); ld("hatch 1"); time.sleep(6)
P("setcomp:", ld("setcomp ember0c")[:50]); time.sleep(3)  # Ember baby on the shoulder: fire is the most visible breath colour
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ledge'"); time.sleep(3)
w = wave()
P("wave:", json.dumps(w)[:200])
# 1. the Gloom from the nest ledge: this is how a newcomer sees it
if w:
    e = w["enemies"][0]["pos"]
    C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable local r=game.Players.LocalPlayer.Character.HumanoidRootPart "
      f"local t=Vector3.new({e[0]},{e[1]},{e[2]}) local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Unit c.CFrame=CFrame.lookAt(r.Position-f*9+Vector3.new(0,6,0), t) return 'cam'")
    time.sleep(1.2)
    shot("P1_gloom_from_ledge")
    # 2-4. fight as a baby: projectile, number, purification
    stand(e, 13); time.sleep(1.5)
    w = wave()
    e = w["enemies"][0]["pos"] if w else e
    cam_side(e); time.sleep(1.0)
    shot("P2_gloom_close")
    seq = 0
    for k in range(6):
        click_breath()
        time.sleep(0.05)
        shot(f"P3_breath_{k}")
        time.sleep(0.35)
        shot(f"P4_number_{k}")
        w = wave()
        if not w or not w.get("enemies"):
            break
    # purification strip: consecutive frames right after the last hit
    for k in range(4):
        shot(f"P5_purify_{k}"); time.sleep(0.25)
cam_free()
# 5. warden
P("setcomp:", ld("setcomp ember1c")[:50]); time.sleep(3)
P("stage 4:", combat("stage 4")); time.sleep(3)
w = wave()
if w and w.get("enemies"):
    g = w["enemies"][0]["pos"]
    stand(g, 26); time.sleep(1)
    cam_side(g, side=12, up=6, back=10); time.sleep(1)
    shot("P6_guardian")
    for k in range(4):
        click_breath(); time.sleep(0.6)
    shot("P7_guardian_hit")
    # pulse circle: a warning 1.5 s before the hit, every 8 s from spawn
    for k in range(10):
        time.sleep(0.8)
        shot(f"P8_pulse_{k}")
cam_free()
# 6. the Gloom in the sky: after the warden, view from the meadow upward
combat("stage 5"); time.sleep(1)
sky = S("local Core=require(game.ReplicatedStorage.Shared.Core.Combat) local Cfg=require(game.ReplicatedStorage.Shared.Config) "
        "local x,z,y=Core.arenaXZ(Cfg.Combat,Cfg.World.nests,1,'sky') return string.format('%.0f,%.0f,%.0f',x,y,z)")
xs, ys, zs = [float(v) for v in sky.split(",")]
ld("setcomp ember2c"); time.sleep(4)
P("mount:", ld("mount")[:40]); time.sleep(2)
P("warp:", ld("warp " + f"{int(xs - 30)}x{int(ys)}x{int(zs)}".replace("-", "n"))[:60]); time.sleep(2.5)
shot("P9_sky_rider")
C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable c.CFrame=CFrame.lookAt(Vector3.new({xs - 70},{ys - 10},{zs - 30}), Vector3.new({xs},{ys},{zs})) return 'cam'")
time.sleep(1.2)
shot("P10_sky_gloom")
cam_free()
stop()
# strip
try:
    from PIL import Image
    names = [n for n in ["P2_gloom_close", "P3_breath_0", "P4_number_0", "P5_purify_0", "P5_purify_1", "P5_purify_2"] if os.path.exists(f"{OUT}/{n}.jpg")]
    ims = [Image.open(f"{OUT}/{n}.jpg") for n in names]
    if ims:
        w0, h0 = ims[0].size
        cols = 3
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (w0 * cols // 2, h0 * rows // 2), (20, 20, 24))
        for i, im in enumerate(ims):
            sheet.paste(im.resize((w0 // 2, h0 // 2)), ((i % cols) * w0 // 2, (i // cols) * h0 // 2))
        sheet.save(f"{OUT}/P_purify_strip.jpg", quality=88)
        P("strip:", f"{OUT}/P_purify_strip.jpg", names)
except Exception as ex:
    P("strip failed:", ex)
s.close()
