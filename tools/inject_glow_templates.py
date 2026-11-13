#!/usr/bin/env python3
"""Moving the glow templates (ReplicatedStorage.GlowTemplates - SurfaceAppearance with maps, baked in Studio on P8,
tests/p8/glowegg_bake.py) from a saved place file into a fresh build build/place.rbxlx - without a new Studio session.
    python3 tools/inject_glow_templates.py <file with the baked templates> [build/place.rbxlx]"""
import re, sys
src_path = sys.argv[1]
dst_path = sys.argv[2] if len(sys.argv) > 2 else "build/place.rbxlx"
src = open(src_path, encoding="utf-8").read()
dst = open(dst_path, encoding="utf-8").read()

def item_span(text, start):
    # the end of the <Item ...> element from start (nested Items are taken into account)
    depth, i = 0, start
    tok = re.compile(r"<Item\b|</Item>")
    for m in tok.finditer(text, start):
        depth += 1 if m.group(0) == "<Item" else -1
        if depth == 0:
            return m.end()
    raise SystemExit("unclosed Item")

name = text_pos = src.find('<string name="Name">GlowTemplates</string>')
if name < 0:
    raise SystemExit("the source file has no GlowTemplates")
start = src.rfind('<Item class="Folder"', 0, name)
block = src[start:item_span(src, start)]
# the Studio file stores the tags (Tags) as references to the shared <SharedStrings> dictionary at the end of the file; the build does not have it - the server
# cannot load the place ('Waiting for an available server'). The templates do not need tags - remove the references
block, n_sh = re.subn(r"\s*<SharedString name=\"[^\"]+\">[^<]*</SharedString>", "", block)
assert "SharedString" not in block, "SharedString references remain in the block"
n_sa = block.count('class="SurfaceAppearance"')
if 'name="Name">GlowTemplates<' in dst:
    raise SystemExit("the build already has GlowTemplates")
rs = dst.find('<Item class="ReplicatedStorage"')
if rs < 0:
    raise SystemExit("the build has no ReplicatedStorage")
end = item_span(dst, rs)
close = dst.rfind("</Item>", rs, end)
dst = dst[:close] + block + "\n" + dst[close:]
open(dst_path, "w", encoding="utf-8").write(dst)
print(f"GlowTemplates moved: {n_sa} SurfaceAppearance, SharedString references removed {n_sh} -> {dst_path}")
