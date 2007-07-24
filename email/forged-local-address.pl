#! /usr/bin/perl
################################################################################
#
# Check for forged email SENDER addresses, exiting 0 if so.
#
# [created.  -- rgr, 22-Jul-06.]
#
# $Id$

use strict;
use warnings;

use Mail::Header;
use Getopt::Long;
use Pod::Usage;

### Option parsing.

my $verbose_p = 0;
my $not_p = 0;		# to reverse the sense of the test.
my $local_domain_file = '/var/qmail/control/locals';

GetOptions('verbose+' => \$verbose_p,
	   'not!' => \$not_p,
	   'locals=s' => \$local_domain_file)
    or pod2usage();

my ($spam_exit, $legit_exit) = ($not_p ? (1, 0) : (0, 1));

### Subroutines.

my %match_domains;
my @suffix_domains;
sub ensure_nonlocal_host {
    # Exits with $spam_exit code if it matches any local domain.
    my ($host, $description) = @_;

    $host =~ s/.*@//;
    $host = lc($host);

    if ($match_domains{$host}
	|| grep { substr($_, -length($host)) eq $host; } @suffix_domains) {
	warn "lose:  '$host' is forged in $description\n"
	    if $verbose_p;
	exit($spam_exit);
    }
    warn "$host is good\n"
	if $verbose_p;
}

### Main code.

# Check headers for local vs. remote.
my $message = Mail::Header->new(\*STDIN);
my $hdr = $message->get('Received', 0);
my $local_p;
if ($hdr =~ /qmail \d+ invoked by /) {
    $local_p = 'local';
}
else {
    my $hdr = $message->get('Received', 1);
    $local_p = 'lan'
	if $hdr && $hdr =~ /by 192.168.57.\d+ with SMTP/;
}
if ($local_p) {
    warn "win:  $local_p\n"
	if $verbose_p;
    exit($legit_exit);
}

# We have a remote message, so we need to find out what our local addresses are.
if (-r $local_domain_file) {
    open(IN, $local_domain_file)
	or die "$0:  Could not open '$local_domain_file':  $!";
    while (<IN>) {
	chomp;
	$_ = lc($_);
	if (substr($_, 0, 1) eq '.') {
	    push(@suffix_domains, $_);
	}
	else {
	    $match_domains{$_}++;
	}
    }
    close(IN);
}

# Check the envelope sender against all of the match domains.  If we find a
# match, we lose.
my $host = $ENV{SENDER}
   or die "$0:  Bug:  No \$SENDER";
ensure_nonlocal_host($host, 'envelope sender');

# Look for forged local addresses in appropriate headers.
for my $header_name (qw(sender from)) {
    for my $header ($message->get($header_name)) {
	for my $address (split(/\s*,\s*/, $header)) {
	    $address =~ s/\"[^""]*\"//g;
	    $address =~ s/\([^()]*\)//g;
	    if ($address =~ /<([^<>]+)>/) {
		ensure_nonlocal_host($1, $header_name);
	    }
	    else {
		ensure_nonlocal_host($address, $header_name);
	    }
	}
    }
}

# This means NOT spam.
warn "win:  remote, sender '$host' not forged\n"
    if $verbose_p;
exit($legit_exit);

__END__

=head1 DESCRIPTION

Detect forged email addresses by examining 'Received:' headers.

To use this, put the following in your C<.qmail> file:

	| condredirect rogers-spam bin/forged-local-address.pl

The C<rogers-spam> address must be defined.  [This is something of a
bug; C<forged-local-address.pl> should just exit 99 directly to drop
the message completely.  But I don't think I want to implement this
until I have some kind of logging first.  -- rgr, 22-Jul-06.]

Currently, only qmail-style delivery is supported.  Postfix will be
added before long.

=head2 Internals

There are three cases: 

=over 4

=item 1.

Locally injected, in which case the first 'Received:' header contains
something like "qmail 20512 invoked by uid 500" or "qmail 20513
invoked by alias".  This is legitimate.

=item 2.

Accepted via SMTP from the internal network; this too is legit.  The
first header will say "qmail 20704 invoked from network", and the next
header will look like this:

    Received: from unknown (HELO ?192.168.57.4?) (192.168.57.4)
      by 192.168.57.1 with SMTP; 15 Jun 2006 00:22:49 -0000

[I don't know what the question marks are for.  -- rgr, 17-Jun-06.]

=item 3.

Accepted remotely.  This includes all other "invoked from network"
cases, regardless of what the next header says.  But here is an
example:

   Received: from bay113-f18.bay113.hotmail.com (HELO hotmail.com) (65.54.168.28)
     by c-24-128-218-106.hsd1.ma.comcast.net with SMTP; 15 Jun 2006 02:15:10 -0000

It's a good thing we don't need to care about the content of this
header, because this is pretty variable.

=back

In the last case only, we need to check for a remote sender address.
The domain of the envelope sender must B<not> match any of our 'local'
domains.  There are two kinds of matching:

=over 4

=item 1.

If the entry starts with a dot, as in C<.rgrjr.com>, then it matches
any subdomain (but not the domain itself).

=item 2.

If the entry does not start with a dot, as in C<rgrjr.com>, then the
match is exact.

=back

Note that these are mutually exclusive; if you want to include both,
you must mention both explicitly.

=cut
