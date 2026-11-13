# P8 setup2 (over SSH as Administrator). The secrets come as KEY=VALUE lines via stdin, they are not written to files and not printed.
# Does: Studio, TightVNC (a service, only 127.0.0.1:5900, a password), Administrator autologin to the console, no screensaver,
# waits for the NVIDIA driver, prints the state. The reboot is done by a separate command.
$ErrorActionPreference = 'Continue'
function T($s) { "[$(Get-Date -Format HH:mm:ss)] $s" }
$s = @{}
while ($null -ne ($l = [Console]::In.ReadLine())) { if ($l -match '^([A-Z_]+)=(.*)$') { $s[$matches[1]] = $matches[2] } }
foreach ($k in 'WINDOWS_PASSWORD','VNC_PASSWORD','VNC_CONTROL_PASSWORD') { if (-not $s[$k]) { T "MISSING $k"; exit 2 } }
T "secrets received: $($s.Keys -join ',')"

# 1) Roblox Studio (installed machine-wide as Administrator, checked on P6)
if (-not (Get-ChildItem 'C:\Program Files (x86)\Roblox\Versions' -Recurse -Filter RobloxStudioBeta.exe -ErrorAction SilentlyContinue)) {
  $p = Start-Process C:\p8\RobloxStudioInstaller.exe -PassThru
  for ($i = 0; $i -lt 72; $i++) { Start-Sleep 5; if ($p.HasExited) { break } }
  T "studio installer exited=$($p.HasExited) code=$(if ($p.HasExited) { $p.ExitCode })"
  Start-Sleep 5
  Get-Process | Where-Object { $_.Name -like 'Roblox*' } | Stop-Process -Force -ErrorAction SilentlyContinue }
Get-ChildItem 'C:\Program Files (x86)\Roblox\Versions' -Recurse -Depth 1 -Include RobloxStudioBeta.exe,StudioMCP.exe -ErrorAction SilentlyContinue | ForEach-Object { T "exe: $($_.FullName)" }
foreach ($k in 'roblox-studio','roblox-studio-auth') { T "HKCR $k = $((Get-ItemProperty "Registry::HKEY_CLASSES_ROOT\$k\shell\open\command" -ErrorAction SilentlyContinue).'(default)')" }

# 2) TightVNC: a service on the console, a password, listens only on loopback (outside access only via the noVNC proxy)
if (-not (Get-Service tvnserver -ErrorAction SilentlyContinue)) {
  $a = @('/i','C:\p8\tightvnc.msi','/quiet','/norestart','ADDLOCAL=Server','SERVER_REGISTER_AS_SERVICE=1','SERVER_ADD_FIREWALL_EXCEPTION=0',
         'SERVER_ALLOW_SAS=1','SET_USEVNCAUTHENTICATION=1','VALUE_OF_USEVNCAUTHENTICATION=1','SET_PASSWORD=1',"VALUE_OF_PASSWORD=$($s.VNC_PASSWORD)",
         'SET_USECONTROLAUTHENTICATION=1','VALUE_OF_USECONTROLAUTHENTICATION=1','SET_CONTROLPASSWORD=1',"VALUE_OF_CONTROLPASSWORD=$($s.VNC_CONTROL_PASSWORD)",
         'SET_ACCEPTHTTPCONNECTIONS=1','VALUE_OF_ACCEPTHTTPCONNECTIONS=0','SET_ALLOWLOOPBACK=1','VALUE_OF_ALLOWLOOPBACK=1',
         'SET_LOOPBACKONLY=1','VALUE_OF_LOOPBACKONLY=1','SET_REMOVEWALLPAPER=1','VALUE_OF_REMOVEWALLPAPER=0')
  $m = Start-Process msiexec.exe -ArgumentList $a -Wait -PassThru
  T "tightvnc msi exit=$($m.ExitCode)" }
$r = Get-ItemProperty 'HKLM:\SOFTWARE\TightVNC\Server' -ErrorAction SilentlyContinue
if ($r) { foreach ($n in 'UseVncAuthentication','AllowLoopback','LoopbackOnly','AcceptHttpConnections','RfbPort','PollingInterval','RemoveWallpaper','DisconnectAction') { T "tvn $n = $($r.$n)" }
          T "tvn Password set: $([bool]$r.Password)" }
T "tvnserver: $((Get-Service tvnserver -ErrorAction SilentlyContinue).Status)"
Get-NetTCPConnection -LocalPort 5900 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { T "listen 5900 on $($_.LocalAddress)" }

# 3) Administrator autologin to the console session
& C:\p8\Autologon64.exe /accepteula Administrator $env:COMPUTERNAME $s.WINDOWS_PASSWORD | Out-Null
$w = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
T "winlogon AutoAdminLogon=$($w.AutoAdminLogon) DefaultUserName=$($w.DefaultUserName) DefaultDomainName=$($w.DefaultDomainName) plaintextDefaultPassword=$([bool]$w.DefaultPassword)"

# 4) no screensaver and no screen lock
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaveActive -Value '0'
Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name ScreenSaverIsSecure -Value '0'
$pol = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
Set-ItemProperty $pol -Name InactivityTimeoutSecs -Value 0 -Type DWord

# 5) the NVIDIA driver: wait for the installer (started in the background from user-data)
for ($i = 0; $i -lt 60; $i++) { if (-not (Get-Process -Name nvidia_grid,setup -ErrorAction SilentlyContinue)) { break }; Start-Sleep 10 }
T "nvidia installer running: $([bool](Get-Process -Name nvidia_grid,setup -ErrorAction SilentlyContinue))"
& 'C:\Windows\System32\nvidia-smi.exe' --query-gpu=name,driver_version --format=csv,noheader 2>&1 | ForEach-Object { T "nvidia-smi: $_" }
Get-CimInstance Win32_VideoController | ForEach-Object { T "video: $($_.Name) | $($_.Status) | $($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)" }

# 6) the rest of the state
T "proxy 6080 listen: $((Get-NetTCPConnection -LocalPort 6080 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count), 6081: $((Get-NetTCPConnection -LocalPort 6081 -State Listen -ErrorAction SilentlyContinue | Measure-Object).Count)"
T "cony url (not in autostart): $(Test-Path 'C:\p8\Cony-Studio.url')"
T "edge policy keys: $(((Get-Item 'HKLM:\SOFTWARE\Policies\Microsoft\Edge').Property) -join ',')"
T "disk C free GB: $([math]::Round((Get-PSDrive C).Free/1GB,1))"
T "setup2 done"
