#!/usr/bin/env bash
# voice-gate.sh - mechanical gate for text about to be posted on GitHub (see references/github-voice.md)
#
# Usage: voice-gate.sh [--max-chars N] [file]   (stdin when no file)
#   A JSON array of objects with a "body" (review comments) is checked per comment, plus the 5-comment cap.
#   Anything else is one comment.
# Exit 0 = clean (prints "voice-gate: clean"), 1 = violations (one per line on stdout), 2 = usage error.

max=600
while [ $# -gt 0 ]; do
    case "$1" in
        --max-chars) max="$2"; shift 2 ;;
        -h|--help) sed -n '2,8p' "$0"; exit 0 ;;
        *) break ;;
    esac
done
case "$max" in ''|*[!0-9]*) echo "voice-gate: --max-chars needs a number" >&2; exit 2 ;; esac

input=$(cat "${1:-/dev/stdin}") || exit 2
banned="$(dirname "$0")/references/banned-list.md"
[ -r "$banned" ] || { echo "voice-gate: can't read $banned" >&2; exit 2; }

json=false; count=1
if jq -e 'type == "array"' <<<"$input" >/dev/null 2>&1; then json=true; count=$(jq length <<<"$input"); fi

# NUL-separated bodies; a shell variable can't hold NUL, so this streams straight into perl
emit() {
    if $json; then jq -j '.[] | (.body // "") + "\u0000"' <<<"$input"; else printf '%s\0' "$input"; fi
}

emit | MAX="$max" COUNT="$count" BANNED="$banned" perl -CSD -0 -ne '
    BEGIN {
        our @phrases;
        open my $fh, "<:encoding(UTF-8)", $ENV{BANNED} or die "voice-gate: $ENV{BANNED}: $!\n";
        my $section = "";
        local $/ = "\n";
        while (<$fh>) {
            $section = $1 if /^## (.+)/;
            next unless $section =~ /^(Phrases to delete|Self-narration)/ && /^"/;
            for my $p (split m{\s*/\s*}) {
                $p =~ s/^"|"$//g; $p =~ s/\.\.\.$//; $p =~ s/\s*\(.*?\)\s*$//;
                $p =~ s/^\s+|\s+$//g;
                next unless length $p;
                my $re = join "\\S*(?:\\s+\\S+)*?\\s+", map { quotemeta } grep { length } split /\s*\[[^\]]*\]\s*/, $p;
                push @phrases, [$p, qr/(?<![\w])$re(?![\w])/i];
            }
        }
        our $n = 0; our $bad = 0;
        if ($ENV{COUNT} > 5) { print "all: $ENV{COUNT} inline comments (max 5) - keep the five that change the merge decision\n"; $bad = 1 }
    }
    chomp; $n++;
    my $body = $_;
    my $tag = $ENV{COUNT} > 1 ? "comment $n" : "comment";
    my @v;

    # Walk fences once: language, length, <details> wrapping, suggestion size
    my ($in, $lang, $lines, $details, $prose) = (0, "", 0, 0, "");
    for my $line (split /\n/, $body, -1) {
        if (!$in && $line =~ /^\s*(`{3,}|~{3,})\s*(\S*)/) {
            ($in, $lang, $lines) = (1, $2, 0);
            push @v, "code fence without a language (use ```text for plain output)" unless length $lang;
            next;
        }
        if ($in) {
            if ($line =~ /^\s*(`{3,}|~{3,})\s*$/) {
                $in = 0;
                push @v, "$lines-line code block outside <details> (over 15 lines goes in <details><summary>)" if $lines > 15 && !$details;
                push @v, "$lines-line suggestion block (suggestions are for fixes of 3 lines or fewer)" if $lang eq "suggestion" && $lines > 3;
            } else { $lines++ }
            next;
        }
        $details++ if $line =~ /<details>/i;
        $details-- if $line =~ m{</details>}i && $details > 0;
        $prose .= "$line\n";
    }
    push @v, "unclosed code fence" if $in;

    push @v, "em dash (use a hyphen)" if $body =~ /\x{2014}/;
    if ($body =~ m{github\.com/[^/\s]+/[^/\s]+/(?:blob|tree)/([^/\s#)]+)}) {
        my @refs = $body =~ m{github\.com/[^/\s]+/[^/\s]+/(?:blob|tree)/([^/\s#)]+)}g;
        push @v, "permalink pinned to \"$_\", not a commit SHA" for grep { !/^[0-9a-f]{7,40}$/ } @refs;
    }

    (my $text = $prose) =~ s/`[^`\n]+`//g;
    $text =~ s{<summary>.*?</summary>}{}gis;
    $text =~ s{https?://\S+}{}g;
    $text =~ s{\]\([^)]*\)}{]}g;

    my $len = length($prose =~ s/\s+$//r);
    push @v, "$len characters of prose (max $ENV{MAX}) - cut to the fact and the question" if $len > $ENV{MAX};
    push @v, "heading \"$1\" (comments are paragraphs)" if $text =~ /^(#{1,6}\s.*)$/m;
    push @v, "emoji \"$1\"" if $text =~ /([\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B50}\x{2B06}\x{2934}\x{2935}\x{3030}\x{FE0F}])/;
    push @v, "severity tag \"$1\" (only **Minor nit:** is used)" if $text =~ /(\[(?:critical|warning|blocker|major|minor|nit|info|suggestion)\]|\*\*(?:critical|warning|blocker|major|severity)[^*]*\*\*)/i;
    push @v, "praise filler \"$1\"" if $text =~ /\b(great (?:job|work|catch|question|pr|change)|nice (?:job|work|catch)|well done|kudos|awesome work|excellent work)\b/i;
    push @v, "contrast framing \"$1\"" if $text =~ /\b(it.?s not\b[^.\n]{1,80}?[,;.]\s*it.?s\b|not (?:just|only)\b[^.\n]{1,80}?\bbut\b)/i;
    for my $id ($text =~ /(?<![\w.\/-])([a-z][a-z0-9]*_[a-z0-9_]+|[a-z]+[A-Z][A-Za-z0-9]*|\w+\(\)|[\w\/-]+\.(?:py|ts|tsx|js|go|rb|sh|md|json|ya?ml|toml|sql))(?![\w\/-])/g) {
        push @v, "identifier \"$id\" outside backticks";
    }
    # References must be clickable: a file:line as a link to the blob, a PR in another repo as owner/repo#N
    # (GitHub autolinks only that form). Code spans count here: `a.py:12` in backticks is still not a link.
    (my $unlinked = $prose) =~ s/\[[^\]\n]*\]\([^)\s]*\)//g;
    $unlinked =~ s{https?://\S+}{}g;
    push @v, "file reference \"$1\" is not a link - link it to the blob at a commit SHA" while $unlinked =~ /(?<![\w\/.-])([\w\/.-]+\.[A-Za-z0-9]{1,6}:L?\d+(?:-L?\d+)?)\b/g;
    (my $refs = $unlinked) =~ s/`[^`\n]+`//g;
    push @v, "reference \"$1\" needs its owner (owner/$1) to link" while $refs =~ /(?<![\w\/.-])((?!(?:PR|pr|issue|Issue)#)[A-Za-z][\w.-]*#\d+)\b/g;
    for my $p (our @phrases) { push @v, "banned phrase \"$p->[0]\"" if $text =~ $p->[1] }

    # Variety across one review: openings repeated comment to comment read as a template, and an
    # interjection is human once and a tic twice. "Well," as an opener reads as talking down.
    our (%opening, $interjections);
    (my $lead = $text) =~ s/^[\s*_>]+//;
    my $open = lc join " ", (split /\s+/, $lead =~ s/[^\w\s@\x27-]//gr)[0, 1];
    if (length $open > 2 && $ENV{COUNT} > 1) {
        push @v, "opens like comment $opening{$open} (\"$open ...\") - vary the openings" if $opening{$open};
        $opening{$open} //= $n;
    }
    push @v, "\"Well,\" as an opener reads as talking down" if $lead =~ /^well,/i;
    my @ij = $text =~ /(?:^|[.!?]\s+|\n)(hmm+|ahh?|oh|ooh|huh)\b[,.!]/gi;
    $interjections += @ij;
    push @v, "interjection \"$ij[-1]\" makes $interjections in one review (one at most)" if @ij && $interjections > 1;

    my %seen;
    for (grep { !$seen{$_}++ } @v) { print "$tag: $_\n"; $bad = 1 }
    END { print "voice-gate: clean\n" unless $bad; exit($bad ? 1 : 0) }
'
