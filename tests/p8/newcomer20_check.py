#!/usr/bin/env python3
"""A FULL 20-MINUTE NEWCOMER PASS in real time (the clock is not fast-forwarded) in a LOCAL file on P8,
phone window 812x375, fresh profile (no StudioSeed). Difference from first15_check (18.10): the newcomer WALKS ON FOOT (PathfindingService +
Humanoid:MoveTo - table, bowl, pile, ledge, egg on the meadow, back up the stairs, stall); teleport is only a fallback, and it
is recorded as the discrepancy 'did not make it on foot'. Buttons - real mouse clicks on the HUD (Hatch, Feed All, Ride, Fly, Dismount, X),
the fallback - the same Remote, also marked. Prompts (egg on the meadow, stall, chest) - ProximityPrompt InputHoldBegin/End, like
a button on a phone.
Recorder: on the client every 0.5 s new visible screen texts (catches toasts and banners shorter than 6 s) -> texts.log; every ~6 s a snapshot
of the server state -> timeline.jsonl; a frame every minute M00..M20 and on events E<mmss>_<name>; at the end the funnel steps from the profile
against spec 02 §2 and the gates §5 -> result.md, events.json. Discrepancy analysis - by hand from the frames and texts (REPORT.md next to it).
Run: python3 tests/p8/newcomer20_check.py [minutes=20] (after tools/p8/open_local.sh). Output: $P8_OUT_ROOT/roblox_build_<date>/newcomer20/."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("newcomer20")
from p8lib import *  # noqa: F401,F403

MINUTES = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 20
TL = open(f"{OUT}/timeline.jsonl", "w")
TX = open(f"{OUT}/texts.log", "w")

# ------------------------------------------------------------------------------------------------ Luau templates
NEST = ("local p=game.Players:GetPlayers()[1] local n for _,r in game:GetService('CollectionService'):GetTagged('Incubator') do "
        "if r:GetAttribute('OwnerId')==p.UserId then n=r.Parent.Parent end end ")

# text recorder on the client: every 0.5 s new visible texts (key - the text with digits -> #, so counters do not spam)
SAMPLER = r"""
local me=game.Players.LocalPlayer local pg=me.PlayerGui
local old=pg:FindFirstChild('NCBuf') if old then old:Destroy() end
local sv=Instance.new('StringValue') sv.Name='NCBuf' sv.Parent=pg
_G.__nc={buf={},last={},t0=os.clock()}
local skip={Chat=true,BubbleChat=true,Freecam=true}
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
task.spawn(function()
  while sv.Parent do
    local now={}
    local ok=pcall(function()
      for _,g in pg:GetChildren() do
        if g:IsA('LayerCollector') and g.Enabled and not skip[g.Name] then
          for _,o in g:GetDescendants() do
            if (o:IsA('TextLabel') or o:IsA('TextButton')) and o.ContentText~='' and o.AbsoluteSize.Y>0 and shown(o) then
              local s=g.Name..': '..(o.ContentText:gsub('%s+',' ')):sub(1,100)
              local k=s:gsub('%d','#')
              now[k]=true
              if not _G.__nc.last[k] then _G.__nc.buf[#_G.__nc.buf+1]=string.format('%.1f|%s', os.clock()-_G.__nc.t0, s) end
            end
          end
        end
      end
    end)
    if ok then _G.__nc.last=now end
    if #_G.__nc.buf>0 then sv.Value=sv.Value..table.concat(_G.__nc.buf,'\n')..'\n' table.clear(_G.__nc.buf) end
    if #sv.Value>200000 then sv.Value=sv.Value:sub(-100000) end
    task.wait(0.5)
  end
end)
return 'sampler on'
"""
DRAIN = "local sv=game.Players.LocalPlayer.PlayerGui:FindFirstChild('NCBuf') if not sv then return 'NOSAMPLER' end local s=sv.Value sv.Value='' return s"

# snapshot of the visible texts (screen + world labels closer than 45 studs) - once every ~6 s, as in first15
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

# walking on foot (server, non-blocking): PathfindingService path -> Humanoid:MoveTo along the points; the result in ServerStorage.WalkState
WALK = NEST + r"""
local ch=p.Character local hum=ch:FindFirstChildOfClass('Humanoid') local root=ch.HumanoidRootPart
local goal=Vector3.new(%s)
local SS=game:GetService('ServerStorage') local st=SS:FindFirstChild('WalkState') if not st then st=Instance.new('StringValue') st.Name='WalkState' st.Parent=SS end
st.Value='walking'
task.spawn(function()
  local PFS=game:GetService('PathfindingService')
  local path=PFS:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
  local okp=pcall(function() path:ComputeAsync(root.Position,goal) end)
  if not okp or path.Status~=Enum.PathStatus.Success then st.Value='nopath:'..(okp and path.Status.Name or 'err') return end
  local wps=path:GetWaypoints() local t0=os.clock() local stuck=0
  for i,w in wps do
    if st.Value~='walking' then return end
    if i>1 then
      if w.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
      hum:MoveTo(w.Position)
      local done=false local c=hum.MoveToFinished:Connect(function() done=true end)
      local t1=os.clock() while not done and os.clock()-t1<4 do task.wait(0.05) end c:Disconnect()
      if not done then stuck+=1 end
      if os.clock()-t0>%d then break end
    end
  end
  st.Value=string.format('done:%%.1f:%%d:%%.0f:%%d',(root.Position-goal).Magnitude,#wps,os.clock()-t0,stuck)
end)
return 'started'
"""
STOPWALK = "local st=game:GetService('ServerStorage'):FindFirstChild('WalkState') if st then st.Value='stop' end local p=game.Players:GetPlayers()[1] local h=p.Character and p.Character:FindFirstChildOfClass('Humanoid') if h then h:MoveTo(p.Character.HumanoidRootPart.Position) end return 'x'"
WALKSTATE = "local st=game:GetService('ServerStorage'):FindFirstChild('WalkState') return st and st.Value or '-'"

# ------------------------------------------------------------------------------------------------ recorder and events
t0 = None
def el(): return time.time() - t0
def stamp(): s_ = int(el()); return f"{s_ // 60}:{s_ % 60:02d}"
def tag(): s_ = int(el()); return f"E{s_ // 60:02d}{s_ % 60:02d}"
last_rec = -99.0
next_min = 0
events = []
findings = []   # stand/game discrepancies found along the way (teleport instead of walking, a button did not work)
def ev(name, detail="", frame=None):
    events.append((round(el(), 1), name, detail)); P(f"[{stamp()}] {name} | {detail[:220]}")
    if frame: shot(f"{tag()}_{frame}")
def finding(text):
    findings.append((round(el(), 1), text)); P(f"[{stamp()}] DISCREPANCY: {text}")
def drain():
    tx = C(DRAIN)
    if tx and tx != "NOSAMPLER":
        for line in tx.splitlines():
            TX.write(line + "\n")
        TX.flush()
    return tx
def record(force=False):
    global last_rec, next_min
    if not force and el() - last_rec < 6:
        return
    last_rec = el()
    st = state(); tx = C(TEXTS)
    TL.write(json.dumps({"t": round(el(), 1), "state": st, "texts": tx}, ensure_ascii=False) + "\n"); TL.flush()
    drain()
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

# ------------------------------------------------------------------------------------------------ game state
def inc1():
    m = re.search(r"inc1=(\w+):(-?\d+)", state()); return (m.group(1), int(m.group(2))) if m else (None, None)
def dragons(): return re.findall(r"(d\d+)=(\w+)/(\w+)/s(\d)", state())
def coins():
    m = re.search(r"coins=(\d+)", state()); return int(m.group(1)) if m else -1
def carrying(): return "carry=-" not in state()
def attr(a): return C(f"return tostring(game.Players.LocalPlayer:GetAttribute('{a}'))")
def action(): return C("local h=game.Players.LocalPlayer.PlayerGui:FindFirstChild('HUD') if not h then return '-|-' end local a,b=h:FindFirstChild('Action'),h:FindFirstChild('Action2') return (a and a.Visible and a.Text or '-')..'|'..(b and b.Visible and b.Text or '-')")
def quest_text(): return C("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Quests') local t={} if q then for _,o in q:GetDescendants() do if o:IsA('TextLabel') and o.Visible and o.ContentText~='' then t[#t+1]=o.ContentText end end end return table.concat(t,' / ')")
def banner_text(): return C("local q=game.Players.LocalPlayer.PlayerGui:FindFirstChild('StepBanner') local t={} if q then for _,o in q:GetDescendants() do if o:IsA('TextLabel') and o.Visible and o.ContentText~='' then t[#t+1]=o.ContentText end end end return table.concat(t,' / ')")
def pos(): return S("local p=game.Players:GetPlayers()[1] local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart') return r and string.format('%.1f,%.1f,%.1f', r.Position.X, r.Position.Y, r.Position.Z) or '-'")
def nest_point(dx, dy, dz): return S(NEST + f"if not n then return '-' end local q=(n:GetPivot()*CFrame.new({dx},{dy},{dz})).Position return string.format('%.2f,%.2f,%.2f', q.X, q.Y, q.Z)")
def part_point(expr, off="0,0,0"):  # expr -> BasePart (Luau), point = position + offset in the part axes
    return S(NEST + f"local t={expr} if not (t and t:IsA('BasePart')) then return '-' end local q=(t.CFrame*CFrame.new({off})).Position return string.format('%.2f,%.2f,%.2f', q.X, q.Y, q.Z)")

# ------------------------------------------------------------------------------------------------ newcomer actions
def dist_to(point):
    """XZ distance from the character to the point 'x,y,z' (this is how the server measures the pickup/placing/collect radii)."""
    r = S(f"local p=game.Players:GetPlayers()[1] local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart') if not r then return '-1' end local q=Vector3.new({point}) return string.format('%.2f', (Vector3.new(q.X,0,q.Z)-Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude)")
    try: return float(r)
    except ValueError: return -1.0
def step_to(point, sec=3.0):
    """A step straight to the point (Humanoid:MoveTo without a path, like a player pushing against the table/bowl), sec seconds."""
    S(f"local p=game.Players:GetPlayers()[1] local h=p.Character:FindFirstChildOfClass('Humanoid') h:MoveTo(Vector3.new({point})) return 'x'")
    sleep_rec(sec)
    S("local p=game.Players:GetPlayers()[1] local h=p.Character:FindFirstChildOfClass('Humanoid') h:MoveTo(p.Character.HumanoidRootPart.Position) return 'x'")
def walk(name, point, maxsec=60, near=3.0, fallback=None, closer=None):
    """Walk on foot to the point 'x,y,z' (PathfindingService path + MoveTo). Did not get closer than near - a straight step to closer (or to the point) for 3 s.
    Still far - a fallback teleport (fallback: a LoopDebug 'go ...' line or a point) with a discrepancy record. True - got there by itself."""
    if not point or point == "-":
        finding(f"{name}: target not found ({point})")
        return False
    r = S(WALK % (point, maxsec)); ev(f"walking: {name}", f"{r} -> {point}")
    done = wait_until(lambda: not S(WALKSTATE).startswith("walking"), maxsec + 8, 0.7)
    st = S(WALKSTATE); S(STOPWALK)
    m = re.match(r"done:([\d.]+):(\d+):(\d+):(\d+)", st)
    dist = float(m.group(1)) if m else 9999
    if m and dist > near:
        step_to(closer or point, 3.0); d2 = dist_to(point)
        ev(f"straight step: {name}", f"was {dist:.1f}, now {d2:.1f} (XZ)")
        dist = d2
    ok_ = done and m is not None and 0 <= dist <= near
    ev(f"arrived: {name}" if ok_ else f"DID NOT ARRIVE: {name}", f"{st} (path {m.group(2) + ' points, ' + m.group(3) + ' s, stuck ' + m.group(4) if m else 'no path'}; to target {dist:.1f})")
    if not ok_:
        finding(f"did not reach '{name}' on foot: {st}, to target {dist:.1f} - fallback teleport")
        if fallback:
            if fallback.startswith("go "):
                S(LD + f"ld('{fallback}') return 'x'")
            else:
                S(NEST + f"p.Character:PivotTo(CFrame.new(Vector3.new({fallback})+Vector3.new(0,3,0))) return 'tp'")
            time.sleep(1.5)
    return ok_

def hold_nearest_prompt(maxdist=12):
    """Press the nearest prompt (ProximityPrompt), like a button on a phone. Returns ActionText or 'noprompt'."""
    return C("local best,bd local r=game.Players.LocalPlayer.Character.HumanoidRootPart local function at(x) if x:IsA('BasePart') then return x.Position elseif x:IsA('Attachment') then return x.WorldPosition elseif x:IsA('Model') then return x:GetPivot().Position end end "
             "for _,p in workspace:GetDescendants() do if p:IsA('ProximityPrompt') and p.Enabled and p.Parent then local q=at(p.Parent) if q then "
             f"local d=(q-r.Position).Magnitude if d<={maxdist} and d<=p.MaxActivationDistance and (not bd or d<bd) then best,bd=p,d end end end end "
             "if best then best:InputHoldBegin() task.wait(best.HoldDuration+0.25) best:InputHoldEnd() return best.ActionText..' / '..best.ObjectText..string.format(' (%.1f)', bd) end return 'noprompt'")

def hud_press(word, name, fallback):
    """A real click on the bottom HUD button with the text word; if there is no button or the result did not happen - fallback() (Remote) with a mark."""
    a = action()
    which = None
    if a.split("|")[0].startswith(word): which = "Action"
    elif a.split("|")[1].startswith(word): which = "Action2"
    if which:
        press("HUD", which, name=name); return "click"
    finding(f"{name}: no '{word}' button in the HUD (visible: {a}) - fallback Remote")
    r = fallback(); ev(f"{name} (Remote)", r); return "remote"

def hatch_now(slot=1):
    return C(f"local r=game.ReplicatedStorage.Remotes.HatchReady:InvokeServer({slot}) return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def feed_all(): return C("local r=game.ReplicatedStorage.Remotes.Feed:InvokeServer('all') return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def mount(uid): return C(f"local r=game.ReplicatedStorage.Remotes.Mount:InvokeServer('{uid}') return tostring(r and r.ok)..'/'..tostring(r and r.reason)")
def dismount(): return C("local r=game.ReplicatedStorage.Remotes.Dismount:InvokeServer() return tostring(r and r.ok)")

def do_hatch(nth):
    """Walk to the bowl (on foot), press Hatch in the HUD; the name dialog (for the first two) closes by itself in 5 s (ssh clicks are not fast enough)."""
    walk("incubator (hatch)", nest_point(*INC_OFF), 40, 3.0, "go inc", closer=INC_RING)
    wait_until(lambda: action().split("|")[0].startswith("Hatch") or action().split("|")[1].startswith("Hatch"), 6, 0.5)
    before = len(dragons())
    how = hud_press("Hatch", f"Hatch #{nth} (HUD)", lambda: hatch_now(1))
    got = wait_until(lambda: len(dragons()) > before, 10, 0.5)
    if not got and how == "click":
        finding(f"Hatch #{nth}: the HUD button click did not hatch - fallback Remote"); ev("Hatch (Remote)", hatch_now(1))
        got = wait_until(lambda: len(dragons()) > before, 8, 0.5)
    ev(f"hatch #{nth}" if got else f"HATCH #{nth} DID NOT HAPPEN", state()[:200], frame=f"hatch{nth}")
    time.sleep(1.5); shot(f"{tag()}_hatch{nth}_scene")
    nd = wait_until(lambda: gui_on("NameDialog"), 8, 0.4)
    ev("name dialog opened" if nd else "no name dialog", f"hatch #{nth}", frame=("name" if nd else None))
    if nd:
        closed = wait_until(lambda: not gui_on("NameDialog"), 9, 0.5); ev("name dialog closed by itself" if closed else "name dialog did NOT close in 9 s")
    return got

INC_RING = '-'
INC_OFF = (0, 0, 0)   # offset of the 'at the bowl' point in the nest axes (computed after the start from the Incubator1 position)

# ================================================================================================ JOIN
seed = S("local s=game:GetService('ServerStorage'):FindFirstChild('StudioSeed') return tostring(s and s.Value~='' )")
ok("fresh profile: no StudioSeed in ServerStorage", seed != "true", f"StudioSeed={seed}")
stop()
s.call("start_stop_play", {"studio_id": sid, "is_start": True})
t_play = time.time()
# the first egg now goes into the bowl and hatches by itself (Config.Loop.firstEgg); this probe waits for the Hatch button - until it is rewritten for the new
# path it measures the old (manual) one; the new newcomer path - tests/p8/firstegg_check.py
S(LD + "return ld('firstegg off')")
loading_gone = None
for _ in range(180):
    if C("return tostring(game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') ~= nil)") == "false":
        loading_gone = time.time(); break
    time.sleep(0.5)
t0 = time.time()
P("the splash held the screen:", f"{(loading_gone or t0) - t_play:.1f} s after the game start (local file, P8)")
C(SAMPLER)
S("game.ReplicatedStorage.DayCycle:SetAttribute('ForcePhase','day') task.wait(0.3) return 'day'")
ev("splash gone (0:00)", f"viewport={C('return tostring(workspace.CurrentCamera.ViewportSize)')}", frame="spawn")
record(force=True)
# the 'at the bowl' point: like LoopDebug go inc - 3.3 studs toward the nest centre from Incubator1
INC_OFF = tuple(float(x) for x in S(NEST + "local i=n.Incubators.Incubator1 local l=n:GetPivot():PointToObjectSpace(i.Position) return string.format('%.2f,%.2f,%.2f', l.X, 0, l.Z-3.3)").split(","))
INC_RING = part_point("n:FindFirstChild('Incubators') and n.Incubators:FindFirstChild('Incubator1')")
P("Incubator1 in the nest axes (with the offset):", INC_OFF, "| ring:", INC_RING)
P("spawn:", pos(), "| to the table (XZ):", dist_to(part_point("n:FindFirstChild('EggTable')")))
sleep_rec(3)

# 0:03-0:10 egg from the table (walk on foot to the long side of the table; pickup without pressing, pickRadius 2.6 by XZ from the egg)
TABLE = part_point("n:FindFirstChild('EggTable')")
sideA, sideB = part_point("n:FindFirstChild('EggTable')", "0,0,2.3"), part_point("n:FindFirstChild('EggTable')", "0,0,-2.3")
side = sideA if dist_to(sideA) <= dist_to(sideB) else sideB
walk("egg table", side, 30, 2.5, None, closer=TABLE)
picked = wait_until(carrying, 6, 0.5)
if not picked:
    de = S(NEST + "local t=n:FindFirstChild('EggTable') local r=p.Character.HumanoidRootPart local out={} for k=1,3 do local e=t and t:FindFirstChild('TableEgg'..k) if e then local q=e:GetPivot().Position out[#out+1]=string.format('TableEgg%d:%.2f', k, (Vector3.new(q.X,0,q.Z)-Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude) end end return table.concat(out,' ')")
    finding(f"the table egg was not picked up standing at the table (just walking up): XZ distances to the eggs {de}, pickRadius 2.6 - a step right up to the table")
    step_to(TABLE, 3.0); picked = wait_until(carrying, 5, 0.5)
    if not picked:
        de = S(NEST + "local t=n:FindFirstChild('EggTable') local r=p.Character.HumanoidRootPart local out={} for k=1,3 do local e=t and t:FindFirstChild('TableEgg'..k) if e then local q=e:GetPivot().Position out[#out+1]=string.format('TableEgg%d:%.2f', k, (Vector3.new(q.X,0,q.Z)-Vector3.new(r.Position.X,0,r.Position.Z)).Magnitude) end end return table.concat(out,' ')")
        finding(f"the table egg was not picked up even point-blank: {de} - fallback teleport go table")
        S(LD + "ld('go table') return 'x'"); picked = wait_until(carrying, 6, 0.5)
ev("egg in the hands" if picked else "EGG NOT PICKED UP", state()[:160], frame="pick1")

# 0:10 egg into the bowl -> ready (the first egg ~3 s) -> Hatch with the HUD button
def place_egg(label):
    walk(label, nest_point(*INC_OFF), 40, 3.0, None, closer=INC_RING)
    placed = wait_until(lambda: not carrying(), 6, 0.5)
    if not placed:
        finding(f"{label}: the egg did not go into the bowl, to the ring {dist_to(INC_RING):.1f} XZ (placeRadius 3.8) - a step right up to the ring")
        step_to(INC_RING, 3.0); placed = wait_until(lambda: not carrying(), 5, 0.5)
        if not placed:
            finding(f"{label}: the egg did not go in even point-blank (to the ring {dist_to(INC_RING):.1f}) - fallback teleport go inc")
            S(LD + "ld('go inc') return 'x'"); placed = wait_until(lambda: not carrying(), 6, 0.5)
    return placed
placed = place_egg("incubator"); ev("egg in the bowl" if placed else "EGG NOT IN THE BOWL", state()[:160], frame="place1")
ready = wait_until(lambda: (lambda r: r is not None and r <= 0)(inc1()[1]), 40, 0.5); ev("ready to hatch" if ready else "NOT READY in 40 s", str(inc1()))
do_hatch(1)

# 0:18-0:30 coins: the pile at the nest (walk through it)
sleep_rec(4)
c0 = coins()
walk("coin pile", part_point("n:FindFirstChild('CoinPile')"), 30, 4.0, "go pile")
got = wait_until(lambda: coins() > c0, 8, 0.5); ev("coins collected" if got else "COINS NOT COLLECTED", state()[:160], frame="coins")
sleep_rec(5)
ev("quest", quest_text()); ev("step banner", banner_text())

# 0:30-1:00 off the ledge into the updraft (baby on the shoulder): on foot to the edge, a step forward (Humanoid:Move 3.2 s like a joystick)
ledge_pt = nest_point(0, 0, 44)
walk("nest ledge", ledge_pt, 30, 3.0, ledge_pt)
fwd = S(NEST + "local z=n:GetPivot():VectorToWorldSpace(Vector3.new(0,0,1)) return string.format('%.3f,0,%.3f', z.X, z.Z)")
S(NEST + "local ch=p.Character local r=ch.HumanoidRootPart local f=(n:GetPivot()*CFrame.new(0,0,80)).Position ch:PivotTo(CFrame.lookAt(r.Position, Vector3.new(f.X, r.Position.Y, f.Z))) return 'face'")
C("local c=workspace.CurrentCamera local r=game.Players.LocalPlayer.Character.HumanoidRootPart c.CFrame=CFrame.lookAt(r.Position-r.CFrame.LookVector*12+Vector3.new(0,5,0), r.Position+r.CFrame.LookVector*20) return 'cam'")
shot(f"{tag()}_ledge")
C("local me=game.Players.LocalPlayer local h=me.Character:FindFirstChildOfClass('Humanoid') local t0=os.clock() local c c=game:GetService('RunService').RenderStepped:Connect(function() "
  f"if os.clock()-t0<3.2 then h:Move(Vector3.new({fwd}).Unit,false) else h:Move(Vector3.zero,false) c:Disconnect() end end) return 'move'")
ev("step off the ledge")
gl = wait_until(lambda: attr("Gliding") == "true", 8, 0.3); ev("gliding" if gl else "NO GLIDING", pos(), frame="glide")
landed = wait_until(lambda: attr("Gliding") != "true", 30, 0.5); ev("landed" if landed else "gliding longer than 30 s", pos(), frame="landed")

# 1:00-1:40 egg on the meadow (on foot to the nearest, the prompt like a phone button) -> on foot back to the bowl (stairs)
egg_pt = S("local p=game.Players:GetPlayers()[1] local r=p.Character.HumanoidRootPart local best,bd for _,e in workspace:GetDescendants() do if e:IsA('Model') and e.Name=='Egg' and e.Parent and e.Parent:GetAttribute('Zone')=='Meadow' and not e.Parent:GetAttribute('Secret') then "
            "local d=(e:GetPivot().Position-r.Position).Magnitude if not bd or d<bd then best,bd=e,d end end end if not best then return '-' end local q=best:GetPivot().Position return string.format('%.2f,%.2f,%.2f|%.0f', q.X, q.Y, q.Z, bd)")
ev("nearest meadow egg", egg_pt)
egg_xyz = egg_pt.split("|")[0]
walk("egg on the meadow", egg_xyz, 60, 6.0, egg_xyz)
pr = hold_nearest_prompt(); ev("prompt at the egg", pr)
got2 = wait_until(carrying, 6, 0.5)
if not got2 and pr == "noprompt":
    pr = hold_nearest_prompt(20); ev("prompt at the egg (repeat, radius 20)", pr); got2 = wait_until(carrying, 6, 0.5)
ev("second egg in the hands" if got2 else "SECOND EGG NOT PICKED UP", state()[:160], frame="pick2")
sleep_rec(2)
ev("step banner", banner_text())
placed2 = place_egg("back to the bowl up the stairs"); ev("second egg in the bowl" if placed2 else "SECOND EGG NOT IN THE BOWL", state()[:200], frame="place2")

# 1:30-2:00 the Keeper stall: berries (the Feed prompt at the stall)
sleep_rec(3)
ev("quest", quest_text()); ev("step banner", banner_text())
stall_pt = S("local st=workspace.World:FindFirstChild('Stall',true) if not st then return '-' end local q=(st.CFrame*CFrame.new(0,0,-6)).Position return string.format('%.2f,%.2f,%.2f', q.X, q.Y, q.Z)")
walk("Keeper stall", stall_pt, 90, 5.0, stall_pt)
ev("at the stall", f"coins={coins()} | {quest_text()} | {banner_text()}", frame="stall")
pr = C("local st=game:GetService('CollectionService'):GetTagged('Stall')[1] local p=st and st:FindFirstChild('StallFeed') if not p then return 'noprompt' end "
       "return string.format('enabled=%s dist=%.1f / %s / %s', tostring(p.Enabled), (st.Position-game.Players.LocalPlayer.Character.HumanoidRootPart.Position).Magnitude, p.ActionText, p.ObjectText)")
ev("stall prompt", pr)
r = hold_nearest_prompt(16); ev("pressed the prompt at the stall", r)
fed = wait_until(lambda: "/fed" in state(), 5, 0.5)
ev("fed at the stall" if fed else "DID NOT FEED AT THE STALL", state()[:200], frame="fed")
if not fed:
    finding(f"the berries at the stall did not work (prompt: {pr}; press: {r}; coins {coins()})")
last_feed = el() if fed else -999

# ================================================================================================ until 20:00 - the newcomer loop
S(NEST + "return 'x'")
rode = flew = False
gift_closed = False
hatch_n = 1
hatch_now_seen = None
chest_tried = False
notes = []
walk("to the nest (pile)", part_point("n:FindFirstChild('CoinPile')"), 90, 5.0, "go pile")
while el() < MINUTES * 60:
    record()
    ds = dragons()
    inc = inc1()
    # a ready egg - hatch it
    if inc[0] and inc[1] is not None and inc[1] <= 0:
        hatch_n += 1; do_hatch(hatch_n)
        walk("to the pile after the hatch", part_point("n:FindFirstChild('CoinPile')"), 40, 5.0, "go pile")
    # food: fed for 5 min; at the nest Feed All with the real button
    if el() - last_feed > 305 and any(st in ("0", "1") for _, _, _, st in ds):
        a = action()
        how = hud_press("Feed All", "Feed All", feed_all)
        okf = wait_until(lambda: state().count("/fed") >= 1, 5, 0.5)
        if not okf and how == "click":
            finding("Feed All: the HUD button click did not feed - fallback Remote"); ev("Feed All (Remote)", feed_all())
        ev("refeed", f"{a} -> {state()[:160]}", frame="feed"); last_feed = el()
    # a teen nearby - mount (the Ride button), ride, dismount
    if not rode and any(st == "1" for _, _, _, st in ds):
        uid = [u for u, _, _, st in ds if st == "1"][0]
        ev("teen", uid, frame="teen"); sleep_rec(4)
        ev("step banner", banner_text())
        hud_press("Ride", "Ride", lambda: mount(uid))
        m_ = wait_until(lambda: attr("Mounted") != "nil", 6, 0.5)
        if not m_:
            finding("Ride: the click did not mount - fallback Remote Mount"); ev("Ride (Remote)", mount(uid)); m_ = wait_until(lambda: attr("Mounted") != "nil", 5, 0.5)
        ev("riding" if m_ else "DID NOT MOUNT", f"Mounted={attr('Mounted')}", frame="ride")
        C("local me=game.Players.LocalPlayer local h=me.Character:FindFirstChildOfClass('Humanoid') local t0=os.clock() local c c=game:GetService('RunService').RenderStepped:Connect(function() "
          "if os.clock()-t0<4 then h:Move(workspace.CurrentCamera.CFrame.LookVector*Vector3.new(1,0,1),false) else h:Move(Vector3.zero,false) c:Disconnect() end end) return 'move'")
        sleep_rec(6); shot(f"{tag()}_riding")
        press("Movement", "Dismount", name="Dismount")
        dm = wait_until(lambda: attr("Mounted") == "nil", 5, 0.5)
        if not dm:
            finding("Dismount: the click did not dismount - fallback Remote"); ev("Dismount (Remote)", dismount())
        rode = True
        walk("to the pile after the ride", part_point("n:FindFirstChild('CoinPile')"), 60, 5.0, "go pile")
    # adult - mount (Fly), take off (hold jump), fly around, dismount
    if not flew and any(st == "2" for _, _, _, st in ds):
        uid = [u for u, _, _, st in ds if st == "2"][0]
        ev("adult", uid, frame="adult"); sleep_rec(4)
        ev("step banner", banner_text())
        hud_press("Fly", "Fly", lambda: mount(uid))
        m_ = wait_until(lambda: attr("Mounted") != "nil", 6, 0.5)
        if not m_:
            finding("Fly: the click did not mount - fallback Remote Mount"); ev("Fly (Remote)", mount(uid)); m_ = wait_until(lambda: attr("Mounted") != "nil", 5, 0.5)
        ev("riding the adult" if m_ else "DID NOT MOUNT THE ADULT", f"Mounted={attr('Mounted')} | {banner_text()}", frame="fly_mounted")
        keys("down space;wait 1500;up space;wait 300")
        fl = wait_until(lambda: attr("Flying") == "true", 4, 0.3)
        if not fl:
            finding("takeoff: holding jump (a key via ssh) did not lift - fallback ClientDebug fly up"); ev("takeoff (ClientDebug)", C(CD + "return tostring(cd('fly up on'))"))
            fl = wait_until(lambda: attr("Flying") == "true", 5, 0.3)
        ev("in the air" if fl else "DID NOT TAKE OFF", f"Flying={attr('Flying')} | {banner_text()}", frame="takeoff")
        sleep_rec(4); shot(f"{tag()}_flying"); ev("in flight", f"{pos()} | {banner_text()} | {quest_text()}")
        C(CD + "return tostring(cd('fly off'))"); sleep_rec(6)
        ev("banner after the flight", banner_text())
        press("Movement", "Dismount", name="Dismount (after the flight)")
        if not wait_until(lambda: attr("Mounted") == "nil", 6, 0.5):
            finding("Dismount after the flight: the click did not dismount - fallback Remote"); ev("Dismount (Remote)", dismount())
        flew = True
        walk("to the pile after the flight", part_point("n:FindFirstChild('CoinPile')"), 90, 5.0, "go pile")
    # the Free Gift card (02 §2 2:45-3:00): a frame, close with the cross after 10 s
    if not gift_closed and gui_on("FreeGiftCard"):
        ev("the Free Gift card appeared", C(TEXTS)[:300], frame="freegift"); sleep_rec(6)
        press("FreeGiftCard", "X", name="Free Gift cross")
        gift_closed = True; ev("the Free Gift card closed" if not gui_on("FreeGiftCard") else "the Free Gift card did NOT close with the cross")
        if gui_on("FreeGiftCard"): finding("the Free Gift card cross did not close it")
    # Hatch now at the incubator (02 §2 3:00): does the label appear in the WorldUI above the bowl
    if hatch_now_seen is None and el() >= 185 and inc[0]:
        hn = C("for _,g in game.Players.LocalPlayer.PlayerGui:GetChildren() do if g:IsA('BillboardGui') and g.Enabled then for _,o in g:GetDescendants() do if (o:IsA('TextLabel') or o:IsA('TextButton')) and o.Visible and o.ContentText:lower():find('hatch now') then return 'yes: '..o.ContentText end end end end return 'no'")
        if hn != "no" or el() > 240:
            hatch_now_seen = hn; ev("Hatch now at the incubator after 3:00", f"{hn} | inc1={inc}", frame="hatchnow")
    # the 5-minute gift chest (02 §2 5:00): walk up, press
    if not chest_tried and el() >= 305:
        chest_tried = True
        cp = S("local p=game.Players:GetPlayers()[1] for _,m in game:GetService('CollectionService'):GetTagged('GiftChest') do if m.Parent and m.Parent:GetAttribute('OwnerId')==p.UserId then local q=m:GetPivot().Position return string.format('%.2f,%.2f,%.2f', q.X, q.Y, q.Z) end end return '-'")  # the chest of the OWN nest (run 2 walked to someone else's 134 m away)
        ev("gift chest", f"{cp} | {C(TEXTS)[:200]}", frame="chest")
        if cp != "-":
            c1 = coins(); walk("gift chest", cp, 40, 4.0, None)
            r = hold_nearest_prompt(10); ev("prompt at the chest", r); sleep_rec(3)
            ev("after the chest", f"coins {c1} -> {coins()} | {C(TEXTS)[:200]}", frame="chest_after")
    time.sleep(1.5)
record(force=True)
shot("M%02d" % MINUTES) if next_min <= MINUTES else None
ev("20 minutes are up", f"{state()[:200]} | {quest_text()} | {banner_text()}", frame="end")

# ================================================================================================ result: the funnel from the profile
d = dump()
ob = ((d.get("analytics") or {}).get("onboard") or {})
join = min(ob.values()) if ob else None
NAMES = {1: "spawn", 2: "egg_first_pick", 3: "hatch_first", 4: "coins_first_collect", 5: "glide_first", 6: "egg_second", 7: "feed_first",
         8: "juvenile_first", 9: "ride_first", 10: "hatch_second", 11: "adult_first", 12: "fly_first", 13: "ascension_first"}
TZ = {2: "0:03-0:10", 3: "0:10-0:13", 4: "0:18-0:30", 5: "0:50-1:00", 6: "1:00-1:40", 7: "1:45-2:00", 8: "2:00-2:30", 9: "2:30-2:45",
      10: "3:30-4:30", 11: "5:00-7:30", 12: "7:30-8:00", 13: "10:00-20:00"}
SIM = {3: "0:14", 7: "0:25*", 8: "2:20", 11: "7:20"}   # sim_first10 (Common first): * the bot feeds right after the reward, the player - at the stall ~1:45
GATE = {3: 20, 5: 60, 6: 120, 8: 180, 11: 480}
steps = {int(k): v - join for k, v in ob.items()} if join is not None else {}
P("funnel steps (s from join):", json.dumps({NAMES[k]: steps[k] for k in sorted(steps)}, ensure_ascii=False))
rows = []
for k in sorted(NAMES):
    if k == 1: continue
    sec = steps.get(k); gate = GATE.get(k)
    shown_ = ("%d:%02d" % (sec // 60, sec % 60)) if sec is not None else "none"
    rows.append((NAMES[k], shown_, TZ.get(k, "-"), SIM.get(k, "-"), gate))
    det = f"{NAMES[k]}: {shown_} (spec {TZ.get(k, '-')}, sim {SIM.get(k, '-')}{', gate <= %d s' % gate if gate else ''})"
    if gate:
        ok(f"gate: {NAMES[k]} <= {gate} s", sec is not None and sec <= gate, det)
    else:
        P("step", det)
ok("walked everywhere on foot (no teleports)", not any("teleport" in f for _, f in findings), "; ".join(f for _, f in findings if "teleport" in f)[:300])
ok("all buttons worked with a real click (no Remote needed)", not any("Remote" in f for _, f in findings), "; ".join(f for _, f in findings if "Remote" in f)[:300])
json.dump({"events": events, "onboard": steps, "findings": findings, "quests": d.get("quests"), "onboarding": d.get("onboarding")},
          open(f"{OUT}/events.json", "w"), ensure_ascii=False, indent=0)
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
open(f"{OUT}/console.txt", "w").write(ctext)
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("console without game errors", not errs, " ;; ".join(errs[:5]))
drain()
stop()
bad = write_result(f"Full newcomer pass {MINUTES} minutes (real time, on foot, real clicks)")
with open(f"{OUT}/result.md", "a") as f:
    f.write("\n## Funnel steps against spec 02 §2 and sim_first10\n\n| step | actual | spec 02 | sim_first10 | gate |\n|---|---|---|---|---|\n")
    for n, sh, tz, sm, g in rows:
        f.write(f"| {n} | {sh} | {tz} | {sm} | {('<= %d s' % g) if g else '-'} |\n")
    f.write("\n## Discrepancies found along the way (stand and game)\n\n")
    for t, txt in findings:
        f.write(f"- [{int(t) // 60}:{int(t) % 60:02d}] {txt}\n")
    if not findings: f.write("- none\n")
s.close()
