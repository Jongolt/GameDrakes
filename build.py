#!/usr/bin/env python3
"""Build the Roblox place (.rbxlx) from the sources without Rojo.

src/first/**              -> ReplicatedFirst                      (client entry point, loading screen)
src/shared/**             -> ReplicatedStorage/Shared             (Config, Content, Strings, Remotes, Core/...)
src/server/**             -> ServerScriptService                  (Main.server.luau, Services/...)
src/client/**             -> StarterPlayer/StarterPlayerScripts   (Controllers/...)
vendor/ProfileStore.luau  -> ServerScriptService/Vendor/ProfileStore

Classes by suffix: *.server.luau -> Script, *.client.luau -> LocalScript, *.luau -> ModuleScript; folders -> Folder.
require("./X") and require("../X") in the sources (the luau CLI understands them in tests) are rewritten into
require(script.Parent.X) / require(script.Parent.Parent.X). Lighting and effects are written into the file from Config.Lighting
(through tests/dump_lighting.luau - a single source of numbers), Players.CharacterAutoLoads = false. The world is built by services at start.

python3 build.py            # -> build/place.rbxlx; then tools/lune/lune run tests/inspect_place.luau build/place.rbxlx
"""
import os
import re
import subprocess
import sys
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "src")
OUT = os.path.join(HERE, "build", "place.rbxlx")
LUAU = os.environ.get("LUAU", "luau")
_ref = [0]


def ref():
    _ref[0] += 1
    return f"RBX{_ref[0]}"


# ---------------------------------------------------------------------------------------------- properties
def p_float(name, v):
    return f'<float name="{name}">{v}</float>'


def p_bool(name, v):
    return f'<bool name="{name}">{"true" if v else "false"}</bool>'


def p_int(name, v):
    return f'<int name="{name}">{int(v)}</int>'


def p_token(name, v):
    return f'<token name="{name}">{int(v)}</token>'


def p_string(name, v):
    return f'<string name="{name}">{escape(v)}</string>'


def p_color3(name, rgb):
    r, g, b = (float(c) / 255 for c in rgb)
    return f'<Color3 name="{name}"><R>{r:.6f}</R><G>{g:.6f}</G><B>{b:.6f}</B></Color3>'


def item(cls, name, props="", children=()):
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>{p_string("Name", name)}{props}</Properties>'
            f'{"".join(children)}</Item>')


# ---------------------------------------------------------------------------------------------- scripts
REQ = re.compile(r'require\("((?:\.\./)+|\./)([\w/]+)"\)')


def rewrite_requires(source, fname):
    def sub(m):
        ups = m.group(1).count("../")
        parts = m.group(2).split("/")
        path = "script.Parent" + ".Parent" * ups
        for part in parts:
            if not re.fullmatch(r"[A-Za-z_]\w*", part):
                sys.exit(f"{fname}: module name is not an identifier: {part}")
            path += "." + part
        return f"require({path})"
    return REQ.sub(sub, source)


def script(cls, name, source, fname):
    source = rewrite_requires(source, fname)
    if "]]>" in source:
        sys.exit(f"{fname} contains ]]>, CDATA would break")
    return (f'<Item class="{cls}" referent="{ref()}"><Properties>{p_string("Name", name)}'
            f'<ProtectedString name="Source"><![CDATA[{source}]]></ProtectedString></Properties></Item>')


def folder(name, children):
    return item("Folder", name, "", children)


def tree(path):
    """Contents of a source folder -> list of Items (folders recursively, files by suffix)."""
    out = []
    if not os.path.isdir(path):
        return out
    for entry in sorted(os.listdir(path)):
        full = os.path.join(path, entry)
        if os.path.isdir(full):
            if entry.startswith("__") or entry.startswith("."):
                continue
            out.append(folder(entry, tree(full)))
        elif entry.endswith(".luau"):
            src = open(full, encoding="utf-8").read()
            if entry.endswith(".server.luau"):
                out.append(script("Script", entry[:-len(".server.luau")], src, full))
            elif entry.endswith(".client.luau"):
                out.append(script("LocalScript", entry[:-len(".client.luau")], src, full))
            else:
                out.append(script("ModuleScript", entry[:-len(".luau")], src, full))
    return out


def count_scripts(path):
    n = 0
    for _, dirs, files in os.walk(path):
        dirs[:] = [d for d in dirs if not d.startswith("__")]
        n += sum(1 for f in files if f.endswith(".luau"))
    return n


# ---------------------------------------------------------------------------------------------- lighting from Config
def read_lighting():
    r = subprocess.run([LUAU, os.path.join(HERE, "tests", "dump_lighting.luau")], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("dump_lighting.luau failed: " + r.stderr[:500])
    cfg = {}
    for line in r.stdout.splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            cfg[k.strip()] = v.strip()
    return cfg


def rgb(s):
    return [float(x) for x in s.split(",")]


LIGHTING_STYLE = {"Realistic": 0, "Soft": 1}  # Enum.LightingStyle; checked by Lune after the build
TECHNOLOGY = {"Legacy": 0, "Voxel": 1, "Compatibility": 2, "ShadowMap": 3, "Future": 4}  # Enum.Technology (place file only)
MATERIAL = {"Rock": 896, "Limestone": 820, "Ground": 1360, "Sand": 1296, "Mud": 1344, "Grass": 1280, "LeafyGrass": 1284,
            "Slate": 800, "Basalt": 788}  # Enum.Material for the BaseMaterial of a variant (codes verified with Lune)
TEXTURES_STATE = os.path.join(HERE, "assets_textures.json")  # image ids (tools/upload_image.py)


def lighting_item(L):
    props = (p_token("LightingStyle", LIGHTING_STYLE[L["style"]])
             + p_token("Technology", TECHNOLOGY[L.get("technology", "ShadowMap")])
             + p_float("GeographicLatitude", L.get("geographicLatitude", 41.733))
             + p_float("ShadowSoftness", L.get("shadowSoftness", 0.2))
             + p_bool("PrioritizeLightingQuality", L["prioritizeQuality"] == "true")
             + p_float("Brightness", L["brightness"])
             + p_color3("Ambient", rgb(L["ambient"]))
             + p_color3("OutdoorAmbient", rgb(L["outdoorAmbient"]))
             + p_color3("ColorShift_Top", rgb(L["colorShiftTop"]))
             + p_float("EnvironmentDiffuseScale", L["envDiffuse"])
             + p_float("EnvironmentSpecularScale", L["envSpecular"])
             + p_float("ExposureCompensation", L["exposure"])
             + p_bool("GlobalShadows", L["globalShadows"] == "true")
             + p_float("ClockTime", L["clockTime"]))
    sky = item("Sky", "Sky", p_float("SunAngularSize", L["sunAngularSize"]) + p_float("MoonAngularSize", 11))
    atmo = item("Atmosphere", "Atmosphere",
                p_float("Density", L["atmosphere.density"]) + p_float("Offset", L["atmosphere.offset"])
                + p_color3("Color", rgb(L["atmosphere.color"])) + p_color3("Decay", rgb(L["atmosphere.decay"]))
                + p_float("Glare", L["atmosphere.glare"]) + p_float("Haze", L["atmosphere.haze"]))
    bloom = item("BloomEffect", "Bloom", p_bool("Enabled", True) + p_float("Intensity", L["bloom.intensity"])
                 + p_float("Size", L["bloom.size"]) + p_float("Threshold", L["bloom.threshold"]))
    rays = item("SunRaysEffect", "SunRays", p_bool("Enabled", True) + p_float("Intensity", L["sunRays.intensity"])
                + p_float("Spread", L["sunRays.spread"]))
    cc = item("ColorCorrectionEffect", "ColorCorrection", p_bool("Enabled", True)
              + p_float("Saturation", L["colorCorrection.saturation"]) + p_float("Contrast", L["colorCorrection.contrast"])
              + p_float("Brightness", L["colorCorrection.brightness"]))
    blur = item("BlurEffect", "MenuBlur", p_bool("Enabled", True) + p_float("Size", 0))
    return item("Lighting", "Lighting", props, [sky, atmo, bloom, rays, cc, blur])


def part(cls, name, size, pos, rgb_, extra="", yaw180=False):
    # yaw180: rotate 180 degrees around Y (LookVector +Z instead of -Z) - the SpawnLocation faces the plaza (spec 04 §2)
    m = {(0, 0): -1 if yaw180 else 1, (1, 1): 1, (2, 2): -1 if yaw180 else 1}
    rot = "".join(f"<R{i}{j}>{m.get((i, j), 0)}</R{i}{j}>" for i in range(3) for j in range(3))
    props = (p_bool("Anchored", True)
             + f'<Vector3 name="size"><X>{size[0]}</X><Y>{size[1]}</Y><Z>{size[2]}</Z></Vector3>'
             + f'<CoordinateFrame name="CFrame"><X>{pos[0]}</X><Y>{pos[1]}</Y><Z>{pos[2]}</Z>{rot}</CoordinateFrame>'
             + f'<Color3uint8 name="Color3uint8">{(int(rgb_[0]) << 16) | (int(rgb_[1]) << 8) | int(rgb_[2])}</Color3uint8>' + extra)
    return item(cls, name, props)


def terrain_decoration():
    """Config.World.terrainDecoration -> Terrain.Decoration in the place file (the property is not available to scripts)."""
    r = subprocess.run([LUAU, os.path.join(HERE, "tests", "dump_world_flags.luau")], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("dump_world_flags.luau failed: " + r.stderr[:300])
    flags = dict(line.split("=", 1) for line in r.stdout.splitlines() if "=" in line)
    return {k.strip(): v.strip() for k, v in flags.items()}


def p_content(name, asset_id):
    return f'<Content name="{name}"><uri>rbxassetid://{int(asset_id)}</uri></Content>'


def read_materials():
    """Config.World.materials -> (enabled, [variant]) through tests/dump_materials.luau."""
    r = subprocess.run([LUAU, os.path.join(HERE, "tests", "dump_materials.luau")], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("dump_materials.luau failed: " + r.stderr[:300])
    enabled, variants = False, []
    for line in r.stdout.splitlines():
        if line.startswith("enabled="):
            enabled = line.strip() == "enabled=true"
        elif line.startswith("variant="):
            name, base, texture, studs, tint = line[len("variant="):].strip().split("|")
            variants.append({"name": name, "base": base, "texture": texture, "studs": float(studs), "tint": rgb(tint)})
    return enabled, variants


def material_service(enabled, variants):
    """MaterialService with terrain MaterialVariants: color/normal/roughness maps from assets_textures.json
    (tools/upload_image.py; Approved only); the base material override is the <Base>Name property.
    A variant without an uploaded color map is skipped with a warning."""
    ids = {}
    if os.path.exists(TEXTURES_STATE):
        import json
        for name, v in json.load(open(TEXTURES_STATE, encoding="utf-8")).items():
            if v.get("assetId") and v.get("moderation") in (None, "Approved", "Reviewing"):  # Reviewing: the image is already served; upload_image.py --refresh updates the status
                ids[name] = v["assetId"]
    overrides, children, used = "", [], []
    for v in (variants if enabled else []):
        color = ids.get(f"tex_{v['texture']}_color")
        if not color:
            print(f"  variant {v['name']}: no color map tex_{v['texture']}_color in assets_textures.json - skipped")
            continue
        props = p_token("BaseMaterial", MATERIAL[v["base"]]) + p_token("MaterialPattern", 1) + p_float("StudsPerTile", v["studs"]) + p_content("ColorMapContent", color)
        for suffix, prop in (("normal", "NormalMapContent"), ("rough", "RoughnessMapContent")):
            base_tex = v["texture"].rsplit("_v", 1)[0]  # _v2 maps share the normal and roughness maps of the original
            aid = ids.get(f"tex_{v['texture']}_{suffix}") or ids.get(f"tex_{base_tex}_{suffix}")
            if aid:
                props += p_content(prop, aid)
        children.append(item("MaterialVariant", v["name"], props))
        overrides += p_string(v["base"] + "Name", v["name"])
        used.append(v["name"])
    return item("MaterialService", "MaterialService", overrides, children), used


MODEL_STREAMING = {"Default": 0, "Legacy": 1, "Improved": 2}  # Enum.ModelStreamingBehavior (verified with Lune)


def workspace_props(flags):
    """C3: StreamingEnabled and the radii live only in the place file (scripts cannot change the property)."""
    if flags.get("streamingEnabled") != "true":
        return p_bool("StreamingEnabled", False)
    return (p_bool("StreamingEnabled", True) + p_int("StreamingMinRadius", float(flags.get("streamingMin", 64)))
            + p_int("StreamingTargetRadius", float(flags.get("streamingTarget", 1024)))
            + p_token("ModelStreamingBehavior", MODEL_STREAMING.get(flags.get("streamingBehavior", "Default"), 0)))


def localization_item():
    """Before the build, refreshes LocaleData.luau from the translations in git (tools/locales.py) - the Loc module reads it.
    The LocalizationTable is NOT put into the place: static labels are translated by the game's cloud table (our es/pt/de/fr
    + Roblox machine translation, uploaded by tools/loc_cloud.py table); a table in the place could block the cloud
    machine translation - one source only."""
    sys.path.insert(0, os.path.join(HERE, "tools"))
    import locales
    src, ok, report = locales.load()
    locales.write_luau(src, ok)
    done = " ".join(f"{lang} {report[lang]['done']}/{report[lang]['total']}" for lang in locales.LANGS)
    return "", f"LocaleData ({done}), the table lives in the cloud"


def build():
    loc_item, loc_note = localization_item()
    L = read_lighting()
    mat_enabled, variants = read_materials()
    mat_item, mat_used = material_service(mat_enabled, variants)
    flags = terrain_decoration()
    deco = flags.get("terrainDecoration") == "true"
    world = [part("SpawnLocation", "SpawnLocation", (12, 1, 12), (0, 18.5, -20), (200, 185, 165),
                  p_bool("Neutral", True) + p_int("Duration", 0) + p_token("Material", 272) + p_token("TopSurface", 0)
                  + p_token("BottomSurface", 0)
                  # the plate lay on the plaza 0.5 above the stone, smooth plastic; the plate is invisible, pass-through
                  # does not exist for the camera or rays. the player spawned with the BACK to the plaza
                  # (an unrotated plate looks at -Z, toward the stall and the sea), Old Ash and the table behind - spec 04 §2 requires "facing the plaza":
                  # yaw180 - LookVector +Z, Old Ash 20 studs ahead. The plate moved from z -30 to -20: facing the plaza, the camera
                  # behind the back (12.5 studs) ended up inside the red stall roof (StallRoof z -43..-38, frame spawn_face_check F0 10:54) -
                  # red screen; at -20 the camera is 7 studs from the roof and the stall's Feed hint (radius 12) does not fire on spawn
                  + p_float("Transparency", 1) + p_bool("CanCollide", False) + p_bool("CanQuery", False) + p_bool("CanTouch", False),
                  yaw180=True),
             item("Terrain", "Terrain", p_bool("Decoration", deco) + p_float("GrassLength", flags.get("grassLength", "1")),
                  [item("Clouds", "Clouds", p_bool("Enabled", True) + p_float("Cover", flags.get("cloudCover", "0.5"))
                        + p_float("Density", flags.get("cloudDensity", "0.3")) + p_color3("Color", (255, 255, 255)))])]  # terrain grass + volumetric clouds
    vendor = [script("ModuleScript", "ProfileStore",
                     open(os.path.join(HERE, "vendor", "ProfileStore.luau"), encoding="utf-8").read(), "vendor/ProfileStore.luau")]
    xml = ('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
           'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">'
           + item("Workspace", "Workspace", workspace_props(flags), world)
           + lighting_item(L)
           + mat_item
           + item("Players", "Players", p_bool("CharacterAutoLoads", False))
           + loc_item
           + item("ReplicatedFirst", "ReplicatedFirst", "", tree(os.path.join(SRC, "first")) + baked_models())
           + item("ReplicatedStorage", "ReplicatedStorage", "", [folder("Shared", tree(os.path.join(SRC, "shared")))])
           + item("ServerScriptService", "ServerScriptService", "", tree(os.path.join(SRC, "server")) + [folder("Vendor", vendor)])
           + item("StarterPlayer", "StarterPlayer", p_float("CameraMinZoomDistance", 8) + p_float("CameraMaxZoomDistance", 60), [item("StarterPlayerScripts", "StarterPlayerScripts", "", tree(os.path.join(SRC, "client")))])
           + "</roblox>")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "w", encoding="utf-8").write(xml)
    n = {k: count_scripts(os.path.join(SRC, k)) for k in ("first", "shared", "server", "client")}
    print(f"built {OUT}: scripts first {n['first']}, shared {n['shared']}, server {n['server']}, client {n['client']}, "
          f"vendor 1; {len(xml) / 1024:.0f} KB; lighting {L['style']}/{L.get('technology', '-')} Brightness {L['brightness']}; "
          f"Terrain.Decoration {deco}; MaterialVariant {len(mat_used)}: {', '.join(mat_used) or '-'}; "
          f"Streaming {flags.get('streamingEnabled')} ({flags.get('streamingMin')}-{flags.get('streamingTarget')}); "
          f"localization {loc_note}")


SPLASH = os.path.join(HERE, "assets_src", "splash", "LoadingDragon.rbxmx")


def baked_models():
    """Ready models in ReplicatedFirst - the 3D hatchling of the loading screen (tools/make_splash_model.luau) reaches the client first,
    without waiting for the server. XML as is, referents prefixed so they do not collide with RBX<n>."""
    if not os.path.exists(SPLASH):
        # the splash model is mandatory (*.rbxmx is in .gitignore): without it the loading screen falls back to a picture - do not build silently
        sys.exit(f"missing {SPLASH} - the 3D hatchling of the loading screen; the file is in git (an exception in .gitignore)")
    x = open(SPLASH, encoding="utf-8").read()
    body = x[x.index("<Item"):x.rindex("</roblox>")]
    body = re.sub(r'referent="(\w+)"', r'referent="SPLASH\1"', body)
    body = re.sub(r'(<Ref name="\w+">)(\w+)(</Ref>)', lambda m: m.group(1) + (m.group(2) if m.group(2) == "null" else "SPLASH" + m.group(2)) + m.group(3), body)
    return [body]


if __name__ == "__main__":
    build()
