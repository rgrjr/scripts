#!/usr/bin/perl -w
#
# Convert "svn log -xml" output into a historical narrative, annotated with
# files where possible, in reverse chronological order.
#
# [created.  -- rgr, 26-Nov-05.]
#
# $Id$

use strict;

### Main program.

my $entries = ChronoLog::Entry->parse_svn_log_xml(shift(@ARGV));
warn "$0:  No entries selected.\n"
    unless %$entries;
for my $revision (sort { $b <=> $a; } keys(%$entries)) {
    $entries->{$revision}->report;
}
	
### The ChronoLog::Entry class.

package ChronoLog::Entry;

use Date::Parse;
use XML::Parser;
use Date::Format;

# define instance accessors.
sub BEGIN {
  no strict 'refs';
  for my $method (qw(revision author encoded_date msg files)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift;
      @_ ? $self->{$field} = shift : $self->{$field};
    }
  }
}

sub new {
    my $class = shift;

    my $self = bless({}, $class);
    while (my ($attr, $value) = splice(@_, 0, 2)) {
	$self->$attr($value)
	    if $self->can($attr);
    }
    $self;
}

sub _add_file_information {
    # add file information.
    my $entries = shift;

    open(IN, "svn status --verbose |")
	or die;
    while (<IN>) {
	next
	    if /^\?/;
	chomp;
	s/^.\s*//;
	my ($current_rev, $file_rev, $author, $file_name) = split(' ');
	my $entry = $entries->{$file_rev};
	# [this is kind of lame; we can only attribute the file author if it is
	# the latest revision, in which case the revision already knows who the
	# author is.  -- rgr, 26-Nov-05.]
	push(@{$entry->{_files}},
	     [ $file_name, $file_rev, "author: $author" ])
	    if $entry && ! -d $file_name;
    }
    close(IN);
}

sub extract_subfield_string {
    my $thing = shift;

    (ref($thing) eq 'ARRAY' && @$thing == 3 && $thing->[1] eq '0'
     ? $thing->[2]
     # [it's not worth dying for this.  -- rgr, 26-Nov-05.]
     : '');
}

sub parse_svn_log_xml {
    my ($class, $source) = @_;
    $source ||= '-';

    my $parser = new XML::Parser(Style => 'Tree');
    my $tokens = $parser->parsefile($source);
    my %entries;
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
	    my $entry = $class->new
		(revision => $revision,
		 msg => extract_subfield_string($keyed_content{msg}),
		 author => $author,
		 encoded_date => $encoded_date);
	    $entries{$revision} = $entry;
	}
    }
    _add_file_information(\%entries)
	if %entries;
    \%entries;
}

sub report {
    my $self = shift;

    my $date_format_string = '%Y-%m-%d %H:%M:%S';
    my $formatted_date = time2str($date_format_string, $self->encoded_date);
    print("$formatted_date:\n");
    for my $line (split("\n", $self->msg)) {
	# indent by two, skipping empty lines.
	unless ($line =~ /^\s*$/) {
	    $line =~ s/^\t*/$&  /;
	    print "$line\n";
	}
    }
    print("  => Revision ", $self->revision,
	  ":  author: ", $self->author, "\n");
    my $files = $self->files;
    if ($files) {
	for my $entry (sort { $a->[0] cmp $b->[0]; } @$files) {
	    my ($file_name, $file_rev, $date_etc) = @$entry;
	    # [this is kinda lame.  -- rgr, 26-Nov-05.]
	    # print "  => $file_name $file_rev:  $date_etc\n";
	    print "  => $file_name\n";
	}
    }
    print "\n";
}
