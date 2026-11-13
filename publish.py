#!/usr/bin/env python3
"""Upload the built place (build/place.rbxlx) to the game through Open Cloud Place Publishing.
The key comes from the file in ROBLOX_OPENCLOUD_KEY_FILE and never reaches the output. 409 "Server is busy" = the place is open in Studio
(a Team Create session lives up to ~20 min after closing) - retry once a minute for up to 15 minutes.

python3 publish.py                 # to the live game (universe 10769731146)
python3 publish.py --saved         # save a version without publishing
"""
import os
import sys
import time

import requests

UNIVERSE_ID = 10769731146  # the LIVE game
PLACE_ID = 85991537614055
KEY_FILE = os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")
PLACE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "place.rbxlx")


# Mandatory content of the place file (e.g. the 3D hatchling of the loading screen) is checked BEFORE the upload: missing - do not publish.
REQUIRED = [(b'<string name="Name">LoadingDragon</string>', "the 3D hatchling of the loading screen (ReplicatedFirst.LoadingDragon, build.py baked_models)")]


def main():
    vt = "Saved" if "--saved" in sys.argv else "Published"
    body = open(PLACE, "rb").read()
    missing = [what for mark, what in REQUIRED if mark not in body]
    if missing:
        sys.exit("NOT PUBLISHING - build/place.rbxlx lacks: " + "; ".join(missing))
    key = open(KEY_FILE).read().strip()
    deadline = time.time() + 15 * 60
    while True:
        r = requests.post(f"https://apis.roblox.com/universes/v1/{UNIVERSE_ID}/places/{PLACE_ID}/versions",
                          params={"versionType": vt}, data=body,
                          headers={"x-api-key": key, "Content-Type": "application/xml"}, timeout=120)
        text = r.text.replace(key, "<key>")[:300]
        print(time.strftime("%H:%M:%S", time.gmtime()), "UTC | HTTP", r.status_code, "|", text, flush=True)
        if r.status_code != 409 or time.time() > deadline:
            break
        time.sleep(60)
    del key
    sys.exit(0 if r.status_code == 200 else 1)


if __name__ == "__main__":
    main()
