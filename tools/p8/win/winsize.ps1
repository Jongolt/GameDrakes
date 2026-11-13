# a Studio window of the given size (phone screen emulation): the size "W H" from C:\p8\winsize.txt; a screen frame to C:\p8\cap\winsize.png
Add-Type -AssemblyName Microsoft.VisualBasic
$nir = 'C:\p8\tools\nircmd\nircmd.exe'
$wh = (Get-Content C:\p8\winsize.txt -Raw).Trim() -split '\s+'
$ok = [Microsoft.VisualBasic.Interaction]::AppActivate('Roblox Studio')
Start-Sleep -Milliseconds 500
& $nir win normal ititle "Roblox Studio"
Start-Sleep -Milliseconds 800
& $nir win setsize ititle "Roblox Studio" 0 0 $wh[0] $wh[1]
Start-Sleep -Seconds 2
& $nir setcursor 2550 1430
& C:\p8\tools\ffmpeg.exe -y -loglevel error -f gdigrab -framerate 1 -i desktop -frames:v 1 C:\p8\cap\winsize.png
"winsize $($wh[0]) $($wh[1]) activate=$ok $(Get-Date -Format o)" | Add-Content C:\p8\cap\click.txt
