#!/usr/bin/perl -w
#
# Installation script that copies only if the file has been changed since the
# last install (so that the file dates in the bin directory mean something).
# Also can do "diff -u" instead of installing.
#
# [created, based on ../scripts/install.pl version.  -- rgr, 9-Dec-03.]
#

use strict;

use Getopt::Long;

my $mode = 0444;		# default permissions.
my $force_p = 0;		# overrides contents checking.
my $install_p = 1;		# whether to actually do it, or just show.
my $create_directories_p = 0;
my $show_p = 0;
my $verbose_p = 0;
my $reverse_p;
my $make_numbered_backup_p = 1;
my $n_errors = 0;
my $ignore;

GetOptions('mode|m=i' => sub {
	       # Explicit mode specification.
	       $mode = oct($_[1]);
	   },
	   'c' => \$ignore,
	   'verbose' => sub {
	       $show_p = 1; $verbose_p++;
	   },
	   'show!' => \$show_p,
	   'reverse!' => \$reverse_p,
	   'create-dir|D!' => \$create_directories_p,
	   'noinstall|n' => sub { 
	       $install_p = 0;
	       $show_p = '-noinstall';
	   },
	   'diff' => sub { 
	       $install_p = 0;
	       $show_p = '-diff';
	   },
	   'backup!' => \$make_numbered_backup_p,
	   'force!' => \$force_p)
    or die;

my $destination = pop(@ARGV) || die "$0:  No destination directory.\n";
$destination =~ s:/$::;		# canonicalize without the slash.
my $directory = $destination;
if (! -d $directory) {
    # the destination is a file name; find its directory portion.
    $directory =~ s:/[^/]+$:: || die "'$directory'";
}
if (-d $directory) {
    # OK.
}
elsif ($create_directories_p) {
    mkdir($directory)
	or die "$0:  Couldn't create '$directory' as a directory:  $!";
}
else {
    die("$0:  Last arg is '$destination', which is not ",
	($directory eq $destination ? '' : 'in '),
	"a directory that exists.  [got $directory]\nDied");
}

### Subroutines.

sub x11_install {
    # Use cp to install a given file in a specified directory.  This subroutine
    # does not die (or croak, or exit), so that callers may clean up; it just
    # prints a warning and increments $n_errors so that we die later instead.
    # Based in part on the install.sh routine that comes with FSF emacs, which
    # has the following comment:
    #
    #	install - install a program, script, or datafile
    #	This comes from X11R5 (mit/util/scripts/install.sh).
    #	Copyright 1991 by the Massachusetts Institute of Technology
    #
    # $program is the pathname of the thing where it lives now,
    # $installed_program_name is its "new" name when in place, and
    # $program_pretty_name is for use in messages.
    my ($program, $installed_program_name, $program_pretty_name,
	$reason, $directory) = @_;

    if ($show_p eq '-diff') {
	return system('diff', '-u', $program, $installed_program_name);
    }
    my $src_mod = (stat($program))[9] || 0;
    my $dst_mod = (stat($installed_program_name))[9] || 0;
    my $older_p = $src_mod && $src_mod < $dst_mod;
    if ($older_p && $reason ne 'forced') {
	warn("$0:  '$installed_program_name' is older than '$program'; ",
	     "not installing.\n");
	return;
    }
    warn("$0:  Installing $program_pretty_name in $installed_program_name ",
	 "($reason)",
	 ($older_p ? " despite $program_pretty_name being older" : ''), ".\n")
	if $show_p || $verbose_p;
    my $rename_into_place_p = -w $directory;
    warn("$0:  Destination directory '$directory' is not writable.\n")
	if ! $rename_into_place_p && $verbose_p;
    return
	if ! $install_p;
    my $target_name = ($rename_into_place_p
		    ? "$directory/ins$$.tmp"
		    : $installed_program_name);
    if (! $rename_into_place_p && ! -w $installed_program_name) {
	# Must overwrite.  Make temporarily writable.  This will fail if we
	# don't own it, or aren't root.
	if (! chmod(0755, $installed_program_name)) {
	    warn "$0:  Can't chmod '$installed_program_name'.\n";
	    $n_errors++;
	    return 0;
	}
	# belt and suspenders.
	if (! -w $installed_program_name) {
	    warn("$0:  Can't write '$installed_program_name' ", 
		 "or its parent directory.\n");
	    $n_errors++;
	    return 0;
	}
    }
    # Do it.
    my $result = system('cp', $program, $target_name) >> 8;
    $result = ! chmod($mode, $target_name)
	if ! $result || $reason eq 'reverse';
    if ($rename_into_place_p && ! $result) {
	if ($make_numbered_backup_p && -e $installed_program_name) {
	    # make a numbered backup of the installed version.  that means we
	    # need to find the highest backup version number, and add one.
	    my $pattern = $installed_program_name;
	    $pattern =~ s@^.*/@@;
	    $pattern =~ s/\W/\\$&/g;
	    $pattern = '^'.$pattern.'.~(\d+)~$';	# ', for emacs.
	    my $version = 0;
	    opendir(DIR, $directory) || die;
	    while (defined(my $file = readdir(DIR))) {
		$version = $1
		    if ($file =~ /$pattern/ && $1 > $version);
	    }
	    closedir(DIR);
	    $version++;
	    my $backup = "$installed_program_name.~$version~";
	    warn("$0:  Renaming '$installed_program_name' to '$backup'.\n")
		if $show_p;
	    $result = ! rename($installed_program_name, $backup);
	    warn("$0:  Rename of '$installed_program_name' to ",
		 "'$backup' failed.\n")
		if $result;
	}
	$result = ! rename($target_name, $installed_program_name)
	    if ! $result;
    }
    if ($result) {
	# This is fatal (eventually).
	warn "$0:  Installing $program_pretty_name failed.\n";
	$n_errors++;
    }
}

sub install_program {
    # Have a real program to install; decide how & whether to do it.
    my ($program) = @_;

    my $program_base_name = $program;
    $program_base_name =~ s@^.*/@@;
    my $installed_program_name 
	= ($destination eq $directory 
	   ? "$directory/$program_base_name"
	   : $destination || die "$0:  Multiple installs to '$destination'");

    # See if installation is necessary.
    if (! -r $installed_program_name || $force_p) {
	# must install anyway.
	x11_install($program, $installed_program_name, $program_base_name,
		    'forced', $directory);
    }
    else {
	if (0 == system("cmp -s '$program' '$installed_program_name'")) {
	    warn "$0:  $program_base_name is up to date.\n"
		if $verbose_p;
	}
	elsif ($reverse_p) {
	    # Look in the local directory for versions.
	    my $dir = $program =~ m@(.*)/@ ? $1 : '.';
	    x11_install($installed_program_name, $program, $program_base_name,
			'reverse', $dir);
	}
	else {
	    x11_install($program, $installed_program_name, $program_base_name,
			'changed', $directory);
	}
    }
}

### Main loop

# Process all remaining args as files to be installed.
for my $program (@ARGV) {
    if (! -r $program || -d $program) {
	# This is actually an error (possibly a misspelled program name).
	warn "$0:  '$program' does not exist.\n";
	$n_errors++;
    }
    else {
	install_program($program);
    }
}
die "$0:  $n_errors errors encountered.\n"
    if $n_errors;

__END__

=head1 NAME

install.pl -- install files 

=head1 SYNOPSIS

    install.pl [ --[no]backup ] [ -D | --create-dir ] [ --diff ] [ --force ]
	       [ -m <mode> | -mode=<mode> ] [ -n | --noinstall ]
	       [ --show ] [ --verbose ]

=head1 DESCRIPTION

The C<install.pl> script installs program and data files into a
destination directory.  In addition to what the standard UNIX
C<install> utility does by default, C<install.pl> declines to install
a file that hasn't changed or is older thand what it is 
replacing, and makes numbered backups.  Additionally,
it can be made verbose, can be asked to diff the source and installed
versions, and can force installation.

=head1 OPTIONS

=over 4

=item C<--nobackup>

=item C<--backup>

If C<--backup> is specified and an installed file already exists, a
numbered backup is created before installing a new version.  For
example, before F</usr/local/bin/install.pl> is replaced by a new
version, it would be renamed to F</usr/local/bin/install.pl.~1~>,
using a version number higher than anything already in place.

=item C<-D>

=item C<--create-dir>

If specified, this option causes the destination directory to be
created if missing.  The default permission mask is used, so use this
with caution.

=item C<-c>

Historical option (from Berkeley UNIX C<install>?); ignored.

=item C<--diff>

If specified, instead of installing files, the source file is compared
to the destination file with "diff -u".

=item C<--force>

If specified, forces installation.  The C<install.pl> script normally
avoids installation of things that haven't changed, or that are older
than what they would be replacing; the C<--force> option causes the
identity check to be skipped, and merely reports that a newer file is
being overwritten if C<--show> is also enabled.

=item C<-m>

=item C<--mode>

Specifies the file permission mode, in octal.  The default is 444,
meaning read-only to everybody, including the owner.  The other
popular value is 666, meaning read/execute to everyone, including the
owner.

=item C<-n>

=item C<--noinstall>

If specified, the C<install.pl> script goes through the motions
without actually installing anything.  This option also implies
C<--show>.

=item C<--reverse>

If specified, programs are taken from the destination and copied back
to the source(s), under the same conditions as for installation,
i.e. not copying unless changed, making backups, showing operations
done, obeying C<--noinstall>, etc.

=item C<--show>

If specified, extra messages are produced on stderr describing what's
being done.

=item C<--verbose>

Specifies verbose output; repeat to increase verbosity.  This option
also implies C<--show>.

=back

=head1 EXAMPLES

	perl install.pl --show -m 555 install.pl vc-chrono-log.pl /usr/local/bin
	perl install.pl --mode 555 install.pl /usr/local/bin/install

=head1 BUGS

If you find any, please let me know.

=head1 AUTHOR

Bob Rogers E<lt>rogers@rgrjr.comE<gt>

=cut
