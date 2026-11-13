#!/bin/bash
# keys.sh "down space;wait 2500;down w;wait 4000;up space;up w" - real keys in Studio on P8 (win/keys.ps1)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
t=$(mktemp); echo "$1" | tr ';' '\n' > "$t"
p8_scp_to "$t" C:/p8/keys.txt >/dev/null; rm -f "$t"
p8_ssh 'powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\run_interactive.ps1 -File C:\p8\keys.ps1' >/dev/null
p8_ssh 'powershell -NoProfile -Command "Get-Content C:\p8\cap\click.txt -Tail 1"'
