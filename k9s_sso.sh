k9s_sso() {
  emulate -L zsh
  setopt localoptions pipefail

  _log() { print -r -- "[k9s_sso] $*"; }
  _run() {
    _log "$*"
    "$@"
  }
  _aws_credentials_ready() {
    command aws configure export-credentials \
      --profile "$PROFILE" \
      --format env-no-export >/dev/null 2>&1
  }

  local PROFILE="$1"
  local CONTEXT="$2"

  if [[ -z "$PROFILE" ]]; then
    _log "Usage: k9s_sso <aws-profile> [k8s-context]"
    return 1
  fi

  _log "Checking cached AWS credentials for profile: $PROFILE"

  if ! _aws_credentials_ready; then
    _log "No reusable AWS SSO session found. Running login..."
    _run aws sso login --profile "$PROFILE" || return 1

    if ! _aws_credentials_ready; then
      _log "AWS credentials are still unavailable after login"
      return 1
    fi
  fi

  if [[ -n "$CONTEXT" ]]; then
    _log "Starting k9s with context: $CONTEXT"
    exec env AWS_PROFILE="$PROFILE" k9s --context "$CONTEXT"
  else
    _log "Starting k9s without an explicit context"
    exec env AWS_PROFILE="$PROFILE" k9s
  fi
}
