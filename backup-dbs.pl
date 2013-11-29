#!/usr/bin/perl -w
#
# Backup databases defined by configuration files.
#
# [created.  -- rgr, 15-Jun-13.]
#
# $Id$

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Date::Format;

# Command-line option variables.
my $verbose_p = 0;
my $overwrite_ok = 0;
my $time_format_string;
my @prefixes;
my $backup_dir;

### Process command-line arguments.

GetOptions('verbose+' => \$verbose_p,
	   'prefix=s' => \@prefixes,
	   'overwrite!' => \$overwrite_ok,
	   'time-format=s' => \$time_format_string,
	   'backup-dir=s' => \$backup_dir)
    or pod2usage(2);

# Another security hack:  Make these files readable by the creator only.
umask(127);

### Subroutines.

sub read_config_file {
    my ($file_name) = @_;

    open(my $in, '<', $file_name)
	or die "$0:  Could not open '$file_name':  $!";
    my $result = { };
    while (<$in>) {
	chomp;
	s/^\s+//;
	next
	    if /^#/;
	my ($keyword, $value) = split(/\s*=\s*/);
	next
	    unless $keyword;
	$result->{$keyword} = $value;
    }
    return $result;
}

sub _redundant_backup_p {
    # See if $backup_name is identical to the most recent backup file with $pfx
    # in $directory; return true if so.
    my ($pfx, $directory, $backup_name) = @_;
    my $backup_file = "$directory/$backup_name";

    my ($most_recent_backup, $most_recent_time);
    {
	opendir(DIR, $directory) or die "oops";
	while (my $name = readdir(DIR)) {
	    next
		if $name eq $backup_name;
	    next
		unless $name =~ /^$pfx-.*\.dump$/;
	    my $backup = "$directory/$name";
	    my $mtime = [ stat($backup) ]->[9];
	    ($most_recent_backup, $most_recent_time) = ($backup, $mtime)
		unless $most_recent_time && $most_recent_time > $mtime;
	}
    }
    return
	unless $most_recent_backup;
    # warn "most recent ($most_recent_backup, $most_recent_time)";
    return 0 == system("cmp $most_recent_backup $backup_file >/dev/null");
}

my %file_written_p;
sub backup_config {
    my ($config) = @_;
    # use Data::Dumper; warn Dumper($config);

    my ($user_name, $password, $db, $host, $pfx, $directory)
	= map { $config->{$_};
    } qw(db_user db_password db_database db_host
	 db_dump_prefix db_dump_directory);

    # Find the destination directory and prefix.
    $directory = $backup_dir
	if $backup_dir;
    $directory ||= '.';
    # This is a security check.
    die("$0:  Directory '$directory' does not exist, ",
	"or is not owned by the current user.\n")
	unless -O $directory;
    $pfx = pop(@prefixes)
	if @prefixes;
    $pfx ||= $db;

    # Create the timestamp.
    my $time_format = $config->{db_dump_time_format} || $time_format_string;
    my $timestamp = time2str($time_format || '%R', time);
    $timestamp =~ s/://;

    # Make the backup file name, and check that it is unique.
    my $backup_name = "$pfx-$timestamp.dump";
    my $backup_file = "$directory/$backup_name";
    die("$0:  Duplicate file name '$backup_file' for ",
	$config->config_file_name, ".\n")
	if $file_written_p{$backup_file}++;
    if (! $overwrite_ok && -e $backup_file) {
	warn "$0:  File '$backup_file' already exists; skipping.\n"
	    if $verbose_p;
	return;
    }

    # Write to a temporary file.
    my $backup_temp_name = "$pfx-$timestamp.tmp.dump";
    my $backup_temp_file = "$directory/$backup_temp_name";
    warn "$0:  Writing to $backup_temp_file.\n"
	if $verbose_p;
    my $command = join(' ', 'mysqldump -u', $user_name, "-p$password",
		       '-h', $host,
		       '--opt --skip-lock-tables --skip-dump-date',
		       $db, '>', $backup_temp_file);
    # warn "command '$command'";
    my $result = system($command);
    die "$0:  '$command' failed with result $result:  $!"
	if $result;

    # Keep the file if different from the latest, else remove it.
    if (_redundant_backup_p($pfx, $directory, $backup_temp_name)) {
	warn "$0:  Removing $backup_temp_file\n"
	    if $verbose_p;
	unlink($backup_temp_file);
    }
    else {
	warn "$0:  Renaming $backup_temp_file to $backup_file\n"
	    if $verbose_p;
	0 == system('mv', $backup_temp_file, $backup_file)
	    or die("$0:  Could not rename $backup_temp_file ",
		   "to $backup_file:  $!");
    }
}

### Main code.

die "$0:  No configuration files"
    unless @ARGV;
for my $file (@ARGV) {
    backup_config(read_config_file($file));
}
