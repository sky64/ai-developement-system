#!/usr/bin/env bash
# Unit test for tools/orca-version-check.sh: one line, exit 0 always,
# drift=yes only when the running and the recorded version both exist and differ.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/tools/orca-version-check.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
stub() { printf '#!/usr/bin/env bash\necho "%s"\n' "$1" > "$TMP/orca"; chmod +x "$TMP/orca"; }
printf '## State\n\n| Item | Result |\n|---|---|\n| Orca | 1.4.255 verified 2026-11-17 on the local host; runtime ready |\n| Claude Code hooks | x |\n' > "$TMP/docs12.md"
printf '## State\n\n| Item | Result |\n|---|---|\n| Claude Code hooks | x |\n' > "$TMP/docs12-norow.md"

stub "1.4.259"
out="$(ORCA_CLI_COMMAND="$TMP/orca" bash "$CHECK" "$TMP/docs12.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "orca=1.4.259 docs12=1.4.255 drift=yes" ] && ok "newer host → drift=yes" || bad "drift yes: rc=$rc out=$out"

stub "orca 1.4.255 (build x)"
out="$(ORCA_CLI_COMMAND="$TMP/orca" bash "$CHECK" "$TMP/docs12.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "orca=1.4.255 docs12=1.4.255 drift=no" ] && ok "same version with a prefix → drift=no" || bad "drift no: rc=$rc out=$out"

out="$(ORCA_CLI_COMMAND="$TMP/nonexistent" bash "$CHECK" "$TMP/docs12.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "orca=none docs12=1.4.255 drift=no" ] && ok "missing binary → orca=none, exit 0" || bad "missing binary: rc=$rc out=$out"

stub "1.4.259"
out="$(ORCA_CLI_COMMAND="$TMP/orca" bash "$CHECK" "$TMP/docs12-norow.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "orca=1.4.259 docs12=none drift=no" ] && ok "docs without an Orca row → docs12=none" || bad "no row: rc=$rc out=$out"

out="$(ORCA_CLI_COMMAND="$TMP/orca" bash "$CHECK" "$TMP/missing.md" 2>&1)"; rc=$?
[ "$rc" = 0 ] && [ "$out" = "orca=1.4.259 docs12=none drift=no" ] && ok "missing docs file → docs12=none, exit 0" || bad "missing docs: rc=$rc out=$out"

exit $fail
