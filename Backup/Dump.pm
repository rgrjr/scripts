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
	(qw(prefix date level slices current_p));
}

sub entry_cmp {
    # Compare two dumps, considering the more recent one to be "less than" the
    # other.  This sorts first by prefix forwards, then by date backwards, then
    # by level backwards (if someone performs backups at two different levels
    # on the same day, the second is usually an extracurricular L9 dump on top
    # of the other).
    my ($self, $other) = @_;

    return ($self->prefix cmp $other->prefix
	    || $other->date cmp $self->date
	    || $other->level <=> $self->level);
}

sub file_stem {
    # Includes the directory name, but not the slice or file extension.
    # [Too DAR-specific?  -- rgr, 12-Mar-11.]
    my $self = shift;

    my $slices = $self->slices;
    my $stem = $slices->[0]->file;
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

__END__

=head1 Backup::Dump

Class that represents a single backup dump as a set of files
("slices", in C<dar> terminology).  Each slice is represented as a
C<Backup::Slice> object in an arrayref stored in the C<slices> slot.

=head2 Accessors and methods

=head3 age_in_days

Uses C<Time::Local> and our C<date> slot value to compute the number
of days since this backup was made.  Used in determining eligibility
for reaping by C<clean-backups.pl>.

=head3 current_p

Returns or sets a boolean indicating whether the caller thinks this
backup dump is current, i.e. would be required to restore the most
recent state of the filesystem.  (The caller doesn't necessary have
enough information for this to be correct, though.)

=head3 date

Returns or sets the eight-digit string component of the file name that
indicates the date the dump was made.

=head3 entry_cmp

Given another C<Backup::Dump> instance, return a -1,0,1 comparison value
reflecting the proper sort order of the two instances,
considering the more recent one to be "less than" the other.
First we compare by C<prefix> alphabetically forwards, then by
C<date> backwards (i.e. putting the most recent
dump first), and finally by C<level> backwards (if someone
performs backups at two different levels on the same day, the second is
usually an extracurricular L9 dump on top of the other).

=head3 file_stem

Returns the slice file name prefix including the directory but without
the slice index or ".dar" suffix.  This will fail if the dump has no
slices (which is pretty broken in any case).

=head3 level

Returns or sets the numeric backup level, a digit from 0 (for a full
dump) to 9 (for most incremental).

=head3 prefix

Returns or sets a string that usually echoes the name of the mount
point of the partition that has been backed up.

=head3 slices

Returns or sets an arrayref of C<Backup::Slice> objects describing
slices that belong to this dump.

=cut
