#!/usr/bin/env python3
"""GlTF (json + .bin + images) -> one GLB with embedded images (Poly Haven CC0 for Roblox Open Cloud).
Pure Python. Scale: --scale k multiplies all positions (Poly Haven is in metres; 1 stud ~ 0.28 m -> for Roblox usually 3.5).
Prints the triangle count per mesh (the Roblox limit per MeshPart is ~10 000 - checked on upload).
    python3 gltf_pack.py model.gltf out.glb [--scale 3.5]
"""
import argparse
import base64
import json
import os
import struct

import numpy as np

CT_SIZE = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
CT_NP = {5120: "<i1", 5121: "<u1", 5122: "<i2", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
TYPE_N = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gltf")
    ap.add_argument("out")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--mesh", type=int, default=None, help="keep only the mesh with this index (stone sets -> separate stones)")
    a = ap.parse_args()
    base = os.path.dirname(os.path.abspath(a.gltf))
    js = json.load(open(a.gltf, encoding="utf-8"))
    if a.mesh is not None:  # a single mesh: the only node in the scene, without an offset (the stone will sit at the origin)
        js["nodes"] = [{"name": js["meshes"][a.mesh].get("name", "mesh"), "mesh": a.mesh}]
        js["scenes"] = [{"nodes": [0]}]
        js["scene"] = 0
    buffers = []
    for b in js.get("buffers", []):
        uri = b.get("uri", "")
        if uri.startswith("data:"):
            buffers.append(base64.b64decode(uri.split(",", 1)[1]))
        else:
            buffers.append(open(os.path.join(base, uri), "rb").read())
    # build a new single buffer: all bufferViews in a row
    newbuf = bytearray()
    views = []
    for v in js.get("bufferViews", []):
        src = buffers[v["buffer"]]
        off = v.get("byteOffset", 0)
        chunk = src[off:off + v["byteLength"]]
        nv = dict(v)
        nv["buffer"] = 0
        nv["byteOffset"] = len(newbuf)
        newbuf += pad4(bytes(chunk))
        views.append(nv)
    # position scale: rewrite the POSITION accessors (float32) right in the buffer
    if a.scale != 1.0:
        done = set()
        for m in js.get("meshes", []):
            for p in m.get("primitives", []):
                ai = p["attributes"].get("POSITION")
                if ai is None or ai in done:
                    continue
                done.add(ai)
                acc = js["accessors"][ai]
                v = views[acc["bufferView"]]
                stride = v.get("byteStride", 12)
                off = v["byteOffset"] + acc.get("byteOffset", 0)
                for i in range(acc["count"]):
                    o = off + i * stride
                    x, y, z = struct.unpack_from("<fff", newbuf, o)
                    struct.pack_into("<fff", newbuf, o, x * a.scale, y * a.scale, z * a.scale)
                if "min" in acc:
                    acc["min"] = [c * a.scale for c in acc["min"]]
                    acc["max"] = [c * a.scale for c in acc["max"]]
        for n in js.get("nodes", []):
            if "translation" in n:
                n["translation"] = [c * a.scale for c in n["translation"]]
    # images inside
    for im in js.get("images", []):
        uri = im.pop("uri", None)
        if uri is None:
            continue
        data = open(os.path.join(base, uri), "rb").read()
        mime = "image/png" if uri.lower().endswith(".png") else "image/jpeg"
        views.append({"buffer": 0, "byteOffset": len(newbuf), "byteLength": len(data)})
        newbuf += pad4(data)
        im["bufferView"] = len(views) - 1
        im["mimeType"] = mime
    js["bufferViews"] = views
    js["buffers"] = [{"byteLength": len(newbuf)}]
    # triangles per mesh
    for m in js.get("meshes", []):
        tris = 0
        for p in m.get("primitives", []):
            if "indices" in p:
                tris += js["accessors"][p["indices"]]["count"] // 3
            else:
                tris += js["accessors"][p["attributes"]["POSITION"]]["count"] // 3
        print("  mesh", m.get("name"), "triangles", tris)
    jb = pad4(json.dumps(js, separators=(",", ":")).encode("utf-8"), b" ")
    binc = bytes(newbuf)
    total = 12 + 8 + len(jb) + 8 + len(binc)
    with open(a.out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(binc), 0x004E4942) + binc)
    print(a.out, round(total / 1e6, 2), "MB, meshes", len(js.get("meshes", [])), "images", len(js.get("images", [])))


if __name__ == "__main__":
    main()
