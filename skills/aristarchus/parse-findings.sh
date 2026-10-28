#!/usr/bin/env bash
# parse-findings.sh - read an aristarchus review and check or extract its findings
#
# Usage: parse-findings.sh [--check] [file]   (stdin without a file)
#   (default)  print the findings as a JSON array:
#              {n, severity, tag, where, pre_existing, verification, text}
#              verification is "verified", "weak", "unresolved" or "none"
#   --check    check the review against the output format in references/output-example.md;
#              prints each problem, or "parse-findings: ok". Exit 0 = ok, 1 = problems, 2 = usage.
#
# The format this reads (SKILL.md Step 9):
#   finding header   <emoji>  **#N · <critical|warning|nit> · <Tag> · <path:line>[ · pre-existing]**
#   verification     a closing line ending in (verified), (weak) or (unresolved) when darkmoon ran
#   findings list    <emoji>  #N  <path:line>   in the findings summary, one per detailed finding
#   header line      **Verified**: N claims via darkmoon - U upheld, W weak, C can't-determine, R refuted
# aristarchus runs --check on its own draft before printing it; pr-watch reads the JSON.

check=false
[ "${1:-}" = --check ] && { check=true; shift; }
[ "${1:-}" = -h ] || [ "${1:-}" = --help ] && { sed -n '2,17p' "$0"; exit 0; }
review=$(cat "${1:-/dev/stdin}") || exit 2

CHECK=$check perl -CSD -0777 -ne '
    use strict; use warnings;
    my $r = $_;
    my %emoji = (critical => "\x{1F6D1}", warning => "\x{26A0}", nit => "\x{270F}");
    my (@f, @problems);

    # Detailed findings: a header line, then everything up to the next header or a --- line
    my @lines = split /\n/, $r, -1;
    my $cur;
    for my $line (@lines) {
        if ($line =~ /\*\*#(\d+) \x{b7} /) {
            if ($line =~ /^(\S+)\s+\*\*#(\d+) \x{b7} (critical|warning|nit) \x{b7} ([^\x{b7}*]+?) \x{b7} ([^\x{b7}*]+?)( \x{b7} pre-existing)?\*\*\s*$/) {
                $cur = {lead => $1, n => $2 + 0, severity => $3, tag => $4, where => $5,
                        pre_existing => ($6 ? \1 : \0), text => "$line\n"};
                push @f, $cur;
                next;
            }
            push @problems, "finding header not in the format \"<emoji>  **#N \x{b7} <critical|warning|nit> \x{b7} <Tag> \x{b7} <path:line>**\": $line";
            undef $cur; next;
        }
        if ($line =~ /^---\s*$/) { undef $cur; next }
        $cur->{text} .= "$line\n" if $cur;
    }
    for my $x (@f) {
        my @marks = $x->{text} =~ /\((verified|weak|unresolved)\)/g;
        $x->{verification} = @marks ? $marks[-1] : "none";
        $x->{text} =~ s/\s+$//;
    }

    if ($ENV{CHECK} eq "true") {
        my %seen;
        for my $x (@f) {
            push @problems, "finding #$x->{n} appears twice" if $seen{$x->{n}}++;
            my $want = $emoji{$x->{severity}};
            push @problems, "finding #$x->{n} is $x->{severity} but leads with \"$x->{lead}\" (use $want)" if index($x->{lead}, $want) < 0;
        }
        # The findings summary lists every detailed finding by number, and nothing else
        my ($summary) = $r =~ /\*\*Findings summary\*\*(.*?)(?=\n---\s*\n)/s;
        if (defined $summary) {
            my %listed = map { $_ => 1 } $summary =~ /^\S+\s+#(\d+)\b/mg;
            my %detailed = map { $_->{n} => 1 } @f;
            push @problems, "finding #$_ is in the summary list but has no detailed finding" for grep { !$detailed{$_} } sort { $a <=> $b } keys %listed;
            push @problems, "finding #$_ has no line in the summary list" for grep { !$listed{$_} } sort { $a <=> $b } keys %detailed;
        } elsif (@f) {
            push @problems, "no **Findings summary** section before the detailed findings";
        }
        # When darkmoon ran, every finding carries its verdict and the counts match the header line
        if ($r =~ /\*\*Verified\*\*:?\s*(\d+) claims?\b[^\n]*?(\d+) upheld[^\n]*?(\d+) weak/) {
            my ($upheld, $weak) = ($2, $3);
            push @problems, "finding #$_->{n} has no (verified), (weak) or (unresolved) marker" for grep { $_->{verification} eq "none" } @f;
            my $v = grep { $_->{verification} eq "verified" } @f;
            my $w = grep { $_->{verification} eq "weak" } @f;
            push @problems, "header says $upheld upheld but $v findings are marked (verified)" if $v != $upheld;
            push @problems, "header says $weak weak but $w findings are marked (weak)" if $w != $weak;
        }
        print "$_\n" for @problems;
        print "parse-findings: ok\n" unless @problems;
        exit(@problems ? 1 : 0);
    }

    # JSON out, by hand: no module dependencies
    sub js { my $s = shift; $s =~ s/(["\\])/\\$1/g; $s =~ s/\n/\\n/g; $s =~ s/\t/\\t/g; $s =~ s/([\x00-\x1f])/sprintf("\\u%04x", ord $1)/ge; "\"$s\"" }
    print "[", join(",", map {
        sprintf "{\"n\":%d,\"severity\":%s,\"tag\":%s,\"where\":%s,\"pre_existing\":%s,\"verification\":%s,\"text\":%s}",
            $_->{n}, js($_->{severity}), js($_->{tag}), js($_->{where}), (${$_->{pre_existing}} ? "true" : "false"), js($_->{verification}), js($_->{text})
    } @f), "]\n";
    exit(@problems ? 1 : 0);
' <<<"$review"
