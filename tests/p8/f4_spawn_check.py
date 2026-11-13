#!/usr/bin/env python3
"""A newcomer with the first dragon WITHOUT time -
grows into a teen by itself (firstborn ~60 s) -> the golden nest appears -> the glowEgg spawn event on the client and the banner. From the very start
we log the glowEgg events and all banner texts with timestamps on the client. Checks: (1) spawn arrived, (2) the banner with the golden text was on
screen, (3) the nest exists. Run: python3 tests/p8/f4_spawn_check.py (after open_local.sh)."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("f4_spawn_check")
from p8lib import *  # noqa: F401,F403


def ld(c): return S(LD + f"return ld('{c}')")
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)

HOOK = ("workspace:SetAttribute('GEv','') workspace:SetAttribute('BAN','') local t0=os.clock() "
        "game.ReplicatedStorage.Remotes.Notice.OnClientEvent:Connect(function(p) if type(p)=='table' and p.kind=='glowEgg' then "
        "workspace:SetAttribute('GEv',(workspace:GetAttribute('GEv') or '')..string.format(' %s@%.1f',tostring(p.ev),os.clock()-t0)) end end) "
        "task.spawn(function() local pg=game.Players.LocalPlayer.PlayerGui local last='' while os.clock()-t0<200 do "
        "local b=pg:FindFirstChild('Banners') local f=b and b:FindFirstChild('Banner',true) local l=f and f:FindFirstChild('L1') "
        "local tx=(l and f.Visible) and l.Text or '' if tx~=last then last=tx if tx~='' then workspace:SetAttribute('BAN',(workspace:GetAttribute('BAN') or '')..string.format(' | %s@%.1f',tx,os.clock()-t0)) end end task.wait(0.05) end end) "
        "workspace:SetAttribute('T0',t0) return 'hook'")
STAGE = "return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))"
GLOW = ("local f=workspace:FindFirstChild('GlowEggs') local n=f and f:FindFirstChild('GlowEgg_'..game.Players:GetPlayers()[1].UserId) return n and 'yes' or 'none'")

stop(); start(); wait_world()
P("hook:", C(HOOK))
P("give egg:", ld("give egg Meadow")[:60]); time.sleep(0.8)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(4)
P("stage after hatching:", C(STAGE))
t0 = time.time(); st1 = None; nest = None
while time.time() - t0 < 120:
    st = C(STAGE)
    if st1 is None and st in ("1", "2", "3"):
        st1 = round(time.time() - t0, 1)
    g = S(GLOW)
    if nest is None and g == "yes":
        nest = round(time.time() - t0, 1)
    if st1 is not None and nest is not None and time.time() - t0 > (nest + 12):
        break
    time.sleep(1)
ev = C("return tostring(workspace:GetAttribute('GEv'))")
ban = C("return tostring(workspace:GetAttribute('BAN'))")
P("teen after", st1, "s; nest after", nest, "s"); P("glowEgg ev:", ev); P("banners:", ban[:600])
ok("the nest appeared (no time, the firstborn grew by itself)", nest is not None, f"{nest}")
ok("the server sent glowEgg spawn", "spawn@" in ev, ev[:200])
ok("the banner 'A GOLDEN NEST WITH A GLOWING EGG!' was on screen", "A GOLDEN NEST" in ban, ban[:300])
shot("F4_after")
stop()
write_result("f4_spawn_check: golden nest - event and banner")
