# run shot.ps1 in the Administrator interactive session and wait for the result
Remove-Item C:\p8\shot.png,C:\p8\shot.txt -ErrorAction SilentlyContinue
$a = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\p8\shot.ps1'
$p = New-ScheduledTaskPrincipal -UserId 'Administrator' -LogonType Interactive -RunLevel Highest
Register-ScheduledTask -TaskName 'P8-Shot' -Action $a -Principal $p -Force | Out-Null
Start-ScheduledTask -TaskName 'P8-Shot'
for ($i = 0; $i -lt 30; $i++) { Start-Sleep 1; if (Test-Path C:\p8\shot.txt) { break } }
Get-Content C:\p8\shot.txt -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName 'P8-Shot' -Confirm:$false
