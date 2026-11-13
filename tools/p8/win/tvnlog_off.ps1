Set-ItemProperty HKLM:\SOFTWARE\TightVNC\Server -Name LogLevel -Value 0 -Type DWord
Restart-Service tvnserver -Force
Start-Sleep 3
$f = 'C:\Windows\System32\config\systemprofile\AppData\Roaming\TightVNC\tvnserver.log'
"tvnserver: $((Get-Service tvnserver).Status); LogLevel=$((Get-ItemProperty HKLM:\SOFTWARE\TightVNC\Server).LogLevel); log MB: $([math]::Round((Get-Item $f).Length/1MB,1))"
Remove-Item C:\p8\shot.png,C:\p8\edge.png,C:\p8\policy.txt -ErrorAction SilentlyContinue
