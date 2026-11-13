#!/usr/bin/env python3
"""Smooth table eggs and the victory phrase after a fight on P8, LOCAL file.
  1) the newcomer table: took egg 1 - after ~0.3 s (0.2 + the LoopDebug wait 0.1) it is hidden, the other two fade (0 < transparency < 1, the Fading mark); after 1 s all
     three are hidden, no mark (Config.Loop.tableFade 0.5);
  2) the ambush after the first egg - the fight music Music_fight (track A or C);
  3) 'combat clear' - Fight removed right away, fight_win plays in tune with the track (A -> 88533814202542, C -> 115216657381233), the fight track fades;
  4) after 3.5 s there is no state music (the phrase plays alone); after 8 s - the state music again (not fight);
  5) console without game errors.
Run: python3 tests/p8/pkg28_check.py."""
import os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("pkg28_check")
from p8lib import *  # noqa: F401,F403

def ld(c): return S(LD + f"return ld('{c}')")
WIN = {"70406877413972": "88533814202542", "122122871722371": "115216657381233"}
# the own table - the one where egg 2 is visible (other nests are empty, resetTable); measured inside one server call - 0.5 s
# does not wait out the P8 -> Studio round trip
TABLE = LD + r"""
local tbl
for _, d in workspace:GetDescendants() do
	if d.Name == 'EggTable' and d:IsA('BasePart') then
		local e = d:FindFirstChild('TableEgg2')
		if e then
			for _, x in e:GetDescendants() do
				if x:IsA('BasePart') and x.Transparency < 0.99 then tbl = d break end
			end
		end
	end
	if tbl then break end
end
if not tbl then return 'notable' end
local function t(k)
	local e = tbl:FindFirstChild('TableEgg' .. k)
	local mn = 1
	for _, x in e:GetDescendants() do
		if x:IsA('BasePart') then mn = math.min(mn, x.Transparency) end
	end
	return string.format('%.2f', mn) .. (if e:GetAttribute('Fading') then 'F' else '')
end
local r = ld('table 1')
task.wait(0.2)
local a = t(1) .. ',' .. t(2) .. ',' .. t(3)
task.wait(0.8)
local b = t(1) .. ',' .. t(2) .. ',' .. t(3)
local okr = typeof(r) == 'string' and r:find('reply=true', 1, true) ~= nil -- LoopDebug replies with a string (Nest.luau)
return tostring(okr) .. '|' .. a .. '|' .. b
"""
MUS = ("local SS=game:GetService('SoundService') local o={} for _,x in SS:GetChildren() do if x:IsA('Sound') and "
       "(x.Name:sub(1,6)=='Music_' or x.Name=='fight_win') then table.insert(o, x.Name..'='..(x.SoundId:match('%d+') or '?').."
       "'@'..string.format('%.2f',x.Volume)..(x.IsPlaying and 'P' or '')) end end "
       "return table.concat(o,' ')..' fight='..tostring(game.Players.LocalPlayer:GetAttribute('Fight'))")

def parse(m):  # {name: (id, volume)}
    out = {}
    for tok in m.split():
        if "=" in tok and "@" in tok and not tok.startswith("fight="):
            n, rest = tok.split("=", 1)
            sid_, vol = rest.split("@", 1)
            out[n] = (sid_, float(vol.rstrip("P")))
    return out

stop()
P("seed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value='{\"coins\":0}' return #s.Value", "Edit"))
start()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
tb = S(TABLE)
P("table:", tb)
parts = tb.split("|")
okp = len(parts) == 3 and parts[0] == "true"
a = parts[1].split(",") if okp else []
b = parts[2].split(",") if okp else []
def tr(v): return float(v.rstrip("F"))
ok("1a. took egg 1 - it is hidden right away", okp and tr(a[0]) >= 0.99, tb)
ok("1b. after 0.2 s the other two fade (0 < T < 1, Fading)", okp and all(0.0 < tr(x) < 0.99 and x.endswith("F") for x in a[1:]), tb)
ok("1c. after 1 s all three are hidden, no Fading mark", okp and all(tr(x) >= 0.99 and not x.endswith("F") for x in b), tb)

ld("go inc")
fight = None
for _ in range(80):
    m = C(MUS)
    if "Music_fight=" in m:
        fight = m; break
    time.sleep(0.5)
ok("2. ambush - fight music Music_fight (A or C)", fight is not None and parse(fight).get("Music_fight", ("",))[0] in WIN, fight or C(MUS))
track = parse(fight)["Music_fight"][0] if fight else ""
time.sleep(2)
P("clear:", ld("combat clear")[:40]); time.sleep(0.5)
m3 = C(MUS)
p3 = parse(m3)
P("after clear:", m3)
ok("3a. Fight removed right after the cleared wave", "fight=nil" in m3, m3)
ok("3b. the victory phrase in tune with the fight track", p3.get("fight_win", ("",))[0] == WIN.get(track), f"track {track} -> {p3.get('fight_win')}")
ok("3c. the fight track fades (volume below full or removed)", "Music_fight" not in p3 or p3["Music_fight"][1] < 0.17, m3)
time.sleep(3)
m4 = C(MUS)
p4 = parse(m4)
P("+3.5 s:", m4)
ok("4a. the phrase plays alone - no state music", not any(n.startswith("Music_") and v[1] > 0.02 for n, v in p4.items()), m4)
time.sleep(5)
m5 = C(MUS)
p5 = parse(m5)
P("+8 s:", m5)
ok("4b. after the phrase - state music (not fight)", any(n.startswith("Music_") and n != "Music_fight" for n in p5), m5)
desk("after_win")

cons = s.call("get_console_output", {"studio_id": sid}, 120)
lines = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
bad = [l for l in lines if ("rror" in l or "[Combat]" in l or "[EggSpawner]" in l) and "errors 0" not in l and "TexturePack" not in l]
ok("5. console without game errors", not bad, str(len(bad)))
for l in bad[-6:]: P("  ", l[:200])
stop()
P("unseed:", run("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'", "Edit"))
write_result("Pack 28.10: table eggs and the victory phrase")
