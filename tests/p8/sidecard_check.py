#!/usr/bin/env python3
"""The side cards Free Gift (02 §2 2:45) and Hatch Party / Invite (7:30) on P8, phone window 812x375.
Before: both in the top right corner (350x80) lay over the step banner (frames newcomer20 M03, 18.10 H3). Now: UIKit.sideCard - under
the Keeper plaque, hidden while riding/in flight and with the menu open, one at a time.
Checks: the card appears by GiftSec (reward time), stands under the Keeper plaque (gap 8), does not cross the step banner, the Keeper plaque,
the HUD/Movement buttons, does not leave the screen; hidden while riding and comes back after dismounting; hidden with the book open; the Invite card
closes Free Gift; a full UI probe (sweep) with the card - 0 overlaps; a clean console.
Run: python3 tests/p8/sidecard_check.py (after tools/p8/open_local.sh)."""
import os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("sidecard_check")
from p8lib import *  # noqa: F401,F403

RECT = r"""
local pg=game.Players.LocalPlayer.PlayerGui
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local function rect(o) if not o or not o:IsA('GuiObject') or not shown(o) then return nil end local p,z=o.AbsolutePosition,o.AbsoluteSize if z.X<=1 or z.Y<=1 then return nil end return {p.X,p.Y,p.X+z.X,p.Y+z.Y} end
local function fmt(r) return r and string.format('%d,%d,%d,%d', r[1],r[2],r[3],r[4]) or '-' end
local out={}
local function card(name) local g=pg:FindFirstChild(name) local f=g and g:FindFirstChildWhichIsA('Frame') out[name]=fmt(rect(f)) out[name..'_enabled']=tostring(g~=nil and g.Enabled) end
card('FreeGiftCard') card('InviteCard')
local sb=pg:FindFirstChild('StepBanner') out.step=fmt(rect(sb and sb:FindFirstChild('Step')))
local q=pg:FindFirstChild('Quests') out.panel=fmt(rect(q and q:FindFirstChild('Panel')))
local hud=pg:FindFirstChild('HUD') local acts={} if hud then for _,n in {'Action','Action2'} do local a=hud:FindFirstChild(n) if a then acts[#acts+1]=fmt(rect(a)) end end end out.actions=table.concat(acts,';')
local mv=pg:FindFirstChild('Movement') local b={} if mv then for _,d in mv:GetDescendants() do if d:IsA('GuiButton') and shown(d) then b[#b+1]=d.Name..'='..fmt(rect(d)) end end end out.movement=table.concat(b,';')
out.vp=tostring(workspace.CurrentCamera.ViewportSize)
local t={} for k,v in out do t[#t+1]=k..'|'..v end table.sort(t) return table.concat(t,'\n')
"""
def rects():
    d = {}
    for line in C(RECT).splitlines():
        k, _, v = line.partition("|"); d[k] = v
    return d
def r4(s):
    m = re.match(r"(-?\d+),(-?\d+),(-?\d+),(-?\d+)", s or ""); return [int(x) for x in m.groups()] if m else None
def overlap(a, b, m=0):
    return a and b and a[0] - m < b[2] and b[0] < a[2] + m and a[1] - m < b[3] and b[1] < a[3] + m

start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
time.sleep(2)
vp = C("return tostring(workspace.CurrentCamera.ViewportSize)"); P("viewport", vp)
W, H = [int(float(x)) for x in vp.split(",")]

# 1) the Free Gift card by GiftSec >= showAt (165); it arrives with the book OPEN - not shown on top, comes out after closing
press("HUD", "Menu_Shop", name="open the book before the card"); time.sleep(1.2)
S(LD + "return ld('reward time 170')"); time.sleep(3)
got = False
for _ in range(10):
    if C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('FreeGiftCard') return tostring(g~=nil)") == "true": got = True; break
    time.sleep(1)
ok("the Free Gift card is created at second 165 (reward time 170)", got)
ok("the card arrived with the book open - not shown on top of it", gui_on("Book") and not gui_on("FreeGiftCard"), f"book={gui_on('Book')} card={gui_on('FreeGiftCard')}")
shot("S0_book_card_hidden")
press("Book", "Close"); time.sleep(1.5)
ok("after closing the book the card came out", not gui_on("Book") and gui_on("FreeGiftCard"), f"book={gui_on('Book')} card={gui_on('FreeGiftCard')}")
time.sleep(1.5); shot("S1_freegift"); d = rects(); P("rects:", d)
card, step, panel = r4(d.get("FreeGiftCard")), r4(d.get("step")), r4(d.get("panel"))
ok("the card is visible and within the screen", card is not None and card[0] >= 0 and card[1] >= 0 and card[2] <= W and card[3] <= H, f"card={card} vp={W}x{H}")
ok("the card under the Keeper plaque (gap 8 px, the right edge as the plaque's)", card and panel and card[1] == panel[3] + 8 and card[2] <= W, f"card={card} panel={panel}")
ok("the card does not cross the step banner", step is None or not overlap(card, step), f"card={card} step={step}")
ok("the card does not cross the Keeper plaque", not overlap(card, panel), f"card={card} panel={panel}")
acts = [r4(x) for x in d.get("actions", "").split(";") if x and x != "-"]
ok("the card does not cross the bottom HUD buttons", not any(overlap(card, a) for a in acts), f"actions={acts}")
sw = sweep("S1_sweep"); mi = re.search(r"ISSUES\[(\d+)\]", sw)
ok("a full UI probe with the card: 0 overlaps (ISSUES[0])", mi is not None and mi.group(1) == "0", sw[:300])

# 2) riding the card is hidden, after dismounting visible (egg -> baby -> teen -> Ride)
S(LD + "ld('table 1') task.wait(1) ld('place 1') task.wait(0.5) ld('time 900') task.wait(2) ld('hatch 1') return 'h'"); time.sleep(10)
if gui_on("NameDialog"):
    time.sleep(6)
S(LD + "ld('time 300') task.wait(2) return 'teen'"); time.sleep(2)
m = S(LD + "return ld('mount d1')"); P("mount:", m[:120]); time.sleep(2.5)
mt = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))")
d = rects(); shot("S2_mounted")
ok("riding: the card is hidden", mt != "nil" and d.get("FreeGiftCard_enabled") == "false", f"Mounted={mt} enabled={d.get('FreeGiftCard_enabled')} movement={d.get('movement')}")
S(LD + "return ld('dismount')"); time.sleep(2.5)
d = rects(); shot("S3_dismounted")
ok("after dismounting the card is visible again", d.get("FreeGiftCard_enabled") == "true" and d.get("FreeGiftCard") != "-", f"enabled={d.get('FreeGiftCard_enabled')} card={d.get('FreeGiftCard')}")

# 3) an open menu hides the card, closing brings it back
press("HUD", "Menu_Shop", name="open the book"); time.sleep(1.5)
d = rects(); shot("S4_book")
ok("with the book open the card is hidden", gui_on("Book") and d.get("FreeGiftCard_enabled") == "false", f"book={gui_on('Book')} enabled={d.get('FreeGiftCard_enabled')}")
press("Book", "Close"); time.sleep(1.5)
d = rects()
ok("after closing the book the card is visible again", not gui_on("Book") and d.get("FreeGiftCard_enabled") == "true", f"enabled={d.get('FreeGiftCard_enabled')}")

# 4) the Invite card (GiftSec >= inviteAt 450) closes Free Gift and stands at the same place
S(LD + "return ld('reward time 455')"); got = False
for _ in range(12):
    if gui_on("InviteCard"): got = True; break
    time.sleep(1)
time.sleep(1.5); d = rects(); shot("S5_invite")
inv = r4(d.get("InviteCard"))
ok("the Invite card appears at second 450", got and inv is not None, f"invite={inv}")
ok("the Invite card closed Free Gift (one at a time)", d.get("FreeGiftCard_enabled") in ("false", "nil") or d.get("FreeGiftCard") == "-", f"freegift={d.get('FreeGiftCard')} enabled={d.get('FreeGiftCard_enabled')}")
ok("the Invite card under the Keeper plaque, not on the step banner", inv and panel and inv[1] == r4(d.get("panel"))[3] + 8 and (r4(d.get("step")) is None or not overlap(inv, r4(d.get("step")))), f"invite={inv} panel={d.get('panel')} step={d.get('step')}")
ok("the Invite card within the screen", inv is not None and inv[2] <= W and inv[3] <= H and inv[0] >= 0, f"invite={inv}")
press("InviteCard", "X", name="Invite cross"); time.sleep(1.2)
ok("the cross closes the Invite card", not gui_on("InviteCard"))

cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result("Side cards Free Gift / Invite under the Keeper plaque (20.10)")
s.close()
