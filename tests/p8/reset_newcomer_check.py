#!/usr/bin/env python3
"""Reset Progress must bring back the full newcomer path.
0 veteran: first dragon, teen, first ride - the golden nest with the warden stands (in the series - also 'glow done': nest #2, as in
a profile with a hatched Ember). 1 Reset Progress from the menu (Remote Admin 'reset', like the Menu button) in the same session.
2 after the reset - the newcomer path as on a fresh profile: 0 dragons, the ring 0 Gloom nests (3), the own far one (FirstNest) with an egg and a sleeping
warden, the step 'Steal an egg from the sleeping Gloom', the remains of the golden nest and its warden removed. 3 theft: right up to FirstNest -
the raid egg in the hands. 4 console. Run on the new build and on the previous live one (comparison).
Run: python3 tests/p8/reset_newcomer_check.py [tag] (after open_local)."""
import os, sys, time, re
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
TAG = sys.argv[1] if len(sys.argv) > 1 else "new"
p8lib.begin("reset_newcomer_check_" + TAG)
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
ME = "local me=game.Players:GetPlayers()[1] local ch=me and me.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') "
NESTS = ("local CS=game:GetService('CollectionService') "
         "local function nests(ring) local o={} for _,m in CS:GetTagged('RaidNest') do if tonumber(m:GetAttribute('Ring'))==ring then table.insert(o,m) end end return o end "
         "local function nestById(id) for _,m in CS:GetTagged('RaidNest') do if m:GetAttribute('NestId')==id then return m end end return nil end "
         "local function guardOf(m) for _,g in CS:GetTagged('GloomChase') do if g:GetAttribute('PackKey')=='raid:'..tostring(m:GetAttribute('NestId')) then return g end end return nil end "
         "local function mk(g) local b=g and g.PrimaryPart and g.PrimaryPart:FindFirstChild('Mark') return b and b.T and b.T.Text or '-' end ")
DUMP = "local d=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) "

def labels(sub):
    return C("local pg=game.Players.LocalPlayer.PlayerGui local o={} for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and d.Visible and d.Text:find([[" + sub + "]],1,true) then table.insert(o,d.Text) end end return table.concat(o,' | ')")

def state(title):
    st = S(ME + NESTS + DUMP + "local dr=0 for _ in d.dragons do dr+=1 end local fid=me:GetAttribute('FirstNest') local fm=fid and nestById(fid) local g=fm and guardOf(fm) "
           "local gold=workspace:FindFirstChild('GlowEggs') gold=gold and gold:FindFirstChild('GlowEgg_'..me.UserId) local packs=0 "
           "for _,x in CS:GetTagged('GloomChase') do if x:GetAttribute('OwnerId')==me.UserId then packs+=1 end end local eggs0=0 for _,m in nests(0) do if m:GetAttribute('HasEgg')==true then eggs0+=1 end end "
           "return string.format('dragons=%d ring0=%d eggs0=%d first=%s firstEgg=%s guard=%s gold=%s goldPack=%d glowRaid=%s glowWait=%s carry=%s ge=%s', dr, #nests(0), eggs0, tostring(fid), "
           "tostring(fm and fm:GetAttribute('HasEgg')), g and mk(g) or 'none', tostring(gold~=nil), packs, tostring(me:GetAttribute('GlowRaid')), tostring(me:GetAttribute('GlowWait')~=nil), "
           "tostring(d.eggs.carry and (d.eggs.carry.raid or d.eggs.carry.glow)), game:GetService('HttpService'):JSONEncode(d.glowEgg or {}))")
    P(title, st)
    return st

# ------------------------------------------------- 0 veteran with a golden nest
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
time.sleep(10)
fresh = state("fresh profile:")
S(LD + "return ld('give 1000000')")
S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
S(LD + "return ld('go inc')"); time.sleep(2)
S(LD + "return ld('time 9999999')"); time.sleep(3)
P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
time.sleep(8)
P("setcomp:", S(LD + "local r=ld('setcomp moss1') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
P("mount:", ld("mount")[:40]); time.sleep(1.5)
P("dismount:", ld("dismount")[:40]); time.sleep(4)
P("glow done:", ld("glow done")[:80]); time.sleep(4)
vet = state("veteran:")
ok("0. veteran: has a dragon, the golden nest stands", "gold=true" in vet and "dragons=0" not in vet, vet)

# ------------------------------------------------- 1 Reset Progress (like the menu button)
rr = C("local ok,rep=pcall(function() return game.ReplicatedStorage.Remotes.Admin:InvokeServer('reset') end) return tostring(ok)..' '..(typeof(rep)=='table' and tostring(rep.ok)..'/'..tostring(rep.reason) or tostring(rep))")
P("reset:", rr)
time.sleep(6)
after = state("after the reset:")
ok("1. the reset went through: 0 dragons", "true true" in rr and "dragons=0" in after, rr + " | " + after)
ok("2. Gloom nests: ring 0 = 3, the newcomer has the own far one (FirstNest) with an egg, the warden sleeps", "ring0=3" in after and "first=nil" not in after
   and "firstEgg=true" in after and "guard=Zz" in after, after)
ok("2a. no remains of the golden nest and its warden, no sortie", "gold=false" in after and "goldPack=0" in after and "glowRaid=nil" in after and "glowWait=false" in after, after)
hint = ""
for _ in range(28):
    hint = labels("Steal an egg from the sleeping Gloom")
    if hint: break
    time.sleep(0.5)
ok("2b. the step 'Steal an egg from the sleeping Gloom - your first dragon!'", bool(hint), hint[:120])

# ------------------------------------------------- 3 theft of the first egg
c3 = S(ME + NESTS + DUMP + "local fm=nestById(me:GetAttribute('FirstNest')) if not fm then return 'no nest' end local a=fm:GetAttribute('At') "
       "local u=Vector3.new(-a.X,0,-a.Z).Unit ch:PivotTo(CFrame.new(a+u*3+Vector3.new(0,4,0))) local t=0 local took=false while t<6 do "
       "local dd=game:GetService('HttpService'):JSONDecode(game.ServerStorage.LoopDebug:Invoke('dump')) if dd.eggs.carry and dd.eggs.carry.raid~=nil then took=true break end "
       "task.wait(0.1) t+=0.1 end local g=guardOf(fm) return string.format('took=%s t=%.1f mark=%s', tostring(took), t, g and mk(g) or 'none')")
ok("3. right up to the own Gloom nest - the raid egg in the hands (theft works)", "took=true" in c3, c3)

cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[GlowEgg]" in l or "[Raid]" in l or "[Combat]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("4. console without game errors", not bad, str(len(bad)))
for l in bad[-12:]: P("  ", l[:240])
P("the fresh profile was:", fresh)
stop()
write_result(f"Reset Progress -> newcomer path ({TAG}, 02.11)")
