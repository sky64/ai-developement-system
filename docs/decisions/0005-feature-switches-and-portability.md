# 0005: Feature switches and a per-repo config so the harness is modular and portable

Date: 2026-11-17. Status: accepted by the owner in the Orca chat of 2026-11-17 after a builder check. Implemented together with [0004](0004-model-ladder.md) on the same branch; implemented by [the feature-switches plan](../superpowers/plans/2026-11-17-feature-switches.md).

## Intent

The owner's standing rule, stated 2026-11-17: build everything modular, every feature switchable on and off, and with universal adaptation in mind so that anyone could take the harness and use it on their setup. The first audience is a setup like the owner's: Orca with Claude and Codex, optionally DeepSeek and Solvela. The second audience, people without Orca or without those vendors, is designed for but not built for in this round.

## Goals

- Every feature of the plugin has a switch with a safe default. A fresh install with no edits behaves sensibly.
- Every install-specific value (gateway, bot identity, secret manager, which hosts run which agents, model ids) lives in one per-repo config file, never in policy text, skills or scripts.
- One file tells a stranger what is on and how this install is wired.
- Platform- and vendor-specific operations sit behind named seams: one place each to swap, so a non-Orca adapter is an addition, not a rewrite.

## Non-goals (later rounds)

- A non-Orca implementation of the workspace and worker seam.
- The build map Orca plugin (its own decision record, next).
- The adoption audit for half-built repos (its own decision record, after the build map).
- Splitting the plugin into several plugins. Revisit if the feature count doubles.

## Anti-goals

- A switch that changes behaviour silently: every switch is readable in one file and echoed by the orchestrator at session start.
- Defaults that require the owner's accounts: a fresh install must not expect Solvela, 1Password, DeepSeek or a bot named after the owner.
- Config sprawl: one file, one schema version, no second place to look.
- Breaking today's install: the owner's repos keep working with a config that harness-enable writes for them.

## Constraints

- Claude Code plugins have no native per-feature switch; the plugin is on or off. Switches therefore live in a file the plugin's hook and skills read.
- The guard hook runs as a Python PreToolUse hook with `CLAUDE_PROJECT_DIR` set; it already honours `ORCHESTRATOR_GUARD=off`. Any config read in the hook must fail closed (unreadable config means guard on).
- Skills are prose. "Read the config" is an instruction to the orchestrator, verified by the check script pinning the instruction, not by a runtime test.
- Codex workers read none of this; their behaviour comes from the brief the orchestrator writes.
- All changes are risky tier under docs/05 (policy, hooks, AGENTS.md).

## Approaches considered

1. **One config file per repo** (chosen). `.claude/ai-dev-system.json`, written with defaults by harness-enable, read by the hook and the orchestrator skill, overridable by environment variables. One install, one file.
2. **Several plugins in the marketplace** (core, ladder, build map). Native enable and disable, but docs/05 splits along feature lines, cross-references go brittle, and versions move together.
3. **Both.** More moving parts than five features justify.

## Decision

### 1. The config file

Path: `.claude/ai-dev-system.json` in the application repo, committed. Schema version 1:

```json
{
  "version": 1,
  "features": {
    "orchestrator_guard": true,
    "model_ladder": true,
    "bot_identity": false,
    "metering": "none",
    "build_map": false
  },
  "platform": {
    "kind": "orca",
    "hosts": {
      "<orca environment name or local>": {
        "deepseek_agent": "dsh-tui",
        "dsh_profiles": { "0": "<cheapest profile name>", "1": "<standard profile name>" }
      }
    }
  },
  "gateway": {
    "kind": "none",
    "base_url": "",
    "team_key_env": { "implementer": "", "reviewer": "", "research": "" }
  },
  "models": {
    "research": ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"],
    "claude_implementer": ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"],
    "codex_reviewer": { "model": "gpt-6.1-sol", "effort": ["low", "medium", "high"] }
  }
}
```

- `features` are the switches. `metering` is `none`, `solvela`, or `openai-compatible`; the other four are booleans. `build_map` is reserved for the Orca plugin of the next round and does nothing yet.
- `platform.kind` is `orca` and is the seam for the second audience: the orchestrator skill lists the five operations it needs from a platform (create an isolated workspace, start an agent with a brief and a model, wait for completion, read its result, hand a diff to a reviewer) and names the Orca command for each. Another platform is another table in the same section.
- `platform.hosts` replaces the ladder's hard-coded DeepSeek host rule: the DeepSeek row applies on a host that has an entry here. It is a self-check ("does the host I am dispatching on have DeepSeek"), not a routing table; sending work to another host for its agents is a later feature. docs/12 stays the owner's verification log and is marked as such.
- `gateway` replaces every mention of Solvela in policy. The Solvela alias column and the `x-solvela-session` header apply only when `kind` is `solvela`; `openai-compatible` takes a base URL and sends no vendor headers; `none` means direct calls and token counts from worker reports only. In this round nothing executable consumes `base_url` or `team_key_env`: the orchestrator reports them in its status line and names them in briefs, and wiring a worker's client to the gateway remains a docs/12 verification row.
- **The bot identity is a property of the machine and its user, not of a repo**, so it does not live in this file. `install-bot-identity.sh` writes `aidev.bot.name` and `aidev.bot.tokenCommand` into the user's git config (next to the `includeIf` it already installs), taking them as flags; the bot scripts read those keys with `git config --get` and refuse with a clear message when they are absent. The repo config's `features.bot_identity` says only whether this repo's pushes and merges are done by the bot. This keeps a shell command out of any file a worker can edit, and the owner's migration is one re-run of `install-bot-identity.sh` with their values.
- `models` holds the ladder cells, indexed by rung. The plugin ships the canonical defaults in `config/ai-dev-system.defaults.json`; harness-enable copies that file, the check script pins its ids, and docs/05's table refers to it. A repo may override ids per rung, but the orchestrator compares its config against the defaults at session start and reports every deviation in its status line. The decision-record rule from 0004 governs the defaults file; a repo's override is a reported local choice, not a change to the ladder.
- The plugin also ships `config/examples/orca-solvela.json`, the owner's own wiring with names only (gateway `solvela`, `api.solvela.ai`, the three team-key environment variable names, DeepSeek on the home-office host). It is the worked example for the second audience and the file the owner passes to `harness-enable --config`.
- Environment overrides: `AI_DEV_SYSTEM_FEATURE_<NAME>=on|off` for each boolean switch, read before the file. `ORCHESTRATOR_GUARD=off` stays as the alias for `AI_DEV_SYSTEM_FEATURE_ORCHESTRATOR_GUARD=off`.
- **Which copy is trusted.** In a worktree, the hook and the orchestrator read the config from the main checkout (`git rev-parse --git-common-dir`, then its parent), never from the worktree's branch. A worker can edit its branch's copy, but that copy governs nothing until it is merged through review. The config file joins the risky-tier list in docs/05 beside `.claude/settings.json` and the hooks.

### 2. Who reads it

- **The guard hook** reads `features.orchestrator_guard`. Missing file, unreadable file or `version` not 1 means guard on. Off means allow and print one line saying the guard is off by config.
- **The orchestrator skill** reads the file once at session start and states, in its first message, which features are on and what the gateway, platform and bot are. With `model_ladder` off it dispatches without `Rung:` and `Model:` lines and without `--model`, and the ladder sections of docs/05 are inert. With `metering` off it skips the attribution bullets. With `bot_identity` off it does not push or merge and reports that a human must.
- **harness-enable** moves into the plugin as `tools/harness-enable.sh`, run by path from a human or unharnessed session (the guard would deny its writes from an orchestrator session, and the plugin is enabled per project so a plugin skill could not run before the repo is harnessed). The user-level skill at `~/.claude/skills/harness-enable` becomes a thin wrapper that calls the plugin's script. It copies `config/ai-dev-system.defaults.json` to `.claude/ai-dev-system.json` when absent, prints the path, never overwrites an existing one, and takes `--config <path>` to copy a prepared file in.
- **The bot scripts** read `aidev.bot.name` and `aidev.bot.tokenCommand` from git config and the `features.bot_identity` switch from the main checkout's config, and refuse with a clear message when the switch is off or the keys are absent.
- **The check script** pins the instruction text, the schema keys and the defaults, so a later edit cannot desynchronise skill, hook and file.

### 3. Portability edits to existing text

- AGENTS.md: the bot identity paragraph names "the agent identity installed in the user's git config by `install-bot-identity.sh`, enabled per repo by `features.bot_identity`" instead of the owner's bot and vault; the owner's values move to docs/12.
- docs/05 Model ladder: the DeepSeek host sentence points at `platform.hosts`; the Solvela sentences become "when `gateway.kind` is `solvela`"; the table's ids are "the defaults in `models`".
- docs/05 Ladder review: "Solvela" becomes "the configured gateway", with Solvela named once as the owner's and as the reference implementation.
- README: one paragraph, "Using this on your own setup", that walks a stranger through harness-enable, the config file, and which features to turn on.

### 4. The ladder switch (closes the open item from 0004)

`features.model_ladder` defaults to true. When false: briefs omit `Rung:` and `Model:`, dispatch commands omit `--model` and `--effort`, read-only subagents inherit the session model, and the completion report omits rung and escalation fields. Escalation rules still apply by tier (the two-cycle allowance predates the ladder).

## Left to the builder

- Exact JSON parsing in the hook (standard library only) and the one-line message format when the guard is off by config.
- Exact wording of the orchestrator's first-message status line, including how deviations from the defaults file are listed.
- The flag names `install-bot-identity.sh` takes for the two git-config keys.

## Owner items for the implementing plan

- Per repo, at re-enable time: which switches to turn on. The example config is the owner's wiring; a repo with no gateway or bot keeps the defaults.
- One re-run of `install-bot-identity.sh` on each machine that pushes as the bot, with the bot's name and the token command, after the script change lands.

## Consequences

- One more file in every harnessed repo, and one more read at session start. In exchange every feature can be turned off without editing policy, and the owner's names leave the shared text.
- Existing repos need harness-enable re-run once to receive the file; until then the guard and the ladder behave as today because a missing file means defaults. Two things do change for the owner's repos until they are re-enabled with the example config: `metering` is `none`, so the Solvela attribution and the ladder review's meter are inert, and `bot_identity` is off, so merges wait for a human. The bot scripts keep working everywhere once `install-bot-identity.sh` has been re-run on the machine, because the identity lives in git config, not in the repo.
- The second audience gets a documented seam and a config they can fill, not a working non-Orca adapter. That is deliberate.
