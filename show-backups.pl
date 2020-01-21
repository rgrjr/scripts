#!/usr/bin/perl -w
#
# List backup files in inverse chronological order.
#
# [created.  -- rgr, 26-May-04.]
#

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
my ($min_level, $max_level, $sort_order, $slices_p);
my ($before_date, $since_date, $size_by_date_p);
my $prefix = '*';
my %include_prefix_p;

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'slices!' => \$slices_p,
	   'size-by-date!' => \$size_by_date_p,
	   'sort=s' => \$sort_order,
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
	   'prefix=s' => sub { $include_prefix_p{$_[1]}++; })
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

# Apply defaults.
$sort_order ||= ($size_by_date_p ? 'date' : 'prefix');
die "$0:  --size-by-date implies --sort=date.\n"
    if $size_by_date_p && $sort_order ne 'date';
die "$0:  --size-by-date is incompatible with the --slices option.\n"
    if $size_by_date_p && $slices_p;

# Figure out where to search for backups.
my @search_roots = @ARGV;
@search_roots = '/scratch*/backups'
    unless @search_roots;

# Find backup dumps on disk.
my $dump_set_from_prefix
    = Backup::DumpSet->find_dumps(prefix => \%include_prefix_p,
				  root => \@search_roots);
my @selected_dumps;
for my $pfx (sort(keys(%$dump_set_from_prefix))) {
    my $set = $dump_set_from_prefix->{$pfx};
    $set->mark_current_dumps();
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
	push(@selected_dumps, $dump);
    }
}

# Sort the selected dumps.
my @sorted_dumps
    = ($sort_order eq 'date'
	 ? sort {
	     # This is like entry_cmp, but forward by date.
	     $a->date cmp $b->date
		 || $b->level <=> $a->level
		 || $a->prefix cmp $b->prefix;
	   } @selected_dumps
       : $sort_order eq 'dvd'
	 ? map { $_->[1];
	   } sort { $a->[0] cmp $b->[0];
	   } map { my $name = $_->file_stem;
		   $name =~ s@.*/@@;
		   [ $name, $_ ];
	   } @selected_dumps
       : $sort_order eq 'prefix'
	 ? @selected_dumps
       : die "$0:  Unknown --sort order '$sort_order'.\n");

# Generate --size-by-date output if requested.
if ($size_by_date_p) {
    my $total_size = 0;
    my $last_date = '';

    my $do_date = sub {
	# Flush any pending date information.
	my ($next_date) = @_;

	print(join("\t", $last_date, $total_size), "\n")
	    if $last_date;
	$last_date = $next_date;
	$total_size = 0;
    };

    for my $dump (@sorted_dumps) {
	my $date = $dump->date;
	$do_date->($date)
	    if $date ne $last_date;
	# Accumulate.
	for my $slice (@{$dump->slices}) {
	    $total_size += $slice->size;
	}
    }
    $do_date->('');
    exit(0);
}

# Generate output.
my $last_prefix = '';
for my $dump (@sorted_dumps) {
    my $prefix = $dump->prefix;
    print "\n"
	# If not showing slice files, we want a blank line between the last
	# slice of one set and the first slice of the next set.
	if (! $slices_p && $sort_order eq 'prefix'
	    && $last_prefix && $prefix ne $last_prefix);
    $last_prefix = $prefix;
    for my $slice (sort { $a->entry_cmp($b); } @{$dump->slices}) {
	if ($slices_p) {
	    print $slice->file, "\n";
	}
	else {
	    # Put a '*' by each of the current backup files.  (Of course, we
	    # only know which files are "current" in local terms.)
	    my $listing = $slice->listing;
	    substr($listing, 1, 1) = '*'
		if $dump->current_p;
	    print $listing, "\n";
	}
    }
}

__END__

=head1 NAME

show-backups.pl -- generate a sorted list of backup dump files.

=head1 SYNOPSIS

    show-backups.pl [ --help ] [ --man ] [ --usage ] [ --prefix=<pattern> ... ]
                    [ --[no]slices ] [ --[no]date | --sort=(date|prefix|dvd) ]
                    [ --before=<date> ] [ --since=<date> ] [ --size-by-date ]
                    [ --level=<level> | --level=<min>:<max> ]
		    [ <search-root> ... ]

where:

    Parameter Name     Deflt  Explanation
     --before                 If specified, only dumps on or before this date.
     --help                   Print detailed help.
     --level            all   If specified, only do dumps in this range.
     --man                    Print man page.
     --prefix                 Partition prefix on files; may be repeated.
     --since                  If specified, only do dumps since this date.
     --size-by-date      no   Print a table of total size by dump date.
     --slices                 If specified, print only slice file names.
     --sort           prefix  Sort by prefix, date, or dvd order.
     --usage                  Print this synopsis.

=head1 DESCRIPTION

C<show-backups.pl> looks for files that end in ".dar" or ".dump" and
prints them sorted by prefix and date (i.e. what was backed up and
when).  By default it searches in F</scratch*/backups> and
subdirectories; this can be changed by specifying alternative search
roots on the command line (but you'll need to escape any wildcards).

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--sli>
or C<--sl> for C<--slices>), options with arguments can be given as
two words (e.g. C<--prefix home>) or in one word separated by an "="
(e.g. C<--prefix=home>), and "-" can be used instead of "--".

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

Specifies a dump file prefix; this option may be repeated.  The
default is to include all backup files.  (Glob-style wildcards are no
longer supported.)

=item B<--since>

If specified, then treat only dumps made on or after this date.  Date
formats acceptable to C<Date::Parse> may be used.  Note that this is
checked against the date encoded in the file name, and not the file
modification time.

=item B<--size-by-date>

If specified, print just a summary table of total dump size in bytes
as a function of dump date.  This option implies "--sort=date"; it is
an error to specify C<--size-by-date> along with any different sort
option, or the C<--slices> option.

=item B<--slices>

If specified, print only the file name of each selected slice, one per
line.  This is useful for piping to other commands via C<xargs>.

=item B<--sort>

Specifies the sort order; legal values are "prefix"
(groups by ascending prefix and then by descending date), "dvd" (by
ascending file name without the directory, as they would appear in a
DVD listing), and "date" (ascending date, descending level, and
ascending prefix).  If "prefix" sorting is used, and the C<--slices>
option was not specified, then blank lines are inserted to separate
each prefix.

The default is to sort by date if the C<--size-by-date> option was
specified, else to sort by prefix.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=back

=head1 EXAMPLES

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
