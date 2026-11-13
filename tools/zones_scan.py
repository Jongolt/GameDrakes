#!/usr/bin/env python3
"""The visit map from the live game profiles - read only.

The profile stores analytics.zones (Services/Analytics, Core/Zones): s - seconds by zone, f - the play time (playSeconds) of the first
visit, b - of them the seconds without progress (boredom), last - the last zone (on leaving - where he left), idle - the boredom before leaving. Scan: listing the Profile_v2 keys continuing by the cursor (one
Luau Execution task does not get through the whole list), then windows of WIN keys; into the summary - the newcomers with createdAt >= --since (UTC, ISO).

    python3 tools/zones_scan.py --since 2026-10-27T12:00:00 [--out runs/roblox_zones_<date>]

Writes nothing, takes no sessions (GetAsync). Summary: the share of newcomers who reached a zone; the median seconds of those who visited; the median
play time of the first visit; where they left (the last zone) - in total and by the play length (<60 s, <180 s, <600 s, longer).
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLOUD = os.path.join(HERE, "cloud_test.py")
WIN = 200

LIST = r'''-- read only: the Profile_v2 keys from the cursor (continuing the listing)
local DSS = game:GetService("DataStoreService")
local ds = DSS:GetDataStore("Profile_v2")
local t0 = os.clock()
local keys = {}
while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end
local ok, pages = pcall(function() return ds:ListKeysAsync("", 100, CURSOR) end)
if not ok then return { err = "list: " .. tostring(pages) } end
while true do
	for _, k in pages:GetCurrentPage() do table.insert(keys, k.KeyName) end
	if pages.IsFinished then return { keys = keys, done = true } end
	if os.clock() - t0 > 200 then return { keys = keys, cursor = pages.Cursor } end
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.ListAsync) < 1 do task.wait(1) end
	local ok2, e = pcall(function() pages:AdvanceToNextPageAsync() end)
	if not ok2 then return { err = "page: " .. tostring(e), keys = keys, cursor = pages.Cursor } end
end
'''

WINDOW = r'''-- read only: the visit map rows for a window of keys (newcomers with createdAt >= SINCE)
local DSS = game:GetService("DataStoreService")
local ds = DSS:GetDataStore("Profile_v2")
local HttpService = game:GetService("HttpService")
local SINCE = SINCE_TS
local keys = KEYS
local rows, errs = {}, 0
for _, k in keys do
	while DSS:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.GetAsync) < 1 do task.wait(0.5) end
	local ok, v = pcall(function() return ds:GetAsync(k) end)
	if not ok then
		errs += 1
	else
		local d = if type(v) == "table" and type(v.Data) == "table" then v.Data else v
		-- 01.11: and everyone who came by an invitation (data.invite.by > 0, Services/Social) - incl. old accounts (old = 1, they do not go into the newcomer summary)
		local inv = type(d) == "table" and type(d.invite) == "table" and (tonumber(d.invite.by) or 0) > 0
		if type(d) == "table" and ((tonumber(d.createdAt) or 0) >= SINCE or inv) then
			local z = type(d.analytics) == "table" and d.analytics.zones or nil
			table.insert(rows, HttpService:JSONEncode({ k = k, c = d.createdAt, p = d.playSeconds, n = d.sessions,
				ob = type(d.onboarding) == "table" and d.onboarding.stage or nil, z = z, cb = d.combat,
				on = type(d.analytics) == "table" and d.analytics.onboard or nil, iv = if inv then d.invite else nil,
				r1 = type(d.analytics) == "table" and d.analytics.r1 or nil, rd = type(d.analytics) == "table" and d.analytics.rd or nil,
				old = if (tonumber(d.createdAt) or 0) < SINCE then 1 else nil }))
		end
	end
end
return { rows = rows, errs = errs }
'''


def run_luau(src: str, out: str) -> dict:
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, dir=os.path.dirname(out)) as fh:
        fh.write(src)
        path = fh.name
    try:
        # (rewriting raid_census.py: all listing pages into one list.json - a failed task left the file of the previous page, the same
        # cursor was read again, 8088 keys with 1488, 317 rows with 53 players): the old result is deleted before the run
        if os.path.exists(out):
            os.remove(out)
        r = subprocess.run([sys.executable, CLOUD, path, "--out", out], capture_output=True, text=True, timeout=600)
        if not os.path.exists(out):
            raise SystemExit(f"the task gave no result: {(r.stdout + r.stderr)[-400:]}")
        res = json.load(open(out))
        return res[0] if isinstance(res, list) and res else {}
    finally:
        os.remove(path)


def luau_str(s: str) -> str:
    return json.dumps(s)


def funnel(rows: list, split: str):
    """The funnel (analytics.onboard - the unix time of a step, seconds from createdAt) and the fight (combat.stage / guardians) by group."""
    cut = int(datetime.fromisoformat(split).replace(tzinfo=timezone.utc).timestamp()) if split else None
    groups = [("all", rows)] if cut is None else [("before " + split, [r for r in rows if (r.get("c") or 0) < cut]),
                                                   ("after " + split, [r for r in rows if (r.get("c") or 0) >= cut])]
    for name, grp in groups:
        if not grp:
            print(f"{name}: 0 newcomers")
            continue
        p = [r.get("p") or 0 for r in grp]
        on = [r.get("on") if isinstance(r.get("on"), dict) else {} for r in grp]
        cb = [r.get("cb") if isinstance(r.get("cb"), dict) else {} for r in grp]
        print(f"{name}: n={len(grp)}, play median {statistics.median(p):.0f} s, < 3 min {sum(1 for x in p if x < 180) / len(grp):.0%}, "
              f">= 10 min {sum(1 for x in p if x >= 600) / len(grp):.0%}")
        # returned = a second session (sessions >= 2); the official D1 - the Analytics
        # Query API with a 1-2 day delay (runs/roblox_d1_2026-10-27/d1_daily.py). A second session on the same day also counts here
        back = [r for r in grp if (r.get("n") or 0) >= 2]
        print(f"  returned (sessions >= 2): {len(back)} of {len(grp)} = {len(back) / len(grp):.0%}; "
              f"play of the returned median {statistics.median([r.get('p') or 0 for r in back]) if back else 0:.0f} s")
        for step, label in (("2", "egg"), ("3", "hatched"), ("9", "riding"), ("12", "flight")):
            secs = [o[step] - (r.get("c") or o[step]) for o, r in zip(on, grp) if o.get(step)]
            med = f", median {statistics.median(secs):.0f} s from join" if secs else ""
            print(f"  {label:8} {len(secs) / len(grp):5.0%}{med}")
        wv = [c.get("waves") for c in cb if c.get("waves") is not None]
        if wv:  # combat.waves / fightSec - since the fight rhythm release
            fs = [(c.get("fightSec") or 0) / max(1, r.get("p") or 1) for r, c in zip(grp, cb) if c.get("waves") is not None]
            print(f"  waves median {statistics.median(wv):.0f}, fight share of play median {statistics.median(fs):.0%} (n={len(wv)})")
        st = [int(c.get("stage") or 0) for c in cb]
        print("  fight: stage " + ", ".join(f"{k}:{st.count(k)}" for k in sorted(set(st))) +
              f"; warden >= 1 for {sum(1 for c in cb if (c.get('guardians') or 0) >= 1) / len(grp):.0%}")
        short = [(r, o, c) for r, o, c in zip(grp, on, cb) if (r.get("p") or 0) < 180]
        if short:
            print(f"  left < 3 min (n={len(short)}): before hatching {sum(1 for _, o, _ in short if not o.get('3')) / len(short):.0%}, "
                  f"fight stage >= 2 {sum(1 for _, _, c in short if (c.get('stage') or 0) >= 2) / len(short):.0%}")


def first_raid(rows):
    """Who left without the first dragon -
    by analytics.r1 (Services/Analytics + Raid): in place / moving, the closest to the nest, thefts, captures, the last event."""
    noh = [r for r in rows if not (isinstance(r.get("on"), dict) and "3" in r["on"])]
    with_r1 = [r for r in noh if isinstance(r.get("r1"), dict)]
    print(f"without the first dragon: {len(noh)} of {len(rows)}, with the first theft measured: {len(with_r1)}")
    kinds = {}
    for r in with_r1:
        x = r["r1"]
        st, mv = x.get("st") or 0, x.get("mv") or 0
        take, caught = x.get("take") or 0, x.get("caught") or 0
        if st + mv > 0 and st >= 0.7 * (st + mv):
            k = "stood (did not play / loading)"
        elif not x.get("near"):
            k = "did not reach the nest (got lost)"
        elif take == 0:
            k = "reached it but did not take (did not understand / was afraid)"
        elif caught > 0 and x.get("last") == "caught":
            k = "took, got caught - gave up"
        else:
            k = "stole but did not carry it home (got lost)"
        kinds[k] = kinds.get(k, 0) + 1
        print(f"   play {r.get('p')} s | in place {st} / moving {mv} | closest {x.get('dmin')} | came near {x.get('near')} | "
              f"thefts {take} captures {caught} home {x.get('home') or 0} | last {x.get('last')}@{x.get('lastT')} -> {k}")
    for k, v in sorted(kinds.items(), key=lambda kv: -kv[1]):
        print(f"   {k}: {v}")
    # the daily raids of the first two sessions (analytics.rd) of those who left at 3-10 min - were they caught on the square
    mid = [r for r in rows if 180 <= (r.get("p") or 0) < 600 and isinstance(r.get("rd"), dict)]
    print(f"left at 3-10 min with the daily raids measured: {len(mid)}")
    for r in mid:
        x = r["rd"]
        print(f"   play {r.get('p')} s | thefts {x.get('take') or 0} captures {x.get('caught') or 0} home {x.get('home') or 0} | last {x.get('last')}@{x.get('lastT')}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", required=True, help="UTC ISO: the newcomers since this moment (the zone map release)")
    ap.add_argument("--out", default="")
    ap.add_argument("--split", default="", help="UTC ISO: split the newcomers into before / after (a release), the fight and funnel summary by group")
    ap.add_argument("--rows", default="", help="a ready rows.json of a previous scan: only the summary, do not read the profiles")
    a = ap.parse_args()
    if a.rows:
        rows = json.load(open(a.rows))
        print(f"rows from {a.rows}: {len(rows)}")
        funnel(rows, a.split)
        return
    since = int(datetime.fromisoformat(a.since).replace(tzinfo=timezone.utc).timestamp())
    out = a.out or os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_zones_" + datetime.now(timezone.utc).strftime("%Y-%m-%dT%H%M"))
    os.makedirs(out, exist_ok=True)
    keys, cursor, part = [], None, 0
    while True:
        res = run_luau(LIST.replace("CURSOR", luau_str(cursor) if cursor else "nil"), os.path.join(out, f"list_{part}.json"))
        keys += res.get("keys") or []
        if res.get("err"):
            print("listing:", res["err"])
        cursor = res.get("cursor")
        part += 1
        if res.get("done") or not cursor or part > 20:
            break
    keys = sorted(set(keys))
    print("keys", len(keys), "listing tasks", part)
    rows, errs = [], 0
    for i in range(0, len(keys), WIN):
        src = WINDOW.replace("SINCE_TS", str(since)).replace("KEYS", "{" + ",".join(luau_str(k) for k in keys[i:i + WIN]) + "}")
        res = run_luau(src, os.path.join(out, f"win_{i // WIN}.json"))
        rows += [json.loads(r) for r in res.get("rows") or []]
        errs += res.get("errs") or 0
    json.dump(rows, open(os.path.join(out, "rows.json"), "w"), ensure_ascii=False)
    invited = [r for r in rows if r.get("iv")]  # the invitation reward
    print(f"by invitation: {len(invited)}; egg given: {sum(1 for r in invited if (r['iv'].get('got') or '') != '')}")
    for r in invited[:20]:
        print(f"   {r['k']} by={r['iv'].get('by')} sec={r['iv'].get('sec')} got={r['iv'].get('got') or '-'} old={bool(r.get('old'))}")
    rows = [r for r in rows if not r.get("old")]
    funnel(rows, a.split)
    first_raid(rows)
    with_z = [r for r in rows if isinstance(r.get("z"), dict)]
    for r in with_z:  # an empty Luau table comes in JSON as a list []
        for k in ("s", "f", "b"):
            if not isinstance(r["z"].get(k), dict):
                r["z"][k] = {}
    print(f"newcomers since {a.since}: {len(rows)}, with a zone map: {len(with_z)}, read errors: {errs}")
    if not with_z:
        return
    zones = sorted({z for r in with_z for z in (r["z"].get("s") or {})})
    print(f"{'zone':10} {'reached':>7} {'sec med':>8} {'boredom':>6} {'1st visit med':>14} {'left here':>11}")
    last = [r["z"].get("last") for r in with_z]
    for z in zones:
        vis = [r for r in with_z if (r["z"].get("s") or {}).get(z)]
        secs = [r["z"]["s"][z] for r in vis]
        first = [r["z"]["f"][z] for r in vis if (r["z"].get("f") or {}).get(z) is not None]
        bored = sum((r["z"].get("b") or {}).get(z, 0) for r in vis) / max(1, sum(secs))  # the share of time in the zone without progress
        print(f"{z:10} {len(vis) / len(with_z):7.0%} {statistics.median(secs):8.0f} {bored:6.0%} {statistics.median(first) if first else 0:14.0f} "
              f"{last.count(z) / len(with_z):11.0%}")
    idle = [r["z"].get("idle") or 0 for r in with_z]
    print(f"bored before leaving (no progress at the last mark): median {statistics.median(idle):.0f} s, "
          f">= 20 s for {sum(1 for x in idle if x >= 20) / len(idle):.0%}")
    for lo, hi, name in ((0, 60, "<60 s"), (60, 180, "60-180 s"), (180, 600, "3-10 min"), (600, 10 ** 9, ">10 min")):
        grp = [r for r in with_z if lo <= (r.get("p") or 0) < hi]
        if grp:
            cnt = {}
            for r in grp:
                cnt[r["z"].get("last")] = cnt.get(r["z"].get("last"), 0) + 1
            top = ", ".join(f"{k} {v / len(grp):.0%}" for k, v in sorted(cnt.items(), key=lambda kv: -kv[1])[:5])
            print(f"left, play {name} (n={len(grp)}): {top}")
    print("files:", out)


if __name__ == "__main__":
    main()
