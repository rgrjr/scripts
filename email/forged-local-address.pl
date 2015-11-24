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
my $local_network_prefix;
my $vps = '23.92.21.122';	# fixed IP for rgrjr.com.
my @sender_regexps;

GetOptions('verbose+' => \$verbose_p,
	   'not!' => \$not_p,
	   'sender-re=s' => \@sender_regexps,
	   'add-local=s' => \&add_local_domain,
	   'network-prefix=s' => \$local_network_prefix,
	   'locals=s' => \$local_domain_file)
    or pod2usage();

my ($spam_exit, $legit_exit) = ($not_p ? (1, 0) : (0, 1));
# Find the $local_network_prefix if not specified.
if (! $local_network_prefix) {
    open(my $in, '/sbin/ifconfig |')
	or fail("Could not open pipe from ifconfig:  $!");
    while (defined(my $line = <$in>)) {
	$local_network_prefix = $1, last
	    if $line =~ /inet addr:(192\.168\.\d+|10\.\d+\.\d+)\./;
    }
    fail("Couldn't find default IP address from ifconfig")
	unless $local_network_prefix;
}

### Subroutines.

sub fail {
    # Produce a message on stderr and exit with code 111 so that delivery is
    # tried later.

    warn("$0:  ", @_);
    exit(111);
}

my %match_domains;
my @suffix_domains;
sub add_local_domain {
    my $domain = (@_ == 2 ? $_[1] : shift);

    $domain = lc($domain);
    if (substr($domain, 0, 1) eq '.') {
	push(@suffix_domains, $domain);
    }
    else {
	$match_domains{$domain}++;
    }
}

sub ensure_nonlocal_host {
    # Exits with $spam_exit code if it matches any local domain.
    my ($host, $description) = @_;

    # Clean up and canonicalize the host first.
    chomp($host);
    $host =~ s/.*@//;
    $host =~ s/\s+//g;
    $host = lc($host);

    if ($match_domains{$host}
	|| grep { substr($_, -length($host)) eq $host; } @suffix_domains) {
	warn "lose:  '$host' is forged in nonlocal $description\n"
	    if $verbose_p;
	exit($spam_exit);
    }
    warn "$host is good\n"
	if $verbose_p;
}

sub local_header_p {
    # The sole argument is expected to be a "Received:\s*" header string,
    # possibly multiline, but without the part matching this RE.  Return 1 if
    # the header indicates locally-generated (as opposed to relayed) email,
    # "undef" if the header shows internal relaying, and 0 otherwise (which
    # presumably means that the message came from somewhere else).  Important:
    # Do NOT return "undef" unless the "from" host is trustworthy.
    my $hdr = shift;

    if (! $hdr) {
	# Can't make a determination.
	return;
    }
    elsif ($hdr =~ /qmail \d+ invoked by uid (\d+)/) {
	# qmail locally originated.
	return 'local';
    }
    elsif ($hdr =~ /by $local_network_prefix\.\d+ with SMTP/) {
	# qmail format for delivery to our LAN address.
	'lan';
    }
    elsif ($hdr =~ /^from \S+ \(HELO \S+\) \((\S+\@)?$local_network_prefix\.\d+\)/) {
	# qmail format for receipt from a LAN host.
	'lan';
    }
    elsif ($hdr =~ /^from \S+ \(\S+ \[$local_network_prefix\.\d+\]\)/) {
	# Postfix format for receipt from a LAN host.
	'lan';
    }
    elsif ($hdr =~ /^from \S+ \(localhost \[127.0.0.1\]\)/) {
	# Postfix format for the loopback re-receipt of SpamAssassin results.
	return;
    }
    elsif ($hdr =~ /^from \S+ \(HELO \S+\) \($vps\)/) {
	# qmail format for receipt from the rgrjr.com VPS.  [Though loopback on
	# any trusted host should be equivalent.  -- rgr, 27-Nov-08.]
	return;
    }
    elsif ($hdr !~ /Postfix/) {
	# Assume qmail, which adds two headers for SMTP mail; we need to check
	# the second one.
	return;
    }
    elsif ($hdr =~ /^from \S+ \(\S+ \[$vps\]\)/) {
	# Postfix format for receipt from the rgrjr.com VPS.
	return;
    }
    # Postfix only adds a single header, so we need to make a definite
    # determination on this header to avoid spoofing.
    elsif ($hdr =~ /from userid \d+/) {
	'local';
    }
    elsif ($hdr =~ /^from \S+ \(\S+ \[([\d.]+)\.\d+\]\)/
	   && $1 eq $local_network_prefix) {
	'lan';
    }
    else {
	0;
    }
}

### Main code.

# Check headers for local vs. remote.
my $message = Mail::Header->new(\*STDIN);
my $local_p;
# Iterate backwards in time through headers generated by our mail server(s)
# until $local_p is defined.  The first header (index 0, most recent) is always
# locally-generated, and therefore trustworthy.  The result will be trustworthy
# as long as we (a) check headers in order and (b) local_header_p only returns
# "undef" for internal relaying from another trustworthy source.  Sometimes we
# have to check as many as four headers to get to the earliest internally-
# generated header.
my $n_received_headers = $message->count('Received');
my $rcvd_idx = 0;
do {
    # [Note that Mail::Header version 2.02 always works for $rcvd_idx==0 (we
    # might get undef, but local_header_p can handle that), but blows cookies
    # for higher indices if no such header exists.  -- rgr, 17-Mar-09.]
    my $header = $message->get('Received', $rcvd_idx);
    $local_p = local_header_p($header);
    warn("header $rcvd_idx:  ", $header || "\n",
	 "header $rcvd_idx:  result is ",
	 (defined($local_p) ? "'$local_p'" : '(undef)'), ".\n")
	if $verbose_p > 1;
} until defined($local_p) || ++$rcvd_idx >= $n_received_headers;
if ($local_p) {
    warn "win:  $local_p\n"
	if $verbose_p;
    exit($legit_exit);
}

# Check the envelope sender for whitelisted hosts that are allowed to send email
# that appears to be from us.  This is useful for getting copies from mailing
# lists.
my $envelope_sender = $ENV{SENDER} || '';
if (! $envelope_sender) {
    warn "$0:  Can't check SENDER, as it's undefined.\n"
	if $verbose_p || @sender_regexps;
}
else {
    for my $regexp (@sender_regexps) {
	if ($envelope_sender =~ /$regexp/) {
	    warn "win:  sender '$envelope_sender' matches '$regexp'.\n"
		if $verbose_p;
	    exit($legit_exit);
	}
    }
}

# We have a remote message, so we need to find out what our local addresses are.
if (-r $local_domain_file) {
    open(IN, $local_domain_file)
	or fail("Could not open '$local_domain_file':  $!");
    while (<IN>) {
	chomp;
	add_local_domain($_);
    }
    close(IN);
}
# Default default.
%match_domains = map { ($_ => 1); } qw(rgrjr.com rgrjr.dyndns.org)
    unless %match_domains || @suffix_domains;

# Check the envelope sender against all of the match domains.  If we find a
# match, we lose.
ensure_nonlocal_host($envelope_sender, 'envelope sender')
    if $envelope_sender;

# Look for forged local addresses in appropriate headers.
for my $header_name (qw(sender from reply-to)) {
    for my $header ($message->get($header_name)) {
	# Get rid of RFC822 comments first, so we are not confused by commas in
	# comments.  Parentheses nest.
	while ($header =~ s/\(([^()]*)\)//g) {
	    my $comment = $1;
	    # If a comment in a header intended to identify the sender has one
	    # of our host names, then that is probably a forgery.
	    ensure_nonlocal_host($comment, $header_name)
		if $comment;
	}
	$header =~ s/\"[^""]*\"//g;
	for my $address (split(/\s*,\s*/, $header)) {
	    if ($address =~ /(.*)<([^<>]+)>(.*)/) {
		my ($before, $addr, $after) = $address =~ //;
		$addr =~ s/\s+//g;
		ensure_nonlocal_host($addr, $header_name);
		# We also need to do the stuff outside the angle brackets,
		# since TMDA uses those to match against whitelisted senders.
		ensure_nonlocal_host($before, $header_name)
		    if $before;
		ensure_nonlocal_host($after, $header_name)
		    if $after; 
	    }
	    else {
		$address =~ s/\s+//g;
		ensure_nonlocal_host($address, $header_name);
	    }
	}
    }
}

# This means NOT spam.
warn "win:  remote, sender '$envelope_sender' not local\n"
    if $verbose_p;
exit($legit_exit);

__END__

=head1 DESCRIPTION

Detect forged email addresses by examining 'Received:' headers.

To use this, put the following in your C<.qmail> file:

	| bouncesaying "Go away." bin/forged-local-address.pl

Alternatively, you could redirect all address forgeries to a different
folder:

	| condredirect rogers-spam bin/forged-local-address.pl

In this case, the C<rogers-spam> address must be defined (e.g. via a
C<.qmail-spam> file).

Currently, the only supported MTAs are qmail and Postfix.

=head2 Options

These are parsed with C<Getopt::Long>, so any unique prefix is acceptable.

=over 4

=item B<--add-local>

Specifies a single domain name to add to the "local" set.  If the name
starts with a ".", it is a wildcard; otherwise, the whole domain name
must match.

=item B<--locals>

Specifies a file of domain names.  Each line in this file is treated
as if it had been added individually with C<--add-local>.  The file
name defaults to '/var/qmail/control/locals', which only makes sense
for qmail.  There is no error if the C<--locals> file does not exist.

=item B<--network-prefix>

Specifies a class C network prefix (i.e. "192.168.23") for qmail
relaying.  If not specified, this defaults to the first "192.168.*.*"
subnet in the output of C<ifconfig>.  This is mostly used for testing.

=item B<--not>

Inverts the sense of the return value.  Normally,
C<forged-local-address.pl> exits true (0) if it detects a forgery, and
false (1) otherwise.  If C<--not> is specified,
C<forged-local-address.pl> exits 1 for a forgery, and 0 otherwise.

=item B<--sender-re>

Adds a regular expression that is intended to match the envelope
sender; may be specified multiple times.  If the envelope sender
matches any regular expression, the mail is passed on, regardless of
headings.  This is useful for getting copies of your posts to mailing
lists, which have "From: You" headers and so look like forgeries, but
usually have distinctive envelope sender addresses.

For example, the C<perl6-language> mailing list is hosted at
C<perl.org>, with return addresses that look like this:

	perl6-language-return-30050-rogers-perl6=rgrjr.dyndns.org@perl.org

The return address is usually found in the "Return-Path:" header.  The
part before the "@" encodes the mailing list, the index number of the
posted message, and the recipient, all of which is useful to the
mailing list software if the message bounces for some reason, and
which will differ from one mailing list package to another.  So the
following would be sufficient to accept such messages:

	--sender-re='@perl.org$'

But note that the sender address is not trustworthy, and in fact is
usually forged in the case of spam.  To protect against the slim
chance that the spammer decides to forge a "perl.org" return address,
we can use the following more conservative variation:

	--sender-re='rogers-perl6=rgrjr.dyndns.org@perl.org$'

would be very unlikely for a spammer to stumble upon.  The essential
thing is to omit the variable part of the return address (the digits
encoding the posting index), and not to anchor the RE at the start.

=item B<--verbose>

Turns on verbose debugging output, which is printed to stderr.  This
can be useful to find out how a given message is getting classified.

=back

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

=head2 Bugs

C<--network-prefix> shouldn't be biased towards class C networks that
start with "192.168...".

There is no error if the C<--locals> file does not exist, even if it
was specified explicitly.

=cut
