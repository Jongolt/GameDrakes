#!/usr/bin/env python3
"""Sending the 'calendar day is ready' notifications from the queue the game writes (Services/Notify, Config.Notify).

Once an hour (cron on the VPS): the list of NotifyQueue_v1 entries (Open Cloud data stores) -> those whose due has come - POST users/{id}/notifications
(the text - a Creator Hub string: '{dragon} is waiting at your nest! Day {day} gift: {gift}', its id - MESSAGE_ID below) -> the entry is deleted.
For those who did not opt in to notifications Roblox answers FAILED_PRECONDITION - the entry is deleted too; throttling and 5xx - the entry
stays until the next hour (no longer than STALE_HOURS); a player who joined after leaving (the profile lastSeen) - the entry is deleted without sending. A log per day - LOG_DIR/<date>.jsonl.

    python3 tools/notify_send.py           # send the due ones
    python3 tools/notify_send.py --dry     # only show the queue and what would be sent, send and delete nothing

Key - the file in ROBLOX_OPENCLOUD_KEY_FILE (permissions: data stores, user.user-notification), it does not get into the output.
"""
import fcntl
import json
import os
import sys
import time
import urllib.parse

import requests

UNIVERSE = 10769731146
STORE = "NotifyQueue_v1"  # = Config.Notify.store
MESSAGE_ID = os.environ.get("NOTIFY_MESSAGE_ID", "262cd332-3bcb-1846-ba94-78b761735d0b")  # day_gift; the id of the Creator Hub string (Engagement -> Notifications -> Copy Asset ID); empty - only --dry
KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
LOG_DIR = os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_notify")
STALE_HOURS = 72  # older - not sent, deleted (the player left long ago, 'the gift is ready' is no longer news)
PROFILE_STORE = "Profile_v2"  # before sending: if the profile lastSeen is newer than the leave time in the entry - the player has already come back
CACHE = os.path.join(LOG_DIR, "cache.json")  # uid -> {due, left}: entries with a future due are not reread every hour
API = "https://apis.roblox.com/cloud/v2"


def log(rec):
    os.makedirs(LOG_DIR, exist_ok=True)
    rec["utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    with open(os.path.join(LOG_DIR, time.strftime("%Y-%m-%d", time.gmtime()) + ".jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def req(s, method, url, **kw):
    for attempt in range(3):
        try:
            r = s.request(method, url, timeout=30, **kw)
        except requests.RequestException as e:
            if attempt == 2:
                raise
            time.sleep(2 + attempt * 3)
            continue
        if r.status_code == 429 or r.status_code >= 500:
            if attempt == 2:
                return r
            time.sleep(3 + attempt * 5)
            continue
        return r
    return r


def entries(s):
    base = f"{API}/universes/{UNIVERSE}/data-stores/{STORE}/entries"
    token = ""
    while True:
        url = base + "?maxPageSize=100" + ("&pageToken=" + urllib.parse.quote(token) if token else "")
        r = req(s, "GET", url)
        if r.status_code == 404:  # the store does not exist yet - nobody has left since the release
            return
        r.raise_for_status()
        d = r.json()
        for e in d.get("dataStoreEntries", []):
            yield e["path"], e["path"].rsplit("/", 1)[-1]
        token = d.get("nextPageToken") or ""
        if not token:
            return


def send(s, uid, v):
    body = {
        "source": {"universe": f"universes/{UNIVERSE}"},
        "payload": {
            "message_id": MESSAGE_ID,
            "type": "MOMENT",
            "parameters": {
                "dragon": {"string_value": str(v.get("dragon") or "Your dragon")[:40]},
                "day": {"string_value": str(int(v.get("day") or 1))},
                "gift": {"string_value": str(v.get("gift") or "a gift")[:40]},
            },
        },
        "join_experience": {"launch_data": "src=notify&k=day"},
        "analytics_data": {"category": "day_gift"},
    }
    return req(s, "POST", f"{API}/users/{uid}/notifications", json=body)


def main():
    dry = "--dry" in sys.argv
    lock = open("/tmp/notify_send.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)  # the previous run is still going - skip this one
    except BlockingIOError:
        print("another run is already in progress")
        return
    if not MESSAGE_ID and not dry:
        print("MESSAGE_ID is empty: the Creator Hub string is not set up yet - only --dry")
        return
    key = open(KEY_FILE).read().strip()
    s = requests.Session()
    s.headers.update({"x-api-key": key, "Content-Type": "application/json"})
    now = time.time()
    stat = {"queue": 0, "due": 0, "sent": 0, "not_opted": 0, "throttled": 0, "stale": 0, "back": 0, "bad": 0, "error": 0}
    try:
        cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    except (OSError, ValueError):
        cache = {}
    seen = {}
    try:
        for path, uid in entries(s):
            stat["queue"] += 1
            c = cache.get(uid)
            if c and float(c.get("due", 0)) > now and now - float(c.get("left", 0)) <= STALE_HOURS * 3600:
                seen[uid] = c  # the due time has not come - not reading
                continue
            try:
                kept = one(s, key, path, uid, now, dry, stat)
                if kept:
                    seen[uid] = kept
            except requests.RequestException as e:  # the network failed after retries - the entry stays until the next hour
                stat["error"] += 1
                log({"uid": uid, "outcome": "crash", "resp": str(e)[:200]})
    except requests.RequestException as e:  # the queue list was not received - the run is not lost without a summary
        log({"outcome": "list_crash", "resp": str(e)[:200]})
        stat["error"] += 1
    if not dry:
        os.makedirs(LOG_DIR, exist_ok=True)
        with open(CACHE + ".tmp", "w") as f:
            json.dump(seen, f)
        os.replace(CACHE + ".tmp", CACHE)
    log({"summary": stat, "dry": dry})
    print(("[dry] " if dry else "") + " ".join(f"{k}={n}" for k, n in stat.items()))


def came_back(s, uid, left):
    """The player joined after leaving per the entry (the deletion on join failed or a server race) - no notification is needed."""
    r = req(s, "GET", f"{API}/universes/{UNIVERSE}/data-stores/{PROFILE_STORE}/entries/{uid}")
    if r.status_code != 200:
        return False  # the profile was not read - the queue entry decides
    v = r.json().get("value")
    d = v.get("Data") if isinstance(v, dict) and isinstance(v.get("Data"), dict) else v
    return isinstance(d, dict) and float(d.get("lastSeen") or 0) > float(left) + 60


def delete(s, path, uid):
    r = req(s, "DELETE", f"{API}/{path}")
    if r.status_code not in (200, 204, 404):  # not deleted - the next hour will send it again, this must be visible
        log({"uid": uid, "outcome": "delete_failed", "status": r.status_code})


def one(s, key, path, uid, now, dry, stat):
    """One queue entry. Returns {due, left} if the entry stays (for the cache), otherwise None."""
    r = req(s, "GET", f"{API}/{path}")
    if r.status_code == 404:
        return None  # the player came back and the entry was deleted between the listing and the read
    if r.status_code != 200:
        stat["error"] += 1
        log({"uid": uid, "outcome": "read_error", "status": r.status_code})
        return None
    v = r.json().get("value")
    if not isinstance(v, dict) or not str(uid).isdigit():
        stat["bad"] += 1
        log({"uid": uid, "outcome": "bad_entry"})
        if not dry:
            delete(s, path, uid)
        return None
    keep = {"due": float(v.get("due") or 0), "left": float(v.get("left") or 0)}
    if now - keep["left"] > STALE_HOURS * 3600:
        stat["stale"] += 1
        if not dry:
            delete(s, path, uid)
        return None
    if keep["due"] > now:
        return keep
    stat["due"] += 1
    if dry:
        print(f"would send: {uid} {v}")
        return keep
    if came_back(s, uid, keep["left"]):
        stat["back"] += 1
        log({"uid": uid, "outcome": "came_back"})
        delete(s, path, uid)
        return None
    r = send(s, uid, v)
    text = r.text.replace(key, "<key>")[:300]
    if r.status_code == 200:
        stat["sent"] += 1
        outcome = "sent"
    elif "not opted in" in text:
        stat["not_opted"] += 1
        outcome = "not_opted"
    elif r.status_code == 429 or "throttle" in text.lower() or "RESOURCE_EXHAUSTED" in text:
        stat["throttled"] += 1  # the limit of 1 per day per player: the entry lives until the next hour (or until STALE_HOURS)
        log({"uid": uid, "outcome": "throttled", "status": r.status_code})
        return keep
    elif r.status_code >= 500:
        stat["error"] += 1  # a Roblox failure: keep the entry until the next hour
        log({"uid": uid, "outcome": "error", "status": r.status_code, "resp": text})
        return keep
    else:
        stat["bad"] += 1
        outcome = "bad"
    log({"uid": uid, "outcome": outcome, "status": r.status_code, "day": v.get("day"), "resp": text if outcome == "bad" else ""})
    delete(s, path, uid)
    time.sleep(0.2)
    return None


if __name__ == "__main__":
    main()
