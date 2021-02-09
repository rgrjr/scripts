#!/usr/bin/perl -w
#
# Backup databases defined by configuration files.
#
# [created.  -- rgr, 15-Jun-13.]
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Date::Format;

# Command-line option variables.
my $help = 0;
my $man = 0;
my $usage = 0;
my $verbose_p = 0;
my $overwrite_ok = 0;
my $time_format_string;
my @prefixes;
my $backup_dir;

### Process command-line arguments.

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose+' => \$verbose_p,
	   'prefix=s' => \@prefixes,
	   'overwrite!' => \$overwrite_ok,
	   'time-format=s' => \$time_format_string,
	   'backup-dir=s' => \$backup_dir)
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

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

__END__

=head1 NAME

backup-dbs.pl -- backup databases defined by configuration files

=head1 SYNOPSIS

    backup-dbs.pl [ --help ] [ --man ] [ --usage ] [ --verbose ... ]
		  [ --prefix=<string> ... ] [ --[no]overwrite ]
		  [ --time-format=<string> ... ] [ --backup-dir=<dir> ]
		  <config-file> ...

=head1 DESCRIPTION

Given one or more configuration files on the command line, extract
database connection information from each in turn, and perform a
complete database backup.  Configuration files are expected to have a
simple "keyword = value" structure, with optional comments starting
with "#" in the first column.  In order to be considered for backup,
a configuration file must have a complete set of
C<db_user>, C<db_password>, C<db_database>, and C<db_host> in order to
connect to the database.

Files are written to the C<--backup-dir=> (possibly overridden per
config file by a C<db_dump_directory> option) with file names of the
format

    <pfx>-<date>.dump

where C<< <pfx> >> may be specified by the C<--prefix> option
(possibly overridden per config file by a C<db_dump_prefix> option)
and the format of C<< <date> >> may be controlled by C<--time-format>
(possibly overridden per config file by a C<db_dump_time_format>
option).  Before creation, there is a check for duplication or
overwriting (controlled by C<--[no]overwrite>), the dump is first
written to a temporary file, and if successful, renamed to its final
destination.  If the C<--verbose> option is specified, extra progress
messages are emitted to the standard error stream; otherwise, the
operation is completely silent.

=head2 Time-limited backup series

The C<--overwrite> and C<--time-format> options can be used together
to institute a time-limited backup sequence.  For instance, specifying
just "%a" to get the day of the week abbreviation (e.g. "Tue") as the
date of the backup and allowing new backups to overwrite old ones
means that you will get only seven files (named, for example,
F<data-Sun.dump> through F<data-Sat.dump>) before the new files begin
to overwrite the oldest ones.

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--line-len>
or C<--lin> for C<--line-length>), options with arguments can be given as
two words (e.g. C<--line 100>) or in one word separated by an "="
(e.g. C<--line=100>), and "-" can be used instead of "--".

=over 4

=item B<--backup-dir>

Specifies the directory into which to put the backup files.  This may
be overridden by a C<db_dump_directory> option in the configuration
file, and defaults to the current directory if neither C<--backup-dir>
nor C<db_dump_directory> is specified.  C<backup-dbs.pl> dies with an
error message if the result is not a writable directory that is owned
by the current user.

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--no-overwrite>

=item B<--overwrite>

Specifies whether to overwrite existing backup files.  Note that this
only applies to backups made at some other time; if the file was made
earlier by this invocation of C<backup-dbs.pl> (by another
configuration file), then it dies with an error message.

=item B<--prefix>

Specifies a dump file name prefix.  The C<--prefix> option may be
specified multiple times; prefixes are consumed by configuration files
in their command-line order.  The prefix may be also be specified by a
C<db_dump_prefix> option in the configuration file (in which case a
command-line prefix is not used), and defaults to the C<db_database>
if no C<db_dump_prefix> is specified and no C<--prefix> options are
left.

=item B<--time-format>

Specifies a format string to date the backup files, which must not
contain any "/" characters.  See the C<Date::Format> module for
directives that may be included.  A good value is "%Y%m%d" which gives
the day part of the ISO date, e.g. "20210206" for 6-Feb-2021.
This may be overridden by a C<db_dump_time_format> option in the
configuration file, and defaults to "%R (which produces 24-hour times
such as 21:05) if neither C<--time-format> nor C<db_dump_time_format>
is specified.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--verbose>

Prints debugging information if specified.  May be specified multiple
times to get more debugging information (but the extra information is
usually pretty obscure).

=back

=head1 SEE ALSO

=over 4

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=back

=head1 BUGS

SECURITY BUG:  The database password is visible to the causual C<ps>
user while each database dump is running.

There should be a C<db_dump_date_format> option so that time-limited
backups could be done on a per-configuration-file basis.

There should also be a C<db_dump_overwrite_p>, for similar reasons.

=head1 AUTHOR

Bob Rogers C<< <rogers@rgrjr.com> >>

=head1 COPYRIGHT

Copyright (C) 2013 by Bob Rogers C<< <rogers@rgrjr.com> >>

This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
