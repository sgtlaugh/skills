#!/bin/bash
# install.sh - link skills, agents and hooks into ~/.claude, seed the config templates
#
# Usage: ./install.sh
#
# Re-run after every pull: links are per file, so new files need a new link.
# Anything in the way is backed up with a .bak extension. Config files are never overwritten.

set -e
command -v jq >/dev/null || { echo "jq is required: https://jqlang.github.io/jq/" >&2; exit 1; }

REPO="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config/claude-skills"

# Moves a path aside without clobbering an earlier backup
backup() {
    local bak="$1.bak"
    if [ -e "$bak" ] || [ -L "$bak" ]; then bak="$1.bak.$(date +%s)"; fi
    mv "$1" "$bak"
    echo "  Backed up $1 → $bak"
}

# Copies a template into place unless something is already there
seed() {
    local template="$1" dest="$2" note="$3"
    if [ -L "$dest" ] && [ ! -e "$dest" ]; then
        echo "  ⚠ $dest is a broken link - fix or remove it, then re-run"
    elif [ ! -e "$dest" ]; then
        (umask 077 && cp "$template" "$dest")
        echo "  Created $(basename "$dest")$note"
    fi
}

echo "Linking into ~/.claude:"
for kind in skills agents hooks; do
    base="$HOME/.claude/$kind"
    # A symlinked directory here or one level down would put our links inside another tree
    if [ -L "$base" ]; then backup "$base"; fi
    mkdir -p "$base"
    find "$REPO/$kind" -type f | while read -r src; do
        rel="${src#"$REPO/$kind/"}"
        dest="$base/$rel"
        top="$base/${rel%%/*}"
        if [ "$top" != "$dest" ] && [ -L "$top" ]; then backup "$top"; fi
        mkdir -p "$(dirname "$dest")"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then backup "$dest"; fi
        ln -sfn "$src" "$dest"
    done
    # A file deleted from the repo leaves a dangling link behind; links from other repos are left alone
    find "$base" -type l ! -exec test -e {} \; -print | while read -r link; do
        case "$(readlink "$link")" in "$REPO"/*) rm "$link" ;; esac
    done
    find "$base" -mindepth 1 -type d -empty -delete
    echo "  $kind ✓"
done

echo "Config in ~/.config/claude-skills:"
mkdir -p "$CONFIG_DIR"
seed "$REPO/services.example.md" "$CONFIG_DIR/services.md"
seed "$REPO/credentials.example.json" "$CONFIG_DIR/credentials.json" " (mode 600)"

# Printed every run, so setup that is still missing stays visible after the first install
echo "Setup still missing (see \"Set up what you use\" in $REPO/README.md):"
missing=0
if [ -e "$CONFIG_DIR/credentials.json" ]; then
    if unset=$(jq -r --slurpfile tpl "$REPO/credentials.example.json" \
        '. as $c | $tpl[0] | keys[] | select(($c[.] // "") == "")' "$CONFIG_DIR/credentials.json" 2>/dev/null); then
        for group in "jira:/jira, /triage, /lordvessel; ticket input for /gadfly, /forge, /duck, /nicepr, /aristarchus" \
                     "sentry:/sentry, /sentry-fix, /triage, /firewatch" \
                     "datadog:/firewatch (Datadog APM)" "jenkins:/firewatch (Jenkins jobs)" "opsgenie:/firewatch (Opsgenie alerts)"; do
            keys=$(printf '%s\n' "$unset" | grep "^${group%%:*}" | paste -sd, - | sed 's/,/, /g')
            if [ -n "$keys" ]; then echo "  ⚠ unset in credentials.json: $keys → ${group#*:}"; missing=1; fi
        done
    else
        echo "  ⚠ $CONFIG_DIR/credentials.json is not valid JSON"; missing=1
    fi
fi
if cmp -s "$REPO/services.example.md" "$CONFIG_DIR/services.md"; then
    echo "  ⚠ services.md is still the template → /sentry, /sentry-fix, /triage, /firewatch, /lordvessel, the /aristarchus mutation check"; missing=1
fi
if [ -z "${WORKSPACE:-}" ]; then
    echo "  ⚠ \$WORKSPACE is unset (your clones directory) → /aristarchus, /triage, /sentry-fix"; missing=1
fi
if [ "$missing" -eq 0 ]; then echo "  none"; fi

echo "✓ Done. Restart Claude Code to pick up new skills."
