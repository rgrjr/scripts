#!/usr/bin/perl -w
#
# Find the next ten daylight/standard time switches, using time2str "%Z".
#
# [created.  -- rgr, 25-Feb-07.]
# [revised to search.  -- rgr, 23-Feb-12.]
#

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

__END__

=head1 NAME

snoop-maildir.pl -- print a summary of maildir content

=head1 SYNOPSIS

    check-dates.pl

=head1 DESCRIPTION

Find the next ten daylight savings/standard time switches in the
current locale, relying on the "%Z" directive of C<time2str> (see
C<Date::Format>) to define whether a given time is daylight savings or
not.  Has no options and ignores all arguments.

=head1 EXAMPLE

    > ./check-dates.pl
    2021-03-14 01:59:59 EST	2021-03-14 03:00:00 EDT
    2021-11-07 01:59:59 EDT	2021-11-07 01:00:00 MNT
    2022-03-13 01:59:59 EST	2022-03-13 03:00:00 EDT
    2022-11-06 01:59:59 EDT	2022-11-06 01:00:00 MNT
    2023-03-12 01:59:59 EST	2023-03-12 03:00:00 EDT
    2023-11-05 01:59:59 EDT	2023-11-05 01:00:00 MNT
    2024-03-10 01:59:59 EST	2024-03-10 03:00:00 EDT
    2024-11-03 01:59:59 EDT	2024-11-03 01:00:00 MNT
    2025-03-09 01:59:59 EST	2025-03-09 03:00:00 EDT
    2025-11-02 01:59:59 EDT	2025-11-02 01:00:00 MNT
    > 

=head1 AUTHOR

Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>

=head1 COPYRIGHT

Copyright (C) 2016-2020 by Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
