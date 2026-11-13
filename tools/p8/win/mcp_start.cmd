@echo off
rem P8: Roblox Studio MCP proxy over stdio. Official mcp.bat if Studio created it, else newest StudioMCP.exe.
if exist "%LOCALAPPDATA%\Roblox\mcp.bat" (
  call "%LOCALAPPDATA%\Roblox\mcp.bat" %*
  exit /b
)
for %%r in ("C:\Program Files\Roblox\Versions" "C:\Program Files (x86)\Roblox\Versions") do (
  for /f "delims=" %%d in ('dir /b /ad /o-d "%%~r\version-*" 2^>nul') do (
    if exist "%%~r\%%d\StudioMCP.exe" (
      "%%~r\%%d\StudioMCP.exe" %*
      exit /b
    )
  )
)
echo p8: StudioMCP.exe not found 1>&2
exit /b 1
