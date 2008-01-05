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

my @log_files = qw(/var/log/messages);
push(@log_files, '/var/log/firewall')
    if -r '/var/log/firewall';

chomp(my $yesterday = `date -r $status_since '+%b %d'`);
# since date gives "Apr 05".
$yesterday =~ s/ 0/  /;
system(join(' ',
	    '/usr/local/bin/check-logs.pl',
	    ($yesterday ? "-from '$yesterday'" : ()),
	    @log_files,
	    "| mail rogers -s 'Daily log for $yesterday'"));
system("touch $status_since");
