#!/usr/bin/env python3
"""The teen grew into an adult under the rider -> Movement.regrowRider remounts onto the adult in place (on the ground),
otherwise 'Your dragon can fly!' shows while taking off is impossible.
Check: (1) baby -> teen, riding (Fly.state s1); (2) growth under the rider (LoopDebug time) -> after <= 6 s riding again, Fly.state
s2, the companion model Stage 2; (3) holding Up -> a climb of 6 studs in <= 4 s; (4) no '[Movement] regrow' and no Movement errors in the console.
Run: python3 tests/p8/regrow_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("regrow_check")
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

CD = "local cd=function(a) return game.Players.LocalPlayer.PlayerGui:WaitForChild('ClientDebug'):Invoke(a) end "
FLY = CD + "return tostring(cd('fly state'))"
COMP = ("local p=game.Players:GetPlayers()[1] local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do "
        "if x:GetAttribute('OwnerId')==p.UserId then m=x end end "
        "local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid') local seat=h and h.SeatPart "
        "return string.format('stage=%s mounted=%s seatIn=%s y=%.1f', tostring(m and m:GetAttribute('Stage')), tostring(p:GetAttribute('Mounted')), "
        "tostring(seat~=nil and m~=nil and seat:IsDescendantOf(m)), m and m.PrimaryPart and m.PrimaryPart.Position.Y or -1)")
BODY_Y = ("local p=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do "
          "if x:GetAttribute('OwnerId')==p.UserId then m=x end end return m and m.PrimaryPart and string.format('%.2f', m.PrimaryPart.Position.Y) or 'nocomp'")

stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
n0 = len(console_lines())
P("give egg:", ld("give egg Meadow")[:60]); time.sleep(0.8)
P("place 1:", ld("place 1")[:60]); time.sleep(3.5)
P("hatch 1:", ld("hatch 1")[:60]); time.sleep(6)
P("time -> teen:", ld("time 100000")[:60]); time.sleep(5)
cs = C("return tostring(game.Players.LocalPlayer:GetAttribute('CompanionStage'))")
ok("teen (CompanionStage 1)", cs == "1", cs)
P("mount:", ld("mount")[:80]); time.sleep(2.5)
st1 = C(FLY)
ok("riding the teen (Fly.state s1)", " s1 " in st1, st1[:120])
P("before the growth:", S(COMP))
shot("R1_juvenile")
P("time -> adult under the rider:", ld("time 100000")[:60])
t0 = time.time(); got = None
while time.time() - t0 < 12:
    c = S(COMP)
    if "stage=2" in c and "seatIn=true" in c and "mounted=nil" not in c:
        got = time.time() - t0
        break
    time.sleep(0.5)
P("after the growth:", S(COMP), "in", got)
ok("remount onto the adult (Stage 2, in the saddle, Mounted) in <= 6 s", got is not None and got <= 6, f"{got}")
time.sleep(1.5)
st2 = C(FLY)
ok("client: riding the adult (Fly.state s2)", " s2 " in st2, st2[:120])
shot("R2_adult")
yb = C(BODY_Y)
y0 = float(yb) if re.match(r"^-?\d", yb) else None
C(CD + "return tostring(cd('fly up on'))")
t1 = time.time(); rise = None; ys = []
while time.time() - t1 < 12 and y0 is not None:
    y = C(BODY_Y)
    if re.match(r"^-?\d", y):
        ys.append((round(time.time() - t1, 1), round(float(y) - y0, 1)))
        if float(y) - y0 >= 6:
            rise = time.time() - t1
            break
    time.sleep(0.3)
C(CD + "return tostring(cd('fly up off'))")
shot("R3_air")
ok("takeoff after the remount: +6 studs in <= 4 s", rise is not None and rise <= 4.0, f"{rise}; {ys[:12]}")
lines = console_lines()[n0:]
bad = [l for l in lines if "[Movement]" in l and ("regrow" in l or "error" in l.lower())] + [l for l in lines if "Movement.luau" in l]
ok("console: no remount/Movement errors", not bad, " | ".join(bad[:3]))
C(CD + "return tostring(cd('fly off'))"); time.sleep(2)
stop()
write_result("regrow_check: remount onto the one that grew under the rider")
