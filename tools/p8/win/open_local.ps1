# open the local build file C:\p8\place.rbxlx in Studio (without Team Create - without the 20-minute pause after closing)
$exe = Get-ChildItem 'C:\Program Files\Roblox\Versions' -Recurse -Filter RobloxStudioBeta.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
Start-Process -FilePath $exe -ArgumentList '"C:\p8\place.rbxlx"'
