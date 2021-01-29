### Backup slice objects.
#
# [created (as Backup::Entry).  -- rgr, 3-Mar-08.]
# [renamed to Backup::Slice.  -- rgr, 28-Jun-10.]
#

package Backup::Slice;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Slice->make_class_slots
	(qw(prefix date level host_name file base_name catalog_p index));
}

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    if (! $self->base_name && $self->file) {
	my $base_name = $self->file;
	$base_name =~ s@(.*/)@@;
	# warn "file after:  base_name '$base_name' from file '$file'\n";
	$self->base_name($base_name);
    }
    $self;
}

sub size {
    # Pseudo-slot, self-initializing via stat, caches the result.
    my $self = shift;

    if (@_) {
	$self->{_size} = shift;
    }
    else {
	my $size = $self->{_size};
	if (! defined($size)) {
	    my $file = $self->file;
	    my @stat = stat($file);
	    $size = $stat[7];
	    $self->{_size} = $size;
	}
	$size;
    }
}

# Figurative constants for converting bytes to megabytes.
my $mega = 1024.0*1024.0;
my $mega_per_million = $mega/1000000;

sub size_in_mb {
    # Convert the size into MB.  Do this in two chunks, because Perl 5.6 thinks
    # it's always 4095 for values above 2^32.  -- rgr, 9-Sep-03.
    my ($self, $size) = @_;
    $size ||= $self->size;

    my $mb = (length($size) <= 6 ? $size : substr($size, -6))/$mega;
    $mb += substr($size, 0, -6)/$mega_per_million
	if length($size) > 6;
    return $mb;
}

my $local_host_name;	# Cache.  [Really, this is a kludge; how to combine
			# entries from multiple hosts?  -- rgr, 3-Mar-08.]

sub listing {
    my ($self) = @_;

    my $size = $self->size || 0;
    my $base_name = $self->base_name;
    my $file = $self->file;
    my $dir_name = $file =~ m@^(.*/)@ ? $1 : '';
    my $host = $self->host_name;
    if (! $host) {
	chomp($local_host_name = `hostname`)
	    unless $local_host_name;
	$host = $local_host_name;
    }
    # [sprintf can't handle huge numbers.  -- rgr, 28-Jun-04.]
    # my $listing = sprintf('%14i %s', $size, $file);
    return (' 'x(14-length($size)))."$size $base_name [$host:$dir_name]";
}

sub entry_cmp {
    # This sorts first by date backwards, then by level backwards (if someone
    # performs backups at two different levels on the same day, the second is
    # usually an extracurricular L9 dump on top of the other), then prefix
    # alphabetically, then by catalog_p (to put the catalogs first), and
    # finally by index (for when a single backup is split across multiple
    # files).
    my ($self, $other) = @_;

    $other->date cmp $self->date
	|| $other->level <=> $self->level
	|| $self->prefix cmp $other->prefix
	|| ($other->catalog_p || 0) <=> ($self->catalog_p || 0)
	|| $self->index <=> $other->index;
}

1;

__END__

=head1 Backup::Slice

Represents a single slice (file) that comprises part of a backup dump,
which in turn is represented as a C<Backup::Dump> object.  A slice is
not a complete backup, but it is a complete filesystem object, hence
this somewhat awkward dichotomy.

=head2 Accessors and methods

=head3 base_name

Returns or sets a string that is the file name of the slice without
the directory.  This is initialized by the C<new> method from the
C<file> slot.

=head3 catalog_p

Returns or sets a boolean that indicates whether this is a catalog
file made from another backup dump.

=head3 date

Returns or sets the eight-digit string component of the file name that
indicates the date the dump was made.

=head3 entry_cmp

Given another C<Backup::Slice> instance, return a -1,0,1 comparison
value reflecting the proper sort order of the two instances.  First we
compare by C<date> backwards (i.e. putting the most recent dump
first), then by C<level> backwards (if someone performs backups at two
different levels on the same day, the second is usually an
extracurricular L9 dump on top of the other), then by by C<prefix>
alphabetically forwards, then by catalog_p (to put the catalogs
first), and finally by ascending index (for when a single backup is
split across multiple files).  Since one usually only sorts slices
from the same C<Backup::Dump>, only the last two comparisons are
likely to be significant.

=head3 file

Returns or sets the full filename pathname of the slice.

=head3 host_name

Returns or sets the name of the computer on which the slice is found
(which will be shared among all slices).

=head3 index

Returns or sets the numeric index of the slice within the dump.

=head3 level

Returns or sets the backup level of the dump (which will be shared
among all slices).

=head3 listing

Returns the line used by C<show-backups.pl> for the slice, but without
the "*" for current dumps and without a trailing newline.

=head3 new

Create and return a new C<Backup::Slice> instance, initializing
C<base_name> in the process.

=head3 prefix

Returns or sets the dump prefix (which will be shared among all
slices).

=head3 size

Returns or sets the file size in bytes.  If not set, tries to
initialize the size on the first access using C<stat>, but this won't
work for remote files.

=head3 size_in_mb

Given an optional size value (which defaults to our C<size>), convert
it into MiB.  Tries to deal with integer size issues in older perls.

=cut
