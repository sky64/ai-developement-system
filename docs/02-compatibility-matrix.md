# Compatibility matrix (Phase 1 deliverable)

Date: 2026-10-19. Labels: **Y** supported and documented by vendor · **P** partial · **U** unverified or undocumented · **N** not available · **T** tested by me in this engagement. Sources: Cloudroom Core docs (`docs/harnesses.md`, `docs/setup.md`, `docs/api.md`), Cloudroom GUI README, ECC README and hooks, vendor docs via search for Hermes, Pi, OpenCode, Codex, TypeSafe. Items marked U need the audit kit output or a Phase 2–4 test.

## A. Harness × platform

| Capability | Claude Code | Codex | OpenCode | Hermes | Pi |
|---|---|---|---|---|---|
| Cloudroom Core adapter | Y (stream JSON; 2.1.280+ for Opus 5.5) | Y (default harness) | Y (ACP; v1 and v2 tested by vendor) | **U** (named in README and API enum, no adapter section) | Y (rpc mode; ≥0.85.1) |
| Cloudroom Local thread (desktop app) | Y | Y | Y (GUI provider `acp-opencode`) | U | Y |
| Runs on Linux host without Cloudroom | Y | Y | Y | Y | Y |
| Auth model on a Cloud host | Browser sign-in + one-time code, as agent user | `codex login --device-auth`, as agent user | `opencode auth login`, as agent user | Provider key or Nous Portal | Provider keys via `room-cli cloud pi key` or Mac sync |
| Uses your existing subscription | Y (Claude plan) | Y (ChatGPT plan) | P (free `opencode/*` models; else BYO keys) | N (needs a model provider; may be paid) | N (BYO keys) |
| Cloudroom Command Guard | Y | Y | N (not advertised over ACP) | U | Y |
| Pre-action hooks (own system) | Y (PreToolUse etc.) | P (hooks exist; no Claude parity) | P (`permission` config; plugins) | P (approvals system; container backends bypass) | P (TypeScript extensions) |
| Reads `AGENTS.md` | P (via `CLAUDE.md` import) | Y | Y | U | U (extension or system prompt) |
| Skills (Markdown) | Y (SKILL.md; Cloudroom loads selected skills) | P | P (ECC catalog subset) | P (Hermes skills) | P (extensions) |
| Subagents / delegation | Y (subagents; Cloudroom child threads via in-process MCP) | P (Cloudroom child threads) | N (not advertised over ACP) | U | U |
| MCP | Y | Y | Y | U | P (via extension) |
| Structured output | Y | Y | Y | U | U |
| Session resume after Core restart | Y | Y | Y (ACP `session/load`) | U | U |
| ECC support (per ECC README) | Stable, primary | Native plugin, no hook parity | Beta plugin, catalog subset | Experimental | Adapter mentioned, status unverified |

## B. Mobile (iPhone) × harness

| Need | Claude Code | Codex | OpenCode | Hermes | Pi | Cloudroom (platform) | GitHub |
|---|---|---|---|---|---|---|---|
| View running sessions | **Y, T** (Claude app, cloud sessions and Remote Control) | P (ChatGPT app, macOS desktop sessions only) | N | P (chat gateway) | N | Hosted: mobile web app (reported, **U**); self-hosted: dashboard JSON only | N/A |
| Read progress summaries | Y, T | P | N | Y (chat) | N | U | Y (PR descriptions, `docs/progress.md`) |
| Answer agent questions | **Y, T** | P (macOS only) | N | Y (chat) | N (dialogs cancelled under Cloudroom) | U | Y (PR comments) |
| Approve / reject a proposed action | **Y** (permission prompts in app; iOS rendering bugs reported Feb–Apr 2026, closed) | P (macOS only) | N | Y (once/session/always/deny in chat; 60 s default timeout) | N | U (changelog: approvals for agent/automation-initiated turns; Terms say no prompts) | **Y** (PR review, Environment deployment approval) |
| Push notifications | Y (Claude app) | P | N | Y (Telegram etc.) | N | U | Y (GitHub app) |
| Review tests and builds | N | N | N | P (summaries) | N | N | **Y** (Actions, checks) |
| Send follow-up instructions | Y, T | P | N | Y | N | U | Y (PR comment, if an agent watches the PR) |

Conclusion: the dependable mobile plane today is **Claude app + GitHub app**, with Hermes chat as an optional third channel. Cloudroom's own mobile and approval features must be tested in Phase 4 before any claim.

## C. Decision providers

| Field | Jev (TypeSafe AI) | Ting Cactus | Claude / Codex / OpenCode as recommenders |
|---|---|---|---|
| Identity verified | Y (official docs via search; site unreachable from this container) | **N: not found** | Y |
| Runtime | HTTPS API | — | Existing CLIs |
| Auth | Bearer `TYPESAFE_API_KEY` | — | Existing logins |
| Output | Typed answers + calibrated probabilities (Choice / Score / Noul) | — | Free text; structured via prompt or output schema |
| Tool use | N | — | Y |
| Context | Text only; limit unverified | — | Harness-dependent |
| Cost | Paid per token (reported $0.042/M input); early access | — | Covered by subscriptions / chosen models |
| Privacy | Data leaves host; retention unverified | — | Per provider terms |
| Status in registry | Entry, `enabled: false` | No entry | Enabled |

## D. Security controls × layer

| Control | Cloudroom Core | GitHub | 1Password | Harness hooks |
|---|---|---|---|---|
| Agent cannot gain admin | Y (separate user, no sudo, no Docker socket by guidance) | — | — | — |
| Agent cannot read platform secrets | Y (token and history unreadable by agent) | — | Y (scoped read-only service account; keys injected at start) | — |
| Private network only | Y (loopback; Tailscale `serve`) | — | — | — |
| Merge requires human | — | Y (branch protection, CODEOWNERS) | — | — |
| Deploy requires human | — | Y (Environments, required reviewers) | — | — |
| Destructive command block | P (Command Guard, regex) | — | — | P (ECC GateGuard, Claude deny rules, OpenCode permission) |
| Audit trail | Y (history, events) | Y (PR, review, deployment logs) | Y (service account activity) | P (hook logs) |
| Sandbox | **N** (explicitly not a sandbox) | — | — | Codex workspace-write sandbox (P) |

## E. Unknowns to resolve with the audit kit

1. Cloudroom mode in use (Local app / hosted Cloud / self-hosted Core) and app version (v83+ needed for "Connect your own Core").
2. `codex login status` on the machine that runs Codex threads.
3. ECC route and duplicates in `~/.claude`, `~/.codex`, `opencode.json`.
4. Hermes config: `approvals.mode`, gateway platforms, backend (local vs container).
5. Pi providers present and extensions directory.
6. GitHub auth identity and scopes used by agents (`gh auth status`).
7. 1Password CLI presence and plan tier (service accounts need Teams/Business).
