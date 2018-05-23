#!/usr/bin/perl -w
#
# clean-backups.pl:  Remove old backup files.
#
# POD documentation at the bottom.
#
# Copyright (C) 2011 by Bob Rogers <rogers@rgrjr.dyndns.org>.
# This script is free software; you may redistribute it
# and/or modify it under the same terms as Perl itself.
#

use strict;
use warnings;

BEGIN {
    # This is for testing, and only applies if you don't use $PATH.
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Getopt::Long;
use Pod::Usage;
use Backup::Config;
use Backup::DumpSet;
use Backup::Partition;

### Parse command-line options.

my $verbose_p = 0;
my $test_p = 0;
my $usage = 0;
my $help = 0;
my $config = Backup::Config->new();
GetOptions('verbose+' => \$verbose_p,
	   'test!' => \$test_p,
	   'config=s' => sub { die "$0:  The --conf option must be first.\n" },
	   'usage|?' => \$usage, 'help' => \$help)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

$verbose_p ||= 1
    if $test_p;
$config->verbose_p($verbose_p);
$config->test_p($test_p);

# Find partitions that want cleaning.
my $partitions_to_clean = $config->find_partitions_to_clean();
if (! @$partitions_to_clean) {
    warn "$0:  No partitions to clean.\n"
	if $verbose_p;
    exit(0);
}

# We need to find all dumps at once, because we don't know how they fall across
# the various partitions, we don't know which prefixes we're going to need, and
# we can't properly find the current ones without having them all.
my $search_roots = [ $config->find_search_roots() ];
$search_roots = [ map { $_->mount_point; } @$partitions_to_clean ]
    unless @$search_roots;
warn 'Looking for dumps in ', join(' ', @$search_roots)
    if $verbose_p;
my $dump_set_from_prefix
    = Backup::DumpSet->find_dumps(prefix => '*', root => $search_roots);

# Clean dumps by partition.
$config->sort_dumps_by_partition($dump_set_from_prefix, $partitions_to_clean);
for my $partition (@$partitions_to_clean) {
    $partition->clean_partition($config);
}
exit($config->fail_p ? 1 : 0);

__END__

=head1 NAME

clean-backups.pl -- Automated interface to remove old backups.

=head1 SYNOPSIS

        clean-backups.pl [ --conf=<config-file> ]
                         [ --[no]test ] [ --verbose ... ]

        clean-backups.pl [ --usage | --help ]

=head1 DESCRIPTION

The C<clean-backups.pl> script removes old backup dumps created by
C<backup.pl>, in order to keep a prescribed minimum amount of free
disk space to allow room for new backup dumps.  Unlike backup
creation, backup cleaning is done based on the partitions where the
backups are kept, not the partitions that are backed up (which may not
even be on the same system).  Each partition that holds backups is
treated independently, and multiple backup prefixes (denoting the
partition from which the backup was made) are considered when deciding
what to free up.

For each partition on the local system that stores backups and for
which the "clean" option specifies some or all backup prefixes,
C<clean-backups.pl> tries to ensure that the following constraints are
all satisfied:

=over 4

=item 1.

At least C<min-free-space> gigabytes (as reported by C<df>) are free.
the default is 10GB.

=item 2.

At least C<min-odd-retention> days worth of odd daily backups
(e.g. levels 3, 5, 7, and 9) are kept on all local partitions.  The
default is 30 days.

=item 3.

At least C<min-even-retention> days worth of even daily backups
(e.g. levels 2, 4, 6, and 8) are kept on all local partitions.  The
default is 60 days.

=back

Note that when we say we will keep "X days worth" of backups, we
really mean that only backups that are older than X days are eligible
for deletion.

C<clean-backups.pl> attempts to meet these constraints for each
partition independently by first deleting all slices of just enough
odd daily dumps of any prefix that are not current and are past their
retention time to satisfy the C<min-free-space> requirement.  If there
are not enough odd dailies to produce the required free space, then
even dailies are treated in a similar fashion.  If this is still not
enough, then C<clean-backups.pl> emits an error message (after having
already deleted any eligible dumps), and exits with a nonzero code at
completion.

The "clean" option for the partition may be of the form

    clean = home, shared

to consider only backups with the home or src prefix, or

    clean = *

to consider them all.  The order in which prefixes are deleted within
a given category (e.g. odd dailies) is not defined.

Current backups are never deleted, nor are level 0 or level 1 dumps.
[Separate treatment of level 1 dumps may be added in the future,
though it is not clear what priority to give them, since level 1 dumps
are written to DVD and may sometimes be more "expendable" than
dailies.  In any case, level 0 dumps should always be removed
manually.  -- rgr, 14-Mar-11.]

=head2 Configuration file format

C<clean-backups.pl> is driven by a configuration file (see the
C<--conf> option) with a "stanza" for each partition, one of which
might look like this:

    # Note that this must be the mount point here.
    [/scratch4]
    clean = home, src
    min-free-space = 5

Comments (starting with "#") and blank lines are ignored, keywords and
values appear one per line and are separated by "=", and whitespace is
ignored except when internal to a partition name, keyword, or value.

Partitions are named with a single token, which must be the mount
point without a trailing "/" (e.g. "/scratch4" in the example above),
and not the device name (which might be something like "/dev/sda4").
The only exception is that a "default" partition may be given
keyword/value pairs that apply for all partitions unless overridden.
Keyword/value pairs appearing before the first partition are also
included in the "default" partition.  All partitions other than
"default" must start with a "/".

When looking for a value, we search the specific partition first, then
the "default" partition (if any), and then use the global default.

=head2 Configuration options

This is the complete list of options used by C<clean-backups.pl>.
Other options are silently ignored, because they may be needed by
other backup utilities, so be on the lookout for spelling errors.

=over 4

=item B<clean>

Specifies the prefixes to clean as a comma-separated list, or "*" to
clean them all.  For example,

    clean = home, shared

There is no global default (which is why C<clean-backups.pl> requires
a configuration file in order to be useful).

=item B<min-even-retention>

Specifies the minimum number of days worth of even daily backups
(e.g. levels 2, 4, 6, and 8) that must kept on all local partitions.
Even dailies newer than this are never deleted.

=item B<min-free-space>

Specifies the target free space for the partition.  The default is
10GB.

=item B<min-odd-retention>

Specifies the minimum number of days worth of odd daily backups
(e.g. levels 3, 5, 7, and 9) that must kept on all local partitions.
Odd dailies newer than this are never deleted, but all of them that
are older than this will be deleted before C<clean-backups.pl> starts
in on the even dailies.

=item B<test>

If this is true (i.e. specified and neither zero nor the empty
string), then no deletions are done, just as if C<--test> had been
specified, and the C<--notest> command line option is ignored.  This
configuration keyword allows testing to be enabled for some partitions
and not others.

=item B<verbose>

If this is a number that is not zero, then additional progress
information is printed, just as if C<--verbose> had been specified the
corresponding number of times.  The C<--verbose> command line
overrules the configuration option for all partitions.  This
configuration keyword allows verbosity to be enabled for some
partitions and not others.

=back

=head1 OPTIONS

As with all C<Getopt::Long> scripts (and with the exception of
C<--conf>), single hyphens work the same as double hyphens, options
may be abbreviated to the shortest unambiguous string (e.g. "-v" for
C<--verbose>).

=over 4

=item B<--conf>

Specifies the configuration file to use.  If specified, this must be
the first option on the command line, and must not be abbreviated.

If not specified, C<clean-backups.pl> looks for a file named
C<.backup.conf> in the user's home directory (if the "HOME"
environment variable exists), else the global C</etc/backup.conf>
directory.

=item B<--help>

Displays the complete script documentation page.

=item B<--notest>

=item B<--test>

If specified, no deletions are done, but C<clean-backups.pl> goes
through the motions.  The default is C<--notest>.  This also implies
C<--verbose>; if sufficient verbosity is enabled, C<clean-backups.pl>
will tell you exactly what it would do.

=item B<--verbose>

Specifies additional progress output; C<clean-backups.pl> normally
runs silently except in case of error.  If C<--verbose> is specified
once, per-partition information is show.  If specified twice,
additional information on dumps that are being deleted is shown,
Finally, specifying C<--verbose> three times produces per-slice
information.

=item B<--usage>

Displays the "Usage" and "Options" section of this page.

=back

=head1 KNOWN BUGS

This script can only be driven via a config file; it ought to be
possible to use the command line to modify or even specify completely
how to do the cleaning.

It is not possible to specify different retention policies for
different prefixes.

On a former C<vacuum.pl> destination partition, once fresh backups are
no longer copied there, C<clean-backups.pl> will refuse to remove what
it thinks are the "current" dumps, even though they are well past the
minimum retention limits.  This is OK for dump destination partitions,
but not for C<vacuum.pl> destinations, so there ought to be an option
to control this.

If you find any others, please let me know.

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<restore(8)>

=item DAR home page L<http://dar.linux.free.fr/>

=item L<dar(1)>

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=item C<backup.pl> (L<http://www.rgrjr.com/linux/backup.pl.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2011 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
