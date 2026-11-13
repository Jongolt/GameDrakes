#!/bin/bash
# winsize.sh W H - the Studio window on P8 of the given size: 834 630 -> viewport 812x375 (a phone in pt), 1222 930 -> 1200x675
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
p8_ssh "echo $1 $2> C:\p8\winsize.txt"
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\winsize.ps1' >/dev/null
sleep 2.5
p8_ssh 'powershell -NoProfile -Command "Get-Content C:\p8\cap\click.txt -Tail 1"'
