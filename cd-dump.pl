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
use Data::Dumper;
use Pod::Usage;
require 'rename-into-tree.pm';

my $warn = 'cd-dump.pl';
my $VERSION = '0.1';

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
my %options = ();

foreach my $opt (qw(max-iso9660-filenames relaxed-filenames V=s)) {
    my ($name, $type) = ($opt, '!');
    $name = $1, $type = $2
	if $opt =~ /^(.*)([=:!+].*)$/;
    $options{"-$name"} = [\@mkisofs_options, $type];
}
foreach my $opt (qw(dev=s speed=s)) {
    my ($name, $type) = split(/=/, $opt);
    $options{"-$name"} = [\@cdrecord_options, "=$type"];
}
# print Data::Dumper->Dump([\@cdrecord_options, \@mkisofs_options, \%options],
# 			 [qw(*cdrecord_options *mkisofs_options *options)]);

# Parse arguments.  This does limited Getopt::Long emulation; we don't need the
# full set, but do need to do some special handling.
my $arg_errors = 0;
my $verbose_p = 0;
my $test_p = 0;
my $leave_mounted_p = 0;
while (@ARGV) {
    my $arg = shift(@ARGV);
    my ($arg_name, $arg_value) = split(/=/, $arg, 2);
    $arg_name =~ s/^--/-/;
    my $option_entry = $options{$arg_name};
    my ($arg_array, $type);
    if ($arg_name eq '-verbose') {
	$verbose_p++;
    }
    elsif ($arg_name eq '-help') {
	pod2usage(1);
    }
    elsif ($arg_name eq '-man') {
	pod2usage(-exitstatus => 0, -verbose => 2);
    }
    elsif ($arg_name eq '-test') {
	$test_p++;
    }
    elsif ($arg_name =~ /^-(no)?mount$/) {
	$leave_mounted_p = ! $1;
    }
    elsif (! defined($option_entry)) {
	warn "Unknown argument:  '$arg'\n";
	$arg_errors++;
    }
    elsif (($arg_array, $type) = @$option_entry,
	   defined($arg_array)) {
        $arg_value = shift(@ARGV)
	    if ! defined($arg_value)
		&& $type eq '=s';
	$dev_spec = $arg_value
	    if $arg_name eq '-dev';
	$arg = defined($arg_value) ? "$arg_name='$arg_value'" : $arg_name;
	push(@$arg_array, $arg);
    }
    else {
	warn "Unknown argument:  '$arg'\n";
	$arg_errors++;
    }
}
$verbose_p++
    if $test_p;
pod2usage("$warn:  Must specify '-dev=x,y,z' in order to write a CD.\n")
    unless $dev_spec;
pod2usage if $arg_errors;

# Check directories.
die "No ./to-write/ directory; died"
    unless -d './to-write';
mkdir("written", 0700) or die "Can't create ./written/ directory:  $!"
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
	    || die "$warn:  '$mount_command $mount_point' failed:  !?\nDied";
    }
}

### Look for data, and how to write it.

# take inventory, and exit silently if ./to-write/ is empty.
opendir(TW, 'to-write') || die;
my @files_to_write = grep { ! /^\./; } readdir(TW);
closedir(TW);
if (@files_to_write == 0) {
    warn "$warn:  Nothing in ./to-write/ to write.\n"
	if $verbose_p;
    exit(0);
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
my ($space_needed_estimate) = split(' ', `du -s to-write`);
warn("$warn:  Estimate ${cd_used_estimate}K used, ",
     "${space_needed_estimate}K needed, with ${cd_max_size}K max.\n")
    if $verbose_p;
die("$warn:  Not enough disk left:  ${cd_used_estimate}K used ",
    "+ ${space_needed_estimate}K needed > ${cd_max_size}K max.\nDied")
    if $cd_used_estimate+$space_needed_estimate > $cd_max_size;

### all clear, write the disk.
unshift(@mkisofs_options, '-quiet')
    unless $verbose_p;
my $mkisofs_cmd = join(' ', $mkisofs_command, @mkisofs_options, './to-write/');
my $cdrecord_cmd
    = join(' ', $cdrecord_command, '-multi', @cdrecord_options, '-');
print("$warn:  Executing '$mkisofs_cmd\n",
      "\t\t\t| $cdrecord_cmd'\n")
    if $verbose_p || $test_p;
system("$mkisofs_cmd | $cdrecord_cmd") == 0
    || die "$warn:  '$mkisofs_cmd | $cdrecord_cmd' failed:  !?"
    unless $test_p;

# now get rid of what we've written successfully.  if the disk is mountable,
# then none of the possible error cases should die, as they are certainly not
# fatal at this point: the data is there, or it isn't.
ensure_mount($cd_mount_point);
foreach my $file (@files_to_write) {
    if ((-f "to-write/$file"
	 ? system($cmp_command, "to-write/$file", "$cd_mount_point/$file")
	 : system($diff_command, '--recursive', '--brief',
		  "to-write/$file", "$cd_mount_point/$file"))
	!= 0) {
	# cmp/diff will have generated a message.
	warn "$warn:  Leaving to-write/$file in place.\n";
    }
    elsif (! rename_subtree("to-write/$file", "written/$file", 1)) {
	# rename_subtree issues a warning.  -- rgr, 27-Oct-02.
	# warn "$warn:  Can't rename to-write/$file:  $?";
    }
    elsif ($verbose_p) {
	warn "$warn:  Renamed 'to-write/$file' to 'written/$file'.\n";
    }
}

# and leave the disk unmounted, if requested.
system($unmount_command, $cd_mount_point) == 0
    || warn "$warn:  '$unmount_command $cd_mount_point' failed:  !?"
    unless $leave_mounted_p;
# phew . . .
exit(0);

__END__

=head1 NAME

cd-dump.pl -- Interface to `mkisofs' and `cdrecord' for automating backups.

=head1 SYNOPSIS

    cd-dump.pl [--help] [--man] [--verbose] [--test] 
               --dev=x,y,z [--[no]mount] [--max-iso9660-filenames]
               [--relaxed-filenames] [-V=<volname>] [--speed=n]

=head1 DESCRIPTION

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

Leaves the newly written disk mounted, if C<--mount> is specified.
The default is C<--nomount>.

=item B<--max-iso9660-filenames>

Passed to C<mkisofs>.

=item B<--relaxed-filenames>

Passed to C<mkisofs>.

=item B<--V>

Passed to C<mkisofs>.

=item B<--dev>

Specifies the SCSI device, needed by C<cdrecord> to address the CD drive.
There is no default; this must be specified.
Passed to C<cdrecord>.

=item B<--speed>

Write speed, as a multiple of the "standard" read speed for an audio
disk.  Passed to C<cdrecord>, which defines the default.

=back

=head1 NOTES

C<cd-dump.pl> assumes that C<cdrecord> and C<mkisofs> binaries are in
the C</usr/local/bin/> directory.

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 7-Jan-03.]

=head1 COPYRIGHT

Copyright (C) 2002-2003 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=head1 SEE ALSO

=over 4

=item The C<dump.pl> script (L<http://rgrjr.dyndns.org/linux/dump.pl.html>).

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=back

=cut
