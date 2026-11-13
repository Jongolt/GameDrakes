#!/bin/bash
# Stop the P8 machine (stop, not terminate: the disk with the install and the Roblox login is kept, ~$5.7/month for the disk).
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh" || exit 1
st=$(p8_state); echo "was: $st"
if [ "$st" = running ] || [ "$st" = pending ]; then
  aws ec2 stop-instances --instance-ids "$P8_INSTANCE" --query 'StoppingInstances[0].CurrentState.Name' --output text
  echo "stop $(date -u +%FT%TZ)" >> "$P8_STATE/usage.log"
fi
[ "$st" = stopped ] || aws ec2 wait instance-stopped --instance-ids "$P8_INSTANCE"
echo "now: $(p8_state)"
