#!/usr/bin/env python3
"""Acceptance of the sounds (Content.Sounds hatch_*, Content.Voices, Core/Voices, Controllers/Sounds) in a LOCAL file on P8
(after open_local.sh). A client trace of every Sound (except music and nature): name, SoundId, parent (2D SoundService or 3D
a model part), whether it is the own dragon and its stage, PlaybackSpeed, volume; after 0.6 s - IsLoaded and TimeLength (the file loads).
(A) the ladder: 6 hatches Common..Mythic - its own step for every rarity, Mythic before the two 'knocks', the rest after; the first squeak
of the baby 3D from its model. (B) growth (time) -> the voice after stage_up. (C) Feed all -> a crunch 2D + 1..3 happy voices from the bodies.
(D) adult companion: mounting -> the call voice 3D; takeoff -> a wingbeat + roar 3D, the second takeoff within 20 s - without a roar; Elder - the roar lower (x0.85).
(E) life at the nest - voices without a reason over the session. Console.
Run: python3 tests/p8/sound_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("sound_check")
from p8lib import *  # noqa: F401,F403


TRACE = r"""
local me=game.Players.LocalPlayer local HS=game:GetService('HttpService')
local old=game.ReplicatedStorage:FindFirstChild('SoundTrace') if old then old:Destroy() end
local sv=Instance.new('StringValue') sv.Name='SoundTrace' sv.Value='[]' sv.Parent=game.ReplicatedStorage
local t0=os.clock() sv:SetAttribute('t0', t0)
local rows={}
local function on(d)
  if not d:IsA('Sound') then return end
  local n=d.Name
  if n:sub(1,6)=='Music_' or n:sub(1,4)=='Amb_' or n=='Waterfall' then return end
  local par=d.Parent
  local m=par and par:FindFirstAncestorOfClass('Model')
  local r={t=math.floor((os.clock()-t0)*100)/100, n=n, id=d.SoundId, sp=math.floor(d.PlaybackSpeed*1000)/1000, v=math.floor(d.Volume*100)/100,
    p=par and par.ClassName or '-', own=(m~=nil and m:GetAttribute('OwnerId')==me.UserId), st=(m and m:GetAttribute('Stage')) or -1, ro=d.RollOffMaxDistance,
    dist=(m and m.PrimaryPart and me.Character and me.Character:FindFirstChild('HumanoidRootPart')) and math.floor((m.PrimaryPart.Position-me.Character.HumanoidRootPart.Position).Magnitude) or -1}
  table.insert(rows,r)
  task.delay(0.6,function() r.loaded=d.IsLoaded r.len=math.floor(d.TimeLength*100)/100 sv.Value=HS:JSONEncode(rows) end)
  task.delay(3,function() r.loaded3=d.IsLoaded sv.Value=HS:JSONEncode(rows) end)
  sv.Value=HS:JSONEncode(rows)
end
game:GetService('SoundService').DescendantAdded:Connect(on)
workspace.DescendantAdded:Connect(on)
return 'armed'
"""
def now(): return float(C("return tostring(os.clock()-game.ReplicatedStorage.SoundTrace:GetAttribute('t0'))"))
def rows(): return json.loads(C("return game.ReplicatedStorage.SoundTrace.Value"))
def after(t, names=None):
    return [r for r in rows() if r["t"] >= t and (names is None or r["n"] in names or any(r["n"].startswith(x) for x in names if x.endswith("*")))]

stop(); start()
S(LD + "return ld('firstegg off')")  # the manual first egg path (auto - firstegg_check.py)
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
P("trace:", C(TRACE))
SND = json.loads(C("local C=require(game.ReplicatedStorage.Shared.Content) local o={} for k,v in C.Sounds do o[k]=v end return game:GetService('HttpService'):JSONEncode(o)"))
P("Content.Sounds hatch_*:", {k: v for k, v in SND.items() if k.startswith("hatch")})
S(LD + "return ld('give 1000000')")

# ---------------------------------------------------------------- (A) the hatch ladder + the first squeak
for zone, rar, wait in [("Meadow", "Common", 4), ("Meadow", "Uncommon", 4), ("Meadow", "Rare", 4), ("Meadow", "Epic", 5),
                        ("Meadow", "Legendary", 10), ("Summit", "Mythic", 11)]:
    S(LD + f"return ld('give egg {zone} {rar}')"); time.sleep(0.6)
    S(LD + "return ld('go inc')"); time.sleep(2.5)
    S(LD + "return ld('time 9999999')"); time.sleep(5)
    t = now()
    P(f"--- {rar}: hatch", S(LD + "return ld('hatch 1')")[:80])
    time.sleep(wait)
    rs = after(t)
    hs = [r for r in rs if r["n"].startswith("hatch")]
    cr = [r for r in rs if r["n"] == "egg_crack"]
    bi = [r for r in rs if r["n"] == "Voice_birth"]
    P(rar, "hatch:", [(r["n"], r["t"] - t, r.get("loaded"), r.get("len")) for r in hs], "crack:", [round(r["t"] - t, 2) for r in cr],
      "birth:", [(round(r["t"] - t, 2), r["p"], r["own"], r["st"], r["dist"], r.get("loaded")) for r in bi])
    name = f"hatch_{rar}"
    ok(f"A {rar}: its own step {name} plays (id from Content) and only it", len(hs) == 1 and hs[0]["n"] == name and hs[0]["id"] == f"rbxassetid://{SND.get(name)}", json.dumps(hs)[:200])
    ok(f"A {rar}: the step file is loaded (IsLoaded, length > 0)", len(hs) == 1 and hs[0].get("loaded") is True and (hs[0].get("len") or 0) > 0.5, json.dumps(hs)[:200])
    if rar == "Mythic":
        ok("A Mythic: starts with the shaking - before the two 'knocks'", hs and len(cr) == 2 and hs[0]["t"] < cr[0]["t"], f"{[r['t'] for r in hs]} vs {[r['t'] for r in cr]}")
    elif rar != "Common" or True:
        ok(f"A {rar}: the step at the crack - after the 'knocks'", hs and cr and hs[0]["t"] > cr[-1]["t"], f"{[r['t'] for r in hs]} vs {[r['t'] for r in cr]}")
    ok(f"A {rar}: the first squeak of the baby after the crack - 3D from its stage 0 model (no model nearby - 2D), the file is ready", len(bi) == 1
       and ((bi[0]["p"] in ("MeshPart", "Part") and bi[0]["own"] and bi[0]["st"] == 0) or bi[0]["p"] == "SoundService")
       and bi[0].get("loaded") is True and (not hs or bi[0]["t"] >= hs[0]["t"]), json.dumps(bi)[:200])
    time.sleep(5)  # the name dialog closes by itself

# ---------------------------------------------------------------- (B) growth -> the voice of the new stage
t = now()
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6); S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('hatch 1')"); time.sleep(7)
S(LD + "return ld('time 9999999')"); time.sleep(4)
rs = after(t)
su = [r for r in rs if r["n"] == "stage_up"]
vc = [r for r in rs if r["n"] == "Voice_call"]
pairs = [(s_["t"], v["t"], v["st"], v["p"]) for s_ in su for v in vc if 0.4 <= v["t"] - s_["t"] <= 1.5]
P("B stage_up:", [r["t"] for r in su], "Voice_call:", [(r["t"], r["st"], r["p"], r["own"]) for r in vc])
ok("B: after the growth chord - the voice of the new stage (~0.6 s), from the dragon model", bool(pairs) and any(p[3] != "SoundService" for p in pairs), json.dumps(pairs)[:200])

# ---------------------------------------------------------------- (C) food: Feed all
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6); S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('hatch 1')"); time.sleep(7)
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6); S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('hatch 1')"); time.sleep(7)
HUNGRY = "local n=0 for _,m in game:GetService('CollectionService'):GetTagged('CanFeed') do if m:GetAttribute('OwnerId')==game.Players:GetPlayers()[1].UserId then n+=1 end end return tostring(n)"
hungry = S(HUNGRY)
t = now()
C("local r=game.ReplicatedStorage.Remotes.Admin:InvokeServer('give 100000000') return tostring(r and r.ok)")  # a Mythic teen's food costs > 1 M - coins with a margin, we check the sound, not the economy
fr = S(LD + "local r=ld('feed all') return typeof(r)=='table' and (tostring(r.ok)..'/'..tostring(r.reason)..'/'..tostring(r.fed)) or tostring(r)")
time.sleep(3)
hungry2 = S(HUNGRY)
rs = after(t)
fd = [r for r in rs if r["n"] == "feed"]
hp = [r for r in rs if r["n"] == "Voice_happy"]
P("C: hungry", hungry, "feed all", fr, "feed:", [(r["t"] - t, r["p"]) for r in fd], "happy:", [(round(r["t"] - t, 2), r["p"], r["own"], r["st"], r["dist"]) for r in hp])
nfed = int(hungry) - int(hungry2)
P("C: fed", nfed, "(CanFeed own", hungry, "->", hungry2, ")")
ok("C: one crunch, 2D", len(fd) == 1 and fd[0]["p"] == "SoundService", json.dumps(fd)[:160])
ok("C: happy voices from the own dragons' bodies, one per fed dragon, no more than 3", nfed >= 1 and len(hp) == min(nfed, 3) and all(r["own"] and r["p"] != "SoundService" for r in hp), f"fed {nfed}, voices {len(hp)}")
ok("C: the voices after the crunch at different times", len(hp) < 2 or (min(r["t"] for r in hp) >= fd[0]["t"] and len({r["t"] for r in hp}) == len(hp)), json.dumps([r["t"] for r in hp]))

# ---------------------------------------------------------------- (D) adult companion: mounting, takeoff, roar cooldown, Elder
def fly_once(tag):
    t = now()
    P(tag, "up:", C(CD + "return cd('fly up on')")); time.sleep(2.5); C(CD + "return cd('fly up off')")
    P(tag, "state:", C(CD + "return cd('fly state')"))
    return t
P("D setcomp:", S(LD + "local r=ld('setcomp ember2') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
t = now()
MOUNTS = [t]
P("D mount:", S(LD + "local r=ld('mount') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
mc = [r for r in after(t) if r["n"] == "Voice_call"]
P("D mounting Voice_call:", [(r["t"] - t, r["p"], r["own"], r["st"], r["dist"]) for r in mc])
ok("D: mounting - the adult voice 3D from the companion", any(r["own"] and r["st"] == 2 and r["p"] != "SoundService" for r in mc), json.dumps(mc)[:200])
t1 = fly_once("D takeoff 1")
time.sleep(1)
r1 = after(t1)
w1 = [r for r in r1 if r["n"] == "wing"]; ro1 = [r for r in r1 if r["n"] == "Voice_roar"]
P("D takeoff 1:", [(r["n"], r["t"] - t1, r["p"], r["st"], r["sp"], r.get("loaded")) for r in w1 + ro1])
ok("D: takeoff - a wingbeat (its own file) and the adult roar 3D", len(w1) == 1 and w1[0]["id"] == f"rbxassetid://{SND['wing']}" and len(ro1) == 1 and ro1[0]["st"] == 2 and ro1[0]["p"] != "SoundService" and ro1[0].get("loaded") is True, json.dumps(w1 + ro1)[:240])
ok("D: the adult roar without a pitch shift (0.96-1.04)", len(ro1) == 1 and 0.95 <= ro1[0]["sp"] <= 1.05, json.dumps(ro1)[:120])
P("D down:", C(CD + "return cd('fly down on')")); time.sleep(5); C(CD + "return cd('fly down off')"); time.sleep(1.5)
P("D state:", C(CD + "return cd('fly state')"))
ld_ = [r for r in after(t1) if r["n"] == "land"]
ok("D: landing on the ground - its own dull thud", len(ld_) >= 1 and ld_[0]["id"] == f"rbxassetid://{SND['land']}", json.dumps(ld_)[:160])
t2 = fly_once("D takeoff 2")
time.sleep(1)
r2 = after(t2)
w2 = [r for r in r2 if r["n"] == "wing"]; ro2 = [r for r in r2 if r["n"] == "Voice_roar"]
ok("D: the second takeoff within 20 s - a wingbeat without a roar (cooldown)", len(w2) == 1 and len(ro2) == 0 and (t2 - t1) < 20, f"wing {len(w2)} roar {len(ro2)} dt {t2 - t1:.1f}")
P("D dismount:", C(CD + "return cd('fly off')")); time.sleep(2)
P("D Elder:", S(LD + "local r=ld('setcomp ember3') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(3)
MOUNTS.append(now())
S(LD + "return ld('mount')"); time.sleep(3)
time.sleep(max(0, 21 - (now() - t1)))  # roar cooldown
t3 = fly_once("D Elder takeoff")
time.sleep(1)
ro3 = [r for r in after(t3) if r["n"] == "Voice_roar"]
P("D Elder roar:", [(r["t"] - t3, r["st"], r["sp"]) for r in ro3])
ok("D: Elder roars with the adult voice lower (x0.85 +-4%)", len(ro3) == 1 and ro3[0]["st"] == 3 and 0.80 <= ro3[0]["sp"] <= 0.89, json.dumps(ro3)[:160])
C(CD + "return cd('fly down on')"); time.sleep(5); C(CD + "return cd('fly down off')"); time.sleep(1)
C(CD + "return cd('fly off')"); time.sleep(2)

# ---------------------------------------------------------------- (E) life at the nest: voices without a reason over the session
S(LD + "return ld('go inc')")
time.sleep(40)
allr = rows()
ev = [r["t"] for r in allr if r["n"] in ("stage_up", "feed", "mount", "wing", "land", "hatch_Common", "hatch_Uncommon", "hatch_Rare", "hatch_Epic", "hatch_Legendary", "hatch_Mythic", "Voice_birth")]
idle = [r for r in allr if r["n"] in ("Voice_call", "Voice_happy") and not any(0 <= r["t"] - e <= 3.5 for e in ev + MOUNTS)]
P("E: without a reason:", [(r["t"], r["n"], r["p"], r["own"], r["st"], r["dist"]) for r in idle])
ok("E: over the session the life voices at the nest - own dragons nearby, 3D, pauses >= 25 s", len(idle) >= 1 and all(r["own"] and r["p"] != "SoundService" and 0 <= r["dist"] <= 70 for r in idle)
   and all(b["t"] - a["t"] >= 24 for a, b in zip(idle, idle[1:])), json.dumps(idle)[:300])
# a sound that has already finished and been removed reads IsLoaded false, TimeLength 0 (the coin_plus click 0.37 s) - such ones are not counted
bad = [r for r in allr if r.get("loaded3") is False and (r.get("len") or 0) > 3.2]
ok("long sounds (> 3.2 s) stay loaded", not bad, json.dumps(bad)[:300])
late = [r for r in allr if r.get("loaded") is False and (r.get("len") or 0) > 0]
ok("preload: every sound is ready already 0.6 s after the start (not late)", not late, json.dumps([(r["n"], r["t"]) for r in late])[:300])
json.dump(allr, open(f"{OUT}/trace.json", "w"), indent=0)
P("total sounds:", len(allr), {n: sum(1 for r in allr if r["n"] == n) for n in sorted({r["n"] for r in allr})})

cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|Sounds|HatchScene|failed|Error|is invalid", l) and "not authorized" not in l and "TexturePack" not in l and "being generated" not in l and "chunks written" not in l and "world built" not in l and "AssistantCommand" not in l]
ok("console without errors", not errs, " ;; ".join(errs[:6]))
stop()
P("RESULT:", f"{sum(1 for r in res if r[1])}/{len(res)} OK")
for r in res:
    if not r[1]:
        P("  FAIL", r[0], "|", r[2][:300])
write_result()
s.close()
