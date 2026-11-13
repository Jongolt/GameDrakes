#!/usr/bin/env python3
"""Post-processing of the terrain textures (C1): from *_raw.png makes a seamless colour (a half-tile shift + feathering
of the seam), a normal map by brightness (Sobel) and a roughness map (inverted brightness, compressed to 0.7-1.0). All 1024 x 1024 PNG.
    python3 terrain_textures_post.py [granite_moss pebbles ...]     # -> <name>_color.png, _normal.png, _rough.png
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "assets_src", "terrain_textures")
SIZE = 1024
STRENGTH = {"granite_moss": 2.4, "pebbles": 2.2, "dark_earth": 1.6, "dry_grass": 1.2}  # the normal map relief strength
ROUGH = {"granite_moss": (0.72, 1.0), "pebbles": (0.7, 0.98), "dark_earth": (0.8, 1.0), "dry_grass": (0.85, 1.0)}


def seamless(img: np.ndarray, feather: int = 160) -> np.ndarray:
    """A half-tile shift (the seams in the centre) and feathering of the seams with the source by a soft mask: the result edges match."""
    h, w = img.shape[:2]
    shifted = np.roll(np.roll(img, h // 2, axis=0), w // 2, axis=1)
    ys = np.arange(h)
    xs = np.arange(w)
    dy = np.abs(ys - h // 2)[:, None]
    dx = np.abs(xs - w // 2)[None, :]
    d = np.minimum(dy, dx).astype(np.float32)  # the distance to the nearest seam (a cross in the centre)
    mask = np.clip(d / feather, 0, 1)
    mask = mask * mask * (3 - 2 * mask)  # smoothstep
    out = shifted * mask[..., None] + img * (1 - mask[..., None])
    return out


def normal_map(gray: np.ndarray, strength: float) -> np.ndarray:
    g = gray.astype(np.float32) / 255.0
    # a slight blur so the normal does not get noisy on the grain
    k = np.array([1, 4, 6, 4, 1], np.float32) / 16
    g = np.apply_along_axis(lambda r: np.convolve(np.pad(r, 2, mode="wrap"), k, mode="valid"), 1, g)
    g = np.apply_along_axis(lambda c: np.convolve(np.pad(c, 2, mode="wrap"), k, mode="valid"), 0, g)
    gx = (np.roll(g, -1, axis=1) - np.roll(g, 1, axis=1)) * 0.5
    gy = (np.roll(g, -1, axis=0) - np.roll(g, 1, axis=0)) * 0.5
    nx = -gx * strength * 8
    ny = gy * strength * 8  # +Y up (the OpenGL convention, as in Roblox)
    nz = np.ones_like(g)
    n = np.stack([nx, ny, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def main():
    names = sys.argv[1:] or sorted(f[:-8] for f in os.listdir(SRC) if f.endswith("_raw.png"))
    for name in names:
        raw = os.path.join(SRC, f"{name}_raw.png")
        if not os.path.exists(raw):
            print(name, "no raw")
            continue
        im = Image.open(raw).convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
        arr = np.asarray(im).astype(np.float32)
        col = seamless(arr)
        Image.fromarray(col.astype(np.uint8)).save(os.path.join(SRC, f"{name}_color.png"))
        gray = (0.299 * col[..., 0] + 0.587 * col[..., 1] + 0.114 * col[..., 2])
        Image.fromarray(normal_map(gray, STRENGTH.get(name, 1.5))).save(os.path.join(SRC, f"{name}_normal.png"))
        lo, hi = ROUGH.get(name, (0.75, 1.0))
        r = lo + (hi - lo) * (1 - gray / 255.0)
        Image.fromarray((r * 255).astype(np.uint8)).save(os.path.join(SRC, f"{name}_rough.png"))
        # seam control: the difference of the first and last colour column/row
        seam = float(np.abs(col[:, 0] - col[:, -1]).mean() + np.abs(col[0] - col[-1]).mean()) / 2
        print(f"{name}: color/normal/rough ready, seam {seam:.1f} (0-255, lower is better)")


if __name__ == "__main__":
    main()
