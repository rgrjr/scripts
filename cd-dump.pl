#!/usr/bin/perl -w
#
#    Dump the contents of the ./to-write/ directory to a new session on a
# multisession CDROM.  All files that were successfully written (as judged by
# doing a cmp of disk and CD versions) are moved to the ./written/ directory.
# (This is usually run in the /scratch/backups/cd/ directory).
#
#    Modification history:
#
# created.  -- rgr, 20-Oct-02.
# check for too-full disk, do mount conditionally.  -- rgr, 21-Oct-02.
# oops; need to allow for restricted cron PATH.  -- rgr, 22-Oct-02.
# remove warn in ! rename_subtree(...) case.  -- rgr, 27-Oct-02.
# don't die when no disk if --test, --test implies --verbose, started doc.
#	-- rgr, 1-Mar-03.
# update for SuSE 8.1 (cdrecord in /usr/bin, /mnt => /media).  -- rgr, 4-May-03.
#

BEGIN { unshift(@INC, '/root/bin/') if -r '/root/bin'; }

use strict;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
require 'rename-into-tree.pm';

my $warn = 'cd-dump.pl';

my $cdrecord_command = '/usr/bin/cdrecord';
my $mkisofs_command = '/usr/bin/mkisofs';
my $diff_command = '/usr/bin/diff';
my $cmp_command = '/usr/bin/cmp';
my $mount_command = 'mount';
my $unmount_command = 'umount';
my $cd_mount_point = '/mnt/cdrom';
$cd_mount_point = '/media/cdrecorder'
    if ! -d $cd_mount_point && -d '/media/cdrecorder';

# the CD-R and -RW disks are supposed to be 700MB, but leave a little room.
# [backup.pl uses 695MB, so put the ceiling at 698MB.  -- rgr, 21-Oct-02.]
my $cd_max_size = 715000;

my @cdrecord_options = ();
my @mkisofs_options = ();
my $dev_spec = '';

# Option variables.
my $man = 0;
my $help = 0;
my $usage = 0;
my $verbose_p = 0;
my $test_p = 0;
my $leave_mounted_p = 0;
my $written_subdir = 'written';
my $to_write_subdir = 'to-write';

sub make_option_forwarders {
    my $arg_array = shift;

    my @result;
    for my $entry (@_) {
	push(@result, $entry, sub {
	    my ($arg_name, $arg_value) = @_;
	    my $arg = (defined($arg_value) && $arg_value ne 1
		       ? "$arg_name='$arg_value'"
		       : $arg_name);
	    push(@$arg_array, "-$arg");
	});
    }
    @result;
}

GetOptions('help' => \$help, 'man' => \$man, 'verbose+' => \$verbose_p,
	   'test' => \$test_p, 'mount!' => \$leave_mounted_p,
	   'dev=s' => \$dev_spec,
	   'to-write-subdir=s' => \$to_write_subdir,
	   'written-subdir=s' => \$written_subdir,
	   make_option_forwarders(\@mkisofs_options,
				  qw(max-iso9660-filenames relaxed-filenames
				     V=s)),
	   make_option_forwarders(\@cdrecord_options, qw(speed=s)))
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Check directories.
die "No $to_write_subdir directory; died"
    unless -d $to_write_subdir;
mkdir($written_subdir, 0700)
        or die "Can't create ./$written_subdir/ directory:  $!"
    unless -d './written';

### Subroutines.

sub ensure_mount {
    # Given a partition mount point (which must be in /etc/fstab), mount it if
    # it doesn't appear in the /etc/mtab table.
    my $mount_point = shift;

    if (! `fgrep ' $mount_point ' /etc/mtab`) {
	warn "$warn: Mounting $mount_point ...\n"
	    if $verbose_p;
	system($mount_command, $mount_point) == 0
	    || die "$warn:  '$mount_command $mount_point' failed:  $?\nDied";
    }
}

### Look for data, and how to write it.

# take inventory, and exit silently if $to_write_subdir is empty.
opendir(TW, $to_write_subdir) || die;
my @files_to_write = grep { ! /^\./; } readdir(TW);
closedir(TW);
if (@files_to_write == 0) {
    warn "$warn:  Nothing in $to_write_subdir to write.\n"
	if $verbose_p;
    exit(0);
}

# Find a usable -dev specification.
if (! $dev_spec) {
    open(IN, "$cdrecord_command -scanbus 2>&1 |") || die;
    my $line;
    my @specs;
    while (defined($line = <IN>)) {
	chomp($line);
	my ($spec, $foo, $description) = split(' ', $line, 3);
	next
	    unless $description;
	if ($spec =~ /^\d+,\d+,\d+$/
	    && $description =~ /CD-ROM/
	    && $description =~ /RW/) {
	    print "\t '$spec' => \"$description\"\n"
		if $verbose_p > 1;
	    push(@specs, $spec);
	}
    }
    close(IN);
    if (@specs ==1) {
	$dev_spec = $specs[0];
	warn "$0:  Using '--dev=$dev_spec'.\n"
	    if $verbose_p;
    }
    elsif (@specs == 0) {
	die "$0:  No CD burner available.\n";
    }
    else {
	die("$0:  Multiple CD burners available; must specify one of '",
	    join("', '", @specs), "' to --dev.\n");
    }
}

# Check what's currently on the cd.  There are three interesting cases:
#
#   1. The CD is blank, so this is the first session.  In this case
#      "cdrecord -msinfo" says 'Cannot read session offset' (though on stderr).
#   2. The CD has already had one or more sessions written to it, in which case
#      we get a valid pair of sector numbers.
#   3. Otherwise, the CD is missing, unreadable, incorrectly addressed, the
#      driver can't be found, somebody is using the drive as a cup holder, . . .
#
# If somebody simply forgot to put in a blank disk, then cdrecord says "No disk
# / Wrong disk!" (among other things).  But that falls neatly under the third
# case, so all we care is that it *doesn't* say "Cannot read session offset."
my $cd_used_estimate = 0;
my $msinfo_command = "$cdrecord_command -dev=$dev_spec -msinfo 2>&1";
chomp(my $msinfo = `$msinfo_command`);
print("Doing `$msinfo_command` produced '$msinfo'\n")
    if $verbose_p >= 2;
if ($msinfo =~ /Cannot read session offset/) {
    warn "$warn:  Writing first session on $dev_spec.\n"
	if $verbose_p;
}
elsif ($msinfo =~ /^\d+,\d+$/) {
    warn("$warn:  Writing subsequent session on $dev_spec, ",
	 "using '-C $msinfo'.\n")
	if $verbose_p;
    push(@mkisofs_options, "-C", $msinfo, "-M", $dev_spec);
    push(@cdrecord_options, '-waiti');
    my @temp = split(",", $msinfo);
    $cd_used_estimate = $temp[1]*1.8;
}
elsif ($test_p) {
    # assume a blank disk.
    warn "$warn:  Assuming first session on $dev_spec (no disk present).\n";
}
else {
    $msinfo =~ s/\n/\n   /g;
    die("$warn: Error in '$msinfo_command':\n   $msinfo\nDied");
}

# ensure that the data will fit.
my ($space_needed_estimate) = split(' ', `du -s $to_write_subdir`);
warn("$warn:  Estimate ${cd_used_estimate}K used, ",
     "${space_needed_estimate}K needed, with ${cd_max_size}K max.\n")
    if $verbose_p;
die("$warn:  Not enough disk left:  ${cd_used_estimate}K used ",
    "+ ${space_needed_estimate}K needed > ${cd_max_size}K max.\nDied")
    if $cd_used_estimate+$space_needed_estimate > $cd_max_size;

### all clear, write the disk.
unshift(@mkisofs_options, '-quiet')
    unless $verbose_p;
my $mkisofs_cmd
    = join(' ', $mkisofs_command, @mkisofs_options, $to_write_subdir);
my $cdrecord_cmd
    = join(' ', $cdrecord_command, "-dev=$dev_spec",
	   '-multi', @cdrecord_options, '-');
print("$warn:  Executing '$mkisofs_cmd\n",
      "\t\t\t| $cdrecord_cmd'\n")
    if $verbose_p || $test_p;
system("$mkisofs_cmd | $cdrecord_cmd") == 0
    || die "$warn:  '$mkisofs_cmd | $cdrecord_cmd' failed:  $?"
    unless $test_p;

# now get rid of what we've written successfully.  if the disk is mountable,
# then none of the possible error cases should die, as they are certainly not
# fatal at this point: the data is there, or it isn't.
ensure_mount($cd_mount_point);
foreach my $file (@files_to_write) {
    my $to_write_file = "$to_write_subdir/$file";
    my $cd_file = "$cd_mount_point/$file";
    my $written_file = "$written_subdir/$file";
    if ((-f $to_write_file
	 ? system($cmp_command, $to_write_file, $cd_file)
	 : system($diff_command, '--recursive', '--brief',
		  $to_write_file, $cd_file))
	!= 0) {
	# cmp/diff will have generated a message.
	warn "$warn:  Leaving '$to_write_file' in place.\n";
    }
    elsif (! rename_subtree($to_write_file, $written_file, 1)) {
	# rename_subtree issues its own warning if it fails.  -- rgr, 27-Oct-02.
	# warn "$warn:  Can't rename '$to_write_file':  $?";
    }
    elsif ($verbose_p) {
	warn("$warn:  Renamed '$to_write_file' to '$written_file'.\n");
    }
}

# and leave the disk unmounted, if requested.
system($unmount_command, $cd_mount_point) == 0
    || warn "$warn:  '$unmount_command $cd_mount_point' failed:  $?"
    unless $leave_mounted_p;
# phew . . .
exit(0);

__END__

=head1 NAME

cd-dump.pl -- Interface to `mkisofs' and `cdrecord' programs.

=head1 SYNOPSIS

    cd-dump.pl [--help] [--man] [--verbose] [--test] 
               [ --dev=x,y,z ] [--[no]mount] [--max-iso9660-filenames]
               [--relaxed-filenames] [-V=<volname>] [--speed=n]

=head1 DESCRIPTION

C<cd-dump.pl> is a utility that uses C<mkisofs> and C<cdrecord> to
burn files to CD.  It does the following:

=over 4

=item 1.

Burns files from a source directory (./to-write/ by default; see the
C<--to-write-subdir> option) as the first (or subsequent) "session" of
a multisession CD.

=item 2.

Mounts the CD and compares the data to the originals.

=item 3.

Moves each file/directory that was successfully written to a
destination directory (./written/ by default; see the
C<--written-subdir> option).  If the same subdirectory exists in both
the source and destination, then its files are moved recursively; this
maintains the ./written/ directory as a copy of the CD contents.

=back

C<cd-dump.pl> also accepts a subset of C<mkisofs> and C<cdrecord>
options, which it passes along.

=head1 OPTIONS

=over 4

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--verbose>

Turns on verbose message output.  Repeating this option results in
greater verbosity.

=item B<--test>

Specifies testing mode, in which C<cd-dump.pl> goes through all the
motions, but doesn't actually write anything on the CD, or touch the
hard disk file system.  This implies some verbosity.

=item B<--mount>

=item B<--nomount>

If C<--mount> is specified, leaves the newly written disk mounted.
The default is C<--nomount>.

=item B<--max-iso9660-filenames>

Passed directly to C<mkisofs>.

=item B<--relaxed-filenames>

Passed directly to C<mkisofs>.

=item B<--V>

Passed directly to C<mkisofs>.

=item B<--dev>

Specifies the SCSI device, needed by C<cdrecord> to address the CD
drive.  If not specified, C<cd-dump.pl> looks through all SCSI devices
listed by C<cdrecord -scanbus>; if it finds exactly one that appears
to be a CD burner, it uses that device.  See the description of the
C<scanbus> option on the C<cdrecord> "man" page for details.

=item B<--speed>

Write speed, as a multiple of the "standard" read speed for an audio
disk.  Passed directly to C<cdrecord>, which defines the default.

=item B<--to-write-subdir>

Defines the directory of files and subdirectories that need to be
written.  If not specified, "./to_write/" is used.

=item B<--written-subdir>

Defines the place where files that have successfully been written
should be moved (via rename).  This should be on the same partition as
the C<--to-write-subdir>, so that files can be efficiently renamed.
If not specified, "./written/" is used.

=back

=head1 NOTES

C<cd-dump.pl> assumes that C<cdrecord> and C<mkisofs> binaries are in
the C</usr/bin/> directory.

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 7-Jan-03.]

=head1 KNOWN BUGS

The subset of C<mkisofs> and C<cdrecord> options accepted is small and
arbitrary.

C<cd-dump.pl> should probably emit a warning at least if it finds
itself renaming files across partitions.

If you find any more, please let me know.

=head1 SEE ALSO

=over 4

=item The C<dump.pl> script (L<http://rgrjr.dyndns.org/linux/dump.pl.html>).

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2002-2003 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 VERSION

$Id$

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
