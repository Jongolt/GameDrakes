#!/usr/bin/env python3
"""Localization on P8 in a LOCAL file - es, de, fr, pt. Before starting the game: the ReplicatedStorage.LocTest attribute
(the Loc module language in Studio) and an attempt to emulate the Studio language for AutoLocalize (LocalizationService.*ForcePlayMode*). In the game:
HUD, shop (5 sub-tabs), book (dragons, quests, index, settings), gifts - on every screen a full check
of all visible labels (2D and world labels nearby): translated (our translation), an English string from the table that was not
translated (MISS), text outside the table (UNK - names, numbers or a gap), does not fit (TextFits = false on a label without
TextScaled) and too small (TextScaled, text height < 11 px). Dragon names with AutoLocalize off (Loc.raw) are not
a gap (dragon names are not translated). Into labels with AutoLocalize the probe substitutes the translation from the table (as Roblox will show them
to the player) and measures the already translated look.
Run: python3 tests/p8/loc_check.py [es de fr pt] (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("loc_check")
from p8lib import *  # noqa: F401,F403

LANGS = sys.argv[1:] or ["es", "de", "fr", "pt"]
SCREENS = (os.environ.get("LOC_SCREENS") or "hud,shop,book,gifts").split(",")  # a subset of screens: LOC_SCREENS=gifts

SWEEP = r"""
local lang = '%LANG%'
local D = require(game.ReplicatedStorage.Shared.LocaleData)[lang] or {}
local rev = {} for en, t in D do rev[t] = en end
-- dragon names are not translated: elements, variants, dragons of the week - not a gap, but a name
local C = require(game.ReplicatedStorage.Shared.Content)
local names = { Cinder = true, Nightfall = true, Solstice = true, ['Pearl Tide'] = true }
for _, e in C.Elements do names[e.name] = true end
for _, v in C.Variants do names[v.label] = true end
local pg = game.Players.LocalPlayer.PlayerGui
local cam = workspace.CurrentCamera
local skip = { LoadingScreen = true, TouchGui = true, Freecam = true, BubbleChat = true, ProximityPrompts = true, Chat = true } -- Chat: the Roblox system chat (not ours)
local function shown(o)
  local p = o
  while p and p ~= game do
    if p:IsA('GuiObject') and not p.Visible then return false end
    if p:IsA('LayerCollector') and not p.Enabled then return false end
    if p:IsA('BillboardGui') then
      local a = p.Adornee or p.Parent
      local pos = a and (a:IsA('BasePart') and a.Position or (a:IsA('Model') and a:GetPivot().Position) or (a:IsA('Attachment') and a.WorldPosition))
      if not pos or (pos - cam.CFrame.Position).Magnitude > math.min(p.MaxDistance, 120) then return false end
      local _, on = cam:WorldToViewportPoint(pos)
      if not on then return false end
    end
    p = p.Parent
  end
  return true
end
local function auto(o)
  local p = o
  while p and p:IsA('GuiBase2d') do
    if not p.AutoLocalize then return false end
    p = p.Parent
  end
  return true
end
local function word(s) return string.find(s, '%a%a%a') ~= nil end
local labels = {}
for _, g in pg:GetChildren() do
  if g:IsA('LayerCollector') and not skip[g.Name] then
    for _, o in g:GetDescendants() do
      if (o:IsA('TextLabel') or o:IsA('TextButton')) and shown(o) and o.AbsoluteSize.X > 1 then table.insert(labels, o) end
    end
  end
end
for _, o in workspace:GetDescendants() do
  if (o:IsA('TextLabel') or o:IsA('TextButton')) and o:FindFirstAncestorWhichIsA('BillboardGui') and shown(o) then table.insert(labels, o) end
end
local ok, miss, unk, sim = 0, {}, {}, 0
for _, o in labels do
  local t = o.Text
  if t ~= '' and word(t) then
    local a = auto(o)
    if rev[t] or (names[t] and not a) then ok += 1
    elseif D[t] and a then
      if %SIM% then o.Text = D[t] o.AutoLocalize = false sim += 1 end -- this is how Roblox will show it (AutoLocalize by the table)
      ok += 1
    elseif D[t] then table.insert(miss, o:GetFullName():sub(-40) .. '=' .. t)
    else table.insert(unk, t:sub(1, 40)) end
  end
end
task.wait(0.3)
local over, tiny = {}, {}
for _, o in labels do
  if o.Parent and o.Text ~= '' then
    if not o.TextScaled and not o.TextFits then table.insert(over, o:GetFullName():sub(-34) .. '=' .. o.Text:sub(1, 50)) end
    if o.TextScaled and o.TextBounds.Y > 0 and o.TextBounds.Y < 11 and not o:FindFirstAncestorWhichIsA('BillboardGui') then
      table.insert(tiny, o.Name .. '(' .. math.floor(o.TextBounds.Y) .. ')=' .. o.Text:sub(1, 30))
    end
  end
end
return string.format('labels=%d ok=%d sim=%d MISS[%d] %s || UNK[%d] %s || OVER[%d] %s || TINY[%d] %s', #labels, ok, sim,
  # miss, table.concat(miss, '; '), #unk, table.concat(unk, '; '), #over, table.concat(over, '; '), #tiny, table.concat(tiny, '; '))
"""

SUBTAB = ("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local bar=b and b:FindFirstChild('Subs',true) if not bar then return 'none' end "
          "local t={} for _,c in bar:GetChildren() do if c:IsA('GuiButton') then t[#t+1]=c end end table.sort(t,function(x,y) return x.LayoutOrder<y.LayoutOrder end) "
          "local o=t[%d] if not o then return 'none' end local p=o.AbsolutePosition local z=o.AbsoluteSize return string.format('%%d,%%d', p.X+z.X/2, p.Y+z.Y/2)")

summary = {}


def edit(code):
    r = s.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}, 60)
    return ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")


def screen(lang, name, sim):
    r = run(SWEEP.replace("%LANG%", lang).replace("%SIM%", "true" if sim else "false"), "Client", 300)
    P(f"[{lang}] {name}: {r[:1500]}")
    shot(f"{lang}_{name}")
    summary.setdefault(lang, []).append((name, r))
    return r


def click_sub(i):
    t = C(SUBTAB % i)
    if "," not in t:
        P("sub-tab", i, "not found:", t); return False
    x, y = (int(v) for v in t.split(","))
    click_xy(VX + x, VY + INSET + y); time.sleep(1.3)
    return True


for lang in LANGS:
    stop()
    emu = edit("local LS=game:GetService('LocalizationService') game.ReplicatedStorage:SetAttribute('LocTest','%s') local r={} "
               "for _,p in {'RobloxForcePlayModeGameLocaleId','RobloxForcePlayModeRobloxLocaleId','ForcePlayModeGameLocaleId','ForcePlayModeRobloxLocaleId'} do "
               "local ok,e=pcall(function() LS[p]='%s' end) r[#r+1]=p..'='..(ok and 'set' or tostring(e):sub(1,40)) end return table.concat(r,' | ')" % (lang, lang))
    P(f"[{lang}] Studio language emulation: {emu}")
    start()
    eng = C("local LS=game:GetService('LocalizationService') local ok,t=pcall(function() return LS:GetTranslatorForPlayerAsync(game.Players.LocalPlayer).LocaleId end) "
            "return 'Robloxlocale='..LS.RobloxLocaleId..' player='..game.Players.LocalPlayer.LocaleId..' translator='..(ok and t or 'none (place not published)')..' Loc='..require(game.ReplicatedStorage.Shared.Loc).lang()")
    P(f"[{lang}] languages in the game: {eng}")
    # the table translation is always substituted into labels with AutoLocalize: this is how Roblox will show them to the player, and TextFits is measured on
    # the translation regardless of whether Studio can emulate the language (the emulation above is for information only)
    sim = True
    ok(f"{lang}: the Loc module is in the language", f"Loc={lang}" in eng, eng)
    if "hud" in SCREENS:
        screen(lang, "hud", sim)
    if "shop" in SCREENS or "book" in SCREENS:
        press("HUD", "Menu_Shop"); time.sleep(1)
    if "shop" in SCREENS:
        for i in range(1, 6):
            if click_sub(i):
                screen(lang, f"shop{i}", sim)
    if "book" in SCREENS:
        for tab in ("dragons", "quests", "index", "settings"):
            press("Book", f"Tab_{tab}"); time.sleep(1)
            screen(lang, tab, sim)
    if gui_on("Book"):
        press("Book", "Close"); time.sleep(1)
    if "gifts" in SCREENS:
        press("Topbar", "Top_Gifts"); time.sleep(1.5)
        screen(lang, "gifts", sim)
    if gui_on("Book"):
        press("Book", "Close")
    tot = {"MISS": 0, "OVER": 0}
    for name, r in summary.get(lang, []):
        for k in tot:
            i = r.find(k + "[")
            if i >= 0:
                tot[k] += int(r[i + len(k) + 1:r.index("]", i)])
    ok(f"{lang}: no untranslated strings from the table (MISS)", tot["MISS"] == 0, str(tot["MISS"]))
    ok(f"{lang}: everything fits (OVER)", tot["OVER"] == 0, str(tot["OVER"]))

stop()
edit("game.ReplicatedStorage:SetAttribute('LocTest', nil) local LS=game:GetService('LocalizationService') "
     "for _,p in {'RobloxForcePlayModeGameLocaleId','RobloxForcePlayModeRobloxLocaleId','ForcePlayModeGameLocaleId','ForcePlayModeRobloxLocaleId'} do pcall(function() LS[p]='' end) end return 'reset'")
sys.exit(1 if write_result("Localization on P8 (loc_check)") else 0)
