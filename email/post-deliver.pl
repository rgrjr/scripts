#! /usr/bin/perl -w
#
# For calling from .forward files or the TMDA "DELIVERY" option:  Sorts into
# maildirs as directed by command-line args and the "X-Original-To:"  header.
#
# This is what we have to go through to get Postfix to use TMDA for multiple
# addresses for a given user.  Doing this is easy in qmail (and would be easy in
# Postfix if I could figure out how to get wildcard .forward files).
#
# [created (based on postfix-sort.pl).  -- rgr, 28-Apr-08.]
#
# $Id$

use strict;
use warnings;

# debugging
# open(STDERR, ">>post-deliver.log") or die;

my $program_name = "$0 v0.1";
$program_name =~ s@.*/@@;	# drop the directory name.
chomp(my $date = `date`);
$date = substr($date, 4, -9);	# drop the DOW, TZ, and year.
my $tag = "$date $program_name [$$]";

### Process command-line arguments.

# These all need to be of the form "prefix=Maildir/".

my %maildir_from_prefix;
for my $pair (@ARGV) {
    if ($pair =~ /=/) {
	my ($prefix, $maildir) = split(/=/, $pair, 2);
	$maildir_from_prefix{$prefix} = $maildir;
    }
    else {
	warn "Unknown arg '$pair'.\n";
    }
}

### Read the headers to find where this message was originally addressed.

# Look for "X-Original-To:" instead of "To:" since different mail clients will
# format the latter differently, and we're too lazy to use an RFC822-compliant
# parser.  -- rgr, 25-Apr-08.
my $mbox_from_line = '';
my $header = '';
my $maildir;
while (<STDIN>) {
    if (! $header && /^From / && ! $mbox_from_line) {
	$mbox_from_line = $_;
	# Don't put this in $header.
	next;
    }
    $header .= $_;
    if (/^$/) {
	# end of headers.
	last;
    }
    elsif (/^X-Original-To: (\S+)@/i) {
	my $localpart = $1;
	if ($maildir_from_prefix{$localpart}) {
	    # Exact match.
	    $maildir = $maildir_from_prefix{$localpart};
	}
	else {
	    for my $prefix (keys(%maildir_from_prefix)) {
		$maildir = $maildir_from_prefix{$prefix}
	            if $localpart =~ /^$prefix/;
	    }
	}
	last
	    if $maildir;
    }
}

### Check for forgery.
my $spam_maildir = $maildir_from_prefix{spam};
if ($spam_maildir) {
    # Get forged-local-address.pl from the same place we are running.
    my $fla = $0;
    $fla =~ s@[^/]*$@forged-local-address.pl@;
    open(my $out, "| $fla --add-local rgrjr.dyndns.org --add-local rgrjr.com")
	or die "could not open $fla";
    print $out $header, "\n";
    my $result = close($out) && $?;
    # warn "got result $result";
    if (! $result) {
	# Found spam; redirect it.
	$maildir = $spam_maildir;
    }
}

### Deliver the message.

# Default the maildir.
$maildir ||= $maildir_from_prefix{default} || './Maildir/';
die "$tag:  invalid maildir '$maildir'"
    unless $maildir =~ m@/$@ && -d $maildir;

# Write to a temp file.
chomp(my $host = `hostname`);
my $temp_file_name = $maildir . 'tmp/' . join('.', time(), "P$$", $host);
# warn "$tag:  Writing to $temp_file_name.\n";
open(my $out, ">$temp_file_name")
    or die "can't write $temp_file_name:  $!";
print $out ($mbox_from_line, "X-Delivered-By: $program_name\n", $header);
while (<STDIN>) {
    print $out $_;
}
my $inode = (stat($temp_file_name))[1];
close($out);

# Rename uniquely.
my $file_name = $maildir . 'new/' . join('.', time(), "I${inode}P$$", $host);
rename($temp_file_name, $file_name);
# warn "$tag:  Delivered to $file_name.\n";

# Check for "vacation" program delivery.
my $vacation_user = $maildir_from_prefix{vacation};
system("/usr/bin/vacation $vacation_user < $file_name")
    if $vacation_user;

# Check for copy delivery.
my $copy_maildir = $maildir_from_prefix{copy};
if ($copy_maildir) {
    my $base_name = $file_name;
    $base_name =~ s@.*/@@;
    my $temp_file = join('', $copy_maildir, 'new/', $base_name);
    if ($file_name ne $temp_file) {
	system("cp -p $file_name $temp_file");
	# Rename uniquely.
	my $inode = (stat($temp_file))[1];
	my $unique_name = join('.', time(), "I${inode}P$$", $host);
	my $copy_file = join('', $copy_maildir, 'new/', $unique_name);
	rename($temp_file, $copy_file);
    }
}

exit(0);
