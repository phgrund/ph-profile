sync_git_aliases() {
    local aliases_file line key value current_value
    aliases_file="$HOME/.ph-profile/git_aliases.gitconfig"

    command -v git >/dev/null 2>&1 || return 0
    [ -f "$aliases_file" ] || return 0

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        key=${line%% *}
        value=${line#* }

        current_value=$(git config --global --get "$key" 2>/dev/null)
        if [ "$current_value" != "$value" ]; then
            git config --global "$key" "$value"
        fi
    done < <(git config -f "$aliases_file" --get-regexp '^alias\.' 2>/dev/null)
}