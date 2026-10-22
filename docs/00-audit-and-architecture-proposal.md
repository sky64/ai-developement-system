# Multi-agent development environment on Cloudroom: audit and architecture proposal

Status: **HISTORICAL AUDIT; NOT THE CURRENT ARCHITECTURE.** The complete architecture and capability interpretation in this file are superseded by the [revised proposal](01-architecture-proposal.md) and [capability matrix](02-compatibility-matrix.md), updated 2026-10-19. Preserve this file as a record of the original session; its environment, vendor claims, estimates, and questions are not current verification or an implementation checklist. The approval relay was withdrawn, and the five-harness rollout is deferred. No installation or credential changes are authorized by this historical document.
Date: 2026-10-19. Author: Claude (lead architect role), for kd@sky64.io.

This document has three parts:

1. **Audit** of the current setup as it can be observed from this session.
2. **Capability verification**, with emphasis on iPhone approvals and security. Each claim is marked *verified* (observed directly), *documented* (read in a primary source), or *reported* (secondary source only).
3. **Proposed architecture and phased plan**, followed by the questions I need answered in the implementation brief.

---

## 1. Audit of the current setup

### 1.1 This repository (`sky64/ai-developement-system`)

| Item | Finding |
|---|---|
| Contents | `README.md` (one line) and `.gitignore` (ignores `.env*`, `node_modules/`, `.DS_Store`). One commit. |
| Agent config | No `CLAUDE.md`, `AGENTS.md`, `.claude/`, `.codex/`, `opencode.json`, `.pi/`, or ECC artifacts. |
| CI / policy | None. No branch protection visible from here. |

Conclusion: this repo is a clean slate. I propose it becomes the infrastructure-as-code home for the environment (section 3.6).

### 1.2 The Claude Code cloud session you are using right now

| Item | Finding |
|---|---|
| Session origin | `ios` (*verified*). You started this session from the Claude iPhone app, and it is running in Anthropic's cloud environment "Default". This alone proves the Claude iOS app can start, monitor, and converse with a running Claude Code session. |
| Permission mode | `auto` (*verified*). File edits run without asking; most tool calls run without asking; destructive or outward-facing actions still prompt. Bypass mode is not offered in cloud sessions. |
| Second environment | A **bridge environment** for this repository was created today at 19:54 UTC (*verified*). This is a Remote Control bridge to the owner's workstation. Omarchy is DHH's Arch Linux + Hyprland desktop, so your workstation is Arch-based Linux, not macOS. This matters for Cloudroom (section 2.1). |
| Network egress | Blocked for `cloudroom.dev`, `typesafe.ai`, `laya-ai.com`, `1password.com`, `api.openai.com` (*verified*, proxy `connect_rejected`). GitHub is reachable. Implementation work that talks to those vendors must run on the Omarchy machine or the Cloudroom host, not in this cloud container. |
| Installed CLIs here | `claude` 2.1.303, `gh`, `node` 22, `bun`, `python3` 3.13, `docker` 29. Not present: `codex`, `opencode`, `hermes`, `pi`, `op` (1Password CLI). This container is ephemeral, so this list only matters as a baseline. |
| Secrets in this container | Session-scoped tokens injected by the harness (GitHub, AWS, Google Cloud). No 1Password material. Nothing of yours is stored here. |

### 1.3 Your claude.ai organization (connectors and plugins)

| Item | Finding |
|---|---|
| Connected connectors | Microsoft 365 (connected, enabled), Zoho Books (connected, enabled). Alpha Vantage, BlackRock Advisor Center, Keel, Whimsical are installed but not completed. |
| Plugins synced | `small-business`, `productivity`, `bigdata-com`, `desktop-commander`, `cowork-plugin-management`, `zocks-advisor`. Roughly 40 of their MCP servers failed to connect in this session (proxy 403). |
| Assessment | These are business and finance tools, not development tools. Loading them into coding sessions costs context and widens the blast radius of a confused agent. Recommendation: a dedicated development project or environment where only GitHub and development connectors are enabled. |

### 1.4 GitHub footprint (names only, not read)

33 repositories across `sky64`, `solvela-ai`, and `Telsi-ai`. Relevant signals of prior tooling:

- `solvela-ai/agentshield` (fork): AgentShield is ECC's security scanner. Confirms prior ECC use.
- `solvela-ai/openclaw` (fork) and `sky64/rustyclaw`: OpenClaw is a harness Cloudroom supports (adapter documented). Deferred, but it is an option later.
- `sky64/setup-verification`, `sky64/knowledge`, `sky64/terminal-command`: likely prior environment-setup work worth mining for conventions once the brief confirms.

Only this repository is in scope for this session, so I did not open the others.

### 1.5 Everything Claude Code (ECC), what you used before

Read from the primary repo (now `affaan-m/ECC`, old URL redirects). Version 2.2.3, MIT, 284k stars, active (last commits Oct 15, 2026).

| Component | Count | Portability |
|---|---|---|
| Agents | 71 | Markdown with frontmatter, reusable |
| Skills | 311 | Markdown, reusable (the "primary workflow surface") |
| Commands | 97 | Claude-specific shims |
| Hooks | ~27 entries (PreToolUse, Stop, SessionStart, ...) | Claude hook contract; Codex has partial parity; OpenCode gets hooks via `ecc-universal` plugin; Hermes and Pi experimental |
| Rules | common + language packs | Markdown, reusable |
| MCP configs | 14 | Not auto-enabled by the plugin |

Harness support matrix per ECC's own README: Claude Code stable, Codex native plugin (no hook parity), OpenCode beta plugin (catalog subset), Hermes experimental, Pi adapter mentioned but not in the matrix.

Caveats that shape my recommendation: the plugin advertises the whole catalog to the model (context cost), rules are always-loaded, SessionStart injects up to 8,000 chars, stacking install methods causes duplicate hook execution, and hooks run arbitrary Node with user privileges. ECC's security hooks are regex "accident prevention", not a sandbox. **Recommendation: adopt ECC selectively (section 3.5), do not reinstall the full profile.**

---

## 2. Capability verification

### 2.1 Cloudroom

Primary sources: `davidondrej/cloudroom-core` README, `docs/harnesses.md`, `docs/setup.md`, `docs/api.md`, `docs/session-lifecycle.md`, `docs/dashboard.md`, and `davidondrej/cloudroom-gui` README. The website `cloudroom.dev` did not resolve from this environment; changelog and security-page facts below are *reported* via search snippets.

**What it is** (*documented*): an Apache-2.0, self-hostable **Rust runtime ("Core")** that runs coding-agent CLIs on a Linux machine, records their history, and exposes an HTTP API on `127.0.0.1:9840` (bearer token, SSE streams). A separate **desktop app (GUI)** for Apple Silicon macOS 13+ (Linux x64 "alpha" on Releases) connects to a Core by URL + token. **Hosted Cloudroom is invite-only.** Core is labelled "developer alpha" / "pre-release software". Repo stats: ~907 stars, 50 commits.

**Harness support** (*documented* in `docs/harnesses.md`):

| Agent | Status in Cloudroom | Auth model |
|---|---|---|
| Claude Code | Adapter exists (stream JSON, needs 2.1.280+ for Opus 5.5) | Browser sign-in with one-time code; tokens live on the VM in the agent account. "Do not copy Mac credentials." |
| Codex | Adapter exists, **default harness** | `codex login --device-auth` as the agent account |
| Pi | Adapter exists (`--mode rpc`, needs pi-coding-agent 0.85.1+) | Provider keys via `room-cli cloud pi key` or Mac sync of `~/.pi/agent/auth.json` |
| OpenCode | Adapter exists (ACP; OpenCode 1 and 2 tested) | `opencode auth login` as the agent account. Core disables OpenCode's question tool over ACP. |
| Hermes | Named in README and API enum; **no adapter section in harnesses.md** | Undocumented |
| Cursor, Devin, OpenClaw | Preview / enum / adapter | Not in scope |

**Multi-agent features** (*documented*): parallel sessions with no fixed limit; child threads (`room-cli thread spawn|tell|output`) in the parent's folder or `--shared-sandbox`; parent is notified on each child turn end; "Teleport" moves a running local thread to the cloud and back; durable prompt queue, one turn at a time per session; idle sessions sleep after 30 min. No outbound webhooks; the HTTP API is the orchestration surface.

**Security model** (*documented*): agents run as a separate Linux user (`cloudroom-agent`) with no sudo; agents cannot read the Core token or history; API is loopback-only unless fronted by HTTPS; recommended remote access is **Tailscale `serve`** (never `funnel`); "Command Guard" is regex-based accident prevention, **not a sandbox**; guidance is a **fresh VM for one trusted user**, no Docker socket for the agent account. Install guide targets **Ubuntu 24.04** only; "containers and other Linux distributions are outside this guide."

**Approvals and mobile** (the key question):

- Core: **"Agents run without approval prompts"** (*documented*, README, setup.md, and Terms of Service dated Oct 10, 2026).
- GUI: "Mac access: Off, Read-only, Ask first, Full" (*documented*). This governs cloud agents reaching your Mac, not general tool approvals.
- Changelog (*reported*, ~2 days old): "Turns started by agents or automations now ask you for approvals instead of silently denying them", automations renamed "Loops", and "install the Cloudroom mobile app from your browser" (a web app, on a separate private domain per the security page, for the **hosted** product).
- Pi interactive dialogs: adapter "responds cancelled: true, never approval" (*documented*).
- Self-hosted Core has **no UI at all** beyond a JSON dashboard endpoint; no push notifications; no documented remote per-action approval.

**Verdict:** Cloudroom today does not give you per-action approvals or notifications on an iPhone. It gives you a strong, isolated, multi-harness runtime with a good API. The approval and mobile plane has to come from elsewhere (section 3.3).

**1Password:** not mentioned anywhere in Cloudroom's docs. Pi key sync explicitly notes "the VM cannot run Mac secret managers". On a Linux VM, the 1Password CLI with a service account works independently of that limitation.

### 2.2 Mobile approvals per agent

| Agent | iPhone monitoring | iPhone approvals | Evidence |
|---|---|---|---|
| Claude Code | Yes: Claude iOS app, cloud sessions and Remote Control to your own machine | Yes: permission prompts and questions answered in the app; push notifications; `claude remote-control` devices appear as cards | *verified* for cloud sessions (this session); Remote Control *documented* (Anthropic, Feb 2026), with iOS prompt-rendering bugs reported Feb–Apr 2026 and marked closed (*reported*) |
| Codex | ChatGPT iOS app (preview since May 2026) | Yes, but **only for Codex desktop sessions on macOS** | *reported* (multiple outlets). Not available for a Linux host. |
| Hermes | Telegram / Discord / Slack gateway | Yes: dangerous-command approval sent to chat with once / session / always / deny; 60 s default timeout; container backends bypass approvals; `/yolo` disables | *documented* (Hermes security docs) |
| Pi | None native | None; Cloudroom cancels interactive dialogs | *documented* |
| OpenCode | Web/server mode exists; no mobile product | Permission config (`permission` in `opencode.json`), no remote approval UI | *reported*, schema details conflict between sources |

Conclusion: there is **no single approval plane** across your five agents, and the only ones with native phone approval are Claude (Anthropic app) and Hermes (chat gateway). Codex's phone approvals need a Mac. The architecture therefore adds a small, shared approval relay (section 3.3).

### 2.3 Credentials: 1Password

*Documented* on 1password.dev: `op run --env-file` and `op://vault/item/field` secret references resolve at process start and mask resolved values in output; service accounts can be scoped to one vault; Agentic Autofill (early access) lets an agent sign in to websites without seeing credentials. *Reported* (one blog, verify before relying on it): "Environments" for `op run --environment <id>`, and "Credential Broker" (public preview July 2026, Business plan) issuing secrets to workloads based on OIDC claims.

Design consequence: a dedicated vault ("agents-dev"), a read-only service account token held only in `/etc/cloudroom/*.env` (mode 600, owned by root/cloudroom), and every harness launched through `op run` so no raw `.env` ever exists on disk or in a repo.

### 2.4 Decision models to integrate later

**Jev (TypeSafe AI)** (*reported* from official docs via search; the site did not resolve here): a "System One" model that takes program state plus typed questions and returns typed answers with calibrated probabilities. Primitives: **Choice, Score, Noul** (yes/no). Endpoint `POST https://api.typesafe.ai/v1/systemone`, bearer `TYPESAFE_API_KEY`, SDKs `typesafe-sdk` (Python) and `@typesafe-ai/sdk` (Node 20+), default model `jev-latest`, keys at `console.typesafe.ai/keys`. Latency 70–500 ms, text-only, $0.042 per million input tokens, output free. **Early access; signups have been paused at times.** Hosted only. Beware third-party "no waitlist" key resellers.

**Laya** (*reported*; official distribution appears to be Hugging Face `convaiinnovations/laya*` and GitHub `NandhaKishorM/laya`; whether `laya-ai.com` is the official site could not be verified): Apache-2.0, non-autoregressive encoder (ModernBERT-large, 421M params; a 322M multilingual variant), 1024-token context, ~33 ms per question on a T4, single forward pass, typed choice / score / yes-no decisions. **Fine-tuning on your own labelled data is effectively required**: base checkpoints score below a majority baseline; the `laya-typed-decisions` checkpoint reaches ~0.77. Weak on high-cardinality classification. Fully local, so no data leaves your machine.

Both fit the same interface: `decide(state, typed_questions) -> answers + probabilities`. That is the contract the architecture exposes (section 3.4), with a deterministic rules provider first.

---

## 3. Proposed architecture

### 3.1 Principles

1. **One trusted user, one isolated host.** Cloudroom Core runs on its own Ubuntu 24.04 VM, not on your Omarchy workstation. Agents get no sudo, no Docker socket, no access to the Core token.
2. **Private network only.** Core, the approval relay, and the status page are reachable only over Tailscale (your iPhone runs the Tailscale app). No public ports.
3. **Credentials come from 1Password at process start, never from files in repos.** OAuth logins that the harnesses manage themselves (Claude, Codex, OpenCode) stay in the agent account's home as Cloudroom designs; everything that is an API key or token goes through `op run`.
4. **Humans approve consequential actions; agents never self-authorize them.** A shared policy defines risk tiers. Tier 0 runs silently, Tier 1 notifies, Tier 2 blocks until you approve from your phone, Tier 3 is denied outright. Timeout means deny.
5. **Git is the only path to production.** Agents push to branches; PRs are required; you merge. Branch protection enforces this even if an agent misbehaves.
6. **Everything is code in this repo**: host provisioning, harness configs, policy, relay, decision-provider adapters, runbooks.
7. **Decision models advise; policy decides.** Jev or Laya can lower a Tier 2 action to Tier 1 only within thresholds you set, and never for irreversible operations.

### 3.2 Topology

```
 iPhone (Tailscale app)                      Omarchy workstation (Linux)
 ├─ Claude iOS app ──────────┐               ├─ Cloudroom GUI (Linux x64 alpha) or
 ├─ Telegram app ───────┐    │               │  claude / codex / opencode / pi CLIs
 └─ Safari → status UI ─┼──┐ │               └─ claude remote-control (bridge)
                        │  │ │
 ======================= Tailscale tailnet (private) ===========================
                        │  │ │
 Ubuntu 24.04 VM "cloudroom-host"             Anthropic cloud / Claude Code
 ├─ cloudroom (Core, Rust, :9840, token)       (sessions started from the
 │   └─ cloudroom-agent user                     Claude app; already works)
 │       ├─ claude   (Claude Code)
 │       ├─ codex    (Codex, default harness)
 │       ├─ opencode (OpenCode 2, ACP)
 │       ├─ pi       (Pi, rpc mode)
 │       └─ hermes   (Hermes gateway → Telegram)
 ├─ approval-relay (small service)
 │   ├─ /hook endpoint called by harness hooks
 │   ├─ policy.yaml (risk tiers, allow/deny lists)
 │   ├─ decision providers: rules → Jev → Laya
 │   ├─ Telegram bot: prompt with Approve/Deny buttons
 │   └─ audit log (append-only JSONL)
 ├─ status page (reads Core /v1/dashboard, read-only)
 ├─ op (1Password CLI, service account, vault "agents-dev")
 └─ tailscale serve (HTTPS for :9840 and relay)
```

Why not run Core on Omarchy: Cloudroom's guide covers Ubuntu 24.04 only, wants a fresh VM for one trusted user, and agents run without prompts. Your daily workstation should not be the blast radius. Omarchy stays your control surface (GUI, CLIs, Remote Control bridge).

### 3.3 Mobile plane: monitoring, questions, approvals

Three channels, each used for what it is already good at:

| Need | Channel | Covers |
|---|---|---|
| Monitor running projects | Status page over Tailscale (reads Core's dashboard API every 5 s) plus Claude iOS app for Claude sessions | All harnesses (status), Claude (full transcript) |
| Respond to agent questions | Claude iOS app (Claude sessions); Telegram (Hermes natively; other harnesses via relay) | All |
| Approve consequential actions | **Approval relay → Telegram** with inline Approve / Deny / Allow-for-session buttons; Claude's native prompts also appear in the Claude app | All harnesses that expose a pre-action hook |

How each harness reaches the relay:

- **Claude Code**: `PreToolUse` hook (`Bash`, `Edit|Write`, `mcp__*`) posts the pending action; exit code 2 blocks on deny or timeout. Same contract ECC uses.
- **Codex**: Codex hooks (ECC ships `hooks/codex-hooks.json`; parity is partial), with approval policy set to ask for anything outside the workspace sandbox.
- **OpenCode**: a small plugin registering a permission handler (the `ecc-universal` plugin shows the mechanism).
- **Pi**: a TypeScript extension in `~/.pi/agent/extensions/` that intercepts tool calls. Pi's own dialogs are unavailable under Cloudroom, so the extension must call the relay rather than prompt locally.
- **Hermes**: keep Hermes's native Telegram approvals (`approvals.mode: manual`, never `--yolo`, local backend so approvals are not bypassed), and mirror to the relay's audit log.

Fallback when the relay is down: fail closed (deny Tier 2+). Telegram is proposed because it has first-class bot buttons, works on iPhone with push, and Hermes already speaks it. Slack is the alternative if you prefer one workspace; Teams is not supported by Hermes.

### 3.4 Decision layer (Jev and Laya ready, deferred)

A `DecisionProvider` interface in the relay:

```
decide(state: text, questions: [Choice | Score | YesNo]) -> [{answer, probability}]
```

Providers, in order of adoption:

1. **RulesProvider** (Phase 1): deterministic allow/deny/ask lists from `policy.yaml`. Always present, always last word.
2. **JevProvider** (Phase 4): hosted, `POST /v1/systemone`, key from 1Password. Used for routing ("which agent should take this task") and risk scoring of actions the rules call ambiguous.
3. **LayaProvider** (Phase 4+): local GPU or CPU inference on the host, fine-tuned on the relay's own audit log (every action plus your approve/deny is a labelled example). Useful once a few hundred decisions exist.

Guardrails: a provider can never move an action out of Tier 3, never approve a Tier 2 action with probability below a configured threshold, and every provider call is logged with the final human outcome.

### 3.5 ECC: what to keep

Keep (install as the native Claude plugin with the **minimal profile**, enable hooks explicitly, never stack with a manual copy):

- Rules `common` and the TypeScript/Python packs you use.
- A short list of skills: `tdd-workflow`, `security-review`, `search-first`, `strategic-compact`, plus any you name in the brief.
- Hooks: destructive-command gate (GateGuard-style), pre-commit secrets check, dev-server-outside-tmux block.
- **AgentShield** as a CI step (you already fork it).

Skip: the 97 command shims, continuous-learning daemon (Windows defects, extra processes), Itô and other commercial hooks, and the 14 MCP configs. Share the portable layer (`AGENTS.md`, `.agents/skills/`, rules as Markdown) across Codex, OpenCode, Pi and Hermes from this repo instead of per-harness ECC installs.

### 3.6 Repository layout (this repo)

```
docs/            audit, architecture, runbooks, decision records
infra/           VM provisioning script, systemd units, tailscale, op setup, backups
harness/         claude/ codex/ opencode/ pi/ hermes/  (settings, hooks, extensions)
policy/          policy.yaml (risk tiers), allowlists, Telegram routing
relay/           approval relay service + decision providers (rules, jev, laya)
status/          read-only dashboard page
shared/          AGENTS.md, CLAUDE.md, .agents/skills/, rules/ shared by all harnesses
.github/         CI: lint, AgentShield scan, policy validation
```

### 3.7 Security checklist to be enforced

- Separate 1Password vault, read-only service account, token only in `/etc/cloudroom/*.env` (mode 600).
- `CLOUDROOM_TOKEN` and GUI connection token stored in 1Password, never in Git or prompts.
- Tailscale only; MagicDNS + HTTPS certs; never `tailscale funnel`; `tailscale serve` for :9840 and the relay.
- Agent account: no sudo, no Docker socket, home mode 700; Core refuses to start if misconfigured.
- Per-agent GitHub identity (fine-grained PAT or GitHub App per harness) with contents + pull-request scopes only; branch protection on `main` of every target repo; required PR, no agent merges.
- Approval relay fails closed; audit log append-only and backed up with `/var/lib/cloudroom/history`.
- Harness auto-update disabled on the host; upgrades through the documented `update.py` after reading release notes.
- ECC hooks installed from the official marketplace only (the README warns about malware in re-uploads).
- Quarterly review: rotate service account token, prune allowlists, review audit log.

### 3.8 Phased plan

| Phase | Scope | Exit criteria |
|---|---|---|
| **0. Approve** | This document, answers to section 4 | Architecture approved in writing |
| **1. Foundation** | Provision Ubuntu 24.04 VM; Tailscale; 1Password service account + `op`; install Cloudroom Core (pinned release); create agent account; log in Claude Code and Codex as agent; connect GUI from Omarchy (Linux alpha) or Mac; scaffold this repo; branch protection on first target repo | A Claude thread and a Codex thread run on the host from the GUI, push a branch, open a PR |
| **2. Mobile plane** | Verify Claude iOS prompts end to end; Hermes with Telegram gateway in manual approval mode; approval relay MVP wired to Claude hooks; status page over Tailscale | You approve a Tier 2 action from the iPhone for a Claude thread and a Hermes thread, and see all threads on the status page |
| **3. Breadth** | Add OpenCode and Pi harnesses; relay adapters for Codex, OpenCode, Pi; selective ECC install; shared `AGENTS.md`/skills; AgentShield in CI | All five harnesses run under Cloudroom and route Tier 2 actions through the relay |
| **4. Decision layer** | RulesProvider hardened from audit data; JevProvider behind a feature flag once you hold a key; Laya local inference and first fine-tune when enough labels exist | Routing suggestions and risk scores appear in Telegram prompts; no provider can bypass policy |
| **5. Operate** | Backups, upgrade runbook, token rotation, alerting on relay/Core downtime, quarterly review | Runbooks tested once each |

Rough effort: Phase 1 about one working day on the host plus your logins; Phase 2 two to three days (relay MVP is the bulk); Phase 3 two days; Phase 4 depends on Jev access and GPU availability.

### 3.9 Risks and open unknowns

- **Cloudroom maturity.** Developer alpha, single maintainer, 50 commits. Pin versions, keep the agent CLIs usable without Cloudroom (they are) so Cloudroom is a convenience layer, not a dependency.
- **Hermes under Cloudroom is undocumented.** Plan B: run Hermes as its own systemd service on the same host, outside Core, with its Telegram gateway. It still lands in the relay's audit log.
- **Linux GUI is alpha; the polished GUI is macOS.** If you have a Mac, use it for the GUI. Otherwise the HTTP API and `room-cli` are fully usable from Omarchy.
- **Codex phone approvals need macOS.** The relay covers Codex instead.
- **Jev access.** Early access, signups paused at times. Everything is designed to work without it.
- **Laya source ambiguity.** Verify the publisher (Hugging Face `convaiinnovations` vs `laya-ai.com`) and read the license and code before running it.
- **Approval-prompt reliability on iOS** for Claude Remote Control had bugs earlier in 2026. Phase 2 tests this explicitly; Telegram is the redundant path.
- **This cloud environment cannot reach the vendor sites.** Implementation runs on the host and from your Omarchy bridge, with this repo as the shared artifact.

---

## 4. Questions for the implementation brief

1. **Host.** New Ubuntu 24.04 VPS (which provider and region), a home server, or something else? Any existing Tailscale tailnet?
2. **GUI.** Do you have an Apple Silicon Mac for the Cloudroom desktop app, or should I plan on the Linux x64 alpha on Omarchy plus the API/CLI?
3. **Hosted Cloudroom.** Do you have, or want, an invite? Or self-host only?
4. **Subscriptions and keys.** Claude plan (Max/Team), ChatGPT plan for Codex, model providers for Pi, Hermes, and OpenCode (OpenRouter, direct keys, local models?).
5. **1Password plan.** Individual, Families, Teams, or Business? Service accounts need Teams or Business; Credential Broker needs Business.
6. **Approval channel.** Telegram (recommended), Slack, or Discord?
7. **Risk tiers.** What counts as consequential for you? My default Tier 2 list: push to a protected branch, deploy, anything that spends money, deleting outside the workspace, sending external messages, touching production data. Tier 3 (always deny): credential exfiltration patterns, `rm -rf` of home or repo root, force-push to main.
8. **Agent roles.** My default: Claude Code as primary builder and reviewer, Codex as second implementer and independent reviewer, OpenCode for open-model and cheaper tasks, Pi for small scripted automations, Hermes as the operator/chat-facing agent and long-running loops. Adjust?
9. **First target projects.** Which repositories go under agent management first?
10. **ECC.** Which parts you valued most (skills, hooks, memory, instincts) so the selective install keeps them.
11. **Jev and Laya.** Do you already hold a TypeSafe key? Is there a GPU available for Laya (the host, Omarchy, or a separate box)?
12. **Team.** Single user, or will others need access (changes the one-user-per-host assumption)?

---

## 5. Sources

Primary (read directly):
- https://github.com/davidondrej/cloudroom-core (README, docs/harnesses.md, docs/setup.md, docs/api.md, docs/session-lifecycle.md, docs/dashboard.md)
- https://github.com/davidondrej/cloudroom-gui
- https://github.com/affaan-m/ECC (README, AGENTS.md, hooks/hooks.json, hooks/README)

Secondary (search snippets; sites did not resolve from this environment):
- https://www.cloudroom.dev/changelog , https://www.cloudroom.dev/security , https://www.cloudroom.dev/terms
- https://docs.typesafe.ai/introduction/quickstart , https://docs.typesafe.ai/concepts/system-one , https://typesafe.ai/blog/introducing-system-one-models-and-jev , https://pydantic.dev/docs/ai/models/typesafe/
- https://huggingface.co/convaiinnovations/laya-typed-decisions , https://github.com/NandhaKishorM/laya , https://laya-ai.com/ , https://www.eesel.ai/blog/laya-ai-review
- https://www.1password.dev/get-started/secure-ai-access , https://flaviocopes.com/ai-agent-passwords/
- https://hermes-agent.nousresearch.com/docs/user-guide/security/
- https://opencode.ai/v2/docs/agents/
- https://github.com/anthropics/claude-code/issues/29438 , https://claudeissues.com/issue/28427-permission-prompts-not-visible-on-ios-remote-control-client
- https://www.neowin.net/amp/openai-is-bringing-codex-to-the-chatgpt-mobile-apps-on-ios-and-android/
