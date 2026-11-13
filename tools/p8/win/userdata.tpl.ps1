<powershell>
# P8 first boot (SYSTEM): self-shutdown, sshd, Edge policy, game shortcuts, downloads, WebView2, NVIDIA (background), Python+aiohttp, noVNC, proxy.
# Passwords are not put here: TightVNC with a password and the autologin are set over SSH (win/setup2.ps1).
$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force C:\p8 | Out-Null
Start-Transcript -Path C:\p8\userdata.log -Append
function L($s) { $t = "P8 $(Get-Date -Format HH:mm:ss) $s"; Write-Output $t
  try { $sp = New-Object System.IO.Ports.SerialPort 'COM1',115200; $sp.Open(); $sp.WriteLine($t); $sp.Close() } catch {} }
L "start"

# 1) self-shutdown on every boot after N minutes (C:\p8\autostop_minutes.txt)
Set-Content C:\p8\autostop_minutes.txt '150'
@'
$m = 180
if (Test-Path C:\p8\autostop_minutes.txt) { $m = [int](Get-Content C:\p8\autostop_minutes.txt | Select-Object -First 1) }
shutdown.exe /a 2>$null
Add-Content C:\p8\boots.log ("{0} boot, autostop in {1} min" -f (Get-Date -Format o), $m)
shutdown.exe /s /t ($m*60) /c "P8 auto-stop after $m min (cancel: shutdown /a)"
'@ | Set-Content C:\p8\autostop.ps1
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\p8\autostop.ps1'
Register-ScheduledTask -TaskName 'P8-AutoStop' -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\p8\autostop.ps1
L "autostop set"

# 2) sshd + firewall (the EC2 network = Public, the built-in rule is Private only)
New-Item -ItemType Directory -Force C:\ProgramData\ssh | Out-Null
Set-Content -Path C:\ProgramData\ssh\administrators_authorized_keys -Value '__PUBKEY__' -Encoding ascii
icacls.exe C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r /grant 'Administrators:F' /grant 'SYSTEM:F' | Out-Null
Set-Service sshd -StartupType Automatic
Start-Service sshd
New-NetFirewallRule -Name 'p8-sshd' -DisplayName 'P8 sshd 22' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22 -Profile Any | Out-Null
New-NetFirewallRule -Name 'p8-novnc' -DisplayName 'P8 noVNC 6080-6081' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 6080,6081 -Profile Any | Out-Null
L "sshd: $((Get-Service sshd).Status)"

# 3) the screen does not go dark, Server Manager does not open on login
powercfg /change monitor-timeout-ac 0; powercfg /change standby-timeout-ac 0
New-Item -Force 'HKLM:\SOFTWARE\Microsoft\ServerManager' | Out-Null
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\ServerManager' -Name DoNotOpenServerManagerAtLogon -Value 1 -Type DWord
Get-ScheduledTask -TaskName ServerManager -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null

# 4) Edge: no first-run wizard, the Roblox protocols open without asking
$e = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
New-Item -Force $e | Out-Null
foreach ($kv in @(@('HideFirstRunExperience',1),@('ExternalProtocolDialogShowAlwaysOpenCheckbox',1),@('DefaultBrowserSettingEnabled',0),
                  @('BrowserSignin',0),@('SyncDisabled',1),@('ShowRecommendationsEnabled',0),@('PromotionalTabsEnabled',0),
                  @('AutoImportAtFirstRun',4),@('PasswordManagerEnabled',0),@('StartupBoostEnabled',0))) {
  Set-ItemProperty $e -Name $kv[0] -Value $kv[1] -Type DWord }
$proto = '[{"protocol":"roblox-studio-auth","allowed_origins":["roblox.com","*"]},{"protocol":"roblox-studio","allowed_origins":["roblox.com","*"]},{"protocol":"roblox-player","allowed_origins":["roblox.com","*"]},{"protocol":"roblox","allowed_origins":["roblox.com","*"]}]'
Set-ItemProperty $e -Name AutoLaunchProtocolsFromOrigins -Value $proto -Type String
L "edge policies set"

# 5) the Cony game: Studio autostart on console login + a desktop shortcut
$url = "[InternetShortcut]`r`nURL=roblox-studio:1+launchmode:edit+task:EditPlace+placeId:85991537614055+universeId:10769731146`r`n"
# the shortcut is NOT in autostart - Studio, opening the cloud place on login, saves its copy as a new version on every
# machine start; open the cloud place by hand with the P8-OpenCony task (tasks.ps1)
Set-Content -Path 'C:\p8\Cony-Studio.url' -Value $url -Encoding ascii
Set-Content -Path 'C:\Users\Public\Desktop\Cony (Roblox Studio).url' -Value $url -Encoding ascii

# 6) downloads
$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'
$tvnc = $null
try { $pg = (Invoke-WebRequest -UseBasicParsing -Uri 'https://www.tightvnc.com/download.php').Content
      $m = [regex]::Match($pg, '(https?://[^"''\s<>]*|/[^"''\s<>]*)tightvnc-[0-9.]+-gpl-setup-64bit\.msi')
      if ($m.Success) { $tvnc = $m.Value; if ($tvnc.StartsWith('/')) { $tvnc = 'https://www.tightvnc.com' + $tvnc } } } catch { L "tightvnc page failed" }
if (-not $tvnc) { $tvnc = 'https://www.tightvnc.com/download/2.8.85/tightvnc-2.8.85-gpl-setup-64bit.msi' }
L "tightvnc url: $tvnc"
$dl = [ordered]@{
  'C:\p8\nvidia_grid.exe' = 'https://ec2-windows-nvidia-drivers.s3.amazonaws.com/latest/596.86__grid_win10_win11_server2022_server2025_dch_64bit_international_aws_swl.exe';
  'C:\p8\MicrosoftEdgeWebview2Setup.exe' = 'https://go.microsoft.com/fwlink/p/?LinkId=2124703';
  'C:\p8\RobloxStudioInstaller.exe' = 'https://setup.rbxcdn.com/RobloxStudioInstaller.exe';
  'C:\p8\Autologon64.exe' = 'https://live.sysinternals.com/Autologon64.exe';
  'C:\p8\tightvnc.msi' = $tvnc;
  'C:\p8\python.exe' = 'https://www.python.org/ftp/python/3.12.10/python-3.12.10-amd64.exe';
  'C:\p8\novnc.zip' = 'https://github.com/novnc/noVNC/archive/refs/tags/v1.6.0.zip' }
foreach ($k in $dl.Keys) { try { Invoke-WebRequest -UseBasicParsing -Uri $dl[$k] -OutFile $k } catch { L "FAILED $k : $($_.Exception.Message)" }
  L "file $k $((Get-Item $k -ErrorAction SilentlyContinue).Length)" }
if (-not (Test-Path C:\p8\novnc.zip)) { try { Invoke-WebRequest -UseBasicParsing -Uri 'https://github.com/novnc/noVNC/archive/refs/tags/v1.5.0.zip' -OutFile C:\p8\novnc.zip } catch {}; L "novnc 1.5 fallback $((Get-Item C:\p8\novnc.zip -ErrorAction SilentlyContinue).Length)" }

# 7) NVIDIA in the background, WebView2, Python + aiohttp + cryptography
Start-Process C:\p8\nvidia_grid.exe -ArgumentList '-s','-noreboot','-clean'
L "nvidia started"
Start-Process C:\p8\MicrosoftEdgeWebview2Setup.exe -ArgumentList '/silent','/install' -Wait
L "webview2 done"
Start-Process C:\p8\python.exe -ArgumentList '/quiet','InstallAllUsers=1','PrependPath=1','Include_test=0','Include_launcher=0' -Wait
$py = 'C:\Program Files\Python312\python.exe'
L "python: $(Test-Path $py)"
& $py -m pip install --disable-pip-version-check -q aiohttp cryptography 2>&1 | Select-Object -Last 3 | ForEach-Object { L "pip: $_" }

# 8) noVNC + proxy (a task at boot, restart on a crash)
Expand-Archive -Force C:\p8\novnc.zip C:\p8\novnc_x
$d = Get-ChildItem C:\p8\novnc_x -Directory | Select-Object -First 1
if (Test-Path C:\p8\novnc) { Remove-Item -Recurse -Force C:\p8\novnc }
Move-Item $d.FullName C:\p8\novnc
L "novnc: $(Test-Path C:\p8\novnc\vnc.html)"
[IO.File]::WriteAllBytes('C:\p8\novnc_proxy.py', [Convert]::FromBase64String('__PROXY_B64__'))
$act = New-ScheduledTaskAction -Execute $py -Argument 'C:\p8\novnc_proxy.py' -WorkingDirectory 'C:\p8'
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName 'P8-noVNC' -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'P8-noVNC'
Start-Sleep 8
L "proxy listen 6080: $((Get-NetTCPConnection -LocalPort 6080 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count)"
L "end"
Stop-Transcript
</powershell>
