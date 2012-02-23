#!/usr/bin/perl -w
#
# Find the next ten daylight/standard time switches, assuming that the first is
# within the next 15 weeks, and relying on the time2str "%Z" directive to
# define whether a given absolute time is daylight savings or not.
#
# [created.  -- rgr, 25-Feb-07.]
# [revised to search.  -- rgr, 23-Feb-12.]
#
# $Id$

use strict;
use warnings;

use Date::Format;

my $date_format_string = '%Y-%m-%d %H:%M:%S %Z';

sub binary_search {
    my ($start, $end) = @_;

    # Check for termination (or failure).
    my $start_str = time2str($date_format_string, $start);
    my $start_zone = substr($start_str, -3);
    my $end_str = time2str($date_format_string, $end);
    my $end_zone = substr($end_str, -3);
    if ($start_zone eq $end_zone) {
	die "lost between $start_str and $end_str";
    }
    elsif (abs($start - $end) <= 1) {
	# Because we insist that $start and $end be in different zones, they
	# can never be exactly equal.
	print "$start_str\t$end_str\n";
	return ($start, $end);
    }

    # Interpolate.
    my $mid = int(($start + $end) / 2);
    my $mid_str = time2str($date_format_string, $mid);
    my $mid_zone = substr($mid_str, -3);
    # print "$mid_str ($mid, from $start and $end)\n";
    if ($start_zone eq $mid_zone) {
	binary_search($mid, $end);
    }
    else {
	binary_search($start, $mid);
    }
}

use constant SECONDS_PER_WEEK => 7*24*60*60;

my $start = time;
for my $switch (1 .. 10) {
    ($start) = binary_search($start, $start + 20 * SECONDS_PER_WEEK);
    $start += 15 * SECONDS_PER_WEEK;
}
