#!/usr/bin/perl -w
#
# Extract all recipients from an mbox file.
#
# [created.  -- rgr, 28-Sep-03.]
#
# $Id$

use strict;

my $debug_p = 0;
# The stuff in the middle (matched by "\S*") is the envelope sender -- we need
# "\S*" instead of "\S+" because bounces get "<>" as the sender address.  We
# just want to get to the DOW to help eliminate false hits.
my $from_line_regexp = '^From \S* +(Sun|Mon|Tue|Wed|Thu|Fri|Sat) ';

### Subroutines.

my %addresses;
sub process_header_lines {
    for (@_) {
	next
	    unless /^(Sender|From|Reply-To): */i;
	s///i;
	my $address = (/<([^>]+)>/ ? $1 : $_);
	$address =~ s/\(.*\)//g;
	$address =~ s/\[.*\]//g;
	$address =~ s/\s+//g;
	$address = lc($address);
	$addresses{$address}++;
    }
}

sub search_one_file {
    # Process the given file, looking for hits, and generating the appropriate
    # output.  Returns the number of matches in the file, and updates the global
    # $matching_line_count appropriately.
    my ($file_name) = @_;

    if (! open(IN, $file_name)) {
	warn "$0:  Can't open '$file_name':  $!\n";
	return 0;
    }
    # Do lookahead in order to recognize mbox type.
    my $line = <IN>;
    return
	unless $line;
    my $rmail_p = ($line =~ /^BABYL OPTIONS/);
    my $last_line_empty_p = 1;		# start of file is good enough.
    my ($message, $line_number, $in_header_p) = (0, 0, ! $rmail_p);
    my @header_lines;
    while (defined($line)) {
	# Look for new messages.
	if ($rmail_p
	      # message start in rmail (babyl) format.  the string below
	      # displays as '^_^L' in emacs.
	      ? $line eq "\037\014\n"
	      # message start in standard mbox format.
	      : $last_line_empty_p && $line =~ /$from_line_regexp/o) {
	    # Start a new message.
	    $message++;
	    warn "$0:  $file_name:  Message $message starts on line $.\n"
		if $debug_p;
	    $in_header_p = 1;
	    # rmail buffers have an extra line before the headers that is not
	    # per RFC821 syntax.
	    $line = <IN>
		if $rmail_p;
	}
	else {
	    $line_number++;
	}
	# Skip rmail buffer option lines.
	next
	    if $rmail_p && $message == 0;
	# Look for header lines.
	push(@header_lines, $line)
	    if $in_header_p;
    }
    continue {
	# Look for header/body transitions.
	$last_line_empty_p = ($line eq "\n");
	if ($last_line_empty_p && $in_header_p) {
	    # Leaving the header: process the header lines.
	    process_header_lines(@header_lines)
		if @header_lines;
	    @header_lines = ();
	    $line_number = 0;
	    $in_header_p = 0;
	}
	# Next line.
	$line = <IN>;
	if ($rmail_p && $line_number == 0
	      && $line eq "*** EOOH ***\n") {
	    # Skip headers abbreviated by rmail for display.
	    while (defined($line)
		   && $line ne "\n") {
		$line = <IN>;
	    }
	    # Now skip the blank line at the end of the headers (which is what
	    # we thought we were skipping above).
	    $line = <IN>;
	}
    }
    close(IN);
}

### Main loop
if (@ARGV) {
    map { search_one_file($_); } @ARGV;
}
else {
    search_one_file('-');
}
for my $address (sort(keys(%addresses))) {
    print "$address\n";
}
