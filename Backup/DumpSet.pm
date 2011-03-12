### Sets of backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#
# $Id$

package Backup::DumpSet;

use strict;
use warnings;

use Backup::Slice;
use Backup::Dump;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::DumpSet->make_class_slots(qw(prefix dumps_from_date
                                         dumps_from_key dumps sorted_p));
}

sub new {
    my $class = shift;

    my $self = $class->SUPER::new(@_);
    $self->dumps_from_date({ })
	unless $self->dumps_from_date;
    die "bug"
	unless $self->prefix;
    $self;
}

sub add_dump_entry {
    my ($self, $slice) = @_;

    push(@{$self->dumps_from_date->{$slice->date || die}}, $slice);
    my $key = $slice->dump_key;
    my $dumps_from_key = $self->dumps_from_key;
    $self->dumps_from_key($dumps_from_key = { })
	unless $dumps_from_key;
    my $dump = $dumps_from_key->{$key};
    if (! $dump) {
	$self->sorted_p(0);
	$dump = Backup::Dump->new(prefix => $slice->prefix,
				  date => $slice->date,
				  level => $slice->level,
				  base_name => $slice->base_name,
				  slices => [ ]);
	$self->dumps_from_key->{$key} = $dump;
	push(@{$self->{_dumps}}, $dump);
    }
    push(@{$dump->slices}, $slice);
    return $slice;
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
	my $entry = Backup::Slice->new_from_file($_);
	next
	    unless $entry;
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

sub mark_current_dumps {
    my ($self) = @_;

    # Sort our "dumps" slot backwards in time.
    my $dumps = $self->dumps || [ ];
    $dumps = [ sort { $a->entry_cmp($b); } @{$self->dumps} ];
    $self->dumps($dumps);
    $self->sorted_p(1);

    # Process entries backwards by date and level; the most recent one is
    # always current.
    my $current_p = 0;
    my $last_backup_level = 10;
    for my $dump (@$dumps) {
	my $level = $dump->level;
	# We are still current iff more comprehensive than the last.
	$current_p = $level < $last_backup_level;
	$dump->current_p($current_p);
	$last_backup_level = $level
	    if $current_p;
    }
}

sub current_dumps {
    my ($self) = @_;

    $self->mark_current_dumps()
	unless $self->sorted_p;
    my $dumps = $self->dumps || [ ];
    return grep { $_->current_p; } @$dumps;
}

### vacuum.pl support.

sub site_list_files {
    # Parse directory listings, dealing with remote file syntax.  This is used
    # by vacuum.pl, and isn't very well integrated with the rest of the module.
    my ($self, $dir, $prefix) = @_;
    my @result = ();

    if ($dir =~ /:/) {
	my ($host, $spec) = split(':', $dir, 2);
	open(IN, "ssh '$host' \"ls -l '$spec'\" |")
	    or die;
    }
    else {
	open(IN, "ls -l '$dir' |")
	    or die;
    }

    # Now go backward through the files, taking only those that aren't
    # superceded by a more recent file of the same or higher backup level.
    my %levels = ();
    for my $line (reverse(<IN>)) {
	chomp($line);

	# Look for the file date as a way of recognizing the size and name.
	my ($size, $file);
	if ($line =~ /(\d+) ([A-Z][a-z][a-z] +\d+|\d\d-\d\d) +[\d:]+ (.+)$/) {
	    ($size, $file) = ($1, $3);
	}
	elsif ($line =~ /(\d+) \d+-\d\d-\d\d +\d\d:\d\d (.+)$/) {
	    # numeric ISO date.
	    ($size, $file) = $line =~ //;
	}
	else {
	    # not a file line.
	    next;
	}

	# Turn that into a Backup::Slice object.
	my $new_entry = Backup::Slice->new_from_file($file);
	next
	    unless $new_entry;
	next
	    if $prefix && $new_entry->prefix ne $prefix;
	$new_entry->size($size);

	# Decide if this file is current.  [Should merge this someday with the
	# current_dumps logic above, but currently each Backup::DumpSet can
	# only handle one prefix.  -- rgr, 14-Apr-08.]
	my ($tag, $date, $new_level)
	    = ($new_entry->prefix, $new_entry->date, $new_entry->level);
	my $entry = $levels{$tag};
	my ($entry_tag, $entry_date, $entry_level)
	    = ($entry ? @$entry : ('', '', undef));
	if (! defined($entry_level) || $new_level < $entry_level) {
	    # it's a keeper.
	    # warn "[file $file, tag $tag, date $date, level $new_level]\n";
	    $levels{$tag} = [$tag, $date, $new_level];
	    push(@result, $new_entry);
	}
	elsif ($new_level == $entry_level
	       && $tag eq $entry_tag && $date eq $entry_date) {
	    # another file of the current set.
	    # warn "[another $file, tag $tag, date $date, level $new_level]\n";
	    push(@result, $new_entry);
	}
	else {
	    # must have been superceded by something we've seen already.
	}
    }
    close(IN)
	or die "oops; pipe error:  $!";
    reverse(@result);
}

1;

__END__

=head1 Backup::DumpSet

=head2 Slots and methods

=head3 add_dump_entry

Add a new C<Backup::Slice>.  Semi-internal.

=head3 current_dumps

This returns a list of current C<Backup::Dump> objects, sorting them
if necessary.

=head3 dumps_from_date

Returns or sets a hash that maps date strings (the 8-digit format that
is used in the backup file names) to an arrayref of C<Backup::Slice>
objects.

=head3 find_dumps

Given as keyword options a C<prefix> (which defaults to "home") and a set
of C<search_roots> (which defaults to "."), find all backups

C<prefix> can be "*", in which case all dumps are found.  The return
value is a hash of prefix to a C<Backup::DumpSet> object that contains
all backups that have that prefix.  This is normally invoked as a
class method.

=head3 mark_current_dumps

Sorts the C<dumps> elements by time and level, and sets the
C<current_p> slot for each C<Backup::Dump> object.

=head3 new

Takes slot initializers, and creates and returns a new
C<Backup::DumpSet> object.

=head3 prefix

Returns or sets a string that names the backup file prefix for all of
the dumps contained in this dump set.  This is required.

=head3 site_list_files

Parse directory listings, dealing with remote file syntax.  This is
used by C<vacuum.pl>, and isn't very well integrated with the rest of
the module.

=cut
