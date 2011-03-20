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
# $Id$

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

$config->verbose_p($verbose_p);
$config->test_p($test_p);

# Find partitions that want cleaning.
my @partitions = Backup::Partition->find_partitions();
my @partitions_to_clean;
for my $partition (@partitions) {
    my $clean = $config->find_option('clean', $partition->mount_point, 0);
    next
	unless $clean;
    $partition->prefixes([ split(/[, ]+/, $clean) ])
	unless $clean eq '*';
    push(@partitions_to_clean, $partition);
}
die "$0:  Nothing to clean.\n"
    unless @partitions_to_clean;

# We need to find all dumps at once, because we don't know how they fall across
# the various partitions, we don't know which prefixes we're going to need, and
# we can't properly find the current ones without having them all.
my $search_roots = [ map { $_->mount_point; } @partitions_to_clean ];
warn 'Looking for dumps in ', join(' ', @$search_roots)
    if $verbose_p;
my $dump_set_from_prefix
    = Backup::DumpSet->find_dumps(prefix => '*', root => $search_roots);

# Clean dumps by partition.
$config->sort_dumps_by_partition($dump_set_from_prefix, \@partitions_to_clean);
for my $partition (@partitions_to_clean) {
    $partition->clean_partition($config);
}
exit($config->fail_p ? 1 : 0);

__END__

=head1 NAME

clean-backups.pl -- Automated interface to remove old backups.

=head1 SYNOPSIS

[tbd.  -- rgr, 14-Mar-11.]

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

    # Note that this must be the mount point here.
    [/scratch4]
    clean = home, src
    min-free-space = 5

For each partition on the local system that stores backups and for
which the "clean" option specifies some or all backup prefixes, try to
ensure that the following constraints are all satisfied:

=over 4

=item 1.

At least C<min-free-space> gigabytes (as reported by C<df>) are free.

=item 2.

At least C<min-odd-retention> days worth of odd daily backups
(e.g. levels 3, 5, 7, and 9) are kept on all local partitions.

=item 3.

At least C<min-even-retention> days worth of even daily backups
(e.g. levels 2, 4, 6, and 8) are kept on all local partitions.

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

    clean = home, src

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

=head1 OPTIONS

[finish.  -- rgr, 19-Mar-11.]

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

=head1 VERSION

 $Id$

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
