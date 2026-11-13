# in the interactive session: keep one screen (the primary, T4) and set the resolution from C:\p8\display_mode.txt (WxH) if the mode exists
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public class P8Disp {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DEVMODE { [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmDeviceName; public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra; public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput; public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate; [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string dmFormName; public short dmLogPixels; public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency, dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int ChangeDisplaySettingsEx(string dev, ref DEVMODE dm, IntPtr hwnd, int flags, IntPtr lParam);
}
'@
$o = @()
& "$env:WINDIR\System32\DisplaySwitch.exe" /internal
Start-Sleep 4
$prim = [System.Windows.Forms.Screen]::PrimaryScreen.DeviceName
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) { $o += "before: $($s.DeviceName) primary=$($s.Primary) $($s.Bounds)" }
$dm = New-Object P8Disp+DEVMODE; $dm.dmSize = [Runtime.InteropServices.Marshal]::SizeOf($dm)
$modes = @(); $i = 0
while ([P8Disp]::EnumDisplaySettings($prim, $i, [ref]$dm)) { if ($dm.dmBitsPerPel -eq 32) { $modes += "$($dm.dmPelsWidth)x$($dm.dmPelsHeight)" }; $i++ }
$o += "modes $prim : $(($modes | Select-Object -Unique) -join ' ')"
$want = "$(Get-Content C:\p8\display_mode.txt -ErrorAction SilentlyContinue | Select-Object -First 1)".Trim(); $o += "want [$want]"
if ($want -and ($modes -contains $want)) {
  $w, $h = $want -split 'x'
  [P8Disp]::EnumDisplaySettings($prim, -1, [ref]$dm) | Out-Null
  $dm.dmPelsWidth = [int]$w; $dm.dmPelsHeight = [int]$h; $dm.dmFields = 0x80000 -bor 0x100000
  $o += "change to $want -> $([P8Disp]::ChangeDisplaySettingsEx($prim, [ref]$dm, [IntPtr]::Zero, 1, [IntPtr]::Zero))"
  Start-Sleep 3 }
foreach ($s in [System.Windows.Forms.Screen]::AllScreens) { $o += "after: $($s.DeviceName) primary=$($s.Primary) $($s.Bounds)" }
$o | Set-Content C:\p8\shot.txt
