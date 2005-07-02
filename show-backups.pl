#!/usr/bin/perl -w
#
# List backup files in inverse chronological order.
#
# [created.  -- rgr, 26-May-04.]
#
# $Id$

use strict;
use Getopt::Long;
# use Data::Dumper;

my $host_name = `hostname`;
chomp($host_name);
my $prefix = 'home';

GetOptions('prefix=s' => \$prefix, 'host=s' => \$host_name)
    or die;

# Figure out where to search for backups.
my @search_roots = @ARGV;
if (! @search_roots) {
    for my $root ('scratch', 'scratch2', 'scratch.old') {
	for my $base ('', '/alt', '/old', '/new') {
	    my $dir = "$base/$root/backups";
	    push (@search_roots, $dir)
		if -d $dir;
	}
    }
    die "$0:  No search roots.\n"
	unless @search_roots;
}

# Find backup dumps on disk.
my $command = join(' ', 'find', @search_roots, '-name', "'$prefix-*.dump'");
open(IN, "$command |")
    or die;
my %date_to_dumps;
while (<IN>) {
    chomp;
    if (/-(\d+)-l(\d)\.dump$/) {
	my ($date, $level) = //;
	my $file = $_;
	my @stat = stat($file);
	my $size = $stat[7];
	$file =~ s@(/.*/)(.*)$@$2 [$host_name:$1]@;
	# [sprintf can't handle huge numbers.  -- rgr, 28-Jun-04.]
	# my $listing = sprintf('%14i %s', $size, $file);
	my $listing = (' 'x(14-length($size))).$size.' '.$file;
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
