#!/usr/bin/env bash
# Store an agent GitHub token in the 1Password vault Agents.
# Usage: new-agent-token.sh TITLE USERNAME HOSTNAME EXPIRY_YYYY-MM-DD [CLOUD_ENV_KEY]
# The token is read from the terminal without echo and is never printed.
# With CLOUD_ENV_KEY, the stored credential is also copied into Cloudroom's
# cloud environment under that key.
set -euo pipefail

if [ "$#" -lt 4 ] || [ "$#" -gt 5 ]; then
  echo "usage: $0 TITLE USERNAME HOSTNAME EXPIRY_YYYY-MM-DD [CLOUD_ENV_KEY]" >&2
  exit 64
fi

title=$1
username=$2
hostname=$3
expiry=$4
env_key=${5:-}
template="$(cd "$(dirname "$0")" && pwd)/agent-token.template.json"

if ! [[ $expiry =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  echo "expiry must be YYYY-MM-DD" >&2
  exit 64
fi

read -rs -p "Token for $username: " token
echo >&2
if [ -z "$token" ]; then
  echo "empty token" >&2
  exit 1
fi

# The token reaches python through the environment, not argv, so it does not
# show in the process list.
# op echoes the new item, credential included, so its output goes straight
# to the id parser and is never stored or printed.
item_id=$(
  AGENT_TOKEN="$token" python3 -I -c '
import json, os, sys
path, title, username, hostname, expiry = sys.argv[1:6]
with open(path) as f:
    item = json.load(f)
item["title"] = title
values = {
    "username": username,
    "credential": os.environ["AGENT_TOKEN"],
    "expires": expiry,
    "hostname": hostname,
}
for field in item["fields"]:
    if field["id"] in values:
        field["value"] = values[field["id"]]
json.dump(item, sys.stdout)
' "$template" "$title" "$username" "$hostname" "$expiry" |
    op item create --vault Agents --format json - |
    python3 -I -c 'import json, sys; print(json.load(sys.stdin)["id"])'
)
unset token
echo "Created 1Password item $item_id in vault Agents." >&2

if [ -n "$env_key" ]; then
  op read "op://Agents/$item_id/credential" | room-cli cloud env set "$env_key"
  echo "Copied credential into cloud environment key $env_key." >&2
fi
