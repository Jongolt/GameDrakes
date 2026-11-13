#!/usr/bin/env python3
"""The Old Ash plaza: a clay glade with an uneven outline (the edge goes
under the grass), an ancient circle of worn slabs with moss in the cracks and a broken edge, paths of worn slabs to the 6 stairs, 6 standing
marker stones with runes at the nest entrances. One GLB, node = MeshPart, vertices in Roblox world coordinates (the plaza centre 0,0;
the angle as Layout.dir: x = r cos a, z = -r sin a). The glade - 36 sector chunks of an almost convex shape: the Roblox collisions
(convex hulls) follow the surface, the camera does not go under the clay (rings without collisions let it through).
Writes src/shared/Core/PlazaShape.luau (outline, nodes, heights) - read by Island (the grass at the rim) and WorldBuilder.
python3 tools/plaza_glb.py [--seed 16] [--preview /tmp/plaza_top.png]
"""
import argparse
import io
import json
import math
import os
import struct

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX = os.path.join(ROOT, "assets_src", "terrain_textures")
OUT_DIR = os.path.join(ROOT, "assets_src", "plaza")
SHAPE = os.path.join(ROOT, "src", "shared", "Core", "PlazaShape.luau")

GRASS = 18.0  # the plateau grass (the terrain is drawn exactly at 18.0 with wallTop 16)
TOP = 18.45  # the clay top at the start of the rim
DOME = 0.12  # the centre is higher by this much (a gentle dome)
RIM = 3.0  # the width of the rim going under the grass
SKIRT = 1.4  # the skirt beyond the outline (under the grass)
DROP = 1.2  # the rim drop to the end of the skirt
POW = 3.0  # the rim profile (y -= DROP * u^POW): steeper at the grass - a narrower 'clay right above the grass' strip (v1: 0.5 studs)
BOTTOM = 17.25  # the bottom of the glade chunks
TILE = 22.0  # studs per clay tile
STEP = 2.5  # the outline step, degrees
NEST_ANGLES = [0, 60, 120, 180, 240, 300]
STAIRS_ANGLES = [30, 90, 150, 210, 270, 330]
STALL_FRONT = 38.5  # the stall (0, 18, -40), a counter 3 deep - the path at 90 deg. ends in front of it
LOT_INNER, LOT_HALF = 60.0, 28.0  # the nest petals (Config.World.nests: rInner 60, lotWidth 56)


def dirv(a_deg):
    a = math.radians(a_deg)
    return np.array([math.cos(a), -math.sin(a)])


def angdiff(a, b):
    return (a - b + 180.0) % 360.0 - 180.0


# ------------------------------------------------------------------------------------------------ outline
class Contour:
    def __init__(self, rng):
        self.lobes = [(s + rng.uniform(-2.5, 2.5), rng.uniform(8.0, 10.5), rng.uniform(7.0, 10.0)) for s in STAIRS_ANGLES]
        self.harm = [(n, 1.1 / math.sqrt(n), rng.uniform(0, 2 * math.pi)) for n in range(4, 14)]
        self.fine = [(n, 0.22, rng.uniform(0, 2 * math.pi)) for n in range(17, 32, 2)]
        n = int(round(360 / STEP))
        self.radii = np.array([self._raw(i * STEP) for i in range(n)])

    def _raw(self, a):
        r = 49.0
        for c, L, w in self.lobes:
            r += L * math.exp(-(angdiff(a, c) / w) ** 2)  # the paths to the stairs trampled the glade into tongues
        for c in NEST_ANGLES:
            r += 3.5 * math.exp(-(angdiff(a, c) / 14.0) ** 2)  # and to the nest entrances
        t = math.radians(a)
        for n, amp, ph in self.harm + self.fine:
            r += amp * math.cos(n * t + ph)
        return r

    def r(self, a):
        a = a % 360.0
        i = a / STEP
        i0 = int(math.floor(i)) % len(self.radii)
        i1 = (i0 + 1) % len(self.radii)
        f = i - math.floor(i)
        return self.radii[i0] * (1 - f) + self.radii[i1] * f


def theta_of(x, z):
    return math.degrees(math.atan2(-z, x)) % 360.0


def height(C, x, z):
    """The clay top at the point (x, z): the dome + a concave rim (a concave profile - a convex body for collisions)."""
    r = math.hypot(x, z)
    rc = C.r(theta_of(x, z))
    r0 = rc - RIM
    y = TOP + DOME * (1 - (r / rc) ** 2)
    if r > r0:
        y -= DROP * ((r - r0) / (rc + SKIRT - r0)) ** POW
    return y


def normal_at(C, x, z, e=0.05):
    dx = (height(C, x + e, z) - height(C, x - e, z)) / (2 * e)
    dz = (height(C, x, z + e) - height(C, x, z - e)) / (2 * e)
    n = np.array([-dx, 1.0, -dz])
    return n / np.linalg.norm(n)


# ------------------------------------------------------------------------------------------------ mesh
class Mesh:
    def __init__(self, name, material):
        self.name, self.material = name, material
        self.p, self.n, self.uv, self.idx = [], [], [], []

    def v(self, p, n, uv):
        self.p.append([float(p[0]), float(p[1]), float(p[2])])
        self.n.append([float(n[0]), float(n[1]), float(n[2])])
        self.uv.append([float(uv[0]), float(uv[1])])
        return len(self.p) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    def quad_flat(self, pts, uvs, out=None):
        """A flat quad, the normal by geometry; out - the outward direction (the face is turned toward it)."""
        p = [np.array(q, float) for q in pts]
        uvs = list(uvs)
        n = np.cross(p[1] - p[0], p[2] - p[0])
        if np.linalg.norm(n) < 1e-9:
            n = np.cross(p[2] - p[0], p[3] - p[0])
        n = n / max(np.linalg.norm(n), 1e-9)
        if out is not None and np.dot(n, out) < 0:
            p, uvs, n = p[::-1], uvs[::-1], -n
        ids = [self.v(p[i], n, uvs[i]) for i in range(4)]
        self.tri(ids[0], ids[1], ids[2])
        self.tri(ids[0], ids[2], ids[3])

    def bbox(self):
        a = np.array(self.p)
        return a.min(0), a.max(0)


def fix_winding(m):
    """Triangles facing along the vertex normals (Roblox draws one side)."""
    P, N = np.array(m.p), np.array(m.n)
    idx = m.idx
    for t in range(0, len(idx), 3):
        a, b, c = idx[t:t + 3]
        fn = np.cross(P[b] - P[a], P[c] - P[a])
        if np.dot(fn, N[a] + N[b] + N[c]) < 0:
            idx[t + 1], idx[t + 2] = c, b


def clay_piece(C, k, per=4):
    """Glade sector k: the top by height(), the skirt under the grass, the side walls and the bottom - a closed body."""
    m = Mesh("Clay%02d" % (k + 1), "clay")
    a0 = k * per * STEP
    angs = [a0 + j * STEP for j in range(per + 1)]
    ts = [0.0, 0.14, 0.28, 0.42, 0.56, 0.7]
    us = [0.0, 0.25, 0.45, 0.6, 0.72, 0.82, 0.9, 0.96, 1.0, 1.1, 1.22, (RIM + SKIRT) / RIM]
    rows = []  # rows[i][j] = (x, z) by radial levels
    for a in angs:
        rc = C.r(a)
        d = dirv(a)
        r0 = rc - RIM
        rad = [r0 * (t / 0.7) * 0.86 for t in ts]  # inner levels up to 0.86 r0
        rad += [r0 + u * RIM for u in us]
        rows.append([(d[0] * rr, d[1] * rr) for rr in rad])
    nr = len(rows[0])
    grid = [[None] * nr for _ in angs]
    for j in range(len(angs)):
        for i in range(nr):
            x, z = rows[j][i]
            if i == 0:
                x, z = 0.0, 0.0
            y = height(C, x, z)
            grid[j][i] = m.v((x, y, z), normal_at(C, x, z), (x / TILE, z / TILE))
    for j in range(len(angs) - 1):
        for i in range(nr - 1):
            a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]
            if i == 0:
                m.tri(a, b, c)
            else:
                m.tri(a, b, c)
                m.tri(a, c, d)
    # the outer skirt wall down to the bottom
    for j in range(len(angs) - 1):
        p1, p2 = m.p[grid[j][nr - 1]], m.p[grid[j + 1][nr - 1]]
        out = np.array([p1[0] + p2[0], 0, p1[2] + p2[2]])
        m.quad_flat([(p1[0], BOTTOM, p1[2]), (p2[0], BOTTOM, p2[2]), p2, p1],
                    [(0, 0), (0.1, 0), (0.1, 0.05), (0, 0.05)], out)
    # the side walls along the radii a0 and a1 (a solid body)
    amid = dirv((angs[0] + angs[-1]) / 2)
    for j in (0, len(angs) - 1):
        for i in range(nr - 1):
            p1, p2 = m.p[grid[j][i]], m.p[grid[j][i + 1]]
            mx, mz = (p1[0] + p2[0]) / 2, (p1[2] + p2[2]) / 2
            rr = math.hypot(mx, mz)
            out = np.array([mx - amid[0] * rr, 0, mz - amid[1] * rr])
            m.quad_flat([(p1[0], BOTTOM, p1[2]), (p2[0], BOTTOM, p2[2]), p2, p1], [(0, 0), (0.1, 0), (0.1, 0.05), (0, 0.05)], out)
    # the bottom: a fan from the centre over the outer skirt points
    c0 = m.v((0, BOTTOM, 0), (0, -1, 0), (0, 0))
    for j in range(len(angs) - 1):
        p1, p2 = m.p[grid[j][nr - 1]], m.p[grid[j + 1][nr - 1]]
        a = m.v((p1[0], BOTTOM, p1[2]), (0, -1, 0), (p1[0] / TILE, p1[2] / TILE))
        b = m.v((p2[0], BOTTOM, p2[2]), (0, -1, 0), (p2[0] / TILE, p2[2] / TILE))
        m.tri(c0, a, b)
    fix_winding(m)
    # convexity in plan: the share of the hull area above the polygon
    poly = [(0.0, 0.0)] + [rows[j][nr - 1] for j in range(len(angs))]
    return m, hull_excess(poly)


def poly_area(pts):
    s = 0.0
    for i in range(len(pts)):
        x1, z1 = pts[i]
        x2, z2 = pts[(i + 1) % len(pts)]
        s += x1 * z2 - x2 * z1
    return abs(s) / 2


def convex_hull(pts):
    pts = sorted(set(pts))
    if len(pts) <= 2:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lo, hi = [], []
    for p in pts:
        while len(lo) >= 2 and cross(lo[-2], lo[-1], p) <= 0:
            lo.pop()
        lo.append(p)
    for p in reversed(pts):
        while len(hi) >= 2 and cross(hi[-2], hi[-1], p) <= 0:
            hi.pop()
        hi.append(p)
    return lo[:-1] + hi[:-1]


def hull_excess(poly):
    return poly_area(convex_hull(poly)) - poly_area(poly)


# ------------------------------------------------------------------------------------------------ slabs
def offset_convex(poly, g):
    """Offsetting a convex polygon (counterclockwise in the x-z plan... by the area sign) inward by g."""
    n = len(poly)
    s = sum(poly[i][0] * poly[(i + 1) % n][1] - poly[(i + 1) % n][0] * poly[i][1] for i in range(n))
    sign = 1.0 if s > 0 else -1.0
    lines = []
    for i in range(n):
        p, q = np.array(poly[i]), np.array(poly[(i + 1) % n])
        d = q - p
        L = np.linalg.norm(d)
        if L < 1e-6:
            continue
        d /= L
        inward = np.array([-d[1], d[0]]) * sign
        lines.append((p + inward * g, d))
    out = []
    for i in range(len(lines)):
        p1, d1 = lines[i - 1]
        p2, d2 = lines[i]
        den = d1[0] * d2[1] - d1[1] * d2[0]
        if abs(den) < 1e-9:
            out.append(tuple(p2))
            continue
        t = ((p2[0] - p1[0]) * d2[1] - (p2[1] - p1[1]) * d2[0]) / den
        out.append(tuple(p1 + d1 * t))
    return out


SLAB_TOPS = []  # (polygon, top function) - a sample for the collision probe
PLACED = []  # the slabs in plan (convex polygons): new ones must not overlap (tops close in height flicker)


def overlaps(a, b, eps=0.06):
    """Intersection of convex polygons (the separating axis theorem) with a margin eps."""
    for poly in (a, b):
        for i in range(len(poly)):
            x1, z1 = poly[i]
            x2, z2 = poly[(i + 1) % len(poly)]
            nx, nz = z1 - z2, x2 - x1
            L = math.hypot(nx, nz) or 1.0
            nx, nz = nx / L, nz / L
            pa = [x * nx + z * nz for x, z in a]
            pb = [x * nx + z * nz for x, z in b]
            if max(pa) + eps < min(pb) or max(pb) + eps < min(pa):
                return False
    return True


def free(poly):
    return not any(overlaps(poly, q) for q in PLACED)


def chip(poly, rng, prob):
    if rng.random() >= prob or len(poly) > 9:
        return poly
    i = rng.integers(len(poly))
    p = np.array(poly[i])
    a, b = np.array(poly[i - 1]), np.array(poly[(i + 1) % len(poly)])
    c = rng.uniform(0.35, 0.8)
    pa = p + (a - p) / max(np.linalg.norm(a - p), 1e-6) * min(c, np.linalg.norm(a - p) * 0.4)
    pb = p + (b - p) / max(np.linalg.norm(b - p), 1e-6) * min(c, np.linalg.norm(b - p) * 0.4)
    return poly[:i] + [tuple(pa), tuple(pb)] + poly[i + 1:]


def slab(m, C, poly, rng, lift, bevel, cham, tilt, sink=0.4, uv_scale=14.0):
    """A slab: the top (bevelled at the edge), walls down to the clay and below - moss. poly - a convex polygon (x, z)."""
    poly = [tuple(p) for p in poly]
    PLACED.append(poly)
    n = len(poly)
    cx = sum(p[0] for p in poly) / n
    cz = sum(p[1] for p in poly) / n
    base_top = max(height(C, x, z) for x, z in poly) + lift
    ax, az = rng.uniform(-tilt, tilt), rng.uniform(-tilt, tilt)

    def ytop(x, z):
        return base_top + ax * (x - cx) + az * (z - cz)

    inner = offset_convex(poly, bevel)
    if len(inner) != n:  # a degenerate edge - without a bevel
        inner = list(poly)
    rot = rng.uniform(0, 2 * math.pi)
    cr, sr = math.cos(rot), math.sin(rot)
    ou, ov = rng.uniform(0, 0.4), rng.uniform(0, 0.4)

    def uv_top(x, z):
        lx, lz = (x - cx) * cr - (z - cz) * sr, (x - cx) * sr + (z - cz) * cr
        u = min(max(lx / uv_scale + 0.3 + ou, 0.01), 0.99)
        v = min(max(lz / uv_scale + 0.3 + ov, 0.01), 0.99)
        return (u, v * 0.74)

    if m.name == "Circle":
        SLAB_TOPS.append((poly, ytop))
    tn = np.array([-ax, 1.0, -az])
    tn /= np.linalg.norm(tn)
    # the top: a fan from the centre over the inner polygon
    c = m.v((cx, ytop(cx, cz), cz), tn, uv_top(cx, cz))
    ids = [m.v((x, ytop(x, z), z), tn, uv_top(x, z)) for x, z in inner]
    for i in range(len(ids)):
        m.tri(c, ids[i], ids[(i + 1) % len(ids)])
    # the bevel: the inner outline (vertex i at the outer vertex i - offset keeps the edge order) down-outward to the outer one
    for i in range(n):
        j = (i + 1) % n
        (x1, z1), (x2, z2) = inner[i], inner[j]
        (X1, Z1), (X2, Z2) = poly[i], poly[j]
        q = [(X1, ytop(X1, Z1) - cham, Z1), (X2, ytop(X2, Z2) - cham, Z2), (x2, ytop(x2, z2), z2), (x1, ytop(x1, z1), z1)]
        out = np.array([(X1 + X2) / 2 - cx, 1.0, (Z1 + Z2) / 2 - cz])
        m.quad_flat(q, [uv_top(X1, Z1), uv_top(X2, Z2), uv_top(x2, z2), uv_top(x1, z1)], out)
    # walls down to the clay and below (moss in the cracks)
    per = 0.0
    for i in range(n):
        j = (i + 1) % n
        (X1, Z1), (X2, Z2) = poly[i], poly[j]
        L = math.hypot(X2 - X1, Z2 - Z1)
        y1b, y2b = height(C, X1, Z1) - sink, height(C, X2, Z2) - sink
        q = [(X1, y1b, Z1), (X2, y2b, Z2), (X2, ytop(X2, Z2) - cham, Z2), (X1, ytop(X1, Z1) - cham, Z1)]
        out = np.array([(X1 + X2) / 2 - cx, 0.0, (Z1 + Z2) / 2 - cz])
        m.quad_flat(q, [(per / 4, 0.99), ((per + L) / 4, 0.99), ((per + L) / 4, 0.77), (per / 4, 0.77)], out)
        per += L
    return base_top


def circle_slabs(C, rng):
    m = Mesh("Circle", "slab")
    bands = [(3.6, 7.6), (7.9, 12.0), (12.3, 16.4), (16.7, 20.6)]
    drop = [0.0, 0.04, 0.08, 0.38]
    tops = []

    def rb(r, a, ph):
        t = math.radians(a)
        return r + 0.55 * math.sin(3 * t + ph) + 0.35 * math.sin(7 * t + 2 * ph) + 0.2 * math.sin(13 * t + 3 * ph)

    phases = [rng.uniform(0, 6.28) for _ in range(len(bands) + 1)]
    # the central slab
    cen = []
    for i in range(7):
        a = i * 360 / 7 + rng.uniform(-12, 12)
        rr = 3.1 + rng.uniform(-0.25, 0.25)
        d = dirv(a)
        cen.append((d[0] * rr, d[1] * rr))
    tops.append(slab(m, C, offset_convex(cen, 0.15), rng, 0.34, 0.18, 0.1, 0.006))
    for b, (r1, r2) in enumerate(bands):
        mid = (r1 + r2) / 2
        nb = max(6, int(round(2 * math.pi * mid / ((r2 - r1) * 1.25))))
        # assorted: slab width 0.55-1.6 of the average, sometimes two neighbours - one long slab
        w = rng.uniform(0.55, 1.6, nb)
        w = w / w.sum() * 360
        off = rng.uniform(0, 360)
        bounds = list(off + np.concatenate([[0], np.cumsum(w)[:-1]]))
        j = 0
        cells = []
        while j < nb:
            span = 2 if (j < nb - 1 and rng.random() < 0.14 and w[j] + w[j + 1] < 2.2 * 360 / nb) else 1
            cells.append((bounds[j], bounds[j] + sum(w[j:j + span])))
            j += span
        for aa, ab in cells:
            if rng.random() < drop[b]:
                continue
            am = (aa + ab) / 2
            ri_a, ri_b = rb(r1, aa, phases[b]), rb(r1, ab, phases[b])
            ro_a, ro_m, ro_b = rb(r2, aa, phases[b + 1]), rb(r2, am, phases[b + 1]), rb(r2, ab, phases[b + 1])
            if b == len(bands) - 1:  # the broken edge
                ro_a -= rng.uniform(0, 1.3)
                ro_m -= rng.uniform(0, 1.0)
                ro_b -= rng.uniform(0, 1.3)
            pts = []
            for a, r in ((aa, ri_a), (ab, ri_b), (ab, ro_b), (am, ro_m), (aa, ro_a)):
                d = dirv(a)
                pts.append((d[0] * r, d[1] * r))
            pts = convex_hull(pts)
            pts = offset_convex(pts, rng.uniform(0.14, 0.2))
            pts = chip(pts, rng, 0.28)
            # shifted over the centuries: a rotation around the centre by +-2.5 degrees
            cxp, czp = sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)
            rot = math.radians(rng.uniform(-2.5, 2.5))
            turned = [(cxp + (x - cxp) * math.cos(rot) - (z - czp) * math.sin(rot), czp + (x - cxp) * math.sin(rot) + (z - czp) * math.cos(rot)) for x, z in pts]
            if free(turned):
                pts = turned
            elif not free(pts):
                continue
            tops.append(slab(m, C, pts, rng, rng.uniform(0.3, 0.42), 0.18, 0.1, 0.02))
    # fragments beyond the circle edge
    for _ in range(5):
        for _try in range(20):
            a = rng.uniform(0, 360)
            if min(abs(angdiff(a, s)) for s in STAIRS_ANGLES) > 9:
                break
        r = rng.uniform(21.5, 25.0)
        d = dirv(a)
        sz = rng.uniform(1.2, 2.2)
        pts = []
        for i in range(5):
            aa = i * 72 + rng.uniform(-15, 15)
            dd = dirv(aa)
            pts.append((d[0] * r + dd[0] * sz * rng.uniform(0.7, 1.0), d[1] * r + dd[1] * sz * rng.uniform(0.7, 1.0)))
        pts = convex_hull(pts)
        if free(pts):
            slab(m, C, pts, rng, rng.uniform(0.1, 0.25), 0.15, 0.08, 0.12, sink=0.5)
    fix_winding(m)
    return m, max(tops)


def trail(C, rng, k):
    s = STAIRS_ANGLES[k]
    m = Mesh("Trail%d" % (k + 1), "slab")
    d, l = dirv(s), dirv(s + 90)
    r_end = STALL_FRONT - 2.0 if s == 90 else C.r(s) - 3.2
    ph = rng.uniform(0, 6.28)
    r = 22.8
    while r < r_end:
        along = rng.uniform(1.7, 2.3)
        across = rng.uniform(2.0, 3.0)
        lat = 0.7 * math.sin(r / 7 + ph) + rng.uniform(-0.3, 0.3)
        rot = math.radians(rng.uniform(-12, 12))
        parts = [(lat, across)]
        if rng.random() < 0.2:
            parts = [(lat - across * 0.27, across * 0.46), (lat + across * 0.27, across * 0.46)]
        for lt, ac in parts:
            cxz = d * (r + along / 2) + l * lt
            pts = []
            for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                u = su * along / 2 + rng.uniform(-0.15, 0.15)
                v = sv * ac / 2 + rng.uniform(-0.15, 0.15)
                ru = u * math.cos(rot) - v * math.sin(rot)
                rv = u * math.sin(rot) + v * math.cos(rot)
                p = cxz + d * ru + l * rv
                pts.append((p[0], p[1]))
            pts = convex_hull(pts)
            pts = chip(pts, rng, 0.3)
            if free(pts):
                slab(m, C, pts, rng, rng.uniform(0.16, 0.24), 0.12, 0.07, 0.015, sink=0.3, uv_scale=12.0)
        r += along + rng.uniform(0.7, 1.2)
    fix_winding(m)
    return m


# ------------------------------------------------------------------------------------------------ grass in the cracks
def inside_convex(poly, x, z):
    sgn = 0
    for i in range(len(poly)):
        x1, z1 = poly[i]
        x2, z2 = poly[(i + 1) % len(poly)]
        c = (x2 - x1) * (z - z1) - (z2 - z1) * (x - x1)
        if abs(c) < 1e-12:
            continue
        if sgn == 0:
            sgn = 1 if c > 0 else -1
        elif (c > 0) != (sgn > 0):
            return False
    return True


def dist_poly(poly, x, z):
    best = 1e9
    for i in range(len(poly)):
        ax, az = poly[i]
        bx, bz = poly[(i + 1) % len(poly)]
        dx, dz = bx - ax, bz - az
        t = max(0.0, min(1.0, ((x - ax) * dx + (z - az) * dz) / max(dx * dx + dz * dz, 1e-9)))
        best = min(best, math.hypot(x - ax - t * dx, z - az - t * dz))
    return best


def blades(m, C, rng, x, z, n, hmin, hmax):
    """A tuft of grass blades: thin triangles on both sides (texture alpha does not work on GLB import - geometry only)."""
    y = height(C, x, z) - 0.05
    col = rng.uniform(0.04, 0.96)
    for _ in range(n):
        phi = rng.uniform(0, 2 * math.pi)
        lean = math.radians(rng.uniform(12, 38))
        h = rng.uniform(hmin, hmax)
        w = rng.uniform(0.07, 0.12)
        ox, oz = x + rng.uniform(-0.18, 0.18), z + rng.uniform(-0.18, 0.18)
        d = np.array([math.cos(phi), 0, math.sin(phi)])
        perp = np.array([-d[2], 0, d[0]])
        base = np.array([ox, y, oz])
        tip = base + d * math.sin(lean) * h + np.array([0, math.cos(lean) * h, 0])
        a, b = base + perp * w, base - perp * w
        face = np.cross(b - a, tip - a)
        face /= np.linalg.norm(face)
        u = min(max(col + rng.uniform(-0.03, 0.03), 0.01), 0.99)
        for sgn in (1, -1):
            nrm = np.array([0, 0.85, 0]) + face * 0.35 * sgn
            nrm /= np.linalg.norm(nrm)
            i0 = m.v(a, nrm, (u, 0.98))
            i1 = m.v(b, nrm, (u, 0.98))
            i2 = m.v(tip, nrm, (u, 0.03))
            if sgn > 0:
                m.tri(i0, i1, i2)
            else:
                m.tri(i0, i2, i1)


def tufts(C, rng, stones):
    """Grass and moss in the circle cracks, at the path slabs and at the feet of the marker stones (spec 04 Add. 2.8: 'moss and grass in the cracks')."""
    m = Mesh("Tufts", "tuft")
    n_gap = n_trail = 0
    for _ in range(9000):
        if n_gap >= 70:
            break
        a, r = rng.uniform(0, 360), math.sqrt(rng.uniform(3.4 ** 2, 21.5 ** 2))
        d = dirv(a)
        x, z = d[0] * r, d[1] * r
        if any(inside_convex(q, x, z) for q in PLACED):
            continue
        if min(dist_poly(q, x, z) for q in PLACED) > 0.3:
            continue
        blades(m, C, rng, x, z, int(rng.integers(5, 9)), 0.3, 0.65)
        n_gap += 1
    for _ in range(9000):
        if n_trail >= 45:
            break
        a = STAIRS_ANGLES[int(rng.integers(6))] + rng.uniform(-4, 4)
        r = rng.uniform(23, 56)
        d = dirv(a)
        x, z = d[0] * r, d[1] * r
        if r > C.r(a) - 2.5 or any(inside_convex(q, x, z) for q in PLACED):
            continue
        if min(dist_poly(q, x, z) for q in PLACED) > 0.45:
            continue
        blades(m, C, rng, x, z, int(rng.integers(6, 11)), 0.4, 0.85)
        n_trail += 1
    for st in stones:
        cx, cz = st["pos"][0], st["pos"][2]
        for _ in range(7):
            a, r = rng.uniform(0, 360), rng.uniform(1.5, 2.4)
            d = dirv(a)
            blades(m, C, rng, cx + d[0] * r, cz + d[1] * r, int(rng.integers(7, 12)), 0.5, 1.1)
    return m, n_gap, n_trail


# ------------------------------------------------------------------------------------------------ stones and runes
RUNES = {  # our own glyphs in the futhark spirit (public domain): segments in the frame u [-0.5, 0.5], v [0, 1]
    1: [((-0.25, 0), (-0.25, 1)), ((-0.25, 0.95), (0.35, 0.7)), ((-0.25, 0.62), (0.35, 0.37))],
    2: [((-0.3, 0), (-0.3, 1)), ((-0.3, 1), (0.32, 0.7)), ((0.32, 0.7), (0.32, 0))],
    3: [((-0.2, 0), (-0.2, 1)), ((-0.2, 0.76), (0.32, 0.5)), ((0.32, 0.5), (-0.2, 0.24))],
    4: [((0, 0), (0, 1)), ((0, 0.55), (-0.4, 0.95)), ((0, 0.55), (0.4, 0.95))],
    5: [((0, 1), (0.32, 0.66)), ((0, 1), (-0.32, 0.66)), ((0.32, 0.66), (-0.32, 0.0)), ((-0.32, 0.66), (0.32, 0.0))],
    6: [((-0.4, 0), (-0.4, 1)), ((0.4, 0), (0.4, 1)), ((-0.4, 1), (0.4, 0)), ((-0.4, 0), (0.4, 1))],
}


def box_stroke(m, origin, U, V, N, p1, p2, w, depth):
    """A rune bar on a face: p1, p2 in the face axes (U sideways, V up), N outward; protrusion depth, sunk by 0.04."""
    a, b = np.array(p1, float), np.array(p2, float)
    d = b - a
    L = np.linalg.norm(d)
    d /= L
    side = np.array([-d[1], d[0]]) * w / 2
    a2, b2 = a - d * w / 2, b + d * w / 2  # the ends with a margin - joints without holes
    corners2 = [a2 - side, b2 - side, b2 + side, a2 + side]
    pts = []
    for zoff in (-0.04, depth):
        for c in corners2:
            pts.append(origin + U * c[0] + V * c[1] + N * zoff)
    P = pts
    bc = sum(P) / 8
    faces = [(4, 5, 6, 7), (0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    for f in faces:
        q = [P[i] for i in f]
        m.quad_flat(q, [(0, 0)] * 4, sum(q) / 4 - bc)


def waystone(C, rng, k):
    a = NEST_ANGLES[k]
    d = dirv(a)
    yaw = math.atan2(math.cos(math.radians(a)), -math.sin(math.radians(a)))
    right = np.array([math.cos(yaw), -math.sin(yaw)])  # the petal RightVector (Layout.localToWorld)
    pos = d * 47.5 + right * 7.5
    ground = height(C, pos[0], pos[1])
    H = rng.uniform(6.8, 8.2)
    y0 = ground - 1.2
    Hf = H + 1.2
    W, D, WF = rng.uniform(1.25, 1.45), rng.uniform(0.65, 0.85), 1.05
    lean_out = math.tan(math.radians(rng.uniform(3, 5)))
    lean_side = math.tan(math.radians(rng.uniform(-2.5, 2.5)))
    slant = rng.uniform(0.25, 0.45) * (1 if rng.random() < 0.5 else -1)
    # the stone axes: f - outward from the centre (toward the nest), s - sideways; the front face (toward the centre) at -D
    f = np.array([d[0], d[1]])
    s = np.array([-d[1], d[0]])
    # the section: right front -> right side -> back -> left side -> left front; the edge left -> right front = the face with the rune
    sec = [(WF, -D)]
    for i in range(5):
        t = math.pi * (i + 0.5) / 5
        sec.append((W * math.cos(t) * rng.uniform(0.9, 1.05), D * math.sin(t) * rng.uniform(0.85, 1.1) + 0.05))
    sec.append((-WF, -D))
    rings = []
    levels = [0.0, 0.18, 0.45, 0.75, 1.0]
    for lv in levels:
        y = y0 + Hf * lv
        sc = 1 - 0.26 * lv
        shift = f * (Hf * lv * lean_out) + s * (Hf * lv * lean_side)
        ring = []
        for i, (u, w) in enumerate(sec):
            jit = 1.0 if i in (0, len(sec) - 1) else rng.uniform(0.94, 1.06)
            uu, ww = u * sc * jit, w * sc * (jit if i not in (0, len(sec) - 1) else 1.0)
            if i in (0, len(sec) - 1):
                ww = -D * sc
            xz = pos + s * uu + f * ww + shift
            yy = y
            if lv == 1.0:
                yy = y + slant * (u / W)  # a slanted broken top
            ring.append(np.array([xz[0], yy, xz[1]]))
        rings.append(ring)
    m = Mesh("Stone%d" % (k + 1), "stone")
    nsec = len(sec)
    cen = sum(rings[0]) / nsec
    cen_top = sum(rings[-1]) / nsec
    for li in range(len(rings) - 1):
        r1, r2 = rings[li], rings[li + 1]
        per = 0.0
        for i in range(nsec):
            j = (i + 1) % nsec
            L = np.linalg.norm(r1[j] - r1[i])
            q = [r1[i], r1[j], r2[j], r2[i]]
            uv = [(per / 6, -r1[i][1] / 6), ((per + L) / 6, -r1[j][1] / 6), ((per + L) / 6, -r2[j][1] / 6), (per / 6, -r2[i][1] / 6)]
            mid = (r1[i] + r1[j] + r2[i] + r2[j]) / 4
            ax_c = (sum(r1) + sum(r2)) / (2 * nsec)
            m.quad_flat(q, uv, np.array([mid[0] - ax_c[0], 0, mid[2] - ax_c[2]]))
            per += L
    # top and bottom
    ct = m.v(cen_top, (0, 1, 0), (0.5, 0.5))
    ids = [m.v(p, (0, 1, 0), (0.5 + (p[0] - cen_top[0]) / 6, 0.5 + (p[2] - cen_top[2]) / 6)) for p in rings[-1]]
    for i in range(nsec):
        m.tri(ct, ids[(i + 1) % nsec], ids[i])
    cb = m.v(cen, (0, -1, 0), (0.5, 0.5))
    ids = [m.v(p, (0, -1, 0), (0.5, 0.5)) for p in rings[0]]
    for i in range(nsec):
        m.tri(cb, ids[i], ids[(i + 1) % nsec])
    fix_winding(m)
    # the front face: a plane through the front vertices of rings 0 and 3 (the stone tilt)
    fa, fb = rings[0][0], rings[0][-1]  # the right and left front ones at the bottom
    ta, tb = rings[3][0], rings[3][-1]
    Uax = (fa - fb)
    Uax /= np.linalg.norm(Uax)
    up = ((ta + tb) / 2 - (fa + fb) / 2)
    up /= np.linalg.norm(up)
    Nf = np.cross(Uax, up)
    if np.dot(Nf[[0, 2]], -f) < 0:
        Nf = -Nf
    Nf /= np.linalg.norm(Nf)
    Vax = np.cross(Nf, Uax)
    if Vax[1] < 0:
        Vax = -Vax
    # the rune: from the ground height + 2.6 to + 5.0 (along the front face)
    base = (fa + fb) / 2 + up * ((ground + 2.6 - (fa + fb)[1] / 2) / max(up[1], 1e-6))
    rm = Mesh("Rune%d" % (k + 1), "rune")
    gw, gh = 1.15, 2.4
    for p1, p2 in RUNES[k + 1]:
        box_stroke(rm, base, Uax if np.dot(Uax[[0, 2]], s) > 0 else -Uax, Vax, Nf,
                   (p1[0] * gw, p1[1] * gh), (p2[0] * gw, p2[1] * gh), 0.24, 0.09)
    return m, rm, {"pos": [float(pos[0]), float(ground), float(pos[1])], "height": float(H)}


# ------------------------------------------------------------------------------------------------ textures
def grade(img, k, desat=0.0):
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    g = a.mean(-1, keepdims=True)
    a = a * (1 - desat) + g * desat
    return Image.fromarray(np.clip(a * k, 0, 255).astype(np.uint8))


def jpeg(img, q=88):
    b = io.BytesIO()
    img.convert("RGB").save(b, "JPEG", quality=q)
    return b.getvalue()


def textures():
    t = {}
    clay = Image.open(os.path.join(TEX, "plaza_clay_color.png"))
    t["clay"] = (jpeg(grade(clay, 0.72, 0.12)), jpeg(Image.open(os.path.join(TEX, "plaza_clay_normal.png")), 90))
    # slabs: darker and of varied tone (a low-frequency brightness field +-16% and a warm/cold shift) - each slab takes its own
    # atlas area; the rims: dark stone with moss spots, not an even green outline (P8 frames v1)
    rs = np.random.default_rng(5)

    def field(w, h, blur, lo, hi):
        f = Image.fromarray((rs.random((h // 16, w // 16)) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)
        f = np.asarray(f.filter(ImageFilter.GaussianBlur(blur))).astype(np.float32) / 255.0
        f = (f - f.min()) / max(f.max() - f.min(), 1e-6)
        return lo + (hi - lo) * f

    # the circle and path slabs from the same granite as
    # the marker stones; the moss in the cracks is already in the texture itself. The tile is cropped by the atlas height (no stretching)
    gsrc = Image.open(os.path.join(TEX, "granite_moss_color.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS).crop((0, 0, 1024, 768))
    flag = np.asarray(grade(gsrc, 0.86, 0.0)).astype(np.float32)  # 0.72 + a warm shift - darker than the source sample
    b = field(1024, 768, 40, 0.92, 1.08)[..., None]
    warm = field(1024, 768, 60, -1.0, 1.0)  # the field is computed in v5 too (the same random number order for the rim mask)
    flag = flag * b
    moss = np.asarray(grade(Image.open(os.path.join(TEX, "plaza_moss_color.png")), 0.7, 0.25).resize((1024, 256), Image.LANCZOS)).astype(np.float32)
    dark = np.asarray(grade(Image.open(os.path.join(TEX, "granite_moss_color.png")).convert("RGB").resize((1024, 1024), Image.LANCZOS).crop((0, 768, 1024, 1024)), 0.45, 0.1)).astype(np.float32)
    mask = (field(1024, 256, 6, 0, 1) > 0.55).astype(np.float32)
    mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32)[..., None] / 255.0
    side = dark * (1 - mask) + moss * mask
    atlas = Image.new("RGB", (1024, 1024))
    atlas.paste(Image.fromarray(np.clip(flag, 0, 255).astype(np.uint8)), (0, 0))
    atlas.paste(Image.fromarray(np.clip(side, 0, 255).astype(np.uint8)), (0, 768))
    natlas = Image.new("RGB", (1024, 1024))
    natlas.paste(Image.open(os.path.join(TEX, "granite_moss_normal.png")).convert("RGB").resize((1024, 1024)).crop((0, 0, 1024, 768)), (0, 0))
    natlas.paste(Image.open(os.path.join(TEX, "plaza_moss_normal.png")).convert("RGB").resize((1024, 256)), (0, 768))
    t["slab"] = (jpeg(atlas), jpeg(natlas, 90))
    cols = np.array([[70, 98, 34], [92, 122, 40], [60, 88, 30], [108, 132, 52], [82, 110, 44], [118, 126, 58], [66, 104, 46]], np.float32)
    tuft = np.zeros((256, 256, 3), np.float32)
    for i in range(256):
        tuft[:, i] = cols[(i * len(cols)) // 256]
    tuft *= np.linspace(1.15, 0.55, 256)[:, None, None]  # v 0 (the tip) lighter, v 1 (the base) darker
    t["tuft"] = (jpeg(Image.fromarray(np.clip(tuft, 0, 255).astype(np.uint8))), None)
    gran = grade(Image.open(os.path.join(TEX, "granite_moss_color.png")), 0.8).resize((512, 512), Image.LANCZOS)
    t["stone"] = (jpeg(gran), jpeg(Image.open(os.path.join(TEX, "granite_moss_normal.png")).convert("RGB").resize((512, 512)), 90))
    return t, atlas


# ------------------------------------------------------------------------------------------------ GLB
def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def write_glb(path, meshes, tex, mat_names=None, plain=None):
    """Mat_names - the material order (plaza by default); plain - the colour of the materials without a texture {name: (r, g, b)} 0..1."""
    chunks, views, accessors = [], [], []

    def add_bytes(data, target=None):
        off = sum(len(c) for c in chunks)
        chunks.append(pad4(data))
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def add(arr, target, comp, typ, minmax=False):
        data = arr.astype("<f4" if comp == 5126 else "<u4").tobytes()
        vi = add_bytes(data, target)
        acc = {"bufferView": vi, "componentType": comp, "count": len(arr), "type": typ}
        if minmax:
            acc["min"] = [float(x) for x in arr.min(0)]
            acc["max"] = [float(x) for x in arr.max(0)]
        accessors.append(acc)
        return len(accessors) - 1

    mat_names = mat_names or ["clay", "slab", "stone", "rune", "tuft"]
    images, textures_js, materials = [], [], []
    for name in mat_names:
        if name in tex and tex[name][1] is None:  # colour only (grass)
            ci = len(images)
            images.append({"bufferView": add_bytes(tex[name][0]), "mimeType": "image/jpeg"})
            textures_js.append({"source": ci, "sampler": 0})
            materials.append({"name": name, "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures_js) - 1},
                                                                     "metallicFactor": 0, "roughnessFactor": 1}, "doubleSided": True})
        elif name in tex:
            col, nrm = tex[name]
            ci = len(images)
            images.append({"bufferView": add_bytes(col), "mimeType": "image/jpeg"})
            images.append({"bufferView": add_bytes(nrm), "mimeType": "image/jpeg"})
            textures_js.append({"source": ci, "sampler": 0})
            textures_js.append({"source": ci + 1, "sampler": 0})
            materials.append({"name": name, "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures_js) - 2},
                                                                     "metallicFactor": 0, "roughnessFactor": 1},
                              "normalTexture": {"index": len(textures_js) - 1}})
        else:
            c = (plain or {}).get(name, (0.22, 0.26, 0.28))
            materials.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": [c[0], c[1], c[2], 1],
                                                                     "metallicFactor": 0, "roughnessFactor": 1}})
    nodes, mesh_js = [], []
    for m in meshes:
        P = np.array(m.p, np.float32)
        N = np.array(m.n, np.float32)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        UV = np.array(m.uv, np.float32)
        I = np.array(m.idx, np.uint32)
        prim = {"attributes": {"POSITION": add(P, 34962, 5126, "VEC3", True), "NORMAL": add(N, 34962, 5126, "VEC3"),
                               "TEXCOORD_0": add(UV, 34962, 5126, "VEC2")},
                "indices": add(I, 34963, 5125, "SCALAR"), "material": mat_names.index(m.material)}
        mesh_js.append({"name": m.name, "primitives": [prim]})
        nodes.append({"name": m.name, "mesh": len(mesh_js) - 1})
    nodes.append({"name": "OldAshPlaza", "children": list(range(len(meshes)))})
    binc = b"".join(chunks)
    js = {"asset": {"version": "2.0", "generator": "plaza_glb.py (Dragon Nest, 16.10.2026)"}, "scene": 0,
          "scenes": [{"name": "plaza", "nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": mesh_js,
          "materials": materials, "textures": textures_js, "images": images,
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
          "bufferViews": views, "accessors": accessors, "buffers": [{"byteLength": len(binc)}]}
    jb = pad4(json.dumps(js, separators=(",", ":")).encode(), b" ")
    total = 12 + 8 + len(jb) + 8 + len(binc)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<III", 0x46546C67, 2, total))
        fh.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        fh.write(struct.pack("<II", len(binc), 0x004E4942) + binc)
    return total


# ------------------------------------------------------------------------------------------------ checks and output
def lot_check(C):
    """The outline with the skirt does not enter the nest petals (along the axis >= 60 and across <= 28)."""
    worst = 99.0
    for i, r in enumerate(C.radii):
        a = i * STEP
        p = dirv(a) * (r + SKIRT)
        for na in NEST_ANGLES:
            d = dirv(na)
            along = p @ d
            across = abs(p[0] * d[1] - p[1] * d[0])
            if across <= LOT_HALF + 1:
                worst = min(worst, LOT_INNER - along)
    return worst


def write_shape(C, nodes, circle_top, stones):
    lines = ["--!strict",
             "-- GENERATED by tools/plaza_glb.py (spec 04 add. 2.8: the Old Ash plaza) - do not edit by hand, rerun the generator.",
             "-- The clay glade outline (the radius by the Layout.dir angle, a step of step degrees), the mesh nodes (the center and the frame size in world studs),",
             "-- the top of the slab circle (Old Ash stands on it), the marker stones at the nests. Pure data: read by Island and WorldBuilder.",
             "",
             "local PlazaShape = {}",
             "",
             "PlazaShape.step = %s" % STEP,
             "PlazaShape.grass = %s -- the plateau grass" % GRASS,
             "PlazaShape.top = %s -- the clay top at the start of the rim" % TOP,
             "PlazaShape.rim = %s -- the width of the rim going under the grass" % RIM,
             "PlazaShape.profile = { dome = %s, drop = %s, skirt = %s, pow = %s } -- the height: top + dome (1 - (r/rc)^2) - drop u^pow" % (DOME, DROP, SKIRT, POW),
             "PlazaShape.circleTop = %.3f" % circle_top,
             "PlazaShape.radii = {"]
    row = []
    for i, r in enumerate(C.radii):
        row.append("%.2f" % r)
        if len(row) == 12:
            lines.append("\t" + ", ".join(row) + ",")
            row = []
    if row:
        lines.append("\t" + ", ".join(row) + ",")
    lines.append("}")
    lines.append("PlazaShape.nodes = {")
    for name, (c, s) in nodes.items():
        lines.append("\t%s = { c = { %.3f, %.3f, %.3f }, s = { %.3f, %.3f, %.3f } }," % (name, *c, *s))
    lines.append("}")
    lines.append("PlazaShape.stones = {")
    for st in stones:
        lines.append("\t{ pos = { %.2f, %.2f, %.2f }, height = %.2f }," % (*st["pos"], st["height"]))
    lines.append("}")
    lines += ["",
              "-- the outline radius by angle (degrees, 0 = east, 90 = north), linear between the samples",
              "function PlazaShape.radius(thetaDeg: number): number",
              "\tlocal n = #PlazaShape.radii",
              "\tlocal i = (thetaDeg % 360) / PlazaShape.step",
              "\tlocal i0 = math.floor(i)",
              "\tlocal f = i - i0",
              "\tlocal a = PlazaShape.radii[(i0 % n) + 1]",
              "\tlocal b = PlazaShape.radii[((i0 + 1) % n) + 1]",
              "\treturn a + (b - a) * f",
              "end",
              "",
              "-- the point (x, z) is inside the outline with a margin of inset (inset > 0 - deeper inside)",
              "function PlazaShape.inside(x: number, z: number, inset: number?): boolean",
              "\tlocal r = math.sqrt(x * x + z * z)",
              "\treturn r <= PlazaShape.radius(math.deg(math.atan2(-z, x))) - (inset or 0)",
              "end",
              "",
              "return PlazaShape", ""]
    open(SHAPE, "w", encoding="utf-8").write("\n".join(lines))


def preview(path, C, meshes):
    S, sc = 900, 7.5
    im = Image.new("RGB", (S, S), (70, 130, 50))
    dr = ImageDraw.Draw(im)
    col = {"clay": (170, 125, 80), "slab": (175, 170, 160), "stone": (95, 95, 100), "rune": (60, 220, 255), "tuft": (60, 140, 40)}
    for m in meshes:
        P = np.array(m.p)
        for t in range(0, len(m.idx), 3):
            tri = [P[m.idx[t + i]] for i in range(3)]
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            if n[1] <= 0:
                continue
            pts = [(S / 2 + p[0] * sc, S / 2 + p[2] * sc) for p in tri]
            c = col[m.material]
            if m.material == "clay":
                shade = int((np.mean([p[1] for p in tri]) - 17.6) * 60)
                c = tuple(max(0, min(255, x + shade)) for x in c)
            dr.polygon(pts, fill=c)
    for a in STAIRS_ANGLES:
        d = dirv(a)
        dr.line([(S / 2 + d[0] * 60 * sc, S / 2 + d[1] * 60 * sc), (S / 2 + d[0] * 70 * sc, S / 2 + d[1] * 70 * sc)], fill=(255, 255, 0), width=3)
    for a in NEST_ANGLES:  # the petals: the inner edge
        d, l = dirv(a), dirv(a + 90)
        p1, p2 = d * LOT_INNER + l * LOT_HALF, d * LOT_INNER - l * LOT_HALF
        dr.line([(S / 2 + p1[0] * sc, S / 2 + p1[1] * sc), (S / 2 + p2[0] * sc, S / 2 + p2[1] * sc)], fill=(255, 60, 60), width=2)
    dr.rectangle([S / 2 - 4 * sc, S / 2 + (-40 - 1.5) * sc, S / 2 + 4 * sc, S / 2 + (-40 + 1.5) * sc], outline=(255, 255, 255))
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seed", type=int, default=16)
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    rng = np.random.default_rng(a.seed)
    C = Contour(rng)
    meshes = []
    worst_excess = 0.0
    for k in range(36):
        m, ex = clay_piece(C, k)
        worst_excess = max(worst_excess, ex)
        meshes.append(m)
    circ, circle_top = circle_slabs(C, rng)
    meshes.append(circ)
    for k in range(6):
        meshes.append(trail(C, rng, k))
    stones = []
    for k in range(6):
        sm, rm, info = waystone(C, rng, k)
        meshes += [sm, rm]
        stones.append(info)
    tm, n_gap, n_trail = tufts(C, rng, stones)
    meshes.append(tm)
    print("grass tufts: in the circle cracks %d, at the paths %d, at the stones %d" % (n_gap, n_trail, 7 * len(stones)))
    samp = []
    for poly, top in SLAB_TOPS[:]:
        cx = sum(p[0] for p in poly) / len(poly)
        cz = sum(p[1] for p in poly) / len(poly)
        samp.append([round(cx, 3), round(cz, 3), round(top(cx, cz), 3)])
    json.dump(samp, open(os.path.join(OUT_DIR, "slab_samples.json"), "w"))
    bad = sum(1 for i in range(len(PLACED)) for j in range(i) if overlaps(PLACED[i], PLACED[j], eps=-0.02))
    print("slabs %d, overlaps %d" % (len(PLACED), bad))
    tex, atlas = textures()
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "plaza.glb")
    size = write_glb(out, meshes, tex)
    nodes = {}
    for m in meshes:
        lo, hi = m.bbox()
        nodes[m.name] = ((lo + hi) / 2, hi - lo)
    write_shape(C, nodes, circle_top, stones)
    allp = np.concatenate([np.array(m.p) for m in meshes])
    print("outline r %.1f..%.1f, margin to the petals %.1f studs, above the convexity of the glade chunks (max) %.2f sq. studs" %
          (C.radii.min(), C.radii.max(), lot_check(C), worst_excess))
    print("nodes %d, triangles %d, frame %s..%s, circle top %.2f, GLB %d KB -> %s" %
          (len(meshes), sum(len(m.idx) // 3 for m in meshes), allp.min(0).round(2), allp.max(0).round(2), circle_top,
           size // 1024, out))
    if a.preview:
        preview(a.preview, C, meshes)


if __name__ == "__main__":
    main()
