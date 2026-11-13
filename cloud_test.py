#!/usr/bin/env python3
"""Cloud tests of the published place through Luau Execution (Open Cloud).
The script tests/cloud/<name>.luau runs on a Roblox server in the context of the place (DataModel without players); the result is printed.

python3 cloud_test.py shop_products          # all ShopIds: GetProductInfoAsync -> price, isForSale, name; compared with monetize.CATALOG
python3 cloud_test.py smoke --version 226    # another script, a specific place version

The key comes from the file in ROBLOX_OPENCLOUD_KEY_FILE and never reaches the output. Substitutions in the script: {{SHOP_IDS}} -> a Luau table { key = { id, kind } }.
"""
import json
import os
import re
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
UNIVERSE = 10769731146
PLACE = 85991537614055


def shop_ids_luau():
    src = open(os.path.join(HERE, "src", "shared", "ShopIds.luau"), encoding="utf-8").read()
    out = []
    for block, kind in (("passes", "GamePass"), ("products", "Product")):
        m = re.search(block + r"\s*=\s*\{(.*?)\n\t\}", src, re.S)
        for k, v in re.findall(r"(\w+)\s*=\s*(\d+)", m.group(1)):
            out.append(f'\t{k} = {{ id = {v}, kind = "{kind}" }},')
    return "{\n" + "\n".join(out) + "\n}"


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    name = sys.argv[1]
    version = sys.argv[sys.argv.index("--version") + 1] if "--version" in sys.argv else None
    key = open(KEY_FILE).read().strip()
    # a name or a path to a .luau (a probe variant outside the repo, e.g. in runs/); --out FILE - the full JSON result without the 6000 cut
    out_file = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else None
    src_path = name if name.endswith(".luau") else os.path.join(HERE, "tests", "cloud", name + ".luau")
    script = open(src_path, encoding="utf-8").read()
    script = script.replace("{{SHOP_IDS}}", shop_ids_luau())
    base = f"https://apis.roblox.com/cloud/v2/universes/{UNIVERSE}/places/{PLACE}"
    if version:
        base += f"/versions/{version}"
    r = requests.post(base + "/luau-execution-session-tasks", headers={"x-api-key": key, "Content-Type": "application/json"},
                      json={"script": script, "timeout": "240s"}, timeout=60)
    if r.status_code >= 300:
        sys.exit(f"start: HTTP {r.status_code}: {r.text.replace(key, '<key>')[:300]}")
    path = r.json()["path"]
    t0 = time.time()
    while True:
        js = requests.get("https://apis.roblox.com/cloud/v2/" + path, headers={"x-api-key": key}, timeout=60).json()
        state = js.get("state")
        if state in ("COMPLETE", "FAILED", "CANCELLED"):
            break
        if time.time() - t0 > 300:
            sys.exit("the task did not finish within 5 minutes")
        time.sleep(3)
    logs = requests.get("https://apis.roblox.com/cloud/v2/" + path + "/logs", headers={"x-api-key": key}, timeout=60).json()
    for page in logs.get("luauExecutionSessionTaskLogs", []):
        for m in page.get("messages", []):
            print("log:", m)
    if state != "COMPLETE":
        sys.exit(f"task {state}: {json.dumps(js.get('error'), ensure_ascii=False)[:500]}")
    results = (js.get("output") or {}).get("results") or []
    print(json.dumps(results, ensure_ascii=False, indent=1)[:6000])
    if out_file:
        with open(out_file, "w", encoding="utf-8") as fh:
            json.dump(results, fh, ensure_ascii=False, indent=1)
        print(f"full result: {out_file}")
    if name == "shop_products" and results:
        sys.path.insert(0, HERE)
        import monetize
        want = {k: (kind, price, nm) for k, kind, nm, _d, price, _g in monetize.CATALOG + monetize.gift_rows()}
        got = results[0]
        bad = 0
        for k, (kind, price, nm) in want.items():
            g = got.get(k)
            if not g or not g.get("ok"):
                print("!! no answer:", k, g)
                bad += 1
            elif g.get("price") != price or not g.get("forSale") or g.get("name") != nm:
                print("!! mismatch:", k, "expected", (price, nm), "got", (g.get("price"), g.get("forSale"), g.get("name")))
                bad += 1
        print(f"shop_products: {len(want)} items, mismatches {bad}")
        sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
