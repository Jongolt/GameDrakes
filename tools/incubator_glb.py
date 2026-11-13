#!/usr/bin/env python3
"""The incubator bowl: a stone bowl with straw and a warm glow.
One GLB, three nodes = three MeshParts, coordinates from the bowl bottom centre on the nest floor (y = 0 -
the nest floor, as in the WorldBuilder.buildNestTemplate template):
Bowl  - the stone bowl (a turned profile with handmade unevenness, granite with moss, like the plaza circle), a low foot into the ground;
Straw - a straw bed with a pit (the egg lies in the centre at height EGG_Y) + straws along the edge and over the rim;
Runes - 8 runes on the wall and a thin ring along the rim top: by day a dark carving, at an occupied incubator they glow warm (WorldBuilder).
Writes src/shared/Core/IncubatorShape.luau (node frames, egg height, rim radius) - read by WorldBuilder.
python3 tools/incubator_glb.py [--seed 17] [--preview /tmp/incubator_side.png]
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from plaza_glb import Mesh, RUNES, box_stroke, fix_winding, grade, jpeg, write_glb  # noqa: E402

ROOT = os.path.dirname(HERE)
TEX = os.path.join(ROOT, "assets_src", "terrain_textures")
OUT_DIR = os.path.join(ROOT, "assets_src", "incubator")
SHAPE = os.path.join(ROOT, "src", "shared", "Core", "IncubatorShape.luau")

NA = 72  # samples around the circle
# the bowl profile (r, y) outside from the bottom up, over the rim, inward to the bed; y = 0 - the nest floor, the foot is sunk into the ground
PROFILE = [
    (0.0, -0.35), (1.45, -0.35), (1.55, -0.05), (1.6, 0.14), (1.78, 0.2), (2.1, 0.3), (2.32, 0.48), (2.42, 0.7),
    (2.45, 0.95), (2.44, 1.15), (2.4, 1.28), (2.33, 1.35), (2.2, 1.38), (2.02, 1.37), (1.94, 1.3), (1.9, 1.15),
    (1.86, 0.95), (1.8, 0.8),
]
STRAW_R = 1.9  # the bed up to the wall (the edge goes into the stone)
EGG_Y = 0.68  # the bottom of the bed pit - the egg sole sits at this height
DIP = 0.24  # the bed rise toward the edge: y = EGG_Y + DIP (r / 1.85)^2
LIP_Y = 1.38
RIM_R = 2.45
TILE = 3.2  # studs per stone tile
STRAW_TILE = 1.6


def straw_y(r):
    return EGG_Y + DIP * (r / 1.85) ** 2


class Wobble:
    """Handmade unevenness: a radius multiplier by angle (low harmonics) - the bowl is not perfectly round."""

    def __init__(self, rng):
        self.h = [(n, rng.uniform(0.004, 0.011), rng.uniform(0, 2 * math.pi)) for n in range(2, 8)]

    def k(self, a):
        return 1.0 + sum(amp * math.cos(n * a + ph) for n, amp, ph in self.h)


def profile_normals(prof):
    """The profile normal at (r, y) outward from the bowl body (the profile walk - the body on the left)."""
    out = []
    for i in range(len(prof)):
        a = np.array(prof[max(i - 1, 0)], float)
        b = np.array(prof[min(i + 1, len(prof) - 1)], float)
        t = b - a
        t /= max(np.linalg.norm(t), 1e-9)
        out.append(np.array([t[1], -t[0]]))  # rotate the tangent clockwise: outward
    return out


def bowl(W):
    m = Mesh("Bowl", "stone")
    nrm = profile_normals(PROFILE)
    arc = [0.0]
    for i in range(1, len(PROFILE)):
        arc.append(arc[-1] + math.dist(PROFILE[i - 1], PROFILE[i]))
    circ = 2 * math.pi * RIM_R
    ut = max(1, round(circ / TILE))
    rows = []
    for j in range(NA + 1):
        a = 2 * math.pi * j / NA
        ca, sa = math.cos(a), math.sin(a)
        k = W.k(a)
        row = []
        for i, (r, y) in enumerate(PROFILE):
            nr, ny = nrm[i]
            p = (r * k * ca, y, r * k * sa)
            n = (nr * ca, ny, nr * sa)
            row.append(m.v(p, n, (ut * j / NA, arc[i] / TILE)))
        rows.append(row)
    for j in range(NA):
        for i in range(len(PROFILE) - 1):
            a, b, c, d = rows[j][i], rows[j][i + 1], rows[j + 1][i + 1], rows[j + 1][i]
            m.tri(a, b, c)
            m.tri(a, c, d)
    fix_winding(m)
    return m


def straw(W, rng):
    m = Mesh("Straw", "straw")
    # the bed with a pit: rings from the centre to the wall
    rings = [0.0, 0.25, 0.5, 0.8, 1.1, 1.4, 1.65, STRAW_R]
    ids = []
    for ri, r in enumerate(rings):
        row = []
        cnt = 1 if r == 0 else NA
        for j in range(cnt):
            a = 2 * math.pi * j / NA
            rr = r * (W.k(a) if r >= STRAW_R else 1.0)
            x, z = rr * math.cos(a), rr * math.sin(a)
            y = straw_y(min(r, 1.85)) + (rng.uniform(-0.025, 0.025) if 0 < r < STRAW_R else 0)
            slope = 2 * DIP * r / 1.85 ** 2
            n = np.array([-slope * math.cos(a), 1.0, -slope * math.sin(a)])
            row.append(m.v((x, y, z), n, (x / STRAW_TILE, z / STRAW_TILE)))
        ids.append(row)
    for j in range(NA):
        m.tri(ids[0][0], ids[1][(j + 1) % NA], ids[1][j])
    for ri in range(1, len(rings) - 1):
        for j in range(NA):
            j2 = (j + 1) % NA
            a, b, c, d = ids[ri][j], ids[ri + 1][j], ids[ri + 1][j2], ids[ri][j2]
            m.tri(a, c, b)
            m.tri(a, d, c)
    fix_winding(m)

    def strand(pts, w):
        """A straw: a ribbon along a polyline, two sides (texture alpha does not work on import - geometry only)."""
        u0, v0 = rng.uniform(0.05, 0.95), rng.uniform(0.05, 0.6)
        P = [np.array(p, float) for p in pts]
        for s in range(len(P) - 1):
            a, b = P[s], P[s + 1]
            d = b - a
            side = np.cross(d, [0, 1, 0])
            if np.linalg.norm(side) < 1e-6:
                side = np.array([1.0, 0, 0])
            side = side / np.linalg.norm(side) * w / 2
            face = np.cross(d, side)
            face /= max(np.linalg.norm(face), 1e-9)
            if face[1] < 0:
                face = -face
            q = [a - side, a + side, b + side, b - side]
            uv = [(u0, v0 + 0.1 * s), (u0 + 0.02, v0 + 0.1 * s), (u0 + 0.02, v0 + 0.1 * (s + 1)), (u0, v0 + 0.1 * (s + 1))]
            for sgn in (1, -1):
                n = face * sgn * 0.6 + np.array([0, 0.4, 0])
                vi = [m.v(q[t], n, uv[t]) for t in range(4)]
                if sgn > 0:
                    m.tri(vi[0], vi[1], vi[2])
                    m.tri(vi[0], vi[2], vi[3])
                else:
                    m.tri(vi[0], vi[2], vi[1])
                    m.tri(vi[0], vi[3], vi[2])

    n_hang = n_up = n_flat = 0
    # over the rim outward (hanging): the base on the bed at the wall, the bend above the rim, the end outside below the rim
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        k = W.k(a)
        d = np.array([math.cos(a), 0, math.sin(a)])
        t = np.array([-d[2], 0, d[0]]) * rng.uniform(-0.25, 0.25)
        r0 = rng.uniform(1.45, 1.75)
        base = d * r0 + np.array([0, straw_y(r0) - 0.02, 0])
        top = d * (2.12 * k) + t * 0.5 + np.array([0, LIP_Y + rng.uniform(0.04, 0.12), 0])
        tip = d * (rng.uniform(2.5, 2.62) * k) + t + np.array([0, LIP_Y - rng.uniform(0.15, 0.45), 0])
        strand([base, top, tip], rng.uniform(0.05, 0.08))
        n_hang += 1
    # sticking up-outward along the bed edge (not high: at 0.3-0.6 it looks like a 'hedgehog')
    for _ in range(30):
        a = rng.uniform(0, 2 * math.pi)
        d = np.array([math.cos(a), 0, math.sin(a)])
        t = np.array([-d[2], 0, d[0]]) * rng.uniform(-0.3, 0.3)
        r0 = rng.uniform(1.25, 1.8)
        base = d * r0 + np.array([0, straw_y(r0) - 0.02, 0])
        tip = d * min(r0 + rng.uniform(0.25, 0.5), 1.92) + t + np.array([0, straw_y(r0) + rng.uniform(0.12, 0.32), 0])
        mid = (base + tip) / 2 + d * 0.06 + np.array([0, 0.04, 0])
        strand([base, mid, tip], rng.uniform(0.045, 0.07))
        n_up += 1
    # lying on the bed (they break the flat texture), not in the centre - the egg is there
    for _ in range(40):
        a = rng.uniform(0, 2 * math.pi)
        r0 = rng.uniform(0.8, 1.7)
        c = np.array([r0 * math.cos(a), 0, r0 * math.sin(a)])
        phi = rng.uniform(0, 2 * math.pi)
        e = np.array([math.cos(phi), 0, math.sin(phi)]) * rng.uniform(0.3, 0.5)
        p0, p1 = c - e, c + e
        pts = []
        for s in (0.0, 0.5, 1.0):
            p = p0 + (p1 - p0) * s
            rr = min(math.hypot(p[0], p[2]), 1.85)
            pts.append(np.array([p[0], straw_y(rr) + 0.025 + (0.03 if s == 0.5 else 0), p[2]]))
        strand(pts, rng.uniform(0.05, 0.075))
        n_flat += 1
    return m, (n_hang, n_up, n_flat)


def runes(W, rng):
    m = Mesh("Runes", "rune")
    nrm = profile_normals(PROFILE)
    # runes on the almost vertical belt of the wall (2.43/0.78 - 2.45/0.95 - 2.44/1.15): the rune plane stands off the stone by no more than 0.01
    y0, y1 = 0.78, 1.16

    def r_at(y):
        for i in range(1, 12):
            (ra, ya), (rb, yb) = PROFILE[i - 1], PROFILE[i]
            if ya <= y <= yb:
                return ra + (rb - ra) * (y - ya) / (yb - ya)
        return 2.44

    order = rng.permutation(6) + 1
    for g in range(8):
        a = 2 * math.pi * (g + 0.5) / 8
        k = W.k(a)
        d = np.array([math.cos(a), 0, math.sin(a)])
        U = np.array([-d[2], 0, d[0]])
        b0 = d * r_at(y0) * k + np.array([0, y0, 0])
        b1 = d * r_at(y1) * k + np.array([0, y1, 0])
        V = (b1 - b0) / np.linalg.norm(b1 - b0)
        N = np.cross(U, V)
        if np.dot(N, d) < 0:
            N = -N
        H = np.linalg.norm(b1 - b0)
        gw = H * 0.62
        for p1, p2 in RUNES[int(order[g % 6])]:
            box_stroke(m, b0, U, V, N, (p1[0] * gw, p1[1] * H), (p2[0] * gw, p2[1] * H), 0.055, 0.035)
    # the inlay ring along the rim top (r 2.11, width 0.07, protrusion 0.018; the bottom sunk into the stone)
    rr, w, top, low = 2.11, 0.035, LIP_Y + 0.016, LIP_Y - 0.05
    ring = []
    for j in range(NA + 1):
        a = 2 * math.pi * j / NA
        k = W.k(a)
        c, s = math.cos(a), math.sin(a)
        ri, ro = (rr - w) * k, (rr + w) * k
        ring.append([(ri * c, low, ri * s), (ri * c, top, ri * s), (ro * c, top, ro * s), (ro * c, low, ro * s), (c, s)])
    for j in range(NA):
        A, B = ring[j], ring[j + 1]
        ca, sa = A[4]
        for (i0, i1), n in (((0, 1), (-ca, 0, -sa)), ((1, 2), (0, 1, 0)), ((2, 3), (ca, 0, sa))):
            m.quad_flat([A[i0], A[i1], B[i1], B[i0]], [(0, 0)] * 4, np.array(n, float))
    return m


# ------------------------------------------------------------------------------------------------ textures
def straw_texture(rng, S=512):
    im = Image.new("RGB", (S, S), (118, 84, 40))
    dr = ImageDraw.Draw(im)
    pal = [(214, 170, 84), (232, 196, 110), (190, 140, 60), (243, 216, 142), (168, 118, 48), (226, 182, 92)]
    for layer, (count, wmin, wmax) in enumerate([(900, 3, 5), (1400, 2, 4), (900, 1, 3)]):
        for _ in range(count):
            x, y = rng.uniform(0, S), rng.uniform(0, S)
            phi = rng.uniform(0, math.pi)
            L = rng.uniform(25, 95)
            dx, dy = math.cos(phi) * L, math.sin(phi) * L
            col = pal[int(rng.integers(len(pal)))]
            sh = 0.78 + 0.11 * layer + rng.uniform(-0.06, 0.06)
            col = tuple(int(max(0, min(255, c * sh))) for c in col)
            w = int(rng.integers(wmin, wmax + 1))
            for ox in (-S, 0, S):  # seamless: the segment and its copies across the edges
                for oy in (-S, 0, S):
                    dr.line([(x + ox, y + oy), (x + dx + ox, y + dy + oy)], fill=col, width=w)
    return im.filter(ImageFilter.GaussianBlur(0.6))


def textures(rng):
    gran = grade(Image.open(os.path.join(TEX, "granite_moss_color.png")), 0.92, 0.08).resize((512, 512), Image.LANCZOS)
    a = np.asarray(gran).astype(np.float32) * np.array([1.04, 1.0, 0.93])  # slightly warmer than the plaza circle
    gran = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    nmap = Image.open(os.path.join(TEX, "granite_moss_normal.png")).convert("RGB").resize((512, 512))
    st = straw_texture(rng)
    os.makedirs(OUT_DIR, exist_ok=True)
    st.save(os.path.join(OUT_DIR, "straw_color.png"))
    return {"stone": (jpeg(gran), jpeg(nmap, 90)), "straw": (jpeg(st, 90), None)}


# ------------------------------------------------------------------------------------------------ output
def write_shape(nodes):
    lines = ["--!strict",
             "-- GENERATED by tools/incubator_glb.py (17.10.2026: the incubator bowl) - do not edit by hand, rerun the generator.",
             "-- The mesh nodes (the center and the frame size in studs from the bowl bottom center on the nest floor), the egg sole height on the bed,",
             "-- the rim top and radius. Pure data: read by WorldBuilder.",
             "",
             "local IncubatorShape = {}",
             "",
             "IncubatorShape.eggY = %s -- the egg sole (the bottom of the bed pit) above the nest floor" % EGG_Y,
             "IncubatorShape.lipY = %s -- the rim top" % LIP_Y,
             "IncubatorShape.rimR = %s -- the outer bowl radius" % RIM_R,
             "IncubatorShape.nodes = {"]
    for name, (c, s) in nodes.items():
        lines.append("\t%s = { c = { %.3f, %.3f, %.3f }, s = { %.3f, %.3f, %.3f } }," % (name, *c, *s))
    lines += ["}", "", "return IncubatorShape", ""]
    open(SHAPE, "w", encoding="utf-8").write("\n".join(lines))


def preview(path, meshes):
    """A side view 25 degrees from above, flat shading by illumination (a shape check before the upload)."""
    S, sc = 900, 150
    im = Image.new("RGB", (S, S), (150, 190, 120))
    dr = ImageDraw.Draw(im)
    col = {"stone": (150, 150, 140), "straw": (220, 180, 90), "rune": (255, 150, 60)}
    el = math.radians(25)
    light = np.array([0.4, 0.8, -0.45])
    light /= np.linalg.norm(light)
    tris = []
    for m in meshes:
        P = np.array(m.p)
        for t in range(0, len(m.idx), 3):
            tri = [P[m.idx[t + i]] for i in range(3)]
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            ln = np.linalg.norm(n)
            if ln < 1e-12:
                continue
            n /= ln
            view = np.array([0, math.sin(el), -math.cos(el)])
            if np.dot(n, view) <= 0:
                continue
            pts, depth = [], 0
            for p in tri:
                y2 = p[1] * math.cos(el) + p[2] * math.sin(el)  # the screen 'up' axis (0, cos, sin)
                z2 = -p[1] * math.sin(el) + p[2] * math.cos(el)  # depth along the view (0, -sin, cos)
                pts.append((S / 2 + p[0] * sc, S * 0.62 - y2 * sc))
                depth += z2
            sh = 0.45 + 0.55 * max(0.0, float(np.dot(n, light)))
            c = tuple(int(x * sh) for x in col[m.material])
            tris.append((depth, pts, c))
    for _, pts, c in sorted(tris, key=lambda t: -t[0]):
        dr.polygon(pts, fill=c)
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=17)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    W = Wobble(rng)
    meshes = [bowl(W)]
    sm, counts = straw(W, rng)
    meshes.append(sm)
    meshes.append(runes(W, rng))
    tex = textures(rng)
    out = os.path.join(OUT_DIR, "incubator.glb")
    size = write_glb(out, meshes, tex, mat_names=["stone", "straw", "rune"], plain={"rune": (0.3, 0.27, 0.24)})
    nodes = {}
    for m in meshes:
        lo, hi = m.bbox()
        nodes[m.name] = ((lo + hi) / 2, hi - lo)
    write_shape(nodes)
    print("straws: over the rim %d, along the edge %d, on the bed %d" % counts)
    for m in meshes:
        lo, hi = m.bbox()
        print("%-6s triangles %5d, frame %s..%s" % (m.name, len(m.idx) // 3, lo.round(2), hi.round(2)))
    print("GLB %d KB -> %s" % (size // 1024, out))
    if a.preview:
        preview(a.preview, meshes)


if __name__ == "__main__":
    main()
