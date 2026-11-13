#!/bin/bash
# deskshot.sh <where.png> - a frame of the top left corner of the P8 screen 834x630 (the Studio window = a phone) by a real screen capture (ffmpeg gdigrab)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
mkdir -p "$(dirname "$1")"
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\deskshot.ps1' >/dev/null
sleep 2
p8_scp_from C:/p8/cap/desk.png "$1" && echo "desk ok $1"
