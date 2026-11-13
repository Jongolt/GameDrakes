# holding the mouse for 3.6 s (Reset by holding) - otherwise like click.ps1; a mouse click on the P8 screen (interactive session): the coordinates "X Y" from C:\p8\click_xy.txt; the cursor to the corner afterwards
Add-Type -AssemblyName Microsoft.VisualBasic
$nir = 'C:\p8\tools\nircmd\nircmd.exe'
$xy = (Get-Content C:\p8\click_xy.txt -Raw).Trim() -split '\s+'
$X = [int]$xy[0]; $Y = [int]$xy[1]
$ok = [Microsoft.VisualBasic.Interaction]::AppActivate('Roblox Studio')
Start-Sleep -Milliseconds 400
& $nir setcursor $X $Y
Start-Sleep -Milliseconds 300
& $nir sendmouse left down
Start-Sleep -Milliseconds 3600
& $nir sendmouse left up
Start-Sleep -Milliseconds 600
& $nir setcursor 1275 1020
"hold $X $Y activate=$ok $(Get-Date -Format o)" | Add-Content C:\p8\cap\click.txt
