#!/usr/bin/perl
#
# Hack to make sense of HTML diffs.
#
# [created.  -- rgr, 5-Jun-18.]
#

use strict;
use warnings;

use Getopt::Long;

my $match_score = 4;
my $mis_score = -4;
my $gap_start = 10;
my $gap_extend = 2;
my $max_line_length = 80;
my $verbose_p = 0;
my $test_split_p = 0;

GetOptions('verbose|v+' => \$verbose_p,
	   'line-length=i' => \$max_line_length,
	   'test-split!' => \$test_split_p)
    or die;

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

    my $select = sub {
	# Return a subarray.
	my ($array, $start, $end) = @_;

	my $result = [ ];
	for my $i ($start .. $end) {
	    push(@$result, $array->[$i]);
	}
	return $result;
    };

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

    my $print_token_diff = sub {
	# $rem and $add are strings or token arrays; 
	my ($rem, $add) = @_;

	if (! (ref($rem) && @$rem) || ! (ref($add) && @$add)
	    || $max_line_length <= 0) {
	    # If one or the other is empty, printing is simple.
	    my $rem_string = ref($rem) ? join('', @$rem) : $rem || '';
	    my $add_string = ref($add) ? join('', @$add) : $add || '';
	    if ($add_string eq $rem_string) {
		print " $rem_string\n";
	    }
	    else {
		print "-$rem_string\n"
		    if $rem_string;
		print "+$add_string\n"
		    if $add_string;
	    }
	}
	else {
	    # Both @rem_lines and @add_lines are guaranteed to be non-empty,
	    # because $rem and $add are.
	    my @rem_lines = $build_lines->($rem);
	    my @add_lines = $build_lines->($add);
	    if ($rem_lines[0] eq $add_lines[0]) {
		# If the first lines are equal, they must all be.  This will
		# happen if only whitespace has changed.
		for my $line (@rem_lines) {
		    print " $line\n";
		}
	    }
	    else {
		# Print @rem_lines before @add_lines.
		for my $line (@rem_lines) {
		    print "-$line\n";
		}
		for my $line (@add_lines) {
		    print "+$line\n";
		}
	    }
	}
    };

    if (! @$removed || ! @$added) {
	# If one or the other token array is empty, then the score matrix will
	# be empty and the traceback will fail, so just cut to the chase.
	$print_token_diff->($removed, $added);
	return;
    }

    my $add_len = @$added;
    my $rem_len = @$removed;
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
	    warn "span $span at [$i][$j]"
		if $verbose_p > 1;
	    $traceback->($i-$span, $j-$span);
	    $print_token_diff->($select->($removed, $j-$span+1, $j),
				$select->($added, $i-$span+1, $i));
	}
	elsif ($choice > 0) {
	    $traceback->($i, $j-$choice);
	    $print_token_diff->($select->($removed, $j-$choice+1, $j), '');
	}
	else { # ($choice < 0)
	    $traceback->($i+$choice, $j);
	    $print_token_diff->('', $select->($added, $i+$choice+1, $i));
	}
    };

    ## Main code of minimize.

    # Do a global alignment of the token arrays.
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
	chomp;
	while (/^([-+])/) {
	    if ($1 eq '-') {
		$removed .= substr($_, 1);
	    }
	    else {
		$added .= substr($_, 1);
	    }
	    $_ = <>;
	    chomp($_)
		if $_;
	}
	my @removed = split_html_tokens($removed);
	my @added = split_html_tokens($added);
	if ($test_split_p) {
	    for my $r (@removed) {
		print "-$r\n";
	    }
	    for my $a (@added) {
		print "+$a\n";
	    }
	}
	else {
	    minimize(\@removed, \@added);
	}
	# We usually have a non-difference line here, but not if the last line
	# in the file was inserted or deleted.
	print "$_\n"
	    if $_;
    }
    else {
	# Non-difference (matching or hunk heading) line.
	print;
    }
}
