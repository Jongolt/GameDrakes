#!/usr/bin/env python3
"""English descriptions of the passes and products in Roblox = monetize.py CATALOG.

    python3 roblox_game/tools/store_desc.py          # check: what is in Roblox now and what it will become (changes nothing)
    python3 roblox_game/tools/store_desc.py --go     # PATCH the descriptions that differ - ONLY AFTER THE OWNER'S 'YES'

The es/pt/de/fr translations are uploaded by tools/loc_items.py push (the same key - the English text from CATALOG). The API key does not get into the output.
"""
import importlib.util
import os
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
KEY = open(os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")).read().strip()
U = 10769731146


def monetize():
    argv, sys.argv = sys.argv, ["monetize.py", "--dry"]
    spec = importlib.util.spec_from_file_location("monetize", os.path.join(GAME, "monetize.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.argv = argv
    return m


def api(method, path, **kw):
    r = requests.request(method, "https://apis.roblox.com" + path, headers={"x-api-key": KEY}, timeout=60, **kw)
    if r.status_code >= 300:
        raise SystemExit(f"{method} {path} -> HTTP {r.status_code}: {r.text.replace(KEY, '<key>')[:300]}")
    return r.json() if r.text.strip() else {}


def main():
    go = "--go" in sys.argv
    m = monetize()
    passes, products = {}, {}
    tok = None
    while True:
        js = api("GET", f"/game-passes/v1/universes/{U}/game-passes/creator", params={"pageSize": 100, **({"pageToken": tok} if tok else {})})
        for p in js.get("gamePasses") or []:
            passes[p["name"]] = p
        tok = js.get("nextPageToken")
        if not tok:
            break
    tok = None
    while True:
        js = api("GET", f"/developer-products/v2/universes/{U}/developer-products/creator", params={"pageSize": 100, **({"pageToken": tok} if tok else {})})
        for p in js.get("developerProducts") or []:
            products[p["name"]] = p
        tok = js.get("nextPageToken")
        if not tok:
            break
    diff = []
    for key, kind, name, desc, _price, _gift in m.CATALOG + m.gift_rows():
        live = (passes if kind == "pass" else products).get(name)
        if not live:
            print(f"  ? not in Roblox: {key} '{name}'")
            continue
        cur = (live.get("description") or "").strip()
        if cur != desc:
            diff.append((key, kind, live, cur, desc))
    print(f"items {len(m.CATALOG) + len(m.gift_rows())}; descriptions that differ: {len(diff)}")
    for key, kind, live, cur, desc in diff:
        print(f"  {key}\n    was:   {cur}\n    will be: {desc}")
    if not go or not diff:
        return
    # an error of one item does not bring down the rest; a pass, if the description PATCH is refused - via the same endpoint as loc_items.py
    # (legacy-game-internationalization, language en = the source text of the pass)
    bad = 0
    for key, kind, live, cur, desc in diff:
        try:
            if kind == "pass":
                # PATCH /game-passes/v1/game-passes/{id} -> 404 (no route), name-description/en -> 400 'source language'.
                # Updating a pass in Open Cloud (legacy): POST /game-passes/v1/game-passes/{id}/details, multipart: Name, Description, ...
                pid = live["gamePassId"]
                api("POST", f"/game-passes/v1/game-passes/{pid}/details",
                    files={"Name": (None, live.get("name")), "Description": (None, desc)})
            else:
                api("PATCH", f"/developer-products/v2/universes/{U}/developer-products/{live['productId']}", files={"description": (None, desc)})
            print(f"  updated: {key}")
        except SystemExit as e:
            bad += 1
            print(f"  FAILED {key}: {e}")
    print(f"result: updated {len(diff) - bad} of {len(diff)}, failures {bad}; check: python3 roblox_game/tools/store_desc.py (without --go)")


if __name__ == "__main__":
    main()
