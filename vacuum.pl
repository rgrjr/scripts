#!/usr/bin/perl -w
#
#    vacuum.pl:  suck backup files across the network.
#
# [created.  -- rgr, 23-Dec-02.]
#
# [$Id$]

use strict;
use Getopt::Long;
use Pod::Usage;

my $warn = $0;
$warn =~ s@.*/@@;

my $VERSION = '0.3';

my $scp_program_name = '/usr/bin/scp';
my $from = '';		# source directory; required arg.
my $to = '';		# destination directory; required arg.
my $prefix = '';	# file name prefix, to limit file choices.
my $mode = 'cp';	# 'mv' or 'cp'.
my $min_free_left = 1024;	# min. disk space in MB to leave after copy.
my $test_p = 0;
my $verbose_p = 0;
my $usage = 0;
my $help = 0;
GetOptions('test+' => \$test_p, 'verbose+' => \$verbose_p,
	   'usage|?' => \$usage, 'help' => \$help,
	   'from=s' => \$from, 'to=s' => \$to,
	   'mode=s' => \$mode, 'prefix=s' => \$prefix,
	   'min-free-left=i' => \$min_free_left)
    or pod2usage(-verbose => 0);
pod2usage(-verbose => 1) if $usage;
pod2usage(-verbose => 2) if $help;

$verbose_p++ if $test_p;
$from = shift(@ARGV)
    if @ARGV && ! $from;
pod2usage("$warn:  Missing --from arg.\n")
    unless $from;
$to = shift(@ARGV)
    if @ARGV && ! $to;
pod2usage("$warn:  Missing --to arg.\n")
    unless $to;
pod2usage("$warn:  '".shift(@ARGV)."' is an extraneous positional arg.\n")
    if @ARGV;
pod2usage("$warn:  Either --from or --to must be a local directory.\n")
    unless -d $from || -d $to;
my $local_to_local_p = -d $from && -d $to;

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
    my ($name, $size, $level) = @$_;

    printf("      %-25s  %s  level %d\n",
	   $name, display_mb($size, 8), $level);
}

sub site_list_files {
    # parse directory listings, dealing with remote file syntax.
    my ($dir, $prefix) = @_;
    my @result = ();

    if ($dir =~ /:/) {
	my $host = $`;
	my $spec = $';
	open(IN, "ssh '$host' \"ls -l '$spec'\" |")
	    or die;
    }
    else {
	open(IN, "ls -l '$dir' |")
	    or die;
    }
    # now go backward through the files, taking only those that aren't
    # superceded by a more recent file of the same or higher backup level.
    my %levels = ();
    for my $line (reverse(<IN>)) {
	chomp($line);
	next
	    # look for the file date as a way of recognizing the size and name.
	    unless $line =~ /(\d+) ([A-Z][a-z][a-z] +\d+|\d\d-\d\d) +[\d:]+ (.+)$/;
	my $size = $1;
	my $file = $3;
	next
	    if $prefix && (substr($file, 0, length($prefix)) ne $prefix);
	next
	    unless $file =~ /^(.+)-(\d+)-l(\d)\.(g?tar|tgz|dump)$/;
	my ($tag, $date, $level) = $file =~ //;
	if (! defined($levels{$tag})
	    || $level < $levels{$tag}) {
	    # it's a keeper.  first, though, convert the size into MB.  do this
	    # in two chunks, because perl 5.6 thinks the answer is always 4095
	    # for values above 2^32.  -- rgr, 9-Sep-03.
	    my $mega = 1024.0*1024.0;
	    my $mega_per_million = $mega/1000000;
	    my $mb = (length($size) <= 6 ? $size : substr($size, -6))/$mega;
	    $mb += substr($size, 0, -6)/$mega_per_million
		if length($size) > 6;
	    # print "[file $file, tag $tag, date $date, level $level]\n";
	    push(@result, [$file, $mb, $level]);
	    $levels{$tag} = $level;
	}
    }
    close(IN);
    @result;
}

sub free_disk_space {
    # parse df output, dealing with remote file syntax.
    my ($dir) = @_;
    my $result;

    my ($host, $spec) = split(/:/, $dir);
    if (defined($spec)) {
	open(IN, "ssh '$host' \"df '$spec'\" |")
	    or die;
    }
    else {
	($host, $spec) = ('localhost', $dir);
	open(IN, "df '$dir' |")
	    or die;
    }
    my $line;
    while (! defined($result)
	   && defined($line = <IN>)) {
	die "$0:  '$dir' is mounted via NFS on $host.\n"
	    if $line =~ /^[-\w\d.]+:/;
	next
	    unless $line =~ m@^/dev/@;
	my @fields = split(' ', $line);
	$result = $fields[3] >> 10
	    if $fields[3] =~ /^\d+$/;
    }
    close(IN);
    die "$0:  Couldn't determine free space for '$spec' on $host.\n"
	unless $result;
    $result;
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
    die "$warn: could not delete '$file':  $!\n"
	if $result && ! $no_error_p;
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
    # need to be copied, i.e. that exist in $from but not in $to (and have the
    # specified prefix, if any).  returns the list of file structures, prefixed
    # by the total space required.
    my ($from, $to, $prefix) = @_;

    my %to = ();
    my @to = site_list_files($to, $prefix);
    # map &print_items, @to;
    foreach my $to (@to) {
	$to{$to->[0]} = $to;
    }
    my @from = site_list_files($from, $prefix);
    my @need_copying = ();
    my $total_space = 0;
    # map &print_items, @from;
    foreach my $from (@from) {
	my $name = $from->[0];
	if (! defined($to{$name})) {
	    $total_space += $from->[1];
	    push(@need_copying, $from);
	}
    }
    $total_space, @need_copying;
}

sub copy_one_file {
    my ($from, $to) = @_;
    
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
    # now verify the copy.
    if ($command[0] ne '/bin/mv') {
	my $from_md5 = site_file_md5($from);
	my $to_md5 = site_file_md5($to);
	warn "[got checksums '$from_md5' and '$to_md5']\n"
	    if $verbose_p;
	if ($from_md5 ne $to_md5 && ! $test_p) {
	    # attempt cleanup (locally, anyway).
	    unlink($to)
		if $to !~ /:/;
	    die("$warn:  $from (checksum '$from_md5') didn't copy ", 
		"to $to (checksum '$from_md5')\n");
	}
    }
    # now it is safe to delete the source copy, if we were moving it over the
    # network.
    if (! $local_to_local_p && $mode eq 'mv') {
	site_file_delete($from);
    }
    print "done\n"
	if $verbose_p;
}

sub copy_backup_files {
    my ($from, $to, $prefix) = @_;

    my ($total_space, @need_copying) 
	= find_files_to_copy($from, $to, $prefix);
    return 1
	if @need_copying == 0;
    my $free_space = free_disk_space($to);
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
    die
	if ! $enough_space_p;
    # OK, green to go.
    map { my $name = $_->[0];
	  copy_one_file("$from/$name", "$to/$name");
      } @need_copying;
}

copy_backup_files($from, $to, $prefix);

__END__

=head1 NAME

vacuum.pl - Suck backup files across the network.

=head1 SYNOPSIS

    vacuum.pl [--test] [--verbose] [--usage|-?] [--help]
              [--from=<source-dir>] [--to=<dest-dir>]
              [--mode=(mv|cp)] [--prefix=<tag>] [--min-free-left=<size>]

=head1 DESCRIPTION

This script selectively copies backup dumps over the network via
C<ssh> (though it can also be used to copy them locally).  It only
sees backup dump and tar files that follow the naming convention used
by the C<backup.pl> script.  Furthermore, it only copies or moves
those files that are both (a) still current and (b) do not already
exist at the destination.  A dump file is current if there is no more
recent dump file with the same prefix at the same or lower dump level.
If no such files exist, C<vacuum.pl> exits without error, and without
printing any messages.

When files are copied across the network (as opposed to being moved
locally), C<vacuum.pl> always does an C<md5sum> on them to verify the
copy, and the original is not deleted unless the checksums match.

Dump file names look something like C<home-20021021-l9.dump>, and
consist of (a) a prefix tag ("home"), which is normally the last
component of the directory where the directory is mounted, (b) the
date the backup was made, e.g. '20021021', and (c) the dump level,
e.g. '9'.  The suffix can be one of ".dump", ".tar", ".tgz", or
".gtar" (for "GNU tar").  The prefix can be used to select a subset of
backup files to transfer.  Currently, there is no way to change the
set of allowed suffixes.

The backup date and backup level that are encoded in the file name are
used to decide which files are still current.  We use the 'official'
backup date in the names rather than the file date because the latter
may get changed as an artifact of copying.  The set of current dumps
is generated by going backward through a directory listing, since
names that follow the convention sort in chronological order within a
series.

C<vacuum.pl> checks the free space on the destination end, and will
refuse to copy in any of the following situations:

=over 4

=item 1.

If C<vacuum.pl> can't run C<ls> on the source machine to establish the
list of files that need to be transferred.

=item 2.

If C<vacuum.pl> can't run C<df> (to determine the current free space)
or C<ls> (to determine which files are already present) on the
destination machine

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
files to transfer.

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

=item man dump(8)

=item man tar

=item C<backup.pl> (L<http://rgrjr.dyndns.org/linux/backup.pl.html>)

=item man ssh

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=back

=head1 VERSION

    $Version:$

=head1 BUGS

None known.

=head1 COPYRIGHT

Copyright (C) 2000-2003 by Bob Rogers <rogers@rgrjr.dyndns.org>.
This script is free software; you may redistribute it and/or modify it
under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
