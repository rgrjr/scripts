### Base class for backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#
# $Id$

package Backup::DumpSet;

use strict;
use warnings;

use Backup::Entry;

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

### Finding backup dumps on disk.

sub find_dumps {
    my ($class, %options) = @_;
    my $prefix = $options{prefix} || 'home';
    my $root = $options{root} || '.';
    my @search_roots = ref($root) eq 'ARRAY' ? @$root : ($root);

    my $find_glob_pattern = '*.d*';
    $find_glob_pattern = join('-', $prefix, $find_glob_pattern)
	if $prefix ne '*';
    my $command = join(' ', 'find', @search_roots,
		       '-name', "'$find_glob_pattern'");
    open(my $in, "$command |")
	or die "Oops; could not open pipe from '$command':  $!";
    my $dump_set_from_prefix = { };
    while (<$in>) {
	chomp;
	my $entry = Backup::Entry->new_from_file($_);
	my $set = $dump_set_from_prefix->{$prefix};
	if (! $set) {
	    $set = $class->new(prefix => $prefix);
	    $dump_set_from_prefix->{$prefix} = $set;
	}
	$set->add_dump_entry($entry);
    }
    return $dump_set_from_prefix;
}

### Finding and extracting current entries.

sub mark_current_entries {
    my ($self) = @_;

    my $current_p = 0;
    my $last_backup_level = 10;
    my $last_pfx_date = '';
    my $dumps_from_date = $self->dumps_from_date;
    # First, process entries backwards by date; the most recent one is always
    # current.
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

sub current_entries {
    my ($self) = @_;

    $self->mark_current_entries();
    my @current_entries;
    my $dumps_from_date = $self->dumps_from_date;
    # First, process entries backwards by date; the most recent one is always
    # current.
    for my $date (sort { $b <=> $a; } keys(%$dumps_from_date)) {
	my $entries = $dumps_from_date->{$date};
	# This sorts first by level backwards (if someone performs backups at
	# two different levels on the same day, the second is usually an
	# extracurricular L9 dump on top of the other), and then by index
	# (for when a single backup is split across multiple files).
	for my $entry (sort { $b->level <=> $a->level
				  || $a->index <=> $b->index;
		       } @$entries) {
	    push(@current_entries, $entry)
		if $entry->current_p;
	}
    }
    return @current_entries;
}

1;
