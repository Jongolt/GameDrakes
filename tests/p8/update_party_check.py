#!/usr/bin/env python3
"""Update Party only before a real update. P8, LOCAL file
(after tools/p8/open_local.sh). The LiveOps clock is shifted by LiveOpsDebug offset, Weather takes the same clock:
  1) today (no shift) - no party: PartyEndsAt 0, mult 1, no 'Update Party' on the screen;
  2) Sun 08.11 18:45 UTC (15 min before Aurora) - the party: PartyEndsAt ~ +900 s, mult x2, the strip 'Update Party! New content in 14:5x',
     the banner 'Update Party! Coins x2 until the update';
  3) Sun 01.11 18:45 UTC (no update) - no party;
  4) Sun 15.11 18:45 UTC (Cinder) - there is a party;
  5) Sun 08.11 19:00 UTC (the update has started) - no party;
  6) Sun 06.12 18:45 UTC (no updates after Nightfall) - no party;
  7) console without game errors.
Run: python3 tests/p8/update_party_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/update_party_check/ (frames P*.jpg, result.md)."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("update_party_check")
from p8lib import *  # noqa: F401,F403

U = "local U=require(game.ReplicatedStorage.Shared.Content).Updates "
def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def at(expr):  # the LiveOps clock at the moment expr (Luau, via U and os.time())
    return S(U + f"return game.ServerStorage.LiveOpsDebug:Invoke('offset '..math.floor(({expr}) - os.time()))")
def wstate():  # PartyEndsAt - os.time() on the server (0 - no party) and the nest income multiplier
    a = S("local f=game.ReplicatedStorage:FindFirstChild('WeatherState') local pe=f and f:GetAttribute('PartyEndsAt') or 0 "
          "return string.format('left=%d', pe > 0 and pe - os.time() or 0)")
    w = S("return game.ServerStorage.WeatherDebug:Invoke('state')")
    m = re.search(r"left=(-?\d+)", a)
    k = re.search(r"kind=(\S*) storm=\S+ mult=(\S+)", w)
    return (int(m.group(1)) if m else -1), (k.group(1) if k else "?"), (float(k.group(2)) if k else -1.0)
# visible labels with 'Update Party' on the player screen over N seconds (the banner lives ~3 s, the strip - while the party is on)
SCAN = ("local pg=game.Players.LocalPlayer.PlayerGui local seen={} local order={} "
        "local function vis(g) while g and g~=pg do if g:IsA('GuiObject') and not g.Visible then return false end "
        "if g:IsA('ScreenGui') and not g.Enabled then return false end g=g.Parent end return true end "
        "for _=1,{n} do for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and string.find(d.Text,'Update Party',1,true) and vis(d) then "
        "local t=d.Text if not seen[t] then seen[t]=true order[#order+1]=t end end end task.wait(0.5) end return table.concat(order,' || ')")
def scan(sec): return C(SCAN.replace("{n}", str(int(sec * 2))))
# the strip icon (a TextLabel next to the strip text): 🎉 during a party without weather, otherwise the weather icon
ICONQ = ("local pg=game.Players.LocalPlayer.PlayerGui for _,d in pg:GetDescendants() do if d:IsA('TextLabel') and string.find(d.Text,'New content in',1,true) then "
         "local b=d.Parent for _,c in b:GetDescendants() do if c:IsA('TextLabel') and c~=d and #c.Text>0 and #c.Text<=8 then return c.Text end end end end return '-'")
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def game_errors(lines):
    return [l for l in lines if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l
            and "TexturePack" not in l and "errors 0" not in l and "RSVP" not in l]
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)


def case(tag, expr, party, shot_name=None):
    P(f"[{tag}] clock:", at(expr))
    texts = scan(7)  # the Weather loop - once every 5 s: in 7 s a tick has surely passed (the banner lives ~3 s - we catch it here)
    after = scan(4)  # after the tick: a clock jump back clears the strip only on the next tick (in the game the clock does not go back)
    left, kind, mult = wstate()
    P(f"[{tag}] left={left} kind={kind} mult={mult} labels: {texts or '-'} | after the tick: {after or '-'}")
    if shot_name:
        shot(shot_name)
    base = 2.0 if kind == "storm" else 1.0  # a storm is x2 by itself (real clock)
    if party:
        ok(f"{tag}: the party is on, 840-900 s to the end", 840 <= left <= 900, f"left={left}")
        ok(f"{tag}: nest income x2", abs(mult - base * 2) < 1e-6, f"mult={mult} kind={kind}")
        ic = C(ICONQ); P(f"[{tag}] strip icon:", ic)
        ok(f"{tag}: strip icon 🎉", ic == "🎉" or kind != "", ic)
        ok(f"{tag}: the strip 'Update Party! New content in 14:..'", re.search(r"Update Party! New content in 1[45]:\d\d", after) is not None
           or kind != "", after)
    else:
        ok(f"{tag}: no party (PartyEndsAt 0)", left == 0, f"left={left}")
        ok(f"{tag}: nest income without x2", abs(mult - base) < 1e-6, f"mult={mult} kind={kind}")
        ok(f"{tag}: no 'Update Party' on the screen (after the tick)", after == "", after)
    return texts


stop(); start(); wait_world()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
P("clock:", lo("offset 0")); time.sleep(6)
case("1. today", "os.time()", False, "P1_today")
t2 = case("2. Sun 08.11 18:45 (Aurora in 15 min)", "U[1].activeFrom - 900", True, "P2_aurora_1845")
ok("2. the banner 'Update Party! Coins x2 until the update' shown", "Update Party! Coins x2 until the update" in t2, t2)
case("3. Sun 01.11 18:45 (no update)", "U[1].activeFrom - 7*86400 - 900", False, "P3_nov01_1845")
t4 = case("4. Sun 15.11 18:45 (Cinder in 15 min)", "U[2].activeFrom - 900", True, "P4_cinder_1845")
case("5. Sun 08.11 19:00:30 (Aurora started)", "U[1].activeFrom + 30", False, "P5_aurora_1900")
case("6. Sun 06.12 18:45 (no updates after Nightfall)", "U[4].activeFrom + 7*86400 - 900", False, "P6_dec06_1845")
P("clock:", lo("offset 0"))
errs = game_errors(console_lines())
ok("7. console without game errors", not errs, " ;; ".join(errs[:4]))
stop()
write_result("Update Party only before a real update (21.10, spec 09 Add. 21.10)")
s.close()
