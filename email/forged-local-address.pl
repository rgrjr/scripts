#!/usr/bin/perl
################################################################################
#
# Check for forged email SENDER addresses, exiting 0 if so.
#
# [created.  -- rgr, 22-Jul-06.]
#

use strict;
use warnings;

BEGIN {
    # This is for testing, and only applies if you don't use $PATH.
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Mail::Header;
use Getopt::Long;
use Pod::Usage;
use Net::Block;

### Option parsing.

my $verbose_p = 0;
my $not_p = 0;		# to reverse the sense of the test.
my ($local_domain_file, %match_domains, @suffix_domains);
my @local_networks;
my %relay_p;		# authorized relays.
my %list_host_p;	# authorized mailing list host names.
my @sender_regexps;
my $dotted_quad = '\d+.\d+.\d+.\d+';	# constant regexp.

GetOptions('verbose+' => \$verbose_p,
	   'not!' => \$not_p,
	   'sender-re=s' => \@sender_regexps,
	   'list-host=s' => \&add_list_host,
	   'add-local=s' => \&add_local_domain,
	   'relay-ip=s' => \&add_relay,
	   'network-prefix=s' => \&add_local_net,
	   'locals=s' => \$local_domain_file)
    or pod2usage();
$local_domain_file ||= '/var/qmail/control/locals'
    # Take the Qmail default only if --add-local was never specified.
    unless %match_domains || @suffix_domains;

my ($spam_exit, $legit_exit) = ($not_p ? (1, 0) : (0, 1));
# Find the local network(s) if not specified.
if (! @local_networks) {
    open(my $in, '/bin/ip a |')
	or fail("Could not open pipe from 'ip a':  $!");
    while (defined(my $line = <$in>)) {
	if ($line =~ m@inet ([.\d]+/\d+)@) {
	    my $address = $1;
	    my $block = Net::Block->parse($address)
		or die "$0:  Bug:  Bad address '$address' from 'ip a'.\n";
	    push(@local_networks, $block)
		# Don't use the loopback address.
		unless $block->host_octets->[0] == 127;
	}
    }
    fail("Couldn't find a default IPv4 netblock from 'ip a'; ",
	 "use --network-prefix to specify one.\n")
	unless @local_networks;
}

### Subroutines.

sub fail {
    # Produce a message on stderr and exit with code 111 so that delivery is
    # tried later.

    warn("$0:  ", @_);
    exit(111);
}

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

sub add_relay {
    # For option parsing.
    my ($option, $relay_address) = @_;

    die "$0:  Relay address must be a dotted quad.\n"
	unless $relay_address =~ /^$dotted_quad$/;
    $relay_p{$relay_address}++;
}

sub add_local_net {
    # More option parsing.
    my ($option, $local_net_address) = @_;

    my $block = Net::Block->parse($local_net_address);
    die "$0:  Malformed --$option '$local_net_address'.\n"
	unless $block;
    push(@local_networks, $block);
}

sub add_list_host {
    # Still more option parsing.
    my ($option, $host_name) = @_;

    die "$0:  Mailing list host name must be a FQDN.\n"
	unless $host_name =~ /\D[.]\D/;
    $list_host_p{lc($host_name)}++;
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

sub local_p {
    # Return true if the address is on one of our local networks.
    my ($address) = @_;

    for my $block (@local_networks) {
	return $block
	    if $block->address_contained_p($address);
    }
}

sub classify_sender_address {
    # Return true if the sender address is known to be a trusted local machine,
    # i.e. the local host or a non-relay machine on the local network, undef if
    # the address belongs to a relay, or 0 otherwise.
    my ($address) = @_;

    if ($address eq '127.0.0.1') {
	return 'local';
    }
    elsif ($relay_p{$address}) {
	# We check this before local_p in case the relay is on our local
	# network.
	return;
    }
    elsif (local_p($address)) {
	return 'lan';
    }
    else {
	# Definitely from elsewhere.
	return 0;
    }
}

sub local_header_p {
    # The sole argument is expected to be a "Received:\s*" header string,
    # possibly multiline, but without the part matching this RE.  Return 1 if
    # the header indicates locally-generated (as opposed to relayed) email,
    # "undef" if the header shows internal relaying, and 0 otherwise (which
    # presumably means that the message came from somewhere else).  Important:
    # Do NOT return "undef" unless the "from" host is trustworthy.
    my ($hdr) = @_;

    if (! $hdr) {
	# Can't make a determination.
	return;
    }
    elsif ($hdr =~ /qmail \d+ invoked by uid (\d+)/) {
	# qmail locally originated.
	return 'local';
    }
    elsif ($hdr =~ /^by \S+ \(Postfix/) {
	# Postfix locally originated.
	return 'local';
    }
    elsif ($hdr =~ /^from \S+ \(HELO \S+\) \((\S+\@)?($dotted_quad)\)/) {
	# qmail format
	return classify_sender_address($2);
    }
    elsif ($hdr =~ /^from \S+ \(localhost \[127.0.0.1\]\)/) {
	# Postfix format for the loopback re-receipt of SpamAssassin results.
	return;
    }
    elsif ($hdr =~ /^from \S+ \(\S+ \[($dotted_quad)\]\)/) {
	# Postfix format.
	return classify_sender_address($1);
    }
    elsif ($hdr =~ /^from \S+ \(HELO \S+\) \(($dotted_quad)\)/) {
	# qmail format.
	return classify_sender_address($1);
    }
    elsif ($hdr =~ /qmail \d+ invoked from network/) {
	# qmail adds two headers for SMTP mail; we must check the second one.
	return;
    }
    # Postfix only adds a single header, so we need to make a definite
    # determination on this header to avoid spoofing.
    elsif ($hdr =~ /from userid \d+/) {
	return 'local';
    }
    else {
	return 0;
    }
}

sub list_host_p {
    # The sole argument is expected to be a "Received:\s*" header string
    # generated by our server, possibly multiline, but without the part
    # matching this RE.  This is expected to be of the form:
    #
    #    "from anna.opensuse.org (foo.opensuse.org [195.135.8.3]) by ..."
    #
    # where "anna.opensuse.org" is what the corresponding server told us when
    # it connected to our server, "195.135.8.3" is the IP address we got from
    # the connection (and therefore trustworthy), and "foo.opensuse.org" is
    # what reverse DNS told us about the IP address (and therefore somewhat
    # less trustworthy).  Return undef if we have no header, 'list' if the rDNS
    # name or a suffix is an email list host in %list_host_p, and 0 otherwise.
    my ($hdr) = @_;

    return
	# Can't make a determination.
	unless $hdr;

    # Collapse linear whitespace for ease of parsing.
    $hdr =~ s/[ \t\n]+/ /;
    if ($hdr =~ /from \S+ \((\S+) \[\S+\]\)/) {
	my $host_name = $1;
	# Chop off prefixes to see if something matches.
	while ($host_name) {
	    return 'list'
		if $list_host_p{$host_name};
	    $host_name =~ s/^[^.]+[.]//
		or last;
	}
    }
    # No match.
    return 0;
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
    $local_p = list_host_p($header)
	if defined($local_p) && ! $local_p;
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
if (%match_domains || @suffix_domains) {
    # Local domains already specified on the command line.
}
elsif ($local_domain_file && -r $local_domain_file) {
    # Qmail "locals" configuration.
    open(my $in, '<', $local_domain_file)
	or fail("Could not open '$local_domain_file':  $!");
    while (<$in>) {
	chomp;
	add_local_domain($_);
    }
}
elsif (-x '/usr/sbin/postconf') {
    # Just ask Postfix.
    chomp(my $destination = `/usr/sbin/postconf -hx mydestination`);
    for my $name (split(/,\s*/, $destination)) {
	add_local_domain($name)
	    unless $name =~ /^localhost/;
    }
}
fail("No local domain names found, use --locals or --add-local.\n")
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

=head1 NAME

forged-local-address.pl - detect forged emails by examining "Received:" headers

=head1 SYNOPSIS

    forged-local-address.pl [ --verbose ... ] [ --not ]
		[ --sender-re=<regexp> ... ] [ --list-host=<host-name ... ]
		[ --add-local=<domain-name> ... ] [ --relay-ip=<dotted-quad> ]
		[ --network-prefix=<netblock> ... ]
		[ --locals=<local-domain-file> ]

=head1 DESCRIPTION

Each mail transport agent (MTA) adds at least one "Received:" header
to the front of the pile, so the first one was added by your MTA
before it handed the message off to the delivery code (including
C<forged-local-address.pl>).  Since we know it came from the local
MTA, we know it is trustworthy.  This header will say what system it
came from, which may be another local system (which we must trust), a
relay (which we trust but which may also accept email from anywhere),
and the Internet at large (definitely not trustworthy).

=over 4

=item 1.

If it's from a local system, defined by having a local network
address, then it's allowed to use local domain names in "From:" and
sender addresses.  We assume such systems will only originate emails,
or may relay emails within the network, but will not relay from the
outside world.

=item 2.

If it's a designated relay system, then we defer judgment, based on
the next "Received:" header, which is still trustworthy because it
came from the relay and we trust the relay.

=item 3.

If it's a designated mailing list server, identified by the
L</--list-host> option, then we assume we're seeing our post coming
back to us, and consider it "local" even though it's not.

=item 4.

Otherwise it's from the wild, wild West, and we disallow any of our
local domain names in the envelope sender and the "Sender:", "From:",
and "Reply-To:" headers, including parenthetical comments and text
outside of any angle brackets that would normally contain just the
user name (if there are angle brackets, that is the real email
address).

=back

In order to make these determinations, we need to know three things:

=over 4

=item 1.

The set of domain names considered local, specified by C<--locals> and
C<--add-local>.  This can usually be defaulted; without
C<--add-local>, C<--locals> defaults to F</var/qmail/control/locals>,
which works for Qmail, and if that file doesn't exist, we ask Postfix.

=item 2.

The local netblock(s), specified by C<--network-prefix>, which
defaults to the directly connected IPv4 networks identified in "ip a"
output.

=item 3.

Any external systems that are authorized to relay mail from the
Internet at large, identified by C<--relay-ip>.

=item 4.

Any external mailing list servers that are authorized by name to send
copies of posts that appear to original from local email addresses,
identified by C<--list-host>.

=back

The defaults for these values are usually sufficient; the only thing
that C<forged-local-address.pl> can't figure out on its own is the
existence of authorized relays and mailing list servers.

Currently, the only supported MTAs are Qmail and Postfix.  Since
"Received:" headers are supposed to be fairly standard, it's possible
that C<forged-local-address.pl> may be able to recognize the headers
added by other MTAs, but there is also a lot of variation just between
these two, so it's not likely.

=head2 Usage for Qmail

To use this with Qmail, put the following in your C<.qmail> file:

	| bouncesaying "Go away." bin/forged-local-address.pl

Alternatively, you could redirect all address forgeries to a different
folder:

	| condredirect rogers-spam bin/forged-local-address.pl

In this case, the C<rogers-spam> address must be defined (e.g. via a
C<.qmail-spam> file).

=head2 Usage for Postfix

OK, I confess, I don't really interface C<forged-local-address.pl>
directly with Postfix.  Instead, I use C<qmail-deliver.pl> which
preserves my Qmail-style delivery options, adds whitelisting and
blacklisting, and throws in C<forged-local-address.pl> as a bonus.

=head2 Options

These are parsed with C<Getopt::Long>, so any unique prefix is acceptable.

=over 4

=item B<--add-local>

Specifies a single domain name to add to the "local" set.  If the name
starts with a ".", it is a wildcard; otherwise, the whole domain name
must match.

=item B<--list-host>

Specifies a single domain name to add to the set of mailing list
servers.  Any host that has an rDNS name with this as a suffix is
considered valid as a mailing list host, so emails using one of our
addresses coming from such a relay are not considered forgeries.

=item B<--locals>

Specifies a file of domain names.  Each line in this file is treated
as if it had been added individually with C<--add-local>.  The file
name defaults to '/var/qmail/control/locals' (which only makes sense
for qmail) but only if C<--add-local> was never specified.

The C<--locals> file is consulted only if we determine that the
message comes from the outside world, so we must check its addresses
for forgeries, and we have no C<--add-local> hosts.  If the
C<--locals> file does not exist, we try to extract the equivalent
information from the C<postconf> command, assuming that Postfix is the
MTA.  If afterwards, no domain names are defined, we die with a fatal
error.

=item B<--network-prefix>

Specifies an IPv4 network block (i.e. "192.168.23" or "73.38.11.6/22")
that is considered local, and may be repeated to add multiple local
blocks.  Local sender or "From:" addresses are considered legitimate
if a message comes from a non-relay system within such a block.  If
not specified, this defaults to all IPv4 subnets found in the output
of C<ip a>.  The option is mostly used for testing.

=item B<--not>

Inverts the sense of the return value.  Normally,
C<forged-local-address.pl> exits true (0) if it detects a forgery, and
false (1) otherwise.  If C<--not> is specified,
C<forged-local-address.pl> exits 1 for a forgery, and 0 otherwise.

=item B<--relay-ip>

Specifies the dotted-quad (i.e. IPv4 only) address of a system with a
non-local IP address that is authorized to relay mail.

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
invoked by alias" (or the Postfix equivalent).  This is legitimate.

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

=head1 BUGS

There is no error if the C<--locals> file does not exist, even if it
was specified explicitly.

=cut
