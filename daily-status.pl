#!/usr/bin/perl
#
# Generate daily status message.
#
#    Modification history:
#
# created.  -- rgr, 29-Apr-00.
# use status-since file to avoid "date -t yesterday" bug.  -- rgr, 1-May-00.
#

# File which keeps track of when we last ran.
$status_since = '/root/bin/status-since';

chomp($yesterday = `date -r $status_since '+%b %d'`);
# since date gives "Apr 05".
$yesterday =~ s/ 0/  /;
system("/root/bin/check-logs.pl -from '$yesterday' /var/log/messages"
       . " | mail rogers -s 'Daily log for $yesterday'");
system("touch $status_since");
