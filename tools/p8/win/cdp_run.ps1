$pw = [Console]::In.ReadLine()
Remove-Item C:\p8\edge.png -ErrorAction SilentlyContinue
$pw | & 'C:\Program Files\Python312\python.exe' C:\p8\cdp_shot.py 2>&1 | Select-String -NotMatch 'password='
$me = (Get-Process -Id $PID).SessionId
Start-Sleep 2
Get-Process msedge -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -eq $me } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep 2
Remove-Item -Recurse -Force C:\p8\edgetest -ErrorAction SilentlyContinue
"ssh session $me; edgetest removed: $(-not (Test-Path C:\p8\edgetest))"
