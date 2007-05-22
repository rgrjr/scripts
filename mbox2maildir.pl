#!/usr/bin/perl -w
#
# [I've forgotten where I got this . . .  -- rgr, 23-May-04.]
#
# See http://cr.yp.to/proto/maildir.html for Maildir folder format details.
#
# $Id$

=pod

=head1 NAME

mbox2maildir.pl - convert a BSD mbox file into a Maildir.

=head1 SYNOPSIS

  mbox2maildir B<-d> B<-n> mbox maildir

=head1 DESCRIPTION

Converts a BSD mbox into a qmail style maildir.

=head1 OPTIONS

=over 4

=item B<-d>

Debug mode.  Print what's going on to stderr.

=item B<-n>

If specified, the mail will appear as unread mail in the maildir.  If
not, then the mail will be in the "read" state.

=back

=cut

use strict;
use warnings;

use vars qw($DEBUG);

$DEBUG = 0;

use Getopt::Std;
use Sys::Hostname;
use Mail::Field;

sub usage {
    my $me = $0;
    $me =~ s!.*/!!;
    die "usage: $me [-n] mbox maildir\n";
}



#-----------------------------------------------------------------------
# This lot should really be in a module...

sub ismaildir ($) {
    my $md = shift;
    return (-d $md && -d "$md/cur" && -d "$md/new" && -d "$md/tmp");
}

# XXX Should use mkpath().
sub maildirmake ($) {
    my $md = shift;
    die "usage: maildirmake(dir)\n"
	unless $md;
    my @dirs = ($md, "$md/cur", "$md/new", "$md/tmp");
    umask 0077;
    foreach my $d (@dirs) {
	mkdir $d, 0755
	    or die "mkdir($d): $!\n";
    }
}

# Copy the contents of a mailbox into a maildir.
sub convert ($$;$) {
    my ($mbox_file_name, $maildir, $new) = @_;

    # Should the messages be flagged as newly arrived?
    my $sub = $new ? "new" : "cur";
    my $inf = $new ? "" : ":2,S";

    die "usage: convert(mbox,maildir)\n"
	unless $mbox_file_name && $maildir;
    die "not a file: $mbox_file_name\n"
	unless -f $mbox_file_name;
    die "not a maildir: $maildir\n"
	unless ismaildir($maildir);

    my $host = hostname;
    my $i = 0;

    my $write_message = sub {
	# Write the passed message content as a maildir message, extracting the
	# delivery time from the "Date:" field.  This is not strictly necessary,
	# but it works better for Outlook in combination with Courier IMAP;
	# otherwise, Outlook uses the wrong date until you look at the message.
	my $contents = shift;

	# First, figure out the time from the message.
	my $time;
	if ($contents =~ /\nDate: *([^\n]*)/i) {
	    my $date_string = $1;
	    my $date = Mail::Field->new(Date => $date_string);
	    $time = $date->time;
	}
	# Sometimes, messages have defective dates (particularly spam).
	$time ||= time();

	# Now write the file.
	$i++;
	my $msg_name = "${maildir}/${sub}/${time}.$$\_${i}.${host}${inf}";
	open(my $out, ">$msg_name")
	    or die "$0:  Could not open '$msg_name':  $!";
	warn "creating $msg_name\n"
	    if $DEBUG;
	print $out $contents
	    or die "$0:  Could not print to '$msg_name':  $!";
	undef $out;	# to close.
	utime($time, $time, $msg_name)
	    # Nonfatal problem.
	    or warn("$0:  Could not change mod time ",
		    "to $time for $msg_name:  $!");
    };

    open(my $mbox, $mbox_file_name)
	or die "open($mbox_file_name): $!\n";
    my $current_message = '';
    my $last_line_empty_p = 1;	# the start of the file counts.
    while (<$mbox>) {
	if ($_ eq "\n") {
	    # If this comes before a "From " line, we will swallow it.
	    $last_line_empty_p = 1;
	}
	elsif ($last_line_empty_p && m/^From /) {
	    # Start of a new message.
	    $write_message->($current_message)
		if $current_message;
	    $current_message = '';
	    $last_line_empty_p = 0;
	}
	else {
	    $current_message .= "\n"
		if $last_line_empty_p;
	    s/^>From /From /;
	    $current_message .= $_;
	    $last_line_empty_p = 0;
	}
    }
    $write_message->($current_message)
	if $current_message;
}

#-----------------------------------------------------------------------

my %opt;
getopts("dn", \%opt)
    or usage;
$DEBUG = $opt{d};
usage
    unless @ARGV == 2;
convert($ARGV[0], $ARGV[1], $opt{n});
