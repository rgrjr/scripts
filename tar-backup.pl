#!/usr/bin/perl
#
#    Use GNU tar to create dump-like backups.
#
#    Modification history:
#
# created (from home version).  -- rgr, 1-Nov-02.
#

use strict;
use Getopt::Long;
use Pod::Usage;

my $warn = $0;
$warn =~ s@.*/@@;
my $VERSION = '0.2';

my $test_p = 0;
my $verbose_p = 0;
my $file_date = '';		# date used in constructing $dump_name
my $directory_abbrev = '';	# prefix used in constructing $dump_name
my $dump_name = '';		# name of the backup.
my $dump_dir = '';		# where to write the backup file.
my $outgoing_dir = '';		# where to move them when verified.
my $dump_directory_name = '';	# absolute name of directory to dump
				# (any leading / will be dropped later).
my $level = 9;			# backup level.
my $dump_label = '';		# string to pass as --label to tar.
my @other_tar_options;		# passed through to GNU tar.
# We want to use full pathnames for these programs (which are not yet covered by
# options) so that we don't have to rely on $ENV{'PATH'} being set up correctly,
# e.g. by cron.
my $grep_program = '/bin/grep';
my $date_program = '/bin/date';
my $tar_program = '/bin/tar';

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

sub rename_or_die {
    my ($from, $to) = @_;

    rename($from, $to)
	|| die("$warn:  rename('$from', '$to') failed:  $?")
	unless $test_p;
    warn "$warn:  Renamed '$from' to '$to'.\n"
	if $test_p || $verbose_p;
}

### Option parsing, defaulting, & validation.

sub pass_through_to_tar {
    my ($option, $value) = @_;

    warn "$0:  adding tar options --$option='$value'.\n";
    push(@other_tar_options, "--$option", $value);
}

my $usage = 0;
my $help = 0;
GetOptions('date=s' => \$file_date,
	   'file-name=s' => \$dump_name,
	   'name-prefix=s' => \$directory_abbrev,
	   'dump-dir=s' => \$dump_dir,
	   'out-dir=s' => \$outgoing_dir,
	   'test+' => \$test_p, 'verbose+' => \$verbose_p,
	   # 'volsize=i' => \$dump_volume_size,
	   'directory=s' => \$dump_directory_name,
	   'dump-label=s' => \$dump_label,
	   'level=i' => \$level,
	   'exclude=s' => \&pass_through_to_tar,
	   'exclude-file=s' => \&pass_through_to_tar,
	   'usage|?' => \$usage, 'help' => \$help)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

pod2usage("$warn:  Missing --directory arg.\n")
    unless $dump_directory_name;
pod2usage("$warn:  --level arg must be a single digit.\n")
    unless $level =~ /^\d$/;
pod2usage("$warn:  '".shift(@ARGV)."' is an extraneous positional arg.\n")
    if @ARGV;
if (! $test_p) {
    # semantic checks that we disable for testing so that we can test from
    # unprivileged accounts.
    pod2usage("$warn:  --directory '$dump_directory_name' "
	      . "is not the absolute name\n\t of an existing directory.\n")
	unless -d $dump_directory_name && $dump_directory_name =~ m@^/@;
    pod2usage("$warn:  --dump-dir value '".$dump_dir."' is not "
	      . "the absolute name\n\t of an existing writable directory.\n")
	unless -d $dump_dir && -w $dump_dir && $dump_dir =~ m@^/@;
    if ($outgoing_dir) {
	pod2usage("$warn:  --outgoing-dir value '$outgoing_dir' is not the "
		  . "absolute name\n\t of an existing writable directory.\n")
	    unless (-d $outgoing_dir && -w $outgoing_dir
		    && $outgoing_dir =~ m@^/@);
    }
}
# Find a directory abbreviation.
if (! $directory_abbrev) {
    $directory_abbrev = $dump_directory_name;
    $directory_abbrev =~ s@.*/@@;
    $directory_abbrev = 'sys' unless $directory_abbrev;
}
# Compute the dump file name.
if (! $dump_name) {
    # Must make our own dump name using the directory abbreviation and the dump
    # date.  Normally, everything is defaulted, and we have to do it all.
    chomp($file_date = `$date_program '+%Y%m%d'`)
	unless $file_date;
    $dump_name = "$directory_abbrev-$file_date-l$level.gtar";
}
my $dump_tar_file = "$dump_dir/$dump_name";
my $dump_list_file = "$dump_dir/$directory_abbrev-l$level.gtarl";
my $outgoing_dump_tar_file = "$outgoing_dir/$dump_name"
    if $outgoing_dir;
# more validation.
die "$warn:  '$dump_tar_file' exists; remove it if you want to overwrite.\n"
    if -e $dump_tar_file;
die("$warn:  '$outgoing_dump_tar_file' already exists; ",
    "remove it if you want to overwrite.\n")
    if $outgoing_dir && -e $outgoing_dump_tar_file;
if (! $dump_label) {
    chomp(my $hostname = `hostname`);
    $dump_label = "$hostname $dump_directory_name level $level backup";
}

### Make the backup.
chdir('/');
umask(066);
print("Backing up $dump_directory_name to $dump_tar_file, ",
      "label '$dump_label'\n");
rename_or_die($dump_list_file, "$dump_list_file.old")
    if -e $dump_list_file;
if ($level) {
    # for all but full dumps, we need to initialize the listing file with a copy
    # of the listing for the most recent backup with a level that is strictly
    # less than ours.  if no such file exists, then leaving it missing produces
    # a full dump, which is consistent with what dump would do in that case.
    my $most_recent = '';
    my $file;

    # let ls do time sorting for us.  then we just have to pick the first match
    # with a smaller dump level.
    open(LS, "ls -t $dump_dir/*.gtarl |") or die;
    while (defined($file = <LS>)) {
	chomp($file);
	if ($file =~ m@/$directory_abbrev-l(\d)\.gtarl$@
	      && $1 < $level) {
	    $most_recent = $file;
	    last;
	}
    }
    close(LS);
    if ($most_recent) {
	do_or_die('cp', $most_recent, $dump_list_file);
    }
    else {
	warn "$warn:  No complete dump for level $level backup???\n";
    }
}
do_or_die($tar_program, '--create', '--one-file-system',
	  '--label', $dump_label, @other_tar_options,
	  '--listed-incremental', $dump_list_file,
	  '--file', $dump_tar_file,
	  substr($dump_directory_name, 1));
print "Done creating $dump_tar_file; verifying . . .\n";
do_or_die('-ignore-return',
	  $tar_program, '--compare', '--file', $dump_tar_file);

### Cleanup.
rename_or_die($dump_tar_file, $outgoing_dump_tar_file)
    if $outgoing_dir;
# Phew.
print "Done.\n";
exit(0);

__END__

=head1 NAME

tar-backup.pl - Interface to `tar' for automating backups.

=head1 SYNOPSIS

    tar-backup.pl [--file-name=<name>] [--dump-dir=<dest-dir>]
	      [--test] [--verbose] [--usage|-?] [--help]
	      [--directory=<block-special-device>] [--level=<digit>]
	      [--volsize=<max-vol-size>] [--outgoing-dir=<mv-dir>]

=head1 DESCRIPTION

This script creates and verifies a backup dump using the GNU `tar' program.

The product of this procedure is a dump file on disk somewhere that has
been verified against the backed-up directory.  If not supplied, a
suitable name is chosen based on the directory mount point, current
date, and backup level.  Optionally, the file can be moved to somewhere
else in the destination file system after it has been verified; this
makes it easy to use the cd-dump.pl script to write the resulting dump
file(s) to a CD.  The whole process is readily automatable via cron
jobs.

[Writing to tape may work, but I haven't tried it, having no tape on my 
system.  -- rgr, 21-Oct-02.]

=head1 OPTIONS

=over 4

=item --test

If specified, no commands will be executed.  Instead, the commands will
just be echoed to STDERR.

=item --verbose

If specified, extra information messages are printed during the backup.
Since the output of dump and restore are included unedited, the default
output is pretty verbose even without this.

=item --file-name=<name>

If specified, give the name of the dump file excluding the directory.
The default looks something like home-20021021-l9.dump, and depends on
(a) the last component of the directory where the directory is normally
mounted, e.g. 'home', (b) the current date, e.g. '20021021', and (c) the
dump level, e.g. '9'.  If some of the default values are not acceptable,
you can either specify a specific file name, or use the -name-prefix or
-date parameters to override how the default name is constructed.  Say
if you had '/usr/local' and '/seq/local' directorys and needed to make
the resulting file names distinct, you could say "-name-prefix
usr-local" for one, and "-name-prefix seq-local" for the other.

=item --date=<string>

Overrides the date value in the default dump file name; see the
description of the -file-name option.

=item --name-prefix=<string>

Overrides the directory abbreviation (the last file name component of
the mount point) in the default dump file name; see the description of
the -file-name option.

=item --dump-dir=<dest-dir>

Specifies the directory to which to write the dump file.  For CD backups
(the default), this defaults to /scratch/backups; for all others, it
defaults to /mnt/zip.

=item --cd-dir=<mv-dir>

If specified, names a directory to which we should move the dump file
after it has been verified successfully.
It doesn't have anything to do with CDs per se, it's just that the
-cd-dir can be used as the communication interface to cd-dump.pl when
both are running as cron jobs.  If the file is present, then it's a good
backup and needs to be written to the CD; if not, then 

=item --directory=<block-special-device>

The name of a block-special device file for the ext2 or ext3 directory
that is to be backed up.  There is no default; this option must be
specified.

=item --level=<digit>

A digit for the backup level.  Level 0 is a full backup, level 9 is the
least inclusive incremental backup.  For more details, see the dump man
page, or my "System backups" page
(http://rgrjr.dyndns.org/linux/backup.html).  The level defaults to 9.

=item --volsize=<max-vol-size>

Specifies the size of the largest dump file that the backup medium can
hold, in 1Kbyte blocks.  If the backup requires more than this, then
dump will pause and wait for you to "change volumes" (by renaming the
current dump file) before continuing, which will mess up the 'restore'
phase of the operation.  The default depends on the --[no]cd option
(q.v.).

=back

=head1 USAGE AND EXAMPLES

=head1 COPYRIGHT

Copyright (C) 2000-2002 by Bob Rogers <rogers@rgrjr.dyndns.org>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers <rogers@rgrjr.dyndns.org>

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (http://sourceforge.net/projects/dump/)

=item man dump(8)

=item man restore(8)

=item System backups (http://rgrjr.dyndns.org/linux/backup.html)

=back

=cut
