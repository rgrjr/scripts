#!/usr/local/bin/perl
#
# bug: somehow, @cp_program_args isn't being obeyed . . .  -- rgr, 1-Nov-00.
#
#    Modification history:
#
# created.  -- rgr, 1-Sep-00.
# nearly finished, but obsolete; use "cp -uR" instead.  -- rgr, 2-Sep-00.
# not obsolete; .AppleDouble directories are special.  -- rgr, 1-Nov-00.
#

$warn = 'cp-if-newer.pl';

$small_recursive_p = $big_recursive_p = $verbose_p = 0;
$daylight_savings_kludge = 0;
$cp_program = 'cp';
$verbose_p = 0;

while ($ARGV[0] =~ /^-/) {
    $arg = shift(@ARGV);
    if (substr($arg, 0, 2) eq '--') {
	do_arg($arg);
    }
    else {
	map { do_arg("-$_"); } split(//, substr($arg, 1));
    }
}

@cp_program_args = ();		# options to pass to cp
sub do_arg {
    my $arg = shift;

    if ($arg eq '-r') {
	$small_recursive_p = $arg;
    }
    elsif ($arg eq '-R' || $arg eq '--recursive') {
	$big_recursive_p = $arg;
    }
    elsif ($arg eq '-P' || $arg eq '--parents') {
	die "$warn:  $arg is not supported.\n";
    }
    elsif ($arg eq '--verbose') {
	$verbose_p++;
    }
    elsif ($arg eq '--dst-kludge') {
	$daylight_savings_kludge = $arg;
    }
    else {
	push(@cp_program_args, $arg);
	warn("$warn:  Pushed '$arg', \@cp_program_args is now ",
	     join(' ', @cp_program_args), ".\n")
	    if $verbose_p > 1;
    }
}

# [stolen from install.pl (part of needle tools).  -- rgr, 1-Sep-00.]
sub mtime {
    # Return the modification time of the file given as an argument.  This not
    # only hides the magic number, but it gets around the fact that perl doesn't
    # like subscripting of function return values.  -- rgr, 22-Oct-96.
    my $file = shift;
    my @stat = stat($file);

    warn "$warn:  modification time of $file is $stat[9].\n"
	if $verbose_p > 1;
    $stat[9];
}

$n_copy_errors = 0;
sub standard_cp {
    # Do the standard copy from one file to another.
    my ($from, $to, $set_to_date) = @_;
    my $result = 0;

    print("system('", join("', '", $cp_program, @cp_program_args, $from, $to),
	  "');\n")
	if $verbose_p > 1;
    $result = system($cp_program, @cp_program_args, $from, $to);
    if ($result) {
	$n_copy_errors++;
    }
    elsif (defined($set_to_date)) {
	print("  utime($set_to_date, $set_to_date, '$to');\n")
	    if $verbose_p > 1;
	utime($set_to_date, $set_to_date, $to);
    }
    $result;
}

sub cp_if_newer {
    # Given exactly two non-directory file names, where the second one might not
    # exist yet, copy from one to another if the source file is newer than the
    # destination.
    my ($from, $to) = @_;

    my $from_date = mtime($from);
    my $to_date = mtime($to);
    if (! defined($to_date) || $from_date > $to_date) {
	standard_cp($from, $to);
    }
    else {
	0;
    }
}

sub copy_directory {
    my ($from_dir, $to_dir, $file_to_date) = @_;
    my ($file, $from_file, $to_file);
    my @subdirs = ();
    my %copied_files = ();

    warn "$warn:  copy_directory($from_dir, $to_dir, $file_to_date);\n"
	if $verbose_p;
    $from_dir =~ s@/$@@
	unless $from_dir eq '/';
    opendir(FROM, $from_dir)
	|| die "$warn:  Couldn't open '$from_dir':  $!\nDied";
    while (defined($file = readdir(FROM))) {
	$from_file = "$from_dir/$file";
	$to_file = "$to_dir/$file";
	if ($file eq '.' || $file eq '..') {
	    # noop.
	}
	elsif (-d $from_file) {
	    push(@subdirs, $from_file, $to_file)
		if $big_recursive_p || $file eq '.AppleDouble';
	}
	elsif (-l $from_file) {
	    warn "$warn:  punting link $from_file.\n";
	}
	elsif (! -f $from_file) {
	    warn "$warn:  punting unknown file type for $from_file.\n";
	}
	elsif ($file_to_date) {
	    my $from_date = $ {$file_to_date}{$file};
	    if (defined($from_date)) {
		# parent file was copied, so this is forced.
		standard_cp($from_file, $to_file, $from_date);
	    }
	}
	else {
	    # cp_if_newer($from_file, $to_file);
	    my $from_date = mtime($from_file);
	    $from_date -= 3600
		if $daylight_savings_kludge;
	    my $to_date = mtime($to_file);
	    if (! defined($to_date) || $from_date > $to_date) {
		standard_cp($from_file, $to_file);
		$copied_files{$file} = $from_date;
	    }
	}
    }
    closedir(FROM);
    # Copy any subdirectories (there will be none unless -R was specified).
    while (@subdirs) {
	$to_dir = pop(@subdirs);
	$from_dir = pop(@subdirs);
	if ($to_dir =~ m@/.AppleDouble$@) {
	    # copy a .AppleDouble file only if it's parent gets copied.
	    copy_directory($from_dir, $to_dir, \%copied_files);
	}
	else {
	    # normal case.
	    copy_directory($from_dir, $to_dir);
	}
    }
}

### main body.
if (@ARGV == 2) {
    ($from, $to) = @ARGV;
    if (! -d $from) {
	# [this should do what the user intended whether or not $to is a
	# directory.  right?  -- rgr, 2-Sep-00.]
	cp_if_newer($from, $to);
    }
    elsif (-r $to && ! -d $to) {
	die "$warn:  Can't copy from a a directory onto a file.\nDied";
    }
    else {
	# Directory to directory copy.  [what does it mean if $from is a
	# directory, and $big_recursive_p is false?  -- rgr, 2-Sep-00.]
	copy_directory($from, $to);
    }
}
elsif (@ARGV > 2) {
    $to = pop(@ARGV);
    die "$warn:  not supported; died";
}
else {
    die "$warn:  Must have at least two args.\n";
}
