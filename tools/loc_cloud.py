#!/usr/bin/env python3
"""Localization in the Roblox cloud with our Open Cloud key.

Order: (1) languages - 18 Roblox languages (without them the table does not accept translations); (2) the table - our entries (English +
es/pt/de/fr) before turning on auto-translation, so the Roblox machine fills only the empty languages; (3) auto-translation of the strings and the page (the description -
to the machine); the game name - the English brand in all languages (our value, the machine does not touch it).
Text capture (ATC, isAutomaticEntriesSettingEnabled) is NOT turned on: the table from the repo covers the game, and the capture would catch strings with
numbers and dragon names. Key - the file in ROBLOX_OPENCLOUD_KEY_FILE (not printed).

python3 roblox_game/tools/loc_cloud.py status          # settings, languages, auto-translation, the entry count (POSTing the table creates it if missing)
python3 roblox_game/tools/loc_cloud.py languages       # (1) the game languages, without auto-translation (otherwise the table will not accept translations)
python3 roblox_game/tools/loc_cloud.py table           # (2) the table entries (idempotent, batches of 20)
python3 roblox_game/tools/loc_cloud.py auto            # (3) auto-translation of the strings and the page, the name - the brand
python3 roblox_game/tools/loc_cloud.py page <page_description.json>   # our description in 4 languages
"""
import json
import os
import sys
import time

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import locales  # noqa: E402

U = 10769731146  # the game universe
B = "https://apis.roblox.com"
KEY = open(os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")).read().strip()
H = {"x-api-key": KEY, "Content-Type": "application/json"}
NAME = "Fly a Dragon to Steal Eggs 🐉🥚"  # the game name (set in Creator Hub), the translations - with this key
# 18 Roblox machine translation languages: en - the source
LANGS = ["es", "pt", "de", "fr", "it", "ja", "ko", "zh-hans", "zh-hant", "ru", "tr", "th", "id", "vi", "pl", "ar", "hi"]


def call(method, path, body=None, ok=(200,)):
    for attempt in range(4):
        r = requests.request(method, B + path, headers=H, data=None if body is None else json.dumps(body), timeout=60)
        if r.status_code == 429 or r.status_code >= 500:
            time.sleep(2 ** attempt * 2)
            continue
        break
    if r.status_code not in ok:
        print(f"  {method} {path.split('/v1/')[-1][:90]} -> {r.status_code} {r.text[:300]}")
    return r


def settings():
    r = call("POST", f"/legacy-localization-tables/v1/autolocalization/games/{U}/autolocalizationtable")
    return r.json() if r.status_code == 200 else {}


def status():
    s = settings()
    print("table settings:", {k: s.get(k) for k in ("isAutolocalizationEnabled", "isAutomaticEntriesSettingEnabled",
                                                        "shouldUseLocalizationTable", "sourceLanguage", "autoLocalizationTableId")})
    t = s.get("autoLocalizationTableId")
    if t:
        r = call("GET", f"/legacy-localization-tables/v1/localization-table/tables/{t}/entry-count?gameId={U}")
        print("entries in the cloud table:", r.text[:120])
    r = call("GET", f"/legacy-game-internationalization/v1/supported-languages/games/{U}/automatic-translation-status")
    langs = r.json().get("data", []) if r.status_code == 200 else []
    print("languages:", ", ".join(f"{x['languageCode']}{'+auto' if x.get('isAutomaticTranslationEnabled') else ''}" for x in langs))
    r = call("GET", f"/legacy-game-internationalization/v1/supported-languages/games/{U}/universe-display-info-automatic-translation-settings")
    print("page (auto-translation):", r.text[:400])
    return s


def table():
    s = settings()
    t = s.get("autoLocalizationTableId")
    if not t:
        sys.exit("no cloud table id")
    src, ok, report = locales.load()
    entries = locales.table_entries(src, ok)
    batch, done, failed = [], 0, 0
    def flush():
        nonlocal batch, done, failed
        if not batch:
            return
        r = call("PATCH", f"/legacy-localization-tables/v1/localization-table/tables/{t}?gameId={U}", {"entries": batch})
        if r.status_code == 200:
            j = r.json()
            failed += len(j.get("failedEntriesAndTranslations") or [])
            for f in (j.get("failedEntriesAndTranslations") or [])[:3]:
                print("  entry failure:", json.dumps(f)[:300])
            done += len(batch)
        else:
            failed += len(batch)
            print("  the batch failed, the first line:", batch[0]["identifier"]["source"][:40],
                  "| translation deletions:", sum(1 for b in batch for x in b.get("translations", []) if x.get("delete")))
        batch = []
    # sync with the repo: the standard words - delete our 4 translations (the Roblox machine fills them); entries not in the repo
    # (names, brand, VIP, R$ - not translated) - delete entirely, otherwise the machine translates them ('Old Ash' -> a literal 'old ash')
    std = locales.standard()
    cloud, cur = [], None
    while True:
        r = call("GET", f"/legacy-localization-tables/v1/localization-table/tables/{t}/entries?gameId={U}" + (f"&cursor={cur}" if cur else ""))
        d = r.json() if r.status_code == 200 else {}
        cloud += d.get("data", [])
        cur = d.get("nextPageCursor")
        if not cur:
            break
    # match by the key + text pair, not
    # by the text - after a day swap the texts swapped keys, and the old entry with the same text was not deleted
    ours = {(e["key"], e["source"]) for e in entries}
    items = []
    for x in cloud:
        if (x["identifier"].get("key") or "", x["identifier"]["source"]) not in ours:
            items.append({"identifier": {k: x["identifier"].get(k) or "" for k in ("key", "context", "source")}, "delete": True})
    pruned = len(items)
    # limit: limits promises 300, in fact 56 entries with 4 translations - 'Maximum entries exceeded', 19 - passes
    # a standard word: the Roblox machine translates only a NEW entry - it does not fill the emptied cells itself (waiting and
    # re-enabling auto-translation do not help), a recreated one - right away. If our 4 languages have no machine translation - recreate
    machine = {x["identifier"]["source"]: {y["locale"] for y in x.get("translations", [])
                                           if (y.get("translator") or {}).get("agentType") == "Automation"} for x in cloud}
    recreate = []
    for e in entries:
        ident = {"key": e["key"], "context": "", "source": e["source"]}
        if e["source"] in std:
            if not set(locales.LANGS) <= machine.get(e["source"], set()):
                recreate.append(ident)
            continue
        tr = [{"locale": lang, "translationText": text} for lang, text in e["values"].items()]
        items.append({"identifier": ident, "translations": tr})
    for it in items:
        batch.append(it)
        if len(batch) >= 20:
            flush()
    flush()
    for chunk in range(0, len(recreate), 20):
        part = recreate[chunk:chunk + 20]
        call("PATCH", f"/legacy-localization-tables/v1/localization-table/tables/{t}?gameId={U}", {"entries": [{"identifier": i, "delete": True} for i in part]})
        time.sleep(2)
        call("PATCH", f"/legacy-localization-tables/v1/localization-table/tables/{t}?gameId={U}", {"entries": [{"identifier": i, "translations": []} for i in part]})
    print(f"standard words recreated for machine translation: {len(recreate)}")
    print(f"deleted entries not from the repo: {pruned}; standard words (our translation removed): {sum(1 for e in entries if e['source'] in std)}")
    print(f"table: sent {done} entries of {len(entries)}, failures {failed}")
    # use the cloud table in the game; text capture (ATC) - off
    if not s.get("shouldUseLocalizationTable") or s.get("isAutomaticEntriesSettingEnabled"):
        call("PATCH", f"/legacy-localization-tables/v1/autolocalization/games/{U}/settings",
             {"shouldUseLocalizationTable": True, "isAutomaticEntriesSettingEnabled": False})
    return failed


def languages():
    """The game languages (without auto-translation): without them the table does not accept translations (LocalizationTargetNotSupported)."""
    call("PATCH", f"/legacy-game-internationalization/v1/supported-languages/games/{U}",
         [{"languageCodeType": "Language", "languageCode": l} for l in LANGS])


def auto():
    """Auto-translation of the strings and the page (the machine fills only the empty ones); the name - the brand in all languages."""
    # the name - the English brand in all languages (our value - the machine does not overwrite it)
    r = call("PATCH", f"/legacy-game-internationalization/v1/name-description/games/{U}",
             {"data": [{"name": NAME, "updateType": "Name", "languageCode": l} for l in LANGS]})
    if r.status_code == 200:
        j = r.json()
        print(f"name: ok {len(j.get('successOperations') or [])}, failures {len(j.get('failedOperations') or [])}",
              json.dumps(j.get("failedOperations") or [])[:300])
    bad = 0
    for l in LANGS:
        a = call("PATCH", f"/legacy-game-internationalization/v1/supported-languages/games/{U}/languages/{l}/automatic-translation-status", True)
        d = call("PATCH", f"/legacy-game-internationalization/v1/supported-languages/games/{U}/languages/{l}/universe-display-info-automatic-translation-settings", True)
        bad += (a.status_code != 200) + (d.status_code != 200)
    print("auto-translation: failures", bad)


def page(path):
    """Our page description in es/pt/de/fr: the Roblox machine breaks our words (Old Ash ->
    a literal 'old ash'). The other languages - the machine; the name - the brand (languages/auto). The machine does not overwrite our value."""
    d = json.load(open(path, encoding="utf-8"))
    data = [{"description": d[l], "updateType": "Description", "languageCode": l} for l in locales.LANGS if d.get(l)]
    for x in data:
        if len(x["description"]) > 1000:
            sys.exit(f"{x['languageCode']}: description longer than 1000 characters")
    r = call("PATCH", f"/legacy-game-internationalization/v1/name-description/games/{U}", {"data": data})
    if r.status_code == 200:
        j = r.json()
        print("description: ok", [x.get("languageCode") for x in j.get("successOperations") or []],
              "failures", json.dumps(j.get("failedOperations") or [], ensure_ascii=False)[:300])


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "table":
        table()
    elif cmd == "languages":
        languages()
    elif cmd == "auto":
        auto()
    elif cmd == "page":
        page(sys.argv[2])
    status()
