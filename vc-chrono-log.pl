#!/usr/bin/perl -w
#
# Convert "git log", "cvs log", or "svn log -xml" output into a historical
# narrative, annotated with files where possible.
#
# [created.  -- rgr, 26-Nov-05.]
#

use strict;
use warnings;

use Getopt::Long;

### Parse options.

my $commit_id_abbrev;
GetOptions('abbrev=i' => \$commit_id_abbrev);
$commit_id_abbrev //= 7;

### Main program.

my $parser = ChronoLog::Parser->new();
$parser->parse(*STDIN);
my $entries = $parser->log_entries;
if ($entries && @$entries) {
    for my $entry (@$entries) {
	$entry->report;
    }
}
else {
    print "No log output.\n";
}

### Class definitions.

package ChronoLog::Base;

=head2 B<ChronoLog::Base>

Base class for the other three guys.  Provides a
C<define_instance_accessors> method for building slot accessor
methods, and a C<new> class method that uses them to initialize slots.

=cut

sub new {
    my $class = shift;

    my $self = bless({}, $class);
    while (my ($attr, $value) = splice(@_, 0, 2)) {
	$self->$attr($value)
	    if $self->can($attr);
    }
    $self;
}

# define instance accessors.
sub define_instance_accessors {
    my $class = shift;

    for my $method (@_) {
	my $field = '_' . $method;
	no strict 'refs';
	*{$class.'::'.$method} = sub {
	    my $self = shift;
	    @_ ? $self->{$field} = shift : $self->{$field};
	}
    }
}

sub join_fields {
    my ($self, $fields) = @_;

    join(';  ',
	 map {
	     my $name = $_;
	     my $value = $self->$name;
	     (defined($value) && length($value) ? "$name: $value" : ());
	 } @$fields);
}
	
### The ChronoLog::Entry class.

package ChronoLog::Entry;

=head2 B<ChronoLog::Entry>

Class used to describe a single commit.  Sometimes this is called a
"changeset".  The C<files> slot is an arrayref of
C<RGR::CVS::FileRevision> objects, one for each file that was changed
as part of this commit.  Depending on what sort of information the VCS
"log" command provides, some of these slots may not be defined.

The C<report> method spits out a description of the commit in the
approved style, dealing with partial information as necessary.

Defined slots:

    author
    commitid
    encoded_date
    files
    msg
    revision
    tags

=cut

use Date::Format;

use base (qw(ChronoLog::Base));

# define instance accessors.
sub BEGIN {
    ChronoLog::Entry->define_instance_accessors
	(qw(revision commitid author encoded_date msg tags files));
}

sub report {
    my $self = shift;

    # [can't seem to make these work at top level.  -- rgr, 11-Mar-06.]
    my $per_entry_fields = [ qw(revision author commitid) ];
    my $per_file_fields = [ qw(state action lines branches) ];

    my $date_format_string = '%Y-%m-%d %H:%M:%S';
    my $formatted_date = time2str($date_format_string, $self->encoded_date);
    my $files = $self->files;
    print("$formatted_date:\n",
	  "  ", $self->join_fields($per_entry_fields), "\n");
    my $tags = $self->tags;
    print("  Tags: ", join(', ', @$tags), "\n")
	if $tags && @$tags;
    for my $line (split("\n", $self->msg)) {
	# indent by two, skipping empty lines.
	unless ($line =~ /^\s*$/) {
	    $line =~ s/^\t*/$&  /;
	    print "$line\n";
	}
    }
    if ($files) {
	my ($n_matches, $n_files) = (0, 0);
	my ($lines_removed, $lines_added);
	for my $entry (sort { $a->file_name cmp $b->file_name; } @$files) {
	    my $file_name = $entry->file_name;
	    $file_name .= ' '.$entry->file_rev
		if $entry->file_rev;
	    print(join(' ', "  => $file_name: ",
		       $entry->join_fields($per_file_fields)),
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
    }
    print "\n";
}

package RGR::CVS::FileRevision;

=head2 B<RGR::CVS::FileRevision>

Record the modification of a single file.  In the CVS case, this is
parsed out of textual information that looks like this:

    date: 2006-02-20 23:37:32 +0000; author: rogers; state: Exp;
    lines: +1 -3; commitid: 4b443fa52b84567;

and stored in the following slots:

    action
    author
    branches
    comment
    commitid
    encoded_date
    file_name
    file_rev
    lines
    raw_date
    state

=cut

use base (qw(ChronoLog::Base));

# define instance accessors.
sub BEGIN {
    RGR::CVS::FileRevision->define_instance_accessors
	(qw(comment raw_date encoded_date file_name file_rev
	    action author state lines commitid branches));
}

package ChronoLog::Parser;

=head2 B<ChronoLog::Parser>

Parse VCS log output, storing the result as an arrayref of
C<ChronoLog::Entry> instances in the C<log_entries> slot, sorted with
the most recent ones first.  The main entrypoint is the C<parse>
method, which takes a file handle and decides whether to parse
Subversion XML log format or CVS text format, based solely on whether
the input looks like XML.

Instance slots are:

    entry_from_revision [used only for SVN]
    log_entries
    vcs_name

=cut

use Date::Parse;

use base (qw(ChronoLog::Base));

# define instance accessors.
sub BEGIN {
    ChronoLog::Parser->define_instance_accessors
	(qw(vcs_name entry_from_revision log_entries));
}

sub extract_subfield_string {
    my $thing = shift;

    (ref($thing) eq 'ARRAY' && @$thing == 3 && $thing->[1] eq '0'
     ? $thing->[2]
     # [it's not worth dying for this.  -- rgr, 26-Nov-05.]
     : '');
}

sub parse_svn_xml {
    my ($self, $source) = @_;
    $source ||= *STDIN;
    require XML::Parser;

    $self->vcs_name('SVN');
    my $parser = XML::Parser->new(Style => 'Tree');
    my $tokens = $parser->parse($source);
    my $entries = $self->entry_from_revision;
    $entries = { }, $self->entry_from_revision($entries)
	unless $entries;
    while (my ($token, $content) = splice(@$tokens, 0, 2)) {
	die "Unexpected <$token> element [2].\n"
	    unless $token eq 'log';
	my @items = @$content;
	# no useful attributes.
	shift(@items);
	while (my ($token, $content) = splice(@items, 0, 2)) {
	    next
		if $token eq 0 || ! ref($content);
	    die "Unexpected <$token> element [2].\n"
		unless $token eq 'logentry';
	    my @items = @$content;
	    my $attrs = shift(@items);
	    my %keyed_content = @items;
	    my $revision = $attrs->{revision};
	    # warn "revision $revision";
	    my $author = extract_subfield_string($keyed_content{author});
	    my $date = extract_subfield_string($keyed_content{date});
	    my $encoded_date = str2time($date, 'UTC');
	    my $entry = ChronoLog::Entry->new
		(revision => $revision,
		 msg => extract_subfield_string($keyed_content{msg}),
		 author => $author,
		 encoded_date => $encoded_date);
	    my $files = $keyed_content{paths};
	    if ($files && ref($files) eq 'ARRAY') {
		my $parsed_files = [ ];
		my @files_content = @$files;
		# no useful attributes.
		shift(@files_content);
		while (my ($token, $content) = splice(@files_content, 0, 2)) {
		    next
			if $token eq 0 || ! ref($content);
		    die "Unexpected <$token> element [2].\n"
			unless $token eq 'path';
		    my ($attrs, $tag, $file_name, $extra) = @$content;
		    die "Oops; expected only a single path"
			if $tag ne '0' || $extra || ref($file_name);
		    my $rev = RGR::CVS::FileRevision->new
			(file_name => $file_name,
			 author => $author,
			 %$attrs);
		    push(@$parsed_files, $rev);
		}
		$entry->files($parsed_files);
	    }
	    $entries->{$revision} = $entry;
	}
    }

    # Produce the sorted set of entries.
    $self->log_entries([ map { $entries->{$_};
			 } sort { $b <=> $a; } keys(%$entries) ]);
    $entries;
}

sub parse_git {
    my ($self, $source, $first_line) = @_;
    $source ||= *STDIN;

    $self->vcs_name('Git');
    my $entries = [ ];
    my $entry_from_rev = $self->entry_from_revision;
    $entry_from_rev = { }, $self->entry_from_revision($entry_from_rev)
	unless $entry_from_rev;

    # Check for a prefix of "git show-ref" output.
    my $line = $first_line || <$source>;
    my %tags_from_commit;
    while ($line && $line =~ /^([a-f0-9]{40}) (\S+)$/) {
	chomp($line);
	my ($commit_id, $tag) = $line =~ //;
	$tag =~ s@^refs/(heads|remotes)/@@; # to match log style.
	push(@{$tags_from_commit{$commit_id}}, $tag);
	$line = <$source>;
    }

    # Check for use of commit ID abbreviations (the --abbrev option).
    if ($line && %tags_from_commit && $line =~ /^commit ([a-f0-9]+)$/) {
	my $commit_id = $1;
	my $id_length = length($commit_id);
	if ($id_length < 40) {
	    # Abbreviate all of the tags.
	    %tags_from_commit = map {
		my $tags = $tags_from_commit{$_};
		(substr($_, 0, $id_length) => $tags);
	    } keys(%tags_from_commit);
	}
    }

    # Read commits.
    while ($line) {
	chomp($line);
	# Must have the start of a commit.
	my ($commit_id) = $line =~ /^commit ([a-f0-9]+)$/;
	die "$source:$.:  Unexpected line '$line'.\n"
	    unless $commit_id;

	# Parse RFC822-style keywords.
	my %info;
	$line = <$source>;
	chomp($line);
	while ($line =~ /^([^:]+): *(.*)/) {
	    $info{$1} = $2;
	    $line = <$source>;
	    chomp($line);
	}

	# Read the commit comment.
	warn "nonblank line '$line' before comment?"
	    if $line;
	my $message = '';
	$line = <$source>;
	while ($line && $line ne "\n") {
	    $line =~ s/^    //;	# Undo "git log" indentation.
	    $message .= $line;
	    $line = <$source>;
	}
	$message =~ s/\s*git-svn-id:.*//;
	$line = <$source>;

	# Look for --stat output, which gives us file names and lines changed.
	my $files;
	if ($line && $line =~ /^ (\S.*\S)\s+\|/) {
	    while ($line && $line =~ /^ (\S.*\S)\s+\|\s+((Bin )?\d+.*)/) {
		my ($file_name, $lines) = $line =~ //;
		$lines =~ s/[-+\s]+$//;
		my $rev = RGR::CVS::FileRevision->new
		    (file_name => $file_name,
		     lines => $lines);
		push(@$files, $rev);
		$line = <$source>;
	    }
	    if ($line && $line =~ /^ (\d+) files? changed/) {
		# We don't really have any place to put these.
		$line = <$source>;
	    }
	    $line = <$source>
		if $line && $line eq "\n";
	}

	# Create the entry.
	my $encoded_date = str2time($info{Date}, 'UTC');
	my $revision = $commit_id;
	$revision = substr($revision, 0, $commit_id_abbrev)
	    if ($commit_id_abbrev
		&& length($revision) > $commit_id_abbrev);
	my $entry = ChronoLog::Entry->new
	    (revision => $revision,
	     msg => $message,
	     tags => $tags_from_commit{$commit_id},
	     author => $info{Author} || '?',
	     encoded_date => $encoded_date,
	     files => $files);
	push(@$entries, $entry);
	$entry_from_rev->{$commit_id} = $entry;
    }

    # Produce the sorted set of entries.
    $self->log_entries($entries);
    return $entry_from_rev;
}

sub parse_cvs {
    my ($self, $stream, %options) = @_;
    my $date_fuzz = $options{date_fuzz};
    $date_fuzz = 120		# in seconds.
	unless defined($date_fuzz);

    $self->vcs_name('CVS');

    my $commit_mods = { };
    my $comment_mods = { };

    my $record_file_rev_comment = sub {
	my ($file_name, $file_rev, $date_etc, $comment) = @_;

	my $date = $date_etc =~ s/date: *([^;]+); *// && $1 || '???';
	# warn "[got ($file_name, $file_rev, $date_etc):]\n";
	if ($date eq '???') {
	    warn "Oops; can't identify date in '$date_etc' -- skipping.\n";
	}
	else {
	    my $encoded_date = str2time($date, 'UTC');
	    $date_etc =~ s/; *$//;
	    my $rev = RGR::CVS::FileRevision->new
		(raw_date => $date,
		 encoded_date => $encoded_date,
		 comment => $comment,
		 file_name => $file_name,
		 file_rev => $file_rev,
		 map { split(/: */, $_, 2); } split(/; +/, $date_etc));
	    my $commit_id = $rev->commitid;
	    if ($commit_id) {
		push(@{$commit_mods->{$commit_id}}, $rev);
	    }
	    else {
		push(@{$comment_mods->{$comment}{$encoded_date}}, $rev);
	    }
	}
    };

    my $sort_file_rev_comments = sub {
	# Sort all revision comments by date and grouped by comment.

	# Combine file entries that correspond to a single commit.
	my @combined_entries;
	for my $commit_id (sort(keys(%$commit_mods))) {
	    # All entries with the same commitid perforce belong to the same
	    # commit, to which no entries without a commitid can belong.
	    my $entries = $commit_mods->{$commit_id};
	    my $entry = $entries->[0];
	    push(@combined_entries,
		 ChronoLog::Entry->new(encoded_date => $entry->encoded_date,
				       commitid => $commit_id,
				       author => $entry->author,
				       msg => $entry->comment,
				       files => $entries));
	}

	# Examine remaining entries by comment, then by date, combining all that
	# have the identical comment and nearly the same date.  [we should also
	# refuse to merge them if their modified files are not disjoint.  --
	# rgr, 29-Aug-05.]
	for my $comment (sort(keys(%$comment_mods))) {
	    # this is the latest date for a set of commits that we consider
	    # related.
	    my $last_date;
	    my @entries;
	    for my $date (sort(keys(%{$comment_mods->{$comment}}))) {
		if ($last_date && $date-$last_date > $date_fuzz) {
		    # the current entry probably represents a "cvs commit" event
		    # that is distinct from the previous entry(ies).
		    push(@combined_entries,
			 ChronoLog::Entry->new(encoded_date => $date,
					       author => $entries[0]->author,
					       msg => $comment,
					       files => [ @entries ]));
		    @entries = ();
		    undef($last_date);
		}
		$last_date = $date
		    if ! $last_date || $date > $last_date;
		push(@entries, @{$comment_mods->{$comment}{$date}});
	    }
	    push(@combined_entries,
		 ChronoLog::Entry->new(encoded_date => $last_date,
				       author => $entries[0]->author,
				       msg => $comment,
				       files => [ @entries ]))
		if @entries;
	}

	# Now resort by date.
	$self->log_entries([ sort { $b->encoded_date <=> $a->encoded_date;
				 } @combined_entries ]);
    };

    ## Main code.

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
	    $record_file_rev_comment->($file_name, $file_rev,
				       $date_etc, $comment);
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
    $sort_file_rev_comments->();
}

sub parse {
    # Main entrypoint.
    my ($self, $stream) = @_;

    my $first_line = <$stream>;
    if (! $first_line) {
    }
    elsif ($first_line =~ /^</) {
	# Must be XML.
	seek($stream, 0, 0);
	$self->parse_svn_xml($stream);
    }
    elsif ($first_line =~ /^(commit )?[a-f0-9]{40}/) {
	$self->parse_git($stream, $first_line);
    }
    else {
	$self->parse_cvs($stream);
    }
}
