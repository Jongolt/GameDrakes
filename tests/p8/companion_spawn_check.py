#!/usr/bin/env python3
"""A returning player with an elder appears on the plaza
facing Old Ash, and the companion stands on the Top Nests board (the ray to the ground hit the board), Fly stalls for several seconds. A probe on P8
(after open_local.sh): a profile with an elder companion via StudioSeed (like a returning player's), the entry ->
  1) the companion appeared, its extents do not intersect visible/solid world parts, the extents bottom at the player's feet (not on a sign) -
     at once and after 5 s,
     and does not crawl away within 5 s (20.10: the leash measured the body while the constraint drove the center of mass - the elder crawled away ~9 studs by itself),
  2) a real click on HUD Fly -> riding, holding Up -> a rise of 6 studs in reasonable time (without stalling),
  3) the same at the second entry (repeatability) and with an adult companion (stage 2).
The argument: elder (default) | adult | both. The frames S*_spawn.jpg, F*_air.jpg."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("companion_spawn_check")
from p8lib import *  # noqa: F401,F403

WHICH = (sys.argv[1] if len(sys.argv) > 1 else "elder").lower()
STAGES = {"elder": [3], "adult": [2], "both": [3, 2]}.get(WHICH, [3])


def edit(code): return run(code, "Edit")


def seed_set(js):
    assert "]=====]" not in js
    return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")


def seed_clear(): return edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")


# the player's companion: the extents, the intersections with world parts (the real shape - GetPartsInPart with a temporary block; by the described boxes
# the tilted plaza slabs and the terrace body give false intersections), the height of the extents bottom above the player's feet
PROBE = r"""
local Players=game:GetService('Players') local p=Players:GetPlayers()[1] if not p then return 'noplayer' end
local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==p.UserId then m=x end end
if not m or not m.PrimaryPart then return 'nocomp' end
local ch=p.Character local r=ch and ch:FindFirstChild('HumanoidRootPart') local hum=ch and ch:FindFirstChildOfClass('Humanoid')
if not r then return 'nochar' end
local cf,size=m:GetBoundingBox()
local op=OverlapParams.new() op.FilterType=Enum.RaycastFilterType.Exclude op.FilterDescendantsInstances={m,ch,workspace.Terrain}
local b=Instance.new('Part') b.Anchored=true b.CanCollide=false b.CanQuery=false b.CanTouch=false b.Transparency=1
b.Size=Vector3.new(size.X*0.85,math.max(1,size.Y-1.5),size.Z*0.85) b.CFrame=cf+Vector3.new(0,0.75,0) b.Parent=workspace
local hits={} for _,q in workspace:GetPartsInPart(b, op) do
  if q.CanCollide or (q.Transparency<0.95 and q.Size.Y>=1.5) then
    local top=q:FindFirstAncestorWhichIsA('Model') hits[#hits+1]=(top and top.Name..'/' or '')..q.Name..(q.CanCollide and '*' or '') end end
b:Destroy()
local bottom=cf.Position.Y-size.Y/2
local foot=r.Position.Y-r.Size.Y/2-(hum and hum.HipHeight or 2)
local rp=RaycastParams.new() rp.FilterType=Enum.RaycastFilterType.Exclude rp.FilterDescendantsInstances={m,ch} rp.RespectCanCollide=true
local gh=workspace:Raycast(cf.Position, Vector3.new(0,-(size.Y/2+40),0), rp)
local aboveGround=gh and math.floor((bottom-gh.Position.Y)*100)/100 or 99
-- the support: the highest ground under the body (the center and 4 points at +-0.35 of the size along X/Z, like the leash target Controllers/Companion) - the plaza slabs
-- lie at different heights (up to ~0.45), the paws stand on the upper one
local gmax=gh and gh.Position.Y or nil
for _,o in {{1,0},{-1,0},{0,1},{0,-1}} do
  local off=cf.Rotation*Vector3.new(o[1]*size.X*0.35,0,o[2]*size.Z*0.35)
  local h=workspace:Raycast(cf.Position+off, Vector3.new(0,-(size.Y/2+40),0), rp)
  if h and (gmax==nil or h.Position.Y>gmax) then gmax=h.Position.Y end
end
local aboveSupport=gmax and math.floor((bottom-gmax)*100)/100 or 99
local out={stage=m:GetAttribute('Stage'), pos={math.floor(cf.Position.X*10)/10,math.floor(cf.Position.Y*10)/10,math.floor(cf.Position.Z*10)/10},
  size={math.floor(size.X),math.floor(size.Y),math.floor(size.Z)}, root={math.floor(r.Position.X),math.floor(r.Position.Y),math.floor(r.Position.Z)},
  dist=math.floor(Vector2.new(cf.Position.X-r.Position.X,cf.Position.Z-r.Position.Z).Magnitude*10)/10,
  aboveFeet=math.floor((bottom-foot)*10)/10, aboveGround=aboveGround, aboveSupport=aboveSupport, groundHit=gh and gh.Instance.Name or 'none',
  vel=math.floor(m.PrimaryPart.AssemblyLinearVelocity.Magnitude*100)/100, hits=hits}
return game:GetService('HttpService'):JSONEncode(out)
"""
BODY_Y = "local p=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==p.UserId then m=x end end return m and m.PrimaryPart and string.format('%.2f', m.PrimaryPart.Position.Y) or 'nocomp'"


def wait_companion(t=40):
    t0 = time.time()
    while time.time() - t0 < t:
        r = S(PROBE)
        if r.startswith("{"):
            return json.loads(r), time.time() - t0
        time.sleep(0.5)
    return None, time.time() - t0


def make_profile(stage):
    """A fresh profile: coins, an egg, the hatch, a companion of stage stage (setcomp moss<stage>); the taken profile - for StudioSeed."""
    seed_clear(); stop(); start()
    S(LD + "return ld('give 1000000')")
    S(LD + "return ld('give egg Meadow Common')"); time.sleep(0.6)
    S(LD + "return ld('go inc')"); time.sleep(2)
    S(LD + "return ld('time 9999999')"); time.sleep(3)
    P("hatch:", S(LD + "local r=ld('hatch 1') return typeof(r)=='table' and tostring(r.ok)..'/'..tostring(r.reason) or tostring(r)")[:80])
    time.sleep(8)
    P("setcomp:", S(LD + f"local r=ld('setcomp moss{stage}') return tostring(r.ok)..'/'..tostring(r.reason)")); time.sleep(4)
    d = dump()
    comp = d.get("companion")
    P("the profile: companion", comp, "stage", (d.get("dragons", {}).get(comp) or {}).get("stage"))
    stop()
    return d


def check_spot(tag, st, when):
    ok(f"[{tag}] {when}: the companion's extents do not intersect solid/visible world parts (the board, the posts, the torches)", not st["hits"], ", ".join(st["hits"][:8]))
    # the extents bottom above the ground
    # UNDER the dragon (a ray down from the center, without the model and the character) <= 0.6 and not below the ground by 0.3
    # the run 18:45 on the build with the fix: under the center 0.22-0.65 - the plaza slabs at different heights, the paws on the upper one; we measure the support (max of 5 rays)
    ok(f"[{tag}] {when}: the companion STANDS ON THE GROUND - the extents bottom above the support under it <= 0.6 stud (does not hang)", -0.3 <= st["aboveSupport"] <= 0.6, f"above the support {st['aboveSupport']}, under the center {st['aboveGround']} ({st['groundHit']}), above the feet {st['aboveFeet']}, pos {st['pos']}")


def shot_ground(tag, name):
    """A frame: the camera from the ground at the player's feet, looking at the dragon's bottom (whether it stands on the ground)."""
    C("local me=game.Players.LocalPlayer local m for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==me.UserId then m=x end end "
      "if not m then return 'nocomp' end local cf,size=m:GetBoundingBox() local r=me.Character.HumanoidRootPart local hum=me.Character:FindFirstChildOfClass('Humanoid') "
      "local foot=r.Position.Y-r.Size.Y/2-(hum and hum.HipHeight or 2) local flat=Vector3.new(r.Position.X-cf.Position.X,0,r.Position.Z-cf.Position.Z) "
      "local dir=flat.Magnitude>0.5 and flat.Unit or Vector3.new(0,0,1) local d=math.max(size.X,size.Z)*0.9+14 "
      "local cam=workspace.CurrentCamera cam.CameraType=Enum.CameraType.Scriptable cam.CFrame=CFrame.lookAt(cf.Position+dir*d+Vector3.new(0,foot-cf.Position.Y+3,0), Vector3.new(cf.Position.X, cf.Position.Y-size.Y/2+size.Y*0.25, cf.Position.Z)) return 'ok'")
    time.sleep(0.8); shot(name)
    C("workspace.CurrentCamera.CameraType=Enum.CameraType.Custom return 'ok'"); time.sleep(0.5)


def entry(tag, stage):
    start()
    st, waited = wait_companion()
    shot(f"S{tag}_spawn")
    P(f"[{tag}] the companion after {waited:.1f} s:", json.dumps(st, ensure_ascii=False))
    if not st:
        ok(f"[{tag}] the companion of stage {stage} appeared at the entry", False, "no model in 40 s"); stop(); return
    ok(f"[{tag}] the companion of stage {stage} appeared at the entry", st.get("stage") == stage, f"stage={st.get('stage')} after {waited:.1f} s, {st['dist']} studs away")
    check_spot(tag, st, "at once")
    time.sleep(5)
    st5, _ = wait_companion(5)
    P(f"[{tag}] after 5 s:", json.dumps(st5, ensure_ascii=False))
    if st5:
        check_spot(tag, st5, "after 5 s")
        moved = sum((a - b) ** 2 for a, b in zip(st5["pos"], st["pos"])) ** 0.5
        ok(f"[{tag}] the companion stays at the construction spot (over 5 s the shift < 2 studs, does not crawl away from the player)", moved < 2.0, f"the shift {moved:.1f}: {st['dist']} -> {st5['dist']} studs from the player")
        ok(f"[{tag}] does not shake at rest (the body speed < 0.3 studs/s)", st5["vel"] < 0.3, f"v={st5['vel']}")
        shot_ground(tag, f"G{tag}_ground")
    # Fly: a real click on the HUD button (a click via ssh on this rig 25-40 s), we wait for the mount after the click, then hold Up
    pressed = press("HUD", "Fly", name=f"[{tag}] the Fly button in the HUD")
    t0 = time.time(); mounted = ""
    while pressed and time.time() - t0 < 15:
        mounted = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))")
        if mounted not in ("nil", ""):
            break
        time.sleep(0.4)
    if mounted in ("nil", ""):  # the click via ssh on this rig can get lost - the fallback move by the same Remote as the button
        desk(f"D{tag}_after_click")
        uid = C("local p=game.Players.LocalPlayer for _,x in game:GetService('CollectionService'):GetTagged('Companion') do if x:GetAttribute('OwnerId')==p.UserId then return tostring(x:GetAttribute('Uid')) end end return ''")
        r = C(f"local r=game.ReplicatedStorage.Remotes.Mount:InvokeServer('{uid}') return game:GetService('HttpService'):JSONEncode(r)")
        mounted = C("return tostring(game.Players.LocalPlayer:GetAttribute('Mounted'))")
        P(f"[{tag}] the click did not mount - the fallback move Remote Mount:", r, "Mounted", mounted)
        ok(f"[{tag}] the mount (the fallback move Remote Mount, like the Fly button)", mounted not in ("nil", ""), f"{r}")
    else:
        ok(f"[{tag}] Fly (a real click) -> riding", True, f"Mounted={mounted!r}, after the click {time.time() - t0:.1f} s")
    if mounted in ("nil", ""):
        stop(); return
    yb = C(BODY_Y)
    y0 = float(yb) if re.match(r"^-?\d", yb) else None
    C(CD + "return tostring(cd('fly up on'))")
    t1 = time.time(); rise = None; ys = []
    while time.time() - t1 < 12 and y0 is not None:
        y = C(BODY_Y)
        if re.match(r"^-?\d", y):
            ys.append((round(time.time() - t1, 1), round(float(y) - y0, 1)))
            if float(y) - y0 >= 6:
                rise = time.time() - t1; break
        time.sleep(0.3)
    C(CD + "return tostring(cd('fly up off'))")
    shot(f"F{tag}_air")
    P(f"[{tag}] the rise (s, studs):", ys)
    ok(f"[{tag}] holding Up: a rise of 6 studs in <= 4 s (without stalling)", rise is not None and rise <= 4.0, f"{'no rise in 12 s' if rise is None else f'{rise:.1f} s'}; the series {ys[:14]}")
    C(CD + "return tostring(cd('fly off'))"); time.sleep(2)
    stop()


for stg in STAGES:
    d = make_profile(stg)
    js = json.dumps(d, ensure_ascii=False)
    open(os.path.join(OUT, f"seed_stage{stg}.json"), "w").write(js)
    P("seed:", seed_set(js))
    entry(f"{stg}a", stg)
    entry(f"{stg}b", stg)

seed_clear()
cons = s.call("get_console_output", {"studio_id": sid}, 120)
ctext = ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "")
errs = [l for l in ctext.splitlines() if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l and "TexturePack" not in l and "errors 0" not in l]
ok("the console without game errors", not errs, " ;; ".join(errs[:4]))
write_result(f"The companion at the entry of a returning player ({WHICH}, 20.10)")
s.close()
