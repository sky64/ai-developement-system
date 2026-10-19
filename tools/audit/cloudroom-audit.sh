#!/usr/bin/env bash
# cloudroom-audit.sh : READ-ONLY inventory of a machine that runs Cloudroom and/or coding-agent CLIs.
#
# - Makes no changes and installs nothing. Preliminary inventory, not a security audit.
# - CLI/config status output may include sensitive account details; review locally before sharing.
# - Run on each machine involved (Omarchy workstation, Mac with the Cloudroom app, Cloudroom Core host):
#       bash tools/audit/cloudroom-audit.sh > audit/$(hostname)-$(date +%F).txt
# - Review the output before sharing. Then commit it under audit/ or paste it into the session.
#
# Exit code is always 0; missing tools are reported, not fatal.

set -u
export LC_ALL=C

hr()   { printf '\n==== %s ====\n' "$1"; }
has()  { command -v "$1" >/dev/null 2>&1; }
ver()  { if has "$1"; then printf '%-12s present  %s\n' "$1" "$("$@" 2>/dev/null | head -1)"; else printf '%-12s MISSING\n' "$1"; fi; }
exists(){ if [ -e "$1" ]; then printf '  [x] %s\n' "$1"; else printf '  [ ] %s\n' "$1"; fi; }
count(){ if [ -d "$1" ]; then printf '  %s: %s entries\n' "$1" "$(find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')"; else printf '  %s: absent\n' "$1"; fi; }
json_keys(){ # print top-level keys of a JSON file, never values
  [ -f "$1" ] || { printf '  %s: absent\n' "$1"; return; }
  if has python3; then python3 -I -c 'import json,sys
try:
  d=json.load(open(sys.argv[1]))
  print("  "+sys.argv[1]+" keys: "+", ".join(sorted(d.keys())) if isinstance(d,dict) else "  (not an object)")
except Exception as e: print("  "+sys.argv[1]+": unreadable ("+type(e).__name__+")")' "$1"
  else printf '  %s: present (python3 missing, keys not listed)\n' "$1"; fi
}

hr "0. Context"
printf 'date: %s\nhost: %s\nuser: %s\nos: %s\n' "$(date -u +%FT%TZ)" "$(hostname)" "$(id -un)" "$(uname -srm)"
[ -f /etc/os-release ] && grep -E '^(NAME|VERSION_ID|ID)=' /etc/os-release | sed 's/^/  /'
has sw_vers && sw_vers | sed 's/^/  /'
printf 'systemd: %s   cgroup2: %s   docker-socket: %s\n' \
  "$(has systemctl && echo yes || echo no)" \
  "$([ -f /sys/fs/cgroup/cgroup.controllers ] && echo yes || echo no)" \
  "$([ -S /var/run/docker.sock ] && echo present || echo absent)"

hr "1. Cloudroom"
printf 'Desktop app (GUI):\n'
exists "/Applications/Cloudroom.app"
exists "$HOME/Library/Application Support/Cloudroom"
exists "$HOME/.config/Cloudroom"
exists "$HOME/.config/cloudroom"
exists "$HOME/.local/share/Cloudroom"
ls -d "$HOME"/.config/*loudroom* "$HOME"/Library/Application\ Support/*loudroom* 2>/dev/null | sed 's/^/  found: /'
printf 'Core (self-hosted runtime):\n'
exists /usr/local/lib/cloudroom/cloudroom
exists /etc/cloudroom/core.env
exists /etc/cloudroom/storage.json
exists /var/lib/cloudroom/history
exists /code
if has systemctl; then printf '  cloudroom.service: %s\n' "$(systemctl is-active cloudroom.service 2>/dev/null || echo not-found)"; fi
if has ss; then printf '  port 9840 listening: %s\n' "$(ss -ltn 2>/dev/null | grep -q ':9840 ' && echo yes || echo no)"; elif has lsof; then printf '  port 9840 listening: %s\n' "$(lsof -iTCP:9840 -sTCP:LISTEN >/dev/null 2>&1 && echo yes || echo no)"; fi
id cloudroom-agent >/dev/null 2>&1 && printf '  user cloudroom-agent: present (sudo? %s)\n' "$(sudo -l -U cloudroom-agent 2>/dev/null | grep -q 'may run' && echo YES-REVIEW || echo no/unknown)" || printf '  user cloudroom-agent: absent\n'
ver room-cli --version
has tailscale && printf '  tailscale: %s\n' "$(tailscale status --json 2>/dev/null | grep -o '"BackendState":"[^"]*"' | head -1)" || printf '  tailscale: MISSING\n'

hr "2. Agent harness CLIs (versions)"
ver claude --version
ver codex --version
ver opencode --version
ver pi --version
ver hermes --version
ver cursor-agent --version
ver openclaw --version
ver node --version
ver python3 --version
ver git --version
ver gh --version
ver op --version

hr "3. Authentication status (status only, no tokens)"
printf 'Claude Code:\n'
if has claude; then claude auth status 2>/dev/null | sed 's/^/  /' || printf '  (claude auth status unavailable in this version)\n'; fi
exists "$HOME/.claude/.credentials.json"
exists "$HOME/.claude.json"
printf 'Codex (must be authenticated separately from ChatGPT web):\n'
if has codex; then codex login status 2>&1 | sed 's/^/  /'; fi
exists "$HOME/.codex/auth.json"
exists "$HOME/.codex/config.toml"
printf 'OpenCode:\n'
if has opencode; then opencode auth list 2>&1 | sed 's/^/  /' | head -20; fi
exists "$HOME/.local/share/opencode/auth.json"
exists "$HOME/.local/share/opencode/opencode.db"
exists "$HOME/.config/opencode/opencode.json"
printf 'Pi:\n'
exists "$HOME/.pi/agent/auth.json"
[ -f "$HOME/.pi/agent/auth.json" ] && json_keys "$HOME/.pi/agent/auth.json"   # provider names only
count "$HOME/.pi/agent/extensions"
printf 'Hermes:\n'
exists "$HOME/.hermes/config.yaml"
[ -f "$HOME/.hermes/config.yaml" ] && grep -E '^\s*(approvals|mode|provider|model|platforms|telegram|discord|slack|memory|cron):' "$HOME/.hermes/config.yaml" 2>/dev/null | sed 's/^/  cfg: /' | head -20
printf 'GitHub:\n'
if has gh; then gh auth status 2>&1 | sed 's/^/  /'; fi
printf '  git user.name set: %s\n' "$(git config --global user.name >/dev/null 2>&1 && echo yes || echo no)"
printf '1Password CLI:\n'
if has op; then op whoami 2>&1 | sed 's/^/  /' | head -5; printf '  OP_SERVICE_ACCOUNT_TOKEN in env: %s\n' "${OP_SERVICE_ACCOUNT_TOKEN:+set}"; fi

hr "4. Everything Claude Code (ECC) footprint"
printf 'Claude plugin route:\n'
json_keys "$HOME/.claude/settings.json"
if [ -f "$HOME/.claude/settings.json" ] && has python3; then python3 -I - "$HOME/.claude/settings.json" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit()
ep=d.get("enabledPlugins",{}); mk=d.get("extraKnownMarketplaces",{}); hk=d.get("hooks",{})
print("  enabledPlugins:", ", ".join(k for k,v in ep.items() if v) or "none")
print("  extraKnownMarketplaces:", ", ".join(mk.keys()) or "none")
print("  hooks by event:", {k:len(v) for k,v in hk.items()} if hk else "none")
txt=json.dumps(hk)
print("  Hook config mentions ECC (ownership unverified):", "yes" if "ecc" in txt.lower() else "no")
PY
fi
ls -d "$HOME"/.claude/plugins/cache/*ecc* "$HOME"/.claude/plugins/*/ecc* 2>/dev/null | sed 's/^/  plugin dir: /'
printf 'Local skill/agent entries (ownership and duplicate registrations need inspection):\n'
count "$HOME/.claude/skills"
ls "$HOME/.claude/skills" 2>/dev/null | head -40 | tr '\n' ' ' | sed 's/^/  skills: /'; echo
count "$HOME/.claude/agents"
count "$HOME/.claude/commands"
exists "$HOME/.claude/rules/ecc"
exists "$HOME/.ecc"
exists "$HOME/.ecc/memory"
exists "$HOME/.claude/ecc-install-state.json"
printf 'Other harness routes:\n'
exists "$HOME/.codex/ecc-manifest.json"
ls -d "$HOME"/.codex/*ecc* 2>/dev/null | sed 's/^/  codex: /'
[ -f "$HOME/.config/opencode/opencode.json" ] && grep -o '"plugin"[^]]*]' "$HOME/.config/opencode/opencode.json" 2>/dev/null | sed 's/^/  opencode plugins: /'
exists "$HOME/.hermes/hooks"
printf 'Global instruction files:\n'
exists "$HOME/.claude/CLAUDE.md"
exists "$HOME/.codex/AGENTS.md"
exists "$HOME/.config/opencode/AGENTS.md"
exists "$HOME/.pi/agent/AGENTS.md"

hr "5. MCP servers configured (names only)"
[ -f "$HOME/.claude.json" ] && has python3 && python3 -I - "$HOME/.claude.json" <<'PY'
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: sys.exit()
print("  user-level mcpServers:", ", ".join((d.get("mcpServers") or {}).keys()) or "none")
projs=d.get("projects") or {}
print("  projects known to Claude Code:", len(projs))
PY
[ -f "$HOME/.codex/config.toml" ] && grep -E '^\[mcp_servers\.' "$HOME/.codex/config.toml" | sed 's/^/  codex: /'

hr "6. Credential hygiene (names only)"
printf 'env var NAMES matching KEY|TOKEN|SECRET|PASSWORD:\n'
env | cut -d= -f1 | grep -E 'KEY|TOKEN|SECRET|PASSWORD' | sort | tr '\n' ' ' | sed 's/^/  /'; echo
printf '.env files under HOME (depth<=3, paths only):\n'
find "$HOME" -maxdepth 3 -name '.env' -not -path '*/node_modules/*' 2>/dev/null | head -20 | sed 's/^/  /'
printf 'world-readable auth files:\n'
for f in "$HOME/.codex/auth.json" "$HOME/.claude/.credentials.json" "$HOME/.local/share/opencode/auth.json" "$HOME/.pi/agent/auth.json" /etc/cloudroom/core.env; do
  [ -f "$f" ] && printf '  %s mode=%s\n' "$f" "$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f" 2>/dev/null)"
done

hr "7. Git repositories under common roots (paths only)"
for root in "$HOME/code" "$HOME/src" "$HOME/projects" "$HOME/dev" "$HOME/Developer" /code; do
  [ -d "$root" ] && find "$root" -maxdepth 2 -name .git -type d 2>/dev/null | sed 's#/.git$##; s/^/  /' | head -40
done

hr "done"
printf 'Review CLI/config output for sensitive details before sharing. Counts do not prove duplicate installs.\n'
