#!/usr/bin/env python3
"""Decor from the Kenney Nature Kit (CC0): takes a GLB from the zip, splits the primitives of one mesh into separate
nodes named by material (woodBark, leafsGreen, grass, dirt, colorRed, ...), so that the Roblox import gives a Model of several
MeshParts that WorldBuilder colours with its palette via Color (Kenney has no textures, only the material colour).
The buffers and accessors are not touched, a new JSON chunk is written.

    python3 kenney_split.py kenney_nature-kit.zip out_dir name [name ...]
"""
import json
import os
import struct
import sys
import zipfile


def pad4(b, fill=b"\x00"):
    return b + fill * ((4 - len(b) % 4) % 4)


def read_glb(data):
    magic = struct.unpack("<I", data[:4])[0]
    assert magic == 0x46546C67, "not a GLB"
    off, js, binc = 12, None, b""
    while off < len(data):
        ln, typ = struct.unpack("<II", data[off:off + 8])
        chunk = data[off + 8:off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        elif typ == 0x004E4942:
            binc = chunk
        off += 8 + ln
    return js, binc


def write_glb(js, binc, path):
    jb = pad4(json.dumps(js, separators=(",", ":")).encode("utf-8"), b" ")
    bb = pad4(binc)
    total = 12 + 8 + len(jb) + 8 + len(bb)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(jb), 0x4E4F534A) + jb)
        f.write(struct.pack("<II", len(bb), 0x004E4942) + bb)


def split(js, name):
    mats = js.get("materials", [])
    new_meshes, new_nodes = [], []
    # the source nodes: tmpParent -> model; take the first mesh and its transform (Kenney's is identity)
    for mesh in js["meshes"]:
        used = {}
        for prim in mesh["primitives"]:
            mi = prim.get("material")
            mname = mats[mi].get("name", "mat%d" % mi) if mi is not None else "mat"
            used[mname] = used.get(mname, 0) + 1
            suffix = "" if used[mname] == 1 else str(used[mname])
            new_meshes.append({"name": mname + suffix, "primitives": [prim]})
            new_nodes.append({"name": mname + suffix, "mesh": len(new_meshes) - 1})
    root = {"name": name, "children": list(range(len(new_nodes)))}
    nodes = new_nodes + [root]
    out = dict(js)
    out["meshes"] = new_meshes
    out["nodes"] = nodes
    out["scenes"] = [{"name": name, "nodes": [len(nodes) - 1]}]
    out["scene"] = 0
    out["asset"] = {"version": "2.0", "generator": "kenney_split.py (Kenney Nature Kit, CC0)"}
    return out


def main():
    zip_path, out_dir, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    os.makedirs(out_dir, exist_ok=True)
    z = zipfile.ZipFile(zip_path)
    for name in names:
        data = z.read("Models/GLTF format/%s.glb" % name)
        js, binc = read_glb(data)
        out = split(js, name)
        path = os.path.join(out_dir, name + ".glb")
        write_glb(out, binc, path)
        print(name, "->", path, "nodes", len(out["nodes"]) - 1, [n["name"] for n in out["nodes"][:-1]])


if __name__ == "__main__":
    main()
