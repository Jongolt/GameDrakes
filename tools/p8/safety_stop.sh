#!/bin/bash
# a VPS safety net: stop the instance at a given UTC time (HH:MM), whatever happens to the session. Only stop, no terminate.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
target=$(date -u -d "${1:?HH:MM UTC}" +%s); now=$(date -u +%s)
sleep $(( target > now ? target - now : 0 ))
st=$(p8_state); echo "$(date -u +%FT%TZ) safety check: state=$st"
if [ "$st" = running ] || [ "$st" = pending ]; then
  aws ec2 stop-instances --instance-ids "$P8_INSTANCE" --query 'StoppingInstances[0].CurrentState.Name' --output text
  echo "safety-stop $(date -u +%FT%TZ)" >> "$P8_STATE/usage.log"
fi
echo "$(date -u +%FT%TZ) safety done"
