# P8 (Windows + Roblox Studio on AWS): shared by up/down/mcp_bridge/click/... (source). Does not print keys and passwords.
# Everything bound to a specific machine and account (instance id, security group, paths to the SSH key, passwords and AWS keys)
# lives OUTSIDE the repo in $P8_ENV (default ~/.config/p8/p8.env, sample tools/p8/p8.env.example).
P8_TOOLS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
P8_ENV=${P8_ENV:-$HOME/.config/p8/p8.env}
if [ ! -r "$P8_ENV" ]; then
  echo "p8: no settings $P8_ENV (copy tools/p8/p8.env.example and fill it in)" >&2
  return 1 2>/dev/null || exit 1
fi
source "$P8_ENV"
: "${P8_INSTANCE:?no P8_INSTANCE in $P8_ENV}" "${P8_SSH_KEY:?no P8_SSH_KEY in $P8_ENV}" "${P8_STATE:?no P8_STATE in $P8_ENV}"
P8_USER=${P8_USER:-Administrator}
P8_PRICE_HOUR=${P8_PRICE_HOUR:-0.847}  # g4dn.xlarge Windows 0.842 + public IPv4 0.005, $/h, AWS API price
mkdir -p "$P8_STATE"                     # known_hosts, usage.log, mcp_session.err

# the AWS key from the P8_AWS_ENV file (the lines AWS_ACCESS_KEY_ID=... and AWS_SECRET_ACCESS_KEY=...), the values are not printed
if [ -n "${P8_AWS_ENV:-}" ] && [ -r "$P8_AWS_ENV" ]; then
  while IFS='=' read -r k v; do
    k="${k#export }"
    case "$k" in AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY) v="${v%\"}"; v="${v#\"}"; v="${v%\'}"; v="${v#\'}"; export "$k=$v";; esac
  done < <(grep -E '^(export )?AWS_(ACCESS_KEY_ID|SECRET_ACCESS_KEY)=' "$P8_AWS_ENV")
fi
export AWS_DEFAULT_REGION=${P8_REGION:-eu-central-1}
export AWS_PAGER=""

p8_state() { aws ec2 describe-instances --instance-ids "$P8_INSTANCE" --query 'Reservations[0].Instances[0].State.Name' --output text; }
p8_ip()    { aws ec2 describe-instances --instance-ids "$P8_INSTANCE" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text; }
P8_SSH_OPTS=(-i "$P8_SSH_KEY" -o IdentitiesOnly=yes -o HostKeyAlias=p8-studio -o UserKnownHostsFile="$P8_STATE/known_hosts"
             -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o ServerAliveInterval=30 -o LogLevel=ERROR)
p8_ssh() { local ip; ip=$(p8_ip); ssh "${P8_SSH_OPTS[@]}" "$P8_USER@$ip" "$@"; }
p8_scp_to() { local ip; ip=$(p8_ip); local dst="${@: -1}"; scp "${P8_SSH_OPTS[@]}" "${@:1:$#-1}" "$P8_USER@$ip:$dst"; }  # p8_scp_to files... C:/p8/
p8_scp_from() { local ip; ip=$(p8_ip); scp "${P8_SSH_OPTS[@]}" "$P8_USER@$ip:$1" "$2"; }  # p8_scp_from C:/p8/x.png ./x.png
p8_secret_set() { [ -n "${P8_SECRETS:-}" ] && [ -w "$P8_SECRETS" ] && sed -i "s|^$1=.*|$1=$2|" "$P8_SECRETS"; }  # the value is not printed
