# run rec.ps1 in the Administrator interactive session (does not wait for the recording to end)
param([string]$Name = "trailer_raw", [int]$Seconds = 75)
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\p8\rec.ps1 -Name $Name -Seconds $Seconds"
$p = New-ScheduledTaskPrincipal -UserId 'Administrator' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'P8-Rec' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName 'P8-Rec'
"started $Name $Seconds"
