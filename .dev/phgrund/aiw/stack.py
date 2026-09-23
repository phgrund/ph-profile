"""Stack sail por worktree + comandos up/down/sail/validate.

Cada worktree ganha um stack compose próprio: COMPOSE_PROJECT_NAME derivado do
diretório + portas livres exportadas por cima dos defaults `${VAR:-...}` do
docker-compose.yml. Volumes/DB ficam separados do stack do repo base.
"""

import os
import re
import socket
import subprocess
import sys
from pathlib import Path

from core import AI_DIR, err, info, load_meta, require_aiw_worktree, run


def free_port():
    with socket.socket() as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def compose_port_vars():
    compose = Path("docker-compose.yml")
    if not compose.is_file():
        err("docker-compose.yml não encontrado na worktree")
    # ponytail: assume que toda var *_PORT interpolada no compose é porta de host
    # deslocável (vale para este projeto; REVERB usa a mesma var dos dois lados)
    return sorted(set(re.findall(r"\$\{([A-Z_]*PORT)[:}]", compose.read_text())))


def patch_env_file(sail_vars):
    # Grava projeto/portas no .env da worktree: o compose interpola daqui e o app
    # dentro do container (ex.: Reverb) lê os mesmos valores. Com isso até
    # './vendor/bin/sail' puro já usa o stack certo, sem passar pelo aiw.
    env_file = Path(".env")
    if env_file.is_symlink():
        info("AVISO: .env é symlink do repo base — não vou editá-lo. Recrie a worktree ('aiw clean' + 'aiw new') para ter .env próprio.")
        return
    if not env_file.is_file():
        return
    text = env_file.read_text()
    for var, val in sail_vars.items():
        if re.search(rf"^{var}=", text, flags=re.M):
            text = re.sub(rf"^{var}=.*$", f"{var}={val}", text, flags=re.M)
        else:
            text = text.rstrip("\n") + f"\n{var}={val}\n"
    env_file.write_text(text)


def ensure_sail_env(meta):
    if not any(k.startswith("AIW_SAIL_") for k in meta):
        project = re.sub(r"[^a-z0-9_-]+", "-", Path.cwd().name.lower())
        sail_vars = {"COMPOSE_PROJECT_NAME": project}
        for var in compose_port_vars():
            sail_vars[var] = str(free_port())
        with (AI_DIR / "meta.env").open("a") as f:
            f.writelines(f"AIW_SAIL_{k}={v}\n" for k, v in sail_vars.items())
        patch_env_file(sail_vars)
        meta.update(load_meta())
        info("projeto/portas do stack gravados em .ai/meta.env e .env")
    return {k[len("AIW_SAIL_"):]: v for k, v in meta.items() if k.startswith("AIW_SAIL_")}


def sail(meta, args, **kwargs):
    env = {**os.environ, **ensure_sail_env(meta)}
    return run(["./vendor/bin/sail", *args], env=env, **kwargs)


def require_stack_running(meta):
    result = sail(meta, ["ps", "-q"], capture_output=True, text=True, check=False)
    if not result.stdout.strip():
        err("o stack desta worktree não está rodando — rode 'aiw up' primeiro")


def fix_root_files(meta, wt):
    # o container cria arquivos como root em storage/ (bind mount); sem consertar o
    # dono, o 'git worktree remove' falha com permissão negada
    uid, gid = os.getuid(), os.getgid()
    check = run(["find", str(wt), "!", "-user", str(uid), "-print", "-quit"],
                capture_output=True, text=True, check=False)
    if not check.stdout.strip():
        return
    info("corrigindo dono de arquivos criados pelo container...")
    images = sail(meta, ["config", "--images"], capture_output=True, text=True, check=False).stdout.split()
    if not images:
        info(f"AVISO: não achei imagem do compose; rode manualmente: sudo chown -R {uid}:{gid} {wt}")
        return
    run(["docker", "run", "--rm", "--entrypoint", "chown",
         "-v", f"{wt}:/aiw-wt", images[0], "-R", f"{uid}:{gid}", "/aiw-wt"], check=False)


def cmd_up(args):
    seed = "--skip-seed" not in args
    fresh = "--fresh" in args
    meta = require_aiw_worktree()
    sail_env = ensure_sail_env(meta)
    info(f"subindo stack '{sail_env['COMPOSE_PROJECT_NAME']}'...")
    sail(meta, ["up", "-d"], check=True)
    # ponytail: marcador em meta.env, não no banco; se apagar o volume por fora, use --fresh
    if fresh or not meta.get("AIW_DB_READY"):
        migrate = ["artisan", "migrate:fresh" if fresh else "migrate"]
        if seed:
            migrate.append("--seed")
        info("preparando banco: " + " ".join(migrate[1:]))
        sail(meta, migrate, check=True)
        if not meta.get("AIW_DB_READY"):
            with (AI_DIR / "meta.env").open("a") as f:
                f.write("AIW_DB_READY=1\n")
    else:
        info("banco já migrado — pulando migrations (use --fresh para recriar)")
    ports = "\n".join(f"  {k}={v}" for k, v in sail_env.items() if k.endswith("PORT"))
    print(f"\nStack de pé. Portas desta worktree:\n{ports}\n\nApp: http://localhost:{sail_env.get('APP_PORT', '?')}")


def cmd_down(args):
    meta = require_aiw_worktree()
    sail(meta, ["down"], check=True)
    info("stack parado (volumes preservados; 'aiw clean' remove tudo)")


def cmd_sail(args):
    meta = require_aiw_worktree()
    if not args:
        err("uso: aiw sail <comando sail...>  (ex: aiw sail artisan tinker)")
    sys.exit(sail(meta, args, check=False).returncode)


def cmd_validate(args):
    meta = require_aiw_worktree()
    if not os.access("vendor/bin/sail", os.X_OK):
        err("vendor/bin/sail não encontrado")
    require_stack_running(meta)
    env = {**os.environ, **ensure_sail_env(meta)}

    steps = []
    composer = Path("composer.json").read_text() if Path("composer.json").is_file() else ""
    # ponytail: checagem por substring em vez de parse do bloco "scripts"; suficiente na prática
    if '"test"' in composer:
        steps.append(("testes (composer)", ["./vendor/bin/sail", "composer", "test"]))
    elif any(Path(p).is_file() for p in ("phpunit.xml", "phpunit.xml.dist", "tests/Pest.php")):
        steps.append(("testes (artisan)", ["./vendor/bin/sail", "artisan", "test"]))
    if Path("vendor/bin/pint").exists():
        steps.append(("pint", ["./vendor/bin/sail", "pint", "--test"]))
    if any(Path(p).is_file() for p in ("phpstan.neon", "phpstan.neon.dist")):
        steps.append(("phpstan", ["./vendor/bin/sail", "bin", "phpstan", "analyse"]))

    failed = False
    with (AI_DIR / "validation.log").open("w") as log:
        def tee(line):
            print(line)
            log.write(line + "\n")

        for desc, cmd in steps:
            tee(f"==> {desc}: {' '.join(cmd)}")
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
            for line in proc.stdout:
                tee(line.rstrip("\n"))
            if proc.wait() == 0:
                tee(f"[OK] {desc}")
            else:
                tee(f"[FALHOU] {desc}")
                failed = True

    info("log completo em .ai/validation.log")
    sys.exit(1 if failed else 0)
