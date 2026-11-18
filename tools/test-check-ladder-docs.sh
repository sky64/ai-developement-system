#!/usr/bin/env bash
# Unit test for tools/check-ladder-docs.sh: the pins on agents/scout64.md read
# the effective frontmatter fields, not any matching text in the file. Runs the
# checker against mutated copies of the working tree. Exit 0 = all pass.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
COPY="$TMP/copy"; AGENT="$COPY/agents/scout64.md"
fail=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1"; fail=1; }
fresh() { # a pristine copy of the files the checker reads
  rm -rf "$COPY"; mkdir -p "$COPY"
  cp -r "$ROOT/agents" "$ROOT/config" "$ROOT/docs" "$ROOT/skills" "$ROOT/tools" \
        "$ROOT/.claude-plugin" "$ROOT/AGENTS.md" "$ROOT/README.md" "$COPY/"
}
check() { out="$(bash "$COPY/tools/check-ladder-docs.sh" 2>&1)"; rc=$?; }
rejects() { # label : the checker must exit 1 and name the agent file
  check
  [ "$rc" = 1 ] && case "$out" in *"agents/scout64.md"*) true;; *) false;; esac \
    && ok "$1" || bad "$1: rc=$rc out=$out"
}

# 1. the shipped tree passes
fresh; check
[ "$rc" = 0 ] && [ "$out" = "ladder docs OK" ] && ok "unmodified tree → ladder docs OK" || bad "unmodified: rc=$rc out=$out"

# 2. the model field changed, the old value kept as a YAML comment
fresh; sed -i 's/^model: haiku$/model: sonnet # model: haiku/' "$AGENT"
rejects "model: sonnet with the pinned text in a comment → rejected"

# 3. a second model line after the pinned one (the later key wins in YAML)
fresh; sed -i 's/^model: haiku$/model: haiku\nmodel: sonnet/' "$AGENT"
rejects "a duplicate model key → rejected"

# 4. a write tool appended to the tools field
fresh; sed -i 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob, Bash, Write/' "$AGENT"
rejects "tools field with Write appended → rejected"

# 5. the same, with the pinned tools line quoted in the prompt body as a decoy
fresh; sed -i 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob, Bash, Write/' "$AGENT"
printf '\nPrevious tools:\n\n```text\ntools: Read, Grep, Glob, Bash\nmodel: haiku\n```\n' >> "$AGENT"
rejects "tools field with Write and a decoy line in the body → rejected"

# 6. no frontmatter block at all: the pinned lines are body text
fresh; sed -i '1d' "$AGENT"
rejects "agent file without a frontmatter block → rejected"

exit $fail
