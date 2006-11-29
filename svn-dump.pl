#!/usr/bin/perl
#
#    svn-dump.pl:  Create a Subversion repository dump.
#
# [created.  -- rgr, 3-Jun-06.]
#
# [$Id$]

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

# this is where the Subversion binaries live on my system, and it's not part of
# $PATH as supplied by cron.
$ENV{PATH} = '/usr/local/bin:'.$ENV{PATH};

my ($from_revision, $to_revision, $incremental_p, $repository);
my $deltas_p = 1;
my $verbose_p = 0;
my $usage = 0;
my $help = 0;

GetOptions('verbose+' => \$verbose_p,
	   'usage|?' => \$usage, 'help' => \$help,
	   'from-revision=i' => \$from_revision,
	   'to-revision=i' => \$to_revision,
	   'deltas!' => \$deltas_p,
	   'incremental!' => \$incremental_p,
	   'repository=s' => \$repository)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

$repository ||= shift(@ARGV)
    or die "$0:  No repository specified.\n";

### Subroutine.

sub svn_dump {
    my ($repository, $from_revision, $to_revision) = @_;

    $repository =~ s{ / $ }{}x;
    die "$0:  '$repository' is not a directory.\n"
	unless -d $repository;

    # Default the 'to' revision number.
    chomp($to_revision = `svnlook youngest '$repository'`)
	if ! $to_revision;
    die "$0:  'To' revision is not an integer.\n"
	unless $to_revision =~ /^\d+$/;

    # Construct the file name, and ensure that we haven't already made it.
    my $output_file_name = "$repository-$to_revision.svndump";
    $output_file_name =~ s@.*/@@;
    return
	# Apparently, there have been no changes since the last dump.
	if -e $output_file_name;

    # Default the 'from' revision number to one more than the last revision of
    # this repository that we dumped.
    if (! defined($from_revision)) {
	# Look for previously created files.
	$from_revision = 0;
	my $prefix = $output_file_name;
	$prefix =~ s/-\d+\.svndump$//;
	opendir(FILES, '.')
	    or die;
	while (my $file_name = readdir(FILES)) {
	    next
		unless $file_name =~ /$prefix-(\d+)\.svndump$/;
	    $from_revision = $1
		if $from_revision < $1;
	}
	# $from_revision may still be 0 if there are no matching files; that's
	# OK.  if not, increment to the next rev.
	$from_revision++
	    if $from_revision;
    }
    die "$0:  Nothing to dump into $output_file_name.\n"
	# This shouldn't happen unless the user specified some odd combination
	# of options.
	if $from_revision > $to_revision;

    # Default $incremental_p.
    $incremental_p = ($from_revision > 0)
	if ! defined($incremental_p);

    # Make the dump.
    my @command_and_options = qw(svnadmin dump);
    push(@command_and_options, '--incremental')
	if $incremental_p;
    push(@command_and_options, '--deltas')
	if $deltas_p;
    open(STDOUT, ">$output_file_name")
	or die "$0:  Couldn't redirect stdout to '$output_file_name':  $!";
    my $error_file_name = "$output_file_name.err";
    # We need to redirect stderr, because 'svnadmin dump' keeps a running tally
    # of versions dumped there, and we don't want that to mess up cron use.
    open(STDERR, ">$error_file_name")
	or die "$0:  Couldn't redirect stderr to '$error_file_name':  $!";
    my $result
	= system(@command_and_options,
		 '--revision', "$from_revision:$to_revision",
		 $repository);
    if (0 != $result) {
	unlink($output_file_name);	# just in case.
	die("$0:  Oops -- got result $result; ",
	    "see $error_file_name for details.\n");
    }

    # Clean up.
    close(STDOUT);
    close(STDERR);
    unlink($error_file_name);
}

### Main code.

svn_dump($repository, $from_revision, $to_revision);
for my $other_repository (@ARGV) {
    svn_dump($other_repository);
}

__END__

=head1 NAME

svn-dump.pl - Dump a Subversion repository

=head1 SYNOPSIS

    svn-dump.pl [ --verbose ] [ --usage|-? ] [ --help ]
                [ --from-revision=<int> ] [ --to-revision=<int> ]
                [ --[no]deltas ] [ --[no]incremental ]
                [ --repository=<repos-path> | <repos-path> ... ]

=head1 DESCRIPTION

Dumps one or more Subversion repositories, each to the latest of a series
of numbered files in the current directory.  If the C</home/me/svn/foo>
repository is being dumped, and its latest revision is 317, then the
file will be written to the C<foo-317.svndump> file; if this file
already exists, then C<svn-dump.pl> exits immediately.  This is useful
for using from a C<cron> job; the resulting series of dump files play
nicely with incremental filesystem dumps.

If more than one repository path is specified on the command line, then the
C<--from-revision> and C<--to-revision> options apply only to the first.

=head1 OPTIONS

=over 4

=item B<--verbose>

If specified, extra information messages are printed.  [Not actually
used at present.  -- rgr, 3-Jun-06.]

=item B<--usage>

Prints a brief usage message.

=item B<--help>

Prints a more detailed help message.

=item B<--from-revision>

Specifies the starting revision to dump; this only applies to the
first repository if more than one is specified.  The default is one
plus the revision in the latest C<foo-*.svndump> file, or zero if
there are no matching files.  Specify C<--from-revision=0> to get
everything.

=item B<--to-revision>

Specifies the latest revision to dump; this only applies to the first
repository if more than one is specified.  If omitted, C<svn-dump.pl>
asks Subversion for the number of the latest revision.  If the
C</home/me/svn/foo> repository is being dumped, and its latest
revision is 317, then the file will be written to the
C<foo-317.svndump> file in the current directory.

=item B<--[no]deltas>

Specifies whether or not each revision of the series after the first
should be dumped as binary deltas with respect to the previous
revision.  The default is C<--deltas>.

=item B<--[no]incremental>

Specifies whether or the first revision of the series should be dumped
incrementally with respect to the previous revision.  If
C<--noincremental> is specified, the C<--from-revision> is treated as
if it was indeed the first revision, with all previous revisions
merged into it.  The default is C<--noincremental> if
C<--from-revision> is zero (i.e. we are dumping the whole thing
anyway), and C<--incremental> otherwise (the usual case).

=item B<--repository>

Specifies the path to the Subversion repository to be dumped.  This
may also be specified as a positional argument, i.e. without the
C<--repository> prefix.  Any number of positional repository paths may
be specified; if C<--repository> is also specified, then that path is
considered to be the first.

=back

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 3-Jun-06.]

=head1 SEE ALSO

=over 4

=item Subversion (L<http://www.collab.net/products/subversion.html>)

=item C<svnadmin dump> (L<http://svnbook.red-bean.com/nightly/en/svn.ref.svnadmin.c.dump.html>)

=back

=head1 VERSION

 $Id$

=head1 BUGS

If you find any, please let me know.

=head1 COPYRIGHT

 Copyright (C) 2006 by Bob Rogers <rogers@rgrjr.dyndns.org>.
 This script is free software; you may redistribute it and/or modify it
 under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
