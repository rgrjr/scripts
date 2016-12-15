#!/usr/bin/perl
#
# Deliver a message the way that qmail-local does.
#
# [created (post-deliver.pl, based on postfix-sort.pl).  -- rgr, 28-Apr-08.]
# [created (based on post-deliver.pl).  -- rgr, 9-Sep-16.]
#

use strict;
use warnings;

use Getopt::Long;
use Mail::Header;
use IO::String;

my $tag = "$0 ($$)";
my $test_p = 0;
my $verbose_p = 0;
my $redeliver_p = 0;
my (@whitelists, @blacklists);

# Selection of /usr/include/sysexits.h constants.
use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;

### Process command-line arguments.

GetOptions('test!' => \$test_p,
	   'verbose+' => \$verbose_p,
	   'redeliver!' => \$redeliver_p,
	   'whitelist=s' => \@whitelists,
	   'blacklist=s' => \@blacklists);
if ($verbose_p) {
    # debugging.
    open(STDERR, ">>post-deliver.log") or die;
}

### Subroutines.

sub parse_headers {
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
    my ($maildir, $headers, $message_source) = @_;

    # Validate maildir.
    unless ($maildir =~ m@/$@ && -d $maildir) {
	warn "$tag:  invalid maildir '$maildir'.\n";
	exit(EX_TEMPFAIL);
    }

    # Write to a temp file.
    chomp(my $host = `hostname`);
    my $temp_file_name = $maildir . 'tmp/' . join('.', time(), "P$$", $host);
    # warn "$tag:  Writing to $temp_file_name.\n";
    my $inode;
    if (ref($message_source)) {
	# Copy from the stream.
	open(my $out, '>', $temp_file_name) or do {
	    warn "$tag:  can't write temp file '$temp_file_name':  $!";
	    exit(EX_TEMPFAIL);
	};
	print $out ("X-Delivered-By: $0 ($$)\n", $headers);
	while (<$message_source>) {
	    print $out $_;
	}
	$inode = (stat($temp_file_name))[1];
	close($out);
    }
    elsif ($redeliver_p) {
	# Move the file.
	my $result = system('mv', $message_source, $temp_file_name);
	die("$0:  Move of '$message_source' to '$temp_file_name' failed:  $!")
	    if $result;
	$inode = (stat($temp_file_name))[1];
    }
    else {
	# Copy the file.
	my $result = system('cp', $message_source, $temp_file_name);
	die("$0:  Copy of '$message_source' to '$temp_file_name' failed:  $!")
	    if $result;
	$inode = (stat($temp_file_name))[1];
    }

    # Punt if just testing.
    if ($test_p) {
	warn "Delivered message to $maildir [not]\n";
	unlink($temp_file_name);
	return;
    }

    # Rename uniquely.
    my $file_name = ($maildir . 'new/'
		     . join('.', time(), "I${inode}P$$", $host));
    rename($temp_file_name, $file_name);
    warn "Delivered message to $maildir\n"
	if $verbose_p;
}

sub process_qmail_file {
    # [this will fail in the case of multiple delivery.  -- rgr, 9-Sep-16.]
    my ($qmail_file, $message_headers, $message_source) = @_;

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
	    # Silently ignore piped commands.
	}
	elsif (/^&?dev-null$/) {
	    # Explicitly ignored.
	}
	elsif (m@^\S+/$@) {
	    # Maildir delivery.
	    write_maildir_message($_, $message_headers, $message_source);
	}
	else {
	    die "$tag:  In $qmail_file:  Unsupported directive '$_'.\n";
	}
    }
}

sub find_localpart {
    # Pull a localpart from a Delivered-To or X-Original-To header.
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
    # Find the extension from $ENV{EXTENSION}, or the localpart if we can find
    # one, or assume it is "".
    my ($head) = @_;

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
    # came from somewhere else..
    my ($header) = @_;

    # Get forged-local-address.pl from the same place we are running.
    my $fla = $0;
    $fla =~ s@[^/]*$@forged-local-address.pl@;
    open(my $out, "| $fla --network-prefix 10.0.0 --add-local rgrjr.dyndns.org --add-local rgrjr.com")
	or die "could not open $fla";
    print $out $header, "\n";
    my $result;
    # If "close" got an error, then it returns false and $! is the error code,
    # else $? is the process return code.  Only if both are false do we want to
    # treat the message as forged.
    if (close($out)) {
	# Success.
	$result = ! $?;
    }
    elsif (! $!) {
	# Nonzero exit, which (in shell land) means false (not a forgery).
    }
    else {
	# Some other error must have happened when running the piped command;
	# pretend like everything's OK so we don't lose mail.
	warn "$tag:  got error '$!' (", $!+0, ") and result $? from $fla\n";
    }
    return $result;
}

sub check_lists {
    my ($head) = @_;

    # Find all source addresses.
    my %addresses;
    for my $header_name (qw(sender from reply-to)) {
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
		    $addresses{lc($addr)}++;
		}
		else {
		    $address =~ s/\s+//g;
		    $addresses{lc($address)}++
			if $address;
		}
	    }
	}
    }

    my $address_match_p = sub {

	for my $list_name (@_) {
	    open(my $in, '<', $list_name)
		or die "$tag:  Can't open list '$list_name':  $!";
	    while (<$in>) {
		chomp;
		return 1
		    if $addresses{lc($_)};
	    }
	}
	return;
    };

    if (@blacklists && $address_match_p->(@blacklists)) {
	return '.qmail-spam';
    }
    elsif (@whitelists && ! $address_match_p->(@whitelists)) {
	my $qmail_file = '.qmail-spam';
	$qmail_file = '.qmail-grey'
	    if -r '.qmail-grey';
	return $qmail_file;
    }
}

sub deliver_message {
    my ($message_source) = @_;

    # Read the headers to find where this message was originally addressed.
    my ($head, $mbox_from_line, $header) = parse_headers($message_source);

    # Check for forgery, whitelisting, and/or blacklisting.
    my $qmail_file;
    if (-r '.qmail-spam') {
	my $file;
	if (address_forged_p($header)) {
	    # Found spam; redirect it.
	    $qmail_file = '.qmail-spam';
	}
	elsif (@whitelists || @blacklists
	       and $file = check_lists($head)) {
	    $qmail_file = $file;
	}
    }

    # Deliver the message.
    my $extension;
    if ($qmail_file) {
	process_qmail_file($qmail_file, $header, $message_source);
    }
    elsif ($extension = find_extension($head)
	   and -r ".qmail-$extension") {
	process_qmail_file(".qmail-$extension", $header, $message_source);
    }
    else {
	write_maildir_message('Maildir/', $header, $message_source);
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
