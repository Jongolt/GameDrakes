#!/usr/bin/env python3
"""The Feed prompt at the Keeper stall (WorldUI.stallPrompt): the spawn point is 10 studs from the stall, so the prompt is visible only if the player has a dragon with the
CanFeed tag. In a LOCAL file on P8: (1) joining as a newcomer - the prompt is off; (2) egg from the table -> incubator -> hatch -
a hungry baby, the prompt is on; a real press at the stall feeds (fedUntil), quest 4 counted; (3) fed - off.
Run: python3 tests/p8/stall_feed_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("stall_feed_check")
from p8lib import *  # noqa: F401,F403

PR = ("local s for _,x in game:GetService('CollectionService'):GetTagged('Stall') do s=x end local pr=s and s:FindFirstChild('StallFeed') "
      "local ch=game.Players.LocalPlayer.Character local d=ch and s and (Vector3.new(ch:GetPivot().Position.X,0,ch:GetPivot().Position.Z)-Vector3.new(s.Position.X,0,s.Position.Z)).Magnitude or -1 "
      "local n=0 for _,m in game:GetService('CollectionService'):GetTagged('CanFeed') do if m:GetAttribute('OwnerId')==game.Players.LocalPlayer.UserId then n+=1 end end "
      "return string.format('prompt=%s enabled=%s dist=%.1f max=%s canFeed=%d shown=%d', tostring(pr~=nil), tostring(pr and pr.Enabled), d, tostring(pr and pr.MaxActivationDistance), n, _G.stallShown or 0)")
def ld(c): return S(LD + f"return ld('{c}')")

stop(); start()
for _ in range(40):
    if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
        break
    time.sleep(3)
time.sleep(3)
C("_G.stallShown=0 game:GetService('ProximityPromptService').PromptShown:Connect(function(p) if p.Name=='StallFeed' then _G.stallShown+=1 end end) return 'ok'")
st0 = C(PR); P("join:", st0); shot("S1_start")
ok("joining as a newcomer: the stall prompt exists but is off (nobody to feed)", "prompt=true" in st0 and "enabled=false" in st0, st0)
# the spawn point floats: the character stood 11.9 and 13.5 studs from the stall with a prompt radius of 12 - for information
P("to the stall on join (prompt radius 12):", re.search(r"dist=[\d.]+", st0).group(0) if "dist=" in st0 else st0)

for c in ("table 1", "place 1", "time 900", "hatch 1"):
    P(c, "->", ld(c)[:160]); time.sleep(1.5)
time.sleep(3)
# coins for berries (a Common baby - 60, a newcomer has 50 after the hatch): nest income, the pile at the nest
for _ in range(20):
    if dump().get("coins", 0) >= 70:
        break
    ld("go pile"); time.sleep(3)
P("coins before the stall:", dump().get("coins"))
# a new
# spawn with a hungry dragon - no button on the slab; stepped off the slab toward the stall - it is there
S("game.Players:GetPlayers()[1]:LoadCharacter() return 'ok'")
time.sleep(5)
st_sp = C(PR); P("new spawn, hungry baby:", st_sp); shot("S2a_spawn_hungry")
ok("new spawn with a hungry dragon: on the slab the stall button is off", "canFeed=0" not in st_sp and "enabled=false" in st_sp, st_sp)
C("local s for _,x in game:GetService('CollectionService'):GetTagged('Stall') do s=x end local ch=game.Players.LocalPlayer.Character "
  "if s and ch then ch:PivotTo(CFrame.new(s.Position+Vector3.new(0,3,-7))) end return 'ok'")
time.sleep(2)
st1 = C(PR); P("hungry baby:", st1); shot("S2_hungry")
ok("stepped off the slab toward the stall (within the radius all the time), hungry baby: the button is on and shown", "enabled=true" in st1 and "canFeed=0" not in st1 and "shown=0" not in st1, st1)
q0 = dump().get("quests", {}).get("keeper", {})
r = C("local s for _,x in game:GetService('CollectionService'):GetTagged('Stall') do s=x end local pr=s and s:FindFirstChild('StallFeed') "
      "if not pr or not pr.Enabled then return 'no prompt' end pr:InputHoldBegin() task.wait(0.2) pr:InputHoldEnd() return 'pressed'")
P("press at the stall:", r); time.sleep(3)
st2 = C(PR); P("after feeding:", st2); shot("S3_fed")
d = dump()
fed = [u for u, x in (d.get("dragons") or {}).items() if (x.get("fedUntil") or 0) > 0]
P("fed dragons:", fed, "quest:", q0, "->", d.get("quests", {}).get("keeper", {}))
ok("the press at the stall fed the baby (fedUntil)", r == "pressed" and len(fed) >= 1, f"{r} {fed}")
ok("fed baby: the prompt is off", "enabled=false" in st2, st2)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[WorldUI\]", l) and "ExecuteLuau" not in l]
ok("console without script errors (WorldUI)", not errs, " ;; ".join(errs[:5]))
stop()
write_result("The Feed button at the stall: only when there is someone to feed and not on the spawn slab")
s.close()
