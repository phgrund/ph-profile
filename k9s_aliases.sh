#!/usr/bin/env bash

K9S_CONTEXTS_FILE="$HOME/.ph-profile/k9s_contexts.csv"

load_k9s_aliases() {
    [ -f "$K9S_CONTEXTS_FILE" ] || return 0

    while IFS=',' read -r alias_name aws_profile cluster_context; do
        [ -n "$alias_name" ] || continue

        case "$alias_name" in
            \#*)
                continue
                ;;
        esac

        alias "$alias_name=k9s_sso $aws_profile $cluster_context"
    done < "$K9S_CONTEXTS_FILE"
}

load_k9s_aliases