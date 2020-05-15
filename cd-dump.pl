#!/usr/bin/perl -w
#
#    Dump the contents of the ./to-write/ directory to a new session on a
# multisession CD- or DVD-ROM.  All files that were successfully written (as
# judged by doing a cmp of the two versions) are moved to the ./written/
# directory.  (This is usually run in the /scratch/backups/ directory).
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
# added to CVS, which now keeps the version history.  -- rgr, 16-Jun-03.
#

BEGIN {
    # Prefer root versions of modules, if available.
    unshift(@INC, '/root/bin/')
	if -r '/root/bin';
}

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

my $warn = 'cd-dump.pl';

my $cdrecord_command = '/usr/bin/cdrecord';
my $mkisofs_command = '/usr/bin/mkisofs';
my $diff_command = '/usr/bin/diff';
my $cmp_command = '/usr/bin/cmp';
my $mount_command = 'mount';
my $unmount_command = 'umount';
my $cd_mount_point;

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
my $dvd_p = 0;
my $leave_mounted_p = 0;
my $written_subdir = 'written';
my $to_write_subdir = 'to-write';

sub make_option_forwarders {
    my $arg_array = shift;

    my @result;
    for my $entry (@_) {
	push(@result, $entry, sub {
	    my ($arg_name, $arg_value) = @_;
	    my $arg = (defined($arg_value) && $entry =~ /=/
		       ? "-$arg_name='$arg_value'"
		       : "-$arg_name");
	    push(@$arg_array, $arg);
	});
    }
    @result;
}

GetOptions('help' => \$help, 'man' => \$man, 'verbose+' => \$verbose_p,
	   'test' => \$test_p, 'mount!' => \$leave_mounted_p,
	   'cd-mount-point=s' => \$cd_mount_point,
	   'dev=s' => \$dev_spec, 'dvd!' => \$dvd_p,
	   'to-write-subdir=s' => \$to_write_subdir,
	   'written-subdir=s' => \$written_subdir,
	   make_option_forwarders(\@mkisofs_options,
				  qw(max-iso9660-filenames relaxed-filenames
				     R! J! V=s)),
	   make_option_forwarders(\@cdrecord_options, qw(speed=s)))
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Check directories.
if ($cd_mount_point) {
    # already specified
}
elsif ($dev_spec =~ m@^/dev/(\S+)$@
       && -d "/media/$1") {
    # use the mount point that matches the device name.
    $cd_mount_point = "/media/$1";
}
else {
    # look for a likely candidate.
    for my $mp (qw(/mnt/cdrom /media/cdrecorder /media/sr0)) {
	if (-d $mp) {
	    # found it.
	    $cd_mount_point = $mp;
	    last;
	}
    }
}
die "$0:  Can't find written CD mount point; use --cd-mount-point to specify.\n"
    unless $cd_mount_point;
die "$0:  CD mount point '$cd_mount_point' does not exist.\n"
    unless -d $cd_mount_point;
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

    if ($dvd_p) {
	# [***kludge***: problems with using the default mount.  -- rgr,
	# 5-Dec-06.]
	my $warn = "$warn [dvd kludge]";
	warn "$warn: Mounting $mount_point ...\n";
	system('eject', $dev_spec) == 0
	    || die "$warn:  'eject $dev_spec' failed:  $?\nDied";
	system($mount_command, qw(-t iso9660), $dev_spec, $mount_point) == 0
	    || die "$warn:  '$mount_command $mount_point' failed:  $?\nDied";
	# [end kludge.  -- rgr, 5-Dec-06.]
    }
    elsif (! `fgrep ' $mount_point ' /etc/mtab`) {
	warn "$warn: Mounting $mount_point ...\n"
	    if $verbose_p;
	system($mount_command, $mount_point) == 0
	    || die "$warn:  '$mount_command $mount_point' failed:  $?\nDied";
    }
}

### Look for data, and how to write it.

# set up for DVD writing, if requested.
my $growisofs_p = 0;
if ($dvd_p) {
    if (! -x $cdrecord_command) {
	for my $command_name (qw(wodim growisofs cdrecord-dvd)) {
	    my $binary_name = "/usr/bin/$command_name";
	    $cdrecord_command = $binary_name, last
		if -x $binary_name;
	}
	die "$0:  Can't find a DVD burning command"
	    unless -x $cdrecord_command;
    }
    $mkisofs_command = '/usr/bin/genisoimage'
	if ! -x $mkisofs_command && -x '/usr/bin/genisoimage';
    $growisofs_p = $cdrecord_command =~ /growisofs$/;
    # [single-sided DVDs are 4.7G; call it 4.5 for safety.  -- rgr, 28-Oct-05.]
    $cd_max_size = 45000000;
    # [this may be a peculiarity of my particular DVD burner, which cdrecord
    # identifies as a MAD DOG 'MD-16XDVD9A2' rev 1.F0.  in any case, it doesn't
    # handle track-at-once, which is why we need -tsize.  -- rgr, 28-Oct-05.]
    # [but this is not needed for growisofs.  -- rgr, 2-Feb-07.]
    unshift(@cdrecord_options, '-dao')
	unless $growisofs_p;
}

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
if (! $dev_spec && $growisofs_p) {
    # [kludge.  -- rgr, 2-Feb-07.]
    $dev_spec = '/dev/sr0';
}
elsif (! $dev_spec) {
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
if (! $growisofs_p) {
    my $msinfo_command = "$cdrecord_command -dev=$dev_spec -msinfo 2>&1";
    chomp(my $msinfo = `$msinfo_command`);
    print("Doing `$msinfo_command` produced '$msinfo'\n")
	if $verbose_p >= 2;
    if ($msinfo =~ /Cannot read session offset/) {
	warn "$warn:  Writing first session on $dev_spec.\n"
	    if $verbose_p;
    }
    elsif ($msinfo =~ /\d+,\d+\z/) {
	my $msinfo_data = $&;
	warn("$warn:  Writing subsequent session on $dev_spec, ",
	     "using '-C $msinfo_data'.\n")
	    if $verbose_p;
	push(@mkisofs_options, '-C', $msinfo_data, '-M', $dev_spec);
	push(@cdrecord_options, '-waiti');
	my @temp = split(',', $msinfo_data);
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
}

# check how much data we want to write in this session.
unshift(@mkisofs_options, '-quiet')
    unless $verbose_p;
my $mkisofs_cmd = join(' ', $mkisofs_command, @mkisofs_options);
my $disk_size = `$mkisofs_cmd -print-size $to_write_subdir 2>/dev/null`;
chomp($disk_size);
die("$0:  Couldn't get disk size from ",
    "'$mkisofs_cmd -print-size $to_write_subdir'.\n")
    unless $disk_size && $disk_size =~ /^\d+$/;

# ensure that the data will fit.
my $space_needed_estimate = 2*$disk_size;
warn("$warn:  Estimate ${cd_used_estimate}K used, ",
     "${space_needed_estimate}K needed, with ${cd_max_size}K max.\n")
    if $verbose_p;
die("$warn:  Not enough disk left:  ${cd_used_estimate}K used ",
    "+ ${space_needed_estimate}K needed > ${cd_max_size}K max.\nDied")
    if $cd_used_estimate+$space_needed_estimate > $cd_max_size;

### all clear, write the disk.
my $cmd
    = ($growisofs_p
       ? join(' ', $cdrecord_command,
	      ($cd_used_estimate ? '-M' : '-Z'), $dev_spec,
	      @mkisofs_options, $to_write_subdir)
       : join(' ', $mkisofs_cmd, $to_write_subdir,
	      '|', $cdrecord_command, "-dev=$dev_spec",
	      "-tsize=${disk_size}s", '-multi', @cdrecord_options, '-'));
print("$warn:  Executing '$cmd'\n")
    if $verbose_p || $test_p;
system($cmd) == 0
    || die "$warn:  '$cmd' failed:  $?"
        unless $test_p;

# now get rid of what we've written successfully.  if the disk is mountable,
# then none of the possible error cases should die, as they are certainly not
# fatal at this point: the data is there, or it isn't.
ensure_mount($cd_mount_point);
for my $file (@files_to_write) {
    my $to_write_file = "$to_write_subdir/$file";
    my $cd_file = "$cd_mount_point/$file";
    if (! -r $cd_file) {
	# [kludge for DAR, which creates files with two dots in the name;
	# mkisofs changes the first to an underscore.  -- rgr, 27-Mar-08.]
	$cd_file =~ s{ \. ( \d+ \.dar ) $ } {_$1}x;
    }
    my $written_file = "$written_subdir/$file";
    if ((-f $to_write_file
	 ? system($cmp_command, $to_write_file, $cd_file)
	 : system($diff_command, '--recursive', '--brief',
		  $to_write_file, $cd_file))
	!= 0) {
	# cmp/diff will have generated a message.
	warn "$warn:  Leaving '$to_write_file' in place.\n";
    }
    elsif (! rename_subtree($to_write_file, $written_file, 1, $verbose_p)) {
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

    cd-dump.pl [--help] [--man] [--verbose] [--test] [--[no]dvd]
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

=item B<--dvd>

Specifies writing to a DVD burner.  This affects the size of images
that can be written, alters where C<cd-dump.pl> expects to find the
burner program, and selects the C<-dao> option.

[need much more detail, cdrecord-ProDVD link.  -- rgr, 5-Mar-06.]

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

Comparison of files written to CD versus originals will fail unless
you supply both the C<--max-iso9660-filenames> and
C<--relaxed-filenames> arguments (both passed to C<mkisofs>) on the
command line.  These arguments should be hardwired.

The subset of C<mkisofs> and C<cdrecord> options accepted is small and
arbitrary.

C<cd-dump.pl> should probably emit a warning at least if it finds
itself renaming files across partitions.

The C<--dvd> stuff is not well tested.

If you find any more, please let me know.

=head1 SEE ALSO

=over 4

=item The C<backup.pl> script (L<http://www.rgrjr.com/linux/backup.pl.html>).

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2002-2006 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
