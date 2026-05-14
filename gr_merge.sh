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
  _merge_in_progress() {
    git rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1
  }
  _tree_clean() {
    git diff --quiet && git diff --cached --quiet
  }
  _wait_for_merge_resolution() {
    local source_branch="$1"
    local target="$2"
    local pre_merge_head="$3"
    local current_head state last_state=""

    _log "Merge conflict while merging $source_branch into $target."
    _log "Resolve the conflicts in another terminal, then run: git add <files> && git merge --continue"
    _log "Waiting for the merge to finish. Press Ctrl+C to stop waiting."

    while true; do
      if _merge_in_progress; then
        state="merge-in-progress"
      elif ! _tree_clean; then
        state="local-changes"
      else
        current_head="$(git rev-parse HEAD)"
        if [[ "$current_head" == "$pre_merge_head" ]]; then
          _log "Merge did not complete; HEAD is unchanged. Did you abort the merge?"
          return 1
        fi

        _log "Merge resolution detected. Continuing."
        return 0
      fi

      if [[ "$state" != "$last_state" ]]; then
        case "$state" in
          merge-in-progress)
            _log "Still waiting: merge is in progress."
            ;;
          local-changes)
            _log "Still waiting: merge state ended but local changes remain."
            ;;
        esac
        last_state="$state"
      fi

      sleep 5
    done
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
    local pre_merge_head

    _run git switch "$target" || return 1
    _run git pull origin "$target" || return 1

    pre_merge_head="$(git rev-parse HEAD)"
    if ! _run git merge "$source_branch"; then
      if _merge_in_progress; then
        _wait_for_merge_resolution "$source_branch" "$target" "$pre_merge_head" || return 1
      else
        _log "Merge failed and no merge is in progress."
        return 1
      fi
    fi

    _run git push origin "$target" || return 1
    source_branch="$target"
  done

  _log "Completed successfully. Final branch: $(git branch --show-current)"
}

gr_merge_deploy() {
  emulate -L zsh
  setopt localoptions pipefail

  _log() { print -r -- "[gr_merge_deploy] $*"; }

  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null)
  local target

  if [[ "$remote_url" == *apta-backend* ]]; then
    target="--back"
  elif [[ "$remote_url" == *apta-frontend* ]]; then
    target="--front"
  else
    _log "Error: cannot determine project type from remote: $remote_url" >&2
    return 1
  fi

  gr_merge || return 1

  _log "Running: dev-deploy $target $*"
  dev-deploy "$target" "$@"
}
