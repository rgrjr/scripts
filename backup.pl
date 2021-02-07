#!/usr/bin/perl -w
#
# backup.pl:  Create and verify a "dar" dump file.
#
# POD documentation at the bottom.
#
# Copyright (C) 2000-2017 by Bob Rogers <rogers@rgrjr.dyndns.org>.
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
use Date::Format;

# Backups are dated in 8-digit ISO date format, e.g. 20210208.
# This can't be an option because the other backup tools depend on it.
use constant DATE_FORMAT => '%Y%m%d';

my $VERSION = '2.2';

my $test_p = 0;
my $verbose_p = 0;
my $file_date = '';
my $prefix = '';
my $dump_name = '';
# [$dump_dir is the scratch directory to which we write, $destination_dir is the
# final directory to which we rename.  -- rgr, 17-Nov-02.]
my $dump_dir = '';
my $destination_dir = '';
my $dump_volume_size = '';
my ($target, $level);
# We want to use full pathnames for these programs (which are not yet covered by
# options) so that we don't have to rely on $ENV{'PATH'} being set up correctly,
# e.g. by cron.  See also the maybe_find_prog sub, below.
my $grep_program = '/bin/grep';
my $date_program = '/bin/date';
my $dar_p = 1;
my ($dump_program, $restore_program);

### Subroutines.

sub device_of {
    # Return the device of the named file/directory.
    my ($file_name) = @_;

    my ($device) = stat($file_name);
    return $device;
}

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

my (@dar_options, @dar_verify_options);
my %dar_option_p;
sub push_dar_compression_opt {
    # Add an option string to @dar_options, checking for duplicates.
    my ($option, $value) = @_;
    $value ||= 9;	# zero does not make sense.

    my ($compression_type, $compression_level);
    if ($value =~ /^(.+):(\d*)$/) {
	($compression_type, $compression_level) = $value =~ //;
    }
    elsif ($value =~ /^(\d+)$/) {
	$compression_level = $value;
    }
    else {
	$compression_type = $value;
    }
    $compression_level ||= 9;
    $compression_type
	||= $option eq 'y' || $option eq 'bzip2' ? 'bzip2' : 'gzip';
    my $option_string = "--compression=$compression_type:$compression_level";
    my $old_option = $dar_option_p{'--compression'};
    if (! $old_option) {
	push(@dar_options, $option_string);
	$dar_option_p{'--compression'} = $option_string;
    }
    elsif ($old_option eq $option_string) {
	# Duplication is OK, as long as they are consistent.
    }
    else {
	die("$0:  Conflict between '$old_option' and '$option_string'.\n");
    }
}

sub push_dar_value_opt {
    # Add an option string to @dar_options, and maybe also @dar_verify_options,
    # insisting on a value but allowing duplicates.
    my ($option, $value, $both_p) = @_;

    if (! defined($value)) {
	pod2usage("$0:  Option '--$option' requires a value; ignored.\n");
    }
    else {
	push(@dar_options, "--$option=$value");
	push(@dar_verify_options, "--$option=$value")
	    if $both_p;
    }
}

my $usage = 0;
my $help = 0;
GetOptions('date=s' => \$file_date,
	   'file-name=s' => \$dump_name,
	   'name-prefix=s' => \$prefix,
	   'dump-dir=s' => \$dump_dir,
	   'dest-dir=s' => \$destination_dir,
	   'test+' => \$test_p, 'verbose+' => \$verbose_p,
	   'volsize=i' => \$dump_volume_size,
	   'target|mount-point|partition=s' => \$target,
	   'dump-program=s' => \$dump_program,
	   'restore-program=s' => \$restore_program,
	   'dar!' => \$dar_p,
	   'compression=s' => \&push_dar_compression_opt,
	   'gzip|z:i' => \&push_dar_compression_opt,
	   'bzip2|y:i' => \&push_dar_compression_opt,
	   'alter=s' => sub { push_dar_value_opt(@_, 1); },
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

# Find $dump_program.
pod2usage("$0:  The dump/restore suite is no longer supported.\n")
    unless $dar_p;
if ($dump_program) {
    pod2usage("$0:  --dump-program '$dump_program' is not executable.\n")
	unless -x $dump_program;
}
elsif ($dump_program = maybe_find_prog('/usr/bin/dar')) {
} 
else {
    pod2usage("$0:  Can't find the 'dar' program.\n");
}

# Now figure out the options about the dump itself.
$target = shift(@ARGV)
    if ! $target && @ARGV;
if (! $target) {
    pod2usage("$0:  Missing --target or positional <target> arg.");
}
elsif (-b $target) {
    # It's actually a partition.
    my ($part, $mount)
	= split(' ', `$grep_program "^$target " /etc/mtab`);
    pod2usage("$0:  '$target' is not mounted.")
	unless $mount && -d $mount;
    $target = $mount;
}

# [note that we have to check for defined-ness, since 0 is a valid backup level.
# -- rgr, 20-Aug-03.]
$level = (@ARGV ? shift(@ARGV) : 9)
    unless defined($level);
pod2usage("$0:  --level (or positional <level>) arg must be a single digit.")
    unless $level =~ /^\d$/;
pod2usage("$0:  '".shift(@ARGV)."' is an extraneous positional arg.")
    if @ARGV;

### Default and validate $destination_dir and $dump_dir.

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
elsif (! (-d $dump_dir && -w $dump_dir)) {
    pod2usage("$0:  --dump-dir value '$dump_dir' must be "
	      ."an existing writable directory.");
}
elsif ($dump_dir eq $destination_dir) {
    pod2usage("$0:  --dest-dir must be different from --dump-dir.");
}
elsif (device_of($dump_dir) ne device_of($destination_dir)) {
    pod2usage("$0:  --dest-dir must be on the same physical "
	      . "device as --dump-dir.");
}

### Compute the dump file name.

if (! $prefix) {
    $prefix = $target;
    $prefix =~ s@.*/@@;
    $prefix = 'sys' unless $prefix;
}
if (! $dump_name) {
    # Must make our own dump name.
    $file_date = time2str(DATE_FORMAT, time())
	unless $file_date;
    $dump_name = "$prefix-$file_date-l$level";
}
my $orig_dump_name = $dump_name;

### Make the backup.

check_for_existing_dump_files("$dump_name.1.dar",
			      $dump_dir, $destination_dir);
my $dump_file = "$dump_dir/$dump_name";
print("Backing up $target to $dump_file.\n");
umask(066);
my @dump_names;
my $reference_file_stem;
if ($level > 0) {
    # For an incremental dump, we need to give dar the file stem of the most
    # recent prior dump at any level greater than the new dump level.
    # Finding and sorting existing dump files is the job of Backup::DumpSet.
    require Backup::DumpSet;

    my $sets = Backup::DumpSet->find_dumps(prefix => $prefix,
					   root => $destination_dir);
    my @dumps = ($sets->{$prefix} 
		 ? $sets->{$prefix}->current_dumps
		 : ());
    while (@dumps && $dumps[0]->level >= $level) {
	# $dumps[0] is too incremental, and therefore irrelevant.
	shift(@dumps);
    }
    die("$0:  Can't find the last dump for '$prefix', ",
	"for a level $level dump.\n")
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
	  '-R', $target);
# Now figure out how many slices (dump files) it wrote.
opendir(my $dir, $dump_dir)
    or die;
my $name_len = length($dump_name);
for my $file (readdir($dir)) {
    push(@dump_names, $file)
	if substr($file, 0, $name_len) eq $dump_name;
}

### . . . and verify it.

print "Done creating $dump_file; verifying . . .\n";
# According to the man page, dar returns 5 in the following circumstance
# (among others):
#
#     While comparing [-d], it is the case when a file in the archive does
#     not match the one in the filesystem.
#
# Since this just means that those files will still need saving in the next
# backup, that is not a problem.
do_or_die(ignore_code => 5,
	  $dump_program, '-d', $dump_file, @dar_verify_options, '-R', $target);

### Rename dump files to their final destination.

for my $name (sort(@dump_names)) {
    my $dump_file = "$dump_dir/$name";
    my $dest_dump_file = "$destination_dir/$name";
    rename($dump_file, $dest_dump_file)
	|| die("$0:  rename('$dump_file', '$dest_dump_file') failed:  $?")
	    unless $test_p;
    warn "$0:  Renamed '$dump_file' to '$dest_dump_file'.\n"
	if $test_p || $verbose_p;
}
if ($level == 0) {
    print "Creating 'dar' catalog . . .\n";
    my $dump_file = "$destination_dir/$dump_name";
    my $catalog_file = "$dump_file-cat";
    do_or_die($dump_program, '-C', $catalog_file, '-A', $dump_file);
}

# Phew.
print "Done.\n";
exit(0);

__END__

=head1 NAME

backup.pl -- Automated interface to create "dar" backups.

=head1 SYNOPSIS

    backup.pl [ --test ] [ --verbose ] [ --usage|-? ] [ --help ]
              [ --date=<string> ] [ --name-prefix=<string> ]
              [ --file-name=<name> ]
              [ --dump-program=<dump-prog> ] [ --[no]dar ]
              [ --gzip | -z ] [ --bzip2 | -y ] [  --compression[=[algo:]level] ]
              [ --dest-dir=<destination-dir> ] [ --dump-dir=<dest-dir> ]
              [ --volsize=<max-vol-size> ]
              [ --target=<dir> | <dir> ] [ --level=<digit> | <level> ]

=head1 DESCRIPTION

This script creates and verifies a backup dump using the "dar" ("disk
archiver") program.

The product of this procedure is a set of dump files on disk somewhere
that has been verified against the backed-up directory.  More than one
file may be required (C<dar> calls these "slices")
if the dump is to be written to offline media; in
that case, use the C<--volsize> option to limit the maximum file size.
Optionally, the file can be moved to somewhere else in the destination
file system after it has been verified; this makes it easy to use the
C<cd-dump.pl> script to write the resulting dump file(s) to a 
DVD or CD.  The whole process is readily automatable via C<cron> jobs.

=head2 Dump file naming

Each dump file name looks something like C<home-20051102-l0.17.dar>,
and consists of the following five components:

=over 4

=item 1.

A prefix tag (e.g. C<home>).  This is normally the last component of
the directory name, but can be specified via
the C<--name-prefix> option.  The tag is arbitrary and may consist of
multiple words, as in C<usr-local>; its purpose is solely to group all
of the backups made for a given directory.

=item 2.

The date the backup was made.  This is normally the current date in
"YYYYMMDD" format, e.g. '20021021', but can be overridden via the
C<--date> option.  (But be aware that the other backup tools,
e.g. C<vacuum.pl> and C<show-backups.pl>, expect eight-digit dates.)

=item 3.

The dump level as specified by C<--level>, a digit from 0 to 9, with a
lowercase "L" prefix, as in C<l9>.

=item 4.

A slice index.  The dar program creates these automatically by
appending a number to the file stem, starting from one.  Even if the
dump consists of only one slice, it still gets an index.

=item 5.

A file suffix (extension), which is always ".dar" for dar backups.

=back

It is important that the name prefix be unique.  For example, if you
had C<'/usr/local'> and C<'/seq/local'> directories on the same
system, you could say C<"--name-prefix=usr-local"> for the first, and
C<"--name-prefix=seq-local"> for the second.

If the C<--file-name> option is specified, then it overrides the first
three components.  There is no way to override the slice index or
file suffix.

=head2 Full versus incremental backups

In order for incremental (level > 0) dumps to work, you
must have a previous catalog or dump set in the same destination
directory.  See L<dar(1)> for details.

If you specify a full (level == 0) dump, C<backup.pl> will
automatically create a catalog of it using the base name of the dump
plus "-cat", e.g. C<home-20080521-l0-cat.1.dar> for a
C<home-20080521-l0.*.dar> full dump set.  This is so that we can
create L1 dumps of everything since the full dump without having to
keep all of the full dump around, which dar would otherwise require.

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
See L<Dump file naming>.

=item B<--date>

Overrides the date value in the default dump file name; see the
description of the C<--file-name> option.
See L<Dump file naming>.

=item B<--name-prefix>

Overrides the directory abbreviation (the last file name component of
the dumped directory) in the default dump file name.
See L<Dump file naming>.

=item B<--dump-program>

Specifies the names of the dar binary to use.  The default is
'/usr/bin/dar'.

=item B<--restore-program>

Legacy option for the dump/restore suite; currently ignored.

=item B<--nodar>

=item B<--dar>

Use the dar (Disk Archiver) program to create the dump.  Not only is
C<--dar> the default, it is the only supported option; if you specify
C<--nodar>, C<backup.pl> will fail.

=item B<--bzip2=#>

=item B<--gzip=#>

Specifies the bzip2 or gzip compression level; the default is no
compression.  The optional integer values are for the compression
level, from 1 to 9; if omitted, a value of 9 (maximum compresssion) is
used.

=item B<--alter=what>

The value of "what" can be "ctime" (the default) to specify that the
inode times are to be modified in order to preserve the "atime" at the
expense of altering the "ctime", or "atime" to specify that the inode
times are to be left alone at the cost of keeping the modified
"atime".  See L<dar(1)> for a more detailed explanation of
why this tradeoff is necessary.

=item B<--compression[=[algo:]level]>

Specifies the level of compression desired; the default is none.  The
value can specify an algorithm from the set C<gzip>, C<bzip2>, or
C<lzo>, a compression level of 1 to 9, or both separated by a colon.
If no value is supplied, then C<gzip> is the default algorithm, and 9
(the maximum) is the default level.

Note that this is a synonym for the C<-y> and C<-z> options.
Regardless of how the compression is specified, it is always passed on
to the C<dar> command using its C<--compression> option, so this will
not work with older versions of dar.

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

=item B<--level>

A digit for the backup level.  Level 0 is a full backup, level 9 is
the least inclusive incremental backup.  For more details, see
L<dar(1)>, or my "System backups" page
(L<http://www.rgrjr.com/linux/backup.html>).  The level defaults to
9.  A positional level argument is also supported for backward
compatibility, but to use it the C<--partition> argument must also be
supplied positionally.

=item B<--mount-point>

Synonym for C<--target>.

=item B<--partition>

Synonym for C<--target>.

=item B<--target>

The name of a directory that is to be
backed up, e.g. F</home>.  There is no default;
this option must be specified.  A positional directory argument is
also supported for backward compatibility.

For backward compatibility, one may name a block-special device file
for a mounted partition instead of a directory, e.g. F</dev/sda5>.
Note that it must be mounted,
since C<dar> can only operate on mounted directories.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--volsize>

Specifies the maximum dump file (slice) size.  This is useful because
C<mkisofs> imposes a limit of 2147483646 bytes (= 2^31-2) on files
burned to DVD-ROM.  A C<--volsize> of 1527253 allows three slices to
fit on a DVD with a little room left over.  See the "DVDs created with
too large files" thread at
L<http://groups.google.com/group/mailing.comp.cdwrite/browse_thread/thread/423a083cc7ad8ee8/fecd18c0f8507901%23fecd18c0f8507901>
for details.

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

If you find any more, please let me know.

=head1 SEE ALSO

=over 4

=item C<dar> home page L<http://dar.linux.free.fr/>

=item C<dar> "man" page L<dar(1)>

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=item C<cd-dump.pl> (L<http://www.rgrjr.com/linux/cd-burning.html#cd-dump.pl>)

=back

=head1 COPYRIGHT

Copyright (C) 2000-2020 by Bob Rogers C<< <rogers@rgrjr.dyndns.org> >>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<< <rogers@rgrjr.dyndns.org> >>

=cut
