#!/usr/bin/perl -w
#
# List backup files in inverse chronological order.
#
# [created.  -- rgr, 26-May-04.]
#
# $Id$

use strict;
use Getopt::Long;
use Pod::Usage;

my $verbose_p = 0;		# this doesn't actually do anything yet.
my $usage = 0;
my $help = 0;
my $man = 0;
my $host_name = `hostname`;
chomp($host_name);
my $prefix = 'home';

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose+' => \$verbose_p,
	   'prefix=s' => \$prefix, 'host=s' => \$host_name)
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Figure out where to search for backups.
my @search_roots = @ARGV;
if (! @search_roots) {
    for my $base ('', '/alt', '/old', '/new') {
	next
	    if $base && ! -d $base;
	for my $root (qw(scratch scratch2 scratch3 scratch4 scratch.old)) {
	    my $dir = "$base/$root/backups";
	    push (@search_roots, $dir)
		if -d $dir;
	}
    }
    die "$0:  No search roots.\n"
	unless @search_roots;
}

# Find backup dumps on disk.
my $find_glob_pattern = '*.dump';
$find_glob_pattern = join('-', $prefix, $find_glob_pattern)
    if $prefix ne '*';
my $command = join(' ', 'find', @search_roots, '-name', "'$find_glob_pattern'");
open(IN, "$command |")
    or die "Oops; could not open pipe from '$command':  $!";
my %prefix_and_date_to_dumps;
while (<IN>) {
    chomp;
    if (m@([^/]+)-(\d+)-l(\d)\w*\.dump$@) {
	my ($pfx, $date, $level) = //;
	my $file = $_;
	my @stat = stat($file);
	my $size = $stat[7];
	$file =~ s@(/.*/)(.*)$@$2 [$host_name:$1]@;
	my $base_name = $2;
	# [sprintf can't handle huge numbers.  -- rgr, 28-Jun-04.]
	# my $listing = sprintf('%14i %s', $size, $file);
	my $listing = (' 'x(14-length($size))).$size.' '.$file;
	push(@{$prefix_and_date_to_dumps{$pfx}->{$date}},
	     ["$pfx-$date", $level, $listing, $base_name]);
    }
}

# For each prefix, generate output sorted with the most recent at the top, and a
# '*' marking each of the current backup files.  (Of course, we only know which
# files are "current" in local terms.)
my $n_prefixes = 0;
for my $pfx (sort(keys(%prefix_and_date_to_dumps))) {
    my $date_to_dumps = $prefix_and_date_to_dumps{$pfx};
    print "\n"
	if $n_prefixes;
    my $star_p = 0;
    my $last_star_level = 10;
    my $last_pfx_date = '';
    for my $date (sort { $b <=> $a; } keys(%$date_to_dumps)) {
	my $entries = $date_to_dumps->{$date};
	# This sorts first by level backwards (if someone performs backups at
	# two different levels on the same day, the second is usually an
	# extracurricular L9 dump on top of the other), and then by file name
	# (for when a single backup is split across multiple files).
	for my $entry (sort { $b->[1] <=> $a->[1]
				  || $a->[3] cmp $b->[3]; } @$entries) {
	    my ($pfx_date, $level, $listing) = @$entry;
	    $star_p = ($pfx_date eq $last_pfx_date
		       # same dump, no change in $star_p.
		       ? $star_p
		       # put a star if more comprehensive than the last.
		       : $level < $last_star_level);
	    substr($listing, 1, 1) = '*', $last_star_level = $level
		if $star_p;
	    print $listing, "\n";
	    $last_pfx_date = $pfx_date;
	}
    }
    $n_prefixes++;
}

__END__

=head1 NAME

show-backups.pl -- generate a sorted list of backup dump files.

=head1 SYNOPSIS

    show-backups.pl [ --help ] [ --man ] [ --usage ] [ --verbose ... ]
                    [ --prefix=<pattern> ] [ --host=<string> ]

where:

    Parameter Name     Deflt  Explanation
     --help	              Print detailed help.
     --man	              Print man page.
     --usage                  Print this synopsis.
     --verbose                Get debugging output; repeat to increase.
     --prefix         'home'  Required prefix on files; '*' to include all.
     --host-name    hostname  Host name for annotating listing lines.

=head1 DESCRIPTION

C<show-backups.pl> looks in certain subdirectories for files that end
in ".dump", and prints them sorted by prefix and date (i.e. what was
backed up and when).

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--ver>
or C<--verb> for C<--verbose>), options with arguments can be given as
two words (e.g. C<--prefix '*'>) or in one word separated by an "="
(e.g. C<--prefix='*'>), and "-" can be used instead of "--".

=over 4

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--verbose>

Turns on verbose message output.  Repeating this option results in
greater verbosity.

=item B<--host>

Specifies the host name to use for constructing the full directory
pathname in file listings.  This is useful for distinguishing
duplicate copies after merging listings from different systems.  The
default is whatever the C<hostname> command prints.

=item B<--prefix>

Specifies the dump file prefix.  This can be a glob-style wildcard,
e.g. if '*' is specified, then all dump files are considered.  The
default is 'home'.

=back

=head1 EXAMPLES

=head1 VERSION

 $Id$

=head1 BUGS

If you find any, please let me know.

=head1 SEE ALSO

=over 4

=item Dump/Restore at SourceForge (L<http://sourceforge.net/projects/dump/>)

=item L<dump(8)>

=item L<restore(8)>

=item System backups (L<http://rgrjr.dyndns.org/linux/backup.html>)

=item C<cd-dump.pl> (L<http://rgrjr.dyndns.org/linux/cd-dump.pl.html>)

=item C<backup.pl> (L<http://rgrjr.dyndns.org/linux/backup.pl.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2004-2005 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers E<lt>rogers@rgrjr.dyndns.org<gt>

=cut
