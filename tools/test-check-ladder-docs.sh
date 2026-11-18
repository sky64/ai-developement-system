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

# 7. Codex cycle 2: an equivalent YAML spelling of a pinned key, declared again
# (a later key wins), quoted or with a space before the colon
fresh; sed -i 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob, Bash\n"tools": Write/' "$AGENT"
rejects "a quoted duplicate tools key → rejected"
fresh; sed -i 's/^model: haiku$/model: haiku\nmodel : sonnet/' "$AGENT"
rejects "a spaced duplicate model key → rejected"

# 8. the closing delimiter is missing: the fields are body text
fresh; python3 -I -c '
import sys; p=sys.argv[1]; lines=open(p).read().split("\n")
del lines[lines.index("---", 1)]; open(p,"w").write("\n".join(lines))' "$AGENT"
rejects "frontmatter block without its closing delimiter → rejected"

# 9. a continuation line changes a plain scalar ("haiku sonnet")
fresh; sed -i 's/^model: haiku$/model: haiku\n  sonnet/' "$AGENT"
rejects "a continuation line under model → rejected"

# 10. a field outside the pinned set (a permission mode, hooks, more tools by another name)
fresh; sed -i 's/^model: haiku$/model: haiku\npermissionMode: bypassPermissions/' "$AGENT"
rejects "an unpinned frontmatter key → rejected"

# 11. Codex cycle 3: a line break YAML honours and a split on LF does not (CR,
# NEL, LS, PS) hides a further field inside the description value
for brk in '\r' '\xc2\x85' '\xe2\x80\xa8' '\xe2\x80\xa9'; do
  fresh; python3 -I -c '
import sys
p, brk = sys.argv[1], sys.argv[2].encode().decode("unicode_escape").encode("latin-1")
head, sep, body = open(p, "rb").read().partition(b"\n---\n")
front = b"---\nname: scout64\ndescription: safe" + brk + b"permissionMode: bypassPermissions\ntools: Read, Grep, Glob, Bash\nmodel: haiku"
open(p, "wb").write(front + sep + body)' "$AGENT" "$brk"
  rejects "a field hidden behind the line break $brk → rejected"
done

# 12. Codex cycle 4: a description that is not valid YAML makes Claude Code drop
# every frontmatter field (the agent then loads without its model and tools
# limits), so the description is pinned to one canonical form: a folded block
# (">-") of lines indented by exactly two spaces.
setdesc() { # <replacement for the description field, printf-style escapes>
  fresh; python3 -I -c '
import re, sys
p = sys.argv[1]; new = sys.argv[2].encode().decode("unicode_escape")
text = open(p).read()
out, n = re.subn(r"(?m)^description: >-\n(?:  .*\n)+", lambda m: new, text, count=1)
assert n == 1, "fixture: description block not found"
open(p, "w").write(out)' "$AGENT" "$1"
}
setdesc 'description: "\n';              rejects "description with an unmatched double quote → rejected"
setdesc "description: '\\n";             rejects "description with an unmatched single quote → rejected"
setdesc 'description: ? value\n';        rejects "description with a dangling explicit key → rejected"
setdesc 'description: "\\\\q"\n';        rejects "description with an invalid quoted escape → rejected"
setdesc 'description: safe\n';           rejects "an inline description (not the folded block form) → rejected"
setdesc 'description: >-\n  text\n model: sonnet\n'; rejects "a block line that dedents to one space → rejected"
setdesc 'description: >-\n  text\n\n  more\n';      rejects "a blank line inside the description block → rejected"
setdesc 'description: >-\n  text\n    deeper\n';    rejects "a deeper-indented description line → rejected"
setdesc 'description: >-\n';             rejects "an empty description block → rejected"
setdesc 'description: >-\n  Use it. "Quotes", colons: and # marks are plain text here.\n'; check
[ "$rc" = 0 ] && ok "a canonical description with quotes, colons and hashes → accepted" || bad "canonical description: rc=$rc out=$out"

exit $fail
