#!/usr/bin/env python3
"""aiw - toolkit para rodar agentes de IA (Claude Code / Codex) em worktrees Git isoladas.

Uso: aiw new <slug> [clickup-url] | plan | implement | review | fix | validate | status | clean
"""

import subprocess
import sys
from pathlib import Path

# permite chamar via symlink (ex.: ~/.local/bin/aiw) de qualquer diretório
sys.path.insert(0, str(Path(__file__).resolve().parent))

import agents
import stack
import worktree
from core import err
from prompts import USAGE

COMMANDS = {
    "new": worktree.cmd_new,
    "up": stack.cmd_up,
    "down": stack.cmd_down,
    "sail": stack.cmd_sail,
    "plan": agents.cmd_plan,
    "implement": agents.cmd_implement,
    "review": agents.cmd_review,
    "fix": agents.cmd_fix,
    "validate": stack.cmd_validate,
    "status": worktree.cmd_status,
    "clean": worktree.cmd_clean,
}


def main():
    sys.stdout.reconfigure(line_buffering=True)
    cmd = sys.argv[1] if len(sys.argv) > 1 else "help"
    if cmd in ("help", "-h", "--help"):
        print(USAGE)
        return
    handler = COMMANDS.get(cmd)
    if handler is None:
        print(USAGE, file=sys.stderr)
        err(f"comando desconhecido: {cmd}")
    try:
        handler(sys.argv[2:])
    except subprocess.CalledProcessError as e:
        err(f"comando falhou ({e.returncode}): {' '.join(map(str, e.cmd))}")
    except KeyboardInterrupt:
        print()
        sys.exit(130)


if __name__ == "__main__":
    main()
