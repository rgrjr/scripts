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

sub add_dump {
    my ($self, $file_name, $date, $level) = @_;

    my $key = "$date:$level";
    my $dump = $self->{_dumps_from_key}->{$key};
    if (! $dump) {
	$self->sorted_p(0);
	my $base_name = $file_name;
	$base_name =~ s@.*/@@;
	$dump = Backup::Dump->new(prefix => $self->prefix,
				  date => $date,
				  level => $level,
				  base_name => $base_name,
				  slices => [ ]);
	$self->{_dumps_from_key}->{$key} = $dump;
	push(@{$self->{_dumps}}, $dump);
    }
    return $dump;
}

sub add_slice {
    my ($self, $file_name, $date, $level, $index, $cat_p) = @_;

    my $dump = $self->add_dump($file_name, $date, $level);
    my $slice = Backup::Slice->new(prefix => $self->prefix,
				   date => $date,
				   level => $level,
				   catalog_p => $cat_p,
				   index => $index,
				   file => $file_name);
    push(@{$dump->slices}, $slice);
    return $slice;
}

### Finding backup dumps on disk.

sub _parse_file_name {
    # Returns nothing if the file name is not parseable as a valid dump file.
    my ($file_name) = @_;

    if ($file_name =~ m@([^/]+)-(\d+)-l(\d)(\w*)\.dump$@) {
	# dump/restore format.
	my ($pfx, $date, $level, $alpha_index) = $file_name =~ //;
	my $index = $alpha_index ? ord($alpha_index)-ord('a')+1 : 0;
	return ($pfx, $date, $level, $index, 0);
    }
    elsif ($file_name =~ m@([^/]+)-(\d+)-l(\d)(-cat)?\.(\d+)\.dar$@) {
	# DAR format.
	my ($pfx, $date, $level, $cat_p, $index) = $file_name =~ //;
	return ($pfx, $date, $level, $index, $cat_p ? 1 : 0);
    }
}

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
	my ($prefix, $date, $level, $index, $cat_p) = _parse_file_name($_);
	next
	    unless $prefix;
	my $set = $dump_set_from_prefix->{$prefix};
	if (! $set) {
	    $set = $class->new(prefix => $prefix);
	    $dump_set_from_prefix->{$prefix} = $set;
	}
	$set->add_slice($_, $date, $level, $index, $cat_p);
    }
    return $dump_set_from_prefix;
}

### Finding and extracting current entries.

sub mark_current_dumps {
    my ($self) = @_;

    # Sort our "dumps" slot backwards in time.
    my $dumps = $self->dumps || [ ];
    $dumps = [ sort { $a->entry_cmp($b); } @$dumps ];
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
    return grep { $_->current_p; } @{$self->dumps};
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
	my ($pfx, $date, $level, $index, $cat_p) = _parse_file_name($file);
	next
	    unless $pfx;
	next
	    if $prefix && $pfx ne $prefix;
	my $new_entry = Backup::Slice->new(prefix => $pfx,
					   date => $date,
					   level => $level,
					   catalog_p => $cat_p,
					   index => $index,
					   file => $file);
	$new_entry->size($size);

	# Decide if this file is current.  [Should merge this someday with the
	# current_dumps logic above, but currently each Backup::DumpSet can
	# only handle one prefix.  -- rgr, 14-Apr-08.]
	my $entry = $levels{$pfx};
	my ($entry_tag, $entry_date, $entry_level)
	    = ($entry ? @$entry : ('', '', undef));
	if (! defined($entry_level) || $level < $entry_level) {
	    # it's a keeper.
	    # warn "[file $file, tag $pfx, date $date, level $level]\n";
	    $levels{$pfx} = [$pfx, $date, $level];
	    push(@result, $new_entry);
	}
	elsif ($level == $entry_level
	       && $pfx eq $entry_tag && $date eq $entry_date) {
	    # another file of the current set.
	    # warn "[another $file, tag $pfx, date $date, level $level]\n";
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

=head3 add_dump

Given file name, date, and level arguments, look for and return an
existing C<Backup::Dump> with those characteristics, and create a new
one if not.  Semi-internal.

=head3 add_slice

Given file name, date, level, index, and "catalog_p" arguments, create
and return a new C<Backup::Slice>, adding it to one of our dumps.
Semi-internal.

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
