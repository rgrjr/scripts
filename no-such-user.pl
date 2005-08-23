#!/usr/bin/perl -w
#
# Return an "address no longer valid" bounce message via sendmail.
#
# [created.  -- rgr, 22-Aug-05.]
#
# $Id$

use strict;

use Date::Format;

my $date_format_string = '%a, %e %b %Y %H:%M:%S %z';

my $domain = $ENV{DOMAIN} || 'modulargenetics.com';
my $sender = $ENV{SENDER}
    or die;
open(OUT, "| /usr/sbin/sendmail -f '' '$sender'")
    or die;

print OUT "From: Mailer Daemon <mailer-daemon\@$domain>\n";
print OUT "To: $sender\n";
print OUT "Date: ", time2str($date_format_string, time()), "\n";
print OUT "Subject: No such user\n\n";

print OUT ("We are sorry, but this address is no longer valid.  Please ",
	   "update your address\nbook.  If you have questions, ",
	   "please address them to \"postmaster\".\n\n");

print OUT "Original message headers:\n\n";
my $skip_p = 1;
while (<>) {
    if ($skip_p && /^(From |Return-Path:|Delivered-To:)/i) {
	# these lines are generated as part of the local delivery process; since
	# this would be for the delivery to "bounce", they are misleading.
    }
    else {
	print OUT "   $_";
	$skip_p = 0;
    }
    last if $_ eq "\n";
}
close(OUT);
