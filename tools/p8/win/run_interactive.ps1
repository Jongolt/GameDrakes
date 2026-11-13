# run any ps1 in the Administrator interactive session: run_interactive.ps1 -File C:\p8\fs.ps1 [-Args "..."]
param([string]$File, [string]$Args = "")
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File $File $Args"
$p = New-ScheduledTaskPrincipal -UserId 'Administrator' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'P8-Interactive' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName 'P8-Interactive'
"started $File"
