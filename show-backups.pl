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
    unshift(@INC, $1)
	if $0 =~ m@(.+)/@;
}

use Getopt::Long;
use Pod::Usage;

use Backup::DumpSet;
use Backup::Entry;

my $verbose_p = 0;		# this doesn't actually do anything yet.
my $usage = 0;
my $help = 0;
my $man = 0;
my $prefix = 'home';

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose+' => \$verbose_p,
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
    print "\n"
	if $n_prefixes;
    $set->mark_current_entries();
    my $dumps_from_date = $set->dumps_from_date;
    for my $date (sort { $b <=> $a; } keys(%$dumps_from_date)) {
	my $entries = $dumps_from_date->{$date};
	for my $entry (sort { $a->entry_cmp($b); } @$entries) {
	    my $listing = $entry->listing;
	    substr($listing, 1, 1) = '*'
		if $entry->current_p;
	    print $listing, "\n";
	}
    }
    $n_prefixes++;
}

__END__

=head1 NAME

show-backups.pl -- generate a sorted list of backup dump files.

=head1 SYNOPSIS

    show-backups.pl [ --help ] [ --man ] [ --usage ] [ --verbose ... ]
                    [ --prefix=<pattern> ]

where:

    Parameter Name     Deflt  Explanation
     --help	              Print detailed help.
     --man	              Print man page.
     --usage                  Print this synopsis.
     --verbose                Get debugging output; repeat to increase.
     --prefix         'home'  Required prefix on files; '*' to include all.

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
