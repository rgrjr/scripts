#!/usr/bin/perl -w
#
# Check that DST conversion will do the right thing in the next few weeks.
#
# [created.  -- rgr, 25-Feb-07.]
#
# $Id$

use strict;
use warnings;

use Date::Format;

my $date_format_string = '%Y-%m-%d %H:%M:%S %Z';

my $time = time;
for my $week (0..5) {
    print time2str($date_format_string, $time), "\n";
    $time += 7*24*60*60;
}
