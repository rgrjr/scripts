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
my $verbose_p = 0;
my ($whitelist, $blacklist);

# Selection of /usr/include/sysexits.h constants.
use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;

### Process command-line arguments.

GetOptions('verbose+' => \$verbose_p,
	   'whitelist=s' => \$whitelist,
	   'blacklist=s' => \$blacklist);
if ($verbose_p) {
    # debugging.
    open(STDERR, ">>post-deliver.log") or die;
}

### Subroutines.

sub write_maildir_message {
    my ($maildir, $headers) = @_;

    # Validate maildir.
    unless ($maildir =~ m@/$@ && -d $maildir) {
	warn "$tag:  invalid maildir '$maildir'.\n";
	exit(EX_TEMPFAIL);
    }

    # Write to a temp file.
    chomp(my $host = `hostname`);
    my $temp_file_name = $maildir . 'tmp/' . join('.', time(), "P$$", $host);
    # warn "$tag:  Writing to $temp_file_name.\n";
    open(my $out, '>', $temp_file_name) or do {
	warn "$tag:  can't write temp file '$temp_file_name':  $!";
	exit(EX_TEMPFAIL);
    };
    print $out ($headers);
    while (<STDIN>) {
	print $out $_;
    }
    my $inode = (stat($temp_file_name))[1];
    close($out);

    # Rename uniquely.
    my $file_name = ($maildir . 'new/'
		     . join('.', time(), "I${inode}P$$", $host));
    rename($temp_file_name, $file_name);
    warn "Delivered message to $maildir\n"
	if $verbose_p;
}

sub process_qmail_file {
    # [this will fail in the case of multiple delivery.  -- rgr, 9-Sep-16.]
    my ($qmail_file, $message_headers) = @_;

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
	    write_maildir_message($_, $message_headers);
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

### Main code.

## Read the headers to find where this message was originally addressed.

my $mbox_from_line = '';
my $header = '';
my $qmail_file;
while (<STDIN>) {
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
# Parse headers.
my $header_stream = IO::String->new($header);
# Note that supplying a non-file stream to "new" does not work.
my $head = Mail::Header->new();
$head->read($header_stream);

## Check for forgery.

if (-r '.qmail-spam') {
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
	$result = $?;
    }
    elsif (! $!) {
	# Nonzero exit, which (in shell land) means false (not a forgery).
	$result = 1;
    }
    else {
	# Some other error must have happened when running the piped command;
	# pretend like everything's OK so we don't lose mail.
	warn "$0:  got error '$!' (", $!+0, ") and result $? from $fla\n";
	$result = 1;
    }
    if (! $result) {
	# Found spam; redirect it.
	$qmail_file = '.qmail-spam';
    }
}

## Check for whitelisting.

my $message_headers = $mbox_from_line . "X-Delivered-By: $0 ($$)\n" . $header;
if (! $qmail_file && ($whitelist || $blacklist)) {
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
	my ($list_name) = @_;

	open(my $in, '<', $list_name)
	    or die "$tag:  Can't open list '$list_name':  $!";
	while (<$in>) {
	    chomp;
	    return 1
		if $addresses{$_};
	}
	return;
    };

    if ($blacklist && $address_match_p->($blacklist)) {
	$qmail_file = '.qmail-spam';
    }
    elsif ($whitelist && ! $address_match_p->($whitelist)) {
	$qmail_file = '.qmail-spam';
	$qmail_file = '.qmail-grey'
	    if -r '.qmail-grey';
    }
}

## Deliver the message.

my $extension;
if ($qmail_file) {
    process_qmail_file($qmail_file, $message_headers);
}
elsif ($extension = find_extension($head)
       and -r ".qmail-$extension") {
    process_qmail_file(".qmail-$extension", $message_headers);
}
else {
    write_maildir_message('Maildir/', $message_headers);
}
exit(EX_OK);
