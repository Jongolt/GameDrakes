#!/bin/bash
# MCP stdio bridge: Claude Code <-> ssh <-> StudioMCP.exe on the P8 Windows machine.
# Connect (once):  claude mcp add roblox-studio -- <repo>/tools/p8/mcp_bridge.sh
# Does not start the machine itself (money): up.sh first. Only the MCP stream goes to stdout, everything else to stderr.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
IP=$(p8_ip)
if [ -z "$IP" ] || [ "$IP" = None ]; then echo "p8: the machine is not running ($(p8_state)), up.sh first" >&2; exit 1; fi
exec ssh -T "${P8_SSH_OPTS[@]}" "$P8_USER@$IP" 'C:\p8\mcp_start.cmd'
