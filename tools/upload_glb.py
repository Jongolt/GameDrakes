#!/usr/bin/env python3
"""Uploading a GLB (Model) to Roblox via the Open Cloud Assets API (modelled on runs/roblox_heroes_2026-10-10/tools/upload_glb.py).
State - JSON (idempotent by name): name -> assetId, moderation. The key from the file in ROBLOX_OPENCLOUD_KEY_FILE, it does not get into the output.

    python3 upload_glb.py --state assets_decor.json --prefix decor --desc "Kenney Nature Kit, CC0" file.glb [...]
"""
import argparse
import json
import os
import sys
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
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    key = open(KEY_FILE).read().strip()
    st = json.load(open(a.state)) if os.path.exists(a.state) else {}

    def save():
        json.dump(st, open(a.state, "w"), indent=1, ensure_ascii=False)

    ok = fail = 0
    for path in a.files:
        name = (a.prefix + "_" if a.prefix else "") + os.path.splitext(os.path.basename(path))[0]
        if st.get(name, {}).get("assetId"):
            continue
        req = {"assetType": "Model", "displayName": f"DN {name}"[:50], "description": a.desc[:1000],
               "creationContext": {"creator": {"userId": USER_ID}}}
        t = time.time()
        with open(path, "rb") as fh:
            r = requests.post(f"{API}/assets", headers={"x-api-key": key}, timeout=180,
                              files={"request": (None, json.dumps(req)),
                                     "fileContent": (os.path.basename(path), fh, "model/gltf-binary")})
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
                    "upload_s": round(time.time() - t, 1), "utc": time.strftime("%H:%M:%S", time.gmtime())}
        save()
        ok += 1 if asset_id else 0
        fail += 0 if asset_id else 1
        print(f"{name}: assetId {asset_id}, moderation {mod}, {st[name]['upload_s']} s", flush=True)
        time.sleep(1)
    del key
    print(f"done: uploaded {ok}, failures {fail}, total in the state {len(st)}")


if __name__ == "__main__":
    main()
