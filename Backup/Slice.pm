### Backup slice objects.
#
# [created (as Backup::Entry).  -- rgr, 3-Mar-08.]
# [renamed to Backup::Slice.  -- rgr, 28-Jun-10.]
#
# $Id$

package Backup::Slice;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Slice->make_class_slots
	(qw(prefix date level file base_name catalog_p index));
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

my $host_name;	# Cache.  [Really, this is an ugly kludge; how would we
		# combine entries from multiple hosts?  -- rgr, 3-Mar-08.]

sub listing {
    my ($self) = @_;

    my $size = $self->size;
    my $base_name = $self->base_name;
    my $file = $self->file;
    my $dir_name = $file =~ m@^(.*/)@ ? $1 : '';
    chomp($host_name = `hostname`)
	unless $host_name;
    # [sprintf can't handle huge numbers.  -- rgr, 28-Jun-04.]
    # my $listing = sprintf('%14i %s', $size, $file);
    return (' 'x(14-length($size)))."$size $base_name [$host_name:$dir_name]";
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
