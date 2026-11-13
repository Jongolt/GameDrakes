# P8: Task Scheduler tasks for opening Studio in the Administrator interactive session.
# Run over SSH: powershell -NoProfile -ExecutionPolicy Bypass -File C:\p8\tasks.ps1
# P8-OpenLocal - Studio with the local file C:\p8\place.rbxlx (open_local.ps1; without Team Create)
# P8-OpenCony  - Studio with the cloud place via the shortcut C:\p8\Cony-Studio.url (only by hand, not in autostart -
# Studio saves a copy of the cloud place as a new version on every machine start)
# The other tasks are created by the scripts themselves: P8-noVNC and P8-AutoStop - userdata.tpl.ps1, P8-Interactive - run_interactive.ps1,
# P8-Rec - rec_run.ps1.
$p = New-ScheduledTaskPrincipal -UserId 'Administrator' -LogonType Interactive
$a = New-ScheduledTaskAction -Execute 'powershell' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\p8\open_local.ps1'
Register-ScheduledTask -TaskName 'P8-OpenLocal' -Action $a -Principal $p -Force | Out-Null
$a = New-ScheduledTaskAction -Execute 'cmd' -Argument '/c start "" "C:\p8\Cony-Studio.url"'
Register-ScheduledTask -TaskName 'P8-OpenCony' -Action $a -Principal $p -Force | Out-Null
foreach ($t in 'P8-OpenLocal', 'P8-OpenCony') { "$t $((Get-ScheduledTask -TaskName $t -ErrorAction SilentlyContinue).State)" }
