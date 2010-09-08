#!/usr/bin/perl
#
# Run diff on two files, either of which may be remote, fetched via scp.
#
# [created.  -- rgr, 8-Sep-10.]
#
# $Id$

use strict;
use warnings;

use File::Temp;

my $diff_opts = '-u';

## Parse args.

$diff_opts = shift(@ARGV)
    if @ARGV && $ARGV[0] =~ /^-/;
die "$0:  Need two file arguments"
    unless @ARGV == 2;
my ($file1, $file2) = @ARGV;

## Subs.

my @temp_files;
my $temp_dir = $ENV{TMP} || '/tmp';
sub make_file_local {
    my $name = shift;

    if ($name =~ /:/) {
	my $temp_name = File::Temp::tempnam($temp_dir, 'sdiff');
	push(@temp_files, $temp_name);
	my $result = system('scp', '-q', $name, $temp_name);
	die("$0:  Copying '$name' to '$temp_name' failed with code $result")
	    unless $result == 0;
	return $temp_name;
    }
    else {
	return $name;
    }
}

## Main code.

# Make the files local, and feed them to diff.
my $local1 = make_file_local($file1);
my $local2 = make_file_local($file2);
open(my $in, "diff $diff_opts '$local1' '$local2' |")
    or die "$0:  Could not open pipe from diff:  $!";
# Copy preliminaries.
my $n_changes_remaining = @temp_files;
while (<$in>) {
    $n_changes_remaining--
	if s/^--- $local1/--- $file1/;
    $n_changes_remaining--
	if s/^\+\+\+ $local2/+++ $file1/;
    print;
    last
	unless $n_changes_remaining;
}
# Copy the rest (without the overhead).
while (<$in>) {
    print;
}
# And clean up.
unlink(@temp_files);

__END__

=head1 NAME

sdiff.pl -- scp diff

=head1 SYNOPSIS

    sdiff.pl [ <diff-opts> ] file1 file2

=head1 DESCRIPTION

Given the names of two files, either of which may be remote, run
C<diff> on them, using C<scp> to fetch them locally first (so remote
files are named using the C<scp> "host:/path/to/file" syntax).

Options to C<diff> may be specified before the file names.  The
default options are "-u".

An attempt is made to use the remote file name in the diff heading
(the "---" and "+++" lines), but the date(s) will be wrong for remote
files.

=head1 VERSION

 $Id$

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
