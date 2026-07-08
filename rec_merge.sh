# Recursive Merge
# From the current branch, merges an ancestor branch down through the stack:
# rec_merge A (while on C, stacked C <- B <- A) merges A into B, then B into C.
# Intermediate branches are auto-detected by ancestry; pass them explicitly
# (rec_merge A B) if the auto-detection guesses wrong.

rec_merge() {
  emulate -L zsh
  setopt localoptions pipefail

  _log() { print -r -- "[rec_merge] $*"; }
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

  local base_branch="${1:-}"

  if [[ -z "$base_branch" ]]; then
    _log "Usage: rec_merge <base-branch> [intermediate-branches...]"
    return 1
  fi

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _log "Error: this directory is not a Git repository."
    return 1
  fi

  if ! _tree_clean; then
    _log "Error: there are local changes (staged/unstaged)."
    return 1
  fi

  local current
  current="$(git branch --show-current)"

  if [[ -z "$current" ]]; then
    _log "Error: not on a branch (detached HEAD)."
    return 1
  fi

  if [[ "$base_branch" == "$current" ]]; then
    _log "Error: base branch is the current branch."
    return 1
  fi

  if ! git show-ref -q --verify "refs/heads/$base_branch"; then
    _log "Error: local branch $base_branch does not exist."
    return 1
  fi

  _run git fetch origin --prune

  local -a chain=()
  if (( $# > 1 )); then
    chain=("$@" "$current")
  else
    local base
    if ! base="$(git merge-base "$base_branch" "$current" 2>/dev/null)"; then
      _log "Error: $base_branch and $current have no common history."
      return 1
    fi

    # ponytail: ancestry heuristic — a branch whose fork point with the current
    # branch is strictly after the base's fork point sits between them in the
    # stack. Siblings forked from the same commit can slip in; the confirmation
    # prompt below is the guard, and explicit args are the escape hatch.
    local -a middles=() middle_bases=()
    local x mb i
    for x in "${(@f)$(git for-each-ref --format='%(refname:short)' refs/heads)}"; do
      [[ "$x" == "$current" || "$x" == "$base_branch" ]] && continue
      mb="$(git merge-base "$x" "$current" 2>/dev/null)" || continue
      [[ "$mb" == "$base" ]] && continue
      git merge-base --is-ancestor "$base" "$mb" || continue

      # Insertion sort by fork-point ancestry: earlier fork point comes first.
      i=1
      while (( i <= ${#middles[@]} )) && git merge-base --is-ancestor "${middle_bases[$i]}" "$mb"; do
        (( i++ ))
      done
      middles=("${(@)middles[1,$((i-1))]}" "$x" "${(@)middles[$i,-1]}")
      middle_bases=("${(@)middle_bases[1,$((i-1))]}" "$mb" "${(@)middle_bases[$i,-1]}")
    done

    chain=("$base_branch" "${middles[@]}" "$current")
  fi

  _log "Merge path: ${(j: -> :)chain}"
  local reply
  read "reply?[rec_merge] Proceed? [y/N] "
  if [[ "$reply" != [yY] ]]; then
    _log "Aborted."
    return 1
  fi

  local source_branch="" target pre_merge_head
  for target in "${chain[@]}"; do
    _run git switch "$target" || return 1
    if git show-ref -q --verify "refs/remotes/origin/$target"; then
      _run git pull origin "$target" || return 1
    fi

    if [[ -n "$source_branch" ]]; then
      _log "Propagating: $source_branch -> $target"
      pre_merge_head="$(git rev-parse HEAD)"
      if ! _run git merge --no-edit "$source_branch"; then
        if _merge_in_progress; then
          _wait_for_merge_resolution "$source_branch" "$target" "$pre_merge_head" || return 1
        else
          _log "Merge failed and no merge is in progress."
          return 1
        fi
      fi

      _run git push -u origin "$target" || return 1
    fi

    source_branch="$target"
  done

  _log "Completed successfully. Final branch: $(git branch --show-current)"
}
