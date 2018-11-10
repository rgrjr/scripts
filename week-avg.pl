#!/usr/bin/perl -w
#
# week-avg.pl:  Produce a plot of weekly averages.
#
# POD documentation at the bottom.
#
# Copyright (C) 2015..2017 by Bob Rogers <rogers@rgrjr.dyndns.org>.
# This script is free software; you may redistribute it
# and/or modify it under the same terms as Perl itself.
#

use strict;
use warnings;

BEGIN {
    # This is for testing, and only applies if you don't use $PATH.
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Getopt::Long;
use Pod::Usage;
use Date::Parse;
use Date::Format;

### Parse command-line options.

my $verbose_p = 0;
my $usage = 0;
my $help = 0;
my $limit;
my $discard = 4;
GetOptions('verbose+' => \$verbose_p,
	   'limit=s' => \$limit,
	   'discard=i' => \$discard,
	   'usage|?' => \$usage, 'help' => \$help)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

if ($limit && $limit =~ /^\d+$/) {
    # Interpret an integer limit as N days in the past.
    $limit = time() - $limit * 24*3600;
}
elsif ($limit) {
    # This must be a date string.
    $limit = str2time($limit)
	|| die "$0:  Can't parse '--limit=$limit'.\n";
}

### Main code.

## Process input.
my ($first_week, @counts_by_week, @sums_by_week);
while (<>) {
    chomp;
    my ($date_string, $value) = split("\t");
    next
	# Some lines will be empty.
	unless $date_string && $value;
    my $date = str2time($date_string);
    die "$0:  Can't parse date '$date_string' at $..\n"
	unless $date;
    last
	if $limit && $date < $limit;
    my $day_number = int($date / (24*3600)) - 3;
    my $week_number = int($day_number/7);
    $first_week ||= $week_number;
    my $delta_week = $first_week-$week_number;
    # print "$date_string => $delta_week => $value\n";
    $counts_by_week[$delta_week]++;
    $sums_by_week[$delta_week] += $value;
}

## Produce output.
my $skip_p = 0;
for my $delta_week (0 .. @counts_by_week-1) {
    my $count = $counts_by_week[$delta_week];
    if (! $count || $count < $discard) {
	$skip_p++;
	next;
    }
    my $average = $sums_by_week[$delta_week] / $count;
    my $week_date = time2str('%d-%b-%y', 7*24*3600 * ($first_week-$delta_week));
    print"\n"
	# Reflect a gap in the data.
	if $skip_p;
    printf("%s\t%.1f\n", $week_date, $average);
    $skip_p = 0;
}

__END__

=head1 NAME

week-avg.pl -- produce a plot of weekly averages

=head1 SYNOPSIS

        week-avg.pl [ --verbose ... ] [ --discard=<int> ]
		[ --limit=<n-days-or-date> ]

        week-avg.pl [ --usage | --help ]

=head1 DESCRIPTION

=head1 COPYRIGHT

Copyright (C) 2011 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
