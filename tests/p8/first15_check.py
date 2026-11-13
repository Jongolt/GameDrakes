#!/usr/bin/env python3
"""The first 15 minutes of a newcomer in REAL time (the clock is not fast-forwarded) against spec 02 §2 and the gates
§5 (hatch <= 20 s, glide <= 60 s, second egg <= 120 s, teen <= 180 s, adult <= 480 s) in a LOCAL file on P8.
The newcomer follows the spec route: walking is replaced by teleport (faster than a player - time gates are checked by the game timers, not by
legs), buttons - the same Remotes the UI calls, eggs in the glade - the real E key. Recorder: every ~6 s the visible
UI texts (screen and world labels nearby) and the server state -> timeline.jsonl; every minute a frame M00..M15;
at the end the onboarding steps from the profile (Analytics.onboard writes os.time() of the step) -> seconds from join, table result.md.
Run: python3 tests/p8/first15_check.py [minutes=15] (after tools/p8/open_local.sh). Output: p8lib.OUT."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("first15_check")
from p8lib import *  # noqa: F401,F403

MINUTES = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 15
TL = open(f"{OUT}/timeline.jsonl", "w")

TEXTS = r"""
local me=game.Players.LocalPlayer local pg=me.PlayerGui
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local out={} local seen={}
local skip={Chat=true,BubbleChat=true,Freecam=true}
for _,g in pg:GetChildren() do
  if g:IsA('LayerCollector') and g.Enabled and not skip[g.Name] then
    local t={}
    for _,o in g:GetDescendants() do
      if (o:IsA('TextLabel') or o:IsA('TextButton')) and o.ContentText~='' and shown(o) and #t<14 then
        local s=o.ContentText:gsub('%s+',' ') local k=g.Name..s if not seen[k] then seen[k]=true t[#t+1]=s:sub(1,70) end
      end
    end
    if #t>0 then out[#out+1]=g.Name..': '..table.concat(t,' / ') end
  end
end
local root=me.Character and me.Character:FindFirstChild('HumanoidRootPart')
if root then
  local w={}
  for _,b in workspace:GetDescendants() do
    if b:IsA('BillboardGui') and b.Enabled and b.Parent and b.Parent:IsA('BasePart') and (b.Parent.Position-root.Position).Magnitude<45 then
      for _,o in b:GetDescendants() do if o:IsA('TextLabel') and o.ContentText~='' and o.Visible and #w<10 then local s=o.ContentText:gsub('%s+',' ') if not seen['w'..s] then seen['w'..s]=true w[#w+1]=s:sub(1,50) end end end
    end
  end
  if #w>0 then out[#out+1]='WORLD: '..table.concat(w,' / ') end
end
out[#out+1]=string.format('ATTR gliding=%s mounted=%s flying=%s pos=%s', tostring(me:GetAttribute('Gliding')), tostring(me:GetAttribute('Mounted')), tostring(me:GetAttribute('Flying')), root and string.format('%.0f,%.0f,%.0f', root.Position.X, root.Position.Y, root.Position.Z) or '-')
return table.concat(out,' || ')
"""

t0 = None
def el(): return time.time() - t0
def stamp(): s_ = int(el()); return f"{s_ // 60}:{s_ % 60:02d}"
last_rec = -99.0
next_min = 0
events = []
def ev(name, detail=""):
    events.append((round(el(), 1), name, detail)); P(f"[{stamp()}] {name} | {detail[:200]}")
def record(force=False):
    global last_rec, next_min
    if not force and el() - last_rec < 6:
        return
    last_rec = el()
    tx = C(TEXTS); st = state()
    TL.write(json.dumps({"t": round(el(), 1), "texts": tx, "state": st}, ensure_ascii=False) + "\n"); TL.flush()
    if el() >= next_min * 60:
        shot(f"M{next_min:02d}"); next_min += 1
def wait_until(cond, timeout, step=1.0):
    t1 = time.time()
    while time.time() - t1 < timeout:
        record()
        try:
            if cond(): return True
        except Exception as e:  # noqa: BLE001
            P("cond:", repr(e)[:120])
        time.sleep(step)
    return False
def sleep_rec(sec):
    t1 = time.time()
    while time.time() - t1 < sec:
        record(); time.sleep(1)
def inc1():
    m = re.search(r"inc1=(\w+):(-?\d+)", state()); return (m.group(1), int(m.group(2))) if m else (None, None)
def dragons():
    return re.findall(r"(d\d+)=(\w+)/(\w+)/s(\d)", state())
def feed_all():
    return C("local r=game.ReplicatedStorage.Remotes.Feed:InvokeServer('all') return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def ledge_profile():  # the ground past the ledge of the own nest: height above it at 0..40 studs from the edge (Glide.minHeight 12)
    return S("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end "
             "if not n then return 'nonest' end local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={p.Character} local out={} "
             "local top=(n:GetPivot()*CFrame.new(0,0,54)).Position.Y "
             "for _,dz in {56,58,60,64,70,80,95} do local q=(n:GetPivot()*CFrame.new(0,0,dz)).Position local h=workspace:Raycast(Vector3.new(q.X,top+30,q.Z),Vector3.new(0,-200,0),rp) "
             "out[#out+1]=string.format('z%d:%.1f', dz, h and top-h.Position.Y or -1) end return 'drop below ledge top: '..table.concat(out,' ')")
def mount(uid):
    return C(f"local r=game.ReplicatedStorage.Remotes.Mount:InvokeServer('{uid}') return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def hatch(slot=1):
    return C(f"local r=game.ReplicatedStorage.Remotes.HatchReady:InvokeServer({slot}) return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def to_nest_offset(dx, dy, dz):  # a point in the own nest coordinates (0,0,55 - the ledge)
    return S("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end "
             f"if not n then return 'nonest' end p.Character:PivotTo(n:GetPivot()*CFrame.new({dx},{dy},{dz})) return 'ok'")
def to_egg(zone):  # to the nearest lying egg of the zone, 3 studs to the side
    return S("local p=game.Players:GetPlayers()[1] local r=p.Character.HumanoidRootPart local best,bd "
             f"for _,e in workspace:GetDescendants() do if e:IsA('Model') and e.Name=='Egg' and e.Parent and e.Parent:GetAttribute('Zone')=='{zone}' and not e.Parent:GetAttribute('Secret') then "
             "local d=(e:GetPivot().Position-r.Position).Magnitude if not bd or d<bd then best,bd=e,d end end end "
             "if not best then return 'noegg' end p.Character:PivotTo(CFrame.new(best:GetPivot().Position+Vector3.new(3,3,0))) return 'egg '..math.floor(bd)")

# ------------------------------------------------------------------------------ newcomer join
stop()
s.call("start_stop_play", {"studio_id": sid, "is_start": True})
for _ in range(90):
    if C("return tostring(game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') ~= nil)") == "false": break
    time.sleep(0.5)
t0 = time.time()
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.5) return 'day'")
ev("splash gone (0:00)")
record(force=True)
sleep_rec(4)

# 0:03-0:10 egg from the table -> bowl
S(LD + "ld('go table') return 'x'"); ev("walked to the table")
picked = wait_until(lambda: "carry=-" not in state(), 8); ev("egg in the hands" if picked else "EGG NOT PICKED UP", state()[:160])
sleep_rec(3)
S(LD + "ld('go inc') return 'x'"); ev("walked to the incubator")
placed = wait_until(lambda: inc1()[0] is not None, 8); ev("egg in the bowl" if placed else "EGG NOT IN THE BOWL", state()[:160])
ready = wait_until(lambda: (lambda r: r is not None and r <= 0)(inc1()[1]), 30); ev("ready to hatch" if ready else "NOT READY in 30 s", str(inc1()))
r = hatch(1); ev("Hatch", r)
nd = wait_until(lambda: gui_on("NameDialog"), 8, 0.4); ev("name dialog opened" if nd else "NO NAME DIALOG")
if nd:
    closed = wait_until(lambda: not gui_on("NameDialog"), 9, 0.5); ev("name dialog closed by itself" if closed else "name dialog did NOT close in 9 s")

# 0:18-0:30 coins
sleep_rec(6)
S(LD + "ld('go pile') return 'x'"); ev("walked through a coin pile", state()[:120])
sleep_rec(8)

# 0:30-1:00 quest 1 and gliding from the ledge (baby on the shoulder)
ev("quest", C("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Quests') local t={} if q then for _,o in q:GetDescendants() do if o:IsA('TextLabel') and o.Visible and o.ContentText~='' then t[#t+1]=o.ContentText end end end return table.concat(t,' / ')"))
sleep_rec(6)
ev("profile past the ledge", ledge_profile())
to_nest_offset(0, 3, 44); sleep_rec(1)
S("local p=game.Players:GetPlayers()[1] local ch=p.Character local r=ch.HumanoidRootPart local n for _,x in game:GetService('CollectionService'):GetTagged('Incubator') do if x:GetAttribute('OwnerId')==p.UserId then n=x.Parent.Parent end end "
  "local f=(n:GetPivot()*CFrame.new(0,0,80)).Position ch:PivotTo(CFrame.lookAt(r.Position, Vector3.new(f.X, r.Position.Y, f.Z))) return 'face'")
C("local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart c.CFrame=CFrame.lookAt(r.Position-r.CFrame.LookVector*12+Vector3.new(0,5,0), r.Position+r.CFrame.LookVector*20) return 'cam'")
# step off the ledge: Humanoid:Move on the client every frame (like the joystick control module; ssh keys do not always reach P8)
fwd = S("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end "
        "local z=n:GetPivot():VectorToWorldSpace(Vector3.new(0,0,1)) return string.format('%.3f,0,%.3f', z.X, z.Z)")
C("local me=game.Players.LocalPlayer local h=me.Character:FindFirstChildOfClass('Humanoid') local t0=os.clock() local c c=game:GetService('RunService').RenderStepped:Connect(function() "
  f"if os.clock()-t0<3.2 then h:Move(Vector3.new({fwd}).Unit,false) else h:Move(Vector3.zero,false) c:Disconnect() end end) return 'move'")
ev("step off the ledge (Humanoid:Move 3.2 s, like a joystick)")
gl = wait_until(lambda: C("return tostring(game.Players.LocalPlayer:GetAttribute('Gliding'))") == "true" or "glided=true" in S(LD + "local d=game.ServerStorage.LoopDebug:Invoke('dump') return d:find('\"glided\":true') and 'glided=true' or '-'"), 6, 0.3)
ev("gliding" if gl else "NO GLIDING")
landed = wait_until(lambda: C("return tostring(game.Players.LocalPlayer:GetAttribute('Gliding'))") != "true", 25, 0.5); ev("landed" if landed else "gliding longer than 25 s")

# 1:00-1:40 egg in the glade (real E key) -> back to the nest
ev("to the Meadow egg", to_egg("Meadow")); sleep_rec(2)
keys("down e;wait 900;up e"); got = wait_until(lambda: "carry=-" not in state(), 6); ev("second egg in the hands" if got else "SECOND EGG NOT PICKED UP (E)", state()[:160])
sleep_rec(8)
S(LD + "ld('go inc') return 'x'"); ev("back at the incubator (second egg)")
wait_until(lambda: "carry=-" in state(), 8); ev("after the incubator", state()[:200])

# 1:30-2:00 50 Keeper coins, berries
sleep_rec(5)
S("local p=game.Players:GetPlayers()[1] local st=workspace.World:FindFirstChild('Stall',true) if st then p.Character:PivotTo(st.CFrame*CFrame.new(0,3,-5)) return 'stall' end return 'nostall'"); ev("at the stall")
sleep_rec(3)
pr = C("local st=game:GetService('CollectionService'):GetTagged('Stall')[1] local p=st and st:FindFirstChild('StallFeed') if not p then return 'noprompt' end "
       "p:InputHoldBegin() task.wait(0.2) p:InputHoldEnd() return p.ActionText..' / '..p.ObjectText")  # like tapping the prompt on a phone
sleep_rec(3); fed = "/fed" in state(); ev(f"berries at the stall ({pr})" if fed else f"did NOT feed at the stall ({pr})", state()[:200])
if not fed:
    S(LD + "ld('go pile') return 'x'"); sleep_rec(2)
    ev("Feed all at the nest (Remote, like the Feed All button)", feed_all())
last_feed = el()

# then - wait for growth in real time, mount the teen, take off on the adult; hatch the ready eggs
S(LD + "ld('go table') return 'x'")
rode = flew = False
hatched2 = 0
while el() < MINUTES * 60:
    record()
    ds = dragons()
    inc = inc1()
    if inc[0] and inc[1] is not None and inc[1] <= 0:
        S(LD + "ld('go inc') return 'x'"); sleep_rec(2)
        ev("second hatch" if hatched2 == 0 else "hatch", hatch(1)); hatched2 += 1
        sleep_rec(7); S(LD + "ld('go table') return 'x'")
    if el() - last_feed > 305 and any(st in ("0", "1") for _, _, _, st in ds):  # Fed x2 lasts 5 min - feed again
        S(LD + "ld('go pile') return 'x'"); sleep_rec(2); ev("refeed (Feed All)", feed_all()); last_feed = el(); S(LD + "ld('go table') return 'x'")
    if not rode and any(st == "1" for _, _, _, st in ds):
        uid = [u for u, _, _, st in ds if st == "1"][0]
        ev("teen", uid); sleep_rec(3); ev("Ride (Remote)", mount(uid)); sleep_rec(6)
        ev("Dismount", C("local r=game.ReplicatedStorage.Remotes.Dismount:InvokeServer() return tostring(r and r.ok)")); rode = True
    if not flew and any(st == "2" for _, _, _, st in ds):
        uid = [u for u, _, _, st in ds if st == "2"][0]
        ev("adult", uid); sleep_rec(4); ev("Fly (Remote)", mount(uid)); sleep_rec(2)
        ev("takeoff", C(CD + "return tostring(cd('fly up on'))")); sleep_rec(5); C(CD + "return tostring(cd('fly off'))")
        sleep_rec(8); ev("Dismount", C("local r=game.ReplicatedStorage.Remotes.Dismount:InvokeServer() return tostring(r and r.ok)"))
        S(LD + "ld('go table') return 'x'"); flew = True
    time.sleep(2)
record(force=True)

# ------------------------------------------------------------------------------ result: onboarding steps from the profile
d = dump()
ob = ((d.get("analytics") or {}).get("onboard") or {})
join = min(ob.values()) if ob else None   # step 1 spawn = the join moment
NAMES = {1: "spawn", 2: "egg_first_pick", 3: "hatch_first", 4: "coins_first_collect", 5: "glide_first", 6: "egg_second", 7: "feed_first",
         8: "juvenile_first", 9: "ride_first", 10: "hatch_second", 11: "adult_first", 12: "fly_first", 13: "ascension_first"}
TZ = {2: "0:03-0:10", 3: "0:10-0:13", 4: "0:18-0:30", 5: "0:50-1:00", 6: "1:00-1:40", 7: "1:45-2:00", 8: "2:00-2:30", 9: "2:30-2:45",
      10: "3:30-4:30", 11: "5:00-7:30", 12: "7:30-8:00", 13: "10:00-20:00"}
GATE = {3: 20, 5: 60, 6: 120, 8: 180, 11: 480}
steps = {}
for k, v in ob.items():
    steps[int(k)] = v - join
P("onboarding steps (s from join):", json.dumps({NAMES[k]: steps[k] for k in sorted(steps)}, ensure_ascii=False))
for k in sorted(NAMES):
    if k == 1: continue
    sec = steps.get(k)
    gate = GATE.get(k)
    det = f"{NAMES[k]}: {('%d:%02d' % (sec // 60, sec % 60)) if sec is not None else 'none'} (spec {TZ.get(k, '-')}{', gate <= %d s' % gate if gate else ''})"
    if gate:
        ok(f"gate: {NAMES[k]} <= {gate} s", sec is not None and sec <= gate, det)
    else:
        P("step", det)
json.dump({"events": events, "onboard": steps}, open(f"{OUT}/events.json", "w"), ensure_ascii=False, indent=0)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:5]))
stop()
write_result(f"First {MINUTES} minutes of a newcomer (real time)")
s.close()
