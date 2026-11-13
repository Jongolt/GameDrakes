#!/usr/bin/env python3
"""Springs 'a cascade of turquoise pools': a gentle terrain hill in the north-west
part of the platform, 4 travertine pool basins down the slope and the biggest lower one - the lagoon. Each basin has: a rim in chunks
(almost convex - the Roblox collisions are exact, the camera does not go under the rim), a white bottom, water - a thin part of its own colour
(turquoise, not the sea colour). The overflows between the basins and the steam are placed by WorldBuilder at the points from the shape. One GLB, vertices in world
coordinates; writes src/shared/Core/SpringsShape.luau (the hill, the basins, the overflows, the egg points) - read by Island, Layout, DecorLayout and
WorldBuilder. The plaza pipeline: tools/plaza_glb.py (writing the GLB, the import turns the nodes by 180 - importYaw in Config).
    python3 tools/springs_glb.py [--preview /tmp/springs_top.png]
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import plaza_glb as PG  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TEX = os.path.join(ROOT, "assets_src", "terrain_textures")
OUT_DIR = os.path.join(ROOT, "assets_src", "springs")
SHAPE = os.path.join(ROOT, "src", "shared", "Core", "SpringsShape.luau")

BASE = 4.0  # the Springs platform (Config island2.springs.y)
BOX = (-372.0, -232.0, -130.0, 124.0)  # x1, x2, z1, z2 - island2.springs.box (z1 extended north for the hill)
MOUND = {"x": -326.0, "z": -88.0, "r": 105.0, "h": 18.0, "pow": 1.25, "fade": 26.0}  # the hill: the top, the radius, the height, the fade at the platform edge
LIP = 1.7  # rim width
LIP_UP = 0.45  # the rim top above the water
TILE = 9.0  # studs per travertine tile
ISLET_R, ISLET_Y = 12.0, 78.0  # a floating islet above the cascade top: radius, height (a waterfall from its edge into the upper basin)
EGG_LIFT = 1.25  # EggSpawner: the egg bottom = point + 0.1 (anchor) + 1.2 (terrain correction) - on the rim we lower the point
WALL_DEEP = 2.5  # the outer rim wall goes underground by this much (the terrain pits are quantized by the 4 voxel)
# basins: name, centre, radius, depth, rim chunks, outline phases (bottom up: lagoon -> upper)
BASINS = [
    ("Lagoon", (-296.0, 46.0), 27.0, 2.2, 20, 1),
    ("Pool1", (-314.0, -10.0), 14.0, 1.6, 14, 2),
    ("Pool2", (-337.0, -42.0), 12.5, 1.5, 12, 3),
    ("Pool3", (-311.0, -67.0), 11.0, 1.5, 12, 4),
    ("Pool4", (-334.0, -98.0), 9.5, 1.4, 12, 5, 2.8),  # the upper one on the top is raised
]


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def mound(x, z):
    """A cone hill with a rounded top (no edge noise - the same computation in SpringsShape.hill)."""
    d = math.hypot(x - MOUND["x"], z - MOUND["z"]) / MOUND["r"]
    if d >= 1:
        return 0.0
    edge = min(x - BOX[0], BOX[1] - x, z - BOX[2], BOX[3] - z)
    return MOUND["h"] * (1 - d) ** MOUND["pow"] * (1 - 0.25 * math.exp(-(d / 0.12) ** 2)) * smooth(edge / MOUND["fade"])


def ground(x, z):
    return BASE + mound(x, z)


class Basin:
    def __init__(self, name, c, r, depth, pieces, seed, raise_=0.0):
        rng = np.random.default_rng(100 + seed)
        self.name, self.c, self.R, self.depth, self.pieces = name, np.array(c), r, depth, pieces
        self.ph = rng.uniform(0, 2 * math.pi, 4)
        n = pieces * 4
        self.angs = [360.0 * i / n for i in range(n)]
        # the water level: the highest ground under the outer rim edge + a margin (the basin does not sink into the slope)
        hmax = max(ground(*self.pt(a, self.rin(a) + LIP + 0.6)) for a in self.angs)
        self.W = hmax + 0.55 + raise_
        self.floor = self.W - depth

    def rin(self, a):
        t = math.radians(a)
        p = self.ph
        return self.R * (1 + 0.11 * math.sin(2 * t + p[0]) + 0.06 * math.sin(3 * t + p[1]) + 0.035 * math.sin(5 * t + p[2]))

    def pt(self, a, r):
        t = math.radians(a)
        return self.c[0] + r * math.cos(t), self.c[1] - r * math.sin(t)

    def rout(self, a):
        return self.rin(a) + LIP


def build_basin(b):
    """Rim chunks (4 angle samples each), the bottom, the water."""
    meshes = []
    n = len(b.angs)
    per = n // b.pieces
    for k in range(b.pieces):
        m = PG.Mesh("%sRim%02d" % (b.name, k + 1), "trav")
        idx = [(k * per + j) % n for j in range(per + 1)]
        rings = []  # by angle: inner bottom, inner top, outer top, outer bottom
        for i in idx:
            a = b.angs[i]
            ri, ro = b.rin(a), b.rout(a)
            xi, zi = b.pt(a, ri - 0.45)
            xi2, zi2 = b.pt(a, ri)
            xo, zo = b.pt(a, ro)
            xo2, zo2 = b.pt(a, ro + 0.5)
            gy = ground(xo2, zo2)
            rings.append([np.array([xi, b.floor - 0.5, zi]), np.array([xi2, b.W + LIP_UP - 0.05, zi2]),
                          np.array([xo, b.W + LIP_UP + 0.05, zo]), np.array([xo2, min(gy, b.W) - WALL_DEEP, zo2])])
        cx = sum(r[1] for r in rings) / len(rings)
        arc = 0.0
        for j in range(len(rings) - 1):
            A, B = rings[j], rings[j + 1]
            L = np.linalg.norm(B[2] - A[2])
            # the rim top
            m.quad_flat([A[1], B[1], B[2], A[2]], [(A[1][0] / TILE, A[1][2] / TILE), (B[1][0] / TILE, B[1][2] / TILE),
                                                   (B[2][0] / TILE, B[2][2] / TILE), (A[2][0] / TILE, A[2][2] / TILE)], np.array([0, 1.0, 0]))
            # the inner wall (toward the water)
            cin = np.array([b.c[0], 0, b.c[1]])
            m.quad_flat([A[0], B[0], B[1], A[1]], [(arc / TILE, A[0][1] / TILE), ((arc + L) / TILE, B[0][1] / TILE),
                                                   ((arc + L) / TILE, B[1][1] / TILE), (arc / TILE, A[1][1] / TILE)],
                        cin - (A[0] + B[0]) / 2 * np.array([1, 0, 1]))
            # the outer wall (a travertine curtain down the slope)
            m.quad_flat([A[3], B[3], B[2], A[2]], [(arc / TILE, -A[3][1] / TILE), ((arc + L) / TILE, -B[3][1] / TILE),
                                                   ((arc + L) / TILE, -B[2][1] / TILE), (arc / TILE, -A[2][1] / TILE)],
                        (A[3] + B[3]) / 2 * np.array([1, 0, 1]) - cin)
            # bottom
            m.quad_flat([A[0], B[0], B[3], A[3]], [(0, 0)] * 4, np.array([0, -1.0, 0]))
            arc += L
        for end, sgn in ((rings[0], -1), (rings[-1], 1)):  # the chunk ends
            tang = (rings[-1][1] - rings[0][1]) * np.array([1, 0, 1])
            m.quad_flat([end[0], end[1], end[2], end[3]], [(0, 0)] * 4, tang * sgn)
        PG.fix_winding(m)
        meshes.append(m)
    # the bottom: a polygon under the inner edge, thickness 0.8
    fl = PG.Mesh("%sFloor" % b.name, "trav")
    top, bot = [], []
    for a in b.angs:
        x, z = b.pt(a, b.rin(a) - 0.2)
        top.append(fl.v((x, b.floor, z), (0, 1, 0), (x / TILE, z / TILE)))
    ct = fl.v((b.c[0], b.floor, b.c[1]), (0, 1, 0), (b.c[0] / TILE, b.c[1] / TILE))
    for i in range(n):
        fl.tri(ct, top[i], top[(i + 1) % n])
    for a in b.angs:
        x, z = b.pt(a, b.rin(a) - 0.2)
        bot.append(fl.v((x, b.floor - 0.8, z), (0, -1, 0), (0, 0)))
    cb = fl.v((b.c[0], b.floor - 0.8, b.c[1]), (0, -1, 0), (0, 0))
    for i in range(n):
        fl.tri(cb, bot[(i + 1) % n], bot[i])
    PG.fix_winding(fl)
    meshes.append(fl)
    # the water: a thin plate just under the rim (the edge goes into the rim by 0.25)
    wm = PG.Mesh("%sWater" % b.name, "water")
    top = []
    for a in b.angs:
        x, z = b.pt(a, b.rin(a) + 0.25)
        top.append(wm.v((x, b.W, z), (0, 1, 0), (0, 0)))
    ct = wm.v((b.c[0], b.W, b.c[1]), (0, 1, 0), (0, 0))
    for i in range(n):
        wm.tri(ct, top[i], top[(i + 1) % n])
    bot = []
    for a in b.angs:
        x, z = b.pt(a, b.rin(a) + 0.25)
        bot.append(wm.v((x, b.W - 0.15, z), (0, -1, 0), (0, 0)))
    cb = wm.v((b.c[0], b.W - 0.15, b.c[1]), (0, -1, 0), (0, 0))
    for i in range(n):
        wm.tri(cb, bot[(i + 1) % n], bot[i])
    PG.fix_winding(wm)
    meshes.append(wm)
    return meshes


def cascades(bs):
    """An overflow from basin k into the lower k-1: from the rim toward the lower basin, the bottom - on its water."""
    out = []
    for k in range(len(bs) - 1, 0, -1):
        up, lo = bs[k], bs[k - 1]
        d = lo.c - up.c
        a = math.degrees(math.atan2(-d[1], d[0])) % 360
        x0, z0 = up.pt(a, up.rout(a) - 0.2)
        dd = d / np.linalg.norm(d)
        # the bottom: a point on the line inside the lower basin 2 studs from its edge
        a2 = (a + 180) % 360
        x1, z1 = lo.pt(a2, lo.rin(a2) - 2.0)
        out.append({"from": up.name, "to": lo.name, "top": [x0, up.W + LIP_UP + 0.05, z0], "bottom": [x1, lo.W, z1],
                    "dir": [float(dd[0]), 0.0, float(dd[1])], "width": 3.0 + 0.26 * up.R})
    return out


def egg_points(bs, casc):
    """6 points on the rims to the side of the overflows: one on each Pool1..4 and two on the lagoon (east and west)."""
    pts = []
    flow = {c["from"]: c["dir"] for c in casc}
    for b in bs[1:]:
        dv = flow.get(b.name, [0, 0, 1])
        a = (math.degrees(math.atan2(-dv[2], dv[0])) + (95 if len(pts) % 2 == 0 else -95)) % 360
        x, z = b.pt(a, b.rin(a) + LIP / 2)
        pts.append([x, b.W + LIP_UP + 0.05 - EGG_LIFT, z])
    L = bs[0]
    for a in (10.0, 200.0):
        x, z = L.pt(a, L.rin(a) + LIP / 2)
        pts.append([x, L.W + LIP_UP + 0.05 - EGG_LIFT, z])
    return pts


# ------------------------------------------------------------------------------------------------ the gate and the crossing
GATE = {"x": -241.0, "z": 24.0, "open": 9.0, "top": 15.5, "bottom": -2.5}  # the passage axis east-west, the pillars along z
STEPS_Z, STEPS_X = 20.0, [-224.0, -221.0, -218.0, -215.0, -212.0, -209.0, -206.0, -203.0]  # stones across the stream (water 0)


def prism(m, rings, out_c):
    """The sides and caps of a polygonal prism by rings (a list of rings of equal length), outward from the axis."""
    n = len(rings[0])
    for li in range(len(rings) - 1):
        r1, r2 = rings[li], rings[li + 1]
        per = 0.0
        for i in range(n):
            j = (i + 1) % n
            L = np.linalg.norm(r1[j] - r1[i])
            mid = (r1[i] + r1[j] + r2[i] + r2[j]) / 4
            ax = out_c(mid)
            m.quad_flat([r1[i], r1[j], r2[j], r2[i]], [(per / 6, -r1[i][1] / 6), ((per + L) / 6, -r1[j][1] / 6),
                                                       ((per + L) / 6, -r2[j][1] / 6), (per / 6, -r2[i][1] / 6)], mid - ax)
            per += L
    for ring, up in ((rings[-1], 1.0), (rings[0], -1.0)):
        c = sum(ring) / n
        ci = m.v(c, (0, up, 0), (0.5, 0.5))
        ids = [m.v(p, (0, up, 0), (0.5 + (p[0] - c[0]) / 6, 0.5 + (p[2] - c[2]) / 6)) for p in ring]
        for i in range(n):
            m.tri(ci, ids[i], ids[(i + 1) % n])
    PG.fix_winding(m)


def gate_meshes(rng):
    """The 'water curtain' arch (Add. 2.9): two mossy granite pillars and a stone lintel; the pillar bottoms in the ground."""
    out = []
    for side, sgn in (("L", -1), ("R", 1)):
        cz = GATE["z"] + sgn * (GATE["open"] / 2 + 2.1)
        m = PG.Mesh("GatePillar" + side, "stone")
        rings = []
        for lv, y in enumerate([GATE["bottom"], 3.0, 9.0, GATE["top"]]):
            sc = 1.0 - 0.22 * lv / 3
            ring = []
            for i in range(8):
                a = 2 * math.pi * i / 8 + 0.2
                rx, rz = 2.3 * sc * rng.uniform(0.88, 1.08), 2.0 * sc * rng.uniform(0.88, 1.08)
                ring.append(np.array([GATE["x"] + rx * math.cos(a), y + (rng.uniform(-0.6, 0.6) if lv == 3 else 0), cz + rz * math.sin(a)]))
            rings.append(ring)
        prism(m, rings, lambda mid, cz=cz: np.array([GATE["x"], mid[1], cz]))
        out.append(m)
    m = PG.Mesh("GateLintel", "stone")
    span = GATE["open"] + 2 * 4.4
    rings = []
    for k, t in enumerate(np.linspace(-0.5, 0.5, 5)):
        z = GATE["z"] + t * span
        y = GATE["top"] - 1.0 + 0.6 * (1 - (2 * t) ** 2)  # a slight upward bend
        ring = []
        for i in range(7):
            a = 2 * math.pi * i / 7
            ring.append(np.array([GATE["x"] + 1.7 * math.cos(a) * rng.uniform(0.85, 1.1), y + 1.2 * math.sin(a) * rng.uniform(0.85, 1.1), z]))
        rings.append(ring)
    # the rings go along z: the prism 'up' is the z axis; caps at the ends
    m2 = PG.Mesh("GateLintel", "stone")
    n = 7
    for li in range(len(rings) - 1):
        r1, r2 = rings[li], rings[li + 1]
        for i in range(n):
            j = (i + 1) % n
            mid = (r1[i] + r1[j] + r2[i] + r2[j]) / 4
            axis = np.array([GATE["x"], (sum(p[1] for p in r1) / n + sum(p[1] for p in r2) / n) / 2, mid[2]])
            m2.quad_flat([r1[i], r1[j], r2[j], r2[i]], [(r1[i][2] / 6, r1[i][1] / 6), (r1[j][2] / 6, r1[j][1] / 6),
                                                       (r2[j][2] / 6, r2[j][1] / 6), (r2[i][2] / 6, r2[i][1] / 6)], mid - axis)
    for ring, sgn in ((rings[0], -1.0), (rings[-1], 1.0)):
        c = sum(ring) / n
        ci = m2.v(c, (0, 0, sgn), (0.5, 0.5))
        ids = [m2.v(p, (0, 0, sgn), (0.5 + (p[0] - c[0]) / 6, 0.5 + (p[1] - c[1]) / 6)) for p in ring]
        for i in range(n):
            m2.tri(ci, ids[i], ids[(i + 1) % n])
    PG.fix_winding(m2)
    out.append(m2)
    lintel_low = min(p[1] for r in rings for p in r)
    return out, lintel_low


def step_stones(rng):
    """Stepping stones across the stream instead of a plank: a flat top 0.7 above the water, the bottom on the riverbed."""
    out = []
    for k, x in enumerate(STEPS_X):
        z = STEPS_Z + (1.0 if k % 2 else -1.0) * rng.uniform(0.4, 1.0)
        m = PG.Mesh("Step%d" % (k + 1), "stone")
        top = 0.7 + rng.uniform(-0.1, 0.15)
        rings = []
        for y, sc in ((-4.5, 1.15), (top - 0.35, 1.0), (top, 0.82)):
            ring = []
            for i in range(7):
                a = 2 * math.pi * i / 7
                ring.append(np.array([x + 1.35 * sc * math.cos(a), y, z + 1.25 * sc * math.sin(a)]))
            rings.append(ring)
        prism(m, rings, lambda mid, x=x, z=z: np.array([x, mid[1], z]))
        out.append(m)
    return out


# ------------------------------------------------------------------------------------------------ the grotto behind the waterfall
def box_prism(name, cx, cz, dirv, along, across, y0, y1, rng, jit=0.25):
    """An uneven granite block prism: a rectangle along x across in the dirv axes, from y0 to y1."""
    m = PG.Mesh(name, "stone")
    f = np.array([dirv[0], dirv[1]])
    l = np.array([-dirv[1], dirv[0]])
    rings = []
    for y in (y0, (y0 + y1) / 2, y1):
        ring = []
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            u = su * along / 2 + rng.uniform(-jit, jit)
            v = sv * across / 2 + rng.uniform(-jit, jit)
            p = np.array([cx, cz]) + f * u + l * v
            ring.append(np.array([p[0], y + (rng.uniform(-jit, jit) if y == y1 else 0), p[1]]))
        rings.append(ring)
    prism(m, rings, lambda mid: np.array([cx, mid[1], cz]))
    return m


def grotto(bs, rng):
    """The grotto behind the upper basin waterfall: the floor at the rim level
    (+0.17 - not flush), walls and a roof of blocks, the entrance toward the basin. The waterfall from the floating islet falls into the basin in front of the entrance."""
    top, nxt = bs[-1], bs[-2]
    d = top.c - nxt.c
    d = d / np.linalg.norm(d)  # from the next basin - the grotto is behind the upper one, on the far side
    a = math.degrees(math.atan2(-d[1], d[0])) % 360
    r_mouth = top.rin(a) + LIP - 0.4
    depth, inner = 6.5, 6.0
    floor_top = top.W + LIP_UP + 0.17
    c0 = top.c + d * r_mouth
    def at(u):
        return top.c + d * (r_mouth + u)
    g = ground(*at(depth / 2))
    out = []
    fc = at(depth / 2)
    out.append(box_prism("GrottoFloor", fc[0], fc[1], d, depth + 0.6, inner + 3.2, g - 2.5, floor_top, rng, 0.15))
    bc = at(depth + 0.7)
    out.append(box_prism("GrottoBack", bc[0], bc[1], d, 1.8, inner + 3.4, g - 2.5, floor_top + 6.4, rng))
    l = np.array([-d[1], d[0]])
    for side, sg in (("L", -1), ("R", 1)):
        sc = at(depth / 2 + 0.4) + l * sg * (inner / 2 + 0.8)
        out.append(box_prism("GrottoSide" + side, sc[0], sc[1], d, depth + 0.6, 1.6, g - 2.5, floor_top + 6.2, rng))
    rc = at(depth / 2 + 0.1)
    out.append(box_prism("GrottoRoof", rc[0], rc[1], d, depth + 1.8, inner + 4.2, floor_top + 6.0, floor_top + 7.6, rng))
    egg = at(depth * 0.55)
    fall = top.c + d * (top.rin(a) + LIP - 1.6)  # the jet - into the basin in front of the entrance
    info = {"egg": [float(egg[0]), floor_top - EGG_LIFT, float(egg[1])], "fall": [float(fall[0]), top.W, float(fall[1])],
            "dir": [float(d[0]), float(d[1])], "floorTop": floor_top, "mouth": [float(c0[0]), float(c0[1])]}
    return out, info


def textures():
    trav = PG.grade(Image.open(os.path.join(TEX, "springs_travertine_color.png")), 0.84, 0.0).resize((1024, 1024), Image.LANCZOS)
    nrm = Image.open(os.path.join(TEX, "springs_travertine_normal.png")).convert("RGB").resize((1024, 1024))
    gran = PG.grade(Image.open(os.path.join(TEX, "granite_moss_color.png")), 0.8).resize((512, 512), Image.LANCZOS)
    gn = Image.open(os.path.join(TEX, "granite_moss_normal.png")).convert("RGB").resize((512, 512))
    return {"trav": (PG.jpeg(trav), PG.jpeg(nrm, 90)), "stone": (PG.jpeg(gran), PG.jpeg(gn, 90))}


def write_shape(bs, casc, pts, nodes):
    L = ["--!strict",
         "-- GENERATED by tools/springs_glb.py (spec 04 add. 2.7: the Springs bath cascade) - do not edit by hand.",
         "-- The hill above the area, the bowls (the center, the outline radii by angle, the water, the bottom), the spillways, 6 egg spots on the rims.",
         "-- Pure data: Island (the hill and the pits under the bowls), Layout (the egg spots), DecorLayout (going around the bowls), WorldBuilder.",
         "",
         "local SpringsShape = {}",
         "",
         "SpringsShape.base = %s" % BASE,
         "SpringsShape.box = { x1 = %s, x2 = %s, z1 = %s, z2 = %s }" % BOX,
         "SpringsShape.mound = { x = %s, z = %s, r = %s, h = %s, pow = %s, fade = %s }" % (MOUND["x"], MOUND["z"], MOUND["r"], MOUND["h"], MOUND["pow"], MOUND["fade"]),
         "SpringsShape.lip = %s" % LIP,
         "SpringsShape.basins = {"]
    for b in bs:
        rr = ", ".join("%.2f" % b.rin(a) for a in b.angs)
        L.append("\t{ name = \"%s\", x = %.2f, z = %.2f, water = %.3f, floor = %.3f, step = %.4f, rin = { %s } }," %
                 (b.name, b.c[0], b.c[1], b.W, b.floor, 360.0 / len(b.angs), rr))
    L.append("}")
    L.append("SpringsShape.cascades = {")
    for c in casc:
        L.append("\t{ from = \"%s\", to = \"%s\", top = { %.2f, %.2f, %.2f }, bottom = { %.2f, %.2f, %.2f }, dir = { %.3f, 0, %.3f }, width = %.2f }," %
                 (c["from"], c["to"], *c["top"], *c["bottom"], c["dir"][0], c["dir"][2], c["width"]))
    L.append("}")
    L.append("SpringsShape.nodes = {")
    for name, (c, sz) in nodes.items():
        L.append("\t%s = { c = { %.3f, %.3f, %.3f }, s = { %.3f, %.3f, %.3f } }," % (name, *c, *sz))
    L.append("}")
    L.append("SpringsShape.gate = { x = %s, z = %s, open = %s, top = %s, lintelLow = %.2f } -- the curtain arch: the passage axis along x" % (GATE["x"], GATE["z"], GATE["open"], GATE["top"], GATE_INFO["lintelLow"]))
    G = GATE_INFO["grotto"]
    isl = [G["fall"][0] + G["dir"][0] * ISLET_R * 0.96, ISLET_Y, G["fall"][2] + G["dir"][1] * ISLET_R * 0.96]
    L.append("-- the grotto behind the upper bowl's waterfall: an egg spot (secret, without hints), the jet from the floating islet (islet) into the bowl in front of the entrance")
    L.append("SpringsShape.grotto = { egg = { %.2f, %.2f, %.2f }, fall = { %.2f, %.2f, %.2f }, floorTop = %.2f }" % (*G["egg"], *G["fall"], G["floorTop"]))
    L.append("SpringsShape.islet = { x = %.2f, y = %.2f, z = %.2f, r = %s, tier = 2 }" % (isl[0], isl[1], isl[2], ISLET_R))
    L.append("SpringsShape.points = {")
    for p in pts:
        L.append("\t{ %.2f, %.2f, %.2f }," % tuple(p))
    L.append("}")
    L += ["",
          "local function smooth(t: number): number",
          "\tt = math.clamp(t, 0, 1)",
          "\treturn t * t * (3 - 2 * t)",
          "end",
          ""]
    L += ["-- the hill above the area (studs above base); 0 outside the radius",
          "function SpringsShape.hill(x: number, z: number): number",
          "\tlocal M, B = SpringsShape.mound, SpringsShape.box",
          "\tlocal d = math.sqrt((x - M.x) ^ 2 + (z - M.z) ^ 2) / M.r",
          "\tif d >= 1 then",
          "\t\treturn 0",
          "\tend",
          "\tlocal edge = math.min(x - B.x1, B.x2 - x, z - B.z1, B.z2 - z)",
          "\treturn M.h * (1 - d) ^ M.pow * (1 - 0.25 * math.exp(-(d / 0.12) ^ 2)) * smooth(edge / M.fade)",
          "end",
          "",
          "-- the radius of the bowl's inner edge by angle (degrees, like Layout.dir)",
          "function SpringsShape.rin(b: any, thetaDeg: number): number",
          "\tlocal n = #b.rin",
          "\tlocal i = (thetaDeg % 360) / b.step",
          "\tlocal i0 = math.floor(i)",
          "\tlocal f = i - i0",
          "\tlocal a = b.rin[(i0 % n) + 1]",
          "\tlocal c = b.rin[((i0 + 1) % n) + 1]",
          "\treturn a + (c - a) * f",
          "end",
          "",
          "-- the bowl the point (x, z) falls into with a margin of margin beyond the outer rim edge; nil - outside the bowls",
          "function SpringsShape.basinAt(x: number, z: number, margin: number?): any?",
          "\tfor _, b in SpringsShape.basins do",
          "\t\tlocal dx, dz = x - b.x, z - b.z",
          "\t\tlocal r = math.sqrt(dx * dx + dz * dz)",
          "\t\tif r <= SpringsShape.rin(b, math.deg(math.atan2(-dz, dx))) + SpringsShape.lip + (margin or 0) then",
          "\t\t\treturn b",
          "\t\tend",
          "\tend",
          "\treturn nil",
          "end",
          "",
          "return SpringsShape", ""]
    open(SHAPE, "w", encoding="utf-8").write("\n".join(L))


def preview(path, bs, meshes, casc, pts):
    S, sc = 900, 2.9
    ox, oz = -302, -3
    im = Image.new("RGB", (S, S), (80, 140, 60))
    dr = ImageDraw.Draw(im)
    for gx in range(0, S, 6):
        for gz in range(0, S, 6):
            x, z = ox + (gx - S / 2) / sc, oz + (gz - S / 2) / sc
            if BOX[0] <= x <= BOX[1] and BOX[2] <= z <= BOX[3]:
                h = ground(x, z)
                c = int(120 + (h - BASE) * 10)
                dr.rectangle([gx, gz, gx + 6, gz + 6], fill=(c, c - 10, c - 40))
    col = {"trav": (240, 232, 215), "water": (90, 210, 215)}
    for m in meshes:
        if m.material != "water" and "Rim" not in m.name:
            continue
        P = np.array(m.p)
        for t in range(0, len(m.idx), 3):
            tri = [P[m.idx[t + i]] for i in range(3)]
            n = np.cross(tri[1] - tri[0], tri[2] - tri[0])
            if n[1] <= 0:
                continue
            dr.polygon([(S / 2 + (p[0] - ox) * sc, S / 2 + (p[2] - oz) * sc) for p in tri], fill=col[m.material])
    for c in casc:
        dr.line([(S / 2 + (c["top"][0] - ox) * sc, S / 2 + (c["top"][2] - oz) * sc), (S / 2 + (c["bottom"][0] - ox) * sc, S / 2 + (c["bottom"][2] - oz) * sc)], fill=(255, 255, 255), width=4)
    for p in pts:
        x, z = S / 2 + (p[0] - ox) * sc, S / 2 + (p[2] - oz) * sc
        dr.ellipse([x - 5, z - 5, x + 5, z + 5], fill=(255, 140, 0))
    for b in bs:
        dr.text((S / 2 + (b.c[0] - ox) * sc - 20, S / 2 + (b.c[1] - oz) * sc), "%s %.1f" % (b.name, b.W), fill=(0, 0, 0))
    im.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", default="")
    a = ap.parse_args()
    bs = [Basin(*x) for x in BASINS]
    meshes = []
    for b in bs:
        meshes += build_basin(b)
    casc = cascades(bs)
    pts = egg_points(bs, casc)
    grng = np.random.default_rng(29)
    gm, lintel_low = gate_meshes(grng)
    meshes += gm + step_stones(grng)
    gr, ginfo = grotto(bs, grng)
    meshes += gr
    for i in range(len(bs)):
        for j in range(i):
            d = np.linalg.norm(bs[i].c - bs[j].c)
            gap = d - (bs[i].R * 1.2 + LIP) - (bs[j].R * 1.2 + LIP)
            if gap < 1.0:
                print("!! basins too close:", bs[i].name, bs[j].name, "gap (rough) %.1f" % gap)
    for b in bs:
        print("%-7s centre (%.0f, %.0f) r %.1f: water %.2f, bottom %.2f, ground at the centre %.2f" % (b.name, b.c[0], b.c[1], b.R, b.W, b.floor, ground(*b.c)))
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "springs.glb")
    size = PG.write_glb(out, meshes, textures(), mat_names=["trav", "water", "stone"], plain={"water": (0.35, 0.82, 0.84)})
    global GATE_INFO
    GATE_INFO = {"lintelLow": lintel_low, "grotto": ginfo}
    nodes = {}
    for m in meshes:
        lo, hi = m.bbox()
        nodes[m.name] = ((lo + hi) / 2, hi - lo)
    write_shape(bs, casc, pts, nodes)
    allp = np.concatenate([np.array(m.p) for m in meshes])
    print("nodes %d, triangles %d, frame %s..%s, GLB %d KB" % (len(meshes), sum(len(m.idx) // 3 for m in meshes),
                                                                  allp.min(0).round(1), allp.max(0).round(1), size // 1024))
    if a.preview:
        preview(a.preview, bs, meshes, casc, pts)


if __name__ == "__main__":
    main()
