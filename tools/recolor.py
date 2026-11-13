#!/usr/bin/env python3
"""An element colour variant by recolouring the embedded GLB texture (spec 03 §6, 09 §2-3). The mesh, the skin and the nodes are not
touched: only the PNG in the bufferView changes, the buffer is rebuilt (offsets, 4-byte alignment, chunk lengths).
The colouring - a gradient map by brightness (the pattern and the shading are kept) over the body mask: dark neutral details
(pupils, straps, atlas seams) and warm tones (mouth, brown spots) stay as they were. The VARIANTS presets: glacier (Frost),
pearl (Tide). --check compares the source and the result, --sheet builds a 'before/after' sheet (texture + a render without dependencies).

    python3 tools/recolor.py --variant glacier in.glb out.glb [--png-dir assets_src/variants/png]
    python3 tools/recolor.py --check in.glb out.glb
    python3 tools/recolor.py --sheet preview.jpg a_src.glb a_out.glb [b_src.glb b_out.glb ...]
"""
import argparse
import copy
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

GLB_MAGIC, CH_JSON, CH_BIN = 0x46546C67, 0x4E4F534A, 0x004E4942

# Preset: ramps - two gradient maps (position 0..1 -> colour), mixed by a source feature (mix);
# tone - the brightness curve control points: (the body brightness percentile, the position on the map); keep_dark - the brightness and
# saturation below which a pixel stays original.
VARIANTS = {
    "glacier": {  # Frost: deep turquoise-blue ice, the highlights almost white with blue
        "ramps": [
            [(0.00, "#04242F"), (0.14, "#074A5E"), (0.34, "#0B6F86"), (0.55, "#1E9AB4"),
             (0.74, "#5CC8DA"), (0.88, "#B5ECF4"), (1.00, "#F0FCFF")],   # turquoise ice
            [(0.00, "#061D3A"), (0.14, "#0A3C6C"), (0.34, "#14609C"), (0.55, "#2C8AC4"),
             (0.74, "#6ABBE6"), (0.88, "#BFE4F8"), (1.00, "#F2FAFF")],   # sapphire ice
        ],
        "mix": ("sat", 0.06, 0.22),       # more saturated (membranes, crest) -> sapphire; a white body -> turquoise
        "tone": [(2, 0.06), (50, 0.47), (90, 0.74), (99.5, 0.97)],
        "keep_dark": (0.12, 0.24, 0.25, 0.45),
    },
    "pearl": {  # Tide: mother-of-pearl, creamy white, in the shadows a pink-lavender and turquoise shimmer
        "ramps": [
            [(0.00, "#3A2E50"), (0.10, "#8A76A8"), (0.28, "#B9A3C8"), (0.46, "#DCC2D2"),
             (0.64, "#F2DACF"), (0.82, "#F8EBDA"), (1.00, "#FFFCF5")],   # pink-lavender
            [(0.00, "#1C3A44"), (0.10, "#5A98A0"), (0.28, "#8EC4C0"), (0.46, "#C4DED3"),
             (0.64, "#E9E6D6"), (0.82, "#F8ECDB"), (1.00, "#FFFCF5")],   # turquoise
        ],
        "mix": ("hue", 209.0, 197.0),     # an indigo-blue body -> lavender; turquoise wings -> turquoise
        "tone": [(2, 0.10), (50, 0.68), (90, 0.87), (99.5, 0.98)],
        "keep_dark": (0.07, 0.16, 0.20, 0.40),
    },
}


# ---------- GLB ----------

def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def read_glb(path):
    data = open(path, "rb").read()
    magic, ver, total = struct.unpack("<III", data[:12])
    if magic != GLB_MAGIC or ver != 2 or total != len(data):
        raise ValueError(f"{path}: not a GLB 2.0 or the length does not match ({total} != {len(data)})")
    off, js, binc = 12, None, b""
    while off < len(data):
        ln, typ = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + ln]
        if typ == CH_JSON:
            js = json.loads(chunk)
        elif typ == CH_BIN:
            binc = chunk
        off += 8 + ln
    return js, binc


def write_glb(path, js, binc):
    jb = pad4(json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8"), b" ")
    binc = pad4(binc)
    out = struct.pack("<III", GLB_MAGIC, 2, 12 + 8 + len(jb) + 8 + len(binc))
    out += struct.pack("<II", len(jb), CH_JSON) + jb + struct.pack("<II", len(binc), CH_BIN) + binc
    with open(path, "wb") as fh:
        fh.write(out)
    return len(out)


def view_bytes(js, binc, i):
    bv = js["bufferViews"][i]
    o = bv.get("byteOffset", 0)
    return binc[o:o + bv["byteLength"]]


def image_view(js, idx=0):
    return js["images"][idx]["bufferView"]


def replace_view(js, binc, vi, raw):
    """The new JSON and BIN: bufferView vi is replaced with raw, the rest are laid out in order with a 4-byte alignment."""
    js = copy.deepcopy(js)
    order = sorted(range(len(js["bufferViews"])), key=lambda i: js["bufferViews"][i].get("byteOffset", 0))
    new = bytearray()
    for i in order:
        chunk = raw if i == vi else view_bytes(js, binc, i)
        new += b"\x00" * ((4 - len(new) % 4) % 4)
        js["bufferViews"][i]["byteOffset"] = len(new)
        js["bufferViews"][i]["byteLength"] = len(chunk)
        new += chunk
    new = pad4(bytes(new))
    js["buffers"][0]["byteLength"] = len(new)
    return js, new


def accessor(js, binc, ai):
    CT = {5120: "<i1", 5121: "<u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
    N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
    a = js["accessors"][ai]
    bv = js["bufferViews"][a["bufferView"]]
    dt, n = np.dtype(CT[a["componentType"]]), N[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", dt.itemsize * n)
    if stride == dt.itemsize * n:
        arr = np.frombuffer(binc, dt, a["count"] * n, start).reshape(a["count"], n)
    else:
        rows = [np.frombuffer(binc, dt, n, start + k * stride) for k in range(a["count"])]
        arr = np.stack(rows)
    return arr.astype(np.float64) if dt.kind == "f" else arr.astype(np.int64)


# ---------- colour ----------

def hex_rgb(h):
    return [int(h[k:k + 2], 16) / 255.0 for k in (1, 3, 5)]


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def hsv(rgb):
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-6)
    h = np.where(mx == r, ((g - b) / dd) % 6, np.where(mx == g, (b - r) / dd + 2, (r - g) / dd + 4)) * 60.0
    return np.where(d > 1e-6, h, 0.0), s, mx


def ramp(t, stops):
    pos = [p for p, _ in stops]
    cols = np.array([hex_rgb(c) for _, c in stops])
    return np.stack([np.interp(t, pos, cols[:, k]) for k in range(3)], -1)


def boxmean(a, r):
    p = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    k, (H, W) = 2 * r + 1, a.shape
    return (p[k:k + H, k:k + W] - p[:H, k:k + W] - p[k:k + H, :W] + p[:H, :W]) / (k * k)


def head_uv_mask(pos, uv, idx, size):
    """The head UV mask: the upper (Y), front (+Z, snout), X-central vertices; triangles -> an image."""
    lo, hi = pos.min(0), pos.max(0)
    ext = hi - lo
    head = ((pos[:, 1] > lo[1] + 0.35 * ext[1]) & (pos[:, 2] > hi[2] - 0.2 * ext[2])
            & (np.abs(pos[:, 0] - (lo[0] + hi[0]) / 2) < 0.12 * ext[0]))
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for t in idx[head[idx].any(1)]:
        d.polygon([(uv[v, 0] * size[0], uv[v, 1] * size[1]) for v in t], fill=255)
    return np.asarray(m.filter(ImageFilter.MaxFilter(13))) > 0


def components(mask):
    """Connected areas of the mask (4-connectivity, PIL flood fill): labels 2..k."""
    lab = Image.fromarray(mask.astype(np.int32), "I")
    k = 1
    for y, x in zip(*np.nonzero(mask)):
        if lab.getpixel((int(x), int(y))) == 1:
            k += 1
            ImageDraw.floodfill(lab, (int(x), int(y)), k)
    return np.asarray(lab), k


def eye_mask(rgb, head, radii=range(4, 17, 2), ndir=16, dl=0.15, ds=0.08, frac=0.875, dark=0.45,
             min_area=100, min_round=0.5, verbose=False):
    """The eyes in the head UV area: a dark round disc (iris+pupil), around it a lighter and less saturated ring
    (sclera) in >= frac directions; the area must be round (area / the circle by the far point >= min_round).
    The babies have big eyes - they are found; the adults' eye is a dark slit, keep_dark keeps it anyway.
    Returns a 0..1 mask (the source iris and pupil pixels) and a list of (x, y, area, roundness)."""
    L = rgb @ np.array([0.2126, 0.7152, 0.0722])
    s = hsv(rgb)[1]
    Lb, Sb = boxmean(L, 1), boxmean(s, 1)
    H, W = L.shape
    ys, xs = np.nonzero(head)
    union = np.zeros(L.shape, bool)
    for R in radii:
        D, DS = boxmean(L, max(1, int(R * 0.6)))[ys, xs], boxmean(s, max(1, int(R * 0.6)))[ys, xs]
        cnt = np.zeros(len(ys))
        for k in range(ndir):
            a = 2 * np.pi * k / ndir
            yy = np.clip(ys + int(round((R + 3) * np.sin(a))), 0, H - 1)
            xx = np.clip(xs + int(round((R + 3) * np.cos(a))), 0, W - 1)
            cnt += (Lb[yy, xx] > D + dl) & (Sb[yy, xx] < DS - ds)
        ok = (cnt >= frac * ndir) & (D < dark)
        if not ok.any():
            continue
        m = Image.new("L", (W, H), 0)
        d = ImageDraw.Draw(m)
        for y, x in zip(ys[ok], xs[ok]):
            d.ellipse((x - R - 1, y - R - 1, x + R + 1, y + R + 1), fill=255)
        thr = np.median(D[ok]) + dl / 2  # inside the disc only what is darker than the sclera
        union |= (np.asarray(m) > 0) & (L < thr)
    out = np.zeros(L.shape, bool)
    eyes = []
    if union.any():
        lab, k = components(union)
        for c in range(2, k + 1):
            cy, cx = np.nonzero(lab == c)
            area = len(cy)
            rmax = np.sqrt(((cy - cy.mean()) ** 2 + (cx - cx.mean()) ** 2).max()) + 0.5
            rnd = area / (np.pi * rmax ** 2)
            if verbose:
                print(f"    candidate {int(cx.mean())},{int(cy.mean())}: area {area}, roundness {rnd:.2f}")
            if area >= min_area and rnd >= min_round:
                out[cy, cx] = True
                eyes.append((int(cx.mean()), int(cy.mean()), area, round(rnd, 2)))
    if eyes:
        out = np.asarray(Image.fromarray(out.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
                         .filter(ImageFilter.GaussianBlur(1))) / 255.0
    return out.astype(np.float64), eyes


def recolor(im, preset, eyes=None):
    rgb = np.asarray(im.convert("RGB")).astype(np.float64) / 255.0
    L = rgb @ np.array([0.2126, 0.7152, 0.0722])
    h, s, _ = hsv(rgb)
    ld0, ld1, sd0, sd1 = preset["keep_dark"]
    keep_dark = (1 - smooth(ld0, ld1, L)) * (1 - smooth(sd0, sd1, s))
    warm_dist = np.minimum(np.abs(h - 25.0), 360.0 - np.abs(h - 25.0))  # mouth, brown spots, claws
    keep_warm = (1 - smooth(40.0, 60.0, warm_dist)) * smooth(0.12, 0.25, s)
    keep = np.maximum(keep_dark, keep_warm)
    if eyes is not None:
        keep = np.maximum(keep, eyes)
    body = keep < 0.5
    pct = np.percentile(L[body], [p for p, _ in preset["tone"]])
    xs = np.concatenate([[0.0], pct, [1.0]])
    ys = np.concatenate([[0.0], [v for _, v in preset["tone"]], [1.0]])
    xs = np.maximum.accumulate(xs + np.arange(len(xs)) * 1e-6)  # strictly increasing supports
    t = np.interp(L, xs, ys)
    kind, a, b = preset["mix"]
    if kind == "sat":
        m = smooth(a, b, s)
    else:  # hue: a -> 0 (the first map), b -> 1 (the second)
        m = smooth(0.0, 1.0, (h - a) / (b - a)) * smooth(0.10, 0.25, s)
    m = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))) / 255.0
    col = ramp(t, preset["ramps"][0]) * (1 - m[..., None]) + ramp(t, preset["ramps"][1]) * m[..., None]
    out = rgb * keep[..., None] + col * (1 - keep[..., None])
    return Image.fromarray((out * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGB")


# ---------- check ----------

def check(src, dst):
    js0, b0 = read_glb(src)
    js1, b1 = read_glb(dst)
    vi = image_view(js0)
    problems = []
    j0, j1 = copy.deepcopy(js0), copy.deepcopy(js1)
    for j in (j0, j1):
        for bv in j["bufferViews"]:
            bv.pop("byteOffset", None)
            bv.pop("byteLength", None)
        for bf in j["buffers"]:
            bf.pop("byteLength", None)
    if j0 != j1:
        problems.append("the JSON differs not only by offsets/lengths")
    for i in range(len(js0["bufferViews"])):
        if i != vi and view_bytes(js0, b0, i) != view_bytes(js1, b1, i):
            problems.append(f"bufferView {i} changed")
        o = js1["bufferViews"][i].get("byteOffset", 0)
        if o % 4 or o + js1["bufferViews"][i]["byteLength"] > len(b1):
            problems.append(f"bufferView {i}: offset {o} is not a multiple of 4 or outside the buffer")
    if js1["buffers"][0]["byteLength"] != len(b1):
        problems.append("buffers[0].byteLength != the BIN length")
    im1 = Image.open(io.BytesIO(view_bytes(js1, b1, vi)))
    im1.load()
    im0 = Image.open(io.BytesIO(view_bytes(js0, b0, vi)))
    if im0.size != im1.size:
        problems.append(f"image size {im0.size} -> {im1.size}")
    for k in ("nodes", "skins", "meshes", "accessors", "materials"):
        if len(js0.get(k, [])) != len(js1.get(k, [])):
            problems.append(f"the count {k} changed")
    print(f"{os.path.basename(dst)}: nodes {len(js1['nodes'])}, skins {len(js1.get('skins', []))}, "
          f"joints {len(js1['skins'][0]['joints']) if js1.get('skins') else 0}, image {im1.size} {im1.mode}, "
          f"BIN {len(b0)} -> {len(b1)}: " + ("OK" if not problems else "; ".join(problems)))
    return not problems


# ---------- comparison sheet ----------

def load_mesh(path):
    js, binc = read_glb(path)
    pr = js["meshes"][0]["primitives"][0]
    pos = accessor(js, binc, pr["attributes"]["POSITION"])
    uv = accessor(js, binc, pr["attributes"]["TEXCOORD_0"])
    idx = accessor(js, binc, pr["indices"]).reshape(-1, 3)
    tex = Image.open(io.BytesIO(view_bytes(js, binc, image_view(js)))).convert("RGB")
    return pos, uv, idx, tex


def render(pos, uv, idx, tex, size=320, yaw=-35.0, pitch=18.0, bg=(205, 214, 222)):
    """Flat fill of the triangles with the texture colour at the UV centre, Lambert, painter's order by depth (PIL only)."""
    cy, sy = np.cos(np.radians(yaw)), np.sin(np.radians(yaw))
    cp, sp = np.cos(np.radians(pitch)), np.sin(np.radians(pitch))
    R = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]) @ np.eye(3)
    R = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]]) @ R
    p = pos @ R.T
    p -= (p.max(0) + p.min(0)) / 2
    sc = 0.9 * size / max(np.ptp(p[:, 0]), np.ptp(p[:, 1]))
    xy = np.stack([size / 2 + p[:, 0] * sc, size / 2 - p[:, 1] * sc], -1)
    tri = p[idx]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.linalg.norm(n, axis=1, keepdims=True) + 1e-12
    light = np.array([0.35, 0.75, 0.55])
    light /= np.linalg.norm(light)
    shade = 0.45 + 0.6 * np.abs(n @ light)
    tw, th = tex.size
    a = np.asarray(tex).astype(np.float64)
    c = uv[idx].mean(1)
    px = np.clip((c[:, 0] % 1.0) * tw, 0, tw - 1).astype(int)
    py = np.clip((c[:, 1] % 1.0) * th, 0, th - 1).astype(int)  # glTF: v down, like the image rows
    col = np.clip(a[py, px] * shade[:, None], 0, 255).astype(np.uint8)
    img = Image.new("RGB", (size, size), bg)
    d = ImageDraw.Draw(img)
    for k in np.argsort(tri[:, :, 2].mean(1)):  # far ones first (+z toward the viewer)
        d.polygon([tuple(v) for v in xy[idx[k]]], fill=tuple(col[k]))
    return img


def sheet(out, pairs, cell=256):
    rows = len(pairs)
    W = Image.new("RGB", (cell * 5, cell * rows), (40, 40, 44))
    d = ImageDraw.Draw(W)
    for r, (src, dst) in enumerate(pairs):
        meshes = [load_mesh(src), load_mesh(dst)]
        for c, m in enumerate(meshes):
            W.paste(m[3].resize((cell, cell), Image.LANCZOS), (c * cell, r * cell))
            big = render(*m, size=cell * 2)
            W.paste(big.resize((cell, cell), Image.LANCZOS), ((2 + c) * cell, r * cell))
        far = Image.new("RGB", (cell, cell), (205, 214, 222))  # ~40 studs: the dragon is 40 px
        for c, m in enumerate(meshes):
            far.paste(render(*m, size=cell * 2).resize((48, 48), Image.LANCZOS), (40 + c * 104, 104))
        W.paste(far, (4 * cell, r * cell))
        d.text((4, r * cell + 4), os.path.basename(src), fill=(255, 255, 0))
        d.text((cell + 4, r * cell + 4), os.path.basename(dst), fill=(255, 255, 0))
    W.save(out, quality=88)
    print(out, W.size)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", choices=sorted(VARIANTS))
    ap.add_argument("--png-dir", default="", help="save the before/after textures as PNG")
    ap.add_argument("--check", action="store_true", help="compare src and dst")
    ap.add_argument("--sheet", default="", help="comparison sheet: src dst pairs")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    if a.sheet:
        sheet(a.sheet, list(zip(a.files[0::2], a.files[1::2])))
        return
    if a.check:
        sys.exit(0 if check(a.files[0], a.files[1]) else 1)
    if not a.variant or len(a.files) != 2:
        ap.error("need --variant and two files: in.glb out.glb")
    src, dst = a.files
    js, binc = read_glb(src)
    vi = image_view(js)
    src_im = Image.open(io.BytesIO(view_bytes(js, binc, vi)))
    pos, uv, idx, _ = load_mesh(src)
    eyes, found = eye_mask(np.asarray(src_im.convert("RGB")) / 255.0, head_uv_mask(pos, uv, idx, src_im.size))
    new_im = recolor(src_im, VARIANTS[a.variant], eyes if found else None)
    buf = io.BytesIO()
    new_im.save(buf, "PNG", optimize=True)
    js2, bin2 = replace_view(js, binc, vi, buf.getvalue())
    js2["images"][0]["mimeType"] = "image/png"
    os.makedirs(os.path.dirname(os.path.abspath(dst)), exist_ok=True)
    n = write_glb(dst, js2, bin2)
    if a.png_dir:
        os.makedirs(a.png_dir, exist_ok=True)
        stem = os.path.splitext(os.path.basename(dst))[0]
        src_im.convert("RGB").save(os.path.join(a.png_dir, f"{stem}_before.png"))
        new_im.save(os.path.join(a.png_dir, f"{stem}_after.png"))
    print(f"{dst}: {n} bytes, image {len(view_bytes(js, binc, vi))} -> {len(buf.getvalue())} bytes, {a.variant}, "
          f"eyes kept: {[(x, y) for x, y, _, _ in found] or 'not found (adults - a dark slit, keep_dark holds it)'}")


if __name__ == "__main__":
    main()
