#!/usr/bin/perl -w
#
# Installation script that is smarter than the install program about (a) perl
# scripts and (b) programs/files that have not been changed since the last
# install (so that the file dates in the bin directory mean something).  See the
# documentation on the
# http://bmerc-www.bu.edu/needle-doc/latest/random-tools.html#install page.
#
#    Modification history:
#
# . . .
# first official version.  -- rgr, 28-Oct-96.
# make smarter about perl scripts.  -- rgr, 15-Feb-97.
# use perl5.003 for a change, add dir check.  -- rgr, 28-Apr-97.
# -inc, #ifdef DEBUG for perl scripts.  -- rgr, 5-Sep-97.
# system_install: new fn for OSF1 smartness.  -- rgr, 3-Nov-97.
# allow for null return from 'which'.  -- rgr, 26-Feb-98.
# nonwritable directory attempt.  -- rgr, 2-Mar-98.
# system_install: better 'cp' messages.  -- rgr, 19-Mar-98.
# attempt to make compatible with perl version 4.  -- rgr, 5-Oct-98.
# Solaris kludges.  -- rgr, 21-Oct-98.
# remove dependency on native install.  -- rgr, 30-Oct-98.
# remove broken '-f' arg to cp (not in SunOS 4.1.x).  -- rgr, 4-Nov-98.
# fix bug in date check when pathname given, improve error handling, clean up
#	modularity.  -- rgr, 17-Nov-98.
# '-mode' synonym for '-m'.  -- rgr, 21-Feb-99.
# have -inc unshift instead of push, so dest dir is first.  -- rgr, 23-Dec-99.
# don't use "which" if we can read $0 directly.  -- rgr, 13-Jan-00.
# -quiet arg.  -- rgr, 19-Jan-00.
#

my $mode = '555';	# default permissions (octal).
# [not used.  -- rgr, 11-Jul-03.]
# my $group = '';	# don't change group by default.
my $install_perl_magic_p = 0;	# whether to change '#!/usr/bin/perl -w' magic.
my $include_p = 0;		# new feature: hack include directory.
my $force_p = 0;		# overrides date checking.
my $show_p = 0;
my $verbose_p = 0;
my $perl_prefix_string = '';
my $perl_prefix_n_lines = 0;

my $destination = pop(@ARGV) || die "$0:  No destination directory.\nDied";
$destination =~ s:/$::;		# canonicalize without the slash.
my $directory = $destination;
if (! -d $directory) {
    # the destination is a file name; find its directory portion.
    $directory =~ s:/[^/]+$:: || die "'$directory'";
}
die("$0:  Last arg is '$destination', which is not ",
    ($directory eq $destination ? '' : 'in '),
    "a directory.  [got $directory]\nDied")
    unless -d $directory;
warn("$0:  Destination directory '$directory' is not writable.\n")
    unless -w $directory;

my $which_install;
if (-r $0) {
    # which on linux doesn't find "./install.pl", but in this case, we don't
    # even need to do which.  -- rgr, 13-Jan-00.
    $which_install = $0;
}
else {
    chomp($which_install = `which $0`);
}
# If we can't find ourself, don't bother complaining until we have actual perl
# scripts to install.
if ($which_install && -r $which_install) {
    # warn "$0:  found myself in '$which_install'\n";
    open(SELF, $which_install)
	|| die "$0:  Can't open '$which_install'; died";
    while (defined($line = <SELF>) && $line !~ /^[ \#\t]*$/) {
	$perl_prefix_string .= $line;
	$perl_prefix_n_lines++;
    }
    $perl_prefix_string .= "#\n";
    close(SELF);
}

### Subroutines.

sub mtime {
    # Return the modification time of the file given as an argument.  This not
    # only hides the magic number, but it gets around the fact that perl doesn't
    # like subscripting of function return values.  -- rgr, 22-Oct-96.
    # [this seems to have been changed in perl5.  -- rgr, 15-Jul-03.]
    my $file = shift;
    my @stat = stat($file);

    warn "$0:  modification time of $file is $stat[9].\n"
	if $verbose_p > 1;
    $stat[9];
}

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
    my ($program, $installed_program_name, $program_pretty_name) = @_;
    my ($result, $rename_p, $target_name);

    warn "$0:  Installing $program_pretty_name in $installed_program_name\n"
	if $show_p;
    # Decide how we're going to get it there.
    $rename_p = -w $directory;
    $target_name = ($rename_p
		    ? "$directory/ins$$.tmp"
		    : $installed_program_name);
    if (! $rename_p && ! -w $installed_program_name) {
	# Must overwrite.  Make temporarily writable.  This will fail if we
	# don't own it, or aren't root.
	chmod(0755, $installed_program_name);
	unless (-w $installed_program_name) {
	    warn "$0:  Can't write '$installed_program_name'.\n";
	    $n_errors++;
	    return 0;
	}
    }
    # Do it.
    $result = system('cp', $program, $target_name) >> 8;
    $result = ! chmod(oct($mode), $target_name)
	if ! $result;
    $result = ! rename($target_name, $installed_program_name)
	if $rename_p && ! $result;
    if ($result) {
	# This is fatal (eventually).
	warn "$0:  Installing $program_pretty_name failed.\n";
	$n_errors++;
    }
}

sub install_perl_script {
    # Install perl script.  Note that we do not want to do this for .pm (perl
    # "module", or library) files.  [though perhaps we should give those the
    # #ifdef stuff for consistency.  -- rgr, 17-Nov-98.]
    my ($program, $installed_program_name) = @_;
    my ($line, $copy_p, $temp_file);

    open(PGM, $program)
	|| die "$0:  Can't read $program; died";
    # Skip preamble in program file.
    while (defined($line = <PGM>) && $line !~ /^[ \#\t]*$/) {};
    # Make a temp file.  [This used to use the same name as $program, in order
    # to tell the native install to use the right name, but now we do this
    # directly, so pick something distinctive.  -- rgr, 17-Nov-98.]
    $temp_file = "/tmp/ntINS$$";
    # Copy doctored script into $temp_file
    open(TMP, ">$temp_file")
	|| die "$0:  Can't write $temp_file; died";
    print TMP $perl_prefix_string;
    # Copy remaining lines (that aren't within "#ifdef DEBUG/#endif" lines).
    $copy_p = 1;
    while ($line = <PGM>) {
	if ($line =~ /^[ \t]*#ifdef[ \t]+DEBUG/) {
	    $copy_p = 0;
	}
	elsif ($line =~ /^[ \t]*#endif/) {
	    $copy_p = 1;
	}
	elsif ($copy_p) {
	    print TMP $line;
	}
    }
    close(TMP); close(PGM);
    # Install and delete $temp_file
    x11_install($temp_file, $installed_program_name,
		"perl script $program");
    unlink($temp_file);
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
    my ($source_mtime, $dest_mtime, $target_name);

    # See if installation is necessary.
    unless ($force_p) {
	$source_mtime = mtime($program);
	$dest_mtime = mtime($installed_program_name);
	if ($dest_mtime && $source_mtime <= $dest_mtime) {
	    warn "$0:  $program is up to date in $directory\n"
		if $verbose_p;
	    return 0;
	}
    }
    # It is; figure out how, and go do it.
    if (! $install_perl_magic_p || $program !~ /\.pr?l$/) {
	# normal program or data file.
	x11_install($program, $installed_program_name, $program_base_name);
    }
    elsif ($perl_prefix_n_lines) {
	install_perl_script($program, $installed_program_name);
    }
    else {
	# perl, but must install as a normal program or data file.
	warn "$0:  Can't fix perl magic line; installing $program as-is.\n";
	x11_install($program, $installed_program_name, $program_base_name);
    }
}

### Main loop

# Parse args, installing files in the process.
while (@ARGV) {
    $program = shift(@ARGV);
    if ($program eq '-m' || $program eq '-mode') {
	# Explicit mode specification.
	$mode = shift(@ARGV);
    }
    elsif ($program eq '-c') {
	# ignore, for BSD install compatibility.
    }
    elsif ($program eq '-verbose') {
	$show_p = $program;
	$verbose_p++;
    }
    elsif ($program eq '-show') {
	$show_p = $program;
	$verbose_p = 0;
    }
    elsif ($program eq '-quiet') {
	$show_p = $verbose_p = 0;
    }
    elsif ($program eq '-force') {
	$force_p = $program;
    }
    elsif ($program eq '-magic') {
	$install_perl_magic_p = $program;
    }
    elsif ($program eq '-inc') {
	# When installing perl scripts, have it put the binary directory at the
	# start of the @INC (include) path as the first thing it does.
	$perl_prefix_string .= "unshift(\@INC, '$directory');\n#\n"
	    unless $include_p;
	$include_p = $program;
	# this also implies '-magic'.
	$install_perl_magic_p = $program;
    }
    elsif ($program =~ /^-./) {
	warn "$0:  Unknown option '$program; ignoring.\n";
    }
    elsif (! -r $program || -d $program) {
	# This is actually an error (possibly a misspelled program name).
	warn "$0:  '$program' does not exist.\n";
	$n_errors++;
    }
    else {
	install_program($program);
    }
}

die "$0:  $n_errors errors encountered; died" 
    if $n_errors;
