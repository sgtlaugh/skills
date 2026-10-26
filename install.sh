#!/bin/bash
# install.sh - link skills, agents and hooks into ~/.claude, seed the config templates
#
# Usage: ./install.sh
#
# Re-run after every pull: links are per file, so new files need a new link.
# Existing non-link files are backed up with a .bak extension. Config files are never overwritten.

set -e

REPO="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-skills"

echo "Linking into ~/.claude:"
for kind in skills agents hooks; do
    find "$REPO/$kind" -type f | while read -r src; do
        dest="$HOME/.claude/$kind/${src#"$REPO/$kind/"}"
        mkdir -p "$(dirname "$dest")"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            mv "$dest" "$dest.bak"
            echo "  Backed up $dest → $dest.bak"
        fi
        ln -sf "$src" "$dest"
    done
    # A file deleted from the repo leaves a dangling link behind
    find "$HOME/.claude/$kind" -xtype l -delete
    find "$HOME/.claude/$kind" -mindepth 1 -type d -empty -delete
    echo "  $kind ✓"
done

echo "Config in ~/.config/claude-skills:"
mkdir -p "$CONFIG_DIR"
if [ ! -e "$CONFIG_DIR/services.md" ]; then
    cp "$REPO/services.example.md" "$CONFIG_DIR/services.md"
    echo "  Created services.md - fill it in for sentry, triage and firewatch"
fi
if [ ! -e "$CONFIG_DIR/credentials.json" ]; then
    (umask 077 && cp "$REPO/credentials.example.json" "$CONFIG_DIR/credentials.json")
    echo "  Created credentials.json (mode 600)"
fi
unset_count=$(jq '[.[] | select(. == null)] | length' "$CONFIG_DIR/credentials.json")
[ "$unset_count" -gt 0 ] && echo "  ⚠ $unset_count credential(s) unset in $CONFIG_DIR/credentials.json"

echo "✓ Done. Restart Claude Code to pick up new skills."
