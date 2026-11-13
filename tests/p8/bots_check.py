#!/usr/bin/env python3
"""The acceptance of 1.14 (bots for measuring FPS) in the LOCAL file on P8, the Studio window = a phone 812x375.
Settings -> 'Test bots' by a real click; the census: the bot nests, dragons 3-5, the riders on adults fly in circles; the Perf measurement;
the world part budget (04 §9) with bots; yielding a nest to a live player (Admin.yieldBot); 'Test bots' again - everything removed; the console.
Run: python3 tests/p8/bots_check.py A (after tools/p8/open_local.sh). The output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin(f"bots_check_{sys.argv[1]}")
from p8lib import *  # noqa: F401,F403
STEP = "bots"

# the returning_test helpers: the profile between runs (StudioSeed), the start with the splash, the dump, the summary
def edit(code): return run(code, "Edit")
def set_seed(js):
    assert "]=====]" not in js
    return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
def clear_seed(): return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
def start():
    s.call("start_stop_play", {"studio_id": sid, "is_start": True})
    seen = []
    t0 = time.time()
    while time.time() - t0 < 60:  # the splash: the 'Welcome back' summary text in the first seconds
        t = C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') if not g then return 'none' end local b=g:FindFirstChild('Back',true) local s=g:FindFirstChild('Summary',true) local ti=g:FindFirstChild('Title',true) return 'on='..tostring(g.Enabled)..' sum='..(s and s.Text or '-')")
        if t and t not in seen: seen.append(t)
        if "none" in t and len(seen) > 1: break
        time.sleep(0.7)
    P("the splash:", " || ".join(x[:160] for x in seen))
    time.sleep(8)
    S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(1) return 'day'")
def dump(): return S(LD + "return ld('dump')")
def summary(js):
    d = json.loads(js)
    dr = d.get("dragons", {}); now = int(time.time())
    parts = [f"coins={int(d.get('coins',0))} pot={int(d.get('pot',0))} sessions={d.get('sessions')} play={d.get('playSeconds')}s companion={d.get('companion')}",
             f"quest={json.dumps(d.get('quests',{}).get('keeper'))} settings={json.dumps(d.get('settings'))}",
             "dragons: " + "; ".join(f"{u}={v.get('name')}/{v.get('rarity')}/{v.get('element')}/s{v.get('stage')}/rem={(v.get('stageEndsAt') or now) - now}" for u, v in dr.items()),
             "eggs: " + json.dumps(d.get("eggs", {}))[:200]]
    return " | ".join(parts)
def hatch_when_ready(maxwait):
    t0 = time.time()
    while time.time() - t0 < maxwait:
        st = state(); m = re.search(r"inc1=\w+:(-?\d+)", st)
        if m and int(m.group(1)) <= 0: break
        P("  waiting for the egg:", st[:120]); time.sleep(20)
    S(LD + "ld('go inc') task.wait(1.5) return 'x'"); time.sleep(2.5)
    desk(f"R{STEP}_ready")
    a = C("local h=game.Players.LocalPlayer.PlayerGui.HUD.Action return h.Visible and h.Text or '-'"); P("the button:", a)
    press("HUD", "Action", name="Hatch (HUD)"); time.sleep(6)
    if gui_on("NameDialog"): press("NameDialog", "Done"); time.sleep(1.5)
    P("after Hatch:", state()[:200])


TAG = sys.argv[1]

CENSUS = ("local out={} for _,n in workspace.World.Nests:GetChildren() do local df=n:FindFirstChild('Dragons') local k=0 if df then for _,m in df:GetChildren() do if m:IsA('Model') then k+=1 end end end "
          "local tl=n:FindFirstChild('SignPost') and n.SignPost:FindFirstChildWhichIsA('TextLabel',true) "
          "out[#out+1]=string.format('%s bot=%s owner=%s dr=%d rate=%s sign=%s', n.Name, tostring(n:GetAttribute('Bot')), tostring(n:GetAttribute('OwnerId')), k, tostring(n:GetAttribute('Rate')), tl and tl.Text or '-') end "
          "table.sort(out) local f=workspace:FindFirstChild('Bots') local fl,rd,sat={},0,0 if f then for _,m in f:GetChildren() do if m.Name=='BotFlier' then local q=m:GetPivot().Position fl[#fl+1]=string.format('%d,%d,%d',q.X,q.Y,q.Z) "
          "elseif m:FindFirstChildOfClass('Humanoid') then rd+=1 if m.Humanoid.SeatPart then sat+=1 end end end end "
          "return table.concat(out,' | ')..' || fliers='..#fl..' ['..table.concat(fl,' ')..'] riders='..rd..' seated='..sat..' attr='..tostring(workspace:GetAttribute('Bots'))")
BUDGET = ("local parts,mesh,emit,pl,hl,dr=0,0,0,0,0,0 for _,d in workspace:GetDescendants() do if d:IsA('BasePart') then parts+=1 if d:IsA('MeshPart') then mesh+=1 end "
          "elseif d:IsA('ParticleEmitter') and d.Enabled then emit+=1 elseif d:IsA('PointLight') and d.Enabled then pl+=1 elseif d:IsA('Highlight') and d.Enabled then hl+=1 end end "
          "for _,m in game:GetService('CollectionService'):GetTagged('Dragon') do dr+=1 end "
          "local w=0 for _,d in workspace.World:GetDescendants() do if d:IsA('BasePart') then w+=1 end end "
          "return string.format('parts=%d (World %d) mesh=%d emitters=%d pointlights=%d highlights=%d dragons=%d', parts, w, mesh, emit, pl, hl, dr)")

clear_seed()
start()
P("before:", S(CENSUS)[:900])
P("the budget without bots:", S(BUDGET))
desk(f"B_{TAG}_0_before")
# a real click: Settings -> Test bots
press("Topbar", "Top_Settings"); time.sleep(1.5)
P("the button:", C(FIND + "local o=find('Book','Bots') return o and o.Text or 'none'"))
desk(f"B_{TAG}_1_settings")
press("Book", "Bots", name="Test bots"); time.sleep(2)
P("after the click:", C(FIND + "local o=find('Book','Bots') return o and o.Text or 'none'"))
time.sleep(12)
c1 = S(CENSUS); P("with bots:", c1[:1200])
nb = len(re.findall(r"bot=\d", c1)); drs = [int(x) for x in re.findall(r"bot=\d owner=-?\d+ dr=(\d+)", c1)]
ok("5 nests are taken by bots (5 were free)", nb == 5, f"{nb} {drs}")
ok("every bot has 3-5 dragons", len(drs) == 5 and all(3 <= x <= 5 for x in drs), str(drs))
fl = re.search(r"fliers=(\d+).*riders=(\d+) seated=(\d+)", c1)
ok("5 riders on adults, seated in the saddle", fl and fl.group(1) == "5" and fl.group(3) == "5", fl.group(0) if fl else c1[-200:])
p1 = re.findall(r"\[([^\]]*)\]", c1); time.sleep(3); c2 = S(CENSUS); p2 = re.findall(r"\[([^\]]*)\]", c2)
ok("the riders fly (the positions changed over 3 s)", p1 and p2 and p1[0] != p2[0], f"{p1[:1]} -> {p2[:1]}")
P("the budget with bots:", S(BUDGET))
# frames: the island from above and a bot nest up close
C("local cam=workspace.CurrentCamera cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(Vector3.new(0,260,-330), Vector3.new(0,60,0)) return 'cam'"); time.sleep(2.5)
desk(f"B_{TAG}_2_island")
C("local n=nil for _,x in workspace.World.Nests:GetChildren() do if x:GetAttribute('Bot') then n=x end end if not n then return 'none' end local p=n.Base.Position local cam=workspace.CurrentCamera cam.CFrame=CFrame.lookAt(p+Vector3.new(0,30,-45), p) return 'cam'"); time.sleep(2.5)
desk(f"B_{TAG}_3_botnest")
C("local f=workspace.Bots:FindFirstChild('BotFlier') if not f then return 'none' end local p=f:GetPivot().Position local cam=workspace.CurrentCamera cam.CFrame=CFrame.lookAt(p+Vector3.new(20,8,20), p) return 'cam'"); time.sleep(1.0)
desk(f"B_{TAG}_4_flier")
C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'free'")
# the duplicate safeguard does not touch the bots (every 3 s): after 8 s the same number of dragons
time.sleep(8); c3 = S(CENSUS)
d1, d3 = re.findall(r"dr=(\d+)", c1), re.findall(r"dr=(\d+)", c3)
ok("the duplicate safeguard does not remove bots", d1 == d3, f"{d1} -> {d3}")
# the measurement: the Perf line in the server console and FPS in Settings
time.sleep(20)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
perf = [l for l in ctext.splitlines() if "[Perf]" in l]
P("Perf:", " ;; ".join(perf[-4:])[:600])
ok("the Perf measurement reaches the server (bots5 in the line)", any("bots5" in l for l in perf), (perf[-1] if perf else "no lines")[:200])
C(CD + "return cd('back')"); time.sleep(1)
press("Topbar", "Top_Settings"); time.sleep(1.5)
ver = C(FIND + "local g=pg:FindFirstChild('Book') local v=g and g:FindFirstChild('Version',true) return v and v.Text or 'none'"); P("the version line:", ver)
ok("in Settings the owner sees FPS", "fps" in ver, ver)
desk(f"B_{TAG}_5_settings_fps")
# yielding a nest to a live player: Admin.yieldBot directly (there is no second player in Studio)
P("yieldBot:", S(LD + "local r=ld('yieldbot') local i=tonumber(r:match('reply=true/(%d+)')) local n=workspace.World.Nests:GetChildren() local s='' for _,x in n do if x.Name:find(tostring(i)) then local tl=x.SignPost:FindFirstChildWhichIsA('TextLabel',true) s=x.Name..' bot='..tostring(x:GetAttribute('Bot'))..' sign='..tl.Text end end return tostring(i)..' '..s..' attr='..tostring(workspace:GetAttribute('Bots'))"))
# click again: remove everyone
press("Book", "Bots", name="Test bots off"); time.sleep(3)
c4 = S(CENSUS); P("after switching off:", c4[:900])
ok("the bots are removed: 0 bot nests, 0 riders, the Free Nest signs", "bot=nil" in c4 and not re.search(r"bot=\d", c4) and "fliers=0" in c4 and "riders=0" in c4 and c4.count("Free Nest") == 5, c4[-160:])
P("the budget after:", S(BUDGET))
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|\[\w+\] .*(fail|error|\[Admin\]|\[Dup\]", l, re.I) and "ExecuteLuau" not in l and "errors 0" not in l]
ok("the console without errors", not errs, " ;; ".join(errs[:6])[:500])
s.call("start_stop_play", {"studio_id": sid, "is_start": False}); time.sleep(2)
P("RESULT:", f"{sum(1 for r in res if r[1])}/{len(res)} OK")
s.close()
