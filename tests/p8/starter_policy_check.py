#!/usr/bin/env python3
"""The Starter Pack with a random rarity - only
where Roblox allows paid randomness (PolicyService ArePaidRandomItemsRestricted = false), and only after showing the odds;
in countries with a ban (BE, NL, AU, UK < 18, BR...) - the same pack without randomness: 2 Rare, no shiny and size. In a LOCAL file on P8,
two game sessions (the Studio profile is new each time), the flag is set by the debug `shop policy restricted|open` (the Studio country cannot be changed):
R - ban: the card 'Two Rare eggs', the pick screen 'Both eggs will be Rare' (no odds); a purchase, even if the client sent 'odds',
gives 2 Rare without variants, the purchase log random=false. A - allowed: the card 'Rare or better', on the pick screen before the purchase
button the odds of every outcome (sum 100) and of the variants; a purchase with 'odds' - a random variant (random=true).
Run: python3 tests/p8/starter_policy_check.py (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("starter_policy_check")
from p8lib import *  # noqa: F401,F403

LINE = (FIND + "local g=pg:FindFirstChild('Book') local c=g and g:FindFirstChild('Card_StarterPack_49',true) local l=c and c:FindFirstChild('Line') "
        "return l and l.ContentText or 'no card'")
ODDS = (FIND + "local g=pg:FindFirstChild('Book') local t={} if g then for _,o in g:GetDescendants() do if o:IsA('TextLabel') and o.Name:sub(1,11)=='StarterOdds' and shown(o) then "
        "local _, nl = string.gsub(o.ContentText, '\\n', '') table.insert(t, {o.Name, (string.gsub(o.ContentText, '\\n', ' | ')), o.TextBounds.Y / (nl + 1)}) end end end table.sort(t, function(a,b) return a[1]<b[1] end) "
        "if #t==0 then return 'no label' end local s,h={},{} for _,x in t do table.insert(s,x[2]) table.insert(h,math.floor(x[3])) end "
        "return table.concat(s,' | ')..' ##px '..table.concat(h,',')")


def session(tag, policy):
    stop(); start()
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
    P(f"[{tag}]", S(LD + "return ld('shop allow')")[:80])
    P(f"[{tag}]", S(LD + f"return ld('shop policy {policy}')")[:80])
    time.sleep(1.5)
    attr = C("return tostring(game.Players.LocalPlayer:GetAttribute('PaidRandomOK'))")
    press("HUD", "Menu_Shop"); press("Book", "Nest")
    line = C(LINE); P(f"[{tag}] card:", line); shot(f"{tag}_card")
    press("Book", "Price", inside="Card_StarterPack_49")
    odds = C(ODDS); P(f"[{tag}] pick screen:", odds); shot(f"{tag}_pick")
    # purchase by the server debug (the receipt process as in Roblox), the client 'sent odds' in both cases
    r = S(LD + "return ld('shop StarterPack_49 frost storm odds')"); P(f"[{tag}] purchase:", r[:160])
    time.sleep(2)
    d = dump()
    shelf = (d.get("eggs") or {}).get("shelf") or []
    eggs = {"eggs": [{"r": e.get("rarity"), "s": e.get("shiny"), "z": e.get("size"), "el": e.get("element")} for e in shelf if str(e.get("id", "")).startswith("starter")],
            "log": (d.get("purchaseLog") or [None])[-1]}
    P(f"[{tag}] given:", eggs)
    return attr, line, odds, eggs


attr, line, odds, got = session("R", "restricted")
ok("R: the player flag PaidRandomOK=false", attr == "false", attr)
ok("R: the card - 'Two Rare eggs', without 'Rare or better'", line.startswith("Two Rare eggs") and "Rare or better" not in line, line)
ok("R: on the pick screen - 'Both eggs will be Rare', no odds", odds.split(" ##px")[0] == "Both eggs will be Rare", odds)
e = got.get("eggs") or []
ok("R: 2 Rare given without shiny and size, the elements as chosen (although the client sent odds)", len(e) == 2 and all(x["r"] == "Rare" and not x["s"] and x["z"] == "normal" for x in e)
   and sorted(x["el"] for x in e) == ["frost", "storm"], json.dumps(e))
ok("R: the purchase log random=false", (got.get("log") or {}).get("random") is False, json.dumps(got.get("log")))

attr, line, odds, got = session("A", "open")
ok("A: the player flag PaidRandomOK=true", attr == "true", attr)
ok("A: the card - 'Rare or better'", "Rare or better" in line, line)
m = re.findall(r"(Uncommon|Rare|Epic|Legendary|Mythic) ([\d.]+)%", odds)
total = sum(float(x[1]) for x in m)
ok("A: before the purchase button the odds of every outcome, sum 100%", [x[0] for x in m] in (["Uncommon", "Rare", "Epic", "Legendary", "Mythic"], ["Rare", "Epic", "Legendary", "Mythic"]) and abs(total - 100) < 0.005,  # minRarity Rare - without Uncommon
   f"{odds} | sum {total:.2f}")
ok("A: the variant odds (Shiny, Big, Huge) are shown", all(w in odds for w in ("Shiny 4%", "Big 5%", "Huge 1%")), odds)
px = [int(x) for x in re.findall(r"\d+", odds.split("##px")[-1])] if "##px" in odds else []
ok("A: the odds are readable - text line height >= 12 px on a phone screen", px and min(px) >= 12, str(px))
e = got.get("eggs") or []
ok("A: 2 eggs given, not below Uncommon", len(e) == 2 and all(x["r"] in ("Uncommon", "Rare", "Epic", "Legendary", "Mythic") for x in e), json.dumps(e))
ok("A: the purchase log random=true", (got.get("log") or {}).get("random") is True, json.dumps(got.get("log")))
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[Shop\]", l) and "ExecuteLuau" not in l]
ok("console without shop errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Starter Pack: randomness only where Roblox allows it and after showing the odds")
s.close()
