k9s_sso() {
  emulate -L zsh
  setopt localoptions pipefail

  _log() { print -r -- "[k9s_sso] $*"; }
  _run() {
    _log "$*"
    "$@"
  }

  local PROFILE="$1"
  local CONTEXT="$2"

  if [[ -z "$PROFILE" ]]; then
    _log "Usage: k9s_sso <aws-profile> [k8s-context]"
    return 1
  fi

  _log "Checking AWS SSO session for profile: $PROFILE"

  if ! AWS_PROFILE=$PROFILE aws sts get-caller-identity >/dev/null 2>&1; then
    _log "SSO session expired. Running login..."
    _run env AWS_PROFILE=$PROFILE aws sso login || return 1
  fi

  if [[ -n "$CONTEXT" ]]; then
    _log "Starting k9s with context: $CONTEXT"
    exec command k9s --context "$CONTEXT"
  else
    _log "Starting k9s without an explicit context"
    exec command k9s
  fi
}