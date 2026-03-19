# Load environment variables and aliases from .env
if [ -f "$HOME/.ph-profile/.env" ]; then
    source "$HOME/.ph-profile/.env"
fi

# Make all .sh files executable
for script in "$HOME/.ph-profile"/*.sh; do
    [ -f "$script" ] || continue
    [ "$script" = "$HOME/.ph-profile/main.sh" ] && continue
    chmod +x "$script"
    source "$script"
done

sync_git_aliases

# Add to PATH
export PATH="$HOME/.ph-profile:$PATH"

