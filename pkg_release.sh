# Package Release
# Cria a próxima tag semver e publica a release no GitHub, a partir da última tag do repo.
# Uso: pkg_release [major|minor|patch]   (padrão: patch)

pkg_release() {
    emulate -L zsh
    setopt localoptions pipefail

    _log() { print -r -- "[pkg_release] $*" }
    _run() { _log "$*"; "$@" }

    local bump=${1:-patch}
    if [[ "$bump" != (major|minor|patch) ]]; then
        _log "Uso: pkg_release [major|minor|patch]"
        return 1
    fi

    git rev-parse --git-dir >/dev/null 2>&1 || { _log "Erro: não é um repositório git"; return 1 }

    local branch=$(git rev-parse --abbrev-ref HEAD)
    local default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)
    default_branch=${default_branch#origin/}

    if [[ -n "$default_branch" && "$branch" != "$default_branch" ]]; then
        _log "Erro: release deve sair de $default_branch (atual: $branch)"
        return 1
    fi

    _run git fetch --tags --quiet || return 1

    # A release é criada a partir do commit remoto: HEAD local precisa estar em sincronia.
    if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/$branch)" ]]; then
        _log "Erro: $branch está fora de sincronia com origin/$branch (faça push/pull)"
        return 1
    fi

    local last_tag=$(git tag --list 'v*' | sort -V | tail -1)
    local -a parts
    parts=(${(s:.:)${last_tag#v}})
    local major=${parts[1]:-0} minor=${parts[2]:-0} patch=${parts[3]:-0}

    case $bump in
        major) (( major++, minor = 0, patch = 0 )) ;;
        minor) (( minor++, patch = 0 )) ;;
        patch) (( patch++ )) ;;
    esac

    local new_tag="v${major}.${minor}.${patch}"
    _log "Última tag: ${last_tag:-nenhuma} -> nova tag: $new_tag ($branch)"

    # ponytail: o prompt é o dry-run — responder "n" mostra a tag calculada e aborta.
    if ! read -q "?Criar a tag e publicar a release $new_tag? [y/N] "; then
        print
        _log "Abortado"
        return 1
    fi
    print

    # `gh release create` já cria a tag no remoto — não precisa de git tag/push local.
    _run gh release create "$new_tag" --target "$branch" --title "$new_tag" --generate-notes || return 1

    _run git fetch --tags --quiet
}
