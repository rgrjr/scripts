#!/usr/bin/perl -w
#
# backup.pl:  Create and verify a dump file.
#
# POD documentation at the bottom.
#
# Copyright (C) 2000-2011 by Bob Rogers <rogers@rgrjr.dyndns.org>.
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

my $VERSION = '2.2';

my $test_p = 0;
my $verbose_p = 0;
my $file_date = '';
my $partition_abbrev = '';
my $dump_name = '';
# [$dump_dir is the scratch directory to which we write, $destination_dir is the
# final directory to which we rename.  -- rgr, 17-Nov-02.]
my $dump_dir = '';
my $destination_dir = '';
my $dump_volume_size = '';
my ($dump_partition, $level);
# We want to use full pathnames for these programs (which are not yet covered by
# options) so that we don't have to rely on $ENV{'PATH'} being set up correctly,
# e.g. by cron.  See also the maybe_find_prog sub, below.
my $grep_program = '/bin/grep';
my $date_program = '/bin/date';
my ($dar_p, $dump_program, $restore_program);

### Subroutines.

sub do_or_die {
    # Utility function that executes the args and insists on success.  Also
    # responds to $test_p and $verbose_p values.
    my $ignore_return_code = 0;
    if ($_[0] eq 'ignore_code') {
	shift;
	$ignore_return_code = shift;
    }

    warn("$0:  Executing '", join(' ', @_), "'\n")
	if $test_p || $verbose_p;
    if ($test_p) {
	1;
    }
    elsif (system(@_) == 0) {
	1;
    }
    elsif (($ignore_return_code << 8) == $?) {
	# We assume the backup program has already printed a message.
	1;
    }
    else {
	die("$0:  Executing '$_[0]' failed:  Code $?\n",
	    ($verbose_p
	     # no sense duplicating this.
	     ? ()
	     : ("Command:  '", join(' ', @_), "'\n")),
	    "Died");
    }
}

sub check_for_existing_dump_files {
    my ($dump_name, $dump_dir, $destination_dir) = @_;

    my $dump_file = "$dump_dir/$dump_name";
    die("$0:  '$dump_file' already exists; ",
	"remove it if you want to overwrite.\n")
	if -e $dump_file;
    my $dest_dump_file = "$destination_dir/$dump_name";
    die("$0:  '$dest_dump_file' already exists; ",
	"remove it if you want to overwrite.\n")
	if -e $dest_dump_file;
}

sub maybe_find_prog {
    # Use the named program if it exists, else use "which" to look it up.
    my ($program_name, $fatal_if_not_found) = @_;

    if (-x $program_name) {
	return $program_name;
    }
    else {
	my $stem = $program_name;
	$stem =~ s@.*/@@;
	chomp(my $program = `which $stem`);
	undef($program)
	    if ! -x $program;
	pod2usage("$0:  Can't find the '$stem' program.\n")
	    if ! $program && $fatal_if_not_found;
	return $program;
    }
}

### Parse options.

my @dar_options;
my %dar_option_p;
sub push_dar_compression_opt {
    # Add an option string to @dar_options, checking for duplicates.
    my ($option, $value) = @_;
    $value ||= 9;	# zero does not make sense.

    my $option_string = "--$option=$value";
    if (! $dar_option_p{$option}) {
	push(@dar_options, $option_string);
	$dar_option_p{$option} = $option_string;
    }
    elsif ($dar_option_p{$option} eq $option_string) {
	# Duplication is OK, as long as they are consistent.
    }
    else {
	die("$0:  Conflict between '$dar_option_p{$option}' ",
	    "and '$option_string'.\n");
    }
}

sub push_dar_value_opt {
    # Add an option string to @dar_options, insisting on a value but allowing
    # duplicates.
    my ($option, $value) = @_;

    if (! defined($value)) {
	# [this should really be an error.  -- rgr, 23-May-09.]
	warn("$0:  Option '--$option' requires a value; ignored.\n");
    }
    else {
	push(@dar_options, "--$option=$value");
    }
}

my $usage = 0;
my $help = 0;
GetOptions('date=s' => \$file_date,
	   'file-name=s' => \$dump_name,
	   'name-prefix=s' => \$partition_abbrev,
	   'dump-dir=s' => \$dump_dir,
	   'dest-dir=s' => \$destination_dir,
	   'test+' => \$test_p, 'verbose+' => \$verbose_p,
	   'volsize=i' => \$dump_volume_size,
	   'partition=s' => \$dump_partition,
	   'dump-program=s' => \$dump_program,
	   'restore-program=s' => \$restore_program,
	   'dar!' => \$dar_p,
	   'gzip|z:i' => \&push_dar_compression_opt,
	   'bzip2|y:i' => \&push_dar_compression_opt,
	   'fs-root|R=s' => \&push_dar_value_opt,
	   'exclude|X=s' => \&push_dar_value_opt,
	   'include|I=s' => \&push_dar_value_opt,
	   'prune|P=s' => \&push_dar_value_opt,
	   'go-into|G=s' => \&push_dar_value_opt,
	   # [note that Getopt::Long can't handle "-[" or "-]" as options;
	   # these are synonyms for the next two.  -- rgr, 23-May-09.]
	   'include-from-file=s' => \&push_dar_value_opt,
	   'exclude-from-file=s' => \&push_dar_value_opt,
	   'level=i' => \$level,
	   'usage|?' => \$usage, 'help' => \$help)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

# Figure out which dumper we're using, and what binaries.
if (! defined($dar_p)) {
    if ($dump_program) {
	$dar_p = $dump_program =~ /dar$/;
    }
    elsif ($dump_program = maybe_find_prog('/sbin/dump')) {
	$dar_p = 0;
    }
    elsif ($dump_program = maybe_find_prog('/usr/bin/dar')) {
	$dar_p = 1;
    } 
    else {
	pod2usage("$0:  Can't find either 'dar' or 'dump'.\n");
    }
}
pod2usage("$0:  Options '".join(' ', @dar_options)."' require DAR.\n")
    if @dar_options && ! $dar_p;
# We assume that $dar_p and $dump_program are consistent if both are defined.
$dump_program = maybe_find_prog($dar_p ? '/usr/bin/dar' : '/sbin/dump', 1)
    unless $dump_program;
$restore_program = maybe_find_prog('/sbin/restore', 1)
    unless $dar_p || $restore_program;

# Now figure out the options about the dump itself.
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

### Compute some defaults.

$destination_dir ||= '.';
pod2usage("$0:  --dest-dir value must be an existing writable directory.")
    unless -d $destination_dir && -w $destination_dir;
if (! $dump_dir) {
    # $dump_dir defaults to "tmp" under $destination_dir.
    $dump_dir = $destination_dir;
    $dump_dir .= '/'
	unless $dump_dir =~ m@/$@;
    $dump_dir .= 'tmp';
    if (! -e $dump_dir) {
	mkdir($dump_dir)
	    or die("$0:  Could not create temp dir '$dump_dir':  $!");
    }
}
pod2usage("$0:  --dest-dir must be different from --dump-dir.")
    if $dump_dir eq $destination_dir;
pod2usage("$0:  --dump-dir value '$dump_dir' must be "
	  ."an existing writable directory.")
    unless -d $dump_dir && -w $dump_dir;
# [should make sure that $destination_dir and $dump_dir are on the same
# partition if both are specified.  -- rgr, 17-Nov-02.]

### Make sure the partition is mounted.

# [hmm, strictly mounting shouldn't be necessary for dump.  but at least this
# verifies that it's really a partition.  -- rgr, 21-Oct-02.]
my ($part, $mount_point)
    = split(' ', `$grep_program "^$dump_partition " /etc/mtab`);
pod2usage("$0:  '$dump_partition' is not a mounted partition.")
    unless $mount_point && -d $mount_point;

### Estimate how big the dump will be.

my $n_vols;
if ($dar_p) {
    # No way to estimate this.
    $n_vols = 1;
}
else {
    warn "running '$dump_program -S -u$level $dump_partition'\n";
    my $estd_dump_size = `$dump_program -S -u$level $dump_partition`;
    chomp($estd_dump_size);
    die "$0:  Can't find estimated dump size.\n"
	unless $estd_dump_size;
    $n_vols = ($estd_dump_size/1024.0)/$dump_volume_size;
    if ($n_vols > 1.5) {
	# Add 10% slop and then round up, to be sure we have enough dump files.
	$n_vols = int(1+1.1*$n_vols);
    }
    elsif ($n_vols >= 0.80) {
	# Offer two volume names, just to be safe.  There is no penalty for
	# this; if dump doesn't need the second, we'll just rename the first to
	# the original.
	$n_vols = 2;
    }
    else {
	$n_vols = 1;
    }
    warn "[got estd_dump_size $estd_dump_size, n_vols $n_vols]\n"
	if $verbose_p;
}

### Compute the dump file name(s).

if (! $partition_abbrev) {
    $partition_abbrev = $mount_point;
    $partition_abbrev =~ s@.*/@@;
    $partition_abbrev = 'sys' unless $partition_abbrev;
}
if (! $dump_name) {
    # Must make our own dump name.
    chomp($file_date = `$date_program '+%Y%m%d'`)
	# [bug:  should use a perl module for this.  -- rgr, 5-Mar-08.]
	unless $file_date;
    $dump_name = "$partition_abbrev-$file_date-l$level";
    # DAR just wants to see a prefix.
    $dump_name .= '.dump'
	unless $dar_p;
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

### Make the backup.

check_for_existing_dump_files(($dar_p ? "$dump_name.1.dar" : $dump_name),
			      $dump_dir, $destination_dir);
my $dump_file = "$dump_dir/$dump_name";
print("Backing up $dump_partition \($mount_point\) to $dump_file",
      (@dump_names > 1 ? ' etc.' : ''), " using $dump_program.\n");
umask(066);
if (! $dar_p) {
    # Use dump.
    do_or_die($dump_program, "-u$level",
	      ($dump_volume_size ? ('-B', $dump_volume_size) : ()),
	      '-f', join(',', map { "$dump_dir/$_"; } @dump_names),
	      $dump_partition);
    if ($dump_names[1] && ! -r $dump_dir.'/'.$dump_names[1] && ! $test_p) {
	# We offered a second dump file name, but it seems that dump didn't need
	# it.  Rename it to the original name (without the suffix letter), and
	# treat that as our only dump file.
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
}
else {
    # Use dar.  Note that dar takes the mount point rather than the partition.
    my $reference_file_stem;
    if ($level > 0) {
	# For an incremental dump, we need to give dar the file stem of the most
	# recent prior dump at any level greater than the new dump level.
	# Finding and sorting existing dump files is the job of Backup::DumpSet.
	require Backup::DumpSet;

	my $sets = Backup::DumpSet->find_dumps(prefix => $partition_abbrev,
					       root => $destination_dir);
	my @dumps = ($sets->{$partition_abbrev} 
		     ? $sets->{$partition_abbrev}->current_dumps
		     : ());
	while (@dumps && $dumps[0]->level >= $level) {
	    # $dumps[0] is too incremental, and therefore irrelevant.
	    shift(@dumps);
	}
	die("$0:  Can't find the last dump for '$partition_abbrev', ",
	    "for a DAR level $level dump.\n")
	    unless @dumps;
	$reference_file_stem = $dumps[0]->file_stem;
    }
    # If dar returns an exit code of 11, it means (from the "man" page):
    #
    #    some saved files have changed while dar was reading them, this may
    #    lead the data saved for this file not correspond to a valid state
    #    for this file.
    #
    # Which means the backup is not helpful for recovering this file, but
    # the other files are still good, and this file will surely get put on
    # the next backup.  So, since dar will have already printed a message,
    # we just ignore these.
    do_or_die(ignore_code => 11,
	      $dump_program, '-c', $dump_file, @dar_options,
	      ($dump_volume_size ? ('-s', $dump_volume_size.'K') : ()),
	      ($reference_file_stem ? ('-A', $reference_file_stem) : ()),
	      '-R', $mount_point);
    # Now figure out how many slices (dump files) it wrote.
    opendir(my $dir, $dump_dir)
	or die;
    @dump_names = ();
    my $name_len = length($dump_name);
    for my $file (readdir($dir)) {
	push(@dump_names, $file)
	    if substr($file, 0, $name_len) eq $dump_name;
    }
    @dump_names = sort @dump_names;
}

### . . . and verify it.

print "Done creating $dump_file; verifying . . .\n";
if ($dar_p) {
    # According to the man page, dar returns 5 in the following circumstance
    # (among others):
    #
    #     While comparing [-d], it is the case when a file in the archive does
    #     not match the one in the filesystem.
    #
    # Since this just means that those files will still need saving in the next
    # backup, that is not a problem.
    do_or_die(ignore_code => 5,
	      $dump_program, '-d', $dump_file, '-R', $mount_point);
}
else {
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
	    # Optimization.  The trouble with this is that we can't be sure how
	    # many volumes dump should have written, so we don't know if a
	    # missing file is due to (e.g.) a "disk full" problem, or is really
	    # past the end of the series.
	    @dump_names = @dump_names[0..$i-1];
	    last;
	}
    }
    # [can't usefully test the return code from restore.  -- rgr, 4-Jun-05.]
    close(RESTORE)
	unless $test_p;
}

### Rename dump files to their final destination.

for my $name (@dump_names) {
    my $dump_file = "$dump_dir/$name";
    my $dest_dump_file = "$destination_dir/$name";
    rename($dump_file, $dest_dump_file)
	|| die("$0:  rename('$dump_file', '$dest_dump_file') failed:  $?")
	    unless $test_p;
    warn "$0:  Renamed '$dump_file' to '$dest_dump_file'.\n"
	if $test_p || $verbose_p;
}
if ($dar_p && $level == 0) {
    print "Creating DAR catalog . . .\n";
    my $dump_file = "$destination_dir/$dump_name";
    my $catalog_file = "$dump_file-cat";
    do_or_die($dump_program, '-C', $catalog_file, '-A', $dump_file);
}

# Phew.
print "Done.\n";
exit(0);

__END__

=head1 NAME

backup.pl -- Automated interface to create `dump/restore' or `dar' backups.

=head1 SYNOPSIS

    backup.pl [--test] [--verbose] [--usage|-?] [--help]
              [--date=<string>] [--name-prefix=<string>]
              [--file-name=<name>]
	      [--dump-program=<dump-prog>] [--[no]dar]
	      [--restore-program=<restore-prog>]
	      [--gzip | -z] [--bzip2 | -y]
	      [--dest-dir=<destination-dir>] [--dump-dir=<dest-dir>]
              [--volsize=<max-vol-size>]
	      [--partition=<block-special-device> | <partition> ]
              [--level=<digit> | <level>]

=head1 DESCRIPTION

This script creates and verifies a backup dump using the `dump' and
`restore' programs, or the `dar' program, both of which are linked
below.

The product of this procedure is a set of dump files on disk somewhere
that has been verified against the backed-up partition.  More than one
file may be required if the dump is to be written to offline media; in
that case, use the C<--volsize> option to limit the maximum file size.
If not supplied, a suitable series of file names is chosen based on
the partition mount point, current date, and backup level.
Optionally, the file can be moved to somewhere else in the destination
file system after it has been verified; this makes it easy to use the
C<cd-dump.pl> script to write the resulting dump file(s) to a CD.  The
whole process is readily automatable via C<cron> jobs.

[Writing to tape probably doesn't work; I have no tape on my system,
so I don't know how to rewind it.  -- rgr, 21-Oct-02.]

Each dump file name looks something like C<home-20021021-l9.dump> or
C<home-20051102-l0a.dump>, or C<home-20051102-l0.17.dar> for DAR, and
consists of the following five components:

=over 4

=item 1.

A prefix tag (e.g. C<home>).  This is normally the last component of
the directory where the partition is mounted, but can be specified via
the C<--name-prefix> option.  The tag is arbitrary and may consist of
multiple words, as in C<usr-local>; its purpose is solely to group all
of the backups make for a given partition.

=item 2.

The date the backup was made.  This is normally the current date in
"YYYYMMDD" format, e.g. '20021021', but can be overridden via the
C<--date> option.

=item 3.

The dump level as specified by C<--level>, a digit from 0 to 9, with a
lowercase "L" prefix, as in C<l9>.

=item 4.

An optional volume suffix.  DAR creates them by appending C<.#.dar> to
the stem, where "#" is a number starting from one; all DAR backups
always have an explicit volume suffix.  If a C<dump> backup requires
two or more volumes, then alphabetic volume designators are assigned
from 'a', as in C<home-20051102-l0a.dump>, C<home-20051102-l0b.dump>,
C<home-20051102-l0c.dump>, etc.  This is only necessary for large
backups that are later copied to physical media.  [Note that
C<mkisofs> imposes a limit of 2147483646 bytes (= 2^31-2) on files
burned to DVD-ROM; see the "DVDs created with too large files" thread
at
L<http://groups.google.com/group/mailing.comp.cdwrite/browse_thread/thread/423a083cc7ad8ee8/fecd18c0f8507901%23fecd18c0f8507901>
for details.  -- rgr, 4-Nov-05.]

=item 5.

A file suffix (extension), which is ".dump" for C<dump> backups, and
(not surprisingly) ".dar" for C<DAR> backups.

=back

If the C<--file-name> option is specified, then it overrides the first
three components.  There is no way to override the volume suffix or
file suffix.

=head1 OPTIONS

=over 4

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

=item B<--dump-program>

=item B<--restore-program>

Specifies the names of the dump and restore programs to use.  The
defaults are '/sbin/dump' and '/sbin/restore', respectively, followed
by whatever it can find on C<$PATH>.

If you specify a C<--dump-program> that ends in "dar", C<backup.pl>
will assume the use of C<--dar>, and use '/usr/bin/dar' as the default
C<--dump-program>.  If C<--dar> is specified or implied, then
C<--restore-program> is ignored.

=item B<--dar>

Use the DAR (Disk Archiver) program to create the dump.  If you
specify a C<--dump-program> that ends in "dar", C<backup.pl> will
assume the use of C<--dar>.  In order for incrementals to work, you
must have a previous catalog or dump set in the same destination
directory.  See L<dar> for details.

If you specify a full (level 0) DAR dump, C<backup.pl> will
automatically create a catalog of it using the base name of the dump
plus "-cat", e.g. C<home-20080521-l0-cat.1.dar> for a
C<home-20080521-l0.*.dar> full dump set.  This is so that we can
create L1 dumps of everything since the full dump without having to
keep all of the full dump around, which DAR would otherwise require.

=item B<--bzip2=#>

=item B<--gzip=#>

Specifies the bzip2 or gzip compression level; the default is no
compression.  The optional integer values are for the compression
level, from 1 to 9; if omitted, a value of 9 (maximum compresssion) is
used.  Note that these options are only available for DAR.

=item B<--dest-dir>

If specified, names a directory to which we should move the dump file
after it has been verified successfully.  This directory must exist
and be writable by the user running C<backup.pl> The default is "."
(the current directory).

=item B<--dump-dir>

Specifies a temporary directory to which to write the dump file.  If
the backup fails, any dump in progress is left in this directory to
aid debugging, without interfering with any C<vacuum.pl> job that is
supposed to pick up completed dumps.  The C<--dump-dir> defaults to
C<tmp> underneath C<--dest-dir>, and must be on the same partition as
C<--dest-dir>; it is created if it does not exist.

=item B<--partition>

The name of a block-special device file for the ext2 or ext3 partition
that is to be backed up, e.g. C</dev/hda12>.  There is no default;
this option must be specified.  A positional partition argument is
also supported for backward compatibility.

=item B<--level>

A digit for the backup level.  Level 0 is a full backup, level 9 is
the least inclusive incremental backup.  For more details, see
L<dump(8)>, or my "System backups" page
(L<http://www.rgrjr.com/linux/backup.html>).  The level defaults to
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
Unfortunately, computing the likely size without actually doing the
dump is impossible if compression is used.

The C<--bzip2> and C<--gzip> options should be supported for
dump/restore as well.

If you find any more, please let me know.

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<restore(8)>

=item DAR home page L<http://dar.linux.free.fr/>

=item L<dar(1)>

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=item C<cd-dump.pl> (L<http://www.rgrjr.com/linux/cd-dump.pl.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2000-2011 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 VERSION

$Id$

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
