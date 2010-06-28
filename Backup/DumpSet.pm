### Base class for backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#
# $Id$

package Backup::DumpSet;

use strict;
use warnings;

use Backup::Slice;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    no strict 'refs';
    Backup::DumpSet->make_class_slots(qw(prefix dumps_from_date));
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

sub mark_current_entries {
    my ($self) = @_;

    # First, extract entries by prefix.  [Pity we don't store them that way.
    # -- rgr, 30-Nov-09.]
    my %entries_from_prefix;
    my $dumps_from_date = $self->dumps_from_date;
    for my $date (sort { $b <=> $a; } keys(%$dumps_from_date)) {
	my $entries = $dumps_from_date->{$date};
	for my $entry (@$entries) {
	    push(@{$entries_from_prefix{$entry->prefix}}, $entry);
	}
    }

    # Detect currency within each prefix separately.
    for my $prefix (keys(%entries_from_prefix)) {
	my $current_p = 0;
	my $last_backup_level = 10;
	my $last_date = '';
	# Process entries backwards by date and level; the most recent one is
	# always current.
	for my $entry (sort { $a->entry_cmp($b);
		       } @{$entries_from_prefix{$prefix}}) {
	    my $level = $entry->level;
	    my $date = $entry->date;
	    if ($level == $last_backup_level) {
		# We are still current only if part of the same backup.
		# [Better would be for Backup::Slice to include all files of a
		# multifile dump.  -- rgr, 4-May-10.]
		$current_p = $entry->date eq $last_date;
	    }
	    else {
		# We are still current iff more comprehensive than the last.
		$current_p = $level < $last_backup_level;
	    }
	    $entry->current_p($current_p);
	    ($last_backup_level, $last_date) = ($level, $date)
		if $current_p;
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
	for my $entry (sort { $a->entry_cmp($b); } @$entries) {
	    push(@current_entries, $entry)
		if $entry->current_p;
	}
    }
    return @current_entries;
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
	# current_entries logic above, but currently each Backup::DumpSet can
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
