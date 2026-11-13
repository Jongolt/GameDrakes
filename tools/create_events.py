#!/usr/bin/env python3
"""Roblox events for updates 2-4 (Cinder 15.11, Pearl Tide 22.11, Nightfall 29.11) and the Aurora text fix - with our Open Cloud key
(the universe.event permission). The texts: an events JSON kept outside this repository.
It writes to an external system - run it by hand:
python3 tools/create_events.py        # plan: which events exist, what will be created
python3 tools/create_events.py --go   # create the missing ones (by title, a repeat duplicates nothing) + Aurora without 'free'
Like the Aurora Update: host - the Lanternfox Studios group, the game place, public, 19:00-21:00 UTC, category newContent, the image - the main
game icon. The ids of the new events are printed at the end - they go into Content.Updates[n].eventId (RSVP in the game).
Own event images:
python3 tools/create_events.py --thumbs        # plan: who has no image, which file will be used
python3 tools/create_events.py --thumbs --go   # upload an Image from the group (like the Aurora image from Creator
# Hub), wait for the moderation, PATCH the event thumbnails
Images - THUMBS (runs/roblox_event_covers_2026-10-21/final, 1920x1080); the upload state - thumbs_state.json in the same place (a repeat
duplicates nothing). An event with an image is not touched.
Key - the file in ROBLOX_OPENCLOUD_KEY_FILE (not printed)."""
import json
import os
import sys
import time
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
U, PLACE, GROUP = 10769731146, 85991537614055, 76414869
AURORA = "9116981376158139036"
DATA = os.path.join(HERE, "..", "docs", "announcements", "2026-10-21_events_cinder_pearl_nightfall.json")
KEY = open(os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")).read().strip()
B = "https://apis.roblox.com/virtual-events"
ASSETS = "https://apis.roblox.com/assets/v1"
COVERS = os.path.join(os.environ.get("RUNS_DIR", "runs"), "roblox_event_covers_2026-10-21", "final")
THUMBS = {"Cinder Update": "cinder_update_event.jpg", "Pearl Tide Update": "pearl_tide_update_event.jpg",
          "Nightfall Update": "nightfall_update_event.jpg"}


def send(method, url, body):
    for attempt in range(4):  # 429/5xx - retry with a pause (only one of three events got created)
        for ct in ("application/json", "application/json-patch+json"):
            r = requests.request(method, url, headers={"x-api-key": KEY, "Content-Type": ct}, data=json.dumps(body), timeout=30)
            if r.status_code != 415:
                break
        if r.status_code != 429 and r.status_code < 500:
            return r
        time.sleep(2 ** attempt * 2)
    return r


def events():
    r = requests.get(f"{B}/v1/universes/{U}/virtual-events?limit=20", headers={"x-api-key": KEY}, timeout=30)
    r.raise_for_status()
    return {e["title"]: e for e in r.json()["data"]}


def upload(title, path, st, save):
    """An Image from the group (the Aurora image from Creator Hub is a group asset); wait for the moderation. -> assetId when Approved, otherwise None."""
    rec = st.get(title) or {}
    if not rec.get("assetId"):
        req = {"assetType": "Image", "displayName": title[:50], "description": f"Event image: {title}",
               "creationContext": {"creator": {"groupId": str(GROUP)}}}
        with open(path, "rb") as fh:
            r = requests.post(f"{ASSETS}/assets", headers={"x-api-key": KEY}, timeout=180,
                              files={"request": (None, json.dumps(req)), "fileContent": (os.path.basename(path), fh, "image/jpeg")})
        if r.status_code >= 300:
            print(f"  {title}: upload ERROR {r.status_code} {r.text[:300].replace(KEY, '<key>')}")
            return None
        op = r.json().get("path", "")
        for _ in range(40):
            time.sleep(3)
            o = requests.get(f"{ASSETS}/{op}", headers={"x-api-key": KEY}, timeout=60).json()
            if o.get("done"):
                rec = {"assetId": (o.get("response") or {}).get("assetId"), "file": os.path.basename(path),
                       "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
                break
        if not rec.get("assetId"):
            print(f"  {title}: upload did not finish in 2 min ({op}) - retry later")
            return None
        st[title] = rec
        save()
        print(f"  {title}: uploaded, assetId {rec['assetId']}")
    for _ in range(40):  # image moderation: usually seconds, wait up to ~4 min
        a = requests.get(f"{ASSETS}/assets/{rec['assetId']}", headers={"x-api-key": KEY}, timeout=30).json()
        rec["moderation"] = (a.get("moderationResult") or {}).get("moderationState")
        if rec["moderation"] in ("Approved", "Rejected"):
            break
        time.sleep(6)
    save()
    if rec["moderation"] != "Approved":
        print(f"  {title}: moderation {rec['moderation']} (assetId {rec['assetId']}) - not touching the event")
        return None
    return rec["assetId"]


def thumbs(have, go):
    path = os.path.join(COVERS, "..", "thumbs_state.json")
    st = json.load(open(path)) if os.path.exists(path) else {}

    def save():
        json.dump(st, open(path, "w"), indent=1, ensure_ascii=False)

    for title, fn in THUMBS.items():
        e = have.get(title)
        if not e:
            print(f"  {title}: no event")
            continue
        if e.get("thumbnails"):
            print(f"  {title}: the image already exists ({e['thumbnails']}) - not touching")
            continue
        img = os.path.join(COVERS, fn)
        if not go:
            print(f"  {title} ({e['id']}): set {img}")
            continue
        aid = upload(title, img, st, save)
        if not aid:
            continue
        r = send("PATCH", f"{B}/v3/game-events/{e['id']}", {"thumbnails": [{"mediaId": int(aid), "rank": 0}]})
        print(f"  {title}: image {aid} -", "ok" if r.ok else f"ERROR {r.status_code} {r.text[:300].replace(KEY, '<key>')}")
    if go:
        print("check:", "; ".join(f"{t}: {e.get('thumbnails')}" for t, e in events().items()))
    else:
        print("this is a plan; to set: python3 tools/create_events.py --thumbs --go")


def main():
    go = "--go" in sys.argv
    d = json.load(open(DATA, encoding="utf-8"))
    have = events()
    print("events now:", ", ".join(f"{t} ({e['id']}, {e['eventTime']['startUtc'][:16]})" for t, e in have.items()) or "-")
    if "--thumbs" in sys.argv:
        thumbs(have, go)
        return
    made = {}
    for key in ("cinder", "pearl", "nightfall"):
        e = d[key]
        if e["title"] in have:
            print(f"  {e['title']}: already exists ({have[e['title']]['id']})")
            made[key] = have[e["title"]]["id"]
            continue
        body = {"title": e["title"], "subtitle": e["subtitle"], "description": e["description"],
                "startTime": e["startUtc"].replace("Z", ".000Z"), "endTime": e["endUtc"].replace("Z", ".000Z"),
                "visibility": "public", "groupId": GROUP, "placeId": PLACE, "categories": [{"category": "newContent", "rank": 0}]}
        if not go:
            print(f"  create: {e['title']} {e['startUtc']} - {e['endUtc']} | {e['subtitle']}")
            continue
        r = send("POST", f"{B}/v3/universes/{U}/game-events", body)
        if r.ok:
            j = r.json()
            made[key] = str(j.get("id") or j.get("eventId") or j.get("path", "").split("/")[-1])
            print(f"  {e['title']}: created, id {made[key]}")
        else:
            print(f"  {e['title']}: ERROR {r.status_code} {r.text[:300].replace(KEY, '<key>')}")
    a = have.get("Aurora Update")
    if a and "free reward" in a.get("description", ""):
        new = a["description"].replace("for a free reward", "for a reward")
        if not go:
            print("  Aurora: «for a free reward» -> «for a reward»")
        else:
            r = send("PATCH", f"{B}/v3/game-events/{AURORA}", {"description": new})
            print("  Aurora: the text without 'free' -", "ok" if r.ok else f"ERROR {r.status_code} {r.text[:300].replace(KEY, '<key>')}")
    if go:
        print("ids for Content.Updates:", json.dumps(made))
    else:
        print("this is a plan; to create: python3 tools/create_events.py --go")


if __name__ == "__main__":
    main()
