# Install the development system as a Claude Code plugin

Decision 2026-10-25 (owner): application repositories stay separate from this one, and the development system is installed into any application repository without copying files. This repository is the plugin: the repository root is the plugin root.

Status: the manifests validate statically and the hook command passes a simulated invocation (see [Verification](#verification)). Loading the plugin in a live Claude Code session, and in a Cloudroom cloud thread, is untested.

## What the plugin contains

| Path | Component | Purpose |
|---|---|---|
| `.claude-plugin/plugin.json` | Manifest | Name `ai-dev-system`, version `0.1.0` |
| `.claude-plugin/marketplace.json` | Marketplace | One-plugin catalog whose plugin source is the repository root (`"./"`) |
| `hooks/hooks.json` | Hook | The PreToolUse write guard, same matcher and timeout as `.claude/settings.json`, path through `${CLAUDE_PLUGIN_ROOT}` |
| `agents/docs-engineer.md` | Agent | Role prompt for documentation and tooling work, usable in a repository that has none of this repository's files |
| `agents/specialist-agent.md.tmpl` | Template | The template from [05-delegation.md](05-delegation.md), not a runnable agent |
| `skills/orchestrator/SKILL.md` | Skill | Makes the session the orchestrator; runs as `/ai-dev-system:orchestrator` |
| `tools/hooks/orchestrator-guard.py` | Script | The guard, unchanged |

`AGENTS.md`, `docs/05-delegation.md` and the rest of the repository ship inside the plugin directory; the skill reads them through `${CLAUDE_PLUGIN_ROOT}`. `.claude/` in this repository is not part of the plugin (the plugin loads `agents/`, `skills/` and `hooks/` at the plugin root), so this repository's own `.claude/agents/docs-engineer.md` and `.claude/skills/` stay as they are.

## Enable it in an application repository

Add these lines to the application repository's `.claude/settings.json` and commit them. Keys and shapes are from the [settings reference](https://code.claude.com/docs/en/settings-reference.md) (`enabledPlugins`, `extraKnownMarketplaces`).

```json
{
  "extraKnownMarketplaces": {
    "ai-dev-system": {
      "source": { "source": "github", "repo": "sky64/ai-developement-system" }
    }
  },
  "enabledPlugins": {
    "ai-dev-system@ai-dev-system": true
  }
}
```

The key `ai-dev-system@ai-dev-system` is `<plugin>@<marketplace>`. Claude Code honors `extraKnownMarketplaces` from a repository only after the workspace trust dialog is accepted for that folder; in an untrusted folder it ignores the entry without a message.

### Why `marketplace.json` is needed

`enabledPlugins` takes `plugin-name@marketplace-name` keys, so the plugin must belong to a marketplace. A plugin whose marketplace entry points at an external source (its own GitHub repository) is not installed by a committed project setting alone; each user would see `Plugin "<name>" is enabled in project settings but isn't installed` until they run `claude plugin install ... --scope project`. A plugin listed by a relative path loads from the marketplace copy once the repository's `extraKnownMarketplaces` entry applies, with no install step. That is why this repository is also a one-plugin marketplace with `"source": "./"`. Sources: [Plugins shared through a repository](https://code.claude.com/docs/en/plugins/loading.md), [Require plugins per repository](https://code.claude.com/docs/en/plugins/org.md), [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference.md).

### Updates

`plugin.json` pins `"version": "0.1.0"`. Per the [loading reference](https://code.claude.com/docs/en/plugins/loading.md), a pinned version keeps users on that version until it changes, so bump `version` in the same change as any plugin content change that application repositories should receive.

### Local development

Documented in [Create a plugin](https://code.claude.com/docs/en/plugins/create.md), without any settings file:

```bash
claude --plugin-dir /path/to/ai-developement-system
```

The flag loads the directory for one session and writes nothing to settings. A local directory marketplace (`claude plugin marketplace add /path/to/ai-developement-system`, then `claude plugin install ai-dev-system@ai-dev-system`) loads the plugin in place, so edits apply at the next session start or `/reload-plugins`. Both are documented; neither was run here.

## Cloudroom project setup

1. Create a Cloudroom project pointed at the application repository, not this one.
2. Start the orchestrator thread in that project.
3. The orchestrator spawns children into the same project with `room-cli thread spawn --parent-self --project "$ROOM_PROJECT_ID" ...`. Flags vary by runtime (Local or Cloud threads); run `room-cli thread spawn --help` in the installed CLI. Observed 2026-10-25 from the Local orchestrator thread, a cloud child from a Local parent was started with `--parent-self --project --provider claude-code --model --reasoning-level --machine cloud --base-branch`. The provider id is `claude-code`. The permission mode is implied full on cloud and must not be passed.
4. The cloud environment needs `ORCHESTRATOR_GUARD=off`, `GH_AGENT_TOKEN`, and the Git identity setup (author `Solvela-bot`, a `github.com` credential helper that reads `GH_AGENT_TOKEN`), exactly as in [09-agent-identity.md](09-agent-identity.md) and [03-cloudroom-setup.md](03-cloudroom-setup.md). Child sandboxes are the boundary; the guard is off there.
5. Protect `main` in the application repository the way [09-agent-identity.md](09-agent-identity.md) describes for this repository (one approving review, admin enforcement, no force pushes).

Whether a Cloudroom cloud thread loads the plugin from the application repository's `.claude/settings.json` is untested. The Claude Code documentation says a Claude Code cloud session (including claude.ai/code) does not load plugins that the repository's `.claude/settings.json` turns on and does not add `extraKnownMarketplaces` from a repository ([Install a plugin](https://code.claude.com/docs/en/plugins/install.md), [Plugin loading reference](https://code.claude.com/docs/en/plugins/loading.md)). Cloudroom runs Claude Code in its own sandbox, so that statement may or may not apply. If it does, the documented alternatives are plugins distributed through managed settings, or listing the absolute path of a checkout of this repository in the `CLAUDE_CODE_PLUGIN_DIRS` environment variable (Claude Code 2.1.280 or later, cannot be set from project or local settings). Neither was tried.

## Where agents live

| Kind | Location |
|---|---|
| Application-specific agents (for example a money-path engineer) | The application repository, `.claude/agents/<name>.md` |
| Role templates and the shared docs-engineer | This plugin repository, `agents/` |

The specialist selection step in [05-delegation.md](05-delegation.md) searches the application's `.claude/` first. Plugin agents are namespaced: the docs-engineer is `ai-dev-system:docs-engineer` ([Add components](https://code.claude.com/docs/en/plugins/components.md)). Plugin agents ignore `hooks`, `mcpServers` and `permissionMode` frontmatter, so an agent that needs those belongs in the application repository.

`agents/specialist-agent.md.tmpl` is a template. The component documentation says each Markdown file under `agents/` defines an agent, and the manifest reference says `agents` entries must be `.md` files. A `.tmpl` file is not a Markdown file, so it is expected not to register. The documentation does not state an extension rule outright, and the check was not made in a live session (untested).

## Make the session an orchestrator

A plugin cannot force a session to adopt a role. Put this in the application repository's `CLAUDE.md`. Every session in the project reads that file, including child threads, so the line is scoped to the orchestrator:

```markdown
If you were started as the project orchestrator and were not assigned a specific implementer or reviewer role in your prompt, invoke the ai-dev-system:orchestrator skill at session start. A session whose prompt assigns it a child role (implementer, reviewer) keeps that role and does not invoke the skill. The orchestrator does not write or commit.
```

A spawn prompt must name the child role explicitly (for example "You are the implementer"), otherwise the child may read the line above as applying to it. The skill also tells a session with an explicitly assigned child role to keep that role.

The skill reads `${CLAUDE_PLUGIN_ROOT}/AGENTS.md` and `${CLAUDE_PLUGIN_ROOT}/docs/05-delegation.md`. The [skills reference](https://code.claude.com/docs/en/skills.md) states that `${CLAUDE_PLUGIN_ROOT}` is substituted in plugin skill content. The application's own `AGENTS.md` and `CLAUDE.md` govern application specifics. Statements in this repository's `AGENTS.md` about itself (setup workspace, no application build, its verification list) refer to the development-system repository. The orchestrator does not write or commit.

## Known behavior

- **Guard fires twice in this repository.** With the plugin enabled in this repository, the guard runs from `.claude/settings.json` and from the plugin's `hooks/hooks.json`. Both run the same script on the same input and give the same result. Not observed in a live session (untested).
- **The denial message points at a file the application lacks.** The guard's denial message mentions docs/05-delegation.md. An application repository has no such file. The guard is intentionally unchanged; the file is inside the plugin directory.
- **Guard scope.** The guard is a tripwire, not a security boundary, as described in [05-delegation.md](05-delegation.md). In the main checkout of the application repository it blocks writes; in a worktree it allows file-tool writes only inside that worktree; with `ORCHESTRATOR_GUARD=off` it allows everything.
- **No `CLAUDE.md` at the plugin root.** `claude plugin validate` warns that this repository's `CLAUDE.md` is not loaded as plugin context. That is expected; the orchestrator skill carries the instructions instead.

## Verification

Run on the branch that added this page. Command output is recorded in the pull request.

| Check | Result |
|---|---|
| `claude plugin validate .` (static, no session) | Passed, with warnings: root `CLAUDE.md` not loaded as context (expected). Plugin-directory advice (no LICENSE, no icon, no README install line) does not affect the verdict |
| `bash tools/hooks/test-orchestrator-guard.sh` | Passes, including a case that runs the command string from `hooks/hooks.json` with `CLAUDE_PLUGIN_ROOT` set and expects exit 2 in a main checkout |
| Hook command against a scratch clone of `sky64/floor`, main checkout and worktree | Simulated invocation only, see the pull request |

Not tested: loading the plugin in a live Claude Code session, in a Cloudroom cloud thread, or inside the `floor` Cloudroom project; marketplace registration from the application repository's settings; the `.tmpl` file staying unregistered at runtime; plugin update behavior; the guard firing twice in this repository.

## Documentation relied on

- [Plugins overview](https://code.claude.com/docs/en/plugins.md) (manifest location, components, install scopes, cloud sessions)
- [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference.md) (this is the page behind `plugins-reference`: fields, `name` and `version` rules, path variables and where they resolve, standard layout)
- [Create a marketplace](https://code.claude.com/docs/en/plugin-marketplaces.md) and the [marketplace reference](https://code.claude.com/docs/en/plugins/marketplace-reference.md) (required `name`, `owner`, `plugins`; relative `source` from the marketplace root; `validate`)
- [Add components to a plugin](https://code.claude.com/docs/en/plugins/components.md) (`hooks/hooks.json` shape with the top-level `"hooks"` key, `agents/` discovery, skills)
- [Plugin loading reference](https://code.claude.com/docs/en/plugins/loading.md), [Install and manage plugins](https://code.claude.com/docs/en/plugins/install.md), [Manage plugins for your organization](https://code.claude.com/docs/en/plugins/org.md), [Create a plugin](https://code.claude.com/docs/en/plugins/create.md) (`--plugin-dir`, `CLAUDE_CODE_PLUGIN_DIRS`, project settings)
- [Settings reference](https://code.claude.com/docs/en/settings-reference.md) (`enabledPlugins`, `extraKnownMarketplaces`)
- [Skills](https://code.claude.com/docs/en/skills.md) (frontmatter; `${CLAUDE_PLUGIN_ROOT}` substituted in plugin skill content)
