"""Invocação dos agentes (coder/reviewer) + comandos plan/implement/review/fix."""

from pathlib import Path

from core import AI_DIR, err, git, info, pop_opt, require_aiw_worktree, run
from prompts import FIX_PROMPT, IMPLEMENT_PROMPT, PLAN_PROMPT, REVIEW_PROMPT


def run_coder(meta, mode, session, prompt, model=None, effort=None):
    coder = meta["AIW_CODER"]
    if coder == "claude":
        cmd = ["claude", "--permission-mode", mode, "-n", session]
        if model:
            cmd += ["--model", model]
        if effort:
            cmd += ["--effort", effort]
        cmd.append(prompt)
    elif coder == "codex":
        sandbox = "read-only" if mode == "plan" else "workspace-write"
        cmd = ["codex", "--sandbox", sandbox]
        if model:
            cmd += ["-m", model]
        if effort:
            cmd += ["-c", f"model_reasoning_effort={effort}"]
        cmd.append(prompt)
    else:
        err(f"AIW_CODER desconhecido: '{coder}' (suportados: claude, codex)")
    run(cmd, check=True)


def run_reviewer(meta, out_file, prompt):
    reviewer = meta["AIW_REVIEWER"]
    if reviewer == "codex":
        run(
            ["codex", "exec", "--sandbox", "read-only", "--output-last-message", str(out_file), prompt],
            check=True,
        )
    elif reviewer == "claude":
        result = run(
            ["claude", "-p", "--permission-mode", "plan", prompt],
            check=True,
            capture_output=True,
            text=True,
        )
        Path(out_file).write_text(result.stdout)
    else:
        err(f"AIW_REVIEWER desconhecido: '{reviewer}' (suportados: codex, claude)")


def cmd_plan(args):
    meta = require_aiw_worktree()
    task = AI_DIR / "task.md"
    if not task.is_file() or not task.read_text().strip():
        err(".ai/task.md não existe ou está vazio — edite-o antes de rodar 'aiw plan'")
    (AI_DIR / "claude-plan-prompt.md").write_text(PLAN_PROMPT)
    run_coder(meta, "plan", f"aiw-{meta['AIW_SLUG']}", PLAN_PROMPT,
              model=pop_opt(args, "--model"), effort=pop_opt(args, "--effort"))


def cmd_implement(args):
    meta = require_aiw_worktree()
    if not (AI_DIR / "plan.md").is_file():
        err(".ai/plan.md não existe — rode 'aiw plan' primeiro")
    run_coder(meta, "acceptEdits", f"aiw-{meta['AIW_SLUG']}", IMPLEMENT_PROMPT,
              model=pop_opt(args, "--model"), effort=pop_opt(args, "--effort"))


def cmd_fix(args):
    meta = require_aiw_worktree()
    if not (AI_DIR / "codex-review.md").is_file():
        err(".ai/codex-review.md não existe — rode 'aiw review' primeiro")
    run_coder(meta, "acceptEdits", f"aiw-{meta['AIW_SLUG']}-fix", FIX_PROMPT,
              model=pop_opt(args, "--model"), effort=pop_opt(args, "--effort"))


def cmd_review(args):
    meta = require_aiw_worktree()
    info("gerando diff...")
    diff = git("diff", "--", ".", ":!vendor", ":!node_modules", ":!.ai", capture=True)
    if not diff:
        err("diff vazio — nada para revisar")
    (AI_DIR / "patch.diff").write_text(diff + "\n")
    (AI_DIR / "codex-review-prompt.md").write_text(REVIEW_PROMPT)
    info(f"revisando com {meta['AIW_REVIEWER']} (read-only)...")
    run_reviewer(meta, AI_DIR / "codex-review.md", REVIEW_PROMPT)
    info("review salva em .ai/codex-review.md")
