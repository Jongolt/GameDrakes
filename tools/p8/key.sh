#!/bin/bash
# key.sh esc - a single key press in the Studio window on P8 (the nircmd key name: esc, enter, f11...)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
p8_ssh "echo $1> C:\p8\key.txt"
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\key.ps1' >/dev/null
sleep 2
