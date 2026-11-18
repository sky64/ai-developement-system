#!/usr/bin/env python3
"""The single reader of .claude/crew64.json (decision 0005).

Importable by the guard hook, callable as a CLI by the bot scripts and the
orchestrator. Standard library only.

    python3 -I tools/crew64_config.py get <dotted.key>   value, or exit 1
                                       (features.<name>, limits.<name> and process.<name>
                                       apply the fallbacks)
    python3 -I tools/crew64_config.py status              one status line
    python3 -I tools/crew64_config.py check <path>        validate, exit 1 + reasons

Rules:
- The config is read from the MAIN checkout (parent of the git common dir),
  never from a worktree's branch, and only when that checkout is registered
  as crew64.trustedRoot in the user's GLOBAL git config (crew64-enable adds
  it), so a worker cannot flip a switch on itself by editing git state.
- Missing, unreadable, non-object or wrong-version files count as absent and
  every reader falls back to the shipped defaults (fail closed for the guard).
- Environment overrides CREW64_FEATURE_<NAME>=on|off beat the file;
  ORCHESTRATOR_GUARD=off is an alias for the orchestrator_guard switch.
- Limits (decision 0007): limits.<name> is an integer of at least 1.
  CREW64_LIMIT_<NAME>=<n> beats the file when it parses as such; any other
  value, in the environment or the file (booleans included), falls through
  to the next source and finally to the shipped default.
- Process ladder (decision 0009): process.default_mode is one of auto,
  native, delegated; CREW64_PROCESS_MODE beats the file when, stripped and
  lower-cased, it names a mode. process.native_max_files and
  process.native_max_tool_calls are integers of at least 1, with no
  environment override. Invalid values read as the shipped defaults.
"""
import json
import os
import subprocess
import sys

CONFIG_REL = os.path.join(".claude", "crew64.json")
VERSION = 1
BOOL_FEATURES = (
    "orchestrator_guard", "model_ladder", "bot_identity", "build_map", "scout64", "process_ladder",
)
# Switches added after the first release: a config without the key validates
# and reads as the shipped default, so repos enabled earlier keep working.
OPTIONAL_FEATURES = ("scout64", "process_ladder")
METERING_KINDS = ("none", "solvela", "openai-compatible")
ENV_PREFIX = "CREW64_FEATURE_"
LIMITS = ("review_cycles",)
LIMIT_ENV_PREFIX = "CREW64_LIMIT_"
PROCESS_MODES = ("auto", "native", "delegated")
PROCESS_LIMITS = ("native_max_files", "native_max_tool_calls")
PROCESS_ENV = "CREW64_PROCESS_MODE"


def _defaults_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "config", "crew64.defaults.json")


def defaults() -> dict:
    with open(_defaults_path(), encoding="utf-8") as fh:
        return json.load(fh)


def _git_paths(cwd: str):
    """(git_dir, common_dir, toplevel) as absolute paths, or None outside a repo."""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--path-format=absolute",
             "--git-dir", "--git-common-dir", "--show-toplevel"],
            capture_output=True, text=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    lines = out.stdout.splitlines()
    if len(lines) < 2 or not lines[0] or not lines[1]:
        return None
    toplevel = lines[2] if len(lines) > 2 and lines[2] else None
    return lines[0], lines[1], toplevel


def _inside_or_equal(path: str, parent: str) -> bool:
    real_path, real_parent = os.path.realpath(path), os.path.realpath(parent)
    return real_path == real_parent or os.path.commonpath([real_path, real_parent]) == real_parent


def main_checkout(cwd: str):
    """Parent of the git common dir for cwd, or None outside a repo. Untrusted:
    a worker can repoint its worktree's commondir. Use trusted_root for config."""
    paths = _git_paths(cwd)
    return os.path.dirname(paths[1]) if paths else None


def candidate_root(cwd: str):
    """The main checkout git state points at for cwd, after structural checks.

    In the main checkout (git dir equals common dir) that is the toplevel.
    In a linked worktree the candidate is the parent of the common dir, and it
    is rejected when it is the worktree itself or anything inside it, or when
    the worktree's admin dir does not live under <common>/worktrees/. This is
    still derived from git state a worker can edit (it can even turn its
    worktree into a standalone repo), so it is a candidate, not a trusted root.
    """
    paths = _git_paths(cwd)
    if not paths:
        return None
    git_dir, common, toplevel = paths
    if os.path.realpath(git_dir) == os.path.realpath(common):
        return toplevel or os.path.dirname(common)
    root = os.path.dirname(common)
    if toplevel and _inside_or_equal(root, toplevel):
        return None
    if os.path.basename(common) != ".git" or not os.path.isdir(common):
        return None
    worktrees_dir = os.path.join(os.path.realpath(common), "worktrees")
    if not _inside_or_equal(git_dir, worktrees_dir) or os.path.realpath(git_dir) == worktrees_dir:
        return None
    return root


def registered_roots():
    """Main checkouts registered as trusted in the user's GLOBAL git config
    (crew64.trustedRoot, multi-valued; crew64-enable adds the entry). The
    global config is the pin outside any file a worker can edit in its
    worktree; a worker that rewrites it through Bash is the tripwire limit."""
    try:
        out = subprocess.run(
            ["git", "config", "--global", "--get-all", "crew64.trustedRoot"],
            capture_output=True, text=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if out.returncode != 0:
        return []
    return [os.path.realpath(line.strip()) for line in out.stdout.splitlines() if line.strip()]


def trusted_root(cwd: str):
    """The main checkout whose config may govern cwd, or None.

    The structural candidate (candidate_root) must also be registered in the
    user's global git config. Without the registration the file is reported
    as untrusted by `status` and every reader falls back to the defaults.
    """
    root = candidate_root(cwd)
    if root and os.path.realpath(root) in registered_roots():
        return root
    return None


def config_path(root: str) -> str:
    return os.path.join(root, CONFIG_REL)


def load_config(root):
    """Parsed config for the checkout at root, or None when absent or invalid."""
    if not root:
        return None
    try:
        with open(config_path(root), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError, UnicodeDecodeError):
        return None
    if not isinstance(data, dict) or data.get("version") != VERSION:
        return None
    return data


def _env_switch(name: str, env) -> object:
    if name not in BOOL_FEATURES:
        return None  # only boolean switches take an on/off override
    raw = env.get(ENV_PREFIX + name.upper())
    if raw is None and name == "orchestrator_guard":
        legacy = env.get("ORCHESTRATOR_GUARD")
        if legacy is not None and legacy.lower() == "off":
            raw = "off"
    if raw is None:
        return None
    low = raw.strip().lower()
    if low in ("on", "true", "1"):
        return True
    if low in ("off", "false", "0"):
        return False
    return None


def feature(cfg, name: str, env=None):
    """Switch value: env override, then the file, then the shipped default."""
    env = os.environ if env is None else env
    from_env = _env_switch(name, env)
    if from_env is not None:
        return from_env
    if isinstance(cfg, dict):
        feats = cfg.get("features")
        if isinstance(feats, dict) and name in feats:
            value = feats[name]
            # A value of the wrong type is a typo, not a switch: fall back to the
            # default so the status line never reports what the hook will not enforce.
            if name in BOOL_FEATURES and isinstance(value, bool):
                return value
            if name == "metering" and value in METERING_KINDS:
                return value
    return defaults()["features"].get(name)


def _positive_int(value):
    """value when it is an int (not a bool) of at least 1, else None."""
    if isinstance(value, bool) or not isinstance(value, int):
        return None
    return value if value >= 1 else None


def _env_limit(name: str, env):
    raw = env.get(LIMIT_ENV_PREFIX + name.upper())
    if raw is None:
        return None
    try:
        return _positive_int(int(raw.strip()))
    except ValueError:
        return None


def limit(cfg, name: str, env=None) -> int:
    """Limit value: env override, then the file, then the shipped default.
    Every source must be an integer of at least 1 or it is skipped."""
    env = os.environ if env is None else env
    from_env = _env_limit(name, env)
    if from_env is not None:
        return from_env
    if isinstance(cfg, dict) and isinstance(cfg.get("limits"), dict):
        from_file = _positive_int(cfg["limits"].get(name))
        if from_file is not None:
            return from_file
    return defaults()["limits"][name]


def _process_section(cfg) -> dict:
    """The config's process object, or an empty dict when absent or not an object."""
    section = cfg.get("process") if isinstance(cfg, dict) else None
    return section if isinstance(section, dict) else {}


def process_mode(cfg, env=None) -> str:
    """Process mode: env override, then the file, then the shipped default.
    Every source must name one of PROCESS_MODES or it is skipped."""
    env = os.environ if env is None else env
    raw = env.get(PROCESS_ENV)
    if raw is not None and raw.strip().lower() in PROCESS_MODES:
        return raw.strip().lower()
    from_file = _process_section(cfg).get("default_mode")
    if isinstance(from_file, str) and from_file in PROCESS_MODES:
        return from_file
    return defaults()["process"]["default_mode"]


def process_limit(cfg, name: str) -> int:
    """Native-mode threshold: the file value when it is an integer of at
    least 1, else the shipped default. No environment override."""
    from_file = _positive_int(_process_section(cfg).get(name))
    if from_file is not None:
        return from_file
    return defaults()["process"][name]


def _process_status(cfg) -> str:
    if feature(cfg, "process_ladder") is not True:
        return "process=off"
    return (
        f"process={process_mode(cfg)}"
        f" max_files={process_limit(cfg, 'native_max_files')}"
        f" max_calls={process_limit(cfg, 'native_max_tool_calls')}"
    )


def deviations(cfg: dict, base: dict):
    """Dotted keys under models whose value differs from base."""
    out = []

    def walk(a, b, prefix):
        if isinstance(a, dict) and isinstance(b, dict):
            for key in sorted(set(a) | set(b)):
                walk(a.get(key), b.get(key), f"{prefix}.{key}")
        elif a != b:
            out.append(prefix)

    walk(cfg.get("models"), base.get("models"), "models")
    return out


def _onoff(value) -> str:
    return "on" if value is True else "off"


def status_line(cfg, cwd: str) -> str:
    base = defaults()
    root = trusted_root(cwd)
    if root and cfg is not None:
        path = config_path(root)
    else:
        path = "none"
        candidate = candidate_root(cwd)
        if candidate and not root and os.path.exists(config_path(candidate)):
            path = "untrusted:" + config_path(candidate)
    eff = cfg if isinstance(cfg, dict) else base
    platform = eff.get("platform", {}) if isinstance(eff.get("platform"), dict) else {}
    gateway = eff.get("gateway", {}) if isinstance(eff.get("gateway"), dict) else {}
    hosts = platform.get("hosts") if isinstance(platform.get("hosts"), dict) else {}
    devs = deviations(eff, base) if cfg is not None else []
    models = "defaults" if not devs else "deviates: " + ",".join(devs)
    return (
        f"crew64: config={path}"
        f" guard={_onoff(feature(cfg, 'orchestrator_guard'))}"
        f" ladder={_onoff(feature(cfg, 'model_ladder'))}"
        f" bot={_onoff(feature(cfg, 'bot_identity'))}"
        f" metering={feature(cfg, 'metering')}"
        f" build_map={_onoff(feature(cfg, 'build_map'))}"
        f" review_cycles={limit(cfg, 'review_cycles')}"
        f" scout64={_onoff(feature(cfg, 'scout64'))}"
        f" {_process_status(cfg)}"
        f" platform={platform.get('kind', 'orca')}"
        f" hosts={','.join(sorted(hosts)) if hosts else 'none'}"
        f" gateway={gateway.get('kind', 'none')}"
        f" models={models}"
    )


def check(data) -> list:
    """Problems with a parsed config; empty list means valid."""
    problems = []
    if not isinstance(data, dict):
        return ["config is not a JSON object"]
    if data.get("version") != VERSION:
        problems.append(f"version must be {VERSION}")
    feats = data.get("features")
    if not isinstance(feats, dict):
        problems.append("features must be an object")
    else:
        for name in BOOL_FEATURES:
            if name in OPTIONAL_FEATURES and name not in feats:
                continue
            if not isinstance(feats.get(name), bool):
                problems.append(f"features.{name} must be true or false")
        if feats.get("metering") not in METERING_KINDS:
            problems.append(f"features.metering must be one of {', '.join(METERING_KINDS)}")
    if "limits" in data:
        limits = data.get("limits")
        if not isinstance(limits, dict):
            problems.append("limits must be an object")
        else:
            for name in LIMITS:
                if _positive_int(limits.get(name)) is None:
                    problems.append(f"limits.{name} must be an integer of at least 1")
    if "process" in data:
        process = data.get("process")
        if not isinstance(process, dict):
            problems.append("process must be an object")
        else:
            mode = process.get("default_mode")
            if not isinstance(mode, str) or mode not in PROCESS_MODES:
                problems.append(f"process.default_mode must be one of {', '.join(PROCESS_MODES)}")
            for name in PROCESS_LIMITS:
                if _positive_int(process.get(name)) is None:
                    problems.append(f"process.{name} must be an integer of at least 1")
    platform = data.get("platform")
    if not isinstance(platform, dict) or not isinstance(platform.get("kind"), str):
        problems.append("platform.kind must be a string")
    elif not isinstance(platform.get("hosts"), dict):
        problems.append("platform.hosts must be an object")
    gateway = data.get("gateway")
    if not isinstance(gateway, dict) or gateway.get("kind") not in METERING_KINDS:
        problems.append(f"gateway.kind must be one of {', '.join(METERING_KINDS)}")
    models = data.get("models")
    if not isinstance(models, dict):
        problems.append("models must be an object")
    else:
        for role in ("research", "claude_implementer"):
            ids = models.get(role)
            if not (isinstance(ids, list) and len(ids) == 3 and all(isinstance(i, str) for i in ids)):
                problems.append(f"models.{role} must be a list of three model ids")
        codex = models.get("codex_reviewer")
        if not isinstance(codex, dict) or not isinstance(codex.get("model"), str):
            problems.append("models.codex_reviewer.model must be a string")
        elif not (isinstance(codex.get("effort"), list) and len(codex["effort"]) == 3):
            problems.append("models.codex_reviewer.effort must be a list of three levels")
    return problems


def _get(data: dict, dotted: str):
    node = data
    for part in dotted.split("."):
        if isinstance(node, dict) and part in node:
            node = node[part]
        elif isinstance(node, list) and part.isdigit() and int(part) < len(node):
            node = node[int(part)]
        else:
            raise KeyError(dotted)
    return node


def _print_value(value) -> None:
    if isinstance(value, bool):
        print("true" if value else "false")
    elif value is None:
        print("none")
    elif isinstance(value, str):
        print(value)
    else:
        print(json.dumps(value, sort_keys=True))


def cli(argv) -> int:
    if len(argv) < 1:
        sys.stderr.write(__doc__)
        return 2
    cmd = argv[0]
    cwd = os.getcwd()
    if cmd == "status":
        print(status_line(load_config(trusted_root(cwd)), cwd))
        return 0
    if cmd == "get" and len(argv) == 2:
        key = argv[1]
        cfg = load_config(trusted_root(cwd))
        if key.startswith("features."):
            value = feature(cfg, key[len("features."):])
            if value is None:
                sys.stderr.write(f"crew64_config: unknown feature {key}\n")
                return 1
            _print_value(value)
            return 0
        if key.startswith("limits."):
            name = key[len("limits."):]
            if name not in LIMITS:
                sys.stderr.write(f"crew64_config: unknown limit {key}\n")
                return 1
            _print_value(limit(cfg, name))
            return 0
        if key.startswith("process."):
            name = key[len("process."):]
            if name == "default_mode":
                _print_value(process_mode(cfg))
            elif name in PROCESS_LIMITS:
                _print_value(process_limit(cfg, name))
            else:
                sys.stderr.write(f"crew64_config: unknown process key {key}\n")
                return 1
            return 0
        try:
            _print_value(_get(cfg if cfg is not None else defaults(), key))
        except KeyError:
            sys.stderr.write(f"crew64_config: no such key {key}\n")
            return 1
        return 0
    if cmd == "check" and len(argv) == 2:
        try:
            with open(argv[1], encoding="utf-8") as fh:
                data = json.load(fh)
        except (OSError, ValueError) as exc:
            print(f"cannot read {argv[1]}: {exc}")
            return 1
        problems = check(data)
        for line in problems:
            print(line)
        return 1 if problems else 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(cli(sys.argv[1:]))
