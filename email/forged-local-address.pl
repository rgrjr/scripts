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

GetOptions('verbose+' => \$verbose_p,
	   'not!' => \$not_p,
	   'add-local=s' => \&add_local_domain,
	   'network-prefix=s' => \$local_network_prefix,
	   'locals=s' => \$local_domain_file)
    or pod2usage();

my ($spam_exit, $legit_exit) = ($not_p ? (1, 0) : (0, 1));
if (! $local_network_prefix) {
    open(my $in, 'ifconfig |')
	or die;
    while (defined(my $line = <$in>)) {
	$local_network_prefix = $1, last
	    if $line =~ /inet addr:(192\.168\.\d+)./;
    }
    die "Couldn't find IP address"
	unless $local_network_prefix;
}

### Subroutines.

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

    $host =~ s/.*@//;
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
    my $hdr = shift;

    if (! $hdr) {
	# Can't make a determination.
	return;
    }
    elsif ($hdr =~ /qmail \d+ invoked by /) {
	# qmail locally originated.
	'local';
    }
    elsif ($hdr =~ /by $local_network_prefix\.\d+ with SMTP/) {
	# qmail format for receipt from a LAN host.
	'lan';
    }
    elsif ($hdr !~ /Postfix/) {
	# Assume qmail, which adds two headers for SMTP mail; we need to check
	# the second one.
	return;
    }
    # Postfix only adds a single header, so we need to make a definite
    # determination on this header to avoid spoofing.
    elsif ($hdr =~ /from userid \d+/) {
	'local';
    }
    elsif ($hdr =~ /\[([\d.]+)\.\d+\]/ && $1 eq $local_network_prefix) {
	'lan';
    }
    else {
	0;
    }
}

### Main code.

# Check headers for local vs. remote.
my $message = Mail::Header->new(\*STDIN);
my $local_p = local_header_p($message->get('Received', 0));
$local_p = local_header_p($message->get('Received', 1))
    if ! defined($local_p);
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
	add_local_domain($_);
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
	# Get rid of RFC822 comments first, so we are not confused by commas in
	# comments.  Parentheses nest.
	while ($header =~ s/\([^()]*\)//g) {
	    # Keep matching.
	}
	$header =~ s/\"[^""]*\"//g;
	for my $address (split(/\s*,\s*/, $header)) {
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
warn "win:  remote, sender '$host' not local\n"
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

=item B<--verbose>

Turns on verbose debugging messages.  This can be useful to find out
how a given message is getting classified.

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
