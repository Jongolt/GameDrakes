# P8: on every boot (the P8-AutoStop task, SYSTEM): the self-shutdown timer + a single screen on the T4
$m = 180
if (Test-Path C:\p8\autostop_minutes.txt) { $m = [int](Get-Content C:\p8\autostop_minutes.txt | Select-Object -First 1) }
shutdown.exe /a 2>$null
Add-Content C:\p8\boots.log ("{0} boot, autostop in {1} min" -f (Get-Date -Format o), $m)
shutdown.exe /s /t ($m*60) /c "P8 auto-stop after $m min (cancel: shutdown /a)"
# turn off the emulated Microsoft Basic Display if the NVIDIA T4 works (otherwise two screens, the second 800x600)
$nv = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -like 'NVIDIA*' -and $_.Status -eq 'OK' }
if ($nv) {
  Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -eq 'Microsoft Basic Display Adapter' -and $_.Status -eq 'OK' } |
    ForEach-Object { pnputil.exe /disable-device "$($_.InstanceId)" | Out-Null; Add-Content C:\p8\boots.log "  disabled basic display $($_.InstanceId)" }
} else { Add-Content C:\p8\boots.log "  NVIDIA not OK, basic display left on" }
