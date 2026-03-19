# Git Release Merge
# Iteratively merges the current release branch into subsequent release branches until reaching develop.

gr_merge() {
  emulate -L zsh
  setopt localoptions pipefail

  _log() { print -r -- "[gr_merge] $*"; }
  _run() {
    _log "$*"
    "$@"
  }

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _log "Error: this directory is not a Git repository."
    return 1
  fi

  if ! git diff --quiet || ! git diff --cached --quiet; then
    _log "Error: there are local changes (staged/unstaged)."
    return 1
  fi

  local current
  current="$(git branch --show-current)"

  if [[ ! "$current" =~ '^release/[0-9]+\.[0-9]+$' ]]; then
    _log "Error: the current branch must match release/X.Y (current: $current)."
    return 1
  fi

  _run git fetch origin --prune

   local -a all_releases=()
  local ref branch

  while IFS= read -r ref; do
    branch="${ref#origin/}"
    if [[ "$branch" =~ '^release/[0-9]+\.[0-9]+$' ]]; then
      all_releases+=("$branch")
    fi
  done < <(git branch -r --list 'origin/release/*' | sed 's/^[[:space:]]*//')

  if (( ${#all_releases[@]} == 0 )); then
    _log "Error: no release/X.Y branches were found on origin."
    return 1
  fi

  all_releases=("${(@on)all_releases}") # Sort lexicographically first.
  # Then sort by version using sort -V.
  all_releases=("${(@f)$(printf "%s\n" "${all_releases[@]}" | sort -V)}")

  local found_current=0
  local -a next_releases=()
  local b
  for b in "${all_releases[@]}"; do
    if (( found_current )); then
      next_releases+=("$b")
    fi
    [[ "$b" == "$current" ]] && found_current=1
  done

  if (( ! found_current )); then
    _log "Error: $current does not exist on origin. Push it first."
    return 1
  fi

  local source_branch="$current"
  local -a chain=("${next_releases[@]}" "develop")

  _log "Initial branch: $current"
  _log "Merge chain: ${chain[*]}"

  _run git switch "$current"
  _run git pull origin "$current"

  local target
  for target in "${chain[@]}"; do
    _log "Propagating: $source_branch -> $target"

    _run git switch "$target" || return 1
    _run git pull origin "$target" || return 1

    if ! _run git merge "$source_branch"; then
      _log "Merge conflict while merging $source_branch into $target. Resolve it manually."
      return 1
    fi

    _run git push origin "$target" || return 1
    source_branch="$target"
  done

  _log "Completed successfully. Final branch: $(git branch --show-current)"
}