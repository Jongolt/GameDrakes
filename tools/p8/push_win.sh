#!/bin/bash
# push_win.sh - upload to P8 (C:\p8) the working scripts of the interactive session from win/: clicks, keys, window, frame, screen recording.
# The machine setup scripts (setup2.ps1, userdata.tpl.ps1, novnc_proxy.py ...) are not included - they are installed when the machine is created.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
cd "$P8_TOOLS/win"
p8_scp_to run_interactive.ps1 fs.ps1 click.ps1 click2.ps1 hold.ps1 key.ps1 keys.ps1 winsize.ps1 deskshot.ps1 rec.ps1 rec_run.ps1 C:/p8/ >/dev/null && echo "ps1 ok"
