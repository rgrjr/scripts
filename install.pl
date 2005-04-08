#!/usr/bin/perl -w
#
# Installation script that copies only if the file has been changed since the
# last install (so that the file dates in the bin directory mean something).
# Also can do "diff -u" instead of installing.
#
# [created, based on ../scripts/install.pl version.  -- rgr, 9-Dec-03.]
#
# $Id$

use strict;

use Getopt::Long;

my $mode = 0444;		# default permissions.
my $force_p = 0;		# overrides contents checking.
my $install_p = 1;		# whether to actually do it, or just show.
my $create_directories_p = 0;
my $show_p = 0;
my $verbose_p = 0;
my $make_numbered_backup_p = 1;
my @old_file_versions;
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
	   'quiet!' => sub {
	       $show_p = $verbose_p = $_[1];
	   },
	   'create-dir!' => \$create_directories_p,
	   'noinstall|n' => sub { 
	       $install_p = 0;
	       $show_p = '-noinstall';
	   },
	   'diff' => sub { 
	       $install_p = 0;
	       $show_p = '-diff';
	   },
	   'backup!' => \$make_numbered_backup_p,
	   'force!' => \$force_p,
	   'old=s' => \@old_file_versions)
    or die;

my $destination = pop(@ARGV) || die "$0:  No destination directory.\nDied";
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
my $rename_into_place_p = -w $directory;

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
    my ($program, $installed_program_name, $program_pretty_name, $reason) = @_;
    my ($result, $target_name);

    if ($show_p eq '-diff') {
	return system('diff', '-u', $program, $installed_program_name);
    }
    warn("$0:  Installing $program_pretty_name in ", 
	 "$installed_program_name (", ($reason || 'changed'), ")\n")
	if $show_p || $verbose_p;
    warn("$0:  Destination directory '$directory' is not writable.\n")
	if ! $rename_into_place_p && $verbose_p;
    return 0
	if ! $install_p;
    $target_name = ($rename_into_place_p
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
    $result = system('cp', $program, $target_name) >> 8;
    $result = ! chmod($mode, $target_name)
	if ! $result;
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

sub file_contents {
    my $file_name = shift;

    open(SRC, $file_name) || die "$0:  Can't open '$file_name'.\n";
    my $src = join('', <SRC>);
    close(SRC);
    $src;
}

my %old_file_name_to_contents;
sub old_version_match_p {
    # return true if the passed file contents matches the one of the specified
    # files, or if there were no old files specified.
    my $src = shift;

    return 1
	if ! @old_file_versions;
    for my $version (@old_file_versions) {
	my $contents = $old_file_name_to_contents{$version};
	$contents = $old_file_name_to_contents{$version} 
	    = file_contents($version)
		unless defined($contents);
	return 1
	    if $src eq $contents;
    }
    0;
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
		    'forced');
    }
    else {
	my $src = file_contents($program);
	my $dst = file_contents($installed_program_name);
	if ($src eq $dst) {
	    warn "$0:  $program_base_name is up to date.\n"
		if $verbose_p;
	}
	elsif (! old_version_match_p($src)) {
	    warn("$0:  $program_base_name has been modified in place; ",
		 "skipping update.\n");
	}
	else {
	    x11_install($program, $installed_program_name, $program_base_name);
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
