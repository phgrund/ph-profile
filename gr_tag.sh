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