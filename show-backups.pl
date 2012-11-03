#!/usr/bin/perl -w
#
# List backup files in inverse chronological order.
#
# [created.  -- rgr, 26-May-04.]
#
# $Id$

use strict;
use warnings;

BEGIN {
    # [this is useful for debugging.  -- rgr, 18-Jan-12.]
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Getopt::Long;
use Date::Parse;
use Pod::Usage;

use Backup::DumpSet;
use Backup::Slice;

my $usage = 0;
my $help = 0;
my $man = 0;
my ($min_level, $max_level);
my ($before_date, $since_date);
my $slices_p = 0;
my $prefix = '*';

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'slices!' => \$slices_p,
	   'before=s' => sub {
	       $before_date = str2time($_[1])
		   or die "$0:  Can't parse date '$_[1]'.\n";
	   },
	   'since=s' => sub {
	       $since_date = str2time($_[1])
		   or die "$0:  Can't parse date '$_[1]'.\n";
	   },
	   'level=s' => sub {
	       ($min_level, $max_level) = split(/[:.]+/, $_[1]);
	       $max_level = $min_level
		   unless defined($max_level);
	   },
	   'prefix=s' => \$prefix)
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
my $dump_set_from_prefix
    = Backup::DumpSet->find_dumps(prefix => $prefix,
				  root => \@search_roots);

# For each prefix, generate output sorted with the most recent at the top, and a
# '*' marking each of the current backup files.  (Of course, we only know which
# files are "current" in local terms.)
my $n_prefixes = 0;
for my $pfx (sort(keys(%$dump_set_from_prefix))) {
    my $set = $dump_set_from_prefix->{$pfx};
    $set->mark_current_dumps();
    my $first_slice_p = 1;
    for my $dump (@{$set->dumps}) {
	if ($before_date || $since_date) {
	    my $dump_date = str2time($dump->date);
	    next
		if $before_date && $before_date <= $dump_date;
	    last
		if $since_date && $since_date > $dump_date;
	}
	next
	    if (defined($min_level)
		&& ! ($min_level <= $dump->level
		      && $dump->level <= $max_level));
	print "\n"
	    # If not showing slice files, we want a blank line between the last
	    # slice of one set and the first slice of the next set.
	    if $n_prefixes && ! $slices_p && $first_slice_p;
	$first_slice_p = 0;
	for my $slice (sort { $a->entry_cmp($b); } @{$dump->slices}) {
	    if ($slices_p) {
		print $slice->file, "\n";
	    }
	    else {
		my $listing = $slice->listing;
		substr($listing, 1, 1) = '*'
		    if $dump->current_p;
		print $listing, "\n";
	    }
	}
    }
    $n_prefixes++;
}

__END__

=head1 NAME

show-backups.pl -- generate a sorted list of backup dump files.

=head1 SYNOPSIS

    show-backups.pl [ --help ] [ --man ] [ --usage ]
                    [ --slices ] [ --since=<date> ] [ --prefix=<pattern> ]
                    [ --level=<level> | --level=<min>:<max> ]

where:

    Parameter Name     Deflt  Explanation
     --help                   Print detailed help.
     --level            all   If specified, only do dumps in this range.
     --man                    Print man page.
     --prefix           '*'   Partition prefix on files; wildcarded.
     --since                  If specified, only do dumps since this date.
     --slices                 If specified, print only slice file names.
     --usage                  Print this synopsis.

=head1 DESCRIPTION

C<show-backups.pl> looks in certain subdirectories for files that end
in ".dump", and prints them sorted by prefix and date (i.e. what was
backed up and when).

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--sli>
or C<--sl> for C<--slices>), options with arguments can be given as
two words (e.g. C<--prefix '*'>) or in one word separated by an "="
(e.g. C<--prefix='*'>), and "-" can be used instead of "--".

=over 4

=item B<--before>

If specified, then treat only dumps made before this date.  Date
formats acceptable to C<Date::Parse> may be used.  Note that this is
checked against the date encoded in the file name, and not the file
modification time.

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--level>

If specified as an integer from 0 to 9, prints only dumps at that
level.  If two integers are given separated by dots or colons
(e.g. "0:1" or "2..9"), then only dumps within that range of levels
are considered.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--prefix>

Specifies the dump file prefix.  This can be a glob-style wildcard;
the default is '*', which includes all dump files.

=item B<--since>

If specified, then treat only dumps made on or after this date.  Date
formats acceptable to C<Date::Parse> may be used.  Note that this is
checked against the date encoded in the file name, and not the file
modification time.

=item B<--slices>

If specified, print only the file name of each selected slice, one per
line.  This is useful for piping to other commands via C<xargs>.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

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

=item System backups (L<http://www.rgrjr.com/linux/backup.html>)

=item C<cd-dump.pl> (L<http://www.rgrjr.com/linux/cd-dump.pl.html>)

=item C<backup.pl> (L<http://www.rgrjr.com/linux/backup.pl.html>)

=back

=head1 COPYRIGHT

Copyright (C) 2004-2012 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers E<lt>rogers@rgrjr.dyndns.org<gt>

=cut
