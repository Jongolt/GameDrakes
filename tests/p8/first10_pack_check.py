#!/usr/bin/env python3
"""Acceptance of the 'first 10 minutes' fixes on P8 in a LOCAL file
(after tools/p8/open_local.sh), phone window 812x375, fresh profile, then a profile via StudioSeed.
1) Old Ash on spawn says 'Welcome, rider. Pick an egg - any of the three.' (KeeperSays bubble), after picking up an egg -
the text of quest 1;
2) pickup from the table from 3.0 studs (Config.Loop.pickRadius 3.2);
3) after the first pickup the two other table eggs are invisible on the client, the server rejects a repeated pickup (LoopDebug 'table k');
the table corner at the bowl: where the egg is taken and immediately goes into the bowl (measurement);
4) first dragon: the firstborn timers (firstDragon.growMin), the growAs mark on Common too;
5) FEED step: at the stall and closer to the stall the step target is Stall (the banner does not call to the nest), at the nest - dragon/nest;
6) Storm dragon: for a player without an adult - no bar, no silhouette, no shards, pickup does not count; with an adult (setcomp ember2) -
visible and counted.
Run: python3 tests/p8/first10_pack_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/first10_pack_check/ (frames F*.jpg, result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("first10_pack_check")
from p8lib import *  # noqa: F401,F403

WELCOME = "Welcome, rider. Pick an egg - any of the three."
QUEST1 = "Put the egg in the nest and keep it warm."
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def cd(c): return C(CD + f"return cd('{c}')")
def wd(c): return S(f"return game.ServerStorage.WeatherDebug:Invoke('{c}')")
def tp(x, y, z): return S(f"return game.ServerStorage.AntiCheatDebug:Invoke('tp {x:.2f} {y:.2f} {z:.2f}')")
def nest_point(dx, dy, dz):
    t = S(NEST + f"if not n then return '-' end local q=(n:GetPivot()*CFrame.new({dx},{dy},{dz})).Position return string.format('%.2f,%.2f,%.2f', q.X, q.Y, q.Z)")
    return tuple(float(v) for v in t.split(","))
def keeper_line():
    return C("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Quests') local f=q and q:FindFirstChild('KeeperSays') local l=f and f:FindFirstChild('Line') "
             "return (f and tostring(f.Visible) or 'nof')..'|'..(l and l.Text or '-')")
def table_vis():  # visibility of the table eggs on the client: k=visible/hidden
    return C(NEST.replace("game.Players:GetPlayers()[1]", "game.Players.LocalPlayer") +
             "if not n then return 'nonest' end local t=n:FindFirstChild('EggTable') local out={} for k=1,3 do local m=t and t:FindFirstChild('TableEgg'..k) local vis=false "
             "if m then for _,d in m:GetDescendants() do if d:IsA('BasePart') and d.Transparency<0.99 then vis=true end end end out[#out+1]='TableEgg'..k..'='..(m and (vis and 'visible' or 'hidden') or 'none') end return table.concat(out,' ')")
def egg_dists():  # XZ distances from the player root to the table eggs (server)
    return S(NEST + "local ch=p.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') if not n or not r then return '-' end local t=n:FindFirstChild('EggTable') local out={} "
             "for k=1,3 do local m=t and t:FindFirstChild('TableEgg'..k) if m then local q=m:GetPivot().Position out[#out+1]=string.format('e%d=%.2f',k,(Vector3.new(q.X,0,q.Z)-Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude) end end "
             "local inc=n:FindFirstChild('Incubators') local i1=inc and inc:FindFirstChild('Incubator1') if i1 then out[#out+1]=string.format('inc1=%.2f',(Vector3.new(i1.Position.X,0,i1.Position.Z)-Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude) end return table.concat(out,' ')")
def shards():
    return S("local n=0 local p for _,c in workspace:GetChildren() do if c.Name=='StormShard' then n+=1 p=c end end return n..'|'..(p and string.format('%.1f,%.1f,%.1f',p.Position.X,p.Position.Y,p.Position.Z) or '-')")
def console_errors():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
    return [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)


edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
stop(); start(); wait_world()
shot("F0_spawn")
# ---------------------------------------------------------------------------------------------- 1. greeting
kl = keeper_line(); P("bubble on spawn:", kl)
for _ in range(16):  # the bubble hides while a banner/splash is up (UIKit.bannerUntil) - wait up to 8 s, check the text right away
    if kl.startswith("true|"):
        break
    time.sleep(0.5); kl = keeper_line()
ok("1. on spawn the Old Ash bubble says 'Welcome, rider. Pick an egg - any of the three.'", kl.startswith("true|") and WELCOME in kl, kl)
# ---------------------------------------------------------------------------------------------- 2. pickup from 3.0 studs
pt = nest_point(-12, 3, -41)   # 3.0 studs from TableEgg2 (-12,-44) on the plaza side, outside the table (edge z -42.3)
tp(*pt); time.sleep(0.6)
d0 = egg_dists(); P("distances to the eggs right after the teleport:", d0)
time.sleep(1.5)
st = state(); P("state:", st[:200])
m = re.search(r"e2=([\d.]+)", d0)
ok("2. at 3.0 studs from a table egg (was point-blank 2.6): the egg jumps into the hands by itself", "carry=-" not in st and m is not None and 2.6 < float(m.group(1)) <= 3.2, f"{d0} | {st[:120]}")
shot("F1_picked")
# ---------------------------------------------------------------------------------------------- 3. the two others vanished, a repeat is rejected
tv = table_vis(); P("table visibility on the client:", tv)
ok("3. after the pickup both other table eggs are invisible on the client", tv.count("hidden") == 3, tv)
r1, r3 = ld("table 1"), ld("table 3")
ok("3. the server rejects picking up the second and third egg (no_egg)", "reply=false/no_egg" in r1 and "reply=false/no_egg" in r3, f"{r1[:60]} | {r3[:60]}")
kl2 = keeper_line(); P("bubble after the pickup:", kl2)
ok("1. after the pickup the bubble shows the quest 1 text", QUEST1 in kl2 or "nof" not in kl2 and WELCOME not in kl2, kl2)
# ---------------------------------------------------------------------------------------------- 4. first dragon: timers 180 / 540
ld("go inc"); time.sleep(2.5)
st = state(); P("at the bowl:", st[:160])
ok("the egg went into the bowl at the rim (placeRadius 3.8)", "inc1=" in st, st[:120])
time.sleep(3.5)
P("hatch:", ld("hatch 1")[:160]); time.sleep(2)
d = dump()
drs = d.get("dragons") or {}
first = next(iter(drs.values()), None)
P("first dragon:", json.dumps({k: first.get(k) for k in ("rarity", "stage", "growAs", "hatchedAt", "stageEndsAt")} if first else None))
ok("4. firstborn: mark growAs=Common (on Common too), H->J exactly 60 s (24.10: growMin 1)", first is not None and first.get("growAs") == "Common" and first.get("stage") == 0 and (first.get("stageEndsAt") or 0) - (first.get("hatchedAt") or 0) == 60, str(first and {k: first.get(k) for k in ("rarity", "growAs", "hatchedAt", "stageEndsAt")}))
ld("time 56"); time.sleep(6)
d = dump(); first = next(iter((d.get("dragons") or {}).values()), None)
now = int(S("return tostring(os.time())"))
left = (first.get("stageEndsAt") or 0) - now if first else -1
P("after time 56:", first and first.get("stage"), "left", left)
ok("4. firstborn teen: J->A 180 s (24.10: growMin 3; Common was 600)", first is not None and first.get("stage") == 1 and 168 <= left <= 181, f"stage={first and first.get('stage')} left={left}")
# ---------------------------------------------------------------------------------------------- table corner at the bowl (measurement, not a gate)
# standing at the south-west table corner (1.2 studs from its edge), the egg 3.0 from TableEgg1 and 3.1 from Incubator1 - pickup and placing in one tick?
stop(); start(); wait_world()
pt = nest_point(-15.0, 3, -46.9); tp(*pt); time.sleep(0.6)
dc = egg_dists(); time.sleep(1.6)
stc = state(); P("table corner:", dc, "|", stc[:160])
P("MEASUREMENT of the table corner at the bowl: the egg " + ("taken and right in the bowl" if "inc1=" in stc else ("in the hands" if "carry=-" not in stc else "not taken")) + f" ({dc})")
shot("F1b_corner")
# coins and profile for FEED / the Storm dragon
ld("table 2"); time.sleep(0.5); ld("place 1"); time.sleep(3.5); ld("hatch 1"); time.sleep(2)
for _ in range(12):
    if dump().get("coins", 0) >= 120:
        break
    ld("go pile"); time.sleep(3)
prof = dump()
P("coins for the seed:", prof.get("coins"))
ob = prof.setdefault("onboarding", {})
ob.update({"glided": True, "coinsCollected": True, "eggFound": True})
prof["lastSeen"] = int(time.time())
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world(); time.sleep(2)
# ---------------------------------------------------------------------------------------------- 5. FEED target at the stall
st5 = cd("state"); P("on the spawn slab:", st5[:240])
ok("5. on the spawn slab (26 m to the stall, 86 to the nest) the FEED step, target - the stall (Stall)", "active=" in st5 and "target=Stall" in st5 and "banner=feed" in st5, st5[:200])
shot("F2_spawn_feed_banner")
ld("go pile"); time.sleep(1.5)
st5n = cd("state"); P("at the nest:", st5n[:240])
ok("5. at the nest the FEED target is the dragon or the nest, not the stall", "banner=feed" in st5n and "target=Stall" not in st5n and "target=-" not in st5n, st5n[:200])
tp(0, 21, -33); time.sleep(1.5)   # 7 studs from the counter (0,18,-40) on the plaza side: stall radius 14, nearSkip 10
st5s = cd("state"); P("at the stall:", st5s[:240])
ok("5. at the stall (within radius 14) the FEED target is Stall, no distance on the banner (0/1)", "target=Stall" in st5s and "[0/1]" in st5s, st5s[:200])
shot("F3_stall_feed")
# ---------------------------------------------------------------------------------------------- 6. Storm dragon: a newcomer does not see it
P("weather dragon:", wd("dragon")); time.sleep(3)
w0 = cd("weather"); P("client without an adult:", w0)
ok("6. without an adult: eligible=false, no bar and no silhouette", "eligible=false" in w0 and "bar=false" in w0 and "silhouette=false" in w0 and "dragon=true" in w0, w0)
shot("F4_storm_hidden")
for _ in range(25):
    sh = shards()
    if not sh.startswith("0|"):
        break
    time.sleep(2)
P("server shards:", sh)
w1 = cd("weather"); P("client without an adult, a shard is lying:", w1)
ok("6. without an adult: the shard exists on the server, invisible on the client (shardsVisible=0)", not sh.startswith("0|") and "shardsVisible=0" in w1, f"{sh} | {w1}")
sx, sy, sz = (float(v) for v in sh.split("|")[1].split(","))
tp(sx, sy + 3, sz); time.sleep(2)
ws = wd("state"); P("after the newcomer walked to the shard:", ws)
ok("6. without an adult: picking up a shard does not count (shards=0/12)", "shards=0/" in ws and "eligible=false" in ws, ws)
# with an adult - visible and counted (first step away from the shard: once a participant, a player on a shard takes it in the same tick)
tp(0, 21, -33); time.sleep(1)
P("setcomp:", ld("setcomp ember2")[:80]); time.sleep(2.5)
for _ in range(15):
    sh2 = shards()
    if not sh2.startswith("0|"):
        break
    time.sleep(2)
time.sleep(1)
w2 = cd("weather"); P("client with an adult:", w2, "| server shards:", sh2)
ok("6. with an adult (setcomp ember2): eligible=true, bar and silhouette visible, shards visible", "eligible=true" in w2 and "bar=true" in w2 and "silhouette=true" in w2 and re.search(r"shardsVisible=[1-9]", w2) is not None, f"{w2} | {sh2}")
shot("F5_storm_visible")
if not sh2.startswith("0|"):
    sx, sy, sz = (float(v) for v in sh2.split("|")[1].split(","))
    tp(sx, sy + 3, sz); time.sleep(2)
ws2 = wd("state"); P("after the adult walked to the shard:", ws2)
ok("6. with an adult: the shard counted (shards>=1), the player is a participant", re.search(r"shards=[1-9]", ws2) is not None and "participant=true" in ws2, ws2)
errs = console_errors()
ok("console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("The 'first 10 minutes' pack (20.10): greeting, table, pickup radius, firstborn timers, FEED at the stall, Storm dragon")
s.close()
