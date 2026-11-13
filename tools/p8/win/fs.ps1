# interactive session: Studio to the foreground, F11 (full screen), a screen frame to C:\p8\cap\fs.png
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.Windows.Forms
$ok = [Microsoft.VisualBasic.Interaction]::AppActivate('Roblox Studio')
Start-Sleep -Milliseconds 800
[System.Windows.Forms.SendKeys]::SendWait('{F11}')
Start-Sleep -Seconds 3
& C:\p8\tools\ffmpeg.exe -y -loglevel error -f gdigrab -framerate 1 -i desktop -frames:v 1 C:\p8\cap\fs.png
"fs activate=$ok done $(Get-Date -Format o)" | Set-Content C:\p8\cap\fs.txt
