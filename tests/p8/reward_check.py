#!/usr/bin/env python3
"""Acceptance in a LOCAL file on P8 (window 834x630 = phone 812x375; the profile is not saved - every start is a newcomer).
(A) egg labels only on Meadow (28), sparkle on all eggs, A/B by UserId on the client, LedgeGlow invisible.
(B) 2.4: the Gifts pill, time gifts (click Claim, not_ready, already), calendar days 1-7 (eggs on the shelf, lantern, a Rare baby
with an element choice), shelf -> incubator, 3 dailies + bonus, berries, rare nest, a full UI check, console.
Run: python3 tests/p8/reward_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("reward_check")
from p8lib import *  # noqa: F401,F403

stop(); start()
P("UserId:", C("return tostring(game.Players.LocalPlayer.UserId)"))

# ------------------------------------------------------------------------------------------------ (A) eggs and the ledge
time.sleep(3)
a = S("""
local CS=game:GetService('CollectionService')
local pts=workspace:FindFirstChild('EggPoints',true)
local lab={} local spark,eggs=0,0 local bad={}
for _,a in pts:GetChildren() do
  local egg=a:FindFirstChild('Egg')
  if egg then eggs+=1
    local z=a:GetAttribute('Zone') local nb,md=0,0
    for _,d in egg:GetDescendants() do
      if d:IsA('BillboardGui') then nb+=1 md=d.MaxDistance if not CS:HasTag(d,'EggLabel') then table.insert(bad,'notag '..a.Name) end end
      if d:IsA('ParticleEmitter') and d.Name=='Sparkle' then spark+=1 end
    end
    lab[z]=(lab[z] or 0)+nb
    if nb>0 and (z~='Meadow' or md~=28) then table.insert(bad,a.Name..' '..z..' '..md) end
    if z=='Meadow' and nb==0 and not a:GetAttribute('Secret') then table.insert(bad,'nolabel '..a.Name) end
  end
end
local lg,tr=0,''
for _,p in workspace:GetDescendants() do if p.Name=='LedgeGlow' and p:IsA('BasePart') then lg+=1 tr=tr..p.Transparency..',' if not CS:HasTag(p,'Ledge') then table.insert(bad,'ledge notag') end end end
return string.format('eggs=%d spark=%d Meadow=%d Cliffs=%d Springs=%d Summit=%d ledge=%d tr=%s bad=%s',eggs,spark,lab.Meadow or 0,lab.Cliffs or 0,lab.Springs or 0,lab.Summit or 0,lg,tr:sub(1,30),table.concat(bad,';'))""")
P("A:", a)
m = dict(re.findall(r"(\w+)=(\d+)", a))
ok("A: sparkle on every island egg except the secret grotto", int(m.get("eggs", 0)) >= 30 and int(m.get("spark", 0)) == int(m.get("eggs", 0)) - 1, a)
ok("A: labels only on Meadow (MaxDistance 28), Cliffs/Springs/Summit without a label", int(m.get("Meadow", 0)) >= 9 and m.get("Cliffs") == "0" and m.get("Springs") == "0" and m.get("Summit") == "0" and "bad=" in a and a.endswith("bad="), a)
ok("A: LedgeGlow invisible in all nests, the Ledge tag in place", int(m.get("ledge", 0)) >= 6 and re.search(r"tr=(1,)+", a) is not None, a)
cl = C("local CS=game:GetService('CollectionService') local n,on=0,0 for _,g in CS:GetTagged('EggLabel') do n+=1 if g.Enabled then on+=1 end end "
       "local E=require(game.ReplicatedStorage.Shared.Core.Experiments) local want=E.eggLabels(game.Players.LocalPlayer.UserId, require(game.ReplicatedStorage.Shared.Config).World.eggMarks) "
       "return string.format('n=%d on=%d want=%s', n, on, tostring(want))")
P("A client:", cl)
mm = dict(re.findall(r"(\w+)=(\w+)", cl))
ok("A: client labels by the A/B group", int(mm.get("n", 0)) > 0 and ((mm.get("want") == "true" and mm.get("on") == mm.get("n")) or (mm.get("want") == "false" and mm.get("on") == "0")), cl)

# ------------------------------------------------------------------------------------------------ (B) time gifts
st = rw(); P("B start:", st)
ok("B: newcomer - calendar day 1 waits, the dailies are picked", "calendar day=1 claimed=0" in st and re.search(r"daily \d{4}-\d\d-\d\d \[\w+ 0/\d+", st) is not None, st)
p0 = pill(); P("pill:", p0)
ok("B: the pill with a timer to the 5th gift and the calendar dot", re.match(r"\d:\d\d \| badge=1", p0) is not None, p0)
rw("time 610"); time.sleep(2)
p1 = pill(); P("pill 10:10:", p1)
ok("B: at 10:10 - Claim! and 3 ready (5, 10, day 1)", p1.startswith("Claim! | badge=3"), p1)
C(CD + "cd('menu gifts') task.wait(1.5) return 'ok'")
r = sweep("gifts_tab")
ok("B: the Gifts tab on a phone - no overflows or overlaps", "ISSUES[0]" in r, r[:300])
coins0 = dump()["coins"]
press("Book", "Claim", name="click Claim"); desk("reward_click"); time.sleep(2.5)
d1 = dump(); cl1 = d1["rewards"]["timeGifts"]["claimed"]; cl1 = cl1 if isinstance(cl1, dict) else {}  # an empty table in JSON - []
P("after the click: coins", coins0, "->", d1["coins"], "claimed", cl1, "calendar", d1["rewards"]["calendar"])
P("tabs:", C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local t={} if b then for _,o in b:GetDescendants() do if o.Name=='Word' and o:IsA('TextLabel') then table.insert(t,o.ContentText..'='..o.TextBounds.Y..'/'..o.AbsoluteSize.X..'x'..o.AbsoluteSize.Y) end end end return table.concat(t,' ')"))
ok("B: click Claim - the first ready one claimed (calendar day 1 or the 5 min gift), coins arrived", (cl1.get("5") is True or d1["rewards"]["calendar"]["claimed"] == 1) and d1["coins"] >= coins0 + 100, f"{coins0}->{d1['coins']}")
shot("gifts_after_claim")
ok("B: gift 15 before its time - not_ready", claim("timeGift", "15") == "false/not_ready")
ok("B: gift 10 - ok, repeat - already", claim("timeGift", "10") == "true/nil" and claim("timeGift", "10") == "false/already")
if d1["rewards"]["calendar"]["claimed"] == 1:  # the click claimed day 1 - claim gift 5 by a call
    ok("B: gift 5 - ok", claim("timeGift", "5") == "true/nil")
ok("B: a foreign id - bad_request", claim("timeGift", "7") == "false/bad_request")

# ------------------------------------------------------------------------------------------------ calendar 1-7
shelf0 = len(dump()["eggs"]["shelf"])
for day in range(1, 8):
    if day == 7:
        C(CD + "cd('menu gifts') task.wait(1.5) return 'ok'")
        r7 = sweep("gifts_day7_pick")
        ok("B: day 7 - the element choice on screen without overflows", "ISSUES[0]" in r7, r7[:300])
        el = C("local R=require(game.ReplicatedStorage.Shared.Core.Rewards) return R.choices(7, require(game.ReplicatedStorage.Shared.Config).Elements, 3)[2]")
        ok("B: day 7 without an element - bad_request", claim("calendar") == "false/bad_request")
        n0 = len(dump()["dragons"])
        ok(f"B: day 7 Rare baby ({el})", claim("calendar", el) == "true/nil")
        time.sleep(4)
        dd = dump(); new = [x for x in dd["dragons"].values() if x.get("rarity") == "Rare" and x.get("element") == el]
        ok("B: day 7 - a Rare dragon of the chosen element in the profile", len(dd["dragons"]) == n0 + 1 and len(new) >= 1, f"{n0}->{len(dd['dragons'])}")
        shot("day7_hatch")
    elif day == 1 and dump()["rewards"]["calendar"]["claimed"] == 1:
        P("day 1 already claimed by the click")
    else:
        rc = claim("calendar"); P(f"day {day}:", rc)
        ok(f"B: calendar day {day} claimed", rc == "true/nil", rc)
    ok(f"B: day {day} - repeat already", claim("calendar") == "false/already")
    if day < 7:
        st = rw("day"); ok(f"B: next day {day + 1}", f"calendar day={day + 1} claimed={day}" in st, st[-120:])
dd = dump()
# day 2 - a Rare dragon for everyone (Config.Rewards.calendar.d2ab.force = "B"), an egg on the shelf only for day 6 (Springs)
# without force - a split by the third UserId bit (group A gets a Cliffs egg)
d2 = C("local C=require(game.ReplicatedStorage.Shared.Config) local E=require(game.ReplicatedStorage.Shared.Core.Experiments) "
       "return E.d2Group(game.Players.LocalPlayer.UserId, C.Rewards.calendar.d2ab)")
want_eggs = 1 if d2 == "B" else 2
ok(f"B: calendar eggs on the shelf (day 6 Springs{'' if d2 == 'B' else ' + day 2 Cliffs'}; group d2={d2})", len(dd["eggs"]["shelf"]) >= shelf0 + want_eggs, f"{shelf0}->{len(dd['eggs']['shelf'])}")
lan = S("local n=0 for _,m in workspace:GetDescendants() do if m.Name=='RewardLantern' then n+=1 end end return tostring(n)")
ok("B: day 5 - the lantern in the nest", lan == "1" and dd.get("owned", {}).get("lantern") is True, lan)
she = S("local n=0 for _,m in workspace:GetDescendants() do if m.Name=='ShelfEgg' then n+=1 end end return tostring(n)")
ok("B: the shelf eggs are visible in the bowls", int(she) == min(len(dd["eggs"]["shelf"]), 5), f"models {she}, in the profile {len(dd['eggs']['shelf'])}")

# ------------------------------------------------------------------------------------------------ shelf -> incubator
S(LD + "return ld('go inc')"); time.sleep(3)
d2 = dump(); P("incubators:", json.dumps(d2["eggs"]["incubating"])[:200], "shelf", len(d2["eggs"]["shelf"]))
ok("B: at the ring the shelf egg went into the incubator by itself", len(d2["eggs"]["incubating"]) >= 1 and len(d2["eggs"]["shelf"]) == len(dd["eggs"]["shelf"]) - 1, f"shelf {len(dd['eggs']['shelf'])}->{len(d2['eggs']['shelf'])}")

# ------------------------------------------------------------------------------------------------ dailies
ids = d2["quests"]["daily"]["ids"]; P("daily quests:", ids)
c0 = d2["coins"]; sh0 = len(d2["eggs"]["shelf"])
for i in ids:
    ev, n = DAILY[i]
    P("  ", i, rw(f"daily {ev} {n}")[-160:])
time.sleep(4.5)
d3 = dump(); dl = d3["quests"]["daily"]
ok("B: all three dailies done, bonus", all(dl["done"].get(t) for t in ("easy", "medium", "hard")) and dl["bonus"] is True, json.dumps(dl)[:200])
ok("B: coins for the dailies, 4 season points, a Cliffs egg for all three", d3["coins"] >= c0 + 300 and d3["rewards"]["season"]["points"] == 4 and len(d3["eggs"]["shelf"]) == sh0 + 1,
   f"coins {c0}->{d3['coins']} season {d3['rewards']['season']['points']} shelf {sh0}->{len(d3['eggs']['shelf'])}")
C(CD + "cd('menu quests') task.wait(1.5) return 'ok'")
r = sweep("quests_tab")
ok("B: the Quests tab with the dailies - no overflows", "ISSUES[0]" in r, r[:300])

# ------------------------------------------------------------------------------------------------ berries and rare nest
rw("time 5410"); time.sleep(1.5)
c1 = dump()["coins"]
ok("B: gift 15 (berries) - ok", claim("timeGift", "15") == "true/nil")
ok("B: gift 90 (rare nest) - ok", claim("timeGift", "90") == "true/nil")
time.sleep(1)
d4 = dump()
ok("B: rare nest - an egg on the shelf with rareNest", any(e.get("rareNest") for e in d4["eggs"]["shelf"]), json.dumps(d4["eggs"]["shelf"])[:200])
P("berries: coins", c1, "->", d4["coins"], "| dragons:", [(k, v.get("fedUntil")) for k, v in d4["dragons"].items()])
C(CD + "cd('back') return 'ok'"); time.sleep(1)
P("pill at the end:", pill()); shot("hud_end")
ok("B: Active (there was input) without an error", C("game.ReplicatedStorage.Remotes.Active:FireServer() return 'ok'") == "ok")

cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[Reward\]|\[Gifts\]|\[Net\]|failed|Error", l) and "not authorized" not in l]
ok("console without errors", not errs, " ;; ".join(errs[:6]))
stop()
P("RESULT:", f"{sum(1 for r in res if r[1])}/{len(res)} OK")
for r in res:
    if not r[1]:
        P("  FAIL", r[0], "|", r[2][:300])
write_result()
s.close()
