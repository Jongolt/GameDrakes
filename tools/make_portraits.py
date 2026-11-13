#!/usr/bin/env python3
"""Dragon portraits for the UI. Source - renders
of the game 3D models themselves (TRELLIS previews, 4 angles on white, we take the second - three quarters from the front): v4b for 21 models, v4 for the Ember
baby and adult, the model sketch for the Dusk baby (there is no render). Background - a flood fill from the edges over near-white (the white Frost parts inside
the silhouette stay), a soft edge, cropping by the silhouette, a square with a margin, 256 px PNG with transparency.
python3 tools/make_portraits.py            # -> assets_src/portraits/<element>_s<1-4>.png + the sheet.png sheet
OBSOLETE: the portraits in the game are shots of the models themselves on P8 on a purple background 480x320 (3:2,
the dragon fills the frame): runs/roblox_portraits_2026-10-17/shoot.py + process.py, assets_portraits2.json. This is a fallback."""
import os
from collections import deque

from PIL import Image, ImageFilter

RUNS = os.environ.get("RUNS_DIR", "runs")
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets_src", "portraits")
V4B = f"{RUNS}/roblox_rig_v4b_2026-10-13/out/{{n}}_preview.png"
SRC = {  # element_stage -> (file, angle 0-3 or None for a single image)
    "ember_s1": (f"{RUNS}/roblox_dragons_v4_2026-10-13/gpu/out/ember_s1_preview.png", 1),
    "ember_s3": (f"{RUNS}/roblox_dragons_v4_2026-10-13/gpu/out/ember_s3_b_fit_preview.png", 1),
    "dusk_s1": (f"{RUNS}/roblox_dragons_v4_2026-10-13/concepts/dusk_s1.png", None),
}
ELEMENTS = ["ember", "frost", "moss", "tide", "storm", "dusk"]
SIZE = 256
PAD = 0.06


def source(name: str):
    path, view = SRC.get(name, (V4B.format(n=name), 1))
    im = Image.open(path).convert("RGB")
    if view is not None:
        w, h = im.size
        tile = w // 4
        im = im.crop((tile * view, 0, tile * (view + 1), h))
    return im


def cutout(im: Image.Image) -> Image.Image:
    w, h = im.size
    px = im.load()
    alpha = Image.new("L", (w, h), 255)
    a = alpha.load()
    seen = bytearray(w * h)
    q = deque()

    def white(x, y):
        r, g, b = px[x, y]
        return r > 232 and g > 232 and b > 232 and max(r, g, b) - min(r, g, b) < 18

    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if seen[i]:
            continue
        seen[i] = 1
        if not white(x, y):
            continue
        a[x, y] = 0
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                q.append((nx, ny))
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    out = im.convert("RGBA")
    out.putalpha(alpha)
    return out


def square(im: Image.Image) -> Image.Image:
    bbox = im.getchannel("A").point(lambda v: 255 if v > 40 else 0).getbbox()
    if bbox:
        im = im.crop(bbox)
    w, h = im.size
    side = int(max(w, h) * (1 + PAD * 2))
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(im, ((side - w) // 2, (side - h) // 2), im)
    return canvas.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for el in ELEMENTS:
        for s in range(1, 5):
            name = f"{el}_s{s}"
            p = square(cutout(source(name)))
            p.save(os.path.join(OUT, name + ".png"))
            tiles.append(p)
            print(name, "ok")
    sheet = Image.new("RGBA", (SIZE * 4, SIZE * 6), (52, 48, 56, 255))
    for i, t in enumerate(tiles):
        sheet.paste(t, ((i % 4) * SIZE, (i // 4) * SIZE), t)
    sheet.convert("RGB").save(os.path.join(OUT, "sheet.jpg"), quality=88)


if __name__ == "__main__":
    main()
