#!/bin/bash
# click.sh X Y - a click on the P8 screen (via win/click.ps1 in the interactive session; the scripts on the machine - push_win.sh)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
p8_ssh "echo $1 $2> C:\p8\click_xy.txt"
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\click.ps1' >/dev/null
sleep 2.5
p8_ssh 'powershell -NoProfile -Command "Get-Content C:\p8\cap\click.txt -Tail 1"'
