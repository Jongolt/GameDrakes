#!/usr/bin/env python3
"""Pass buttons next to the coins, the pass card, the likes goal banner, the page codes.
P8, LOCAL file (after tools/p8/open_local.sh, window 834x630 = phone 812x375). Profile - seed_pearl (a nest of 4 dragons
brings coins), 3 sessions (Robux buttons allowed), x2/Auto Collect not bought, the first flight happened, the 'favorite' prompt has not happened yet.
0) PC 812 with the Roblox player list at the top right: the buttons are not placed (zone), nothing overlaps. Then the player list is off -
the layout as on a phone (no touches in Studio, a phone has no list at the top right): 1) both buttons visible; 2-3) to the right of the pill
in a row (on the left on PC is the Roblox chat window - a click there goes to the chat), height >= minPx, inside the screen, without HUD overlaps;
5) a real click on x2 - the card: title, WHAT YOU GET, 3 lines, Buy once, price; 6) Not now closes, the HUD is back;
7) the cross closes the Auto Collect card; 8) windows do not open at the same time: the card is open, the player dismounted
the dragon - the 'favorite' prompt and the goal banner wait until the card is closed, then go; 9) riding - no buttons, dismounted - they are there;
10) x2 bought - its button is gone, Auto is there; 11) the Auto card is open, Auto bought - the card closed, no buttons;
12) codes: DRAGONS before 26.10 - bad_code; from 26.10 - ok + coins, the second time already; 50LIKES before the goal - bad_code; 4) at the end (changing the Studio window
breaks the clicks): PC 1200x675 with the player list and a narrow 667x375 without it - visible on the right, inside the screen, without overlaps and outside the
player list zone (~244 px); 13) console without game errors.
Run: python3 tests/p8/passchips_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/passchips_check/ (result.md, frames)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("passchips_check")
from p8lib import *  # noqa: F401,F403

SEED = os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_event_covers_2026-10-21", "seed_pearl.json")
X2, AUTO = "PassChip_X2Coins_299", "PassChip_AutoCollect_149"


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def lo(c): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{c}')")
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def game_errors(lines):
    return [l for l in lines if re.search(r"Stack Begin|attempt to|error|PassChips", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l
            and "TexturePack" not in l and "errors 0" not in l and "RSVP" not in l]
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def up(on):
    C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') if g then g:SetAttribute('Up'," + ("true" if on else "false") + ") end return 'ok'")


# geometry: the buttons, the pill, the screen and the rectangles of the other HUD elements (like UIKit.hudRects, without the buttons themselves and the coin pill)
GEO = r"""
local pg=game.Players.LocalPlayer.PlayerGui
local hud=pg:FindFirstChild('HUD')
local function vis(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local function r(o) local a,z=o.AbsolutePosition,o.AbsoluteSize return {a.X,a.Y,a.X+z.X,a.Y+z.Y} end
local out={chips={},others={}}
local pill=hud and hud:FindFirstChild('Coins') and hud.Coins:FindFirstChild('Pill')
out.pill=pill and r(pill)
out.screen={hud and hud.AbsoluteSize.X or 0, hud and hud.AbsoluteSize.Y or 0}
for _,n in {'%s','%s'} do local b=hud and hud:FindFirstChild(n) out.chips[n]= b and {vis=vis(b), rect=r(b)} or 'none' end
local function add(name,o) if o and o:IsA('GuiObject') and vis(o) and o.AbsoluteSize.X>1 then table.insert(out.others,{name, r(o)}) end end
if hud then for _,c in hud:GetChildren() do if c.Name=='LeftColumn' then for _,b in c:GetChildren() do add('Left/'..b.Name,b) end elseif c.Name~='Coins' and not c.Name:find('^PassChip_') then add('HUD/'..c.Name,c) end end end
for _,gn in {'StepBanner','Quests','FreeGiftCard','InviteCard','Topbar','Movement'} do local g=pg:FindFirstChild(gn) if g and g.Enabled then for _,d in g:GetDescendants() do if d:IsA('GuiButton') or d.Name=='Step' or d.Name=='Next' or d.Name=='Panel' then add(gn..'/'..d.Name,d) end end end end
out.touch=game:GetService('UserInputService').TouchEnabled
out.plist=game:GetService('StarterGui'):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
return game:GetService('HttpService'):JSONEncode(out)
""" % (X2, AUTO)


def nolist():  # like on a phone: no Roblox player list at the top right (HUD.setVisible turns it on again - call before clicks)
    C("game:GetService('StarterGui'):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false) return 'ok'"); time.sleep(1.2)


def geo():
    return json.loads(C(GEO))
def overlap(a, b):
    return a[0] < b[2] - 1 and b[0] < a[2] - 1 and a[1] < b[3] - 1 and b[1] < a[3] - 1
def chip_vis(g, n):
    c = g["chips"].get(n)
    return isinstance(c, dict) and c["vis"]


prof = json.load(open(SEED))
prof["lastSeen"] = int(time.time())
prof["sessions"] = 3
prof["owned"] = {"trails": {"tidal": True}}
prof["codes"] = {}
ob = prof.setdefault("onboarding", {})
ob["flew"] = True  # the first flight happened: the 'favorite' prompt will come after the nearest landing (step 8)
ob.pop("favAsked", None)
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world()
time.sleep(6)
cfg = json.loads(S("local C=require(game.ReplicatedStorage.Shared.Config) return game:GetService('HttpService'):JSONEncode({min=C.UI.passChips.minPx, goal=C.LiveOps.likeGoal, delay=C.FavPrompt.delay})"))
P("Config:", cfg)


def geo_checks(tag, g):
    pl = g.get("pill") or [0, 0, 0, 0]
    a, b = (g["chips"].get(X2) or {}).get("rect", [0] * 4), (g["chips"].get(AUTO) or {}).get("rect", [0] * 4)
    W, H = g["screen"]
    side_ok = a[0] >= pl[2] and b[0] >= a[2]
    size_ok = (a[3] - a[1]) >= cfg["min"] - 0.5 and (b[3] - b[1]) >= cfg["min"] - 0.5
    inside = all(0 <= v for v in a + b) and a[2] <= W and b[2] <= W and a[3] <= H and b[3] <= H
    hits = [o[0] for o in g["others"] for c in (a, b) if overlap(c, o[1])]
    if g.get("plist") and not g.get("touch"):
        hits += ["Roblox player list" for c in (a, b) if overlap(c, [W - 244, 0, W, 80])]
    return chip_vis(g, X2) and chip_vis(g, AUTO) and side_ok and size_ok and inside and not hits, f"{tag}: screen={W}x{H} plist={g.get('plist')} pill={[int(v) for v in pl]} x2={a} auto={b} hits={hits}"


g0 = geo(); P("geo PC:", json.dumps(g0)[:600])
ok("0. PC 812 with the player list: the buttons are not placed in its zone, nothing overlaps",
   g0.get("plist") and not g0.get("touch") and not chip_vis(g0, X2) and not chip_vis(g0, AUTO), json.dumps(g0["chips"]) + f" plist={g0.get('plist')} touch={g0.get('touch')}")
shot("A0_pc812_with_playerlist")
nolist()
g = geo(); P("geo:", json.dumps(g)[:900])
ok("1. both buttons visible", chip_vis(g, X2) and chip_vis(g, AUTO), json.dumps(g["chips"]))
good, det = geo_checks("phone", g)
ok("2-3. 812x375 without the player list (like a phone): to the right of the pill in a row, height >= minPx, inside the screen, no overlaps", good, det)
shot("A_phone_chips")


def card_texts():
    return C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('PassCard') if not g then return '' end local t={} for _,o in g:GetDescendants() do if (o:IsA('TextLabel') or o:IsA('TextButton')) and o.ContentText~='' then table.insert(t,o.Name..'='..o.ContentText) end end return table.concat(t,' | ')")


nolist(); press("HUD", X2, name="5. click on x2"); time.sleep(1.5)
card_on = gui_on("PassCard")
texts = card_texts(); P("card:", texts)
buy = re.search(r"Buy=([^|]+)", texts)
ok("5. a real click on x2 - the card with three lines and a price", card_on and "x2 Coins" in texts and "WHAT YOU GET" in texts and "Line3=" in texts and "Buy once - keep it forever" in texts
   and buy is not None and (re.match(r"R\$ \d", buy.group(1).strip()) or "See price" in buy.group(1)), texts[:400])
shot("C_phone_card_x2"); desk("C_phone_card_x2_desk")
press("PassCard", "Not now", name="6. Not now"); time.sleep(1.2)
nolist()  # HUD.setVisible(true) turned the player list on again - on 'PC' the buttons honestly leave its zone
ok("6. Not now closes, the HUD is back", card_on and not gui_on("PassCard") and gui_on("HUD") and chip_vis(geo(), X2), f"was={card_on} card={gui_on('PassCard')} hud={gui_on('HUD')}")

nolist(); press("HUD", AUTO, name="7. click on Auto"); time.sleep(1.5)
t7 = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('PassCard') return g and g:FindFirstChild('Title',true) and g:FindFirstChild('Title',true).ContentText or 'none'")
shot("D_phone_card_auto")
press("PassCard", "Close", name="7. cross"); time.sleep(1.2)
ok("7. the Auto Collect card and the cross closes it", t7 == "Auto Collect" and not gui_on("PassCard") and gui_on("HUD"), f"title={t7} card={gui_on('PassCard')}")


def fav(): return (dump().get("onboarding") or {}).get("favAsked")
def banner():
    return C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Banners') local l1=g and g:FindFirstChild('L1',true) local l2=g and g:FindFirstChild('L2',true) "
             "if l1 and l1.Parent.Visible then return l1.ContentText..' / '..(l2 and l2.ContentText or '') end return ''")


# the banner hangs for 5 s, MCP requests to P8 take one to three seconds - polling missed it.
# So the game itself records: when the card closed and which banner was shown and when (client clock os.clock)
WATCH = r"""
local pg=game.Players.LocalPlayer.PlayerGui
local f=pg:WaitForChild('Banners'):WaitForChild('Banner')
pg:SetAttribute('LastBanner', nil) pg:SetAttribute('CardClosedAt', nil)
f:GetPropertyChangedSignal('Visible'):Connect(function() if f.Visible then pg:SetAttribute('LastBanner', string.format('%.2f|%s / %s', os.clock(), f.L1.ContentText, f.L2.ContentText)) end end)
pg.ChildRemoved:Connect(function(c) if c.Name=='PassCard' then pg:SetAttribute('CardClosedAt', os.clock()) end end)
return 'ok'
"""
def attr(n): return C(f"return tostring(game.Players.LocalPlayer.PlayerGui:GetAttribute('{n}'))")
P("watch:", C(WATCH))
nolist(); press("HUD", X2, name="8. card before landing"); time.sleep(1.2)
open8 = gui_on("PassCard")
P("mount:", ld("mount")[:60]); time.sleep(2)
P("dismount:", ld("dismount")[:60])
time.sleep(cfg["delay"] + 4)
f_during, b_during, still = fav(), attr("LastBanner"), gui_on("PassCard")
shot("E_card_after_landing")
press("PassCard", "Not now", name="8. close the card")
time.sleep(8)
f_after, b_after, closed_at = fav(), attr("LastBanner"), attr("CardClosedAt")
try:
    b_t = float(b_after.split("|", 1)[0]); c_t = float(closed_at)
except ValueError:
    b_t, c_t = -1.0, 0.0
ok("8. the card is open, the player dismounted: the 'favorite' prompt and the banner wait for the card to close, then go",
   open8 and still and f_during is None and "likes" not in b_during and isinstance(f_after, (int, float))
   and "Give it a" in b_after and f"At {cfg['goal']} likes, every rider gets a new code" in b_after and b_t >= c_t > 0,
   f"card={open8}/{still} while open: fav={f_during} banner='{b_during}' | closed at {closed_at}; after: fav={f_after} banner='{b_after}'")

nolist()
P("mount:", ld("mount")[:60]); time.sleep(2.5)
gm = geo()
P("dismount:", ld("dismount")[:60]); time.sleep(2)
nolist(); gd = geo()
ok("9. riding - no buttons, dismounted - they are there", not chip_vis(gm, X2) and not chip_vis(gm, AUTO) and chip_vis(gd, X2) and chip_vis(gd, AUTO),
   f"riding {gm['chips']} | dismounted {gd['chips']}")

nolist()
P("pass x2:", ld("shop pass X2Coins_299")[:80]); time.sleep(1.5)
g10 = geo()
ok("10. x2 bought - its button is gone, Auto moved to the pill", not chip_vis(g10, X2) and chip_vis(g10, AUTO) and abs(g10["chips"][AUTO]["rect"][0] - g10["pill"][2] - 8) <= 1, json.dumps(g10["chips"]) + f" pill={g10['pill']}")
nolist(); press("HUD", AUTO, name="11. click on Auto"); time.sleep(1.2)
was = gui_on("PassCard")
P("pass auto:", ld("shop pass AutoCollect_149")[:80]); time.sleep(1.5)
g11 = geo()
ok("11. the Auto card is open, Auto bought - the card closed, no buttons", was and not gui_on("PassCard") and gui_on("HUD") and not chip_vis(g11, X2) and not chip_vis(g11, AUTO),
   f"was={was} card={gui_on('PassCard')} chips={g11['chips']}")


def code(c):
    time.sleep(1.3)
    return C(f"local r=game.ReplicatedStorage.Remotes.Code:InvokeServer('{c}') return tostring(r.ok)..'/'..tostring(r.reason)..'/'..tostring(r.coins)")


k0 = code("dragons")
off = 1792972800 + 3600 - int(time.time())
P("offset:", lo(f"offset {off}"))
k1 = code("dragons"); k2 = code(" Dragons "); k3 = code("50likes"); k4 = code("1000LIKES")
ok("12. codes: DRAGONS before 26.10 - bad_code; from 26.10 - ok + coins; the second time already; 50LIKES before the goal is reached - bad_code (25.10); a foreign one bad_code",
   k0.startswith("false/bad_code") and k1.startswith("true/nil/") and int(k1.rsplit("/", 1)[1]) >= 100 and k2.startswith("false/already")
   and k3.startswith("false/bad_code") and k4.startswith("false/bad_code"), f"{k0} | {k1} | {k2} | {k3} | {k4}")
lo("offset 0")

# 4) screen sizes - at the end: changing the Studio window takes it out of full screen, the clicks after it miss.
# The passes are already bought and cannot be removed by debug - restart with the same profile (seed: not bought)
stop(); start(); wait_world(); time.sleep(6)
res4 = []
for w, h, tag, pl_on in ((1222, 930, "PC 1200x675 with the player list", True), (689, 630, "narrow 667x375 without the list", False)):
    tool("winsize.sh", w, h); time.sleep(3)
    if not pl_on:
        nolist()
    gg = geo()
    res4.append(geo_checks(tag, gg))
    shot("B_" + ("1200" if pl_on else "667"))
ok("4. PC 1200x675 and narrow 667x375: visible on the right, inside the screen, no overlaps and outside the player list zone", all(r[0] for r in res4), " || ".join(r[1] for r in res4))
tool("winsize.sh", 834, 630); time.sleep(2)

errs = game_errors(console_lines())
ok("13. console without game errors", not errs, " | ".join(errs[:3]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("passchips_check: pass buttons next to the coins, the card, windows not at the same time, the likes goal, the page codes")
