# real keys into the Studio window (P8): the script from C:\p8\keys.txt - lines "down space" / "up w" / "wait 2500"; first a click on the viewport (game focus)
Add-Type -AssemblyName Microsoft.VisualBasic
$nir = 'C:\p8\tools\nircmd\nircmd.exe'
$ok = [Microsoft.VisualBasic.Interaction]::AppActivate('Roblox Studio')
Start-Sleep -Milliseconds 400
& $nir setcursor 600 450
& $nir sendmouse left down
Start-Sleep -Milliseconds 80
& $nir sendmouse left up
Start-Sleep -Milliseconds 300
foreach ($line in Get-Content C:\p8\keys.txt) {
  $p = $line.Trim() -split '\s+'
  if ($p[0] -eq 'wait') { Start-Sleep -Milliseconds ([int]$p[1]) }
  elseif ($p[0] -eq 'down') { & $nir sendkey $p[1] down }
  elseif ($p[0] -eq 'up') { & $nir sendkey $p[1] up }
}
& $nir setcursor 1275 1020
"keys done activate=$ok $(Get-Date -Format o)" | Add-Content C:\p8\cap\click.txt
