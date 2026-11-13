#!/usr/bin/env python3
"""Uploading PNG as Image to Roblox via the Open Cloud Assets API (C1, 11.10.2026; modelled on upload_glb.py).
State - JSON (idempotent by file name): name -> assetId, moderation. The key from the file in ROBLOX_OPENCLOUD_KEY_FILE, it does not get into the output.
    python3 upload_image.py --state assets_textures.json --prefix tex --desc "Dragon Nest terrain texture" file.png [...]
"""
import argparse
import json
import os
import time

import requests

KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
USER_ID = "11774991821"
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
        req = {"assetType": "Image", "displayName": f"DN {name}"[:50], "description": a.desc[:1000],
               "creationContext": {"creator": {"userId": USER_ID}}}
        t = time.time()
        with open(path, "rb") as fh:
            r = requests.post(f"{API}/assets", headers={"x-api-key": key}, timeout=180,
                              files={"request": (None, json.dumps(req)),
                                     "fileContent": (os.path.basename(path), fh, "image/png")})
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
        save()
        ok += 1 if asset_id else 0
        fail += 0 if asset_id else 1
        print(f"{name}: assetId {asset_id}, moderation {mod}, {st[name]['upload_s']} s", flush=True)
        time.sleep(1)
    del key
    print(f"done: uploaded {ok}, failures {fail}, total in the state {len(st)}")


if __name__ == "__main__":
    main()
