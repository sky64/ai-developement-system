# Architecture proposal (Phase 1 deliverable) — Cloudroom Multi-Agent Development System

Status: **PROPOSED, awaiting approval.** Supersedes section 3 of `00-audit-and-architecture-proposal.md` after receipt of the implementation brief (2026-10-19). No installation or configuration has been changed.

Capability labels used throughout: **Implemented** (exists in this repo now), **Tested** (exercised end to end by me), **Native** (documented vendor feature, not yet tested by me), **Proposed** (to be built), **Unsupported** (verified absent or undocumented).

---

## 1. What the audit can and cannot see yet

This session runs in an Anthropic cloud container that holds only this repository. It cannot see your Cloudroom installation, your harness logins, or your ECC state. What is established so far:

| Fact | Evidence |
|---|---|
| You have a Linux workstation `sky64-omarchy` (Omarchy = Arch Linux) bridged to Claude Code Remote Control | Bridge environment created 2026-10-19 19:54 UTC (Tested) |
| The Claude iPhone app can start, monitor and converse with Claude Code sessions | This session's origin is `ios` (Tested) |
| Cloudroom = open-source Rust Core + desktop GUI (macOS; Linux x64 alpha) + invite-only hosted cloud | GitHub repos read directly (Native) |
| Cloudroom Core runs agents "without approval prompts"; GUI has Mac-access "Ask first"; hosted changelog mentions approvals for agent-initiated turns and a browser-installed mobile app | Core docs (Native); changelog (reported, untested) |
| ECC is a 311-skill / 71-agent / ~27-hook Claude plugin with partial Codex and OpenCode adapters | ECC repo read directly (Native) |
| "Ting Cactus" does not resolve to any known model | Web search, two queries, zero matches. See section 8 |

**To complete the audit I need the output of the read-only audit kit** (`tools/audit/cloudroom-audit.sh`, Implemented, Tested here) from each machine involved: the Omarchy workstation, any Mac running the Cloudroom app, and any self-hosted Core host. It prints versions, paths, auth *status*, ECC footprint, and credential hygiene, never secret values. Alternatively, resume this session through the Omarchy bridge and I run it myself with your approval.

Three questions the audit output answers that decide the topology:

1. Which Cloudroom mode you use today: Local threads in the desktop app, hosted Cloud threads (invite), or a self-hosted Core.
2. Whether Codex is authenticated as a harness (`codex login status`), separately from ChatGPT web.
3. Which ECC install route is live (plugin vs manual copy) and whether both coexist.

---

## 2. Simplest viable architecture

### 2.1 Design stance

Cloudroom is the execution and session platform. GitHub is the source of truth and the universal approval gate. Each harness keeps its own native guard rails. Claude Code coordinates. **Nothing custom sits in the approval path.** The only things built are files in Git: instructions, policies, templates, a provider registry, and a small set of hooks that already exist in the harnesses' own hook systems.

### 2.2 Topology

```
                 iPhone
   ┌──────────────┼──────────────────────────┐
   │ Claude app   │ GitHub app / mobile web  │ Cloudroom mobile web app (hosted only,
   │ sessions,    │ PRs, reviews, Actions,   │ Native, untested) or Tailscale → GUI
   │ prompts      │ Environment approvals    │ dashboard (self-hosted)
   └──────┬───────┴───────────┬──────────────┴──────────────┬─────────────────┘
          │                   │                             │
   Anthropic cloud      GitHub (source of truth)      Cloudroom (execution platform)
   Claude Code sessions ├─ protected main              ├─ Local threads (Omarchy / Mac)
   on this repo         ├─ CODEOWNERS = you            ├─ Cloud threads: own sandbox + branch
                        ├─ required PR review           │   (hosted invite OR self-hosted Core)
                        ├─ Actions: tests, lint,        └─ harnesses as separate processes:
                        │   typecheck, AgentShield          Claude Code · Codex · OpenCode
                        └─ Environments: production         Pi · Hermes (standalone if no adapter)
                            with required reviewer
```

### 2.3 Where each principle lands

| Principle | Mechanism | Label |
|---|---|---|
| Model independence | Every harness runs on your own login; shared `AGENTS.md` is harness-neutral; registry records substitutes per role | Proposed |
| Modularity | One directory per harness under `harness/`; skills as Markdown; providers as registry entries plus one adapter file each | Proposed |
| GitHub as truth | Branch protection, CODEOWNERS, PR template with decision record link, `docs/decisions/` | Proposed (GitHub Native) |
| Human oversight | Branch protection + GitHub Environments required reviewers (merge/deploy); Claude native prompts (actions); Hermes native approvals (actions); credential scoping (impossible actions) | Native |
| Agent specialization | Role matrix in `AGENTS.md`; routing table in `docs/workflows.md`; Claude delegates via Cloudroom child threads or Claude subagents | Proposed |
| Persistent context | `docs/progress.md`, `docs/decisions/`, `docs/architecture.md` in each project repo; Hermes memory for operational context only | Proposed |
| Mobile visibility | Claude app, GitHub app, Cloudroom hosted mobile web app (if you have hosted access) | Native, partly Tested |
| Security | No prod credentials on dev hosts; 1Password `op run` for API keys; agent user without sudo; Tailscale only | Proposed (vendor Native) |
| Simplicity | Zero new services. Files in Git plus vendor features | — |

---

## 3. Approval model (replaces the earlier "approval relay" idea)

The brief rules out a custom approval API. The approval policy is therefore enforced at four native layers, chosen so that **no agent, and no agent delegating to another agent, can perform an approval-gated action without you**:

| Gated action (brief §8) | Enforcement layer | How you approve from iPhone | Label |
|---|---|---|---|
| Merge to protected branch | GitHub branch protection: required review from CODEOWNER (you), required status checks, no admin bypass for bots | GitHub app: review → Approve → merge | Native |
| Production deployment | GitHub Actions deploy job bound to Environment `production` with you as required reviewer; prod credentials exist only as Environment secrets | GitHub app: Deployments → Approve | Native |
| Destructive DB migration | Migrations run only in the deploy job above; dev DBs are disposable | Same as deployment | Native |
| Deleting significant files/data | Claude: `PreToolUse` deny rule set + ECC destructive-command hook; Codex: Cloudroom Command Guard + workspace-write sandbox; OpenCode: `permission` config; Pi: extension guard. Git itself makes repo deletions reversible before merge | Claude app prompt (Claude); otherwise blocked and reported in PR | Native + Proposed hooks |
| Purchasing / raising paid limits | No billing credentials available to agents; registry marks `cost: paid` providers as disabled until approved | N/A: structurally impossible | Proposed |
| Exposing private info to new providers | Provider disabled in registry until approved; no key in 1Password agent vault | N/A | Proposed |
| Changing credentials / security policy | 1Password agent vault is read-only; branch protection on this repo's `policy/` via CODEOWNERS | GitHub app review | Native |
| Granting new permissions | GitHub App / PAT scopes managed by you only | — | Native |
| Sending external communications | No messaging credentials in agent vaults; Hermes gateway restricted to you as the only allowed chat user | Hermes native approval in chat if enabled | Native |
| Irreversible / high-impact decisions | Decision record in `docs/decisions/` with status `awaiting-approval`; executed only after you mark it approved in the PR | GitHub app | Proposed |

Delegation cannot bypass these because the gates are outside every agent: GitHub, GitHub Environments, 1Password scoping, and the OS user. Harness-side hooks are defence in depth and reporting, not the boundary.

What this model does **not** give you: a single phone prompt for every shell command a Codex, OpenCode or Pi thread runs on a Linux host. Those harnesses run without prompts under Cloudroom. The mitigation is scope: they work on branches, inside disposable workspaces, with no production credentials, and nothing they do lands anywhere without a PR you approve. If after Phase 4 you still want per-command phone approval for those three, the options are Hermes acting as their chat-gated front door, or re-opening the relay idea with your explicit approval.

---

## 4. Agent roles, routing, and isolation

### 4.1 Roles (from the brief, with the mechanism that realises each)

| Role | Agent | Runs where | Mechanism | Fallback if provider is down |
|---|---|---|---|---|
| Lead architect, planning, orchestration, complex implementation | Claude Code | Cloudroom thread (Local or Cloud) or Anthropic cloud session | Reads `AGENTS.md` + `CLAUDE.md`; delegates via Cloudroom child threads (`room-cli thread spawn`) or Claude subagents | OpenCode with an Anthropic or other model |
| Independent review, debugging, tests, alternative implementation | Codex | Cloudroom thread, separate branch | Review checklist skill; posts findings as PR review comments via `gh` | OpenCode with an OpenAI model, or Claude in a fresh context |
| Flexible development, model experiments | OpenCode | Cloudroom thread (ACP adapter) | `opencode.json` per project; `AGENTS.md` native | Claude or Codex |
| Persistent assistance, summaries, memory, scheduled maintenance | Hermes | Standalone service on the host (no Cloudroom adapter documented) | Hermes cron + memory; Telegram gateway restricted to you; summarises `docs/progress.md` and PR state | Claude scheduled task (Anthropic cloud) |
| Lightweight custom agents, extensions | Pi | Cloudroom thread (rpc adapter) or CLI | TypeScript extensions in repo `harness/pi/extensions/` | Claude subagent |
| Decision support | Jev / future | Registry adapters, disabled until approved | Section 7 | Available LLM agents as independent recommenders |

### 4.2 Standard workflow (brief §5) as it runs on this stack

| Stage | Owner | Concrete action | Bound |
|---|---|---|---|
| 1 Intake | Claude | Creates `docs/decisions/NNNN-<feature>.md` from template with requirements, assumptions, acceptance criteria | 1 turn |
| 2 Planning | Claude (+ Codex or OpenCode for consequential choices) | Plan appended to the decision record; independent analysis requested as a child thread with a fixed prompt | max 2 recommenders |
| 3 Implementation | Assigned agents | One branch or worktree per task; Cloud threads get their own sandbox and branch natively; Local threads use `git worktree add ../<repo>-<task>` | concurrency ≤ 3 threads per project (policy) |
| 4 Verification | GitHub Actions + Codex | CI: tests, lint, typecheck, AgentShield; Codex review on PRs labelled `needs-review` | CI timeout per repo |
| 5 Approval | You | GitHub review / Environment approval per section 3 | — |
| 6 Integration | You merge; Claude | Squash merge; decision record status → `accepted`; `docs/progress.md` updated | — |
| 7 Reporting | Claude or Hermes | PR description summary + `docs/progress.md` entry: done, verification, risks, next | — |

Loop control: no agent re-invokes another agent on its own output more than twice; retries capped at 2 per task; a thread that exceeds its budget stops and writes a blocker to `docs/progress.md` instead of continuing. Enforced by convention in `AGENTS.md` and by the harness limits that exist (Claude `--max-turns` for scripted runs, `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, Cloudroom's one-turn-at-a-time queue and 30-minute idle sleep). Cost visibility: Claude `/cost`, Codex and OpenCode session usage output, Cloudroom dashboard; aggregated weekly by Hermes into `docs/progress.md` (Proposed).

---

## 5. ECC integration plan

Decision rule: **one route only.** The audit kit reports which route exists. Then:

| Situation found | Action |
|---|---|
| Plugin installed and no manual copies | Keep plugin; switch to a minimal/standard hook profile; prune enabled skills |
| Manual copy (skills/agents/commands under `~/.claude/`) and no plugin | Record inventory, uninstall via `ecc-universal uninstall --dry-run` first, then install plugin minimal |
| Both | Stop. Report duplicates. Remove the manual copy after you approve (duplicate hooks execute twice) |
| Nothing | Install plugin minimal profile in Phase 2 |

Keep (Claude plugin): planning/architecture skills, `tdd-workflow`, `code-review`, debugging/root-cause, `security-review`, documentation, refactoring, verification-before-completion, destructive-command and secrets hooks. Skip: 97 command shims, continuous-learning daemon, commercial hooks, MCP bundle.

Share with Codex and OpenCode through this repo, not through ECC's per-harness installers: `AGENTS.md`, `.agents/skills/` (Markdown subset of the kept skills), `.agents/policies/`. Codex reads `AGENTS.md` natively. OpenCode reads `AGENTS.md` natively; its `ecc-universal` plugin (hooks only) is optional. Claude-specific items stay in `.claude/` and the plugin.

---

## 6. Repository conventions (brief §9, adapted)

```
<project>/
├── AGENTS.md            portable: roles, workflow, conventions, approval policy summary (all harnesses)
├── CLAUDE.md            Claude-only additions; imports AGENTS.md
├── README.md
├── docs/
│   ├── architecture.md
│   ├── decisions/       ADR + decision-support records (template in this repo)
│   ├── progress.md      current tasks, blockers, approvals outstanding, next actions
│   └── workflows.md     routing table and stage checklist
├── .agents/
│   ├── skills/          Markdown skills shared across harnesses
│   └── policies/        approval-policy.yaml, budgets.yaml (human-readable; enforced by GitHub + hooks)
├── .claude/settings.json     Claude permissions, hooks, plugin enablement (project scope)
├── .opencode/ or opencode.json
├── .codex/ (if needed)       Codex project config
├── .github/
│   ├── CODEOWNERS, pull_request_template.md
│   └── workflows/ci.yml, deploy.yml (Environment: production)
└── tests/
```

This repository (`ai-developement-system`) holds the templates, the provider registry, the audit kit, and the operations guide. Each application repo gets the structure above via a documented bootstrap checklist (Phase 2).

---

## 7. Decision-support architecture (interfaces first, no new providers)

**Provider registry** (`registry/providers.yaml`, Proposed; schema in Appendix A) with one entry per agent or model: name, provider, endpoint/runtime, auth method (always a 1Password reference, never a value), capabilities, tool-use, structured output, context limit, cost class, privacy constraints, health check, approved use cases, `enabled: false` by default for anything unverified or paid.

**Decision-support workflow** (`docs/decisions/TEMPLATE-decision-support.md`, Proposed): define decision and criteria → select enabled providers by capability → request independent recommendations with identical prompts and no shared context → capture evidence, assumptions, uncertainty → compare against explicit criteria → list disagreements → recommendation with rationale → status `awaiting-approval` until you approve in the PR. Consensus is recorded as consensus, never as proof.

Initial providers for testing (all already yours): Claude Code, Codex, OpenCode (whatever model you select). Jev: entry present, `enabled: false`, adapter stub only, until you hold a key and approve the cost. Ting Cactus: no entry until identified.

---

## 8. Unverified providers

| Name | Verification result | Needed from you |
|---|---|---|
| **JEV** | Identified with high confidence as **Jev by TypeSafe AI**: hosted "System One" typed-decision model, `POST https://api.typesafe.ai/v1/systemone`, bearer `TYPESAFE_API_KEY`, SDKs `typesafe-sdk` (Python) and `@typesafe-ai/sdk` (Node 20+), primitives Choice / Score / Noul, text-only, early access, $0.042 per M input tokens | Confirm; tell me whether you hold a key |
| **Ting Cactus** | **Not identified.** Two searches returned no model, product or paper by that name. Nearest candidates: Cactus Compute (YC; on-device inference engine and the 26M–121M "Needle" tool-calling model, MIT); unrelated "Cactus" products in real estate and retail; Hugging Face users named Ting | Confirm the exact name, vendor and a URL |
| Laya AI (from your first message) | Identified (open-source ModernBERT-based decision model). Dropped from scope per the brief unless you say otherwise | — |

---

## 9. Phased plan with complexity, cost and risk

| Phase | Work | Complexity | Incremental cost | Main risk |
|---|---|---|---|---|
| **1 Audit** (now) | Audit kit run on your machines; confirm Cloudroom mode, Codex auth, ECC route; this proposal and matrix | Low | None | Audit output incomplete → topology undecided |
| **2 Core foundation** | `AGENTS.md`, `CLAUDE.md`, templates, policies, registry schema in this repo; ECC single-route cleanup; branch protection + CODEOWNERS + CI skeleton on one target repo; validate Claude and Codex threads in Cloudroom end to end | Medium | None (existing subscriptions) | ECC duplicate removal touches your global `~/.claude`; done only after approval of the inventory |
| **3 Multi-agent workflow** | OpenCode login and adapter check; delegation via child threads; worktree isolation; Codex review loop on a real PR; merge | Medium | OpenCode model costs only if you choose paid models | Cloudroom adapters are alpha; fallback is running CLIs directly in worktrees |
| **4 Mobile operations** | Test and document: Claude app prompts (cloud + Remote Control), GitHub app reviews and Environment approvals, Cloudroom hosted mobile web app (if invited) or Tailscale access to the GUI/dashboard, Hermes Telegram summaries; write the guide with Tested/Unsupported labels | Low–Medium | Tailscale free tier; none otherwise | Cloudroom mobile approval claims may not hold; documented as Unsupported if so |
| **5 Decision engine** | Registry populated, adapter interface, decision template exercised with Claude + Codex + OpenCode on one real decision | Medium | None | Scope creep; kept to files and prompts |
| **6 Reliability test** | One real feature through all seven stages, with a forced failure (CI red, provider outage) and recovery | Medium | Normal usage | — |

Optional, only if you choose always-on cloud execution without a hosted invite: self-hosted Cloudroom Core on an Ubuntu 24.04 VM (about $10–40/month VPS, or $0 on a home machine), Tailscale, 1Password service account (requires Teams or Business). Complexity Medium. Approval required before any spend.

---

## 10. Definition-of-done mapping

| Done criterion (brief §13) | Phase | How it will be shown |
|---|---|---|
| Claude leads a development task | 2, 6 | Decision record + PR authored from a Cloudroom thread |
| Codex independently reviews | 2, 6 | Codex review comments on the PR, from its own thread and login |
| OpenCode executes a separate task | 3 | Second PR from an OpenCode thread |
| Hermes and Pi have tested roles | 3, 4 | Hermes daily summary into `docs/progress.md`; one Pi extension in use |
| ECC without conflicts | 2 | Audit kit shows one route; hooks fire once |
| Portable configurations | 2 | `AGENTS.md` consumed by Claude, Codex, OpenCode |
| Safe parallel work | 3 | Two threads, two branches, both merged without conflict |
| iPhone monitoring | 4 | Screenshots/notes per channel in the mobile guide |
| Remote questions and approvals | 4 | A Claude prompt answered and a PR approved from the phone |
| No bypass of approvals | 2, 6 | Attempted merge/deploy by an agent is blocked by GitHub; recorded |
| New model via documented adapter | 5 | Adding a registry entry + adapter stub in one PR |
| End-to-end demonstration | 6 | Written validation report |

---

## Appendix A: provider registry schema (proposed)

```yaml
# registry/providers.yaml
providers:
  - id: claude-code
    name: Claude Code
    provider: Anthropic
    kind: coding-agent            # coding-agent | llm | decision-model | tool
    runtime: cli                  # cli | http | local
    endpoint: null                # for http providers
    auth: { method: oauth-subscription, secret_ref: null }   # or op://vault/item/field
    capabilities: [plan, implement, review, orchestrate, research]
    tool_use: true
    structured_output: true
    context_tokens: 200000
    cost: { class: subscription, notes: "Claude plan" }      # subscription | free | paid-per-token
    privacy: { data_leaves_host: true, provider_retention: "per Anthropic terms" }
    health: { check: "claude auth status", last_ok: null }
    use_cases: [lead, complex-implementation, planning]
    enabled: true
  - id: jev
    name: Jev
    provider: TypeSafe AI
    kind: decision-model
    runtime: http
    endpoint: https://api.typesafe.ai/v1/systemone
    auth: { method: bearer, secret_ref: "op://agents-dev/typesafe/api_key" }
    capabilities: [typed-choice, score, yes-no]
    tool_use: false
    structured_output: true
    context_tokens: null          # verify
    cost: { class: paid-per-token, notes: "$0.042/M input, output free (reported)" }
    privacy: { data_leaves_host: true, provider_retention: "unknown" }
    health: { check: null, last_ok: null }
    use_cases: [risk-scoring, routing, criteria-scoring]
    enabled: false                # until key + approval
```

Adapter contract (one file per provider under `registry/adapters/`): `recommend(decision, criteria, evidence) -> {recommendation, confidence, assumptions[], evidence_used[], uncertainties[]}` for decision support; `decide(state, typed_questions) -> answers[]` for decision models. Both must be callable without side effects and must refuse to run when `enabled: false`.
