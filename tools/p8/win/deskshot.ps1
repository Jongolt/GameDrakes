# a frame of the Studio window straight from the P8 screen (the AlwaysOnTop labels are visible too, which are missing in the MCP screen_capture)
& C:\p8\tools\ffmpeg.exe -y -loglevel error -f gdigrab -framerate 1 -offset_x 0 -offset_y 0 -video_size 834x630 -i desktop -frames:v 1 C:\p8\cap\desk.png
"desk $(Get-Date -Format o)" | Add-Content C:\p8\cap\click.txt
