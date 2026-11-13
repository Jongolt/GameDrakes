#!/usr/bin/env python3
"""C4 textures (spec 04 Addendum 2.0 item 3): cards of needles, spruce, fern, bush, heather on a magenta
background (cut out in tree_glb.py) and a pine bark tile. gpt-image-2 medium, the key from the env file, it does not get into the output.
    python3 gen_c4_textures.py [needle_pine needle_spruce fern shrub heather pine_bark]
"""
import base64
import json
import os
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets_src", "c4_textures")
ENV_FILE = os.environ.get("ENV_FILE", "." + "env")
MODEL, QUALITY = "gpt-image-2", "medium"
CARD = ("Photorealistic game texture sprite: {what}, viewed straight from the side, isolated with no ground, no sky, no trunk "
        "and no shadow, soft even daylight, natural colors, fills about 85% of the frame. The background is a flat uniform pure "
        "magenta color (#FF00FF) with no gradient, so it can be keyed out. No text, no border.")
KINDS = {
    "needle_pine": CARD.format(what="a single dense pine tree branch cluster with long dark green needles, warm rusty undertone near the woody twigs, several overlapping sprigs forming a rounded tuft"),
    "needle_spruce": CARD.format(what="a single dense spruce branch cluster with short blue-green needles on drooping twigs, forming a layered flat tier"),
    "fern": CARD.format(what="a clump of green fern fronds spreading outward from one base, several arching fronds with fine leaflets"),
    "shrub": CARD.format(what="a low rounded wild shrub with many small dark green leaves and a few lighter young leaves, bushy and dense"),
    "heather": CARD.format(what="a wild heather bush with thin woody stems, tiny green leaves and many small pink-purple flowers"),
    "pine_bark": ("Seamless tileable photorealistic texture of mature pine tree bark, reddish brown plates with deep dark fissures, "
                  "flat frontal view, even diffuse lighting, no shadows, fills the entire frame edge to edge, no border, no text."),
}


def key():
    for line in open(ENV_FILE, encoding="utf-8"):
        if line.startswith("OPENAI_API_KEY="):
            return line.split("=", 1)[1].strip().strip('"\'')
    sys.exit("no key")


def main():
    os.makedirs(OUT, exist_ok=True)
    upath = os.path.join(OUT, "usage.json")
    usage = json.load(open(upath)) if os.path.exists(upath) else {}
    kinds = sys.argv[1:] or list(KINDS)
    k = key()
    for name in kinds:
        out = os.path.join(OUT, f"{name}.png")
        if os.path.exists(out):
            print(name, "exists")
            continue
        t = time.time()
        r = requests.post("https://api.openai.com/v1/images/generations", headers={"Authorization": f"Bearer {k}"}, timeout=300,
                          json={"model": MODEL, "prompt": KINDS[name], "size": "1024x1024", "quality": QUALITY, "n": 1, "output_format": "png"})
        if r.status_code != 200:
            print(name, "HTTP", r.status_code, r.text[:300].replace(k, "<key>"), flush=True)
            continue
        j = r.json()
        open(out, "wb").write(base64.b64decode(j["data"][0]["b64_json"]))
        usage[name] = {"sec": round(time.time() - t, 1), "usage": j.get("usage"), "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        json.dump(usage, open(upath, "w"), indent=1)
        print(name, "ok", round(time.time() - t), "c", flush=True)
    del k


if __name__ == "__main__":
    main()
