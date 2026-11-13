#!/usr/bin/env python3
"""The Roblox 'favorite' prompt once per account lifetime after the first flight. P8, LOCAL file
(after tools/p8/open_local.sh). Studio has no Roblox prompt (DevForum 2717433) - we check the mechanism: fav_prompt goes to the server,
the server sets onboarding.favAsked.
  1) entering the game - no mark (no prompt on entry);
  2) mounted and dismounted before the first flight - no mark;
  3) first flight, landing, after Config.FavPrompt.delay - the mark is set;
  4) mounted and dismounted again - the mark is unchanged (once per lifetime);
  5) console without game errors.
Run: python3 tests/p8/fav_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/fav_check/ (result.md)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("fav_check")
from p8lib import *  # noqa: F401,F403

SEED = os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_event_covers_2026-10-21", "seed_pearl.json")  # Tide elder as the companion, tutorial done


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def fav(): return (dump().get("onboarding") or {}).get("favAsked")
def flew(): return (dump().get("onboarding") or {}).get("flew")
def console_lines():
    cons = s.call("get_console_output", {"studio_id": sid}, 120)
    return ((cons.get("result") or {}).get("content") or [{}])[0].get("text", "").splitlines()
def game_errors(lines):
    return [l for l in lines if re.search(r"Stack Begin|attempt to|error", l, re.I) and "not authorized" not in l and "ExecuteLuau" not in l
            and "TexturePack" not in l and "errors 0" not in l and "RSVP" not in l]
def wait_world():
    for _ in range(40):
        if S("local w=workspace:FindFirstChild('World') return tostring(w and w:GetAttribute('DecorModels'))") != "nil":
            break
        time.sleep(3)
    time.sleep(3)
def up(on):
    C("local g=game.Players.LocalPlayer.PlayerGui:FindFirstChild('Movement') if g then g:SetAttribute('Up'," + ("true" if on else "false") + ") end return 'ok'")


prof = json.load(open(SEED))
prof["lastSeen"] = int(time.time())
ob = prof.setdefault("onboarding", {})
ob["flew"] = False
ob.pop("favAsked", None)
js = json.dumps(prof, ensure_ascii=False)
assert "]=====]" not in js
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")
start(); wait_world()
delay = float(S("return tostring(require(game.ReplicatedStorage.Shared.Config).FavPrompt.delay)"))
P("delay:", delay)
time.sleep(12)
ok("1. entering the game - no mark", fav() is None, str(fav()))

P("mount:", ld("mount")[:60]); time.sleep(2)
P("dismount:", ld("dismount")[:60]); time.sleep(delay + 3)
ok("2. mounted and dismounted before flying - no mark", fav() is None and not flew(), f"fav={fav()} flew={flew()}")

P("mount:", ld("mount")[:60]); time.sleep(2)
up(True); time.sleep(2.5); up(False)
pos = S("local p=game.Players:GetPlayers()[1] local r=p.Character and p.Character:FindFirstChild('HumanoidRootPart') return r and string.format('%d,%d,%d', r.Position.X, r.Position.Y, r.Position.Z) or '-'")
x, y, z = [int(v) for v in pos.split(",")]
P("warp:", ld(f"warp {x}x{y + 40}x{z}".replace("-", "n"))[:80]); time.sleep(3)
ok("3a. the first flight counted (onboarding.flew)", flew() is True, str(flew()))
mid = fav()
P("warp down:", ld(f"warp {x}x{y + 2}x{z}".replace("-", "n"))[:80]); time.sleep(2)
P("dismount:", ld("dismount")[:60]); time.sleep(delay + 4)
f1 = fav()
ok("3b. no mark while riding, set after landing + delay", mid is None and isinstance(f1, (int, float)), f"in flight={mid} after={f1}")

P("mount:", ld("mount")[:60]); time.sleep(2)
P("dismount:", ld("dismount")[:60]); time.sleep(delay + 4)
f2 = fav()
ok("4. mounting again - the mark is unchanged", f2 == f1, f"{f1} -> {f2}")

errs = game_errors(console_lines())
ok("5. console without game errors", not errs, " | ".join(errs[:3]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("fav_check: the 'favorite' prompt once after the first flight")
