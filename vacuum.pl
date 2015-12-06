#!/usr/bin/perl -w
#
#    vacuum.pl:  suck backup files across the network.
#
# [created.  -- rgr, 23-Dec-02.]
#
# [$Id$]

use strict;
use warnings;

BEGIN {
    # This makes it easier for testing.
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Getopt::Long;
use Pod::Usage;

use Backup::Config;
use Backup::DumpSet;
use Backup::Partition;

my $warn = $0;
$warn =~ s@.*/@@;

my $scp_program_name = '/usr/bin/scp';
my $from = '';		# source directory; required arg.
my $to = '';		# destination directory; required arg.
my @prefixes;		# file name prefix, to limit file choices.
my $since;		# date string, e.g. 200611 or 20061203.
my $mode = 'cp';	# 'mv' or 'cp'.
my $minimum_free_left;	# min. disk space in MB to leave after copying.
my $test_p = 0;
my $verbose_p = 0;
my $usage = 0;
my $help = 0;
my $config = Backup::Config->new();
GetOptions('test+' => \$test_p, 'verbose+' => \$verbose_p,
	   'config=s' => sub {
	       die "$0:  The --config option must be first.\n";
	   },
	   'usage|?' => \$usage, 'help' => \$help,
	   'from=s' => \$from, 'to=s' => \$to,
	   'mode=s' => \$mode, 'prefix=s' => \@prefixes,
	   'since=s' => \$since,
	   'min-free-left=i' => \$minimum_free_left)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

$verbose_p++ if $test_p;
$config->verbose_p($verbose_p);
$config->test_p($test_p);
$from = shift(@ARGV)
    if @ARGV && ! $from;
$to = shift(@ARGV)
    if @ARGV && ! $to;
pod2usage("$warn:  --to without --from.\n")
    if $to && ! $from;
pod2usage("$warn:  --since must be a date in the form '2006' or '200611' "
	  ."or '20061203'.\n")
    if $since && $since !~ /^\d{4,8}$/;

### Subroutines.

sub display_mb {
    my $mb = shift;
    my $n_digits = shift || '';
    my $suffix = 'MB';

    if (abs($mb) < 1.0) {
	$mb *= 1024;
	$suffix = 'KB';
    }
    elsif (abs($mb) > 1024.0) {
	$mb /= 1024;
	$suffix = 'GB';
    }
    sprintf("%$n_digits.2f%s", $mb, $suffix);
}

sub print_items {
    # generate a detail line from a file entry created by find_files_to_copy,
    # passed in $_ as by 'map'.  also used for debugging.
    my $entry = $_;

    printf("      %-25s  %s  level %d\n",
	   $entry->file, display_mb($entry->size_in_mb, 8), $entry->level);
}

sub site_file_delete {
    my ($file, $no_error_p) = @_;
    
    my $result = 0;
    if ($file =~ /:/) {
	my $command = "ssh '$`' \"rm -f '$''\"";
	warn "$warn: executing \"$command\"\n"
	    if $verbose_p;
	$result = system($command)
	    if ! $test_p;
    }
    else {
	warn "$warn: executing \"unlink('$file')\"\n"
	    if $verbose_p;
	$result = 1 != unlink($file)
	    if ! $test_p;
    }
    if (! $result) {
	# Success.
    }
    elsif ($no_error_p) {
	warn "$warn: could not delete '$file':  $!\n";
    }
    else {
	die "$warn: could not delete '$file':  $!\n";
    }
    $result;
}

sub site_file_md5 {
    # compute the MD5 checksum of the given file, which may be remote.
    my $file = shift;
    
    return 'test' 
	if $test_p;
    my $command
	= ($file =~ /:/
	   ? "ssh '$`' \"md5sum '$''\""
	   : "md5sum '$file'");
    open(IN, "$command |") || die;
    my @results = <IN>;
    close(IN);
    @results = split(' ', $results[0]);
    $results[0];
}

sub find_files_to_copy {
    # extract lists for the $from and $to directories, and find those files that
    # need to be copied, i.e. that exist in $from but not in $to, have the
    # specified prefix (if any), and are more recent than the $since date 
    # (if specified).  returns the list of file structures, prefixed
    # by the total space required.
    my ($from, $to, $prefixes) = @_;

    my @to = Backup::DumpSet->site_list_files($to, $prefixes);
    my %dest_latest_full;
    my %to = map { $dest_latest_full{$_->prefix} = $_
		       if $_->level == 0;
		   $_->file => $_; } @to;
    my @from = Backup::DumpSet->site_list_files($from, $prefixes);

    my @need_copying = ();
    my $total_space = 0;
    # map &print_items, @from;
    for my $from (@from) {
	my $name = $from->file;
	my $latest_full
	    = $from->level == 0 && $dest_latest_full{$from->prefix};
	if ($since && substr($from->date, 0, length($since)) le $since) {
	    # not current.
	}
	elsif (defined($to{$name})) {
	    # already there.
	}
	elsif ($latest_full && $latest_full->date > $from->date) {
	    # Superseded full dump.  This can happen when we are copying from a
	    # partition with an older full dump, when the current full dump is
	    # not present.  This is, of course, a kludge.  -- rgr, 5-Jun-10.
	    warn("$0:  Superseded full dump:  Date of ", $from->file, ' is ',
		 $from->date, ' which is older than ',
		 $latest_full->file, ".\n")
		if $verbose_p;
	}
	else {
	    # needs copying.
	    $total_space += $from->size_in_mb;
	    warn '[', $from->file, " needs copying.]\n"
		if $verbose_p > 1;
	    push(@need_copying, $from);
	}
    }
    $total_space, @need_copying;
}

sub copy_one_file {
    my ($local_to_local_p, $from, $to) = @_;

    my @command
	= ((! $local_to_local_p
	    ? ($scp_program_name, '-Bq')
	    : $mode eq 'mv' ? '/bin/mv'
	    : ('/bin/cp', '-p')),
	   $from, $to);
    print("Copying $from to $to",
	  ($verbose_p > 1 ? " (command '".join(' ', @command)."')" : ''),
	  "...")
	if $verbose_p;
    if (! $test_p) {
	my $result = system(@command);
	die "$warn:  Oops; copy of $from to $to got result $result; died"
	    if $result;
    }

    # Now verify the copy.
    if ($command[0] ne '/bin/mv') {
	my $from_md5 = site_file_md5($from);
	my $to_md5 = site_file_md5($to);
	warn "[got checksums '$from_md5' and '$to_md5']\n"
	    if $verbose_p > 1;
	if ($from_md5 ne $to_md5 && ! $test_p) {
	    # attempt cleanup.
	    site_file_delete($to, 1);
	    die("$warn:  $from (checksum '$from_md5') didn't copy ", 
		"to $to (checksum '$to_md5')\n");
	}
    }

    # Now it is safe to delete the source copy, if we were moving it over the
    # network.
    if (! $local_to_local_p && $mode eq 'mv') {
	site_file_delete($from);
    }
    print "done\n"
	if $verbose_p;
}

sub copy_backup_files {
    my ($from_partition, $from, $to, $prefixes) = @_;
    undef($prefixes)
	unless $prefixes && @$prefixes && $prefixes->[0] ne '*';

    # Find what needs to be copied.
    my $to_partition = find_partition($to);
    my $from_local_p = $config->local_partition_p($from_partition);
    my $to_local_p = $config->local_partition_p($to_partition);
    pod2usage("$warn:  Either --from or --to must be a local directory.\n")
	unless $from_local_p || $to_local_p;
    my $local_to_local_p = $from_local_p && $to_local_p;
    my ($total_space, @need_copying);
    if ($prefixes) {
	for my $prefix (@$prefixes) {
	    my ($pfx_space, @pfx_files)
		= find_files_to_copy($from, $to, $prefix);
	    $total_space += $pfx_space;
	    push(@need_copying, @pfx_files);
	}
    }
    else {
	# If we want them all, list them all at once.
	($total_space, @need_copying) = find_files_to_copy($from, $to, '');
    }
    if (@need_copying == 0) {
	warn "$0:  Nothing to copy.\n"
	    if $verbose_p;
	return 1;
    }

    # See if we have enough room on the destination.
    my $free_space
	# divide by 1024.
	= $to_partition->avail_blocks >> 10;
    my $min_free_left
	= $config->find_option('vacuum-min-free-left', $to_partition,
			       $minimum_free_left || 1024);
    my ($enough_space_p, $pretty_free_space, $pretty_free_left, $message)
	= (defined($free_space)
	   ? ($free_space-$total_space >= $min_free_left,
	      display_mb($free_space), display_mb($free_space-$total_space),
	      'not enough space left')
	   : (0, '???', '???', 
	      "can't find free space for the '$to' directory"));
    print "$warn:  Oops; $message:\n"
	if ! $enough_space_p;
    if ($verbose_p || ! $enough_space_p) {
	print "   Files to copy:\n";
	map &print_items, @need_copying;
	print "   Total space:    ", display_mb($total_space), "\n";
	print "   Free space:     $pretty_free_space\n";
	print "   Min free left:  ", display_mb($min_free_left), "\n";
	print "   Free left:      $pretty_free_left\n";
    }
    if (! $enough_space_p) {
	$config->fail_p(1);
	return;
    }

    # OK, green to go.
    map { my $name = $_->file;
	  copy_one_file($local_to_local_p, "$from/$name", "$to/$name");
      } @need_copying;
}

sub find_partition {
    my $file_name = shift;

    my ($partition)
	= Backup::Partition->find_partitions(partition => $file_name);
    die 'bug'
	unless $partition;
    return $partition;
}

### Main code.

if ($from && $to) {
    # Traditional command-line use.
    copy_backup_files(find_partition($from), $from, $to, \@prefixes);
}
elsif ($from) {
    # Vacuum one partition to its standard destination.
    my $from_partition = find_partition($from);
    my $to = $config->find_option('vacuum-to', $from_partition, '');
    if ($to) {
	copy_backup_files($from_partition, $from, $to, \@prefixes);
    }
    elsif (! $config->config_file) {
	pod2usage("$warn:  Missing --to arg.\n");
    }
    else {
	pod2usage(join('', "$warn:  '", $from_partition->host_colon_mount,
		       " has no 'vacuum-to' destination in ",
		       $config->config_file, ".\n"));
    }
}
else {
    # Vacuum all local partitions.
    my @local_partitions = Backup::Partition->find_partitions();

    my $find_part = sub {
	# [it would probably be better just to have a caching
	# Backup::Partition->find_partition method.  -- rgr, 27-Mar-11.]
	my $file = shift;

	my $local_part = $config->local_file_p($file);
	if ($local_part) {
	    for my $partition (@local_partitions) {
		return $partition
		    if $partition->contains_file_p($local_part);
	    }
	}
	else {
	    return find_partition($file);
	}
    };

    for my $partition (@local_partitions) {
	next
	    unless $config->local_partition_p($partition);
	my $name = $partition->host_colon_mount;
	my $from = $config->find_option('vacuum-from', $partition, '');
	my $to = $config->find_option('vacuum-to', $partition, '');
	next
	    unless $from || $to;
	my $from_partition = $from && $find_part->($from);
	my $to_partition = $to && $find_part->($to);
	if ($from_partition && $to_partition) {
	    my $prefixes
		= [ split(/\s*,\s*/,
			  $config->find_option('vacuum-prefix',
					       $partition, '*')) ];
	    if ($from_partition->host_colon_mount eq $name
		|| $to_partition->host_colon_mount eq $name) {
		copy_backup_files($from_partition, $from, $to, $prefixes);
	    }
	    else {
		warn("$warn:  Neither 'vacuum-from' nor 'vacuum-to' ",
		     "belong to '$name'.\n");
	    }
	}
	else {
	    if (! $to) {
		warn "$warn:  '$name' has 'vacuum-from' but no 'vacuum-to'.\n";
	    }
	    elsif (! $to_partition) {
		warn("$warn:  'vacuum-to' partition for '$name' ",
		     "does not exist.\n");
	    }
	    if (! $from) {
		warn "$warn:  '$name' has 'vacuum-to' but no 'vacuum-from'.\n";
	    }
	    elsif (! $from_partition) {
		warn("$warn:  'vacuum-from' partition for '$name' ",
		     "does not exist.\n");
	    }
	}
    }
}

__END__

=head1 NAME

vacuum.pl - Suck backup files across the network.

=head1 SYNOPSIS

    vacuum.pl [--test] [--verbose] [--usage|-?] [--help]
              [--from=<source-dir>] [--to=<dest-dir>]
              [--mode=(mv|cp)] [--prefix=<tag> ... ]
              [--since=<date-string>] [--min-free-left=<size>]

=head1 DESCRIPTION

This script selectively copies backup dumps over the network via
C<ssh> (though it can also be used to copy them locally).  It only
sees backup dump and tar files that follow the naming convention used
by the C<backup.pl> script, as described below.
Furthermore, it only copies or moves
those files that are both (a) still current and (b) do not already
exist at the destination.  A dump file is current if there is no more
recent dump file with the same prefix at the same or lower dump level.
If no such files exist, C<vacuum.pl> exits without error, and without
printing any messages.

When files are copied across the network (as opposed to being moved
locally), C<vacuum.pl> always does an C<md5sum> on them to verify the
copy, and the original is not deleted (if C<--mode=mv>)
unless the checksums match.

Each dump file name looks something like C<home-20021021-l9.dump> or
C<home-20051102-l0a.dump>, or C<home-20051102-l0.1.dar> for DAR, and
consists of the following five components:

=over 4

=item 1.

A prefix tag (e.g. C<home>), which is normally the last component of
the directory where the partition is mounted.  The tag is arbitrary
and may consist of multiple words, as in C<usr-local>; its purpose is
solely to group all of the backups make for a given partition.

=item 2.

The date the backup was made in "YYYYMMDD" format, e.g. '20021021'.
We assume that if more than one backup is made per partition per day,
the subsequent backups have increasing levels.  Under no circumstances
do we trust the file modification timestamp.

=item 3.

The dump level, a digit from 0 to 9, with a lowercase "L" prefix, as
in C<l9>.

=item 4.

An optional volume suffix.  DAR creates these automatically, by
appending C<.#.dar> to the stem, where "#" is a number starting from
one; all DAR backups always have an explicit volume suffix.

If a C<dump> backup requires two
or more volumes, then alphabetic volume designators are assigned from
'a', as in C<home-20051102-l0a.dump>, C<home-20051102-l0b.dump>,
C<home-20051102-l0c.dump>, etc.  This is only necessary for large
backups that are later copied to physical media.  [Note that
C<mkisofs> imposes a limit of 2147483646 bytes (= 2^31-2) on files
burned to DVD-ROM; see the "DVDs created with too large files" thread
at
L<http://groups.google.com/group/mailing.comp.cdwrite/browse_thread/thread/423a083cc7ad8ee8/fecd18c0f8507901%23fecd18c0f8507901>
for details.  -- rgr, 4-Nov-05.]

=item 5.

A file suffix (extension), which can be one of ".dump", ".dar", ".tar",
".tgz", or ".gtar" (for "GNU tar").  Files with other suffixes are
assumed to be something other than backup dumps, and are not copied.

=back

The prefix can be used to select a subset of
backup files to transfer.  Currently, there is no way to change the
set of allowed suffixes.

The backup date and backup level that are encoded in the file name are
used to decide which files are still current.  We use the 'official'
backup date in the names rather than the file date because the latter
may get changed as an artifact of copying.  See L<show-backups.pl>,
which can be used to show which backups are current.

C<vacuum.pl> checks the free space on the destination end, and will
refuse to copy in any of the following situations:

=over 4

=item 1.

If C<vacuum.pl> can't run C<ls> on either machine to establish the
list of files that need to be transferred.

=item 2.

If C<vacuum.pl> can't run C<df> to determine the current free space on
the destination machine

=item 3.

If the destination would not have at least 1GB of free space left over
after copying all current files.  The amount of required leftover
space can be changed via the C<--min-free-left> option.

=item 4.

If the destination directory is NFS-mounted on the destination machine.
In this case, you should vacuum directly onto the exporting machine.

=back

For all of the above situations, C<vacuum.pl> prints an error message
and exits with a non-zero return code (courtesy of C<die>).

=head1 OPTIONS

=over 4

=item B<--test>

If specified, no commands will be executed.  Instead, the commands will
just be echoed to C<STDERR>.

=item B<--verbose>

If specified, extra information messages are printed before and during
the copy.

=item B<--usage>

Prints a brief usage message.

=item B<--help>

Prints a more detailed help message.

=item B<--from>

Specified the source directory for the copy; required argument.  May
be specified positionally.  Either C<--from> or C<--to> may be on a
remote host, using C<ssh> syntax, e.g. C<"user@host:/path/to/dir/">,
but not both.

=item B<--to>

Specifies the destination directory for the copy; required argument.
May also be specified positionally.

=item B<--mode>

This can be either C<--mode=cp> to specify 'copy' mode (the default),
in which case the original file is always left in place, or
C<--mode=mv> to specify 'move' mode, in which case the source file is
deleted after a successful copy.

=item B<--prefix>

Specifies the dump file prefix tag; may be used to select a subset of
files to transfer.  May be specified more than once.  Unfortunately,
wildcards are not supported.

=item B<--since>

Specifies a cutoff date of the form '2006' or '200611' or '20061209'.
If specified, only dumps that are still current and are dated
B<strictly after> this date are copied.  This is a good way to get
current incrementals without also copying an older full dump.

Note that dump files before the cutoff are still used to determine
which files are current.  [This may be a misfeature.  -- rgr,
12-Dec-06.]

=item B<--min-free-left>

Specifies the minimum amount of free space to leave on the destination
device after all copying is done, in megabytes; the default is 1024
(one gigabyte).  If copying all of the requested files would require
more than this, then no files will be copied.

=back

=head1 USAGE AND EXAMPLES

[need some.  -- rgr, 18-Aug-04.]

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<tar(1)>

=item C<backup.pl> (L<http://www.rgrjr.com/linux/backup.pl.html>)

=item C<vacuum.pl> (L<http://www.rgrjr.com/linux/vacuum.pl.html>)

=item C<ssh(1)>

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=back

=head1 VERSION

 $Id$

=head1 BUGS

If you find any, please let me know.

=head1 COPYRIGHT

 Copyright (C) 2002-2005 by Bob Rogers <rogers@rgrjr.dyndns.org>.
 This script is free software; you may redistribute it and/or modify it
 under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
