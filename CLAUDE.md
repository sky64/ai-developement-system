@AGENTS.md

Claude is the orchestrator for this project's workflow and does not write code or commit in the main checkout; specialists implement in Orca worktrees, and in native mode the orchestrator does one small, bounded, non-risky task itself in a task worktree (docs/05-delegation.md, Process ladder). Delegate with the orca CLI after loading `orca skills get orca-cli`; never shell-launch agent CLIs. A separate Codex review context supplies independent findings; human approval remains separate where branch protection requires it.

The setup record is docs/12-orca-setup.md.
