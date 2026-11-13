#!/usr/bin/env python3
"""Game passes and developer products of the shop through Open Cloud:
13 SKU types = 23 products + 7 passes + 19 gift copies [Gift].
Idempotent: reads what already exists by name, creates only the missing ones, takes old items that are not in the catalog off sale
(isForSale=false; Open Cloud cannot delete), then writes the ids into src/shared/ShopIds.luau (generated, do not edit by hand)
and the state into monetization.json. The key comes from the file in ROBLOX_OPENCLOUD_KEY_FILE and never reaches the output.
Endpoints per the creator-docs specification (game-passes-http-service/v1.json, developer-products-api/v1.json).

python3 monetize.py --dry               # plan only (what to create, what to take off sale)
python3 monetize.py                     # the game (universe 10769731146)
python3 monetize.py --universe <id>     # another game

SKU keys (= keys of the Core/Shop.luau catalog; tests/shop_spec.luau compares both lists):
products: HatchNow_5..49, GrowNow_5..49, StarterPack_49, Treats_1_49/3_129/10_399, Boost30_49, Boost120_149,
NestIncome1h_99/4h_299/24h_699, Preset_Sunset_99, Trail_Comet_149, NestSkin_Lagoon_299, NestBundle_2999
passes:   VIP_299, X2Coins_299, AutoCollect_149, NestSlot1_99, NestSlot2_199, NestSlot3_399, FastIncubator_249
gifts:    Gift_<key> for everything except HatchNow, GrowNow and StarterPack - 19 products at the same price.
"""
import datetime
import json
import os
import sys

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
IDS_LUAU = os.path.join(HERE, "src", "shared", "ShopIds.luau")
STATE = os.path.join(HERE, "monetization.json")
UNIVERSE = int(sys.argv[sys.argv.index("--universe") + 1]) if "--universe" in sys.argv else 10769731146
DRY = "--dry" in sys.argv

# (key, kind, name in the Roblox shop, description, price R$, whether a [Gift] copy exists) - 07_shop.md §2 and the appendix
CATALOG = [
    ("HatchNow_5", "product", "Hatch now (1 min)", "Finish hatching an egg with up to 1 minute left. The outcome is already set, Hatch now only saves time.", 5, False),
    ("HatchNow_9", "product", "Hatch now (5 min)", "Finish hatching an egg with up to 5 minutes left. The outcome is already set, Hatch now only saves time.", 9, False),
    ("HatchNow_19", "product", "Hatch now (20 min)", "Finish hatching an egg with up to 20 minutes left. The outcome is already set, Hatch now only saves time.", 19, False),
    ("HatchNow_29", "product", "Hatch now (1 hour)", "Finish hatching an egg with up to 1 hour left. The outcome is already set, Hatch now only saves time.", 29, False),
    ("HatchNow_49", "product", "Hatch now (any)", "Finish hatching any egg right away. The outcome is already set, Hatch now only saves time.", 49, False),
    ("GrowNow_5", "product", "Grow now (1 min)", "Finish a dragon's growth timer with up to 1 minute left.", 5, False),
    ("GrowNow_9", "product", "Grow now (5 min)", "Finish a dragon's growth timer with up to 5 minutes left.", 9, False),
    ("GrowNow_19", "product", "Grow now (20 min)", "Finish a dragon's growth timer with up to 20 minutes left.", 19, False),
    ("GrowNow_29", "product", "Grow now (1 hour)", "Finish a dragon's growth timer with up to 1 hour left.", 29, False),
    ("GrowNow_49", "product", "Grow now (any)", "Finish any dragon's growth timer right away.", 49, False),
    ("StarterPack_49", "product", "Starter Pack",
     "Two eggs of your chosen elements (Rare or better), a second incubator and a rider scarf. One per account.", 49, False),
    ("VIP_299", "pass", "VIP", "+1 nest slot, +10% coins (also offline), VIP name tag and the Gilded nest skin. Yours forever.", 299, True),
    ("X2Coins_299", "pass", "x2 Coins", "Your nest earns double coins forever.", 299, True),
    ("AutoCollect_149", "pass", "Auto Collect", "Nest coins go straight to your balance. Yours forever.", 149, True),
    ("NestSlot1_99", "pass", "Nest slot +1 (I)", "One more dragon earns in your nest. Yours forever.", 99, True),
    ("NestSlot2_199", "pass", "Nest slot +1 (II)", "One more dragon earns in your nest. Requires slot I. Yours forever.", 199, True),
    ("NestSlot3_399", "pass", "Nest slot +1 (III)", "One more dragon earns in your nest. Requires slot II. Yours forever.", 399, True),
    ("FastIncubator_249", "pass", "Fast Incubator", "All eggs hatch 40% faster. Yours forever.", 249, True),
    ("Treats_1_49", "product", "Treats x1", "A treat finishes half of a dragon's growth timer.", 49, True),
    ("Treats_3_129", "product", "Treats x3", "Three treats. A treat finishes half of a dragon's growth timer.", 129, True),
    ("Treats_10_399", "product", "Treats x10", "Ten treats. A treat finishes half of a dragon's growth timer.", 399, True),
    ("Boost30_49", "product", "Coins x2 for 30 min", "Double coins while you play. The timer only runs in game.", 49, True),
    ("Boost120_149", "product", "Coins x2 for 2 h", "Double coins while you play. The timer only runs in game.", 149, True),
    ("NestIncome1h_99", "product", "Nest income (1 h)", "Coins equal to your nest income for 1 hour, at your current rate.", 99, True),
    ("NestIncome4h_299", "product", "Nest income (4 h)", "Coins equal to your nest income for 4 hours, at your current rate.", 299, True),
    ("NestIncome24h_699", "product", "Nest income (24 h)", "Coins equal to your nest income for 24 hours, at your current rate.", 699, True),
    ("Preset_Sunset_99", "product", "Sunset color preset", "A warm color preset for one dragon.", 99, True),
    ("Trail_Comet_149", "product", "Comet flight trail", "A glowing trail behind you in flight. Yours forever.", 149, True),
    ("NestSkin_Lagoon_299", "product", "Lagoon nest skin", "A new look for your nest. Yours forever.", 299, True),
    # products of updates 2-4 (shown in the game from the update date; in Roblox the product exists in advance)
    ("Trail_Tidal_149", "product", "Tidal flight trail", "A sea-blue trail behind you in flight. Yours forever.", 149, True),
    ("NestSkin_Night_299", "product", "Night Sky nest skin", "A starry night look for your nest. Yours forever.", 299, True),
    ("DragonWeek_1_199", "product", "Dragon of the week: Cinder",
     "An Epic Ember hatchling with glowing cinder colors. One per account.", 199, True),
    ("DragonWeek_2_299", "product", "Dragon of the week: Nightfall", "A Legendary Dusk hatchling. One per account.", 299, True),
    ("NestBundle_2999", "product", "Everything for the Nest",
     "Royal nest skin, three nest slots, the Royal aura and the Nest Lord title. Yours forever.", 2999, True),
]


def gift_rows():
    out = []
    for key, _kind, name, _desc, price, gift in CATALOG:
        if gift:
            out.append(("Gift_" + key, "product", "Gift: " + name, f"Send {name} to another player on this server.", price, False))
    return out


def api(method, path, key, **kw):
    r = requests.request(method, "https://apis.roblox.com" + path, headers={"x-api-key": key}, timeout=60, **kw)
    if r.status_code >= 300:
        raise SystemExit(f"{method} {path} -> HTTP {r.status_code}: {r.text.replace(key, '<key>')[:300]}")
    return r.json() if r.text.strip() else {}


def list_all(path, field, key):
    out, tok = [], None
    while True:
        js = api("GET", path, key, params={"pageSize": 100, **({"pageToken": tok} if tok else {})})
        out += js.get(field) or []
        tok = js.get("nextPageToken")
        if not tok:
            return out


def form(**fields):
    return {k: (None, str(v)) for k, v in fields.items()}


def main():
    key = open(KEY_FILE).read().strip()
    rows = CATALOG + gift_rows()
    have_passes = {p["name"]: p["gamePassId"] for p in
                   list_all(f"/game-passes/v1/universes/{UNIVERSE}/game-passes/creator", "gamePasses", key)}
    have_products = {p["name"]: p["productId"] for p in
                     list_all(f"/developer-products/v2/universes/{UNIVERSE}/developer-products/creator", "developerProducts", key)}
    wanted_names = {name for _k, _kind, name, _d, _p, _g in rows}
    old_passes = {n: i for n, i in have_passes.items() if n not in wanted_names}
    old_products = {n: i for n, i in have_products.items() if n not in wanted_names}
    to_create = [r for r in rows if r[2] not in (have_passes if r[1] == "pass" else have_products)]
    print(f"universe {UNIVERSE}: catalog has {len(rows)} items ({sum(1 for r in rows if r[1] == 'pass')} passes), "
          f"already exist {len(rows) - len(to_create)}, to create {len(to_create)}, old ones to take off sale: {len(old_passes) + len(old_products)}")
    for r in to_create:
        print(f"  + {r[1]:7} {r[0]:22} {r[4]:>5} R$  {r[2]}")
    for n in old_passes:
        print(f"  - pass not in the catalog: {n} ({old_passes[n]})")
    for n in old_products:
        print(f"  - product not in the catalog: {n} ({old_products[n]})")
    if DRY:
        return
    passes, products = {}, {}
    for k, kind, name, desc, price, _gift in rows:
        if kind == "pass":
            if name not in have_passes:
                js = api("POST", f"/game-passes/v1/universes/{UNIVERSE}/game-passes", key,
                         files=form(name=name, description=desc, isForSale="true", price=price, isRegionalPricingEnabled="true"))
                have_passes[name] = js["gamePassId"]
                print(f"created pass {name} for {price} R$: {js['gamePassId']}")
            passes[k] = have_passes[name]
        else:
            if name not in have_products:
                js = api("POST", f"/developer-products/v2/universes/{UNIVERSE}/developer-products", key,
                         files=form(name=name, description=desc, isForSale="true", price=price, isRegionalPricingEnabled="true"))
                have_products[name] = js["productId"]
                print(f"created product {name} for {price} R$: {js['productId']}")
            products[k] = have_products[name]
    # old items (an early test game: x2 Cash, +2 Pet Slots, x2 Luck, Cash Pack, Big Cash Pack) - off sale
    for n, pid in old_passes.items():
        try:
            api("PATCH", f"/game-passes/v1/game-passes/{pid}", key, files=form(isForSale="false"))
            print(f"pass {n} taken off sale")
        except SystemExit as e:
            print(f"could not take pass {n} off sale: {e}")
    for n, pid in old_products.items():
        try:
            api("PATCH", f"/developer-products/v2/universes/{UNIVERSE}/developer-products/{pid}", key, files=form(isForSale="false"))
            print(f"product {n} taken off sale")
        except SystemExit as e:
            print(f"could not take product {n} off sale: {e}")
    del key
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    lines = ["--!strict",
             f"-- Generated by monetize.py {stamp}: Roblox pass and product ids for universe {UNIVERSE}. Do not edit by hand:",
             "-- to add a SKU, add a row to CATALOG in monetize.py + an entry in Core/Shop.luau, then run python3 monetize.py.",
             "return {", f"\tuniverse = {UNIVERSE},", "\tpasses = {"]
    lines += [f"\t\t{k} = {v}," for k, v in passes.items()]
    lines += ["\t},", "\tproducts = {"]
    lines += [f"\t\t{k} = {v}," for k, v in products.items()]
    lines += ["\t},", "}", ""]
    open(IDS_LUAU, "w", encoding="utf-8").write("\n".join(lines))
    json.dump({"universe": UNIVERSE, "generated": stamp, "passes": passes, "products": products,
               "retired": {"passes": old_passes, "products": old_products}}, open(STATE, "w"), indent=1)
    print(f"ids written: {IDS_LUAU} ({len(passes)} passes, {len(products)} products)")


if __name__ == "__main__":
    main()
