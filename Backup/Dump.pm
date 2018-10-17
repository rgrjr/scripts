### Backup dump object.
#
# Represents a single backup dump as a set of slices.
#
# [created.  -- rgr, 11-Mar-11.]
#

package Backup::Dump;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Dump->make_class_slots
	(qw(prefix date level base_name slices current_p));
}

sub entry_cmp {
    # This sorts first by date backwards, then by level backwards (if someone
    # performs backups at two different levels on the same day, the second is
    # usually an extracurricular L9 dump on top of the other).
    my ($self, $other) = @_;

    $other->date cmp $self->date
	|| $other->level <=> $self->level
	|| $self->prefix cmp $other->prefix;
}

sub file_stem {
    # Includes the directory name, but not the slice or file extension.
    # [Too DAR-specific?  -- rgr, 12-Mar-11.]
    my $self = shift;

    my $slices = $self->slices;
    my $stem = ($slices && @$slices
		? $slices->[0]->file
		: $self->base_name);
    # Turn this into a proper stem.
    $stem =~ s/\.\d+\.dar$//;
    return $stem;
}

sub age_in_days {
    my ($self) = @_;
    require Time::Local;

    my $date = $self->date;
    my ($year, $month, $dom) = unpack('A4A2A2', $date);
    my $time = Time::Local::timelocal(0, 0, 0,
				      $dom, $month-1, $year-1900);
    return int((time()-$time)/(24*3600));
}

1;
