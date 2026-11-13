"""Tests/p8: the shared module of the probes in Roblox Studio on the P8 machine (MCP Studio + real mouse clicks via ssh).

Before (15-18.10) each probe pulled these functions in via exec() of someone else's file from runs/; here they are gathered in one place.
Usage in a probe:

    import p8lib
    p8lib.begin("hatch_check")          # MCP session, waiting for Studio, output folder
    from p8lib import *                 # s, sid, OUT, P, ok, C, S, run, shot, desk, press, ... (after begin!)

Studio with the local file is already open: tools/p8/open_local.sh (window 834x630 = phone 812x375 pt).
Output: $P8_OUT_ROOT/roblox_build_<UTC date>/<probe name>/ (log <name>.log, frames, console, result.md).
begin() finds the viewport origin on the P8 screen by itself (calibrate); P8_VX/P8_VY in p8.env - set manually and do not calibrate.
"""
import base64, json, os, re, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.path.normpath(os.path.join(HERE, "..", "..", "tools", "p8"))
sys.path.insert(0, TOOLS)
from mcp_session import Session, ENV  # noqa: E402

VX, VY, INSET = int(ENV.get("P8_VX", 3)), int(ENV.get("P8_VY", 144)), 58  # viewport origin on the P8 screen, the Roblox bar
SWEEP = open(os.path.join(HERE, "sweep.luau"), encoding="utf-8").read()
s = sid = OUT = log = None
res = []


def begin(name, out=None):
    """MCP session and output folder. Do not call again."""
    global s, sid, OUT, log
    name = name + os.environ.get("P8_TAG", "")  # P8_TAG=_retention - a folder next to it, earlier measurements of the same day stay intact
    OUT = out or os.path.join(ENV.get("P8_OUT_ROOT", os.path.join(HERE, "out")),
                              "roblox_build_" + time.strftime("%Y-%m-%d", time.gmtime()), name)
    os.makedirs(OUT, exist_ok=True)
    log = open(os.path.join(OUT, f"{name}.log"), "w")
    s = Session()
    s.request("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": name, "version": "1"}})
    s.send({"jsonrpc": "2.0", "method": "notifications/initialized"})
    for _ in range(60):
        t = s.call("list_roblox_studios", {})["result"]["content"][0]["text"]
        if '"studios":[]' not in t.replace(" ", ""):
            sid = json.loads(t)["studios"][0]["id"]; break
        time.sleep(4)
    assert sid, "Studio did not connect"
    P("output:", OUT)
    if "P8_VX" not in ENV:
        calibrate()


def calibrate(tag="_calib"):
    """The viewport origin on the P8 screen (18.10: the layout depends on the winsize/F11 order - 11,176 or 3,144, a miss = false FAILs).
    The Studio snapshot (MCP, exactly the 812x375 viewport) is searched for by trying offsets inside the real 834x630 screen frame."""
    global VX, VY
    try:
        import numpy as np
        from PIL import Image
        shot(tag); desk(tag)
        a = np.asarray(Image.open(f"{OUT}/{tag}.jpg").convert("L"), dtype=np.float32)
        b = np.asarray(Image.open(f"{OUT}/{tag}.png").convert("L"), dtype=np.float32)
        h, w = a.shape
        best = (1e9, VX, VY)
        for y in range(0, b.shape[0] - h + 1):
            for x in range(0, b.shape[1] - w + 1):
                d = float(np.abs(b[y:y + h:4, x:x + w:4] - a[::4, ::4]).mean())
                if d < best[0]: best = (d, x, y)
        if best[0] < 25:   # mean brightness difference 0-255; the right spot ~5-15 (the frames are taken a few seconds apart)
            VX, VY = best[1], best[2]
        P(f"viewport on the screen: {VX},{VY} (difference {best[0]:.1f}; found {best[1]},{best[2]})")
    except Exception as e:  # calibration is optional: P8_VX/P8_VY or 3,144 remain
        P("viewport calibration failed:", repr(e)[:200], "- using", VX, VY)


def P(*a):
    t = " ".join(str(x) for x in a); print(t, flush=True); log.write(t + "\n"); log.flush()


def sh(cmd, t=180):
    """A bash command with the P8 functions (p8_ssh, p8_ip, P8_SSH_OPTS, p8_scp_to/p8_scp_from)."""
    return subprocess.run(f'source "{TOOLS}/common.sh"; ' + cmd, shell=True, executable="/bin/bash",
                          capture_output=True, text=True, timeout=t)


def tool(script, *args, t=90):
    return subprocess.run(["bash", os.path.join(TOOLS, script), *[str(a) for a in args]], capture_output=True, text=True, timeout=t)


def run(code, dm="Client", timeout=120):
    r = s.call("execute_luau", {"studio_id": sid, "datamodel_type": dm, "code": code}, timeout)
    return ((r.get("result") or {}).get("content") or [{}])[0].get("text", "")
def C(code): return run(code, "Client")
def S(code): return run(code, "Server")
def shot(name):
    r = s.call("screen_capture", {"studio_id": sid, "capture_id": name}, 120)
    for part in (r.get("result") or {}).get("content", []):
        if part.get("type") == "image":
            open(f"{OUT}/{name}.jpg", "wb").write(base64.b64decode(part["data"]))
def desk(name):   # a real frame of the P8 screen (ffmpeg), not a Studio snapshot
    tool("deskshot.sh", f"{OUT}/{name}.png")
def key(k):       # a single press (esc, enter...)
    tool("key.sh", k)
def keys(seq, t=120):  # "down space;wait 1500;up space"
    return tool("keys.sh", seq, t=t).stdout
def click_xy(x, y):
    r = tool("click.sh", int(x), int(y))
    out = (r.stdout + r.stderr).strip()
    if f"click {int(x)} {int(y)}" not in out:  # the click did not reach P8 (ssh, the machine shut down) - that is a test failure, not a game one
        raise SystemExit(f"CLICK DID NOT ARRIVE ({x},{y}): {out[-160:]}")
    return out[-80:]
def ok(name, cond, detail=""):
    res.append((name, bool(cond), detail)); P(("OK  " if cond else "FAIL"), name, "|", detail[:300])

FIND = r"""
local pg=game.Players.LocalPlayer.PlayerGui
local function shown(o) local p=o while p and p~=pg do if p:IsA('GuiObject') and not p.Visible then return false end if p:IsA('LayerCollector') and not p.Enabled then return false end p=p.Parent end return true end
local function find(gname, key, inside)
  local g=pg:FindFirstChild(gname) if not g then return nil end
  local root = inside and g:FindFirstChild(inside, true) or g
  if not root then return nil end
  for _,o in root:GetDescendants() do
    if o:IsA('GuiButton') and shown(o) and o.AbsoluteSize.X>0 then
      local w=o:FindFirstChild('Word')
      if o.Name==key or (o:IsA('TextButton') and o.ContentText==key) or (w and w:IsA('TextLabel') and w.ContentText==key) then return o end
    end
  end
end
"""
def press(gname, key_, inside=None, name=None):
    ins = f"'{inside}'" if inside else "nil"
    t = C(FIND + f"local o=find('{gname}', [[{key_}]], {ins}) if not o then return 'none' end local p=o.AbsolutePosition local z=o.AbsoluteSize return string.format('%d,%d', p.X+z.X/2, p.Y+z.Y/2)")
    m = re.match(r"(-?\d+),(-?\d+)", t)
    if not m:
        ok(name or f"press {gname}/{key_}", False, f"button not found ({t[:80]})"); return False
    x, y = int(m.group(1)), int(m.group(2))
    click_xy(VX + x, VY + INSET + y); time.sleep(1.2)
    return True
CD = "local pg=game.Players.LocalPlayer.PlayerGui local function cd(c) return pg.ClientDebug:Invoke(c) end "
LD = "local function ld(c) return game.ServerStorage.LoopDebug:Invoke(c) end "
def has(gname, text):   # a visible label/button with the text
    return C(FIND + f"local g=pg:FindFirstChild('{gname}') if not g then return 'nogui' end for _,o in g:GetDescendants() do if (o:IsA('TextLabel') or o:IsA('TextButton')) and shown(o) and o.ContentText:find([[{text}]],1,true) then return 'yes' end end return 'no'") == "yes"
def gui_on(gname):
    return C(f"local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('{gname}') return tostring(g~=nil and g.Enabled)") == "true"
def state(): return S(LD + "return ld('state')")
def data(expr):  # player data on the client (Store) - there is no ClientDebug for it - we read attributes/the server
    return S(expr)

# ------------------------------------------------- acceptance helpers (reward_check, aurora, hatch, sound)
def stop(): s.call("start_stop_play", {"studio_id": sid, "is_start": False}); time.sleep(3)
def start():
    s.call("start_stop_play", {"studio_id": sid, "is_start": True})
    t0 = time.time()
    while time.time() - t0 < 70:
        if C("return tostring(game.Players.LocalPlayer.PlayerGui:FindFirstChild('LoadingScreen') ~= nil)") == "false": break
        time.sleep(0.8)
    time.sleep(4)
def rw(arg=""): return S(LD + f"return ld('reward {arg}')")
def dump():
    d = json.loads(S(LD + "return ld('dump')"))
    for k in ("dragons",):  # an empty Luau table in JSON - []
        if isinstance(d.get(k), list): d[k] = {}
    return d
def claim(kind, id_=None):
    time.sleep(0.6)  # RateLimit Claim = 2/s
    a = f"'{kind}'" + (f", '{id_}'" if id_ else "")
    return C(f"local r=game.ReplicatedStorage.Remotes.Claim:InvokeServer({a}) return tostring(r.ok)..'/'..tostring(r.reason)")
def pill(): return C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Topbar') local b=g and g:FindFirstChild('Top_Gifts',true) if not b then return 'nopill' end "
                     "return b.Timer.ContentText..' | badge='..(b.Badge.Visible and b.Badge.ContentText or '-')..' | w='..b.AbsoluteSize.X..' h='..b.AbsoluteSize.Y")
def sweep(name):
    r = run(SWEEP, "Client", 600); P(name, "SWEEP:", r[:600]); shot(name); return r

DAILY = {"eggs3": ("eggFound", 3), "feed3": ("feed", 3), "visit2": ("visit", 2), "play10": ("playSec", 600), "hatch2": ("hatch", 2),
         "fly2": ("flySec", 120), "cliffsEgg": ("eggInc_Cliffs", 1), "grow1": ("grow", 1), "rings5": ("ring", 5),
         "hatchRare": ("hatchRare", 1), "summitEgg": ("eggInc_Summit", 1), "party1": ("party", 1), "shards6": ("shard", 6)}


def write_result(title=None):
    """The results table in OUT/result.md; returns the FAIL count."""
    with open(f"{OUT}/result.md", "w") as f:
        if title: f.write(f"# {title}\n\n")
        f.write("| check | result | details |\n|---|---|---|\n")
        for n, o, d in res:
            f.write(f"| {n} | {'OK' if o else 'FAIL'} | {d[:160].replace('|', '/')} |\n")
    bad = sum(1 for _, o, _ in res if not o)
    P(f"RESULT: {len(res) - bad}/{len(res)} OK, FAIL {bad}; {OUT}/result.md")
    return bad
