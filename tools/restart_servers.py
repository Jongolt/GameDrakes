#!/usr/bin/env python3
"""Restarting the live game servers onto the published version (Open Cloud restartServers).

Allowed after every release (publish.py) without a separate question. It kicks all players - say 'restarted, rejoin' in the report.
First prints the live version (Assets API), then restarts; the key does not get into the output. Log: runs/restart_servers.log.

python3 tools/restart_servers.py
"""
import datetime
import os
import re

import requests

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = os.path.dirname(HERE)
UNIVERSE = 10769731146
KEY = open(os.environ.get("ROBLOX_OPENCLOUD_KEY_FILE", ".roblox_opencloud")).read().strip()
LOG = os.path.join(os.path.dirname(GAME), "runs", "restart_servers.log")


def main():
    pid = re.search(r"PLACE_ID\s*=\s*(\d+)", open(os.path.join(GAME, "publish.py")).read()).group(1)
    v = requests.get(f"https://apis.roblox.com/assets/v1/assets/{pid}/versions", params={"maxPageSize": 1},
                     headers={"x-api-key": KEY}, timeout=30).json()["assetVersions"][0]
    ver = v["path"].split("/")[-1]
    r = requests.post(f"https://apis.roblox.com/cloud/v2/universes/{UNIVERSE}:restartServers",
                      headers={"x-api-key": KEY}, json={}, timeout=30)
    line = f"{datetime.datetime.now(datetime.timezone.utc):%Y-%m-%d %H:%M:%S} UTC | live version {ver} | restartServers HTTP {r.status_code}"
    print(line)
    if r.status_code != 200:
        print(r.text.replace(KEY, "<key>")[:300])
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(line + "\n")


if __name__ == "__main__":
    main()
