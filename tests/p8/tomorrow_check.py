#!/usr/bin/env python3
"""The 'tomorrow' chain on P8, LOCAL file (after tools/p8/open_local.sh). Studio has no Roblox 'notifications' window -
we check the calendar day, the banner and the quiet around it (fight, riding).
  1) join: day 1 waits (claimed 0), no 'Tomorrow' banner until the first dismount;
  2) mounted and dismounted after minSession: day 1 claimed by itself (claimed 1), the 'Tomorrow, Day 2' banner appeared when it was quiet (we record whether there was a fight);
  3) the second dismount in the same session - no banner (once per session);
  4) a new session without dismounts: the banner at afterSeconds;
  5) console without game errors.
Run: python3 tests/p8/tomorrow_check.py. Output: $P8_OUT_ROOT/roblox_build_<date>/tomorrow_check/ (result.md, frames)."""
import json, os, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p8lib
p8lib.begin("tomorrow_check")
from p8lib import *  # noqa: F401,F403

SEED = os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_event_covers_2026-10-21", "seed_pearl.json")  # Tide elder as the companion, tutorial done


def edit(code): return run(code, "Edit")
def ld(c): return S(LD + f"return ld('{c}')")
def cal(): return (dump().get("rewards") or {}).get("calendar") or {}
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


# the client itself waits up to N s and returns the first seen banner text with Tomorrow and how many of these seconds a fight was going (the Fight attribute)
WATCH = ("local me=game.Players.LocalPlayer local g=me.PlayerGui:FindFirstChild('Banners') local f=g and g:FindFirstChild('Banner',true) "
         "local fight=0 for i=1,{n} do if me:GetAttribute('Fight') then fight+=1 end "
         "if f and f.Visible then local l=f:FindFirstChild('L1') if l and string.find(l.Text,'Tomorrow') then "
         "return l.Text..' | '..(f:FindFirstChild('L2') and f.L2.Text or '')..' | t='..(i/2)..' fight='..(fight/2) end end task.wait(0.5) end "
         "return 'none | fight='..(fight/2)")


def watch(seconds):
    return run(WATCH.replace("{n}", str(int(seconds * 2))), "Client", int(seconds) + 60)


# only a NEW appearance: the 'Tomorrow' banner must first be hidden, then shown again (an old one that has not faded yet does not count)
WATCH_NEW = ("local me=game.Players.LocalPlayer local g=me.PlayerGui:FindFirstChild('Banners') local f=g and g:FindFirstChild('Banner',true) "
             "local hidden=false for i=1,{n} do local l=f and f:FindFirstChild('L1') "
             "local on=f and f.Visible and l and string.find(l.Text,'Tomorrow') "
             "if not on then hidden=true elseif hidden then return 'new: '..l.Text..' | t='..(i/2) end task.wait(0.5) end "
             "return 'none | hidden_seen='..tostring(hidden)")


def watch_new(seconds):
    return run(WATCH_NEW.replace("{n}", str(int(seconds * 2))), "Client", int(seconds) + 60)


def seed(day, claimed, sessions=0, play=1000):
    """Sessions - how many joins there were before: 0 - the first session (the chain on dismount / afterSeconds), > 0 - a returning player
    (the chain right after join, returnAfter). play - seconds played: >= Config.UI.newbie.seconds - not the newcomer mode (spec 19 §17),
    less - the newcomer mode, the chain waits for its end."""
    prof = json.load(open(SEED))
    prof["lastSeen"] = int(time.time())
    prof["sessions"] = sessions
    prof["playSeconds"] = play
    prof["rewards"]["calendar"] = {"day": day, "claimed": claimed, "lastDate": time.strftime("%Y-%m-%d", time.gmtime())}
    ob = prof.setdefault("onboarding", {})
    ob["flew"] = True
    ob["favAsked"] = int(time.time()) - 3600  # the 'favorite' prompt has already happened - not in the queue
    js = json.dumps(prof, ensure_ascii=False)
    assert "]=====]" not in js
    edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if not s then s=Instance.new('StringValue') s.Name='StudioSeed' s.Parent=game.ServerStorage end s.Value=[=====[" + js + "]=====] return #s.Value")


stop()
seed(1, 0)
start(); wait_world()
t_start = time.time()
TB = json.loads(S("local t=require(game.ReplicatedStorage.Shared.Config).Rewards.tomorrowBanner return game:GetService('HttpService'):JSONEncode(t)"))
NS = int(float(S("return tostring(require(game.ReplicatedStorage.Shared.Config).UI.newbie.seconds)")))  # while the game is running (after stop() S does not answer)
P("tomorrowBanner:", TB, "newbie.seconds:", NS)
if "--newbie" in sys.argv:  # only step 6 (the newcomer mode)
    stop()
    seed(1, 0, sessions=0, play=0)
    start(); wait_world()
    t4 = time.time()
    mid = watch(max(NS - 40, 30))
    c4 = cal()
    ok("6a. newcomer mode: the day not claimed and no banner until the mode ends", mid.startswith("none") and c4.get("claimed") == 0, f"{mid} | {c4} | {int(time.time() - t4)} s of {NS}")
    after = watch(120)
    c5 = cal()
    ok("6b. after the newcomer mode - the day claimed and 'Tomorrow, Day 2'", "Tomorrow, Day 2" in after and c5.get("claimed") == 1, f"{after} | {c5} | {int(time.time() - t4)} s")
    errs = game_errors(console_lines())
    ok("6c. console without game errors", not errs, " | ".join(errs[:3]))
    stop()
    edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
    write_result("tomorrow_check --newbie: newcomer mode")
    sys.exit(0)
c0 = cal()
early = watch(5)
ok("1. join: day 1 waits, no banner", c0.get("day") == 1 and c0.get("claimed") == 0 and early.startswith("none"), f"{c0} | {early}")

left = TB["minSession"] + 2 - (time.time() - t_start)
if left > 0:
    time.sleep(left)
P("mount:", ld("mount")[:60]); time.sleep(3)
P("dismount:", ld("dismount")[:60])
seen = watch(TB["quietFor"] + TB["claimGap"] + 60)
shot("2_after_dismount")
c1 = cal()
ok("2a. day 1 claimed by itself", c1.get("claimed") == 1, str(c1))
ok("2b. the 'Tomorrow, Day 2' banner after the dismount", "Tomorrow, Day 2" in seen, seen)

gone = run("local f=game.Players.LocalPlayer.PlayerGui.Banners:FindFirstChild('Banner',true) for i=1,40 do if not f.Visible then return 'hidden t='..(i/2) end task.wait(0.5) end return 'still visible'", "Client", 80)
P("first banner:", gone)
P("mount:", ld("mount")[:60]); time.sleep(3)
P("dismount:", ld("dismount")[:60])
again = watch_new(25)
ok("3. the second dismount - no new banner", again.startswith("none") and "still" not in gone, f"{gone} | {again}")

if "--d2" in sys.argv:
    # in Studio Config.Rewards.calendar.d2ab.force = "B" (a source edit in Edit, the place is not saved)
    # day 2 waits - the chain itself gives a Rare dragon of the element from the UserId: scene -> name dialog -> reward banner -> 'Tomorrow, Day 3'
    stop()
    edit("local m=game.ReplicatedStorage.Shared.Config local s=m.Source local a,b=string.find(s,'d2ab = { on = true, rarity = \"Rare\" }',1,true) "
         "if not a then return 'no d2ab' end m.Source=string.sub(s,1,a-1)..'d2ab = { on = true, rarity = \"Rare\", force = \"B\" }'..string.sub(s,b+1) return 'forced'")
    seed(2, 1, sessions=3)  # came back on day 2: the gift right on join, without mounting
    start()
    t3 = time.time()
    d_before = len(json.load(open(SEED)).get("dragons") or {})
    el = S("local C=require(game.ReplicatedStorage.Shared.Config) local E=require(game.ReplicatedStorage.Shared.Core.Experiments) "
           "return E.d2Group(game.Players:GetPlayers()[1].UserId, C.Rewards.calendar.d2ab)..'/'..E.d2Element(game.Players:GetPlayers()[1].UserId, C.Elements)")
    P("group/element:", el)
    seen2 = watch(TB["returnAfter"] + TB["quietFor"] + 90)
    P("to the 'tomorrow' banner from join:", int(time.time() - t3), "s")
    shot("d2_after")
    d = dump()
    cal2 = (d.get("rewards") or {}).get("calendar") or {}
    news = [v for v in (d.get("dragons") or {}).values() if isinstance(v, dict) and v.get("rarity") == "Rare" and v.get("element") == el.split("/")[-1]]
    ok("d2-1. group B (force) and the element from the UserId", el.startswith("B/"), el)
    ok("d2-2. day 2 claimed, a dragon of the right element appeared", cal2.get("claimed") == 2 and len(d.get("dragons") or {}) == d_before + 1 and len(news) >= 1, f"{cal2} | was {d_before} now {len(d.get('dragons') or {})} | Rare {el}: {len(news)}")
    ok("d2-3. then the 'Tomorrow, Day 3' banner (returning, without mounting)", "Tomorrow, Day 3" in seen2, seen2)
    errs = game_errors(console_lines())
    ok("d2-4. console without game errors", not errs, " | ".join(errs[:3]))
    stop()
    edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
    write_result("tomorrow_check --d2: the day 2 dragon (force B)")
    sys.exit(0)
if "--only3" in sys.argv:
    stop()
    edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
    write_result("tomorrow_check (--only3): steps 1-3")
    sys.exit(0)
stop()
seed(1, 1)
start(); wait_world()
t2 = time.time()
late = watch(TB["afterSeconds"] + TB["quietFor"] + 45)
ok("4. without dismounts - the banner by afterSeconds", "Tomorrow, Day 2" in late and time.time() - t2 >= TB["afterSeconds"] - 5, f"{late} | {int(time.time() - t2)} s")

# the newcomer mode - neither claiming the day nor the banner until it ends (game newbie.seconds or the 1st fight stage)
stop()
seed(1, 0, sessions=0, play=0)
start(); wait_world()
t4 = time.time()
mid = watch(max(NS - 40, 30))
c4 = cal()
ok("6a. newcomer mode: the day not claimed and no banner until the mode ends", mid.startswith("none") and c4.get("claimed") == 0, f"{mid} | {c4} | {int(time.time() - t4)} s of {NS}")
after = watch(120)
c5 = cal()
ok("6b. after the newcomer mode - the day claimed and 'Tomorrow, Day 2'", "Tomorrow, Day 2" in after and c5.get("claimed") == 1, f"{after} | {c5} | {int(time.time() - t4)} s")

errs = game_errors(console_lines())
ok("5. console without game errors", not errs, " | ".join(errs[:3]))
stop()
edit("local s=game.ServerStorage:FindFirstChild('StudioSeed') if s then s:Destroy() end return 'cleared'")
write_result("tomorrow_check: 'tomorrow' after the first dismount, auto-claim of the day, once per session, fallback timer")
