#!/usr/bin/env bash
# Prints one line: orca=<running|none> docs12=<recorded|none> drift=yes|no
# The running version comes from `${ORCA_CLI_COMMAND:-orca} --version`; the
# recorded one from the "| Orca | <version>" row of docs/12-orca-setup.md,
# the owner's verification log. drift=yes means this host runs an Orca that
# docs/12 has not verified: the orchestrator says so and carries on. Exit 0 always.
# usage: orca-version-check.sh [path/to/docs/12-orca-setup.md]
set -u
docs="${1:-$(cd "$(dirname "$0")/.." && pwd)/docs/12-orca-setup.md}"
ver_re='[0-9]+\.[0-9]+\.[0-9]+'
running="$("${ORCA_CLI_COMMAND:-orca}" --version 2>/dev/null | grep -oE "$ver_re" | head -1 || true)"
recorded="$(grep -E '^\| Orca \|' "$docs" 2>/dev/null | head -1 | grep -oE "$ver_re" | head -1 || true)"
drift=no
if [ -n "$running" ] && [ -n "$recorded" ] && [ "$running" != "$recorded" ]; then drift=yes; fi
printf 'orca=%s docs12=%s drift=%s\n' "${running:-none}" "${recorded:-none}" "$drift"
exit 0
