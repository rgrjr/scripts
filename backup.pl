#!/usr/bin/perl -w
#
# backup.pl:  Create and verify a dump file.
#
# Copyright (C) 2000-2002 by Bob Rogers <rogers@rgrjr.dyndns.org>.
# This script is free software; you may redistribute it
# and/or modify it under the same terms as Perl itself.
#
#    Modification history:
#
# created, based heavily on shell script (bash) version.  -- rgr, 21-Oct-02.
# change $destination_dir dflt, do_or_die '-ignore-return'.  -- rgr, 27-Oct-02.
# more changes in dump/dest dir defaulting.  -- rgr, 17-Nov-02.
# update doc.  -- rgr, 27-Feb-03.
#

use strict;
use Getopt::Long;
use Pod::Usage;

my $VERSION = '2.0';	# really, this is the first perl version.
my $warn = 'backup.pl';
# [this was '/dev/hda9', but that was too error-prone.  -- rgr, 21-Oct-02.]
my $default_dump_partition = '';

my $test_p = 0;
my $verbose_p = 0;
my $file_date = '';
my $partition_abbrev = '';
my $dump_name = '';
# [$dump_dir is the scratch directory to which we write, $destination_dir is the
# final directory to which we rename.  -- rgr, 17-Nov-02.]
my $dump_dir = '';
my $cd_p = 1;
# [changed this default.  -- rgr, 27-Oct-02.]
# [changed again.  -- rgr, 17-Nov-02.]
my $destination_dir = '';
my $dump_volume_size = '';
my ($dump_partition, $level);
# We want to use full pathnames for these programs (which are not yet covered by
# options) so that we don't have to rely on $ENV{'PATH'} being set up correctly,
# e.g. by cron.  [new pathnames for SuSE 8.1; now using the SuSE RPM version.
# -- rgr, 6-May-03.]
my $grep_program = '/bin/grep';
my $date_program = '/bin/date';
my $dump_program = '/sbin/dump';
my $restore_program = '/sbin/restore';

### Subroutines.

sub do_or_die {
    # Utility function that executes the args and insists on success.  Also
    # responds to $test_p and $verbose_p values.
    my $ignore_return_code_p = $_[0] eq '-ignore-return';
    shift if $ignore_return_code_p;

    warn("$warn:  Executing '", join(' ', @_), "'\n")
	if $test_p || $verbose_p;
    if ($test_p) {
	1;
    }
    elsif (system(@_) == 0) {
	1;
    }
    elsif ($ignore_return_code_p && !($? & 255)) {
	warn("$warn:  Executing '$_[0]' failed:  Code $?\n",
	     ($verbose_p
	      # no sense duplicating this.
	      ? ()
	      : ("Command:  '", join(' ', @_), "'\n")));
	1;
    }
    else {
	die("$warn:  Executing '$_[0]' failed:  $?\n",
	    ($verbose_p
	     # no sense duplicating this.
	     ? ()
	     : ("Command:  '", join(' ', @_), "'\n")),
	    "Died");
    }
}

### Option parsing, defaulting, & validation.
my $usage = 0;
my $help = 0;
GetOptions('date=s' => \$file_date,
	   'file-name=s' => \$dump_name,
	   'name-prefix=s' => \$partition_abbrev,
	   'dump-dir=s' => \$dump_dir,
	   'cd-dir=s' => \$destination_dir,
	   'dest-dir=s' => \$destination_dir,
	   'cd!' => \$cd_p,
	   'test+' => \$test_p, 'verbose+' => \$verbose_p,
	   'volsize=i' => \$dump_volume_size,
	   'partition=s' => \$dump_partition,
	   'level=i' => \$level,
	   'usage|?' => \$usage, 'help' => \$help)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

$dump_partition ||= (-b $ARGV[0] ? shift(@ARGV) : $default_dump_partition);
pod2usage("$warn:  Missing -partition (or positional <partition>) arg.")
    unless($dump_partition);
$level ||= ($ARGV[0] =~ /^\d$/ ? shift(@ARGV) : 9);
pod2usage("$warn:  -level (or positional <level>) arg must be a single digit.")
    unless $level =~ /^\d$/;
pod2usage("$warn:  '".shift(@ARGV)."' is an extraneous positional arg.")
    if @ARGV;
# Compute some defaults.
if ($cd_p) {
    # the CD-R and -RW disks are supposed to be 700MB, but leave a little room.
    # [actually, dump appears to leave about 0.1% by itself.  and 712000kB is
    # actually a bit over 695MB, which should be plenty.  -- rgr, 1-Jan-02.]
    $dump_volume_size ||= 712000;
    $dump_dir ||= '/scratch/backups/cd';
}
else {
    # Assume the Zip100 drive.  The "-B 94000" forces it to nearly fill the
    # [Zip100] disk.  -- rgr, 20-Jan-00.
    $dump_volume_size ||= 94000;
    $dump_dir ||= '/mnt/zip';
}
pod2usage("$warn:  --dest-dir value must be an exisiting writable directory.")
    if ($destination_dir
	&& ! (-d $destination_dir && -w $destination_dir));
if ($destination_dir && (! $dump_dir || $dump_dir eq $destination_dir)) {
    # only one directory specified, or the same directory specified twice.  skip
    # the rename step.
    $dump_dir = $destination_dir;
    $destination_dir = '';
}
$dump_dir ||= '.';
pod2usage("$warn:  --dump-dir value must be an exisiting writable directory.")
    unless -d $dump_dir && -w $dump_dir;
# [should make sure that $destination_dir and $dump_dir are on the same
# partition if both are specified.  -- rgr, 17-Nov-02.]

# Make sure the partition is mounted.  [hmm, strictly mounting shouldn't be
# necessary.  but at least this verifies that it's really a partition.  -- rgr,
# 21-Oct-02.]
my ($part, $mount_point)
    = split(' ', `$grep_program "^$dump_partition " /etc/mtab`);
pod2usage("$warn:  '$dump_partition' is not a mounted partition.")
    unless -d $mount_point;
# Compute the dump file name.
if (! $dump_name) {
    # Must make our own dump name.  To do that, we must find a partition
    # abbreviation (if it hasn't been given), and the dump date (if that hasn't
    # been given).  Normally, everything is defaulted, and we have to do it all.
    if (! $partition_abbrev) {
	$partition_abbrev = $mount_point;
	$partition_abbrev =~ s@.*/@@;
	$partition_abbrev = 'sys' unless $partition_abbrev;
	# print "$mount_point -> $partition_abbrev\n";
    }
    # Create the backup file name.
    chomp($file_date = `$date_program '+%Y%m%d'`)
	unless $file_date;
    $dump_name = "$partition_abbrev-$file_date-l$level.dump";
}
my $dump_file = "$dump_dir/$dump_name";
my $cd_dump_file = "$destination_dir/$dump_name";

### Make the backup.
die "$warn:  '$dump_file' already exists; remove it if you want to overwrite.\n"
    if -e $dump_file;
die("$warn:  '$cd_dump_file' already exists; ",
    "remove it if you want to overwrite.\n")
    if $destination_dir && -e $cd_dump_file;
print "Backing up $dump_partition \($mount_point\) to $dump_file\n";
umask(066);
do_or_die($dump_program, "-u$level",
	  ($dump_volume_size ? ('-B', $dump_volume_size) : ()),
	  '-f', $dump_file, $dump_partition);
print "Done creating $dump_file; verifying . . .\n";
do_or_die('-ignore-return', $restore_program, '-C', '-y', '-f', $dump_file);

### Cleanup.
if ($destination_dir) {
    rename($dump_file, $cd_dump_file)
	|| die("$warn:  rename('$dump_file', '$cd_dump_file') failed:  $?")
	    unless $test_p;
    warn "$warn:  Renamed '$dump_file' to '$cd_dump_file'.\n"
	if $test_p || $verbose_p;
}
# Phew.
print "Done.\n";
exit(0);

__END__

=head1 NAME

backup.pl -- Interface to `dump' and `restore' for automating backups.

=head1 SYNOPSIS

    backup.pl [--[no]cd] [--file-name=<name>] [--dump-dir=<dest-dir>]
	      [--test] [--verbose] [--usage|-?] [--help] [--cd-dir=<mv-dir>]
	      [--partition=<block-special-device>] [--level=<digit>]
	      [--volsize=<max-vol-size>] [<partition>] [<level>]

=head1 DESCRIPTION

This script creates a backup dump using the `dump' program, and
verifies it with the `restore' program, both of which are published as the
Dump/Restore ext2/ext3 filesystem backup utilities by Stelian Pop
(see L<http://sourceforge.net/projects/dump/>).

The product of this procedure is a dump file on disk somewhere that has
been verified against the backed-up partition.  If not supplied, a
suitable name is chosen based on the partition mount point, current
date, and backup level.  Optionally, the file can be moved to somewhere
else in the destination file system after it has been verified; this
makes it easy to use the cd-dump.pl script to write the resulting dump
file(s) to a CD.  The whole process is readily automatable via cron
jobs.

[Writing to tape may work, but I haven't tried it, having no tape on my 
system.  -- rgr, 21-Oct-02.]

=head1 OPTIONS

=over 4

=item B<--cd>

=item B<--nocd>

Specifies whether we should expect that the dump file will eventually be
written to a CD-R or CD-RW disk.  This affects the defaults for
C<--dump-dir> and C<--volsize>.  The default is C<--cd>.

=item B<--test>

If specified, no commands will be executed.  Instead, the commands will
just be echoed to the standard error stream.

=item B<--verbose>

If specified, extra information messages are printed during the backup.
Since the output of dump and restore are included unedited, the default
output is pretty verbose even without this.

=item B<--file-name>

If specified, gives the name of the dump file excluding the directory.
The default looks something like C<home-20021021-l9.dump>, and depends
on (a) the last component of the directory where the partition is
normally mounted, e.g. 'home', (b) the current date, e.g. '20021021',
and (c) the dump level, e.g. '9'.  If some of the default values are
not acceptable, you can either specify a specific file name, or use
the C<--name-prefix> or C<--date> parameters to override how the
default name is constructed.  Say if you had C<'/usr/local'> and
C<'/seq/local'> partitions and needed to make the resulting file names
distinct, you could say C<"--name-prefix=usr-local"> for the first,
and C<"--name-prefix=seq-local"> for the second.

=item B<--date>

Overrides the date value in the default dump file name; see the
description of the C<--file-name> option.

=item B<--name-prefix>

Overrides the partition abbreviation (the last file name component of
the mount point) in the default dump file name; see the description of
the C<--file-name> option.

=item B<--dump-dir>

Specifies the directory to which to write the dump file.  For CD backups
(the default), this defaults to C</scratch/backups/cd>; for all others, it
defaults to C</mnt/zip>.

=item B<--cd-dir>

If specified, names a directory to which we should move the dump file
after it has been verified successfully.  It doesn't have anything to
do with CDs per se, it's just that the C<-cd-dir> can be used as the
communication interface to C<cd-dump.pl> when both are running as cron
jobs.  If there are files in this directory, then C<cd-dump.pl>
assumes they are good backups and need to be written to the CD; if
not, then C<cd-dump.pl> won't bother to waste the bits.

=item B<--partition>

The name of a block-special device file for the ext2 or ext3 partition
that is to be backed up, e.g. C</dev/hda12>.  There is no default;
this option must be specified.  A positional partition argument is
also supported for backward compatibility.

=item B<--level>

A digit for the backup level.  Level 0 is a full backup, level 9 is
the least inclusive incremental backup.  For more details, see
L<dump(8)>, or my "System backups" page
(L<http://rgrjr.dyndns.org/linux/backup.html>).  The level defaults to
9.  A positional level argument is also supported for backward
compatibility.

=item B<--volsize>

Specifies the size of the largest dump file that the backup medium can
hold, in 1 kilobyte blocks.  If the backup requires more than this,
then dump will pause and wait for you to "change volumes" (by renaming
the current dump file) before continuing, which will mess up the
'restore' phase of the operation.  The default depends on the C<--cd>
option.

=back

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 7-Jan-03.]

=head1 COPYRIGHT

Copyright (C) 2000-2003 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=back

=cut
