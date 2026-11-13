# a console session screenshot by Windows means (GDI CopyFromScreen) + the monitor list -> C:\p8\shot.png, C:\p8\shot.txt
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
$o = @()
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) { $o += "screen $($s.DeviceName) primary=$($s.Primary) bounds=$($s.Bounds)" }
$b = [System.Windows.Forms.SystemInformation]::VirtualScreen
$o += "virtual $b"
try { $bmp = New-Object System.Drawing.Bitmap $b.Width,$b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen($b.Left,$b.Top,0,0,$bmp.Size); $bmp.Save('C:\p8\shot.png'); $o += 'saved' } catch { $o += "ERR $_" }
$o += "session $((Get-Process -Id $PID).SessionId) $(Get-Date -Format o)"
$o | Set-Content C:\p8\shot.txt
