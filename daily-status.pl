#!/usr/bin/perl
#
# Generate daily status mail message.
#
# [created.  -- rgr, 29-Apr-00.]
#
# $Id$

use strict;
use warnings;

# File which keeps track of when we last ran.
my $status_since = '/root/bin/status-since';

chomp(my $yesterday = `date -r $status_since '+%b %d'`);
# since date gives "Apr 05".
$yesterday =~ s/ 0/  /;
system(join(' ',
	    '/usr/local/bin/check-logs.pl',
	    ($yesterday ? "-from '$yesterday'" : ()),
	    '/var/log/messages',
	    "| mail rogers -s 'Daily log for $yesterday'");
system("touch $status_since");
