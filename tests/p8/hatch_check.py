#!/usr/bin/env python3
"""Acceptance of the hatch scene (Core/HatchFx, client HatchScene) in a LOCAL file on P8 (after open_local.sh).
Four hatches of a newcomer: 1) the first Common - the full scene (camera, Blur, HUD hidden < 5 s), 2) the second Common - a short 1.5 s
(does not touch the camera and HUD), 3) Legendary - full + the element sky and light, a pillar, confetti after the camera returns, 4) Mythic - the egg
rises. On the client a state trace every 0.1 s (camera, HUD, Blur, the egg copy and its tilt/height, shell, confetti,
ColorCorrection), on the server - the egg in the bowl stays until the crack; screen recording (ddagrab 30 fps) of each scene -> frames; console.
Run: python3 tests/p8/hatch_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("hatch_check")
from p8lib import *  # noqa: F401,F403

VID = f"{OUT}/video"; os.makedirs(VID, exist_ok=True)
def rec(name, secs):
    r = sh(f"p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\p8\\rec_run.ps1 -Name {name} -Seconds {secs}'")
    P("rec:", (r.stdout + r.stderr).strip()[-120:])
def fetch(name):
    for _ in range(20):
        t = sh("p8_ssh 'type C:\\p8\\cap\\rec.txt'").stdout
        if "rec done" in t: break
        time.sleep(2)
    P("rec.txt:", t.strip().replace("\r", "").replace("\n", " | ")[-200:])
    sh(f'scp "${{P8_SSH_OPTS[@]}}" "$P8_USER@$(p8_ip):C:/p8/cap/{name}.mp4" {VID}/{name}.mp4', 300)
    return os.path.exists(f"{VID}/{name}.mp4")

# client trace: waits for the egg copy (= arrival of the hatch event), then 0.1 s x 95; the result in the HatchTrace StringValue (client only)
TRACE = r"""
local me=game.Players.LocalPlayer local L=game:GetService('Lighting') local HS=game:GetService('HttpService')
local old=game.ReplicatedStorage:FindFirstChild('HatchTrace') if old then old:Destroy() end
local sv=Instance.new('StringValue') sv.Name='HatchTrace' sv.Value='' sv.Parent=game.ReplicatedStorage
local born={} local bc=workspace.DescendantAdded:Connect(function(d) if d:IsA('Model') and d:GetAttribute('Uid') and d:GetAttribute('OwnerId')==me.UserId then table.insert(born,d) end end)
local function lbl() local n,u=0,{} for _,m in born do if m.Parent then for _,b in m:GetDescendants() do if b:IsA('BillboardGui') and b.Enabled then n+=1 u[m:GetAttribute('Uid')]=1 break end end end end return n,u end
local function vis() local n,u=0,{} for _,m in born do if m.Parent then for _,b in m:GetDescendants() do if b:IsA('BasePart') and b.LocalTransparencyModifier<1 and b.Transparency<1 then n+=1 u[m:GetAttribute('Uid')]=1 break end end end end return n,u end
task.spawn(function()
  local t0=os.clock() local start=nil
  while os.clock()-t0<25 do if workspace:FindFirstChild('HatchEggLocal') then start=os.clock() break end task.wait() end
  if not start then sv.Value='noegg' return end
  local rows={} local y0=nil
  for i=0,95 do
    local e=workspace:FindFirstChild('HatchEggLocal') local tilt,h=-1,-1
    if e then local cf,sz=e:GetBoundingBox() local pv=e:GetPivot() tilt=math.deg(math.acos(math.clamp(pv.UpVector.Y,-1,1))) h=cf.Position.Y-sz.Y/2 y0=y0 or h end
    local wedges,conf=0,0
    for _,c in workspace:GetChildren() do if c:IsA('WedgePart') then wedges+=1 elseif c:IsA('Part') and c.Material==Enum.Material.Neon and math.abs(c.Size.Y-0.06)<0.01 then conf+=1 end end
    local bl=0 for _,b in L:GetChildren() do if b:IsA('BlurEffect') then bl=math.max(bl,b.Size) end end
    local dof=L:FindFirstChild('HatchFocus') local cc=L:FindFirstChild('HatchLegend')
    local hud=me.PlayerGui:FindFirstChild('HUD') local qg=me.PlayerGui:FindFirstChild('Quests') local vn,vu=vis() local ln,lu=lbl()
    table.insert(rows,{t=math.floor((os.clock()-start)*100)/100, cam=workspace.CurrentCamera.CameraType.Name, hud=hud and hud.Enabled or false,
      blur=math.floor(bl), dof=dof and math.floor(dof.FarIntensity*100)/100 or -1, vis=vn, visu=vu, quests=qg and qg.Enabled or false, lbl=ln, lblu=lu, born=#born, egg=e~=nil, tilt=math.floor(tilt*10)/10, lift=(e and y0) and math.floor((h-y0)*100)/100 or 0,
      wedges=wedges, conf=conf, cc=cc and math.floor(cc.TintColor.G*100)/100 or -1, pillar=workspace:FindFirstChild('HatchPillar')~=nil})
    task.wait(0.1)
  end
  bc:Disconnect() sv.Value=HS:JSONEncode(rows)
end)
return 'armed'
"""
def trace():
    for _ in range(40):
        v = C("local v=game.ReplicatedStorage:FindFirstChild('HatchTrace') return v and v.Value or 'none'")
        if v not in ("", "none"): return v
        time.sleep(1)
    return "timeout"

def scenario(tag, zone, rarity, pre=""):
    P(f"---------------- {tag}: {zone} {rarity}")
    S(LD + f"return ld('give egg {zone} {rarity}')"); time.sleep(0.6)
    S(LD + "return ld('go inc')"); time.sleep(2.5)
    inc = (dump().get("eggs", {}).get("incubating") or {})
    ok(f"{tag}: egg {rarity} in bowl 1", "1" in inc and inc["1"]["egg"]["rarity"] == rarity, json.dumps(inc)[:160])
    S(LD + "return ld('time 9999999')"); time.sleep(4)  # growth banners calm down before recording
    C("local h=game.Players.LocalPlayer.Character.Humanoid h:MoveTo(h.Parent.HumanoidRootPart.Position) return 'ok'")
    # the camera as in the game: behind the player, looking at the bowl (after the go inc teleport it looked at the sky)
    bowl = S(MYNEST + "local p=n.Incubators.Incubator1.Position return string.format('%.2f,%.2f,%.2f',p.X,p.Y,p.Z)")
    C("local cam=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart.Position local b=Vector3.new(%s) "
      "local d=Vector3.new(r.X-b.X,0,r.Z-b.Z).Unit cam.CFrame=CFrame.lookAt(r+d*11+Vector3.new(0,7,0), b) return 'cam'" % bowl)
    time.sleep(0.5)
    rec(tag, 13); time.sleep(3.5)
    before = set((dump().get("dragons") or {}).keys())
    C(TRACE)
    hz = S(LD + "return ld('hatch 1')")
    held = S(MYNEST + "local r=n.Incubators.Incubator1 return tostring(r:FindFirstChild('HatchingEgg')~=nil)..' '..tostring(r:FindFirstChild('IncEgg')~=nil)")
    time.sleep(2.6)
    gone = S(MYNEST + "return tostring(n.Incubators.Incubator1:FindFirstChild('HatchingEgg')~=nil)")
    ok(f"{tag}: the server keeps the egg in the bowl until the crack (HatchingEgg), after 2.6 s it is gone", held.startswith("true false") and gone == "false", f"{hz[:60]} | {held} -> {gone}")
    tr = trace()
    open(f"{OUT}/trace_{tag}.json", "w").write(tr)
    try:
        rows = json.loads(tr)
    except Exception:
        ok(f"{tag}: trace", False, tr[:200]); return None
    fetch(tag)
    new = [u for u in (dump().get("dragons") or {}).keys() if u not in before]
    if new:
        uid = new[0]
        cr = {"short_second": 0.45}.get(tag, 1.1)
        vb = any(uid in (r.get("visu") or {}) for r in rows if r["t"] < cr)
        lb = any(uid in (r.get("lblu") or {}) for r in rows if r["t"] < cr)
        va = any(uid in (r.get("visu") or {}) for r in rows if cr + 0.3 < r["t"] < 4)
        ok(f"{tag}: the new baby {uid} and its label are hidden until the crack, visible after", not vb and not lb and va, f"visible before {vb}, label before {lb}, after {va}")
    return rows

def span(rows, key, val):
    ts = [r["t"] for r in rows if r[key] == val]
    return (min(ts), max(ts)) if ts else (None, None)

MYNEST = ("local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do if r:GetAttribute('OwnerId')==game.Players:GetPlayers()[1].UserId then n=r.Parent.Parent end end ")

# P8: recording scripts in place
P(tool("push_win.sh").stdout.strip())

stop(); start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
# the first egg goes into the bowl and hatches by itself (Config.Loop.firstEgg) - the scene trace needs a manual path; auto - tests/p8/firstegg_check.py
P("firstegg:", S(LD + "return ld('firstegg off')")[:40])

# 1) the first hatch: full scene
rows = scenario("full_first", "Meadow", "Common")
if rows:
    sc = [r for r in rows if r["t"] < 2.88]  # scene window (total 2.9); from 2.9 the name dialog holds the camera, HUD and its own Blur (02 §2 0:13)
    c0, c1 = span(sc, "cam", "Scriptable"); h0, h1 = span(sc, "hud", False); e0, e1 = span(rows, "egg", True)
    v_before = max([r["vis"] for r in rows if r["t"] < 1.15] or [0]); v_after = max([r["vis"] for r in rows if 1.4 < r["t"] < 2.9] or [0])
    ok("full: the baby is not visible until the crack, visible after the bounce", v_before == 0 and v_after >= 1, f"before {v_before}, after {v_after}, models {max(r['born'] for r in rows)}")
    l_before = max([r["lbl"] for r in rows if r["t"] < 1.15] or [0]); l_after = max([r["lbl"] for r in rows if 1.4 < r["t"] < 2.9] or [0])
    ok("full: the label above the baby (rarity) is off until the crack", l_before == 0, f"before {l_before}, after {l_after}")
    maxtilt = max(r["tilt"] for r in rows if r["egg"]) if any(r["egg"] for r in rows) else -1
    early_tilt = max([r["tilt"] for r in rows if r["egg"] and r["t"] <= 0.35] or [0])
    w = max(r["wedges"] for r in rows)
    P("full_first: camera", c0, c1, "HUD hidden", h0, h1, "egg", e0, e1, "tilt max", maxtilt, "at start", early_tilt, "shells", w)
    ok("full: Scriptable camera ~2.6 s (less than 5 s)", c1 is not None and 2.2 <= c1 - c0 <= 3.0, f"{c0}-{c1}")
    ok("full: HUD hidden for the scene", h1 is not None and h0 <= 0.1 and 2.4 <= h1 <= 3.0, f"{h0}-{h1}")
    q0, q1 = span(sc, "quests", False)
    ok("full: the quest panel hidden for the scene and came back", q1 is not None and q0 <= 0.1 and 2.4 <= q1 <= 3.0 and any(r["quests"] for r in rows if 2.9 <= r["t"] < 3.0 or r["t"] > 9), f"{q0}-{q1}")
    ok("full: the egg rocks until the crack ~1.1 s, the amplitude grows", e1 is not None and 0.9 <= e1 <= 1.2 and maxtilt >= 4 and early_tilt < maxtilt / 2, f"egg {e0}-{e1} tilt {early_tilt}->{maxtilt}")
    ok("full: the shell flies apart (wedges) and disappears", w >= 8 and rows[-1]["wedges"] == 0, f"max {w}, end {rows[-1]['wedges']}")
    d_on = [r["t"] for r in rows if r["dof"] >= 0.5]
    ok("full: the background is blurred by depth of field (not Blur), removed after the scene", d_on and min(d_on) <= 0.6 and max(d_on) <= 2.95 and all(r["dof"] == -1 for r in rows if r["t"] > 3.0) and max(r["blur"] for r in sc) == 0, f"dof {d_on[:1]}..{d_on[-1:]} blur {max(r['blur'] for r in sc)}")
    ok("full: without Legendary - no sky, no confetti", all(r["cc"] == -1 and r["conf"] == 0 and not r["pillar"] for r in rows))
    ok("full: the camera came back (Custom)", rows[-1]["cam"] == "Custom", rows[-1]["cam"])
time.sleep(4)  # the name dialog closes by itself after 5 s

# 2) the second Common hatch: short
rows = scenario("short_second", "Meadow", "Common")
if rows:
    e0, e1 = span(rows, "egg", True); w = max(r["wedges"] for r in rows)
    sc = [r for r in rows if r["t"] < 1.45]
    ok("short: the camera is not taken, HUD not hidden, no blur", all(r["cam"] == "Custom" and r["hud"] and r["dof"] == -1 and r["blur"] == 0 for r in sc), json.dumps(sc[:2])[:200])
    v_before = max([r["vis"] for r in rows if r["t"] < 0.45] or [0])
    ok("short: the baby is not visible until the crack", v_before == 0, f"{v_before}")
    ok("short: crack ~0.45 s, shell", e1 is not None and e1 <= 0.6 and w >= 8, f"egg {e0}-{e1} wedges {w}")
time.sleep(4)

# 3) Legendary
rows = scenario("legendary", "Meadow", "Legendary")
if rows:
    c0, c1 = span([r for r in rows if r["t"] < 2.95], "cam", "Scriptable")
    cc_on = [r["t"] for r in rows if r["cc"] != -1]
    conf = max(r["conf"] for r in rows); pil = [r["t"] for r in rows if r["pillar"]]
    P("legendary: camera", c0, c1, "sky", (min(cc_on), max(cc_on)) if cc_on else None, "confetti max", conf, "pillar", (min(pil), max(pil)) if pil else None)
    ok("Legendary: the camera no longer than usual (~2.6 s)", c1 is not None and c1 - c0 <= 3.0, f"{c0}-{c1}")
    ok("Legendary: the element sky from the crack ~6.5 s, then removed", cc_on and 0.9 <= min(cc_on) <= 1.4 and 6.5 <= max(cc_on) <= 8.0 and rows[-1]["cc"] == -1, f"{cc_on[:1]}..{cc_on[-1:]}")
    ok("Legendary: confetti and the light pillar", conf >= 30 and pil and max(pil) >= 6, f"conf {conf} pillar {pil[:1]}..{pil[-1:]}")
    ok("Legendary: control came back, the sky and the pillar are still going (after the camera)", c1 is not None and cc_on and max(cc_on) > c1 + 3, "")
    nb = max([r["blur"] for r in rows if r["t"] < 6.2] or [0]); na = max([r["blur"] for r in rows if r["t"] > 6.8] or [0])
    ok("Legendary: the name dialog (Blur) does not cover the celebration - it opens as it fades (~6.4 s)", nb == 0 and na >= 10, f"blur before 6.2 s {nb}, after 6.8 s {na}")
time.sleep(5)

# 4) Mythic: the egg rises
rows = scenario("mythic", "Summit", "Mythic")
if rows:
    lift = max(r["lift"] for r in rows if r["egg"]) if any(r["egg"] for r in rows) else -1
    cc_on = [r["t"] for r in rows if r["cc"] != -1]
    ok("Mythic: the egg rises ~3 studs before the crack", 2.0 <= lift <= 3.2, f"lift {lift}")
    ok("Mythic: sky and confetti", bool(cc_on) and max(r["conf"] for r in rows) >= 30, f"cc {len(cc_on)}")
time.sleep(6)

# console
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|HatchScene|\[Incubation\]|failed|Error|is invalid", l) and "not authorized" not in l and "TexturePack" not in l and "being generated" not in l and "chunks written" not in l and "world built" not in l and "AssistantCommand" not in l]
ok("console without errors", not errs, " ;; ".join(errs[:6]))
stop()
P("RESULT:", f"{sum(1 for r in res if r[1])}/{len(res)} OK")
for r in res:
    if not r[1]:
        P("  FAIL", r[0], "|", r[2][:300])
write_result()
s.close()
