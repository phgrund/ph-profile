#!/usr/bin/env bash

K9S_CONTEXTS_FILE="$HOME/.ph-profile/k9s_contexts.csv"

load_k9s_aliases() {
    [ -f "$K9S_CONTEXTS_FILE" ] || return 0

    while IFS= read -r alias_cmd; do
        [ -n "$alias_cmd" ] || continue
        eval "$alias_cmd"
    done <<EOF
$(awk -F',' '
BEGIN { OFS="," }
NR==1 && $1 ~ /^#/ { next }
$1 ~ /^#/ { next }
{
    gsub("\r", "", $1); gsub("\r", "", $2); gsub("\r", "", $3);
    if (length($1) > 0) {
        gsub(/"/, "\\\"", $2); gsub(/"/, "\\\"", $3);
        print "alias " $1 "=\"k9s_sso " $2 " " $3 "\""
    }
}' "$K9S_CONTEXTS_FILE")
EOF
}

load_k9s_aliases