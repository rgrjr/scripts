#!/usr/bin/perl -w
#
# List backup files in inverse chronological order.
#
# [created.  -- rgr, 26-May-04.]
#
# $Id$

use strict;
# use Data::Dumper;

# Figure out where to search for backups.
my @search_roots = @ARGV;
if (! @search_roots) {
    for my $root ('scratch', 'scratch2', 'scratch.old') {
	for my $base ('', '/alt') {
	    my $dir = "$base/$root/backups";
	    push (@search_roots, $dir)
		if -d $dir;
	}
    }
    die "$0:  No search roots.\n"
	unless @search_roots;
}

# Find backup dumps on disk.
my $command
    = join(' | ',
	   join(' ', 'find', @search_roots, '-name', "'home-*.dump'"),
	   'xargs ls -l');
open(IN, "$command |")
    or die;
my %date_to_dumps;
while (<IN>) {
    chomp;
    if (/-(\d+)-l(\d)\.dump$/) {
	my ($date, $level) = //;
	my $listing = substr($_, 30);
	$listing =~ s/^ *(\d+) /(' 'x(14-length($1))).$1.' '/e;
	push(@{$date_to_dumps{$date}}, [$date, $level, $listing]);
    }
}

# Generate output sorted with the most recent at the top, and a '*' marking the
# current backup files.
my $last_level = 10;
# warn Dumper(\%date_to_dumps);
for my $date (sort { $b <=> $a; } keys(%date_to_dumps)) {
    for my $entry (@{$date_to_dumps{$date}}) {
	my ($ignored_date, $level, $listing) = @$entry;
	substr($listing, 1, 1) = '*', $last_level = $level
	    if $level < $last_level;
	print $listing, "\n";
    }
}
