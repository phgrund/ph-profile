"""Ciclo de vida da worktree: new/status/clean + arquivos locais e VS Code."""

import os
import re
import shutil
from pathlib import Path

from core import (AI_DIR, CONFIG_FILE, current_branch, err, git, info,
                  load_config, load_meta, repo_root, require_aiw_worktree,
                  run, save_config_value)
from prompts import TASK_TEMPLATE
from stack import fix_root_files, sail


def setup_gitignore(wt):
    gitignore = wt / ".gitignore"
    lines = gitignore.read_text().splitlines() if gitignore.exists() else []
    missing = [rule for rule in ("/.ai/*", "!/.ai/.gitkeep") if rule not in lines]
    if missing:
        with gitignore.open("a") as f:
            f.write("\n" + "\n".join(missing) + "\n")


def setup_ai_files(wt, slug, branch, url, base, meta):
    ai = wt / AI_DIR
    ai.mkdir(exist_ok=True)
    (ai / ".gitkeep").touch()
    (ai / "meta.env").write_text(
        f"AIW_SLUG={slug}\n"
        f"AIW_BRANCH={branch}\n"
        f"AIW_CLICKUP_URL={url}\n"
        f"AIW_BASE_REPO={base}\n"
        f"AIW_CODER={meta['AIW_CODER']}\n"
        f"AIW_REVIEWER={meta['AIW_REVIEWER']}\n"
    )
    (ai / "task.md").write_text(TASK_TEMPLATE.format(url=url))


def setup_local_files(wt, base):
    # .env e vendor são CÓPIAS, não symlinks: symlink para fora do bind mount
    # quebraria dentro do container do stack próprio da worktree.
    if (base / ".env").is_file() and not (wt / ".env").exists():
        shutil.copy2(base / ".env", wt / ".env")
        info("copiado: .env")
    if (base / "vendor").is_dir() and not (wt / "vendor").exists():
        info("clonando vendor (hardlinks, instantâneo)...")
        # ponytail: cp -al compartilha inodes; composer substitui arquivos por
        # unlink+create, então updates na worktree não vazam pro vendor do base
        run(["cp", "-al", str(base / "vendor"), str(wt / "vendor")], check=True)
    # storage local por worktree (logs/cache/sessões/uploads isolados)
    for d in ("app", "framework/cache", "framework/sessions", "framework/views", "logs"):
        (wt / "storage" / d).mkdir(parents=True, exist_ok=True)


def check_vendor(wt):
    # ponytail: vendor é clone do base já instalado e o composer.json da branch nova é
    # idêntico ao HEAD do base — composer install na criação seria redundante.
    if not os.access(wt / "vendor/bin/sail", os.X_OK):
        err("vendor/bin/sail não encontrado na worktree. Rode 'composer install' no repositório base primeiro.")
    info("vendor ok (clone do repo base, já instalado)")


def open_vscode(wt):
    if os.environ.get("AIW_NO_CODE"):
        return
    if not shutil.which("code"):
        info(f"VS Code (code) não encontrado no PATH — abra manualmente: {wt / AI_DIR / 'task.md'}")
        return
    pref = load_config().get("vscode")
    if pref == "never":
        return
    if pref != "always":
        try:
            answer = input("Abrir VS Code em nova janela? [s]im / [n]ão / [sempre] / [nunca]: ").strip().lower()
        except EOFError:
            answer = "n"
        if answer in ("sempre", "nunca"):
            save_config_value("vscode", "always" if answer == "sempre" else "never")
            info(f"preferência salva em {CONFIG_FILE}")
        if answer not in ("s", "sim", "sempre"):
            return
    run(["code", "-n", str(wt), str(wt / AI_DIR / "task.md")], check=False)


def cmd_new(args):
    if not args:
        err("uso: aiw new <slug> [clickup-url]")
    slug = args[0]
    url = args[1] if len(args) > 1 else ""
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]*", slug):
        err(f"slug inválido '{slug}' (use apenas letras minúsculas, números e hífens)")

    root = repo_root()
    branch = f"ai/{slug}"
    wt = root.parent / f"{root.name}--ai--{slug}"

    if wt.exists():
        err(f"worktree já existe: {wt}")
    if git("show-ref", "--verify", "--quiet", f"refs/heads/{branch}", cwd=root, check=False).returncode == 0:
        err(f"branch já existe: {branch}")

    info(f"criando worktree {wt} (branch {branch})...")
    git("worktree", "add", "-b", branch, str(wt), cwd=root)

    meta = load_meta()
    setup_gitignore(wt)
    setup_ai_files(wt, slug, branch, url, root, meta)
    setup_local_files(wt, root)
    check_vendor(wt)
    open_vscode(wt)

    print(f"""
Worktree pronta: {wt}

Edite .ai/task.md.
Depois rode dentro da worktree:

  cd {wt}
  aiw plan
""")


def exists_label(path):
    p = Path(path)
    return f"sim ({p})" if p.is_file() and p.stat().st_size else "não"


def cmd_status(args):
    meta = require_aiw_worktree()
    print(f"""Worktree:   {Path.cwd()}
Branch:     {current_branch()}
ClickUp:    {meta.get('AIW_CLICKUP_URL') or '<sem link>'}
Coder:      {meta['AIW_CODER']}
Reviewer:   {meta['AIW_REVIEWER']}
Plano:      {exists_label(AI_DIR / 'plan.md')}
Review:     {exists_label(AI_DIR / 'codex-review.md')}
Validação:  {exists_label(AI_DIR / 'validation.log')}
""")
    git("status", "--short")
    git("diff", "--stat")


def cmd_clean(args):
    prune = "--prune" in args
    meta = require_aiw_worktree()
    wt = Path.cwd()
    branch = current_branch()
    base = meta.get("AIW_BASE_REPO") or err("AIW_BASE_REPO ausente no meta.env")

    print(f"Worktree: {wt}")
    print(f"Branch:   {branch}")
    print("Estado (mudanças abaixo serão PERDIDAS se não commitadas):")
    git("status", "--short")
    if prune:
        answer = input(f"Remover worktree E APAGAR a branch '{branch}'? [y/N] ")
    else:
        answer = input("Remover esta worktree? (a branch será mantida) [y/N] ")
    if answer.strip().lower() != "y":
        print("abortado.")
        return

    if any(k.startswith("AIW_SAIL_") for k in meta):
        info("derrubando stack da worktree (containers + volumes)...")
        sail(meta, ["down", "-v"], check=False)
        fix_root_files(meta, wt)

    # ponytail: --force é necessário porque .ai/ e os symlinks sempre deixam a worktree "suja";
    # a confirmação acima (com status na tela) é a trava de segurança.
    git("worktree", "remove", "--force", str(wt), cwd=base)
    if prune:
        git("branch", "-D", branch, cwd=base)
        info(f"worktree e branch '{branch}' removidas.")
    else:
        info(f"worktree removida. Para apagar a branch: git branch -D {branch}")
