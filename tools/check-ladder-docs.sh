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

need docs/05-delegation.md "## Model ladder"
need docs/05-delegation.md "rung defaults to its tier"
need docs/05-delegation.md "risky tier is always rung 2"
need docs/05-delegation.md "never moved down a rung"
need docs/05-delegation.md "at most two escalations"
need docs/05-delegation.md "identical at every rung"
need docs/05-delegation.md "only through a new decision record"
need docs/05-delegation.md "docs/12-orca-setup.md records a working dsh"
need docs/05-delegation.md "## Plans and owner items"
need docs/05-delegation.md "## Ladder review"
# Final-review pins (2026-11-17)
need docs/05-delegation.md "gpt-6.1-sol"
need docs/05-delegation.md "reported to the owner and corrected by a decision record"
need docs/05-delegation.md "At rung 2, an escalation re-dispatches at rung 2"
need docs/05-delegation.md "one allowance of two per task"
need docs/05-delegation.md "DeepSeek row where docs/12-orca-setup.md records it, otherwise the Claude row"
need docs/05-delegation.md "except a budget or provider error"
need docs/05-delegation.md "Rung: <n>; Model: <id>; Tokens: <in>/<out>"
need docs/05-delegation.md "no Claude Code skills or hooks"

need AGENTS.md "complexity rung"

need skills/orchestrator/SKILL.md "Rung:"
need skills/orchestrator/SKILL.md "--model"
need skills/orchestrator/SKILL.md "x-solvela-session"
need skills/orchestrator/SKILL.md "rung 1"
need skills/orchestrator/SKILL.md "one rung higher"
need skills/orchestrator/SKILL.md "budget"
need skills/orchestrator/SKILL.md "Risky is always rung 2"
need skills/orchestrator/SKILL.md "After two escalations"
need skills/orchestrator/SKILL.md "At rung 2, an escalation re-dispatches at rung 2"
need skills/orchestrator/SKILL.md "model parameter of the Agent tool"
need skills/orchestrator/SKILL.md "DeepSeek row where docs/12 records it, otherwise the Claude row"
need skills/orchestrator/SKILL.md '${CLAUDE_PLUGIN_ROOT}/docs/12-orca-setup.md'
need skills/orchestrator/SKILL.md "Rung: <n>; Model: <id>; Tokens: <in>/<out>"
need skills/orchestrator/SKILL.md "--model gpt-6.1-sol --effort"
need skills/orchestrator/SKILL.md "--model claude-sonnet-5-5"
need skills/orchestrator/SKILL.md "role attribution through the team API key"

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

if [ "$missing" -ne 0 ]; then
  printf '%d required phrase(s) missing\n' "$missing"
  exit 1
fi
echo "ladder docs OK"
