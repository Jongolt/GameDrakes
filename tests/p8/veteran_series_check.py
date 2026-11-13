#!/usr/bin/env python3
"""A veteran with a golden series nest (#2, like a profile with a hatched Ember) keeps the wardens, the nests to steal from and the attacks:
0 veteran: first dragon, teen, first ride, golden #1 stolen and hatched (Glowing Ember); in the series nest #2 (Frost) stands.
1 the step 'Steal another egg - N left today' (daily raids), the arrow not to the golden nest; at the Gloom nest (FirstNest) the egg is visible
to the client, the warden sleeps. 2 theft: right up close - the raid egg in the hands, the warden woke up ('!'). 3 home - the egg in the bowl, the daily limit is 1 less.
4 attack: stands at home idle - a Gloom hunt wave comes (the Gloom_meadow attribute) within <= 150 s. 5 console.
Run: python3 tests/p8/veteran_series_check.py [tag] (after open_local)."""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
TAG = sys.argv[1] if len(sys.argv) > 1 else "new"
p8lib.begin("veteran_series_check_" + TAG)
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
NESTS = ("local CS=game:GetService('CollectionService') "
         "local function nestById(id) for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('NestId')==id then return m end end return nil end "
         "local function guardOf(m) for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='raid:'..tostring(m:GetAttribute('NestId')) then return g end end return nil end "
         "local function mk(g) local b=g and g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') return b and b.T and b.T.Text or '-' end ")
DUMP = "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "

def num(t, key, default=None):
    m = re.search(key + r"=(-?[\d.]+)", t or "")
    return float(m.group(1)) if m else default

def labels(sub):
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find([[" + sub + "]],1,true) then table.insert(o,d.Text) end end return table.concat(o,' | ')")

# ------------------------------------------------- 0 veteran with a golden series nest
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
time.sleep(8)
P("setcomp:", S(LD + "local r=ld('setcomp moss1') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
P("mount:", ld("mount")[:40]); time.sleep(1.5)
P("dismount:", ld("dismount")[:40]); time.sleep(4)
# golden egg #1 for real: take it, home, 'ready', hatch - a profile with a hatched Ember
GN = ("local m=workspace:FindFirstChild('GlowEggs') m=m and m:FindFirstChild('GlowEgg_'..me.UserId) "
      "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end local hb=hn and hn:FindFirstChild('Base') ")
gn = "?"
for _ in range(30):
    gn = S(ME + GN + "return tostring(m~=nil and m:GetAttribute('At')~=nil)")
    if gn == "true": break
    time.sleep(1)
tk = S(ME + GN + "local N=m:GetAttribute('At') local u=Vector3.new(hb.Position.X-N.X,0,hb.Position.Z-N.Z).Unit ch:PivotTo(CFrame.new(N+u*3+Vector3.new(0,4,0))) "
       "local t=0 while t<6 and not m:GetAttribute('Empty') do task.wait(0.05) t+=0.05 end local took=m:GetAttribute('Empty')==true "
       "if took then ch:PivotTo(CFrame.new(hb.Position+Vector3.new(0,5,0))) end return 'took='..tostring(took)")
P("golden #1:", gn, tk)
for _ in range(20):
    if "ready=0" not in S(DUMP + "return 'ready='..tostring((d.glowEgg or {}).readyAt or 0)"): break
    time.sleep(0.5)
P("glow ready:", ld("glow ready")[:40])
for _ in range(20):
    if "true" in S(DUMP + "return tostring((d.glowEgg or {}).hatched)"): break
    time.sleep(1)
time.sleep(4)
P("hatch 1:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:60])
time.sleep(6)
P("glowing:", S(DUMP + "local o={} for _,x in d.dragons do if x.glow then table.insert(o,x.name) end end return table.concat(o,',')"))
v0 = S(ME + DUMP + "local gold=workspace:FindFirstChild('GlowEggs') gold=gold and gold:FindFirstChild('GlowEgg_'..me.UserId) local dr=0 for _ in d.dragons do dr+=1 end "
       "return string.format('dragons=%d gold=%s el=%s left=%s first=%s', dr, tostring(gold~=nil), tostring(gold and gold:GetAttribute('Element')), tostring(me:GetAttribute('RaidLeft')), tostring(me:GetAttribute('FirstNest')))")
ok("0. veteran with a hatched Glowing Ember: daily raids exist (RaidLeft > 0), a Gloom nest assigned (in the series - also golden #2 Frost)",
   num(v0, "left", 0) > 0 and "first=nil" not in v0 and (TAG == "old349" or ("gold=true" in v0 and "el=frost" in v0)), v0)

# ------------------------------------------------- 1 the step to the daily raid, the egg and the warden
step = ""
for _ in range(30):
    step = labels("left today")
    if step: break
    time.sleep(0.5)
ok("1. the step 'Steal another egg - N left today' (as in 349), not to the golden nest", bool(step), step[:120])
g1 = C("local me=game.Players.LocalPlayer local id=me:GetAttribute('FirstNest') local m for _,x in game:GetService('CollectionService'):GetTagged('RaidNest') do if x:GetAttribute('NestId')==id then m=x end end "
       "if not m then return 'no nest' end local e=m:FindFirstChild('Egg',true) local t=1 if e then for _,q in e:GetDescendants() do if q:IsA('BasePart') then t=math.min(t,q.LocalTransparencyModifier) end end end "
       "return string.format('egg=%s eggT=%s', tostring(e~=nil), tostring(t))")
s1 = S(ME + NESTS + "local fm=nestById(me:GetAttribute('FirstNest')) local g=fm and guardOf(fm) return string.format('hasEgg=%s guard=%s', tostring(fm and fm:GetAttribute('HasEgg')), g and mk(g) or 'none')")
ok("1a. at the Gloom nest the egg is visible to the player, the warden sleeps", "egg=true" in g1 and "eggT=0" in g1 and "hasEgg=true" in s1 and "guard=Zz" in s1, g1 + " | " + s1)

# ------------------------------------------------- 2-3 theft and home
c2 = S(ME + NESTS + "local fm=nestById(me:GetAttribute('FirstNest')) if not fm then return 'no nest' end local a=fm:GetAttribute('At') "
       "local u=Vector3.new(-a.X,0,-a.Z).Unit ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) local t=0 local took=false while t<6 do "
       "local dd=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) if dd.eggs.carry and dd.eggs.carry.raid~=nil then took=true break end "
       "task.wait(0.1) t+=0.1 end task.wait(0.3) local g=guardOf(fm) return string.format('took=%s mark=%s', tostring(took), g and mk(g) or 'none')")
ok("2. theft from the Gloom nest: the egg in the hands, the warden woke up ('!')", "took=true" in c2 and "mark=!" in c2, c2)
left0 = num(v0, "left", 0)
S(ME + "local hn for _,x in workspace:FindFirstChild('Nests',true):GetChildren() do if x:GetAttribute('OwnerId')==me.UserId then hn=x end end "
  "if hn and hn:FindFirstChild('Base') then ch:PivotTo(CFrame.new(hn.Base.Position+Vector3.new(0,5,0))) end return 1")
h3 = "?"
for _ in range(30):
    h3 = S(ME + DUMP + "local inc=0 for _ in d.eggs.incubating do inc+=1 end return string.format('carry=%s inc=%d left=%s', tostring(d.eggs.carry and d.eggs.carry.raid), inc, tostring(me:GetAttribute('RaidLeft')))")
    if "carry=nil" in h3 and num(h3, "inc", 0) >= 1: break
    time.sleep(0.5)
ok("3. carried it home: the egg in the bowl, the daily limit is 1 less", "carry=nil" in h3 and num(h3, "inc", 0) >= 1 and num(h3, "left", 99) == left0 - 1, h3 + f" (was {left0})")

# ------------------------------------------------- 4 a Gloom attack (hunt) on the veteran
t0 = time.time(); w = "nil"
while time.time() - t0 < 150:
    w = S(ME + "return tostring(me:GetAttribute('Gloom_meadow'))..' sky='..tostring(me:GetAttribute('Gloom_sky'))")
    if not w.startswith("nil"): break
    time.sleep(3)
ok("4. attack: a Gloom hunt wave came to the veteran (<= 150 s)", not w.startswith("nil"), f"{w} in {time.time() - t0:.0f} s | " + ld("combat info")[:160])

cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Raid]" in l or "[Combat]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("5. console without game errors", not bad, str(len(bad)))
for l in bad[-12:]: P("  ", l[:240])
stop()
write_result(f"Veteran with a golden series nest - as in 349 ({TAG}, 02.11)")
