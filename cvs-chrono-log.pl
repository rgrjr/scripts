#!/usr/bin/perl -w
#
# Convert the file-oriented "cvs log" output into a historical narrative, in
# reverse chronological order.
#
# [created.  -- rgr, 24-Jul-03.]
#
# $Id$

use strict;

my %modifications;

sub record_file_rev_comment {
    my ($file_name, $file_rev, $date_etc, $comment) = @_;
    my $date = ($date_etc =~ /date: *([^;]+); */ 
		? ($date_etc =~ s///, $1)
		: '???');

    # warn "[got ($file_name, $file_rev, $date_etc):]\n";
    $date_etc =~ s/state: Exp; *//;
    push(@{$modifications{$date}{$comment}},
	 [$file_name, $file_rev, $date_etc]);
}

sub print_file_rev_comments {

    for my $date (reverse(sort(keys(%modifications)))) {
	for my $comment (sort(keys(%{$modifications{$date}}))) {
	    print "$date:\n";
	    for my $line (split("\n", $comment)) {
		print "  $line\n"
		    if $line;
	    }
	    for my $entry (@{$modifications{$date}{$comment}}) {
		my ($file_name, $file_rev, $date_etc) = @$entry;
		print "  => $file_name $file_rev:  $date_etc\n";
	    }
	}
	print "\n";
    }
}

### Parser top level.

# state is one of qw(none headings descriptions).
my $state = 'none';
my $file_name;
my $line;
while (defined($line = <>)) {
    if ($line =~ /^RCS file: /) {
	# start of a new entry.
	$state = 'headings';
    }
    elsif ($state eq 'descriptions') {
	# print($line);
	$line =~ /^revision (.*)$/
	    or warn "[oops; expected revision here.]\n";
	my $file_rev = $1;
	chomp(my $date_etc = <>);
	my $comment = '';
	$line = <>;
	while ($line !~ /^---+$|^===+$/) {
	    $comment .= $line;
	    $line = <>;
	}
	record_file_rev_comment($file_name, $file_rev, $date_etc, $comment);
	$state = ($line =~ /^========/ ? 'none' : 'descriptions');
    }
    # $state eq 'headings'
    elsif ($line =~ /^([^:]+):\s*(.*)/) {
	# processing the file header.
	my $tag = $1;
	if ($tag eq 'description') {
	    $line = <>;
	    $state = ($line =~ /^========/ ? 'none' : 'descriptions');
	}
	elsif ($tag eq 'Working file') {
	    chomp($file_name = $2);
	}
    }
}
warn "[oops; final state is $state.]\n"
    unless $state eq 'none';
print_file_rev_comments();
