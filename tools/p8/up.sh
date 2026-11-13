#!/bin/bash
# Start the stopped P8 Windows machine (Roblox Studio + noVNC), wait for the page, print the link for the browser.
# up.sh - start; self-shutdown N minutes after boot (C:\p8\autostop_minutes.txt; the number is remembered on the machine)
# up.sh 90 - self-shutdown after 90 minutes (the value is remembered)
# up.sh --allow 1.2.3.4 - also open port 6080 for this IP
# Price ~$0.85/h while running. Stop: down.sh. The instance is not deleted by itself.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
MIN=""; ALLOW=""
while [ $# -gt 0 ]; do case "$1" in --allow) ALLOW="${2:-}"; shift;; *[!0-9]*|"") ;; *) MIN=$1;; esac; shift; done
st=$(p8_state); echo "was: $st"
[ "$st" = stopping ] && { aws ec2 wait instance-stopped --instance-ids "$P8_INSTANCE"; st=stopped; }
if [ "$st" = stopped ]; then
  aws ec2 start-instances --instance-ids "$P8_INSTANCE" --query 'StartingInstances[0].CurrentState.Name' --output text
  echo "start $(date -u +%FT%TZ)" >> "$P8_STATE/usage.log"
fi
aws ec2 wait instance-running --instance-ids "$P8_INSTANCE"
IP=$(p8_ip); echo "running, IP: $IP"; p8_secret_set LAST_PUBLIC_IP "$IP"
if [ -n "$ALLOW" ]; then
  aws ec2 authorize-security-group-ingress --group-id "$P8_SG" \
    --ip-permissions "IpProtocol=tcp,FromPort=6080,ToPort=6080,IpRanges=[{CidrIp=$ALLOW/32,Description=owner}]" >/dev/null 2>&1 \
    && echo "port 6080 open for $ALLOW" || echo "port 6080 for $ALLOW: the rule already existed or an error (check in SG $P8_SG)"
fi
echo -n "waiting for SSH"; ok=0
for i in $(seq 1 72); do timeout 5 bash -c "echo > /dev/tcp/$IP/22" 2>/dev/null && { ok=1; break; }; echo -n .; sleep 5; done; echo
[ $ok = 1 ] || { echo "SSH did not come up in 6 min"; exit 1; }
sleep 3
[ -n "$MIN" ] && p8_ssh "echo $MIN> C:\p8\autostop_minutes.txt & shutdown /a >nul 2>&1 & shutdown /s /t $((MIN*60)) /c \"P8 auto-stop after $MIN min\"" >/dev/null 2>&1
echo -n "waiting for the noVNC page"; ok=0
for i in $(seq 1 36); do [ "$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 "https://$IP:6080/vnc.html")" = 200 ] && { ok=1; break; }; echo -n .; sleep 5; done; echo
[ $ok = 1 ] && echo "page: up" || echo "the page does not answer in 3 min (the P8-noVNC task on Windows)"
echo "self-shutdown in $(p8_ssh "type C:\p8\autostop_minutes.txt" 2>/dev/null | tr -dc 0-9) min after boot (cancel in Windows: shutdown /a)"
p8_ssh "query user 2>nul | findstr /i console >nul && echo CONSOLE_YES || echo CONSOLE_NO" 2>/dev/null | grep -q CONSOLE_YES && echo "console session: Administrator logged in by itself" || echo "console session: no login"
p8_ssh "tasklist /fi \"imagename eq RobloxStudioBeta.exe\" /fo csv /nh" 2>/dev/null | grep -qi RobloxStudio && echo "Studio: running" || echo "Studio: not running (since 18.10 it does not open by itself: open_local.sh - a local file, P8-OpenCony - the cloud place by hand)"
echo
echo "LINK FOR THE BROWSER: https://$IP:6080/"
echo "  screen password (VNC): grep VNC_PASSWORD $P8_SECRETS   (do not send it to the chat)"
echo "  fallback login without encryption: http://$IP:6081/ (the port is open only for the VPS)"
echo "price ~$P8_PRICE_HOUR \$/h while running. Stop: $P8_TOOLS/down.sh"
