### Base class for backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#
# $Id$

package Backup::Entry;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
sub BEGIN {
  no strict 'refs';
  for my $method (qw(prefix date level file base_name
                     catalog_p index current_p)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift;
      @_ ? ($self->{$field} = shift) : $self->{$field};
    }
  }
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

sub new_from_file {
    # Returns nothing if the file name is not parseable as a valid dump file.
    my ($class, $file) = @_;

    if ($file =~ m@([^/]+)-(\d+)-l(\d)(\w*)\.dump$@) {
	# dump/restore format.
	my ($pfx, $date, $level, $alpha_index) = //;
	my $index = $alpha_index ? ord($alpha_index)-ord('a')+1 : 0;
	return
	    Backup::Entry->new(prefix => $pfx,
			       date => $date,
			       level => $level,
			       index => $index,
			       file => $file);
    }
    elsif ($file =~ m@([^/]+)-(\d+)-l(\d)(-cat)?\.(\d+)\.dar$@) {
	# DAR format.
	my ($pfx, $date, $level, $cat_p, $index) = //;
	return
	    Backup::Entry->new(prefix => $pfx,
			       date => $date,
			       level => $level,
			       catalog_p => ($cat_p ? 1 : 0),
			       index => $index,
			       file => $file);
    }
}

sub entry_cmp {
    # This sorts first by level backwards (if someone performs backups at two
    # different levels on the same day, the second is usually an extracurricular
    # L9 dump on top of the other), then by catalog_p (to put the catalogs
    # first), and finally by index (for when a single backup is split across
    # multiple files).
    my ($self, $other) = @_;

    $other->level <=> $self->level
	|| ($other->catalog_p || 0) <=> ($self->catalog_p || 0)
	|| $self->index <=> $other->index;
}

1;
