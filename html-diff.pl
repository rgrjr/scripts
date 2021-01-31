#!/usr/bin/perl
#
# Hack to make sense of HTML diffs.
#
# [created.  -- rgr, 5-Jun-18.]
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

my $help = 0;
my $man = 0;
my $usage = 0;
my $match_score = 4;
my $mis_score = -4;
my $gap_start = 10;
my $gap_extend = 2;
my $max_line_length = 80;
my $verbose_p = 0;
my $test_split_p = 0;

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose|v+' => \$verbose_p,
	   'line-length=i' => \$max_line_length,
	   'test-split!' => \$test_split_p)
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

### Subroutines.

sub split_html_tokens {
    # Given string, return a list of tokens such that (a) each token is either
    # a tag (defined as a "<", the next unquoted ">", and everything in
    # between) or pure text (not containing tags), and (b) joining them back
    # together produces the original string, i.e. we don't do anything special
    # with whitespace.  An unmatched quote in a tag or a tag broken across a
    # line will not be handled correctly, but also without complaint.
    my ($line) = @_;

    my @tokens;
    my $in_quote_p = 0;
    my $in_tag_p = 0;
    my $token = '';
    for my $frag (split(/([<>""''])/, $line)) {
	if ($frag eq '<' && ! $in_quote_p) {
	    push(@tokens, $token)
		if length($token);
	    $token = $frag;
	    $in_tag_p = 1;
	}
	elsif ($frag eq '>' && ! $in_quote_p) {
	    $token .= $frag;
	    # Don't finish the token if we have a stray ">".
	    if ($in_tag_p) {
		push(@tokens, $token);
		$token = '';
	    }
	    $in_tag_p = 0;
	}
	elsif ($in_tag_p && ($frag eq q{'} || $frag eq q{"})) {
	    # Note that quotes are only interesting if we're in a tag, and not
	    # in the other kind of quote.
	    if ($in_quote_p eq $frag) {
		$in_quote_p = 0;
	    }
	    elsif (! $in_quote_p) {
		$in_quote_p = $frag;
	    }
	    $token .= $frag;
	}
	else {
	    $token .= $frag;
	}
    }
    push(@tokens, $token)
	if length($token);
    return @tokens;
}

sub minimize {
    # Do a global alignment on the passed token arrays, printing the minimized
    # diff output by side effect.
    my ($removed, $added) = @_;
    warn "minimize:  ", scalar(@$removed), ' vs ', scalar(@$added), "\n"
	if $verbose_p;

    my $build_lines = sub {
	# Given an arrayref of tokens, return a list of lines which do not go
	# over $max_line_length-1 (the "-1" is for the prefix "+" or "-", which
	# is not included), except that tokens are never broken over lines.
	my ($tokens) = @_;

	my @lines;
	my $line_so_far = '';
	my $max = $max_line_length-1;
	for my $token (@$tokens) {
	    if (length($line_so_far) + length($token) > $max) {
		push(@lines, $line_so_far)
		    if $line_so_far;
		$line_so_far = $token;
	    }
	    else {
		$line_so_far .= $token;
	    }
	}
	push(@lines, $line_so_far)
	    if $line_so_far;
	return @lines;
    };

    my $print_tokens = sub {
	# $dir is "+" or "-", and @tokens is a nonempty list of tokens, which
	# may include newlines.  We assume that we start on a fresh line, and
	# always end by outputting a newline.
	my ($dir, @tokens) = @_;

	my $prefix = $dir;
	my $column = 0;
	for my $token (@tokens) {
	    # Look for newlines in tokens so we can reset $column and $prefix.
	    for my $subtoken (split(/(\n)/, $token)) {
		if ($column && $max_line_length > 0 && $subtoken ne "\n"
		    && $column + length($subtoken) > $max_line_length) {
		    # This token is too long, so we must start a new line.
		    # Check for nonzero column first, because there's no point
		    # if we're already on a new line (and that also means we
		    # don't have to check the prefix length).
		    print "\n";
		    ($column, $prefix) = (0, $dir);
		}
		print $prefix, $subtoken;
		if ($subtoken  eq "\n") {
		    # We started a new line anyway.
		    ($column, $prefix) = (0, $dir);
		}
		else {
		    # Advance to a new column and scrub the prefix.
		    $column += length($prefix) + length($subtoken);
		    $prefix = '';
		}
	    }
	}
	print "\n"
	    if $column;
    };

    if (! @$removed || ! @$added) {
	# If one or the other token array is empty, then the score matrix will
	# be empty and the traceback will fail, so just cut to the chase.
	$print_tokens->('-', @$removed)
	    if @$removed;
	$print_tokens->('+', @$added)
	    if @$added;
	return;
    }

    my (@scores, @choices);
    my $score_at = sub {
	my ($i, $j) = @_;

	return 0
	    if $i < 0 || $j < 0;
	my $value = $scores[$i][$j];
	die "$0:  No score at [$i][$j]"
	    unless defined $value;
	return $value;
    };

    my $traceback;
    $traceback = sub {
	# Recursively find the optimum trace based on the @choices array,
	# printing the minimized diff output by side effect.
	my ($i, $j) = @_;

	return
	    if $i < 0 || $j < 0;
	my $choice = $choices[$i][$j];
	warn "  choice $choice at [$i][$j]\n"
	    if $verbose_p;
	if ($choice == 0) {
	    # Consolidate all diffs with the same match state.
	    my $state = $added->[$i] eq $removed->[$j];
	    my $add = $added->[$i];
	    my $rem = $removed->[$j];
	    my $span = 1;
	    while ($span <= $i && $span <= $j
		   && $choices[$i-$span][$j-$span] == 0
		   && $state == ($added->[$i-$span] eq $removed->[$j-$span])) {
		$add = $added->[$i-$span] . $add;
		$rem = $removed->[$j-$span] . $rem;
		$span++;
	    }
	    # Do the traceback from before the matching span.
	    warn "span $span at [$i][$j] state '$state'"
		if $verbose_p > 1;
	    $traceback->($i-$span, $j-$span);
	    if ($state == 1) {
		# Matching all the way.
		$print_tokens->(' ', @{$removed}[$j-$span+1 .. $j]);
	    }
	    else {
		$print_tokens->('-', @{$removed}[$j-$span+1 .. $j]);
		$print_tokens->('+', @{$added}[$i-$span+1 .. $i]);
	    }
	}
	elsif ($choice > 0) {
	    $traceback->($i, $j-$choice);
	    $print_tokens->('-', @{$removed}[$j-$choice+1 .. $j]);
	}
	else { # ($choice < 0)
	    $traceback->($i+$choice, $j);
	    $print_tokens->('+', @{$added}[$i+$choice+1 .. $i]);
	}
    };

    ## Main code of minimize.

    # First drop matching trailing newlines, which will be isolated if they
    # appear after markup.  These will necessarily match each other and get
    # reported separately if the last markup tokens are mismatched, which makes
    # it look like there was an extra blank line in the input.  Better to
    # remove them here and let $print_tokens reinstate them on output.
    pop(@$removed), pop(@$added)
	if ($removed->[@$removed - 1] eq "\n"
	    && $added->[@$added - 1] eq "\n");

    # Do a global alignment of the token arrays.
    my $add_len = @$added;
    my $rem_len = @$removed;
    for my $a (0 .. $add_len-1) {
	for my $r (0 .. $rem_len-1) {
	    my $score
		= $added->[$a] eq $removed->[$r] ? $match_score : $mis_score;
	    my $best = $score + $score_at->($a-1, $r-1);
	    my $best_choice = 0;
	    # Look for insertions in $a (the hard way).
	    my $best_gapped = -9999;
	    my $gap_penalty = -$gap_start;
	    my $rg = $r-1;
	    my $gap_choice;
	    while ($rg >= 0) {
		my $gapped = $score_at->($a, $rg) + $gap_penalty;
		($best_gapped, $gap_choice) = ($gapped, $r-$rg)
		    if $best_gapped < $gapped;
		$gap_penalty -= $gap_extend;
		$rg--;
	    }
	    # Look for insertions in $r (also the hard way).
	    $gap_penalty = -$gap_start;
	    my $ag = $a-1;
	    while ($ag >= 0) {
		my $gapped = $score_at->($ag, $r) + $gap_penalty;
		($best_gapped, $gap_choice) = ($gapped, $ag-$a)
		    if $best_gapped < $gapped;
		$gap_penalty -= $gap_extend;
		$ag--;
	    }
	    ($best, $best_choice) = ($best_gapped, $gap_choice)
		if $best < $best_gapped;
	    ($scores[$a][$r], $choices[$a][$r]) = ($best, $best_choice);
	}
    }
    # This is what produces the output.
    $traceback->($add_len-1, $rem_len-1);

    # [debugging:  show the matrix.  -- rgr, 5-Jun-18.]
    if ($verbose_p > 1) {
	for my $a (0 .. $add_len-1) {
	    for my $r (0 .. $rem_len-1) {
		printf STDERR "%4d[%2d]", $scores[$a][$r], $choices[$a][$r];
	    }
	    print STDERR "\n";
	}
    }
}

### Main program.

while (<>) {
    if (/^(---|\+\+\+)/) {
	# File heading line.
	print;
    }
    elsif (/^!/) {
	die "$0:  Not a context diff; can't handle";
    }
    elsif (/^[-+]/) {
	# Difference lines.
	my ($removed, $added) = ('', '');
	while (/^([-+])/) {
	    if ($1 eq '-') {
		$removed .= substr($_, 1);
	    }
	    else {
		$added .= substr($_, 1);
	    }
	    $_ = <>;
	}
	my @removed = split_html_tokens($removed);
	my @added = split_html_tokens($added);
	if ($test_split_p) {
	    for my $r (@removed) {
		print "-$r";
		print "\n"
		    unless $r eq "\n";
	    }
	    for my $a (@added) {
		print "+$a";
		print "\n"
		    unless $a eq "\n";
	    }
	}
	else {
	    minimize(\@removed, \@added);
	}
	# We usually have a non-difference line here, but not if the last line
	# in the file was inserted or deleted.
	print
	    if $_;
    }
    else {
	# Non-difference (matching or hunk heading) line.
	print;
    }
}

=head1 NAME

html-diff.pl -- make diff output of HTML more readable

=head1 SYNOPSIS

    html-diff.pl [ --help ] [ --man ] [ --usage ] [ --verbose ... ]
		 [ --line-length=<integer> ] [ --[no-]test-split ]

where:

    Parameter Name     Deflt  Explanation
     --test-split       no    Enables token split debugging.
     --help                   Print detailed help.
     --man                    Print man page.
     --line-length      80    Max length for reconstructed output lines. 
     --usage                  Print this synopsis.
     --verbose                Enable debugging output, may be repeated.

=head1 DESCRIPTION

C<html-diff.pl> can be used as a filter on C<diff> output of HTML
files to make the differences more obvious.  C<html-diff.pl> works
best at finding subtle differences in long lines of code-generated
HTML that would otherwise tend to get lost in the noise.

Given unidiff format on
the standard input, it works by breaking each series of lines that
C<diff> reports as mismatched into two sequences of tags and nontags,
one for each file, and then tries to find the minimal differences
between the two sequences.  These are then reported on a new series of
unidiff lines on the standard output.  With any luck, there will be
short stretches of differing tokens interspersed with longer matching
subsequences, and the mismatches will thereby stand out.  If all
tokens are stubbornly different, then the output will be no different
from the input (modulo added line breaks), but at least you'll know
that.

Remember that the line numbers in the hunk headers in the rest of the
C<diff> output still refer to the lines of the original file; since
C<html-diff.pl> usually needs to introduce additional line breaks,
these numbers will no longer make sense.  If you feed
this output to the C<patch> program, it will get really confused.
Using C<--line-length=0> to turn off line filling will remove all
added line breaks, but will not eliminate the problem.

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--line-len>
or C<--lin> for C<--line-length>), options with arguments can be given as
two words (e.g. C<--line 100>) or in one word separated by an "="
(e.g. C<--line=100>), and "-" can be used instead of "--".

=over 4

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--line-length>

Specifies the maximum line length to use when reconstructing unidiff
output lines after matched/unmatched subsequences have been found.
Output will extend over this limit only for single tokens that are
longer than this, though newlines within tokens are preserved.
Specifying C<--line-length=0> turns off line filling; in that case,
C<html-diff.pl> will not add any line breaks.

For what it's worth, specifying C<--line-length=1> causes each token
to appear on a line of its own; since the change marker character ("+"
or "-") takes up one column, C<html-diff.pl> will never be able to fit
a second token on a line.

Note that C<--line-length> filling only applies to the tokens that
C<html-diff.pl> processes; file and hunk heading lines and matching
context lines are passed through unchanged.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--test-split>

If specified, the raw tokens are output individually, rather than
trying to minimize their differences.  This is useful mostly for
debugging.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--verbose>

Prints debugging information if specified.  May be specified multiple
times to get more debugging information (but the extra information is
usually pretty obscure).

=back

=head1 EXAMPLE

Consider the following diff hunk with long lines:

    --- test/test-script-1.html	2018-06-04 17:24:46.766421852 -0400
    +++ output-29366-1.tmp.html	2018-06-05 10:58:51.558052976 -0400
    @@ -32,6 +32,6 @@
     <th width="170"><font size="3" face="Arial, Helvetica, sans-serif">Coordinates A3-A6</font></th>
     <th width="300" align="left"><font size="3" face="Arial, Helvetica, sans-serif">Residues in the Binding Pocket</font></th>
     <th width="300" align="left"><font size="3" face="Arial, Helvetica, sans-serif">Prediction</font></th>
    -</table><table width="870" align="center" border="0"><tr><td width="100" align="left">A-domain 1</td><td width="170" align="center">134	346</td><td width="300" align="left"><font size="5" face="Courier New, Courier, mono">  D    V    W    H    X    X    L    V</font></td><td width="100" align="center"></td><td width="200" align="right"> NO BLAST HIT</td></tr></table><table width="870" align="center" border="0" height="25">
    +</table><table width="870" align="center" border="0"><tr><td width="100" align="left">A-domain 1</td><td width="170" align="center">134	346</td><td width="300" align="left"><font size="5" face="Courier New, Courier, mono">  D    V    W    H    X    X    L    V</font></td><td width="200" align="right"> NO BLAST HIT</td></tr></table><table width="870" align="center" border="0" height="25">
		 <tr> <td bgcolor="#339999"> </td> </tr>
		 </table>

Depending on how you are viewing this, the lines may be truncated, or
it may be wrapped somehow, but in the original (which is the
F<test/html/test-diff-tok-1-in.patch> file from the test suite) there
is only one line that looks like it might have changed in a small way
-- or perhaps several small ways; who knows?  You can tell it's gotten
longer, but it's hard to see why.  If you pipe the same C<diff>
command through C<html-diff.pl>, the difference jumps out:

    > diff -u test/test-script-1.html output-29366-1.tmp.html | html-diff.pl
    --- test/test-script-1.html	2018-06-04 17:24:46.766421852 -0400
    +++ output-29366-1.tmp.html	2018-06-05 10:58:51.558052976 -0400
    @@ -32,6 +32,6 @@
     <th width="170"><font size="3" face="Arial, Helvetica, sans-serif">Coordinates A3-A6</font></th>
     <th width="300" align="left"><font size="3" face="Arial, Helvetica, sans-serif">Residues in the Binding Pocket</font></th>
     <th width="300" align="left"><font size="3" face="Arial, Helvetica, sans-serif">Prediction</font></th>
     </table><table width="870" align="center" border="0"><tr>
     <td width="100" align="left">A-domain 1</td><td width="170" align="center">
     134	346</td><td width="300" align="left">
     <font size="5" face="Courier New, Courier, mono">
       D    V    W    H    X    X    L    V</font>
    -</td><td width="100" align="center">
     </td><td width="200" align="right"> NO BLAST HIT</td></tr></table>
     <table width="870" align="center" border="0" height="25">
		 <tr> <td bgcolor="#339999"> </td> </tr>
		 </table>
    >

There is now only one difference line -- an empty C<< <td> >> cell
went away -- and it's easy to see just where it is.  (Note that the
algorithm arbitrarily decided that the previous C<< <td> >> cell was
the one that was deleted and not the matching one.)

=head1 BUGS

Sometimes the differences output do not seem minimal, which suggests
either a scoring problem or a bug in the algorithm implementation, but
I haven't had the time to track it down.

Since code often scrambles the order of attributes within a tag, it
would be nice if C<html-diff.pl> could canonicalize these before
deciding if two tags are really different.

There should be options to control the alignment parameters (they are
parameters in the code), but (a) I'm not sure that would really help
from a user perspective, and (b) describing what they mean might be
more trouble than it's worth.

It might be nice if matching context lines were also reformatted to
obey C<--line-length>; perhaps this should be an option.

=head1 SEE ALSO

=over 4

=item L<diff(1)>

=item L<https://en.wikipedia.org/wiki/Smith%E2%80%93Waterman_algorithm>

=back

=head1 AUTHOR

Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>

=head1 COPYRIGHT

Copyright (C) 2020 by Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
