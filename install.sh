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

# Colour only on a terminal, and never under NO_COLOR; every line still says what it is in words
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\e[1m' DIM=$'\e[2m' GREEN=$'\e[32m' YELLOW=$'\e[33m' RED=$'\e[31m' OFF=$'\e[0m'
else
    BOLD='' DIM='' GREEN='' YELLOW='' RED='' OFF=''
fi
todo=0
section() { printf '\n%s%s%s\n' "$BOLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %-17s %s\n' "$GREEN" "$OFF" "$1" "$2"; }
warn() { printf '  %s⚠%s %-17s %s\n' "$YELLOW" "$OFF" "$1" "$2"; todo=$((todo + 1)); }
fail() { printf '  %s✗%s %-17s %s\n' "$RED" "$OFF" "$1" "$2"; todo=$((todo + 1)); }
skip() { printf '  %s· %-17s %s%s\n' "$DIM" "$1" "$2" "$OFF"; }
hint() { printf '    %s%s%s\n' "$DIM" "$1" "$OFF"; }

# Moves a path aside without clobbering an earlier backup
backup() {
    local bak="$1.bak"
    if [ -e "$bak" ] || [ -L "$bak" ]; then bak="$1.bak.$(date +%s)"; fi
    mv "$1" "$bak"
    hint "backed up $1 → $bak"
}

# Copies a template into place unless something is already there; sets $seeded when it did
seed() {
    seeded=""
    if [ ! -e "$2" ] && [ ! -L "$2" ]; then (umask 077 && cp "$1" "$2"); seeded=" (just created)"; fi
}

printf '%s🌑 skills%s %sinstall%s\n' "$BOLD" "$OFF" "$DIM" "$OFF"

section "Links → ~/.claude"
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
    case $kind in
        skills) count="$(find "$REPO/skills" -name SKILL.md | wc -l | tr -d ' ') skills" ;;
        *) n=$(find "$REPO/$kind" -type f | wc -l | tr -d ' '); count="$n file$([ "$n" -eq 1 ] || echo s)" ;;
    esac
    ok "$kind" "$count linked"
done

section "Config → ~/.config/claude-skills"
mkdir -p "$CONFIG_DIR"
creds="$CONFIG_DIR/credentials.json"
seed "$REPO/credentials.example.json" "$creds"
if [ -L "$creds" ] && [ ! -e "$creds" ]; then
    fail credentials.json "broken link - fix or remove it, then re-run"
elif unset=$(jq -r --slurpfile tpl "$REPO/credentials.example.json" \
        '. as $c | $tpl[0] | keys[] | select(($c[.] // "") == "")' "$creds" 2>/dev/null); then
    total=$(jq 'length' "$REPO/credentials.example.json")
    missing_keys=$(printf '%s' "$unset" | grep -c . || true)
    if [ "$missing_keys" -eq 0 ]; then
        ok credentials.json "all $total keys set$seeded"
    else
        warn credentials.json "$((total - missing_keys)) of $total keys set$seeded"
        for group in "jira:/jira, /triage; ticket input for /gadfly, /forge, /duck, /nicepr, /aristarchus" \
                     "sentry:/sentry, /sentry-fix, /triage, /firewatch" \
                     "datadog:/firewatch (Datadog APM)" "jenkins:/firewatch (Jenkins jobs)" "opsgenie:/firewatch (Opsgenie alerts)"; do
            keys=$(printf '%s\n' "$unset" | grep "^${group%%:*}" | paste -sd, - | sed 's/,/, /g')
            if [ -n "$keys" ]; then hint "unset: $keys → ${group#*:}"; fi
        done
    fi
else
    fail credentials.json "not valid JSON"
fi

catalog="$CONFIG_DIR/services.md"
seed "$REPO/services.example.md" "$catalog"
if [ -L "$catalog" ] && [ ! -e "$catalog" ]; then
    fail services.md "broken link - fix or remove it, then re-run"
elif cmp -s "$REPO/services.example.md" "$catalog"; then
    warn services.md "still the template$seeded"
    hint "→ /sentry, /sentry-fix, /triage, /firewatch, the /aristarchus mutation check"
else
    unfilled=$(grep -c '<your ' "$catalog" || true)
    if [ "$unfilled" -eq 0 ]; then ok services.md "filled in"
    elif [ "$unfilled" -eq 1 ]; then ok services.md "filled in; 1 value still reads <your ...> (fine for a section you don't use)"
    else ok services.md "filled in; $unfilled values still read <your ...> (fine for sections you don't use)"; fi
fi

if [ -e "$CONFIG_DIR/voice.md" ]; then ok voice.md "your voice for /humanize"
else skip voice.md "optional: your voice for /humanize"; fi
if [ -e "$CONFIG_DIR/work.json" ]; then ok work.json "reviewers for /nicepr --create"
else skip work.json "optional: reviewers for /nicepr --create"; fi

section "Environment"
if [ -n "${WORKSPACE:-}" ]; then ok '$WORKSPACE' "$WORKSPACE"
else warn '$WORKSPACE' "unset - export it to your clones directory → /aristarchus, /triage, /sentry-fix"; fi
# The same local test gh makes before an API call: a token in the environment or a host in hosts.yml. gh auth token
# is no test, since it also finds a keyring token that gh api won't use; gh auth status needs the network.
if ! command -v gh >/dev/null; then warn gh "not installed → /aristarchus, /nicepr, /triage, /sentry-fix"
elif [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ] || grep -q '^[^[:space:]#]' "${GH_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/gh}/hosts.yml" 2>/dev/null; then
    ok gh "logged in"
else warn gh "not logged in - run gh auth login → /aristarchus, /nicepr, /triage, /sentry-fix"; fi

echo
if [ "$todo" -eq 0 ]; then
    printf '%s✓ Ready.%s Restart Claude Code to pick up new skills.\n' "$GREEN$BOLD" "$OFF"
else
    printf '%s⚠ %s things to set up%s - see "Install" in %s/README.md\n' "$YELLOW$BOLD" "$todo" "$OFF" "$REPO"
    printf 'Restart Claude Code to pick up new skills.\n'
fi
