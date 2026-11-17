#!/usr/bin/env python3
"""The single reader of .claude/ai-dev-system.json (decision 0005).

Importable by the guard hook, callable as a CLI by the bot scripts and the
orchestrator. Standard library only.

    python3 -I tools/aidev_config.py get <dotted.key>   value, or exit 1
    python3 -I tools/aidev_config.py status              one status line
    python3 -I tools/aidev_config.py check <path>        validate, exit 1 + reasons

Rules:
- The config is read from the MAIN checkout (parent of the git common dir),
  never from a worktree's branch, so a worker cannot flip a switch on itself.
- Missing, unreadable, non-object or wrong-version files count as absent and
  every reader falls back to the shipped defaults (fail closed for the guard).
- Environment overrides AI_DEV_SYSTEM_FEATURE_<NAME>=on|off beat the file;
  ORCHESTRATOR_GUARD=off is an alias for the orchestrator_guard switch.
"""
import json
import os
import subprocess
import sys

CONFIG_REL = os.path.join(".claude", "ai-dev-system.json")
VERSION = 1
BOOL_FEATURES = ("orchestrator_guard", "model_ladder", "bot_identity", "build_map")
METERING_KINDS = ("none", "solvela", "openai-compatible")
ENV_PREFIX = "AI_DEV_SYSTEM_FEATURE_"


def _defaults_path() -> str:
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(os.path.dirname(here), "config", "ai-dev-system.defaults.json")


def defaults() -> dict:
    with open(_defaults_path(), encoding="utf-8") as fh:
        return json.load(fh)


def main_checkout(cwd: str):
    """Absolute path of the main checkout for cwd, or None outside a repo."""
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
            capture_output=True, text=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    common = out.stdout.strip()
    if not common:
        return None
    return os.path.dirname(common)


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
    root = main_checkout(cwd)
    path = config_path(root) if (root and cfg is not None) else "none"
    eff = cfg if isinstance(cfg, dict) else base
    platform = eff.get("platform", {}) if isinstance(eff.get("platform"), dict) else {}
    gateway = eff.get("gateway", {}) if isinstance(eff.get("gateway"), dict) else {}
    hosts = platform.get("hosts") if isinstance(platform.get("hosts"), dict) else {}
    devs = deviations(eff, base) if cfg is not None else []
    models = "defaults" if not devs else "deviates: " + ",".join(devs)
    return (
        f"ai-dev-system: config={path}"
        f" guard={_onoff(feature(cfg, 'orchestrator_guard'))}"
        f" ladder={_onoff(feature(cfg, 'model_ladder'))}"
        f" bot={_onoff(feature(cfg, 'bot_identity'))}"
        f" metering={feature(cfg, 'metering')}"
        f" build_map={_onoff(feature(cfg, 'build_map'))}"
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
            if not isinstance(feats.get(name), bool):
                problems.append(f"features.{name} must be true or false")
        if feats.get("metering") not in METERING_KINDS:
            problems.append(f"features.metering must be one of {', '.join(METERING_KINDS)}")
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
        print(status_line(load_config(main_checkout(cwd)), cwd))
        return 0
    if cmd == "get" and len(argv) == 2:
        key = argv[1]
        cfg = load_config(main_checkout(cwd))
        if key.startswith("features."):
            value = feature(cfg, key[len("features."):])
            if value is None:
                sys.stderr.write(f"aidev_config: unknown feature {key}\n")
                return 1
            _print_value(value)
            return 0
        try:
            _print_value(_get(cfg if cfg is not None else defaults(), key))
        except KeyError:
            sys.stderr.write(f"aidev_config: no such key {key}\n")
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
