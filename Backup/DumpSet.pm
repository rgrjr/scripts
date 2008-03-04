### Base class for backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#
# $Id$

package Backup::DumpSet;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
sub BEGIN {
  no strict 'refs';
  for my $method (qw(prefix dumps_from_date)) {
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
    $self->dumps_from_date({ })
	unless $self->dumps_from_date;
    $self;
}

sub add_dump_entry {
    my ($self, $entry) = @_;

    push(@{$self->dumps_from_date->{$entry->date || die}}, $entry);
    $entry;
}

sub mark_current_entries {
    my ($self) = @_;

    my $current_p = 0;
    my $last_backup_level = 10;
    my $last_pfx_date = '';
    my $dumps_from_date = $self->dumps_from_date;
    # First, process entries backwards by date; the last one is always current.
    for my $date (sort { $b <=> $a; } keys(%$dumps_from_date)) {
	my $entries = $dumps_from_date->{$date};
	# This sorts first by level backwards (if someone performs backups at
	# two different levels on the same day, the second is usually an
	# extracurricular L9 dump on top of the other), and then by index
	# (for when a single backup is split across multiple files).
	for my $entry (sort { $b->level <=> $a->level
				  || $a->index <=> $b->index;
		       } @$entries) {
	    my $pfx_date = join('-', $entry->prefix, $entry->date);
	    my $current_level = $entry->level;
	    my $listing = $entry->listing;
	    $current_p = ($pfx_date eq $last_pfx_date
			  # same dump, no change in $current_p.
			  ? $current_p
			  # put a star if more comprehensive than the last.
			  : $current_level < $last_backup_level);
	    $entry->current_p($current_p);
	    $last_backup_level = $current_level
		if $current_p;
	    $last_pfx_date = $pfx_date;
	}
    }
}

1;
