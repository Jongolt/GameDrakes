# press a key in the Studio window (P8): the nircmd key name from C:\p8\key.txt (esc, enter...)
Add-Type -AssemblyName Microsoft.VisualBasic
$nir = 'C:\p8\tools\nircmd\nircmd.exe'
$k = (Get-Content C:\p8\key.txt -Raw).Trim()
[Microsoft.VisualBasic.Interaction]::AppActivate('Roblox Studio') | Out-Null
Start-Sleep -Milliseconds 300
& $nir sendkeypress $k
"key $k $(Get-Date -Format o)" | Add-Content C:\p8\cap\click.txt
