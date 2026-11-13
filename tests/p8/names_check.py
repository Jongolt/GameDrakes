#!/usr/bin/env python3
"""A name inside a phrase is a placeholder {Ember}, {Cinder},
{StormDragon}... (Loc.NAMES), Loc.t inserts the name after the translation. In a LOCAL file on P8 per language (en, es): on the client
ALL texts that appeared in the UI and on the world signs (including fleeting banners) are recorded; the pass: the Index book (sets),
gifts (the community card), the shop in the Cinder week (the name and the line of the item of the week), the Keeper on quests 21 and 28,
notes 6, 11, 14 (update scrolls 2 and 4), Aurora, the Storm dragon, the Frost Isle sign. Check: not a single
unsubstituted {Name}; the expected phrases (English / our translation from locales/<lang>.csv with the names substituted) are visible.
Run: python3 tests/p8/names_check.py [en es] (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import csv, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("names_check")
from p8lib import *  # noqa: F401,F403

LANGS = sys.argv[1:] or ["en", "es"]
GAME = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
NAMES = {"Ember": "Ember", "Frost": "Frost", "Moss": "Moss", "Tide": "Tide", "Storm": "Storm", "Dusk": "Dusk", "Glacier": "Glacier",
         "Pearl": "Pearl", "Cinder": "Cinder", "Nightfall": "Nightfall", "Solstice": "Solstice", "StormDragon": "Storm Dragon"}
# what the probe must see (localization key) - reachable in this pass
EXPECT = ["Strings.Index.sets.ember", "Strings.Index.sets.dusk", "Strings.Rewards.joinGroup", "Strings.Shop.names.DragonWeek_1_199",
          "Strings.Shop.lines.DragonWeek_1_199", "Strings.Weather.aurora", "Content.Notes.6",
          "Content.Notes.11", "Content.Notes.14", "Quests.21.text", "Quests.28.text"]


def fill(s):
    return re.sub(r"\{(\w+)\}", lambda m: NAMES.get(m.group(1), m.group(0)), s)


def expected(lang):
    rows = {r["key"]: r for r in csv.DictReader(open(os.path.join(GAME, "src", "shared", "locales", "es.csv" if lang == "en" else f"{lang}.csv"), encoding="utf-8"))}
    return {k: fill(rows[k]["source"] if lang == "en" else rows[k]["text"]) for k in EXPECT}


def lo(cmd): return S(f"return game.ServerStorage.LiveOpsDebug:Invoke('{cmd}')")
def wd(cmd): return S(f"return game.ServerStorage.WeatherDebug:Invoke('{cmd}')")
def edit(code):
    r = s.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}, 60)
    return ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")


REC = ("local lp=game.Players.LocalPlayer local f=lp:FindFirstChild('P8Rec') if f then f:Destroy() end f=Instance.new('Folder') f.Name='P8Rec' f.Parent=lp "
       "local seen={} local function put(o) local t=o.Text if t~='' and not seen[t] then seen[t]=true local v=Instance.new('StringValue') v.Value=t v.Parent=f end end "
       "local function rec(o) if o:IsA('TextLabel') or o:IsA('TextButton') then put(o) o:GetPropertyChangedSignal('Text'):Connect(function() put(o) end) end end "
       "for _,o in lp.PlayerGui:GetDescendants() do rec(o) end lp.PlayerGui.DescendantAdded:Connect(rec) "
       "for _,o in workspace:GetDescendants() do if o:IsA('BillboardGui') or o:IsA('SurfaceGui') then for _,x in o:GetDescendants() do rec(x) end end end "
       "workspace.DescendantAdded:Connect(function(o) if o:FindFirstAncestorWhichIsA('BillboardGui') or o:FindFirstAncestorWhichIsA('SurfaceGui') then rec(o) end end) return 'rec'")
DUMP = "local f=game.Players.LocalPlayer:FindFirstChild('P8Rec') if not f then return '' end local t={} for _,v in f:GetChildren() do t[#t+1]=v.Value end return table.concat(t,'\\n<<>>\\n')"
COMP = "local p=game.Players:GetPlayers()[1] p:SetAttribute('CompanionStage', 2) return 'ok'"


def scroll(update, step, n):
    lo(f"update {update}"); time.sleep(1.5)
    lo(f"step {step}"); time.sleep(1.5)
    S(COMP); lo(f"go {n}"); time.sleep(2.5)
    S(COMP); lo(f"go {n}"); time.sleep(0.5)
    P(f"scroll {n}:", lo(f"read {n}"))
    time.sleep(5)  # the note after the Done! banner (chainDelay + noteDelay)
    shot(f"{lang}_note{n}")


for lang in LANGS:
    stop()
    edit("game.ReplicatedStorage:SetAttribute('LocTest', %s) return 'ok'" % ("nil" if lang == "en" else f"'{lang}'"))
    start()
    P(f"[{lang}] Loc:", C("return require(game.ReplicatedStorage.Shared.Loc).lang()"), C(REC))
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') return 'day'")
    # book: Index
    press("HUD", "Menu_Shop"); time.sleep(1.2)
    press("Book", "Tab_index"); time.sleep(1.5); shot(f"{lang}_index")
    if gui_on("Book"):
        press("Book", "Close"); time.sleep(1)
    # gifts
    press("Topbar", "Top_Gifts"); time.sleep(1.5); shot(f"{lang}_gifts")
    if gui_on("Book"):
        press("Book", "Close"); time.sleep(1)
    # Cinder week (update 2): the item of the week in the shop, Keeper 21, note 6
    scroll(2, 21, 6)
    shot(f"{lang}_keeper21")
    press("HUD", "Menu_Shop"); time.sleep(1.2)
    for i in range(1, 6):
        t = C("local b=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Book') local bar=b and b:FindFirstChild('Subs',true) if not bar then return 'none' end "
              "local t={} for _,c in bar:GetChildren() do if c:IsA('GuiButton') then t[#t+1]=c end end table.sort(t,function(x,y) return x.LayoutOrder<y.LayoutOrder end) "
              f"local o=t[{i}] if not o then return 'none' end local p=o.AbsolutePosition local z=o.AbsoluteSize return string.format('%d,%d', p.X+z.X/2, p.Y+z.Y/2)")
        if "," in t:
            x, y = (int(v) for v in t.split(","))
            click_xy(VX + x, VY + INSET + y); time.sleep(1.3)
            shot(f"{lang}_shop{i}")
    if gui_on("Book"):
        press("Book", "Close"); time.sleep(1)
    # Pearl Tide (update 3): Keeper 28
    lo("update 3"); time.sleep(1.5); lo("step 28"); time.sleep(2.5); shot(f"{lang}_keeper28")
    # Nightfall (update 4): notes 11 and 14
    scroll(4, 31, 11)
    scroll(4, 34, 14)
    lo("offset 0")
    # weather: Aurora, the Storm dragon
    P("aurora:", wd("aurora")[:120]); time.sleep(3); shot(f"{lang}_aurora")
    P("dragon:", wd("dragon")[:120]); time.sleep(4); shot(f"{lang}_dragon")
    # the Frost Isle sign (far away, Streaming): the character to it, then back
    C("local c=game.Players.LocalPlayer.Character if c then c:PivotTo(CFrame.new(1080, 40, 0)) end return 'ok'"); time.sleep(6)
    srv = S("local s for _,o in workspace:GetDescendants() do if o.Name=='FrostSign' then s=o end end if not s then return 'nosign' end "
            "local t={} for _,l in s:GetDescendants() do if l:IsA('TextLabel') then t[#t+1]=l.Text..' ['..tostring(l:GetAttribute('Loc_Text'))..']' end end return table.concat(t,' | ')")
    P(f"[{lang}] FrostSign on the server:", srv)
    shot(f"{lang}_frost_sign")
    texts = [t for t in C(DUMP).split("\n<<>>\n") if t]
    open(f"{OUT}/{lang}_texts.txt", "w", encoding="utf-8").write("\n".join(texts))
    P(f"[{lang}] texts recorded: {len(texts)}")
    raw = sorted({t for t in texts if re.search(r"\{(%s)\}" % "|".join(NAMES), t)})
    ok(f"{lang}: no unsubstituted {{Name}} anywhere", not raw, " ;; ".join(raw)[:500])
    other = sorted({t for t in texts if re.search(r"\{\w+\}", t)})
    P(f"[{lang}] other {{x}} in the texts (for information):", " ;; ".join(other)[:400])
    for k, v in expected(lang).items():
        hit = any(v in t for t in texts)
        ok(f"{lang}: {k} visible with the name", hit, v[:90])

stop()
edit("game.ReplicatedStorage:SetAttribute('LocTest', nil) return 'reset'")
sys.exit(1 if write_result("Dragon names in phrases - {Name} (owner decision 19.10)") else 0)
