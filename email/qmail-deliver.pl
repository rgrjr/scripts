#!/usr/bin/perl
#
# Deliver a message the way that qmail-local does.
#
# [created (as post-deliver.pl, based on postfix-sort.pl).  -- rgr, 28-Apr-08.]
# [created (based on post-deliver.pl).  -- rgr, 9-Sep-16.]
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Mail::Header;
use IO::String;

my $help = 0;
my $man = 0;
my $usage = 0;
my $tag = "$0 ($$)";
my $test_p = 0;
my $verbose_p = 0;
my $redeliver_p = 0;
my $ext_from_deliver_to_p = 0;
my (@whitelists, @blacklists, @host_deadlists, @deadlists);
my @forged_local_args;

# Selection of /usr/include/sysexits.h constants.
use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;

### Process command-line arguments.

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'test!' => \$test_p,
	   'verbose+' => \$verbose_p,
	   'redeliver!' => \$redeliver_p,
	   'use-delivered-to!' => \$ext_from_deliver_to_p,
	   'deadlist=s' => \@deadlists,
	   'host-deadlist=s' => \@host_deadlists,
	   'whitelist=s' => \@whitelists,
	   'blacklist=s' => \@blacklists,
	   make_forged_local_pushers
	       (qw(network-prefix=s add-local=s relay-ip=s)))
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
if ($verbose_p) {
    # debugging.
    open(STDERR, ">>post-deliver.log") or die;
}

### Subroutines.

sub make_forged_local_pushers {
    # Given a list of GetOptions keywords, provide them with subs that pass the
    # values on the @forged_local_args list.
    map {
	my $fla_arg = $_;
	$fla_arg =~ s/=.*//;
	$fla_arg = "--$fla_arg";	# Do this once.
	($_ => sub { push(@forged_local_args, $fla_arg => $_[1]); });
    } @_;
}

sub parse_headers {
    # Given a $message_source stream, read the email headers from it, plus any
    # mbox-format "From " line it may include, and Use Mail::Header to parse
    # the headers, returning the parsed headers, from line, and a string
    # containing all unparsed headers as three values.
    my ($message_source) = @_;

    if (! ref($message_source)) {
	open(my $message_stream, '<', $message_source)
	    || die "$0:  Can't open '$message_source':  $!";
	return parse_headers($message_stream);
    }

    # Read headers into a string.
    my $mbox_from_line = '';
    my $header = '';
    while (<$message_source>) {
	if (! $header && /^From / && ! $mbox_from_line) {
	    $mbox_from_line = $_;
	    # Don't put this in $header.
	    next;
	}
	$header .= $_;
	last
	    # end of headers.
	    if /^$/;
    }

    # Parse headers into a Mail::Header object.
    my $header_stream = IO::String->new($header);
    # Note that supplying a non-file stream to "new" does not work.
    my $head = Mail::Header->new();
    $head->read($header_stream);
    return ($head, $mbox_from_line, $header);
}

sub write_maildir_message {
    # Given the name of a maildir (ending with a "/"), parsed headers, a string
    # containing all unparsed headers, and a "message source" which is either a
    # (blessed) stream with the rest of the message or an (unblessed) file name
    # string, deliver the message by copying it into a unique "$maildir/new"
    # file.  If there is a "$maildir/msgid" subdirectory and the message has a
    # "Message-ID:" header value, then create a file with the name of the value
    # if it does not already exist, else assume it's a duplicate and skip the
    # delivery.
    my ($maildir, $head, $headers, $message_source) = @_;

    if ($verbose_p && $head->count('delivered-to')) {
	my @delivered_to = $head->get('delivered-to');
	warn("Message for $maildir has '",
	     join(q{', '}, map { chomp; $_; } @delivered_to), "'.\n")
	    # It's unusual to have more than one of these.
	    if @delivered_to > 1 || $verbose_p > 1;
    }

    # Validate maildir.
    unless ($maildir =~ m@/$@ && -d $maildir) {
	warn "$tag:  invalid maildir '$maildir'.\n";
	exit(EX_TEMPFAIL);
    }

    # Check for a duplicate message ID.
    my $msgid_dir = $maildir . 'msgid';
    my $message_id = $head->get('message-id') || '';
    if ($message_id && -d $msgid_dir && -w $msgid_dir) {
	$message_id =~ s/[^-_\@\w\d.]//g;
	$message_id = lc($message_id);
	if (length($message_id) > 10) {
	    my $msgid_file = "$msgid_dir/$message_id";
	    if (-e $msgid_file) {
		# Already seen.
		warn("Message '$message_id' for $maildir ",
		     "has already been delivered.\n")
		    if $verbose_p;
		if (ref($message_source)) {
		    while (<$message_source>) { }
		}
		else {
		    unlink($message_source);
		}
		return;
	    }
	    # Touch the file.
	    open(my $out, '>', $msgid_file);
	}
    }

    # Write to a temp file.
    chomp(my $host = `hostname`);
    my $temp_file_name = $maildir . 'tmp/' . join('.', time(), "P$$", $host);
    # warn "$tag:  Writing to $temp_file_name.\n";
    if (ref($message_source)) {
	# Copy from the stream.
	open(my $out, '>', $temp_file_name) or do {
	    warn "$tag:  can't write temp file '$temp_file_name':  $!";
	    exit(EX_TEMPFAIL);
	};
	print $out ("X-Delivered-By: $tag\n", $headers);
	while (<$message_source>) {
	    print $out $_;
	}
    }
    elsif ($redeliver_p) {
	# Move the file.
	my $result = 0;
	$result = system('mv', $message_source, $temp_file_name)
	    unless $test_p;
	die("$0:  Move of '$message_source' to '$temp_file_name' failed:  $!")
	    if $result;
    }
    else {
	# Copy the file.
	my $result = system('cp', $message_source, $temp_file_name);
	die("$0:  Copy of '$message_source' to '$temp_file_name' failed:  $!")
	    if $result;
    }

    # Punt if just testing.
    if ($test_p) {
	warn "Delivered message to $maildir [not]\n";
	unlink($temp_file_name);
	return;
    }

    # Rename uniquely.
    my $inode = (stat($temp_file_name))[1];
    my $file_name = ($maildir . 'new/'
		     . join('.', time(), "I${inode}P$$", $host));
    rename($temp_file_name, $file_name);
    warn "Delivered message to $maildir\n"
	if $verbose_p;
}

sub process_qmail_file {
    # Given the name of a "dot-qmail" file, the message parsed headers, a
    # string containing all unparsed headers, and a "message source" which is
    # either a (blessed) stream with the rest of the message or an (unblessed)
    # file name string, open the dot-qmail file and process its directives line
    # by line.  Unfortunately, all we can handle are maildirs and delivery to
    # /dev/null; piped commands are ignored, and all others are flagged as
    # errors.
    # [this will fail in the case of multiple delivery.  -- rgr, 9-Sep-16.]
    my ($qmail_file, $head, $message_headers, $message_source) = @_;

    open(my $in, '<', $qmail_file) or do {
	warn "$tag:  Can't open '$qmail_file':  $!";
	exit(EX_TEMPFAIL);
    };
    while (<$in>) {
	chomp;
	if (/^\s*(#|$)/) {
	    # Ignore comments and blank lines.
	}
	elsif (substr($_, 0, 1) eq '|') {
	    # Ignore piped commands.
	    warn "Ignoring piped command in $qmail_file\n"
		if $verbose_p > 1;
	}
	elsif (m@^(&?dev-null|/dev/null)$@) {
	    # Explicitly ignored.
	    warn "Delivered message to /dev/null\n"
		if $verbose_p > 1;
	}
	elsif (m@^\S+/$@) {
	    # Maildir delivery.
	    write_maildir_message($_, $head, $message_headers,
				  $message_source);
	}
	else {
	    die "$tag:  In $qmail_file:  Unsupported directive '$_'.\n";
	}
    }
}

sub find_localpart {
    # Pull a localpart from a Delivered-To or X-Original-To header.  This is
    # our fallback for redelivery, since $ENV{EXTENSION} won't be defined but
    # $ENV{RECIPIENT} gets stored in a "Delivered-To:" header.
    my ($head) = @_;

    for my $header_name (qw(delivered-to x-original-to)) {
	for my $header_value ($head->get($header_name)) {
	    $header_value =~ s/@.*//g;
	    $header_value =~ s/\s+//g;
	    return lc($header_value);
	}
    }
}

sub find_extension {
    # Find the extension from the difference in the latest two "Delivered-To:"
    # header localparts if --use-delivered-to was specified and such headers
    # exist, or directly from $ENV{EXTENSION}, or the from localpart or
    # $ENV{LOCAL} if we can find one (in which case we have to assume the first
    # hyphen is the extension separator), or just assume the extension is "".
    my ($head) = @_;

    if ($ext_from_deliver_to_p && $head->count('delivered-to') >= 2) {
	# If we have at least two "Delivered-To:" headers, we might be able to
	# extract an extension that was dropped between the previous address
	# ($local2, e.g. "rogers-emacs") and the final destination ($local1,
	# e.g. "rogers").  Note that comparing the two localparts means that we
	# don't have to guess which of possibly many hyphens is the right one.
	my ($local1, $local2)
	    = map { chomp;
		    my ($localpart) = split(/@/);
		    lc($localpart);
	} $head->get('delivered-to');
	my $len1 = length($local1); 
	if (length($local2) > $len1 + 1) {
	    my $suffix = substr($local2, $len1);
	    if (substr($suffix, 0, 1) eq '-'
		&& $local1 eq substr($local2, 0, $len1)) {
		warn("$tag:  Found suffix '$suffix' from 'Delivered-To:'\n")
		    if $verbose_p > 1;
		return substr($suffix, 1)
	    }
	}
    }

    my $extension = $ENV{EXTENSION};
    return $extension
	if $extension;
    my $localpart = find_localpart($head) || $ENV{LOCAL};
    return $1
	if $localpart && $localpart =~ /^[^-]+-(.+)$/;
    return '';
}

sub address_forged_p {
    # Returns true if forged-local-address.pl says it claims to be local but
    # came from somewhere else.
    my ($header) = @_;

    return
	# If we don't know what's local, we can't check.
	unless @forged_local_args;
    # Get forged-local-address.pl from the same place we are running.
    my $fla = $0;
    $fla =~ s@[^/]*$@forged-local-address.pl@;
    unshift(@forged_local_args, ('--verbose') x ($verbose_p - 1))
	if $verbose_p > 1;
    my $fla_cmd = join(' ', "| $fla", @forged_local_args);
    open(my $out, $fla_cmd)
	or die "could not open $fla";
    print $out $header, "\n";
    my $result;
    # If "close" got an error, then it returns false and $! is the error code,
    # else $? is the process return code.  Only if both are false do we want to
    # treat the message as forged.
    if (close($out)) {
	# Success.
	return $result = ! $?;
    }
    elsif (! $!) {
	# Nonzero exit, which (in shell land) means false (not a forgery).
	return;
    }
    else {
	# Some other error must have happened when running the piped command;
	# pretend like everything's OK so we don't lose mail.
	warn "$tag:  got error '$!' (", $!+0, ") and result $? from $fla\n";
    }
    return $result;
}

sub check_lists {
    # Given the parsed email headers, return an existing dot-qmail file that
    # should be used for this message based on address matching against the
    # global lists.  We assume that .qmail-spam exists, so this should not be
    # called unless that file is known to exist.
    my ($head) = @_;

    my $find_addresses = sub {
	# Extract a hashref of all addresses present in all passed headers.
	my $addresses = { };
	for my $header_name (@_) {
	    for my $header ($head->get($header_name)) {
		# Get rid of RFC822 comments first, so we are not confused by
		# commas in comments.  Parentheses nest.
		while ($header =~ s/\(([^()]*)\)//g) {
		}
		$header =~ s/\"[^""]*\"//g;
		# Process each address.
		for my $address (split(/\s*,\s*/, $header)) {
		    if ($address =~ /<([^<>]+)>/) {
			my $addr = $1;
			$addr =~ s/\s+//g;
			$addresses->{lc($addr)}++;
		    }
		    else {
			$address =~ s/\s+//g;
			$addresses->{lc($address)}++
			    if $address;
		    }
		}
	    }
	}
	return $addresses;
    };

    my $address_match_p = sub {
	my ($addresses, @list_names) = @_;

	for my $list_name (@list_names) {
	    open(my $in, '<', $list_name)
		or die "$tag:  Can't open list '$list_name':  $!";
	    while (<$in>) {
		chomp;
		if (! /[*?]/) {
		    return 1
			if $addresses->{lc($_)};
		}
		else {
		    # Use "glob" semantics for matching.
		    my $regexp = $_;
		    $regexp =~ s/[*]/.*/g;
		    $regexp =~ s/[?]/./g;
		    for my $address (keys(%$addresses)) {
			return 1
			    if $address =~ /^$regexp$/i;
		    }
		}
	    }
	}
	return;
    };

    my $host_match_p = sub {
	# This is just an $address_match_p on the host part.
	my ($addresses, @host_list_names) = @_;

	$address_match_p->({ map { s/.*@//;
				   ($_ => 1);
			     } keys(%$addresses) },
			   @host_list_names);
    };

    # Check for dead destination addresses first.
    my $dead_dest = -r '.qmail-dead' ? '.qmail-dead' : '.qmail-spam';
    if (@deadlists) {
	my $to_addresses = $find_addresses->(qw(to cc));
	my $recipient = $ENV{RECIPIENT};
	$to_addresses->{$recipient}++
	    if $recipient;
	return $dead_dest
	    if $address_match_p->($to_addresses, @deadlists);
    }

    # Now check the sender address(es).
    my $from_addresses = $find_addresses->(qw(sender from reply-to));
    $from_addresses->{$ENV{SENDER}}++
	if $ENV{SENDER};
    if (grep { $_ =~ /^\d*@/; } keys(%$from_addresses)) {
	# All-digit localpart; punt.
	return $dead_dest;
    }
    elsif (@blacklists && $address_match_p->($from_addresses, @blacklists)) {
	return '.qmail-spam';
    }
    elsif (@host_deadlists
	   && $host_match_p->($from_addresses, @host_deadlists)) {
	return $dead_dest;
    }
    elsif (@whitelists && ! $address_match_p->($from_addresses, @whitelists)) {
	my $qmail_file = '.qmail-spam';
	$qmail_file = '.qmail-grey'
	    if -r '.qmail-grey';
	return $qmail_file;
    }
}

sub deliver_message {
    # Given a message source (either a file name or a stream), figure out what
    # to do with it, possibly finding an appropriate qmail file if a to/from
    # address is found on a list, looking for the dot-qmail file for an
    # extension if the destination has one, else doing the usual dot-qmail or
    # Maildir/ fallback.
    my ($message_source) = @_;

    # Read the headers to find where this message was originally addressed.
    my ($head, $mbox_from_line, $header) = parse_headers($message_source);

    # Check for forgery, whitelisting, blacklisting, and/or deadlisting.
    my $qmail_file;
    if (-r '.qmail-spam') {
	my $file;
	if (address_forged_p($header)) {
	    # Found spam; redirect it.
	    $qmail_file = -r '.qmail-forged' ? '.qmail-forged' : '.qmail-spam';
	}
	elsif (@whitelists || @blacklists || @host_deadlists || @deadlists
	       and $file = check_lists($head)) {
	    $qmail_file = $file;
	}
    }

    # Deliver the message.
    my $extension;
    if ($qmail_file) {
	process_qmail_file($qmail_file, $head, $header, $message_source);
    }
    elsif ($extension = find_extension($head)
	   and -r ".qmail-$extension") {
	process_qmail_file(".qmail-$extension", $head, $header,
			   $message_source);
    }
    elsif (-r '.qmail') {
	process_qmail_file('.qmail', $head, $header, $message_source);
    }
    else {
	write_maildir_message('Maildir/', $head, $header, $message_source);
    }
}

### Main code.

if (@ARGV) {
    # Deliver each listed file as a message.
    for my $file_name (@ARGV) {
	deliver_message($file_name);
    }
}
else {
    # Normal delivery of a message on STDIN.
    deliver_message(\*STDIN);
}
exit(EX_OK);

__END__

=head1 NAME

qmail-deliver.pl - deliver mail like qmail-local, with whitelists/blacklists

=head1 SYNOPSIS

    qmail-deliver.pl [ --help | --man | --usage ]

    qmail-deliver.pl [ --verbose ... ] [ --[no]test ] [ --redeliver ]
    		     [ --add-local=<name> ... ] [ --[no-]use-delivered-to ]
		     [ --network-prefix=<IP> ... ] [ relay-ip=<IP> ... ]
		     [ --whitelist=<file> ... ] [ --blacklist=<file> ... ]
		     [ --deadlist=<file> ... ] [ --host-deadlist=<file> ... ]

=head1 DESCRIPTION

Given a series of command-line options, decide what to do with one or
more messages as C<qmail-local> would, consulting C<.qmail> files in
the current directory (normally the home directory of the user to whom
the message is addressed), and deliver it appropriately.  The message
may be supplied on the standard input (the normal delivery situation),
or multiple message file names may be supplied on the command line
with the L</--redeliver> option.

In addition to the usual Qmail extension and dot-qmail customizations,
C<qmail-deliver.pl> may also check source and destination addresses
against lists specified by command-line options.  The list options are
L</--whitelist>, L</--blacklist>, L</--deadlist>, and
L</--host-deadlist>;
these name files which contain lists of email addresses.  
In these addresses, "?" and "*" are considered wildcards
which match any single character and zero or more characters
respectively.  All of these command-line options may be repeated in order to
specify multiple files of addresses.
In order to work, the list file options also require a
F<.qmail-spam> file and optionally (for the deadlists) a
F<.qmail-dead> file as the destination for emails with matching addresses,
though they may just contain the line
F</dev/null> in order to discard matching emails.

The L</--add-local>, L</--network-prefix>, and L</--relay-ip> options
are for the C<forged-local-address.pl> script; if any of these three
is supplied (and all may be repeated), then C<forged-local-address.pl>
is used to detect whether the sender has spoofed a local address
illegitimately in order to avoid whitelisting or other antispam
defenses.

=head2 Message processing

Note that list processing only happens if (a) at least one list was
specified and (b) a F<.qmail-spam> file exists, since F<.qmail-spam>
is what tells C<qmail-deliver.pl> what to do with messages that fail
the testing implied by the address lists.

=over 4

=item 1.

Nonlocal messages are checked first for a forged local address (if
enabled) and sent to F<.qmail-forged> if that exists, else to
F<.qmail-spam>.  Note that C<forged-local-address.pl> is in charge of
determining whether the mail was originated locally or not.

=item 2.

If we find any deadlisted B<recipients> in the "To:" or "CC:"
headers, the message is sent to F<.qmail-dead> if that exists, else to
F<.qmail-spam>.

=back

Then we check all B<senders>, including the envelope sender,
and all addresses in the "Sender:", "From:", and "Reply-To:" fields.

=over 4

=item 1.

If we find a sender with "name" of all digits, the message is sent to
F<.qmail-dead> if that exists, else to F<.qmail-spam>.

=item 2.

If we find a blacklisted sender, the message is sent to
F<.qmail-spam>).

=item 3.

If we find a dead host, the message is sent to F<.qmail-dead> if that
exists, else to F<.qmail-spam>.

=item 4.

If the message has gotten this far and there is a whitelist, and the
B<no sender matches> any whitelisted address, then the message is sent
to F<.qmail-grey> if that exists, else to F<.qmail-spam>.

=item 5.

Otherwise (there is no whitelist or some sender matched it), the
message is sent through normal Qmail dot-file processing, honoring the
usual recipient address extensions.

=back

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--white>
or C<--wh> for C<--whitelist>), options with arguments can be given as
two words (e.g. C<--white list.text>) or in one word separated by an "="
(e.g. C<--white=list.text>), and "-" can be used instead of "--".

=over 4

=item B<--add-local>

Specifies a single domain name to add to the "local" set.  If the name
starts with a ".", it is a wildcard; otherwise, the whole domain name
must match.
This is passed verbatim to C<forged-local-address.pl>.

=item B<--blacklist>

Names a file of blacklisted senders; if a sender is on this list and
a F<.qmail-spam> file exists, then the message is sent
to F<.qmail-spam>.
See L</Message processing> for details.

=item B<--deadlist>

Names a file of deadlisted B<recipients>; if the message is addressed
(either "To:" or "CC:" or the envelope
sender) to someone on this list, it is sent to
F<.qmail-dead> if that exists, else to F<.qmail-spam>.
See L</Message processing> for details.

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--host-deadlist>

Names a file of blacklisted sender hosts; if a sender host is on this
list, then the message is sent to F<.qmail-dead> if that exists, else
to F<.qmail-spam>.
See L</Message processing> for details.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--network-prefix>

Specifies an IPv4 network block (i.e. "192.168.23" or "73.38.11.6/22")
that is considered local, and may be repeated to add multiple local
blocks.  Local sender or "From:" addresses are considered legitimate
if a message comes from a non-relay system within such a block.
This is passed verbatim to C<forged-local-address.pl>.

=item B<--redeliver>

Specify this to move message files given on the command line, as
opposed to supplied on the standard input.  This is helpful when a
previous invocation has misfiled something.

=item B<--relay-ip>

Specifies the dotted-quad (i.e. IPv4 only) address of a system with a
non-local IP address that is authorized to relay mail.
This is passed verbatim to C<forged-local-address.pl>.

=item B<--notest>

=item B<--test>

When C<--test> is specified, the new message file is not created.  The
default is C<--notest>.  B<WARNING:> Specifying C<--test> is
guaranteed to lose mail when used on a live email address; this is
really only useful with C<--redeliver>.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--no-use-delivered-to>

=item B<--use-delivered-to>

Whether or not to use "Delivered-To:" headers when trying to find an
address extension.  The default is C<--no-use-delivered-to> because
when C<--use-delivered-to> is specified, this overrides the normal
environment C<EXTENSION> specification provided by the mail server;
normally, the mail server should know better.

The C<--use-delivered-to> option is helpful when an intermediate
server must be put in charge of aliasing in order to funnel multiple
addresses toward a single destination address for final delivery.  If
the intermediate server adds (for instance):

    Delivered-To: rogers-emacs@rgrjr.com

before redirecting the message to C<rogers@rgrjr.com>, and the
destination server adds:

    Delivered-To: rogers@rgrjr.com

before handing the message off to C<qmail-deliver.pl>, then
C<qmail-deliver.pl> can use these headers to re-split the different
alias email streams.  In this case, it would extract "emacs" as the
desired extension, and direct that message according to the
F<.qmail-emacs> file.  Note that only the localpart of each address is
consulted; the "@rgrjr.com" in each address is ignored completely, and
in fact is allowed to be different.  Note that these "Delivered-To:"
headers will be added in the B<reverse> of the order shown here (the
most recent ones are towards the top), and only the (chronologically)
last two such headers are consulted.

=item B<--verbose>

Prints debugging information if specified, appended to the
F<post-deliver.log> file in the current directory (typically the
delivery user's home directory).  May be repeated for extra verbosity.

=item B<--whitelist>

Names a file of whitelisted senders; if the message has not been
blacklisted, or deadlisted, we finally check for whitelisting.  If the
message sender is whitelisted (or there is no whitelist), then the
message is processed normally, either through the default F<.qmail>
file or to the default F<Maildir>.

If the message fails the whitelist, it is processed according to a
F<.qmail-grey> file if that exists, else a F<.qmail-spam> file if that
exists.
See L</Message processing> for details.

=back

=head1 BUGS

If you find any, please let me know.

=head1 SEE ALSO

=over 4

=item C<forged-local-address.pl> 

=item Qmail

=back

=head1 COPYRIGHT

Copyright (C) 2003-2021 by Bob Rogers C<< <rogers@rgrjr.dyndns.org> >>.
This script is free software; you may redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<< <rogers@rgrjr.dyndns.org> >>

=cut
