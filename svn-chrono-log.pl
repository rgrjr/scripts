#!/usr/bin/perl -w
#
# Convert "svn log -xml" output into a historical narrative, annotated with
# files where possible, in reverse chronological order.
#
# [created.  -- rgr, 26-Nov-05.]
#
# $Id$

use strict;
use warnings;

### Main program.

my $parser = ChronoLog::Parser->new();
$parser->parse_svn_log_xml(shift(@ARGV));
for my $entry (@{$parser->log_entries}) {
    $entry->report;
}

### Class definitions.

package ChronoLog::Base;

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
	
### The ChronoLog::Entry class.

package ChronoLog::Entry;

use Date::Format;

use base (qw(ChronoLog::Base));

# define instance accessors.
sub BEGIN {
    ChronoLog::Entry->define_instance_accessors
	(qw(revision commitid author encoded_date msg files));
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
	  "  ",
	  # [kludge.  -- rgr, 11-Mar-06.]
	  RGR::CVS::FileRevision::join_fields($self, $per_entry_fields), "\n");
    for my $line (split("\n", $self->msg)) {
	# indent by two, skipping empty lines.
	unless ($line =~ /^\s*$/) {
	    $line =~ s/^\t*/$&  /;
	    print "$line\n";
	}
    }
    if ($files) {
	for my $entry (sort { $a->file_name cmp $b->file_name; } @$files) {
	    my $file_name = $entry->file_name;
	    print(join(' ', "  => $file_name: ",
		       $entry->join_fields($per_file_fields)),
		  "\n");
	}
    }
    print "\n";
}

package ChronoLog::Parser;

use Date::Parse;
use XML::Parser;

use base (qw(ChronoLog::Base));

# define instance accessors.
sub BEGIN {
    ChronoLog::Parser->define_instance_accessors
	(qw(entry_from_revision log_entries));
}

sub extract_subfield_string {
    my $thing = shift;

    (ref($thing) eq 'ARRAY' && @$thing == 3 && $thing->[1] eq '0'
     ? $thing->[2]
     # [it's not worth dying for this.  -- rgr, 26-Nov-05.]
     : '');
}

sub parse_svn_log_xml {
    my ($self, $source) = @_;
    $source ||= '-';

    my $parser = XML::Parser->new(Style => 'Tree');
    my $tokens = $parser->parsefile($source);
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
	    my $author = extract_subfield_string($keyed_content{author}) || "";
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
			 file_rev => $revision,
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

package RGR::CVS::FileRevision;

use base (qw(ChronoLog::Base));

# [this is CVS-oriented; gotta fix that.  we're looking for an eventual
# unification of the svn-chrono-log.pl and cvs-chrono-log.pl scripts, but first
# we need a way to install modules.  -- rgr, 11-Mar-06.]

# E.g.: date: 2006-02-20 23:37:32 +0000; author: rogers; state: Exp; lines: +1
# -3; commitid: 4b443fa52b84567;

# define instance accessors.
sub BEGIN {
    RGR::CVS::FileRevision->define_instance_accessors
	(qw(comment raw_date encoded_date file_name file_rev
	    action author state lines commitid branches));
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
