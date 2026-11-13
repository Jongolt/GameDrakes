#!/usr/bin/env python3
"""Painted trees (P17): a trunk with branches + foliage cards with an alpha texture -> a GLB for Roblox.
Pure Python + numpy + PIL (like egg_glb.py). Two nodes: woodBark (the trunk and branches, the material colour) and leaf (the cards,
a PNG texture with alpha, alphaMode MASK, doubleSided). Decor colours the trunk with the palette, keeps the texture and a light tone on the foliage.

    python3 tree_glb.py leaf_green.png out.glb --shape round|tall|wide [--seed 1] [--texsize 512]
"""
import argparse
import io
import json
import math
import os
import struct

import numpy as np
from PIL import Image


def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def rot_y(v, a):
    c, s = math.cos(a), math.sin(a)
    return np.array([v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c])


def cylinder(p0, p1, r0, r1, seg=8):
    """A truncated cylinder between p0 and p1: positions, normals, indices."""
    axis = p1 - p0
    length = np.linalg.norm(axis)
    axis = axis / length
    up = np.array([0.0, 1.0, 0.0]) if abs(axis[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = np.cross(axis, up)
    u /= np.linalg.norm(u)
    v = np.cross(axis, u)
    pos, nrm, idx = [], [], []
    for ring, (center, r) in enumerate(((p0, r0), (p1, r1))):
        for i in range(seg):
            a = 2 * math.pi * i / seg
            n = u * math.cos(a) + v * math.sin(a)
            pos.append(center + n * r)
            nrm.append(n)
    for i in range(seg):
        j = (i + 1) % seg
        a, b, c, d = i, j, seg + i, seg + j
        idx += [a, c, b, b, c, d]
    # the cap on top
    top = len(pos)
    pos.append(p1)
    nrm.append(axis)
    for i in range(seg):
        j = (i + 1) % seg
        idx += [seg + i, top, seg + j]
    return np.array(pos), np.array(nrm), np.array(idx, dtype=np.uint32)


def outline(alpha, k=40, inset=0.955):
    """The crown outline by the alpha mask: k rays from the centroid, on each - the outermost foliage pixel. The vertices in fractions
    of the texture side (centre 0,0; -0.5..0.5), a UV for each. The Roblox import does not take alpha (11.10: black squares),
    so the card is cut along the outline and no transparent margins remain."""
    h, w = alpha.shape
    mask = alpha > 0.5
    ys, xs = np.nonzero(mask)
    cy, cx = ys.mean(), xs.mean()
    pts, uvs = [], []
    for i in range(k):
        a = 2 * math.pi * i / k
        dx, dy = math.cos(a), -math.sin(a)
        rmax = 0.0
        r = 0.0
        while True:
            x, y = cx + dx * r, cy + dy * r
            if x < 0 or y < 0 or x >= w or y >= h:
                break
            if mask[int(y), int(x)]:
                rmax = r
            r += 2
        r = rmax * inset
        px, py = cx + dx * r, cy + dy * r
        pts.append(((px - w / 2) / w, (h / 2 - py) / h))
        uvs.append((px / w, py / h))
    return np.array(pts), np.array(uvs)


def card(center, size, yaw, tilt, shape2d, shape_uv):
    """A foliage card along the crown outline: a fan of triangles from the centre, UV by the texture."""
    k = len(shape2d)
    local = np.zeros((k + 1, 3))
    local[1:, 0] = shape2d[:, 0] * size[0]
    local[1:, 1] = shape2d[:, 1] * size[1]
    ct, st = math.cos(tilt), math.sin(tilt)
    local = local @ np.array([[1, 0, 0], [0, ct, -st], [0, st, ct]]).T
    pos = np.array([rot_y(c, yaw) for c in local]) + center
    n = rot_y(np.array([0, 0, 1.0]), yaw)
    uv = np.vstack([[0.5, 0.5], shape_uv])
    idx = []
    for i in range(k):
        idx += [0, 1 + i, 1 + (i + 1) % k]
    return pos, np.tile(n, (k + 1, 1)), uv, np.array(idx, dtype=np.uint32)


SHAPES = {
    # (x, y, z, size) in fractions of the tree height; the crowns are big and dense (9-11 clusters, size 0.5-0.8)
    "round": {"trunk": 0.5, "branches": 4, "cap": True, "clusters": [
        (0, 0.74, 0, 0.78), (0.26, 0.64, 0.12, 0.62), (-0.26, 0.66, -0.1, 0.62), (0.08, 0.6, 0.27, 0.58), (-0.1, 0.62, -0.27, 0.58),
        (0.2, 0.84, -0.14, 0.52), (-0.2, 0.86, 0.14, 0.52), (0.02, 0.94, 0.02, 0.5), (0.3, 0.74, -0.2, 0.48), (-0.3, 0.76, 0.2, 0.48)]},
    "tall": {"trunk": 0.62, "branches": 3, "cap": True, "clusters": [
        (0, 0.86, 0, 0.6), (0.18, 0.74, 0.08, 0.54), (-0.18, 0.7, -0.08, 0.54), (0.08, 0.6, -0.18, 0.48), (-0.1, 0.62, 0.18, 0.48),
        (0.14, 0.94, -0.1, 0.46), (-0.14, 0.96, 0.1, 0.46), (0, 1.02, 0, 0.4), (0.22, 0.82, 0.16, 0.44)]},
    "wide": {"trunk": 0.42, "branches": 5, "cap": True, "clusters": [
        (0, 0.62, 0, 0.72), (0.34, 0.56, 0.14, 0.6), (-0.34, 0.58, -0.12, 0.6), (0.12, 0.52, -0.32, 0.56), (-0.14, 0.54, 0.32, 0.56),
        (0.04, 0.76, 0.04, 0.54), (0.24, 0.7, -0.22, 0.48), (-0.24, 0.72, 0.22, 0.48), (0.4, 0.5, -0.1, 0.42), (-0.4, 0.5, 0.1, 0.42), (0, 0.86, 0, 0.4)]},
}


# C4: conifers in tiers and undergrowth. "tiers": (y, size) of the card tiers by the tree height; undergrowth without a trunk.
CONIFERS = {
    # pine: a bare trunk up to 0.45, the crown in tiers upward, a narrow top
    "pine": {"trunk": 0.98, "trunkR": (0.075, 0.03), "branches": 0, "tiers": [(0.42, 0.62), (0.54, 0.6), (0.66, 0.54), (0.77, 0.46), (0.87, 0.36), (0.96, 0.24)], "cards": 3, "tilt": -0.5},
    # spruce: the crown almost from the ground, the tiers wider at the bottom, a sharp top
    "spruce": {"trunk": 1.0, "trunkR": (0.065, 0.02), "branches": 0, "tiers": [(0.16, 0.66), (0.3, 0.64), (0.44, 0.58), (0.57, 0.5), (0.69, 0.42), (0.8, 0.34), (0.9, 0.26), (0.98, 0.16)], "cards": 3, "tilt": -0.55},
}
UNDERGROWTH = {
    # bush / fern / heather: 3 crossed cards at the ground, no trunk
    "bush": {"cards": 3, "size": (1.0, 0.85), "y": 0.42, "tilt": 0.0},
    "fern": {"cards": 4, "size": (1.0, 0.9), "y": 0.45, "tilt": 0.15},
    "heather": {"cards": 3, "size": (1.0, 0.8), "y": 0.4, "tilt": 0.05},
}


def build(tex_path, out, shape, seed, tex_size, bark_path=None):
    rng = np.random.default_rng(seed)
    if shape in CONIFERS or shape in UNDERGROWTH:
        return build_c4(tex_path, out, shape, rng, tex_size, bark_path)
    sh = SHAPES[shape]
    # trunk and branches
    wpos, wnrm, widx = [], [], []
    base = 0
    trunk_h = sh["trunk"]
    segs = [(np.array([0, -0.02, 0.0]), np.array([0, trunk_h, 0.0]), 0.1, 0.06)]
    for i in range(sh["branches"]):
        a = 2 * math.pi * i / sh["branches"] + rng.uniform(-0.4, 0.4)
        y0 = trunk_h * rng.uniform(0.6, 0.9)
        p0 = np.array([0, y0, 0.0])
        d = np.array([math.cos(a) * 0.3, 0.22 + rng.uniform(0, 0.14), math.sin(a) * 0.3])
        segs.append((p0, p0 + d, 0.05, 0.022))
    for p0, p1, r0, r1 in segs:
        p, n, idx = cylinder(p0, p1, r0, r1)
        wpos.append(p)
        wnrm.append(n)
        widx.append(idx + base)
        base += len(p)
    wpos, wnrm, widx = np.vstack(wpos), np.vstack(wnrm), np.concatenate(widx)
    # the trunk UV for the bark: u by the angle around the Y axis, v by the height (the bark tiles 2 times by height)
    ang = np.arctan2(wpos[:, 2], wpos[:, 0])
    wuv = np.stack([(ang / (2 * math.pi) + 0.5) * 2.0, (wpos[:, 1] / max(trunk_h, 1e-6)) * 2.0], axis=1)
    # the texture: cut out the magenta background (gpt-image-2 gives no transparency); fill the background with the average foliage colour,
    # so the card edge does not darken; alpha is needed only for the outline (the Roblox import does not draw it)
    im = Image.open(tex_path).convert("RGBA")
    arr = np.asarray(im).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    dist = np.sqrt(((255 - r) ** 2 + g ** 2 + (255 - b) ** 2).astype(np.float64))
    alpha = np.clip((dist - 60) / 60, 0, 1)  # < 60 - background, > 120 - foliage
    leaf = alpha > 0.9
    mean = np.array([int(arr[..., c][leaf].mean()) for c in range(3)])
    rgb = arr[..., :3].copy()
    for c in range(3):
        rgb[..., c] = np.where(alpha < 0.9, mean[c], rgb[..., c])
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    shape2d, shape_uv = outline(alpha)
    if im.size[0] != tex_size:
        im = im.resize((tex_size, tex_size), Image.LANCZOS)

    # foliage: clusters of 3 crossed outline cards
    lpos, lnrm, luv, lidx = [], [], [], []
    base = 0
    for ci, (cx, cy, cz, s) in enumerate(sh["clusters"]):
        center = np.array([cx, cy, cz])
        for k in range(3):
            yaw = k * math.pi / 3 + rng.uniform(-0.2, 0.2)
            tilt = rng.uniform(-0.25, 0.25)
            size = (s * rng.uniform(0.9, 1.1), s * rng.uniform(0.85, 1.0))
            p, n, uv, idx = card(center + rng.uniform(-0.03, 0.03, 3), size, yaw, tilt, shape2d, shape_uv)
            lpos.append(p)
            lnrm.append(n)
            luv.append(uv)
            lidx.append(idx + base)
            base += len(p)
        if sh.get("cap") and ci < 3:  # a horizontal card on top: the crown reads from above (top view, flight)
            p, n, uv, idx = card(center + np.array([0, s * 0.18, 0]), (s * 1.05, s * 1.05), rng.uniform(0, math.pi), math.pi / 2, shape2d, shape_uv)
            lpos.append(p)
            lnrm.append(n)
            luv.append(uv)
            lidx.append(idx + base)
            base += len(p)
    lpos, lnrm, luv, lidx = np.vstack(lpos), np.vstack(lnrm), np.vstack(luv), np.concatenate(lidx)
    write_glb(out, shape, im, wpos, wnrm, wuv, widx, lpos, lnrm, luv, lidx, bark_path)


def keyed_texture(tex_path, tex_size, despill="full"):
    """Cut out the magenta background: the outline by alpha and the image with the background of the average foliage colour (as in build).
    despill: removing the magenta halo from thin branches/needles (C4: the needles read purple) - "full" (everywhere R and B
    are above G) or "edge" (only at the edge, for plants with pink flowers, e.g. heather)."""
    im = Image.open(tex_path).convert("RGBA")
    arr = np.asarray(im).astype(np.int32)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    dist = np.sqrt(((255 - r) ** 2 + g ** 2 + (255 - b) ** 2).astype(np.float64))
    alpha = np.clip((dist - 60) / 60, 0, 1)
    leaf = alpha > 0.9
    rgb = arr[..., :3].copy()
    spill = np.clip(np.minimum(r, b) - g, 0, 255)  # the magenta admixture: R and B above G
    if despill == "full":
        k = np.ones_like(spill, dtype=np.float64)
    else:
        k = np.clip((160 - dist) / 100, 0, 1)  # only the pixels closer to magenta (the edge)
    rgb[..., 0] = np.clip(r - spill * k, 0, 255)
    rgb[..., 2] = np.clip(b - spill * k, 0, 255)
    mean = np.array([int(rgb[..., c][leaf].mean()) for c in range(3)])
    for c in range(3):
        rgb[..., c] = np.where(alpha < 0.9, mean[c], rgb[..., c])
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB")
    shape2d, shape_uv = outline(alpha)
    if im.size[0] != tex_size:
        im = im.resize((tex_size, tex_size), Image.LANCZOS)
    return im, shape2d, shape_uv


def build_c4(tex_path, out, shape, rng, tex_size, bark_path):
    im, shape2d, shape_uv = keyed_texture(tex_path, tex_size, "edge" if shape == "heather" else "full")
    lpos, lnrm, luv, lidx = [], [], [], []
    base = 0

    def add_card(center, size, yaw, tilt):
        nonlocal base
        p, n, uv, idx = card(center, size, yaw, tilt, shape2d, shape_uv)
        lpos.append(p)
        lnrm.append(n)
        luv.append(uv)
        lidx.append(idx + base)
        base += len(p)

    if shape in CONIFERS:
        sh = CONIFERS[shape]
        r0, r1 = sh["trunkR"]
        p, n, idx = cylinder(np.array([0, -0.02, 0.0]), np.array([0, sh["trunk"], 0.0]), r0, r1)
        wpos, wnrm, widx = p, n, idx
        ang = np.arctan2(wpos[:, 2], wpos[:, 0])
        wuv = np.stack([(ang / (2 * math.pi) + 0.5) * 2.0, (wpos[:, 1] / sh["trunk"]) * 3.0], axis=1)
        for ti, (ty, ts) in enumerate(sh["tiers"]):
            for k in range(sh["cards"]):
                yaw = k * math.pi / sh["cards"] + ti * 0.5 + rng.uniform(-0.2, 0.2)
                size = (ts * rng.uniform(0.9, 1.1), ts * rng.uniform(0.8, 0.95))
                add_card(np.array([0, ty, 0]) + rng.uniform(-0.02, 0.02, 3), size, yaw, sh["tilt"] + rng.uniform(-0.1, 0.1))
    else:
        sh = UNDERGROWTH[shape]
        # a tiny but non-degenerate 'trunk' at the ground: an empty mesh gave 'Invalid mesh collision data' in the console
        p, n, idx = cylinder(np.array([0, -0.01, 0.0]), np.array([0, 0.04, 0.0]), 0.02, 0.015, seg=4)
        wpos, wnrm, widx = p, n, idx
        wuv = np.zeros((len(p), 2))
        for k in range(sh["cards"]):
            yaw = k * math.pi / sh["cards"] + rng.uniform(-0.2, 0.2)
            size = (sh["size"][0] * rng.uniform(0.9, 1.1), sh["size"][1] * rng.uniform(0.9, 1.05))
            add_card(np.array([0, sh["y"], 0]) + rng.uniform(-0.03, 0.03, 3), size, yaw, sh["tilt"] + rng.uniform(-0.1, 0.1))
    lpos, lnrm, luv, lidx = np.vstack(lpos), np.vstack(lnrm), np.vstack(luv), np.concatenate(lidx)
    write_glb(out, shape, im, wpos, wnrm, wuv, widx, lpos, lnrm, luv, lidx, bark_path)


def write_glb(out, shape, im, wpos, wnrm, wuv, widx, lpos, lnrm, luv, lidx, bark_path=None):
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=88)
    png = buf.getvalue()

    # buffers
    chunks = []
    views = []
    accessors = []

    def add(arr, target, comp_type, acc_type, minmax=False):
        nonlocal chunks
        data = pad4(arr.astype("<f4" if comp_type == 5126 else "<u4").tobytes())
        off = sum(len(c) for c in chunks)
        chunks.append(data)
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        acc = {"bufferView": len(views) - 1, "componentType": comp_type, "count": len(arr), "type": acc_type}
        if minmax:
            acc["min"] = [float(x) for x in arr.min(axis=0)]
            acc["max"] = [float(x) for x in arr.max(axis=0)]
        accessors.append(acc)
        return len(accessors) - 1

    a_wp = add(wpos, 34962, 5126, "VEC3", True)
    a_wn = add(wnrm, 34962, 5126, "VEC3")
    a_wu = add(wuv, 34962, 5126, "VEC2")
    a_wi = add(widx, 34963, 5125, "SCALAR")
    a_lp = add(lpos, 34962, 5126, "VEC3", True)
    a_ln = add(lnrm, 34962, 5126, "VEC3")
    a_lu = add(luv, 34962, 5126, "VEC2")
    a_li = add(lidx, 34963, 5125, "SCALAR")
    img_off = sum(len(c) for c in chunks)
    chunks.append(pad4(png))
    views.append({"buffer": 0, "byteOffset": img_off, "byteLength": len(png)})
    leaf_img_view = len(views) - 1
    bark_img_view = None
    if bark_path:
        bim = Image.open(bark_path).convert("RGB").resize((256, 256), Image.LANCZOS)
        bbuf = io.BytesIO()
        bim.save(bbuf, "JPEG", quality=85)
        bpng = bbuf.getvalue()
        boff = sum(len(c) for c in chunks)
        chunks.append(pad4(bpng))
        views.append({"buffer": 0, "byteOffset": boff, "byteLength": len(bpng)})
        bark_img_view = len(views) - 1
    binc = b"".join(chunks)

    js = {
        "asset": {"version": "2.0", "generator": "tree_glb.py (Dragon Nest, 11.10.2026)"},
        "scene": 0,
        "scenes": [{"name": "tree", "nodes": [2]}],
        "nodes": [{"name": "woodBark", "mesh": 0}, {"name": "leaf", "mesh": 1}, {"name": "tree_%s" % shape, "children": [0, 1]}],
        "meshes": [
            {"name": "woodBark", "primitives": [{"attributes": {"POSITION": a_wp, "NORMAL": a_wn, "TEXCOORD_0": a_wu}, "indices": a_wi, "material": 0}]},
            {"name": "leaf", "primitives": [{"attributes": {"POSITION": a_lp, "NORMAL": a_ln, "TEXCOORD_0": a_lu}, "indices": a_li, "material": 1}]},
        ],
        "materials": [
            {"name": "woodBark", "pbrMetallicRoughness": ({"baseColorTexture": {"index": 1}, "metallicFactor": 0, "roughnessFactor": 1} if bark_img_view is not None
                                                           else {"baseColorFactor": [0.49, 0.33, 0.21, 1], "metallicFactor": 0, "roughnessFactor": 1})},
            {"name": "leaf", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 1},
             "doubleSided": True},
        ],
        "textures": [{"source": 0, "sampler": 0}] + ([{"source": 1, "sampler": 1}] if bark_img_view is not None else []),
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}, {"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
        "images": [{"bufferView": leaf_img_view, "mimeType": "image/jpeg"}] + ([{"bufferView": bark_img_view, "mimeType": "image/jpeg"}] if bark_img_view is not None else []),
        "bufferViews": views,
        "accessors": accessors,
        "buffers": [{"byteLength": len(binc)}],
    }
    jb = pad4(json.dumps(js, separators=(",", ":")).encode("utf-8"), b" ")
    total = 12 + 8 + len(jb) + 8 + len(binc)
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(binc), 0x004E4942) + binc)
    print(out, "trunk", len(widx) // 3, "tris, foliage", len(lidx) // 3, "tris, texture", len(png) // 1024, "KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tex")
    ap.add_argument("out")
    ap.add_argument("--shape", default="round", choices=list(SHAPES) + list(CONIFERS) + list(UNDERGROWTH))
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--texsize", type=int, default=512)
    ap.add_argument("--bark", default=None, help="the bark texture (tiles along the trunk)")
    a = ap.parse_args()
    build(a.tex, a.out, a.shape, a.seed, a.texsize, a.bark)


if __name__ == "__main__":
    main()
