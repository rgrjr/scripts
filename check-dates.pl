#!/usr/bin/perl -w
#
# Find the next ten daylight/standard time switches, relying on the time2str
# "%Z" directive to define whether a given absolute time is DST or not.
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
    my $start_zone = time2str('%Z', $start);
    my $end_zone = time2str('%Z', $end);
    if ($start_zone eq $end_zone) {
	# warn "lost between $start and $end";
	return;
    }
    elsif (abs($start - $end) <= 1) {
	# Because we insist that $start and $end be in different zones, they
	# can never be exactly equal.
	return ($start, $end);
    }

    # Interpolate.
    my $mid = int(($start + $end) / 2);
    my $mid_zone = time2str('%Z', $mid);
    # print "$mid_zone ($mid, from $start and $end)\n";
    if ($start_zone eq $mid_zone) {
	binary_search($mid, $end);
    }
    else {
	binary_search($start, $mid);
    }
}

use constant SECONDS_PER_WEEK => 7*24*60*60;

# Find the first DST change.
my $start = time;
my $interval = 3600;
my ($change_start, $change_end);
while (! defined($change_start)) {
    die "oops"
	if $interval > 50 * SECONDS_PER_WEEK;
    ($change_start, $change_end) = binary_search($start, $start + $interval);
    # Increase the interval by 50%.
    $interval += int($interval/2);
}

# Print the current change dates, and find subsequent changes based on the
# previous one.
for my $counter (1 .. 10) {
    print(join("\t", time2str($date_format_string, $change_start),
	       time2str($date_format_string, $change_end)),
	  "\n");
    $change_start += 15 * SECONDS_PER_WEEK;
    $change_end += 45 * SECONDS_PER_WEEK;
    ($change_start, $change_end) = binary_search($change_start, $change_end);
    last
	unless $change_start;
}
