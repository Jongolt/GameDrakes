#!/usr/bin/env python3
"""Painted foliage textures for our own trees (P17): gpt-image-2 /images/generations, transparent background.
The key is read from the project env file inside the script, it does not get into the output. The model does not give a transparent background (400):
the background is a flat magenta, the alpha is cut out in tree_glb.py (--key). Usage -> painted_trees/usage.json.
    python3 gen_leaf_textures.py [green dark autumn blossom]
"""
import base64
import json
import os
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets_src", "painted_trees")
ENV_FILE = os.environ.get("ENV_FILE", "." + "env")
MODEL, QUALITY = "gpt-image-2", "medium"
KINDS = {
    "green": "fresh summer foliage in 3-4 tones of saturated green with warm yellow-green highlights",
    "dark": "deep forest foliage in dark green and teal-green tones with cool highlights",
    "autumn": "autumn foliage in bright orange, amber and red tones with yellow highlights",
    "blossom": "cherry blossom foliage in pink and rose tones with white highlights",
    "bark": None,  # trunk bark: a separate prompt, without cutting out the background
}
BARK_PROMPT = ("A seamless tileable hand-painted cartoon tree bark texture, flat square, warm brown with darker vertical "
               "cracks and lighter highlights, bold visible brush strokes, cel-shaded game style, no realism, no moss, "
               "no text, fills the entire frame edge to edge with no border.")
PROMPT = ("A single stylized hand-painted leaf cluster sprite for a cartoon video game tree, viewed straight on: a fluffy "
          "rounded mass of painterly leaves with bold visible brush strokes and soft edges, {kind}. Flat cel-shaded "
          "cartoon style, no realism, no texture noise. The cluster is isolated on a fully transparent background, "
          "no trunk, no branches, no ground, no shadow, no text, fills about 85% of the frame. The background is a flat, "
          "uniform, pure magenta color (#FF00FF) with no gradient, so it can be keyed out.")


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
        out = os.path.join(OUT, f"leaf_{name}.png")
        if os.path.exists(out):
            print(name, "exists")
            continue
        t = time.time()
        r = requests.post("https://api.openai.com/v1/images/generations", headers={"Authorization": f"Bearer {k}"}, timeout=300,
                          json={"model": MODEL, "prompt": BARK_PROMPT if name == "bark" else PROMPT.format(kind=KINDS[name]), "size": "1024x1024", "quality": QUALITY,
                                "n": 1, "output_format": "png"})
        if r.status_code != 200:
            print(name, "HTTP", r.status_code, r.text[:300].replace(k, "<key>"), flush=True)
            continue
        j = r.json()
        open(out, "wb").write(base64.b64decode(j["data"][0]["b64_json"]))
        usage[name] = {"sec": round(time.time() - t, 1), "usage": j.get("usage")}
        json.dump(usage, open(upath, "w"), indent=1)
        print(name, "ok", round(time.time() - t), "c", flush=True)
    del k


if __name__ == "__main__":
    main()
