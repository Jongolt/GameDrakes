#!/usr/bin/env python3
"""The material colour under a MaterialVariant = what devices without terrain textures see (they draw the terrain
in a flat colour). We take the average texture colour x 1.2 as the tint, and divide the colour map by the tint (a soft upper clamp), so that
on strong devices map x tint = the source texture. Writes <name>_v2_color.png and tints.json.
python3 terrain_tint_normalize.py [granite_moss pebbles dark_earth dry_grass]
"""
import json
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "assets_src", "terrain_textures")
FACTOR = 1.2
KNEE = 0.85


def main():
    names = sys.argv[1:] or ["granite_moss", "pebbles", "dark_earth", "dry_grass"]
    tints = {}
    for name in names:
        arr = np.asarray(Image.open(os.path.join(SRC, f"{name}_color.png")).convert("RGB")).astype(np.float32)
        mean = arr.reshape(-1, 3).mean(0)
        tint = np.clip(mean * FACTOR, 1, 235)
        r = arr / tint  # 1.0 = exactly the tint
        soft = np.where(r < KNEE, r, KNEE + (r - KNEE) * 0.3)
        out = np.clip(soft * 255, 0, 255).astype(np.uint8)
        Image.fromarray(out).save(os.path.join(SRC, f"{name}_v2_color.png"))
        clipped = float((r > 1.0).mean() * 100)
        tints[name] = [int(round(t)) for t in tint]
        print(f"{name}: mean {mean.round(0).tolist()} -> tint {tints[name]}, pixels above the tint {clipped:.0f}%")
    json.dump(tints, open(os.path.join(SRC, "tints.json"), "w"), indent=1)


if __name__ == "__main__":
    main()
