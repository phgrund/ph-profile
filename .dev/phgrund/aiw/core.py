"""Helpers básicos: saída, subprocess, git, meta.env e config global."""

import os
import subprocess
import sys
from pathlib import Path

AI_DIR = Path(".ai")
CONFIG_FILE = Path.home() / ".config" / "aiw" / "config"


def err(msg):
    print(f"aiw: erro: {msg}", file=sys.stderr)
    sys.exit(1)


def info(msg):
    print(f"==> {msg}")


def run(cmd, **kwargs):
    return subprocess.run(cmd, **kwargs)


def git(*args, capture=False, cwd=None, check=True):
    result = run(
        ["git", *args],
        cwd=cwd,
        check=check,
        capture_output=capture,
        text=True,
    )
    return result.stdout.strip() if capture else result


def repo_root():
    result = run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        err("não está dentro de um repositório Git")
    return Path(result.stdout.strip())


def current_branch():
    return git("rev-parse", "--abbrev-ref", "HEAD", capture=True)


def load_meta():
    meta = {}
    meta_file = AI_DIR / "meta.env"
    if meta_file.is_file():
        for line in meta_file.read_text().splitlines():
            if "=" in line and not line.lstrip().startswith("#"):
                key, _, value = line.partition("=")
                meta[key.strip()] = value.strip()
    meta.setdefault("AIW_CODER", os.environ.get("AIW_CODER", "claude"))
    meta.setdefault("AIW_REVIEWER", os.environ.get("AIW_REVIEWER", "codex"))
    meta.setdefault("AIW_SLUG", Path.cwd().name)
    return meta


def require_aiw_worktree():
    if not (AI_DIR / "meta.env").is_file():
        err("não encontrei .ai/meta.env — rode este comando dentro de uma worktree criada por 'aiw new'")
    return load_meta()


def pop_opt(args, name):
    # extrai '--name valor' de args (in-place); retorna valor ou None
    if name not in args:
        return None
    i = args.index(name)
    if i + 1 >= len(args):
        err(f"{name} requer um valor")
    args.pop(i)
    return args.pop(i)


def load_config():
    if not CONFIG_FILE.is_file():
        return {}
    return dict(
        line.split("=", 1)
        for line in CONFIG_FILE.read_text().splitlines()
        if "=" in line
    )


def save_config_value(key, value):
    cfg = load_config()
    cfg[key] = value
    CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
    CONFIG_FILE.write_text("".join(f"{k}={v}\n" for k, v in cfg.items()))
