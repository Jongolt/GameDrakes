#!/usr/bin/env python3
"""The Lua heap of OUR VMs (client and server) on P8 via the debug commands ClientDebug 'gc' / LoopDebug 'gc' (gcinfo inside
our scripts; execute_luau measures its own plugin VM). Points: join, nest with 3 adults, 2 minutes idle (growth = leak).
Plus the Perf detail() line with the new fields gc=/scr=/int= - as the phone log will see it. Run after tools/p8/open_local.sh."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("memory_gc_check")
from p8lib import *  # noqa: F401,F403

TAGS = ("local Stats=game:GetService('Stats') local f=function(n) local ok,v=pcall(function() return Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag[n]) end) return ok and math.floor(v) or -1 end "
        "return string.format('total=%d lua=%d scr=%d int=%d ins=%d trn=%d tex=%d snd=%d gui=%d', Stats:GetTotalMemoryUsageMb(), f('LuaHeap'), f('Script'), f('Internal'), f('Instances'), f('GraphicsTerrain'), f('GraphicsTexture'), f('Sounds'), f('Gui'))")
def gc_point(name):
    c = C(CD + "return tostring(cd('gc'))"); sv = S(LD + "return tostring(ld('gc'))"); t = C(TAGS)
    P(f"[{name}] client {c} | server {sv} | {t}")
    return c, sv, t
def mb(s):
    m = re.search(r"gc=([\d.]+)MB", s or ""); return float(m.group(1)) if m else -1

start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
time.sleep(12)
p0 = gc_point("spawn")
ok("ClientDebug gc answers (client Lua heap of our VM)", mb(p0[0]) > 0, p0[0])
ok("LoopDebug gc answers (server Lua heap)", mb(p0[1]) > 0, p0[1])
for k in (1, 2, 3):
    S(LD + f"ld('go table') task.wait(0.8) ld('table {k}') task.wait(0.5) ld('go inc') task.wait(1) ld('place 1') task.wait(0.5) ld('time 900') task.wait(1.5) ld('hatch 1') return 'h{k}'"); time.sleep(9)
    if gui_on("NameDialog"): time.sleep(6)
S(LD + "ld('time 100000') task.wait(3) ld('go pile') return 'adults'"); time.sleep(6)
p1 = gc_point("nest3_adults")
time.sleep(60); p2 = gc_point("idle_1m")
time.sleep(60); p3 = gc_point("idle_2m")
ok("the client Lua heap does not grow by more than 10 MB over 2 min idle", mb(p3[0]) - mb(p2[0]) < 10 and mb(p3[0]) - mb(p1[0]) < 20, f"{mb(p1[0])} -> {mb(p2[0])} -> {mb(p3[0])} MB")
ok("the server Lua heap does not grow by more than 10 MB over 2 min idle", mb(p3[1]) - mb(p1[1]) < 10, f"{mb(p1[1])} -> {mb(p3[1])} MB")
# the Perf detail() line - as in the phone log: read via an attribute/log? Perf writes to the server once every `every` s; here - a direct read of the fields
det = C("local Stats=game:GetService('Stats') return string.format('gc=%d lua=%d scr=%d int=%d', math.floor(gcinfo()/1024+0.5), Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.LuaHeap), Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Script), Stats:GetMemoryUsageMbForTag(Enum.DeveloperMemoryTag.Internal))")
P("fields (plugin VM for gc, shared tags):", det)
shot("GC_end")
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
write_result("Lua heap of our VMs (client/server) on P8, 20.10")
s.close()
