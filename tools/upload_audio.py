#!/usr/bin/env python3
"""Uploading MP3 as Audio to Roblox via the Open Cloud Assets API (a copy of upload_image.py) + the game Use permission
(asset-permissions, as for the images 17.10: without it the phone gets nothing). Our own music/ElevenLabs sounds (our rights).
State - JSON (idempotent by file name): name -> assetId, moderation. The key from the file in ROBLOX_OPENCLOUD_KEY_FILE, it does not get into the output.
    python3 tools/upload_audio.py --state assets_audio.json --prefix mus --desc "Dragon Nest music" file.mp3 [...]
"""
import argparse
import json
import os
import time

import requests

KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
USER_ID = "11774991821"
UNIVERSE_ID = "10769731146"
API = "https://apis.roblox.com/assets/v1"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--prefix", default="")
    ap.add_argument("--desc", default="Dragon Nest")
    ap.add_argument("--refresh", action="store_true", help="only refresh the moderation status of the records that are not Approved")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()
    key = open(KEY_FILE).read().strip()
    st = json.load(open(a.state)) if os.path.exists(a.state) else {}

    def save():
        json.dump(st, open(a.state, "w"), indent=1, ensure_ascii=False)

    if a.refresh:
        for name, v in st.items():
            if v.get("assetId") and v.get("moderation") != "Approved" and v.get("operation"):
                o = requests.get(f"{API}/{v['operation']}", headers={"x-api-key": key}, timeout=60).json()
                mod = ((o.get("response") or {}).get("moderationResult") or {}).get("moderationState")
                if mod:
                    v["moderation"] = mod
                print(name, v.get("moderation"))
        save()
        del key
        return

    ok = fail = 0
    for path in a.files:
        name = (a.prefix + "_" if a.prefix else "") + os.path.splitext(os.path.basename(path))[0]
        if st.get(name, {}).get("assetId"):
            continue
        req = {"assetType": "Audio", "displayName": f"DN {name}"[:50], "description": a.desc[:1000],
               "creationContext": {"creator": {"userId": USER_ID}}}
        t = time.time()
        with open(path, "rb") as fh:
            r = requests.post(f"{API}/assets", headers={"x-api-key": key}, timeout=180,
                              files={"request": (None, json.dumps(req)),
                                     "fileContent": (os.path.basename(path), fh, "audio/mpeg")})
        if r.status_code >= 300:
            print(name, "HTTP", r.status_code, r.text.replace(key, "<key>")[:200], flush=True)
            st[name] = {"error": f"HTTP {r.status_code}", "text": r.text.replace(key, "<key>")[:200]}
            save()
            fail += 1
            time.sleep(5)
            continue
        op = r.json().get("path", "")
        asset_id, mod = None, None
        for _ in range(60):
            time.sleep(3)
            o = requests.get(f"{API}/{op}", headers={"x-api-key": key}, timeout=60).json()
            if o.get("done"):
                resp = o.get("response") or {}
                asset_id = resp.get("assetId")
                mod = (resp.get("moderationResult") or {}).get("moderationState")
                break
        st[name] = {"assetId": asset_id, "moderation": mod, "operation": op, "file": os.path.basename(path),
                    "upload_s": round(time.time() - t, 1), "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        if asset_id:
            g = requests.patch("https://apis.roblox.com/asset-permissions-api/v1/assets/permissions", headers={"x-api-key": key},
                               json={"subjectType": "Universe", "subjectId": UNIVERSE_ID, "action": "Use", "requests": [{"assetId": str(asset_id)}]},
                               timeout=60)
            st[name]["grant"] = g.status_code
        save()
        ok += 1 if asset_id else 0
        fail += 0 if asset_id else 1
        print(f"{name}: assetId {asset_id}, moderation {mod}, {st[name]['upload_s']} s", flush=True)
        time.sleep(1)
    del key
    print(f"done: uploaded {ok}, failures {fail}, total in the state {len(st)}")


if __name__ == "__main__":
    main()
