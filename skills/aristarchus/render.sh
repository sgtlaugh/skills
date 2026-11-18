#!/usr/bin/env bash
# render.sh <review file>: prints a finished aristarchus review in the short reader layout, verdict first.
# It only reorders and trims the review, which stays the record, and never drops a finding to fix.
set -uo pipefail
f="${1:-}"
[ -r "$f" ] || { echo "usage: render.sh <review file>" >&2; exit 2; }

perl -CSD -0777 -ne '
    use strict; use warnings;
    my $r = $_;
    sub field { my ($label) = @_; $r =~ /\*\*\Q$label\E\*\*:?\s*:?\s*([^|\n]*?)\s*(?:\||\n)/ ? $1 : "" }
    sub line_of { my ($label) = @_; $r =~ /^\*\*\Q$label\E(?:\*\*:|:\*\*)\s*([^\n]*)/m ? $1 : "" }
    my ($n, $title) = $r =~ /^\*\*Review: PR #(\d+) - ([^\n]*?)\*\*\s*$/m;
    my $author = field("Author");
    my $files = field("Files");
    $files =~ s/^(\d+) changed \(\+(\d+), -(\d+)\)/$1 files (+$2 \x{2212}$3)/;
    my $ci = field("CI");
    my $jira = field("JIRA");
    my ($ticket) = $jira =~ /^([A-Z][A-Z0-9]+-\d+)/;
    my $does = line_of("What this PR does");
    my $rec = line_of("Recommendation");
    my $reason = line_of("Reason");
    $rec =~ s/Request Changes/Request changes/;

    # The findings as the parser reads them: a header, then its text up to the next header, --- or section
    my @f;
    my ($cur, $fence) = (undef, 0);
    for my $line (split /\n/, $r) {
        if ($line =~ /^\s*(```|~~~)/) { $fence = !$fence; $cur->{body} .= "$line\n" if $cur; next }
        if ($fence) { $cur->{body} .= "$line\n" if $cur; next }
        if ($line =~ /^\*\*(Independent Review Lenses|Library Source Tracing|Cross-Repo Analysis|Summary|Recommendation|Finding synthesis|Notes)\b/) { undef $cur; next }
        if ($line =~ /^(\S+)\s+\*\*#(\d+) \x{b7} (critical|warning|nit) \x{b7} ([^\x{b7}*]+?) \x{b7} ([^\x{b7}*]+?)( \x{b7} pre-existing)?\*\*\s*$/) {
            $cur = {head => $line, sev => $3, pre => ($6 ? 1 : 0), body => ""}; push @f, $cur; next;
        }
        if ($line =~ /^---\s*$/) { undef $cur; next }
        $cur->{body} .= "$line\n" if $cur;
    }

    # The evidence line becomes a marker; which agent raised or checked a finding stays in the full review
    sub marker {
        my ($b) = @_;
        my ($ev, $v) = $b =~ /^\*(?:Confirmed|Inferred)\s*-\s*(.*?)\.?\*\s*(?:\((verified|weak|unresolved)\))?\s*$/m;
        return "" unless defined $ev;
        $ev =~ s/\s*(?:Raised|Found|Flagged) by [^.]*(?:\.|$)//gi;
        $ev =~ s/\s*\S*(?:darkmoon|lens)[^.]*(?:\.|$)//gi;
        $ev = plain($ev); $ev =~ s/\s+$//; $ev = substr($ev, 0, 140) . "..." if length $ev > 143;
        my %sym = (verified => "\x{2713} confirmed", weak => "~ weak", unresolved => "? unsure");
        return $ev eq "" ? "" : "\x{b7} $ev" unless $v;
        return $ev eq "" ? $sym{$v} : "$sym{$v} \x{b7} $ev";
    }
    # The reader never needs the names of the agents behind a finding, only what was checked
    sub plain {
        my ($s) = @_;
        my $role = qr/(?:saboteur|simplifier|reader|security|operator)/i;
        $s =~ s/\b(?:the )?(?:skeptic|darkmoon)(?:.s)? (?:counter|caveat)(?: (?:on|above)[^:]*)?:/On the other hand,/gi;
        $s =~ s/\bdarkmoon (upheld|confirmed)\b/an independent check confirmed/gi;
        $s =~ s/\b(?:the )?(?:skeptic|darkmoon)([\x27\x{2019}]s)?\b/"the independent check" . ($1 ? "\x{2019}s" : "")/gie;
        $s =~ s/\b(?:the |a )?$role(?:(?:,| and)(?: the)? $role)* lens(?:es)?\b/a second review angle/gi;
        $s =~ s/\blens(es)?\b/"review angle" . ($1 ? "s" : "")/gie;
        $s;
    }
    sub one { my ($s) = @_; $s =~ s/\s+/ /g; $s =~ s/^\s+|\s+$//g; plain($s) }

    my (@fix, @also, @small);
    for my $x (@f) {
        my $b = $x->{body};
        if ($x->{sev} eq "nit") {
            (my $t = $b) =~ s/^\*(?:Confirmed|Inferred)[^\n]*\n?//mg;
            push @small, $x->{head} . " " . one($t) . " " . marker($b);
            next;
        }
        my ($prob) = $b =~ /\*\*Problem:\*\*\s*(.*?)(?=\n\*\*Impact:\*\*|\n\n|\z)/s;
        my ($imp) = $b =~ /\*\*Impact:\*\*\s*(.*?)(?=\n\n|\n\*\*Fix|\z)/s;
        my ($fix) = $b =~ /\*\*Fix:\*\*\s*(.*?)(?=\n\*(?:Confirmed|Inferred)|\z)/s;
        my @out = ($x->{head});
        if (defined $prob || defined $imp) {
            push @out, one($imp) if defined $imp;
            push @out, one($prob) if defined $prob;
        } else {
            (my $t = $b) =~ s/^\*(?:Confirmed|Inferred)[^\n]*\n?//mg;
            push @out, one($t);
        }
        if (defined $fix) {
            $fix =~ s/^\s+|\s+$//g;
            if ($fix =~ /^(?:```|~~~)/) { push @out, "\x{2192} Fix:", "", $fix, "" }
            elsif ($fix =~ /^(.*?)\n\n((?:```|~~~).*)$/s) { push @out, "\x{2192} " . one($1), "", $2, "" }
            else { push @out, "\x{2192} " . one($fix) }
        }
        push @out, marker($b);
        my ($in) = (0);
        my $block = join("\n", map { my $l = $_; $in = !$in if $l =~ /^\s*(```|~~~)/; $in || $l =~ /^\s*(```|~~~)/ ? $l : plain($l) } map { split /\n/, $_, -1 } @out);
        if ($x->{pre} && $x->{sev} ne "critical") { push @also, $block } else { push @fix, $block }
    }

    my @o;
    push @o, "**PR #$n \x{b7} $title**" if defined $n;
    push @o, join(" \x{b7} ", grep { $_ ne "" } ($author, $files, ($ci ne "" ? "CI $ci" : ""), $ticket // "")), "";
    push @o, "**What it does:** $does", "" if $does ne "";
    push @o, "**Verdict:** $rec" . ($reason ne "" ? ". $reason" : ""), "" if $rec ne "";
    push @o, "**Fix before merge (" . @fix . ")**", "", join("\n\n", @fix), "" if @fix;
    push @o, "**Also worth knowing (" . @also . ")**", "", join("\n\n", @also), "" if @also;
    if (@small) {
        my $shown = @small > 3 ? 3 : scalar @small;
        push @o, "**Small things ($shown)**", "", @small[0 .. $shown - 1];
        push @o, "+" . (@small - 3) . " more in the full review" if @small > 3;
        push @o, "";
    }

    # Footer: how the review ran, in plain words
    my $verified = line_of("Verified");
    my $checked = $verified;
    if ($verified =~ /(\d+) claims via darkmoon - (\d+) upheld, (\d+) weak, (\d+) can.t-determine, (\d+) refuted/) {
        $checked = "$1 points by an independent read - $2 confirmed, $3 weak, $4 unsure, $5 dropped as wrong";
    }
    my $ran = line_of("Agents");
    $ran =~ s/\blenses (\d+\/\d+)/$1 review angles/; $ran =~ s/\blenses\b/review angles/g; $ran =~ s/\s*\|\s*/ \x{b7} /g;
    my $comments = field("Existing comments");
    $comments =~ s/^(\d+) fetched \((\d+) deduped\)/$1 existing comments ($2 already raised)/ or $comments = $comments ne "" ? "$comments existing comments" : "";
    my @read = grep { $_ ne "" } (field("Conventions"), $comments, ($jira ne "" ? "ticket $jira" : ""), field("Filtered"));
    my ($not) = $r =~ /Not examined:?\s*(.*?)(?=\n\n|\n\*\*|\z)/s;
    ($not) = $r =~ /(?:^|\s)([^.\n]*not examined[^.\n]*\.)/i unless defined $not;
    my ($time) = $r =~ /\*\*Time taken\*\*:?\s*([^\n]+)/;
    push @o, "---", "";
    push @o, "**Checked:** $checked" if $checked ne "";
    push @o, "**Ran:** $ran" if $ran ne "";
    push @o, "**Read:** " . join(" \x{b7} ", @read) if @read;
    if (defined $not) { $not =~ s/^\s*-\s*//; $not =~ s/\n\s*-\s*/; /g; $not = one($not) }
    push @o, "**Not checked:** $not" if defined $not && $not ne "";
    push @o, "**Confidence:** " . plain(line_of("Confidence")) if line_of("Confidence") ne "";
    push @o, "**Time:** $time" if defined $time;
    print join("\n", @o), "\n";
' "$f"
