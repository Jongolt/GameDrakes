#!/bin/bash
# open_local.sh - upload build/place.rbxlx to P8, reopen Studio with the local file (the P8-OpenLocal task), window 834x630, F11.
# Without Team Create and without publishing. Probes - separately (tests/p8/*.py). Before this: python3 build.py
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
REPO=$(cd "$P8_TOOLS/../.." && pwd)
bash "$P8_TOOLS/push_win.sh"
p8_scp_to "$REPO/build/place.rbxlx" C:/p8/place.rbxlx >/dev/null && echo "place ok"
p8_ssh 'taskkill /im RobloxStudioBeta.exe /f' 2>/dev/null
sleep 3
p8_ssh "schtasks /run /tn P8-OpenLocal"
sleep 75
bash "$P8_TOOLS/winsize.sh" 834 630 >/dev/null  # P8-OpenLocal does not set the 834x630 window itself
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\fs.ps1'
sleep 10
echo "open done $(date -u +%H:%M:%S)"
