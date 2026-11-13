# P8, interactive session: screen recording to C:\p8\cap\<name>.mp4: ddagrab (GPU, 30 fps, no cursor), gdigrab as a fallback
param([string]$Name = "trailer_raw", [int]$Seconds = 75, [string]$Mode = "dda")
New-Item -ItemType Directory -Force C:\p8\cap | Out-Null
& C:\p8\tools\nircmd\nircmd.exe setcursor 2520 1430
$out = "C:\p8\cap\$Name.mp4"
"rec start $(Get-Date -Format o) mode=$Mode" | Set-Content C:\p8\cap\rec.txt
$code = 1
if ($Mode -eq "dda") {
  & C:\p8\tools\ffmpeg.exe -y -loglevel error -f lavfi -i "ddagrab=output_idx=0:framerate=30:draw_mouse=0" -t $Seconds -vf "hwdownload,format=bgra" -c:v libx264 -preset ultrafast -crf 19 -pix_fmt yuv420p $out
  $code = $LASTEXITCODE
}
if ($code -ne 0 -or -not (Test-Path $out)) {
  "dda failed ($code), gdigrab" | Add-Content C:\p8\cap\rec.txt
  & C:\p8\tools\ffmpeg.exe -y -loglevel error -f gdigrab -draw_mouse 0 -framerate 30 -i desktop -t $Seconds -c:v libx264 -preset ultrafast -crf 19 -pix_fmt yuv420p $out
  $code = $LASTEXITCODE
}
"rec done $(Get-Date -Format o) exit=$code size=$((Get-Item $out -ErrorAction SilentlyContinue).Length)" | Add-Content C:\p8\cap\rec.txt
