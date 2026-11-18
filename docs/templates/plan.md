# <Piece of work> plan

Written by a rung-2 worker; approved once by the owner together with the Owner items below. Tasks then dispatch without further approval. Rules: `docs/05-delegation.md`, "Model ladder", "Process ladder" and "Plans and owner items".

**Spec:** <path to the decision record or design this plan implements>

## Global Constraints

- <one line per project-wide requirement, exact values copied from the spec>
- Rungs are set here and only climb; a risky-tier task is rung 2; the Tooling table is identical at every rung.

## Tooling

Filled with the `plan-tooling` skill before rungs are assigned. Shape:

```markdown
| Part of the job | Tool (exact id) | Kind | Used at | Why this one |
|---|---|---|---|---|
| <part> | <skill, agent, MCP tool or CLI id as the roster prints it> | skill / agent / MCP / CLI / library / none | build / verify / runtime | <reason> |

**Checked and rejected:** <at least one candidate and why>.

**Gaps to build first:** <named gaps, each the first task(s) of this plan> or `none`.
```

## Owner items

Everything the owner must supply before a task can run. Secrets are named, never valued.

| Item | Who issues it | Blocks |
|---|---|---|
| <credential name, account, decision, content or approval> | <owner, vendor, third party> | Task <N> |

## Tasks

| Task | Tier | Rung | Mode | Vendor | Model | Tools | Acceptance | Owner item |
|---|---|---|---|---|---|---|---|---|
| 1. <what it delivers> | trivial / normal / risky | 0 / 1 / 2 (risky is always 2) | native / delegated (risky is always delegated) | DeepSeek where docs/12 records it, otherwise Claude; Codex for review | <from the ladder table for the rung and role> | <ids from the Tooling table> | <the check and its expected output> | <item from the table above, or none> |

Each task below the table carries its files, the failing test first, the implementation step, the verification command with its expected output, and the commit.
