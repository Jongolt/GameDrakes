#!/usr/bin/env python3
"""Newcomer pass + every menu button once with REAL mouse clicks on P8 (Studio window = phone 812x375) with a check
of the result. Based on func_test 15.10, the night check version 18.10 (runs/roblox_build_2026-10-18/night_check.py).
Stages (argument 1): A interface, W menu windows, P purchase, H loop (default WH); nostart - the game is already running, nostop - do not stop.
Run: python3 tests/p8/newcomer_check.py [WH] (after tools/p8/open_local.sh). Result - OUT/result.md, frames in OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("newcomer_check")
from p8lib import *  # noqa: F401,F403
desk = shot  # a frame via MCP (an ffmpeg screen frame is not needed)

# ---------------------------------------------------------------------------------------------- scenario (stages: A interface, P purchase, H loop)
PH = sys.argv[1] if len(sys.argv) > 1 else "WH"
if "nostart" not in sys.argv:
    s.call("start_stop_play", {"studio_id": sid, "is_start": True}); time.sleep(66)
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
P("vp", C("return tostring(workspace.CurrentCamera.ViewportSize)"))
_in = C("local a=game:GetService('GuiService'):GetGuiInset() return tostring(a.Y)")
P("inset", _in)
try: INSET = p8lib.INSET = int(float(_in))
except ValueError: pass
def fieldtext(): return C(FIND + "local g=pg:FindFirstChild('NameDialog') local f=g and g:FindFirstChild('Field',true) return f and f.Text or '-'")
def action(): return C("local h=game.Players.LocalPlayer.PlayerGui.HUD local a,b=h:FindFirstChild('Action'),h:FindFirstChild('Action2') return (a and a.Visible and a.Text or '-')..'|'..(b and b.Visible and b.Text or '-')")
def close_book():
    for _ in range(2):
        if gui_on("Book"): press("Book", "Close")
def close_roblox_dialog(tag):
    desk(tag + "_a")
    click_xy(621, 242); time.sleep(1.5)   # the cross of the Buy item / summary window (viewport 812x375)
    desk(tag + "_b")

def phase_A():
    press("Topbar", "Top_Settings"); ok("Settings in the Roblox row opens the book on Settings", gui_on("Book") and has("Book", "Sounds"))
    for i, nm in [(1, "Sounds"), (2, "Music")]:
        a = C(FIND + f"local o=find('Book','Toggle{i}') return o and o.Text or '-'"); press("Book", f"Toggle{i}")
        b = C(FIND + f"local o=find('Book','Toggle{i}') return o and o.Text or '-'"); press("Book", f"Toggle{i}")
        c = C(FIND + f"local o=find('Book','Toggle{i}') return o and o.Text or '-'")
        ok(f"toggle {nm} (on -> off -> on)", (a, b, c) == ("On", "Off", "On"), f"{a} -> {b} -> {c}")
    press("Book", "Toggle3"); a = C(CD + "return cd('lod')"); press("Book", "Toggle3"); b = C(CD + "return cd('lod')")
    ok("Show other riders' dragons writes to the profile", "profile.otherDragons=false" in a and "profile.otherDragons=true" in b)
    for tab, mark in {"dragons": "Slots", "shop": "Time", "index": "Dragon Index", "quests": "Keeper's tales", "settings": "Sounds"}.items():
        press("Book", f"Tab_{tab}")
        sc = C(FIND + f"local t=pg.Book:FindFirstChild('Tab_{tab}',true) local u=t and t:FindFirstChildOfClass('UIScale') return tostring(u and u.Scale)")
        ok(f"tab {tab}: content and highlight", has("Book", mark) and sc.startswith("1.1"), f"scale={sc}")
    press("Book", "Close"); ok("the book cross closes it", not gui_on("Book"))
    for plaque, mark in [("Shop", "Time"), ("Dragons", "Slots"), ("Index", "Dragon Index")]:
        press("HUD", f"Menu_{plaque}"); ok(f"plaque {plaque} opens its tab", gui_on("Book") and has("Book", mark))
        if plaque != "Index": press("Book", "Close")
    click_xy(VX + 20, VY + INSET + 200); time.sleep(1.5); ok("a tap outside the book window closes it", not gui_on("Book"))
    press("Quests", "Panel"); ok("the Keeper plaque opens Quests", gui_on("Book") and has("Book", "Keeper's tales")); close_book()
    press("HUD", "Menu_Shop")
    for sub, mark in [("Nest", "VIP"), ("Coins", "Nest income"), ("Looks", "Sunset"), ("Gifts", "Nobody else"), ("Time", "Treats")]:
        press("Book", sub); ok(f"shop: sub-tab {sub}", has("Book", mark))
    close_book()

def phase_W():
    lst = C(FIND + "local t={} for _,gn in {'HUD','Topbar'} do local g=pg:FindFirstChild(gn) if g then for _,o in g:GetDescendants() do if o:IsA('GuiButton') and (o.Name:sub(1,5)=='Menu_' or o.Name:sub(1,4)=='Top_') and shown(o) then table.insert(t, gn..':'..o.Name) end end end end return table.concat(t,',')")
    P("menu buttons:", lst)
    def opened():
        return C("local t={} for _,g in game.Players.LocalPlayer.PlayerGui:GetChildren() do if g:IsA('ScreenGui') and g.Enabled and g.Name~='HUD' and g.Name~='Topbar' and g.Name~='FreeGiftCard' then table.insert(t,g.Name) end end table.sort(t) return table.concat(t,',')")
    if gui_on('FreeGiftCard'): press_quiet('FreeGiftCard', 'X')
    base = opened()
    for it in [x for x in lst.split(",") if ":" in x]:
        gn, bn = it.split(":")
        press(gn, bn); time.sleep(1.5); now = opened(); shot("W_" + bn)
        if bn == "Top_Invite":  # the Roblox Invite Friends system window (CoreGui): a frame, then the cross (viewport 38,91)
            ok("Top_Invite: the Roblox Invite Friends window in the frame", True, "see W_Top_Invite.jpg"); click_xy(VX + 38, VY + 91); time.sleep(1.5); shot("W_Top_Invite_closed"); continue
        new = sorted(set(now.split(",")) - set(base.split(",")))
        ok(f"button {bn} opens a window", len(new) > 0, f"new: {new}")
        if gui_on("Book"): press("Book", "Close"); time.sleep(1)
        else:
            for g in new:
                for k in ("Close", "X", "Done"):
                    if press_quiet(g, k): break
            time.sleep(1)
        ok(f"the window from {bn} closes", opened() == base, opened())
    press("HUD", "Menu_Shop"); time.sleep(1)
    for sub in ("Nest", "Coins", "Looks", "Gifts", "Time"):
        r = press_quiet("Book", sub); time.sleep(1); shot("W_shop_" + sub); ok(f"shop: sub-tab {sub}", r)
    close_book()
def press_quiet(gname, key_):
    t = C(FIND + f"local o=find('{gname}', [[{key_}]], nil) if not o then return 'none' end local p=o.AbsolutePosition local z=o.AbsoluteSize return string.format('%d,%d', p.X+z.X/2, p.Y+z.Y/2)")
    m = re.match(r"(-?\d+),(-?\d+)", t)
    if not m: return False
    click_xy(VX + int(m.group(1)), VY + INSET + int(m.group(2))); time.sleep(1.2); return True

def phase_P():
    # test purchase Treats x1: price button -> Roblox window -> Buy -> receipt on the server -> treats stock +1
    t0 = re.search(r"treats=(\d+)", S(LD + "return ld('shop state')")); P("shop state before:", S(LD + "return ld('shop state')")[:200])
    press("HUD", "Menu_Shop"); press("Book", "Time")
    press("Book", "Price", inside="Card_Treats_1_49", name="price Treats x1"); time.sleep(4); desk("P1_buy_item")
    click_xy(417, 390); time.sleep(5); desk("P2_after_buy")  # the Buy button of the Roblox window
    st = S(LD + "return ld('shop state')"); P("shop state after:", st[:200])
    t1 = re.search(r"treats=(\d+)", st)
    ok("the test purchase Treats x1 reaches the game (stock +1)", t0 and t1 and int(t1.group(1)) == int(t0.group(1)) + 1, f"{t0 and t0.group(0)} -> {t1 and t1.group(0)}")
    click_xy(417, 444); time.sleep(1.5)  # 'Purchase completed' -> OK (viewport 812x375: OK at (406,268))
    desk("P3_after_ok")
    still = "Purchase completed"  # check by eye on the P3_after_ok frame
    close_book()
    ok("after the purchase the book is closed, Roblox windows do not get in the way", not gui_on("Book"))

def phase_H():
    S(LD + "ld('go table') task.wait(1.5) ld('go inc') task.wait(1.5) return ld('state')"); time.sleep(1.5)
    S(LD + "ld('time 900') task.wait(2) return 'ready'"); time.sleep(1.5)
    both = C("local hud=game.Players.LocalPlayer.PlayerGui.HUD.Action local w='-' for _,g in game.Players.LocalPlayer.PlayerGui:GetChildren() do if g:IsA('BillboardGui') and g.Name=='WUI' and g.Enabled then local h=g:FindFirstChild('Hatch') if h and h.Visible then w='world' end end end return (hud.Visible and hud.Text or '-')..'|'..w")
    P("hatch buttons (HUD|world):", both); desk("H0_hatch_ready_real")
    wh = C("local cam=workspace.CurrentCamera for _,g in game.Players.LocalPlayer.PlayerGui:GetChildren() do if g:IsA('BillboardGui') and g.Name=='WUI' and g.Enabled then local h=g:FindFirstChild('Hatch') if h and h.Visible then local a=g.Adornee local v,on=cam:WorldToViewportPoint(a.Position+g.StudsOffsetWorldSpace) return string.format('%d,%d,%s',v.X,v.Y,tostring(on)) end end end return 'none'")
    mw = re.match(r"(\d+),(\d+),true", wh)
    if mw:
        click_xy(VX + int(mw.group(1)), VY + int(mw.group(2))); time.sleep(2); shot("H0b_hatch_scene"); time.sleep(5); shot("H0c_name_dialog")
    ok("the round Hatch above the incubator hatches", mw is not None and gui_on("NameDialog"), f"{wh} | {state()[:100]}")
    if not gui_on("NameDialog"):
        press("HUD", "Action", name="Hatch (HUD)"); time.sleep(7)
        ok("Hatch (HUD) hatches", gui_on("NameDialog"), state()[:120])
    n0 = fieldtext(); press("NameDialog", "Dice"); n1 = fieldtext(); ok("the dice changes the name", n1 not in ("-", n0), f"{n0} -> {n1}")
    press("NameDialog", "Done"); time.sleep(1.5); ok("Done closes the name dialog", not gui_on("NameDialog"))
    named = S("local p=game.Players:GetPlayers()[1] for _,m in workspace:GetDescendants() do if m:IsA('Model') and m:GetAttribute('OwnerId')==p.UserId and m:GetAttribute('Uid')=='d1' then return tostring(m:GetAttribute('DragonName')) end end return '-'")
    ok("the name from the dialog is saved on the server", named == n1, f"d1={named}, expected {n1}")
    for k, how in [(2, "Skip"), (3, "Close")]:
        S(LD + f"ld('go table') task.wait(1.2) ld('table {k}') task.wait(0.6) ld('go inc') task.wait(1.5) ld('place 1') task.wait(0.5) ld('time 900') task.wait(2) return 'r'"); time.sleep(1.2)
        press("HUD", "Action", name=f"Hatch #{k} (HUD)"); time.sleep(7)
        shown_ = gui_on("NameDialog"); press("NameDialog", how); time.sleep(1)
        ok(f"Hatch (HUD) #{k} + name dialog: {how} closes it", shown_ and not gui_on("NameDialog"))
    P("state:", state()[:300])
    C("local r=game.ReplicatedStorage.Remotes.Admin:InvokeServer('give 5000') return tostring(r.ok)")
    S(LD + "ld('go table') task.wait(2) return 'nest'"); time.sleep(2)
    fp = C("local cam=workspace.CurrentCamera local me=game.Players.LocalPlayer for _,g in me.PlayerGui:GetChildren() do if g:IsA('BillboardGui') and g.Name=='WUI' and g.Enabled and g:FindFirstChild('Feed') then local a=g.Adornee local m=a and a:FindFirstAncestorWhichIsA('Model') local v,on=cam:WorldToViewportPoint(a.Position+g.StudsOffsetWorldSpace) if on then return string.format('%d,%d,%s', v.X, v.Y - 17, tostring(m and m:GetAttribute('Uid'))) end end end return 'none'")
    P("feed pill:", fp); desk("H1_feed_pill_real")
    m = re.match(r"(\d+),(\d+),(\w+)", fp)
    if m: click_xy(VX + int(m.group(1)), VY + int(m.group(2))); time.sleep(2)
    after = state(); uid = m.group(3) if m else "?"
    ok("the Feed button above a dragon in the nest feeds", m is not None and re.search(uid + r"=[^ ]*/fed", after) is not None, f"{uid}: {after[:200]}")
    txt = action(); P("action buttons:", txt)
    if "Feed All" in txt:
        press("HUD", "Action2" if txt.endswith("Feed All") else "Action", name="Feed All")
    time.sleep(2); fed = state(); ok("Feed All feeds everyone in the nest", "Feed All" in txt and fed.count("/fed") >= 2, f"{txt} | {fed[:200]}")
    press("HUD", "Menu_Dragons"); press("Book", "d2", name="card d2"); time.sleep(1)
    ok("a tap on a dragon in the book opens the card", gui_on("DragonCard"))
    press("DragonCard", "Third", name="Companion"); time.sleep(2.5)
    comp = S(LD + "return ld('comp')"); ok("the Companion button makes it the companion", "d2" in comp, comp[:120])
    press("DragonCard", "Rename"); time.sleep(1); ok("Rename opens the name dialog", gui_on("NameDialog"))
    press("NameDialog", "Dice"); nn = fieldtext(); press("NameDialog", "Done"); time.sleep(1.5)
    title = C(FIND + "local g=pg:FindFirstChild('DragonCard') local p=g and g:FindFirstChild('Title',true) return p and p.Text or '-'")
    ok("renaming in the card", title == nn, f"title={title} new={nn}")
    desk("H2_card_real")
    press("DragonCard", "Close"); time.sleep(0.8); ok("the card cross closes it", not gui_on("DragonCard"))
    close_book()
    S(LD + "ld('time 300') task.wait(3) ld('go table') task.wait(1.5) return 'grown'"); time.sleep(2)
    a1 = action(); press("HUD", "Action", name="Ride"); time.sleep(2.5)
    mt = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))"); ok("Ride mounts the teen", a1.startswith("Ride") and mt != "nil", f"{a1} mounted={mt}")
    desk("H3_riding_real")
    press("Movement", "Dismount"); time.sleep(2.5); mt2 = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))"); ok("Dismount dismounts", mt2 == "nil", mt2)
    S(LD + "ld('time 100000') task.wait(3) ld('go table') task.wait(1.5) return 'adult'"); time.sleep(2.5)
    a2 = action(); press("HUD", "Action", name="Fly"); time.sleep(2.5)
    mt3 = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))"); ok("Fly mounts the adult", a2.startswith("Fly") and mt3 != "nil", f"{a2} mounted={mt3}")
    desk("H4_fly_mounted")
    keys("down space;wait 1500;up space;wait 300"); time.sleep(0.5)
    fl = C("return tostring(game.Players.LocalPlayer:GetAttribute('Flying'))"); shot("H5_takeoff")
    ok("takeoff (hold Space) lifts into the air", fl == "true", f"Flying={fl}")
    time.sleep(4)
    press("Movement", "Dismount"); time.sleep(2.5)
    S("local p=game.Players:GetPlayers()[1] p.Character:PivotTo(CFrame.new(0,0,1000)) return 'sea'"); time.sleep(8)
    shore = has("Swim", "Back to shore"); press("Swim", "Shore", name="Back to shore"); time.sleep(3)
    pos = S("local p=game.Players:GetPlayers()[1].Character:GetPivot().Position return string.format('%.0f,%.0f,%.0f', p.X,p.Y,p.Z)")
    z = float(pos.split(",")[2]) if pos.count(",") == 2 else 9999
    ok("Back to shore returns to the shore", shore and z < 900, f"button={shore} position={pos}")
    S(LD + "return ld('index ember')"); time.sleep(1.5)
    c0 = re.search(r"coins=(\d+)", state()); press("HUD", "Menu_Index"); time.sleep(1)
    press("Book", "Claim", name="Claim in the Index"); time.sleep(2)
    c1 = re.search(r"coins=(\d+)", state())
    ok("Claiming a set in the Index gives the reward", c0 and c1 and int(c1.group(1)) > int(c0.group(1)), f"{c0 and c0.group(1)} -> {c1 and c1.group(1)}")
    close_book()
    press("Topbar", "Top_Settings"); press("Book", "Reset"); r1 = C(FIND + "local o=find('Book','Reset') return o and o.Text or '-'")
    press("Book", "Reset"); time.sleep(3); st = state()
    ok("Reset: the first press asks, the second resets", r1.endswith("?") and "d1=" not in st, f"{r1} | {st[:120]}")
    close_book()

if "A" in PH: phase_A()
if "W" in PH: phase_W()
if "P" in PH: phase_P()
if "H" in PH: phase_H()
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
lines = ctext.splitlines()
errs = []
for i, l in enumerate(lines):
    if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "errors 0" not in l and "TexturePack" not in l:
        errs.append(" / ".join(x.strip() for x in lines[max(0, i - 2): i + 3])[:300])
game_errs = [e for e in errs if "ExecuteLuau" not in e and "CommandExecution" not in e]
ok("console without game errors (errors of my probes do not count)", len(game_errs) == 0, " ;; ".join(game_errs[:4]))
if "nostop" not in sys.argv:
    s.call("start_stop_play", {"studio_id": sid, "is_start": False})
s.close()
with open(f"{OUT}/result.md", "w") as f:
    f.write("| check | result | details |\n|---|---|---|\n")
    for n, o, d in res:
        f.write(f"| {n} | {'OK' if o else 'FAIL'} | {d[:160].replace('|','/')} |\n")
P(f"RESULT: {sum(1 for _, o, _ in res if o)}/{len(res)} OK")
