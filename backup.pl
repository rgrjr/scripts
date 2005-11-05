#!/usr/bin/perl -w
#
# backup.pl:  Create and verify a dump file.
#
# Copyright (C) 2000-2005 by Bob Rogers <rogers@rgrjr.dyndns.org>.
# This script is free software; you may redistribute it
# and/or modify it under the same terms as Perl itself.
#
# $Id$

use strict;
use Getopt::Long;
use Pod::Usage;

my $VERSION = '2.1';

my $test_p = 0;
my $verbose_p = 0;
my $file_date = '';
my $partition_abbrev = '';
my $dump_name = '';
# [$dump_dir is the scratch directory to which we write, $destination_dir is the
# final directory to which we rename.  -- rgr, 17-Nov-02.]
my $dump_dir = '';
my $cd_p = 1;
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

    warn("$0:  Executing '", join(' ', @_), "'\n")
	if $test_p || $verbose_p;
    if ($test_p) {
	1;
    }
    elsif (system(@_) == 0) {
	1;
    }
    elsif ($ignore_return_code_p && !($? & 255)) {
	warn("$0:  Executing '$_[0]' failed:  Code $?\n",
	     ($verbose_p
	      # no sense duplicating this.
	      ? ()
	      : ("Command:  '", join(' ', @_), "'\n")));
	1;
    }
    else {
	die("$0:  Executing '$_[0]' failed:  $?\n",
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

$dump_partition = shift(@ARGV)
    if ! $dump_partition && @ARGV;
pod2usage("$0:  --partition (or positional <partition>) arg must be a "
	  ."block-special device.")
    unless $dump_partition && -b $dump_partition;
# [note that we have to check for defined-ness, since 0 is a valid backup level.
# -- rgr, 20-Aug-03.]
$level = (@ARGV ? shift(@ARGV) : 9)
    unless defined($level);
pod2usage("$0:  --level (or positional <level>) arg must be a single digit.")
    unless $level =~ /^\d$/;
pod2usage("$0:  '".shift(@ARGV)."' is an extraneous positional arg.")
    if @ARGV;
# Compute some defaults.
# [this is broken; there's no way to shut off the $dump_volume_size defaulting, 
# and leave it unlimited.  -- rgr, 20-Aug-03.]
if ($cd_p) {
    # the CD-R and -RW disks are supposed to be 700MB, but leave a little room.
    # [actually, dump appears to leave about 0.1% by itself.  and 712000kB is
    # actually a bit over 695MB, which should be plenty.  -- rgr, 1-Jan-02.]
    # [use 680000 blocks for nominal 650MB disks.  -- rgr, 18-Dec-04.]
    $dump_volume_size ||= 680000;
    $dump_dir ||= '/scratch/backups/cd';
}
else {
    # Assume a Zip100 drive.  The "-B 94000" forces it to nearly fill the
    # [Zip100] disk.  -- rgr, 20-Jan-00.
    $dump_volume_size ||= 94000;
    $dump_dir ||= '/mnt/zip';
}
if ($destination_dir) {
    pod2usage("$0:  --dest-dir value must be an existing writable directory.")
	unless -d $destination_dir && -w $destination_dir;
    if (! $dump_dir || $dump_dir eq $destination_dir) {
	# only one directory specified, or the same directory specified twice.
	# skip the rename step.
	$dump_dir = $destination_dir;
	$destination_dir = '';
    }
}
$dump_dir ||= '.';
pod2usage("$0:  --dump-dir value must be an existing writable directory.")
    unless -d $dump_dir && -w $dump_dir;
# [should make sure that $destination_dir and $dump_dir are on the same
# partition if both are specified.  -- rgr, 17-Nov-02.]

# Make sure the partition is mounted.  [hmm, strictly mounting shouldn't be
# necessary.  but at least this verifies that it's really a partition.  -- rgr,
# 21-Oct-02.]
my ($part, $mount_point)
    = split(' ', `$grep_program "^$dump_partition " /etc/mtab`);
pod2usage("$0:  '$dump_partition' is not a mounted partition.")
    unless $mount_point && -d $mount_point;
# Estimate how big the dump will be.
my $estd_dump_size = `$dump_program -S -u$level $dump_partition`;
chomp($estd_dump_size);
my $n_vols = ($estd_dump_size/1024.0)/$dump_volume_size;
if ($n_vols > 1.5) {
    # Add 10% slop and then round up, to be sure we have enough dump files.
    $n_vols = int(1+1.1*$n_vols);
}
elsif ($n_vols >= 0.80) {
    # Offer two volume names, just to be safe.  There is no penalty for this; if
    # dump doesn't need the second, we'll just rename the first to the original.
    $n_vols = 2;
}
else {
    $n_vols = 1;
}
warn "[got estd_dump_size $estd_dump_size, n_vols $n_vols]\n"
    if $verbose_p;
# Compute the dump file name(s).
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
my $orig_dump_name = $dump_name;
my @dump_names = ($dump_name);
# Handle extra dump files.
if ($n_vols > 1) {
    my $stem = $dump_name;
    $stem =~ s/\.dump$//;
    my $suffix = 'a';
    @dump_names = ();
    for (1..$n_vols) {
	push(@dump_names, $stem.$suffix++.'.dump');
    }
    $dump_name = $dump_names[0];
}
# These are for testing whether the file exists.
my $dump_file = "$dump_dir/$dump_name";
my $cd_dump_file = "$destination_dir/$dump_name";

### Make the backup.
die "$0:  '$dump_file' already exists; remove it if you want to overwrite.\n"
    if -e $dump_file;
die("$0:  '$cd_dump_file' already exists; ",
    "remove it if you want to overwrite.\n")
    if $destination_dir && -e $cd_dump_file;
print("Backing up $dump_partition \($mount_point\) to $dump_file",
      (@dump_names > 1 ? ' etc.' : ''), "\n");
umask(066);
do_or_die($dump_program, "-u$level",
	  ($dump_volume_size ? ('-B', $dump_volume_size) : ()),
	  '-f', join(',', map { "$dump_dir/$_"; } @dump_names),
	  $dump_partition);
if ($dump_names[1] && ! -r $dump_dir.'/'.$dump_names[1] && ! $test_p) {
    # We offered a second dump file name, but it seems that dump didn't need it.
    # Rename it to the original name (without the suffix letter), and treat that
    # as our only dump file.
    my $orig_dump_file = "$dump_dir/$orig_dump_name";
    if (rename($dump_file, $orig_dump_file)) {
	warn "[renamed $dump_file to $orig_dump_file]\n"
	    if $verbose_p;
	$dump_name = $orig_dump_name;
	$dump_file = $orig_dump_file;
	@dump_names = ($dump_name);
    }
    else {
	warn("$0:  rename('$dump_file', '$orig_dump_file') failed:  $?");
    }
}

print "Done creating $dump_file; verifying . . .\n";
# [getting restore to deal with multivolume dump files is more of a pain; it
# doesn't understand comma-separated filenames.  -- rgr, 4-Jun-05.]
open(RESTORE, "| $restore_program -C -y -f $dump_file")
    unless $test_p;
for my $i (1..@dump_names-1) {
    my $name = $dump_names[$i];
    my $dump_file = "$dump_dir/$name";
    if ($test_p || -r $dump_file) {
	print RESTORE "$dump_file\n"
	    unless $test_p;
	print "[also verifying $dump_file]\n"
	    if $verbose_p;
    }
    else {
	# Optimization.  The trouble with this is that we can't be sure how many
	# volumes dump should have written, so we don't know if a missing file
	# is due to (e.g.) a "disk full" problem, or is really past the end of
	# the series.
	@dump_names = @dump_names[0..$i-1];
	last;
    }
}
# [can't usefully test the return code from restore.  -- rgr, 4-Jun-05.]
close(RESTORE)
    unless $test_p;

### Cleanup.
if ($destination_dir) {
    for my $name (@dump_names) {
	my $dump_file = "$dump_dir/$name";
	my $cd_dump_file = "$destination_dir/$name";
	rename($dump_file, $cd_dump_file)
	    || die("$0:  rename('$dump_file', '$cd_dump_file') failed:  $?")
	        unless $test_p;
	warn "$0:  Renamed '$dump_file' to '$cd_dump_file'.\n"
	    if $test_p || $verbose_p;
    }
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
verifies it with the `restore' program, both of which are published as
the Dump/Restore ext2/ext3 filesystem backup (see
L<http://sourceforge.net/projects/dump/>).

The product of this procedure is a dump file on disk somewhere that has
been verified against the backed-up partition.  If not supplied, a
suitable name is chosen based on the partition mount point, current
date, and backup level.  Optionally, the file can be moved to somewhere
else in the destination file system after it has been verified; this
makes it easy to use the C<cd-dump.pl> script to write the resulting dump
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
and (c) the dump level, e.g. '9'.  Suffixes of 'a', 'b', etc., will be 
added after the dump level if needed for a multivolume dump.

If some of the default values are
not acceptable, you can either specify a specific file name, or use
the C<--name-prefix> or C<--date> parameters to override how the
default name is constructed.  For example, if you had C<'/usr/local'> and
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
do with CDs per se, it's just that the C<--cd-dir> can be used as the
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
hold, in 1 kilobyte blocks.  If the backup medium fills up before
this limit is reached, 
then dump will pause and wait for you to "change volumes" (by renaming
the current dump file) before continuing, which will mess up the
'restore' phase of the operation.  The default depends on the C<--cd>
option.

If the dump requires multiple volumes, C<backup.pl> will instruct
C<dump> to write a series of files into the same directory (so the
directory must have enough space for all of them).  This is ideal for
unattended creation of multiple backup files to be copied onto
multiple physical volumes at a later time.  Just be sure to specify a
C<--volsize> that fits on the ultimate storage medium.

Note that C<dump> can do physical end-of-media (tape) and disk-full
detection on its own.  This is only useful if (a) you are writing
directly to the end medium, and (b) you are around to change media
when they fill up.

=back

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 7-Jan-03.]

=head1 KNOWN BUGS

If this script used a backup.conf file, it could get per-site defaults,
plus instructions for doing a number of backups at once,  This would
greatly simplify backup C<crontab> entries; only one would be needed.

C<backup.pl> should refuse to proceed if the size of the dumps it
produces are expected to be larger than the free space remaining on
the disk.  If you can't finish, there's no point getting started.

If you find any more, please let me know.

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=item C<cd-dump.pl> (L<http://rgrjr.dyndns.org/linux/cd-dump.pl.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2000-2005 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 VERSION

$Id$

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
