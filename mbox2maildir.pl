#!/usr/bin/perl -w
#
# [I've forgotten where I got this . . .  -- rgr, 23-May-04.]
#
# $Id$

=pod

=head1 NAME

mbox2maildir - convert a BSD mbox file into a Maildir.

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
use vars qw($DEBUG);

$DEBUG = 0;

use Getopt::Std;
use Sys::Hostname;

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
    my ($mbox, $maildir, $new) = @_;

    # Should the messages be flagged as newly arrived?
    my $sub = $new ? "new" : "cur";
    my $inf = $new ? "" : ":2,S";

    die "usage: convert(mbox,maildir)\n"
	unless $mbox && $maildir;
    die "not a file: $mbox\n"
	unless -f $mbox;
    die "not a maildir: $maildir\n"
	unless ismaildir($maildir);

    open(MBOX, $mbox)
	or die "open($mbox): $!\n";
    my $now = time;
    my $host = hostname;
    my $i = 0;
    my $fn;
    while (<MBOX>) {
	if (m/^From /) {	# New message.
	    # See http://cr.yp.to/proto/maildir.html for details
	    $fn = "${maildir}/${sub}/${now}.$$\_${i}.${host}${inf}";
	    $i++;
	    open(OUT, ">$fn")
		or die "open($fn): $!\n";
	    warn "creating $fn\n"
		if $DEBUG;
	} else {
	    s/^>From /From /;
	    print OUT $_
		or die "print($fn): $!\n";
	}
    }
    close OUT;
    close MBOX;
}

#-----------------------------------------------------------------------

my %opt;
getopts("dn", \%opt)
    or usage;
$DEBUG = $opt{d};
usage
    unless @ARGV == 2;
convert($ARGV[0], $ARGV[1], $opt{n});
