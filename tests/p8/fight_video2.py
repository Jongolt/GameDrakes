#!/usr/bin/env python3
"""P8 screen recording (ddagrab 30 fps) of three fight scenes - Studio snapshots take seconds and miss the breath
projectile and the damage numbers (they live < 1 s). Scenes: A - Ember baby hits the Gloom on the meadow (real BREATH clicks every 0.6 s), B - the
Gloom Warden as a teen (bar, pulse circle), C - the Gloom in the sky. From the clips - frames at 5 fps and strips (video/*_sheet.jpg).
Run: python3 tests/p8/fight_video.py (after tools/p8/open_local.sh with the guardians branch build)."""
import json, os, re, subprocess, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("fight_video2")
from p8lib import *  # noqa: F401,F403

VID = f"{OUT}/video"; os.makedirs(VID, exist_ok=True)
def rec(name, secs):
    r = sh(f"p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\p8\\rec_run.ps1 -Name {name} -Seconds {secs}'")
    P("rec:", (r.stdout + r.stderr).strip()[-120:])
def fetch(name):
    t = ""
    for _ in range(25):
        t = sh("p8_ssh 'type C:\\p8\\cap\\rec.txt'").stdout
        if "rec done" in t: break
        time.sleep(2)
    P("rec.txt:", t.strip().replace("\r", "").replace("\n", " | ")[-200:])
    sh(f'scp "${{P8_SSH_OPTS[@]}}" "$P8_USER@$(p8_ip):C:/p8/cap/{name}.mp4" {VID}/{name}.mp4', 300)
    return os.path.exists(f"{VID}/{name}.mp4")
def ld(c): return S(LD + f"return ld('{c}')")
def combat(cmd):
    raw = S(LD + f"return ld('combat {cmd}')")
    m = re.search(r"reply=\w+/(\{.*?\}) nest=", raw) or re.search(r"reply=\w+/(\S+) nest=", raw)
    return m.group(1) if m else raw
def wave(arena="meadow"):
    try:
        return (json.loads(combat("info")).get("waves") or {}).get(arena)
    except Exception:
        return None
def day():
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def stand(pos, dist):
    x, y, z = pos
    l = (x * x + z * z) ** 0.5 or 1
    sx, sz = x - x / l * dist, z - z / l * dist
    S(f"local p=game.Players:GetPlayers()[1] local h=workspace:Raycast(Vector3.new({sx},300,{sz}),Vector3.new(0,-600,0)) "
      f"local y=(h and h.Position.Y or 2)+3 p.Character:PivotTo(CFrame.lookAt(Vector3.new({sx},y,{sz}),Vector3.new({x},y,{z}))) return 'stand'")
    time.sleep(1.0)
def cam_side(target, side, up, back):
    C(f"local c=workspace.CurrentCamera c.CameraType=Enum.CameraType.Scriptable local r=game.Players.LocalPlayer.Character.HumanoidRootPart "
      f"local t=Vector3.new({target[0]},{target[1]},{target[2]}) local f=(t-r.Position)*Vector3.new(1,0,1) f=f.Magnitude>0.1 and f.Unit or Vector3.zAxis "
      f"local rt=f:Cross(Vector3.yAxis) local mid=r.Position*0.45+t*0.55 c.CFrame=CFrame.lookAt(r.Position-f*{back}+rt*{side}+Vector3.new(0,{up},0), mid) return 'cam'")
def cam_free():
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'free'")
def breath_xy():
    t = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Combat') and game.Players.LocalPlayer.PlayerGui.Combat:FindFirstChild('Breath') "
          "if not b or not b.Visible then return 'none' end return string.format('%d,%d', b.AbsolutePosition.X+b.AbsoluteSize.X/2, b.AbsolutePosition.Y+b.AbsoluteSize.Y/2)")
    m = re.match(r"(\d+),(\d+)", t)
    return (int(m.group(1)), int(m.group(2))) if m else None
def clicks(n, every=0.6):
    xy = breath_xy()
    P("BREATH:", xy)
    for _ in range(n):
        xy = breath_xy() or xy
        if xy:
            click_xy(VX + xy[0], VY + INSET + xy[1])
        time.sleep(every)
def frames(name, fps=5):
    d = f"{VID}/{name}_f"; os.makedirs(d, exist_ok=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"{VID}/{name}.mp4", "-vf", f"crop=834:630:0:0,fps={fps}", f"{d}/%03d.jpg"])
    return sorted(os.listdir(d))

def auto_on():
    t = C("local g=game.Players.LocalPlayer.PlayerGui.Combat local b=g:FindFirstChild('Auto') local x=g:FindFirstChild('Breath') "
          "return tostring(b and b.Visible)..' '..tostring(game.Players.LocalPlayer:GetAttribute('AutoBreath'))")
    P("AUTO:", t)
    press("Combat", "AUTO", name="AUTO")
def cut(name):
    # on P8: the game view without the Studio window, compression (faster transfer), frame strip at 2 fps
    sh(f"p8_ssh 'C:\\p8\\tools\\ffmpeg.exe -y -loglevel error -i C:\\p8\\cap\\{name}.mp4 -vf crop=812:384:12:176,scale=1218:576 -c:v libx264 -preset veryfast -crf 26 -pix_fmt yuv420p -movflags +faststart C:\\p8\\cap\\{name}_v.mp4'", 300)
    sh(f"p8_ssh 'C:\\p8\\tools\\ffmpeg.exe -y -loglevel error -i C:\\p8\\cap\\{name}_v.mp4 -vf fps=2,scale=406:192,tile=4x4 -frames:v 1 C:\\p8\\cap\\{name}_sheet.jpg'", 300)
    sh(f'scp "${{P8_SSH_OPTS[@]}}" "$P8_USER@$(p8_ip):C:/p8/cap/{name}_v.mp4" "$P8_USER@$(p8_ip):C:/p8/cap/{name}_sheet.jpg" {VID}/', 600)
    P("cut:", name, os.path.exists(f"{VID}/{name}_v.mp4"))

stop(); start(); wait_world(); day()
ld("table 2"); time.sleep(0.6); ld("place 1"); time.sleep(3.5); ld("hatch 1"); time.sleep(6)
P("setcomp:", ld("setcomp ember0c")[:40]); time.sleep(3)
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ledge'"); time.sleep(4)
P("models:", S("local f=workspace:FindFirstChild('Gloom') local out={} for _,m in (f and f:GetChildren() or {}) do out[#out+1]=m.Name..'/'..tostring(m:GetAttribute('Kind'))..'/'..tostring(#m:GetDescendants()) end return table.concat(out,' ')"))
# A. baby and the shardlings
w = wave()
if w:
    e = w["enemies"][0]["pos"]
    day(); stand(e, 15); time.sleep(1.2)
    w = wave(); e = w["enemies"][0]["pos"] if w else e
    cam_side(e, 13, 7, 14); time.sleep(0.8)
    shot("V1_shardlings")
    auto_on(); time.sleep(0.3)
    rec("A_shardlings", 12); time.sleep(13.5)
    shot("V2_after_A")
cam_free()
# B. teen and the stone hounds (stage 3)
P("setcomp:", ld("setcomp ember1c")[:40]); time.sleep(3)
P("stage 2:", combat("stage 2")); time.sleep(3)
day()
S(NEST + "p.Character:PivotTo(n:GetPivot()*CFrame.new(0,3,44)) return 'ledge'"); time.sleep(3)
w = wave()
if w and w.get("enemies"):
    e = w["enemies"][0]["pos"]
    stand(e, 16); time.sleep(1.2)
    w = wave(); e = w["enemies"][0]["pos"] if w else e
    cam_side(e, 14, 8, 15); time.sleep(0.8)
    shot("V3_hounds")
    rec("B_hounds", 14); time.sleep(15.5)
    shot("V4_after_B")
cam_free()
# C. warden
P("stage 4:", combat("stage 4")); time.sleep(3)
day()
w = wave()
if w and w.get("enemies"):
    g = w["enemies"][0]["pos"]
    stand(g, 26); time.sleep(1)
    cam_side(g, 16, 10, 16); time.sleep(0.8)
    shot("V5_guardian")
    rec("C_guardian", 16); time.sleep(17.5)
    shot("V6_after_C")
cam_free()
stop()
for name in ("A_shardlings", "B_hounds", "C_guardian"):
    fetch_ok = True
    cut(name)
s.close()
