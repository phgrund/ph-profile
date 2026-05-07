# Git Release Tag
# Automatically creates a tag based on the current release/x.y branch, incrementing the patch when a tag already exists.
# Example: git checkout release/1.30 && gr_tag "Fix version" -> creates a new v1.30.x tag.

gr_tag() {
    emulate -L zsh
    setopt localoptions pipefail

    _log() { print -r -- "[gr_tag] $*"; }
    _run() {
        _log "$*"
        "$@"
    }

    local message=$1

    if [[ -z "$message" ]]; then
        _log "Usage: gr_tag {message}"
        _log "Example: gr_tag \"Fix version\""
        return 1
    fi

    # Get the current branch name.
    local current_branch=$(git rev-parse --abbrev-ref HEAD)

    # Validate the release/x.y branch pattern.
    if [[ ! $current_branch =~ ^release/[0-9]+\.[0-9]+$ ]]; then
        _log "Error: the current branch does not match release/x.y: $current_branch"
        return 1
    fi

    # Extract the version from the branch name, e.g. 1.30 from release/1.30.
    local version="${current_branch#release/}"

    _run git pull --tags || return 1

    local last_tag=$(git tag --list | grep "$version" | sort -V | tail -1)

    local new_tag
    if [[ -z "$last_tag" ]]; then
        _log "No existing tag found for version: $version"
        new_tag="v${version}.0"
    else
        _log "Latest existing tag: $last_tag"
        local tag_clean=${last_tag#v}
        local base=${tag_clean%.*}
        local patch=${tag_clean##*.}
        local new_patch=$((patch + 1))
        new_tag="v${base}.${new_patch}"
    fi

    _log "New tag: $new_tag"

    _run git tag -a "$new_tag" -m "$message" || return 1

    _log "Tag created successfully: $new_tag"

    _run git push origin "$new_tag" || return 1
}

gr_tag_deploy() {
    emulate -L zsh
    setopt localoptions pipefail

    local -a message_parts deploy_args

    while [[ "$#" -gt 0 && "$1" != --* ]]; do
        message_parts+=("$1")
        shift
    done

    local message="${(j: :)message_parts}"
    deploy_args=("$@")

    if [[ -z "$message" ]]; then
        print -r -- "[gr_tag_deploy] Usage: gr_tag_deploy {message} [prod-deploy options]"
        print -r -- "[gr_tag_deploy] Example: gr_tag_deploy Fix bug --notify=false"
        return 1
    fi

    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ ! $current_branch =~ ^release/[0-9]+\.[0-9]+$ ]]; then
        print -r -- "[gr_tag_deploy] Error: not on a release/x.y branch: $current_branch" >&2
        return 1
    fi

    local version="${current_branch#release/}"

    gr_tag "$message" || return 1

    local new_tag
    new_tag=$(git tag --list | grep "^v${version}" | sort -V | tail -1)

    if [[ -z "$new_tag" ]]; then
        print -r -- "[gr_tag_deploy] Error: could not determine the created tag" >&2
        return 1
    fi

    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null)
    local target

    if [[ "$remote_url" == *apta-backend* ]]; then
        target="--back"
    elif [[ "$remote_url" == *apta-frontend* ]]; then
        target="--front"
    else
        print -r -- "[gr_tag_deploy] Error: cannot determine project type from remote: $remote_url" >&2
        return 1
    fi

    if (( ${#deploy_args[@]} > 0 )); then
        print -r -- "[gr_tag_deploy] Running: prod-deploy --tag=$new_tag $target ${deploy_args[*]}"
    else
        print -r -- "[gr_tag_deploy] Running: prod-deploy --tag=$new_tag $target"
    fi

    prod-deploy --tag="$new_tag" "$target" "${deploy_args[@]}"
}
