#!/usr/bin/env bash
# Pins the wording of the model ladder (docs/decisions/0004-model-ladder.md)
# across the files that carry it. Exits 1 and lists every missing
# "file: phrase" so a later edit cannot silently drop a rule.
set -u

cd "$(dirname "$0")/.." || exit 1

missing=0

need() {
  local file="$1" phrase="$2"
  if ! grep -qF -- "$phrase" "$file" 2>/dev/null; then
    printf '%s: %s\n' "$file" "$phrase"
    missing=$((missing + 1))
  fi
}
forbid() {
  local file="$1" phrase="$2"
  if grep -qF -- "$phrase" "$file" 2>/dev/null; then
    printf '%s: must not contain %s\n' "$file" "$phrase"; missing=$((missing + 1))
  fi
}
agent_fields() { # file field... : the agent file's frontmatter is exactly these fields
  # A field is "key=value" (the value must match exactly) or "key" (any value).
  # The frontmatter is read as a strict subset of YAML, so that what this
  # check sees is what any YAML parser sees: an opening "---" on line 1 and a
  # closing "---"; inside, only plain "key: value" lines, each key once, and
  # indented text only under a block scalar ("key: >-"). Quoted or spaced
  # keys, comments, continuation lines, nested values and keys outside the
  # listed set are rejected rather than interpreted.
  local out
  if ! out="$(python3 -I -c '
import re, sys

path, wanted = sys.argv[1], [a.partition("=") for a in sys.argv[2:]]


def fail(msg):
    print(f"{path}: {msg}")
    sys.exit(1)


try:
    with open(path, encoding="utf-8", newline="") as fh:
        lines = fh.read().split("\n")
except (OSError, UnicodeDecodeError) as exc:
    fail(f"cannot read the agent file: {exc}")
if lines[0] != "---":
    fail("no frontmatter block on line 1")
if "---" not in lines[1:]:
    fail("the frontmatter block is not closed")
fields, in_block = {}, False
for number, line in enumerate(lines[1:lines.index("---", 1)], start=2):
    plain = re.fullmatch(r"([A-Za-z][A-Za-z0-9_-]*): (\S.*)", line)
    if plain:
        key, value = plain.groups()
        if key in fields:
            fail(f"line {number}: frontmatter key {key} is declared twice")
        fields[key] = value
        in_block = re.fullmatch(r"[>|][+-]?", value) is not None
    elif not (in_block and (line == "" or line.startswith(" "))):
        fail(f"line {number}: frontmatter line is not a plain key: value line")
allowed = [key for key, _, _ in wanted]
for key in fields:
    if key not in allowed:
        fail(f"frontmatter key {key} is not one of: {", ".join(allowed)}")
for key, pinned, value in wanted:
    if key not in fields:
        fail(f"frontmatter must carry the field {key}")
    if pinned and fields[key] != value:
        fail(f"frontmatter must carry exactly: {key}: {value}")
' "$@" 2>&1)"; then
    printf '%s\n' "$out"
    missing=$((missing + 1))
  fi
}

need docs/05-delegation.md "## Model ladder"
need docs/05-delegation.md "rung defaults to its tier"
need docs/05-delegation.md "risky tier is always rung 2"
need docs/05-delegation.md "never moved down a rung"
need docs/05-delegation.md 'at most `limits.review_cycles` escalations'
need docs/05-delegation.md "identical at every rung"
need docs/05-delegation.md "only through a new decision record"
need docs/05-delegation.md "docs/12-orca-setup.md records a working dsh"
need docs/05-delegation.md "## Plans and owner items"
need docs/05-delegation.md "## Ladder review"
# Final-review pins (2026-11-17)
need docs/05-delegation.md "gpt-6.1-sol"
need docs/05-delegation.md "reported to the owner and corrected by a decision record"
need docs/05-delegation.md "At rung 2, an escalation re-dispatches at rung 2"
need docs/05-delegation.md 'one allowance of `limits.review_cycles` per task'
need docs/05-delegation.md 'up to `limits.review_cycles` correction cycles (default 2)'
need docs/05-delegation.md 'DeepSeek row where `platform.hosts` has an entry for the host, otherwise the Claude row'
# Decision 0005: portability
need docs/05-delegation.md ".claude/crew64.json"
need docs/05-delegation.md "config/crew64.defaults.json"
need docs/05-delegation.md "gateway.kind"
need docs/05-delegation.md "the configured gateway"
need AGENTS.md "features.bot_identity"
need AGENTS.md "install-bot-identity.sh"
need README.md "## Using this on your own setup"
need README.md "tools/crew64-enable.sh"
need README.md "config/examples/orca-solvela.json"
need README.md "crew64.trustedRoot"
need README.md "## Upgrading an existing install"
need README.md "re-run tools/crew64-enable.sh against each existing main checkout"
need docs/decisions/0005-feature-switches-and-portability.md "until it is registered every reader uses the defaults"
need docs/decisions/0005-feature-switches-and-portability.md "crew64.trustedRoot"
need docs/12-orca-setup.md "crew64.bot.name"
need docs/05-delegation.md "except a budget or provider error"
need docs/05-delegation.md "Rung: <n>; Model: <id>; Tokens: <in>/<out>"
need docs/05-delegation.md "no Claude Code skills or hooks"

need AGENTS.md "complexity rung"
need AGENTS.md 'one allowance of `limits.review_cycles` per task'
need AGENTS.md "one budget, not three"

need skills/orchestrator/SKILL.md "Rung:"
need skills/orchestrator/SKILL.md "--model"
need skills/orchestrator/SKILL.md "x-solvela-session"
need skills/orchestrator/SKILL.md "rung 1"
need skills/orchestrator/SKILL.md "one rung higher"
need skills/orchestrator/SKILL.md "budget"
need skills/orchestrator/SKILL.md "Risky is always rung 2"
need skills/orchestrator/SKILL.md "When the allowance is spent"
need skills/orchestrator/SKILL.md "limits.review_cycles"
need skills/orchestrator/SKILL.md "CREW64_LIMIT_REVIEW_CYCLES"
need skills/orchestrator/SKILL.md "grants one more cycle"
need config/crew64.defaults.json '"review_cycles": 2'
need config/examples/orca-solvela.json '"review_cycles": 3'
# Decision 0007: the literal allowance of two is gone from live policy.
forbid AGENTS.md "allowance of two"
forbid docs/05-delegation.md "allowance of two"
forbid docs/05-delegation.md "at most two escalations"
forbid docs/05-delegation.md "up to two correction cycles"
forbid skills/orchestrator/SKILL.md "allowance of two"
forbid skills/orchestrator/SKILL.md "After two escalations"
forbid skills/orchestrator/SKILL.md "two-cycle allowance"
# Decision 0007: every brief names the runtime floor the review applies to.
need agents/specialist-agent.md.tmpl "Runtime:"
need agents/docs-engineer.md "Runtime:"
need skills/orchestrator/SKILL.md "Runtime:"
need skills/orchestrator/SKILL.md "outside that floor are out of scope"
need docs/05-delegation.md "Runtime:"
need AGENTS.md "Python 3.13+"
need .claude-plugin/plugin.json '"version": "0.7.0"'
# Field fixes 2026-11-18: briefs travel by --spec-file from the scratchpad.
need skills/orchestrator/SKILL.md "--spec-file"
need skills/orchestrator/SKILL.md "the guard allows Write and Edit there"
need README.md "/harness-enable"
need tools/harness-enable-skill/SKILL.md "crew64@crew64"
need tools/harness-enable-skill/enable.sh.tmpl "@CREW64_ENABLE@"
need skills/orchestrator/SKILL.md "orca-version-check.sh"
need docs/12-orca-setup.md "| Orca | 1.4.255"
need AGENTS.md "test-orca-version-check.sh"
need skills/orchestrator/SKILL.md "At rung 2, an escalation re-dispatches at rung 2"
need skills/orchestrator/SKILL.md "model parameter of the Agent tool"
need skills/orchestrator/SKILL.md "DeepSeek row where platform.hosts has an entry for the current host, otherwise the Claude row"
need skills/orchestrator/SKILL.md '${CLAUDE_PLUGIN_ROOT}/docs/12-orca-setup.md'
need skills/orchestrator/SKILL.md "Rung: <n>; Model: <id>; Tokens: <in>/<out>"
need skills/orchestrator/SKILL.md "--model gpt-6.1-sol --effort"
need skills/orchestrator/SKILL.md "--model claude-sonnet-5-5"
need skills/orchestrator/SKILL.md "role attribution through the team API key"
# Decision 0005: configuration, switches, platform seam
need skills/orchestrator/SKILL.md "## Configuration"
need skills/orchestrator/SKILL.md 'crew64_config.py" status'
need skills/orchestrator/SKILL.md "CREW64_FEATURE_"
need skills/orchestrator/SKILL.md "model_ladder"
need skills/orchestrator/SKILL.md "When model_ladder is off"
need skills/orchestrator/SKILL.md "When metering is none"
need skills/orchestrator/SKILL.md "When bot_identity is off"
need skills/orchestrator/SKILL.md "## Platform seam"
need skills/orchestrator/SKILL.md "create an isolated workspace"
need skills/orchestrator/SKILL.md "hand a diff to a reviewer"
need skills/orchestrator/SKILL.md "platform.hosts"
need skills/orchestrator/SKILL.md "gateway.kind"
need skills/orchestrator/SKILL.md "config/crew64.defaults.json"

need docs/templates/plan.md "| Vendor |"

need docs/12-orca-setup.md "## Model ladder routing"
need docs/12-orca-setup.md "applies once the profile row below is verified"

need agents/specialist-agent.md.tmpl "Rung:"
need agents/specialist-agent.md.tmpl "budget"
need agents/specialist-agent.md.tmpl "tokens"

need agents/docs-engineer.md "Rung:"

need docs/templates/plan.md "| Rung |"
need docs/templates/plan.md "## Owner items"
need docs/templates/plan.md "## Tooling"

need skills/plan-tooling/SKILL.md "name: plan-tooling"

# Decision 0008: scout64, the read-only Haiku helper. Its tools field carries no
# write tool, and its prompt makes "could not answer" a first-class result. The
# frontmatter is pinned as a whole: exactly these four fields, so no other
# field can widen what the scout may do, and matching text elsewhere in the
# file does not satisfy the pin (tools/test-check-ladder-docs.sh).
agent_fields agents/scout64.md name=scout64 description model=haiku "tools=Read, Grep, Glob, Bash"
need agents/scout64.md "could not answer"
need agents/scout64.md "never write, edit, commit"
forbid agents/scout64.md "Write,"
forbid agents/scout64.md "Edit,"
# Decision 0008: the rule. The skill states both the on and the off behaviour,
# so an off switch never leaves the orchestrator without a rule.
need skills/orchestrator/SKILL.md "crew64:scout64"
need skills/orchestrator/SKILL.md "When the scout's first line is"
need skills/orchestrator/SKILL.md "With \`features.scout64\` off"
need docs/05-delegation.md "crew64:scout64"
need README.md "features.scout64"
need config/crew64.defaults.json '"scout64": true'
forbid skills/orchestrator/SKILL.md "Native read-only subagents run on the rung 1 model from the table"
forbid docs/05-delegation.md "read-only native subagents run at rung 1 by default, and at rung 2 only"

# Decision 0005: the defaults file validates, and every model id it ships
# appears in the docs/05 ladder table, so the table and the file cannot drift.
if ! python3 -I tools/crew64_config.py check config/crew64.defaults.json >/dev/null 2>&1; then
  echo "config/crew64.defaults.json: fails crew64_config.py check"; missing=$((missing + 1))
fi
for id in $(python3 -I -c '
import json; d=json.load(open("config/crew64.defaults.json"))["models"]
ids=set(d["research"])|set(d["claude_implementer"])|{d["codex_reviewer"]["model"]}
print(" ".join(sorted(ids)))' 2>/dev/null); do
  need docs/05-delegation.md "$id"
done
# No owner-specific identity in stranger-facing docs.
forbid docs/11-plugin-install.md "Solvela-bot"

if [ "$missing" -ne 0 ]; then
  printf '%d required phrase(s) missing\n' "$missing"
  exit 1
fi
echo "ladder docs OK"
