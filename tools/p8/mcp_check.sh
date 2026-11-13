#!/bin/bash
# MCP check through the bridge: initialize, list_roblox_studios, get_studio_state. Does NOT start or stop the machine.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
P=$P8_STATE
( printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"p8-check","version":"0.1"}}}'; sleep 5
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_roblox_studios","arguments":{}}}'; sleep 6
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"get_studio_state","arguments":{}}}'; sleep 6 ) \
  | timeout 40 "$P8_TOOLS/mcp_bridge.sh" > "$P/mcp_check.out" 2> "$P/mcp_check.err"
echo "exit=$? out=$(wc -c < "$P/mcp_check.out")B err=$(wc -c < "$P/mcp_check.err")B"
cat "$P/mcp_check.out"
