#!/usr/bin/perl -w
#
# Convert the file-oriented "cvs log" output into a historical narrative, in
# reverse chronological order.
#
# [created.  -- rgr, 24-Jul-03.]
#
# $Id$

use strict;
use Date::Parse;
use Date::Format;

my $date_format_string = '%Y-%m-%d %H:%M';
my $date_fuzz = 120;		# in seconds.
my %commit_mods;		# arrayrefs keyed on commitid.
my %comment_mods;		# arrayrefs keyed on comment and date.

sub record_file_rev_comment {
    my ($file_name, $file_rev, $date_etc, $comment) = @_;

    my $date = $date_etc =~ s/date: *([^;]+); *// && $1 || '???';
    # warn "[got ($file_name, $file_rev, $date_etc):]\n";
    if ($date eq '???') {
	warn "Oops; can't identify date in '$date_etc' -- skipping.\n";
    }
    else {
	my $encoded_date = str2time($date, 'UTC');
	$date_etc =~ s/; *$//;
	my $rev = new RGR::CVS::FileRevision
	    (raw_date => $date, encoded_date => $encoded_date,
	     comment => $comment,
	     file_name => $file_name, file_rev => $file_rev,
	     map { split(/: */, $_, 2); } split(/; +/, $date_etc));
	my $commit_id = $rev->commitid;
	if ($commit_id) {
	    push(@{$commit_mods{$commit_id}}, $rev);
	}
	else {
	    push(@{$comment_mods{$comment}{$encoded_date}}, $rev);
	}
    }
}

my $per_entry_fields = [ qw(author commitid) ];
my $per_file_fields = [ qw(state lines) ];
sub print_file_rev_comments {
    # Print all revision comments, sorted by date and grouped by comment.

    # combine file entries that correspond to a single commit.
    my @combined_entries;
    for my $commit_id (sort(keys(%commit_mods))) {
	# All entries with the same commitid perforce belong to the same commit,
	# to which no entries without a commitid can belong.
	my $entries = $commit_mods{$commit_id};
	my $entry = $entries->[0];
	push(@combined_entries,
	     [$entry->encoded_date, $entry->comment, @$entries]);
    }
    # examine remaining entries by comment, then by date, combining all that
    # have the identical comment and nearly the same date.  [perhaps we should
    # also refuse to merge them if their modified files are not disjoint.  --
    # rgr, 29-Aug-05.]
    for my $comment (sort(keys(%comment_mods))) {
	my $last_date;
	my @entries;
	for my $date (sort(keys(%{$comment_mods{$comment}}))) {
	    if ($last_date && $date-$last_date > $date_fuzz) {
		# the current entry probably represents a "cvs commit" event
		# that is distinct from the previous entry(ies).
		push(@combined_entries, [$last_date, $comment, @entries]);
		@entries = ();
		undef($last_date);
	    }
	    $last_date ||= $date;
	    push(@entries, @{$comment_mods{$comment}{$date}});
	}
	push(@combined_entries, [$last_date, $comment, @entries])
	    if @entries;
    }
    # now resort by date and print them out.
    for my $date_entry (sort { -($a->[0] <=> $b->[0]); } @combined_entries) {
	my $date = time2str($date_format_string, shift(@$date_entry));
	my $comment = shift(@$date_entry);
	print("$date:\n",
	      "  ", $date_entry->[0]->join_fields($per_entry_fields), "\n");
	for my $line (split("\n", $comment)) {
	    print "  $line\n"
		if $line;
	}
	# CVS sorts the file names, but combining sets of entries with similar
	# dates can make them come unsorted.
	my ($n_matches, $n_files) = (0, 0);
	my ($lines_removed, $lines_added);
	for my $entry (sort { $a->file_name cmp $b->file_name; } @$date_entry) {
	    print(join(' ', "  =>", $entry->file_name, $entry->file_rev,
		       ': ', $entry->join_fields($per_file_fields)),
		  "\n");
	    my $lines = $entry->lines;
	    $lines_added += $1, $lines_removed += $2, $n_matches++
		if $lines && $lines =~ /\+(\d+) -(\d+)/;
	    $n_files++;
	}
	print("     Total lines: +$lines_added -$lines_removed", 
	      ($n_matches == $n_files ? '' : ' (incomplete)'),
	      "\n")
	    if $n_matches > 1 && ($lines_removed || $lines_added);
	print "\n";
    }
}

### Parser top level.

# state is one of qw(none headings descriptions).
my $state = 'none';
my $file_name;
my $line;
while (defined($line = <>)) {
    if ($line =~ /^RCS file: /) {
	# start of a new entry.
	$state = 'headings';
    }
    elsif ($state eq 'descriptions') {
	$line =~ /^revision (.*)$/
	    or warn "[oops; expected revision on line $.]\n";
	my $file_rev = $1;
	chomp(my $date_etc = <>);
	my $comment = '';
	$line = <>;
	if ($line =~ /^branches: /) {
	    chomp($line);
	    $date_etc .= "  ".$line;
	    $line = <>;
	}
	while ($line && $line !~ /^---+$|^===+$/) {
	    $comment .= $line;
	    $line = <>;
	}
	record_file_rev_comment($file_name, $file_rev, $date_etc, $comment);
	$state = (! $line || $line =~ /^========/ ? 'none' : 'descriptions');
    }
    # $state eq 'headings'
    elsif ($line =~ /^([^:]+):\s*(.*)/) {
	# processing the file header.
	my $tag = $1;
	if ($tag eq 'description') {
	    # eat the description.
	    $line = <>;
	    # [there are 28 hyphens and 77 equal signs printed by my CVS
	    # version.  how many are printed by yours?  -- rgr, 16-Feb-06.]
	    while ($line && $line !~ /^(========|--------)/) {
		$line = <>;
	    }
	    $state = ($line =~ /^========/ ? 'none' : 'descriptions');
	}
	elsif ($tag eq 'Working file') {
	    chomp($file_name = $2);
	}
    }
}
warn "[oops; final state is $state.]\n"
    unless $state eq 'none';
print_file_rev_comments();

package RGR::CVS::FileRevision;

# E.g.: date: 2006-02-20 23:37:32 +0000; author: rogers; state: Exp; lines: +1
# -3; commitid: 4b443fa52b84567;

# define instance accessors.
sub BEGIN {
  no strict 'refs';
  for my $method (qw(comment raw_date encoded_date file_name file_rev
		     author state lines commitid)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift;
      @_ ? ($self->{$field} = shift, $self) : $self->{$field};
    }
  }
}

sub new {
  my $class = shift;

  my $self = bless({}, $class);
  while (@_) {
      my $method = shift;
      my $argument = shift;
      $self->$method($argument)
	  if $self->can($method);
  }
  $self;
}

sub join_fields {
    my ($self, $fields) = @_;

    join(';  ',
	 map {
	     my $name = $_;
	     my $value = $self->$name;
	     (defined($value)
	      ? "$name: $value"
	      : ());
	 } @$fields);
}
