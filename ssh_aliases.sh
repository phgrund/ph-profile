#!/usr/bin/env bash

SSH_HOSTS_FILE="$HOME/.ph-profile/ssh_hosts.csv"

load_ssh_aliases() {
    [ -f "$SSH_HOSTS_FILE" ] || return 0

    while IFS=',' read -r project pem_file ssh_target; do
        [ -n "$project" ] || continue

        case "$project" in
            \#*)
                continue
                ;;
        esac

        pem_file="${pem_file/#\~/$HOME}"
        alias "$project-ssh=ssh -i $pem_file -X $ssh_target"
    done < "$SSH_HOSTS_FILE"
}

load_ssh_aliases