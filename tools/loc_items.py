#!/usr/bin/env python3
"""Our es/pt/de/fr for the Roblox passes, products and badges.

Roblox translates them by machine and in its own words (Starter Pack -> 'Paquete de inicio', in the game 'Paquete inicial'), badges and passes -
lazily, after the first request (GET name-description starts a machine translation into 19 languages within minutes). The machine does not
overwrite our translation. The names are THE SAME as in the game shop (locales/<lang>.csv: Strings.Shop.names, Content.Badges);
descriptions, time and gift copies - src/shared/locales/store_items.json. English - monetize.py CATALOG + gift_rows() and
the badge descriptions (Content.Badges + EN_BADGE below = the live Roblox text). The API key does not get into the output.

python3 roblox_game/tools/loc_items.py build    # the store item translations JSON + summary
python3 roblox_game/tools/loc_items.py check    # completeness, length (name <= 50), no {x}, names = the game shop
python3 roblox_game/tools/loc_items.py push     # PATCH .../{badges|game-passes|developer-products}/{id}/name-description/language-codes/{lang} - ONLY AFTER THE OWNER'S 'YES'
python3 roblox_game/tools/loc_items.py verify   # GET: our text live on es/pt/de/fr
"""
import csv
import importlib.util
import json
import os
import re
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
LOC = os.path.join(GAME, "src", "shared", "locales")
OUT = os.path.join(GAME, "docs", "announcements", "2026-10-19_store_items_es_pt_de_fr.json")
LANGS = ["es", "pt", "de", "fr"]
B = "https://apis.roblox.com/legacy-game-internationalization/v1"
# English badge descriptions - the live Roblox text (created by runs/roblox_badges_2026-10-17/create_badges.py)
EN_BADGE = {
    "hatch": "You hatched your first dragon.", "glide": "You glided down with a hatchling on your shoulder.",
    "rider": "You rode a juvenile dragon.", "flyer": "You flew on an adult dragon.", "ascend": "You completed Ascension I.",
    "party": "You helped a friend hatch an egg faster.", "index25": "Your Dragon Index is 25% complete.",
    "elder": "You raised an Elder dragon.", "ancient": "You hatched an Ancient dragon. Only a few exist.",
}
NAMES = {"Ember", "Frost", "Moss", "Tide", "Storm", "Dusk", "Glacier", "Pearl", "Cinder", "Nightfall", "Solstice"}


def monetize():
    argv, sys.argv = sys.argv, ["monetize.py", "--dry"]
    spec = importlib.util.spec_from_file_location("monetize", os.path.join(GAME, "monetize.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    sys.argv = argv
    return m


def csv_lang(lang):
    return {r["key"]: r for r in csv.DictReader(open(os.path.join(LOC, f"{lang}.csv"), encoding="utf-8"))}


def fill_names(s):
    return re.sub(r"\{(\w+)\}", lambda m: m.group(1) if m.group(1) in NAMES else m.group(0), s)


def ids():
    src = open(os.path.join(GAME, "src", "shared", "ShopIds.luau"), encoding="utf-8").read()
    passes = dict(re.findall(r"(\w+)\s*=\s*(\d+)", src.split("products")[0].split("passes", 1)[1]))
    products = dict(re.findall(r"(\w+)\s*=\s*(\d+)", src.split("products", 1)[1]))
    content = open(os.path.join(GAME, "src", "shared", "Content.luau"), encoding="utf-8").read()
    badges = re.findall(r"(\w+)\s*=\s*\{\s*id\s*=\s*(\d+),\s*name\s*=\s*\"([^\"]+)\"", content.split("Content.Badges = {")[1].split("\n}")[0])
    return passes, products, badges


def build():
    m = monetize()
    data = json.load(open(os.path.join(LOC, "store_items.json"), encoding="utf-8"))
    T, G, D = data["time"], data["gift"], data["descriptions"]
    rows = {lang: csv_lang(lang) for lang in LANGS}
    passes, products, badges = ids()
    sku_names = {key: name for key, _k, name, _d, _p, _g in m.CATALOG}

    def name_of(key, en, lang):
        R = rows[lang]
        def shop(k):
            return fill_names(R[f"Strings.Shop.names.{k}"]["text"])
        mt = re.match(r"(Hatch|Grow) now \((.+)\)$", en)
        if mt:
            return f"{shop('hatchNow' if mt.group(1) == 'Hatch' else 'growNow')} ({T[mt.group(2)][lang]})"
        mt = re.match(r"Treats x(\d+)$", en)
        if mt:
            return shop("treats").replace("{n}", mt.group(1))
        mt = re.match(r"Coins x2 for (.+)$", en)
        if mt:
            return shop("boost").replace("{time}", T[mt.group(1)][lang])
        mt = re.match(r"Nest income \((.+)\)$", en)
        if mt:  # in the game 'Nest income: {time}', in Roblox - in brackets, like Hatch now
            return re.sub(r"\s*:\s*\{time\}$", "", shop("income")) + f" ({T[mt.group(1)][lang]})"
        if en == "VIP":
            return "VIP"
        k = f"Strings.Shop.names.{key}"
        if k in R and R[k]["source"].replace("{", "").replace("}", "") == en:
            return fill_names(R[k]["text"])
        raise SystemExit(f"no name translation {key} '{en}' ({lang})")

    out = []
    for key, kind, en_name, en_desc, _price, _gift in m.CATALOG + m.gift_rows():
        base = key[5:] if key.startswith("Gift_") else key
        idv = (passes if kind == "pass" else products).get(key)
        item = {"kind": "game-passes" if kind == "pass" else "developer-products", "key": key, "id": idv,
                "en": {"name": en_name, "description": en_desc}}
        for lang in LANGS:
            if key.startswith("Gift_"):
                nm = name_of(base, sku_names[base], lang)
                item[lang] = {"name": G["name"][lang].replace("{name}", nm), "description": G["description"][lang].replace("{name}", nm)}
            else:
                if en_desc not in D:
                    raise SystemExit(f"no description translation '{en_desc}'")
                item[lang] = {"name": name_of(key, en_name, lang), "description": D[en_desc][lang]}
        out.append(item)
    for key, idv, en_name in badges:
        item = {"kind": "badges", "key": key, "id": idv, "en": {"name": en_name, "description": EN_BADGE[key]}}
        for lang in LANGS:
            item[lang] = {"name": rows[lang][f"Content.Badges.{key}.name"]["text"], "description": D[EN_BADGE[key]][lang]}
        out.append(item)
    # the non-breaking space of French typography (' : ' in locales/fr.csv) is rejected by Roblox in product names as
    # 'New name or description is moderated' - in the Roblox shop texts only a normal space (in the game NBSP stays)
    for it in out:
        for lang in LANGS:
            for f in ("name", "description"):
                it[lang][f] = it[lang][f].replace("\u00a0", " ").replace("\u202f", " ")
    return out


def check(items):
    bad = []
    for it in items:
        if not it["id"]:
            bad.append(f"{it['key']}: no id")
        for lang in LANGS:
            n, d = it[lang]["name"], it[lang]["description"]
            if not n or not d:
                bad.append(f"{it['key']} {lang}: empty")
            if len(n) > 50:
                bad.append(f"{it['key']} {lang}: name {len(n)} > 50: {n}")
            if len(d) > 1000:
                bad.append(f"{it['key']} {lang}: description > 1000")
            if re.search("[\u00a0\u202f]", n + d):
                bad.append(f"{it['key']} {lang}: non-breaking space (Roblox rejects)")
            if re.search(r"\{\w+\}", n + d):
                bad.append(f"{it['key']} {lang}: unsubstituted {{x}}: {n} | {d}")
            for nm in NAMES | {"VIP"}:  # names and VIP are not translated: if present in English - present in the translation too
                if re.search(rf"\b{nm}\b", it["en"]["name"] + " " + it["en"]["description"]) and not re.search(rf"\b{nm}\b", n + " " + d):
                    bad.append(f"{it['key']} {lang}: lost name {nm}")
    return bad


def api(method, path, body=None):
    key = open(os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")).read().strip()
    for attempt in range(5):
        r = requests.request(method, B + path, headers={"x-api-key": key, "Content-Type": "application/json"},
                             data=None if body is None else json.dumps(body), timeout=60)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(2 ** attempt * 2)
            continue
        return r
    return r


def push(items):
    ok, fail = 0, []
    for it in items:
        for lang in LANGS:
            r = api("PATCH", f"/{it['kind']}/{it['id']}/name-description/language-codes/{lang}",
                    {"name": it[lang]["name"], "description": it[lang]["description"]})
            if r.status_code == 200:
                ok += 1
            else:
                fail.append(f"{it['key']} {lang}: HTTP {r.status_code} {r.text[:160]}")
            time.sleep(0.25)
    print(f"uploaded {ok} of {len(items) * len(LANGS)}; failures {len(fail)}")
    for f in fail[:10]:
        print("  ", f)
    return not fail


def verify(items):
    good, diff = 0, []
    for it in items:
        r = api("GET", f"/{it['kind']}/{it['id']}/name-description")
        live = {x["languageCode"]: x for x in (r.json().get("data") or [])} if r.status_code == 200 else {}
        for lang in LANGS:
            x = live.get(lang) or {}
            if (x.get("name") or "").strip() == it[lang]["name"] and (x.get("description") or "").strip() == it[lang]["description"]:
                good += 1
            else:
                diff.append(f"{it['key']} {lang}: live '{x.get('name')}' / '{(x.get('description') or '')[:60]}'")
        time.sleep(0.2)
    print(f"our text live: {good} of {len(items) * len(LANGS)}")
    for d in diff[:15]:
        print("  ", d)
    return not diff


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "build"
    items = build()
    problems = check(items)
    kinds = {k: sum(1 for i in items if i["kind"] == k) for k in ("game-passes", "developer-products", "badges")}
    print(f"items {len(items)} {kinds}; entries (item x language) {len(items) * len(LANGS)}; problems {len(problems)}")
    for p in problems:
        print("  ", p)
    if cmd == "build":
        json.dump(items, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("written:", OUT)
    elif cmd == "check":
        sys.exit(1 if problems else 0)
    elif cmd == "push":
        if problems:
            sys.exit("there are problems - not uploading")
        sys.exit(0 if push(items) else 1)
    elif cmd == "verify":
        sys.exit(0 if verify(items) else 1)
