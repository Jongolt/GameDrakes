#!/usr/bin/env python3
"""Terrain textures for MaterialVariant (C1, 11.10.2026; spec 04 Addendum 2.0 item 2): gpt-image-2 /images/generations,
photorealistic 1024 tiles (granite with moss, pebbles, dark soil, dry grass). The key is read from the env file inside
the script and does not get into the output. Seamlessness and normal/roughness - tools/terrain_textures_post.py. Usage -> usage.json.
    python3 gen_terrain_textures.py [granite_moss pebbles dark_earth dry_grass]
"""
import base64
import json
import os
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets_src", "terrain_textures")
ENV_FILE = os.environ.get("ENV_FILE", "." + "env")
MODEL, QUALITY = "gpt-image-2", "medium"
COMMON = (" Photorealistic, seamless tileable texture, viewed exactly from above (orthographic top-down), flat even overcast "
          "diffuse lighting, no cast shadows, no direct sunlight, no lens effects, no horizon, no objects, no text, no border, "
          "the material fills the whole frame edge to edge at a uniform scale.")
KINDS = {
    "granite_moss": "Weathered light grey granite rock surface with rusty brown mineral veins and cracks, patches of bright "
                    "green moss and pale lichen growing in the cracks and hollows, slightly damp." + COMMON,
    "pebbles": "Riverbank ground densely covered with small rounded pebbles and gravel of mixed grey, beige and brown "
               "stones between 1 and 6 cm, with damp coarse sand between them." + COMMON,
    "dark_earth": "Dark brown forest path soil, slightly damp, with small embedded stones, bits of twigs, dry pine needles "
                  "and a few fallen leaves." + COMMON,
    "dry_grass": "Meadow ground densely covered with grass blades in olive green and yellow-green tones with a few dry "
                 "straw-colored patches and tiny clover leaves, dense ground cover seen from directly above." + COMMON,
    # the Old Ash plaza - a clay glade, the ancient slabs of the circle, moss in the cracks (mesh textures, not terrain)
    "plaza_clay": "Packed sun-dried clay earth of a well-trodden village clearing, warm ochre, tan and light terracotta "
                  "tones, fine shallow dry cracks, small embedded flat pebbles and grit, a few tiny dry grass stems, "
                  "slightly uneven trampled surface, light and warm overall." + COMMON,
    "plaza_flagstone": "Surface of ancient worn sandstone paving stone, warm beige and pale grey, smoothed by centuries of "
                       "footsteps, shallow pits, small chips and fine cracks, tiny spots of pale lichen, no joints, one "
                       "continuous stone surface." + COMMON,
    # Springs - the rims and the bottom of the pools from travertine (our own, not other games')
    "springs_travertine": "Natural travertine limestone deposit of hot spring terraces, creamy white and pale ivory with soft "
                          "ochre and light peach mineral streaks, fine wavy ripple ridges and tiny rounded rims of calcite, "
                          "smooth wet-looking but matte, bright and clean." + COMMON,
    "plaza_moss": "Dense soft green cushion moss with tiny leaves and a few small patches of dark soil and tiny clover, "
                  "rich fresh green." + COMMON,
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
        out = os.path.join(OUT, f"{name}_raw.png")
        if os.path.exists(out):
            print(name, "exists")
            continue
        t = time.time()
        r = requests.post("https://api.openai.com/v1/images/generations", headers={"Authorization": f"Bearer {k}"}, timeout=300,
                          json={"model": MODEL, "prompt": KINDS[name], "size": "1024x1024", "quality": QUALITY,
                                "n": 1, "output_format": "png"})
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
