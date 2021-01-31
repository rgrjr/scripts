#!/usr/bin/perl -w
#
# Trying to find regexps in mbox files.
#
#    [old] Modification history:
#
# created.  -- rgr, 5-May-00.
# $from_line_regexp improvements, body-relative line #'s.  -- rgr, 8-May-00.
# fix bug in $from_line_regexp, command line args, @message_order kludge,
#	grep-compatible return value.  -- rgr, 12-May-00.
# update error handling, give usage.  -- rgr, 12-Jul-00.
# -noheaders option.  -- rgr, 16-Jul-00.
# fix bug in -e option.  -- rgr, 3-Aug-00.
# -m option, rmail (babyl) support.  -- rgr, 3-Apr-01.
#
# $Id$

use strict;

my $warn = 'mbox-grep.pl';
# The stuff in the middle (matched by "\S*") is the envelope sender -- we need
# "\S*" instead of "\S+" because bounces get "<>" as the sender address.  We
# just want to get to the DOW to help eliminate false hits.
my $from_line_regexp = ('^From \S* +(Sun|Mon|Tue|Wed|Thu|Fri|Sat'
			.'|Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) ');

my $matching_line_count = 0;	# global count, for exit code.
my @message_order = ();		# for messages reordered by VM.
my $list_files_p = 0;
my $number_p = 0;
my $include_header_hits_p = 1;	# default is to grab them all.
my $display_full_message_p = 0;	# print the message & not hit lines (-m option).
my $n_unreadable_files = 0;	# for exit code.
my $debug_p = 0;
my $regexp;
my $show_file_p;

### Process arguments.
# SunOS 4.1.4 grep args are "-bchilnsvw", with "-e" and "-f" args separate.  We
# handle only a small subset of those.
my $errors = 0;
while ($ARGV[0] =~ /^-./) {
    my $arg = shift(@ARGV);
    if ($arg eq '-debug') {
	$debug_p = $arg;
    }
    elsif ($arg eq '-e') {
	$regexp = shift(@ARGV);
    }
    elsif ($arg eq '-noheaders') {
	$include_header_hits_p = 0;
    }
    else {
	foreach $arg (split(//, substr($arg, 1))) {
	    if ($arg eq 'h') { $show_file_p = 0; }
	    elsif ($arg eq 'l') { $list_files_p = 1; }
	    elsif ($arg eq 'm') { $display_full_message_p = 1; }
	    elsif ($arg eq 'n') { $number_p = 1; }
	    else {
		warn "$warn:  Option '-$arg' unknown/not supported.\n";
		$errors++;
	    }
	}
    }
}
# Implement defaults.
$regexp = shift(@ARGV)
    unless defined($regexp);
unless ($regexp) {
    warn "$warn:  Missing or empty regexp.\n";
    $errors++;
}
if ($display_full_message_p && $list_files_p) {
    warn "$warn:  Both -m and -l specified.\n";
    $errors++;
}
$show_file_p = (@ARGV > 1)
    # might have been turned off.
    unless defined $show_file_p;

if ($errors) {
    warn("\nUsage:  $warn -hl[m|n] [ -noheaders ] [ -e ] regexp file . . .\n\n",
	 "\t-l:  List hit file names instead of grep-like hit line\n",
	 "\t-m:  Show message instead of grep-like hit line\n",
	 "\t-n:  Show 'message#:line#:' at start of hit line\n\n");
    # This is in order to be compatible with grep return codes.
    exit(2);
}

### Subroutines.

sub search_one_file {
    # Process the given file, looking for hits, and generating the appropriate
    # output.  Returns the number of matches in the file, and updates the global
    # $matching_line_count appropriately.
    my $file_name = shift;
    my $last_line_empty_p = 1;		# start of file is good enough.
    # NB: $message and $line_number are one-based.
    my ($message, $line_number, $in_header_p) = (0, 0, 0);
    my ($message_match_count, $file_match_count) = (0, 0);
    my $saved_message = '';		# for $display_full_message_p use
    my ($line, $rmail_p, @header_hit_lines, @header_hit_line_numbers);
    my $do_hit;

    $do_hit = sub {
	# The line is a hit; print it (or whatever).
	my ($line_number, $line) = @_;

	if ($display_full_message_p && ! $number_p) {
	    # don't need to do anything extra here.
	}
	elsif (! $list_files_p) {
	    print(join(':',
		       ($show_file_p ? ($file_name) : ()),
		       ($number_p
			? (($message_order[$message] || $message),
			   $line_number)
			: ()),
		       $line));
	}
	elsif (! $file_match_count) {
	    print "$file_name\n";
	}
	$message_match_count++;
	$file_match_count++;
    };

    if (! open(IN, $file_name)) {
	warn "$warn:  Can't open '$file_name':  $!\n";
	$n_unreadable_files++;
	return 0;
    }
    # Do lookahead in order to recognize mbox type.
    $line = <IN>;
    $rmail_p = ($line =~ /^BABYL OPTIONS/);
    while (defined($line)) {
	# Look for new messages.
	if ($rmail_p
	      # message start in rmail (babyl) format.  the string below
	      # displays as '^_^L' in emacs.
	      ? $line eq "\037\014\n"
	      # message start in standard mbox format.
	      : $last_line_empty_p && $line =~ /$from_line_regexp/o) {
	    # Finish the last message.
	    print $saved_message
		if $display_full_message_p && $message_match_count;
	    # Start a new message.
	    $message++;
	    warn "$warn:  $file_name:  Message $message starts on line $.\n"
		if $debug_p;
	    $saved_message = '';
	    $line_number = $message_match_count = 0;
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
	# Look for message-order kludge in VM buffers.  This will be in the
	# header of the first message if present.  -- rgr, 12-May-00.
	if (! $rmail_p && $in_header_p && $message == 1
	    && $line =~ /^X-VM-Message-Order: *(.*)/) {
	    my $data = $1;
	    while (defined($line = <IN>)
		   && $line =~ /^[ \t]/) {
		$data .= $line;
		$line_number++;
	    }
	    $line_number++;	# handle extra read.
	    # The leading 0 is to make @message_order easily indexable by a
	    # one-based $message number.
	    @message_order = (0, split(' ', $1))
		if $data =~ /\(([0-9 \t\n]+)\)/;
	    warn("$warn: $file_name: Got order (", join(', ', @message_order),
		 ") from header line\n   $data")
		if $debug_p;
	}
	# Accumulate message, if we might need it later.
	if ($display_full_message_p) {
	    $saved_message .= $line
		if (($include_header_hits_p || ! $in_header_p)
		    # Don't bother saving rmail "end-of-message" indicator on
		    # the last message.
		    && $line ne "\037");
	    # That's all we need to do if the user is already going to see the
	    # message anyway.
	    next if $message_match_count;
	}
	# Look for hits.
	if ($line =~ /$regexp/o) {
	    if (! $in_header_p) {
		&$do_hit($line_number, $line);
	    }
	    elsif ($include_header_hits_p) {
		push(@header_hit_lines, $line);
		push(@header_hit_line_numbers, $line_number);
	    }
	}
    }
    continue {
	# Look for header/body transitions.
	$last_line_empty_p = ($line eq "\n");
	if ($last_line_empty_p && $in_header_p) {
	    # Leaving the header: process any hits to header lines, now that we
	    # know how to compute the line number offset.
	    for (my $i = 0; $i < @header_hit_lines; $i++) {
		&$do_hit($header_hit_line_numbers[$i] - $line_number,
			 $header_hit_lines[$i]);
	    }
	    @header_hit_lines = @header_hit_line_numbers = ();
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
    if ($display_full_message_p && $message_match_count && $saved_message) {
	# take care of the last message. 
	print $saved_message;
    }
    $matching_line_count += $file_match_count;
    $file_match_count;
}

### Main loop
if (@ARGV) {
    map {search_one_file($_)} @ARGV;
}
else {
    search_one_file('-');
}
# Return grep-compatible exit code.
exit ($n_unreadable_files ? 2 : ($matching_line_count > 0 ? 0 : 1));

=head1 NAME

mbox-grep.pl -- Perl regular expression search in mbox files

=head1 SYNOPSIS

    mbox-grep.pl [ -debug ] [ -hlmn ] [ [ -e ] <regexp> ] <file> ...

where:

    Parameter Name     Deflt  Explanation
     -debug             no    Whether to print extra debug info on stderr.
     -e                       Next arg is the expression.
     -h                       Show file name in output; default true if >1.
     -l                 no    Show only the file name for hits.
     -m                 no    Display the full message for hits.
     -n                 no    Show the hit line number (in message).

=head1 DESCRIPTION

=head1 OPTIONS

=over 4

=item B<--debug>

Enables a few obscure bits of debugging code that elucidate the
structure of the message file, implemented as extra output to the
standard error.

=item B<-e>

If this option is given by itself, the next word on the command line
is taken to be the regular expression; this is useful if the regular
expression itself starts with a "-".  (The other single-dash options
can be combined, but not this one; we're not as clever as the regular
C<grep> program.)

=item B<-h>

If specified, the name of the file is always used to prefix any hits.
The default is to prefix hits only if more than one file is named on
the command line.

=item B<-l>

If specified, the file name is output only once for a hit, instead of
one line per hit.  C<mbox-grep.pl> considers it an error and exits
with a grep-compatible exit code of 2 if both C<-m> and C<-l> are
specified.

=item B<-m>

If specified, the full message is displayed if a hit is found within
it.  C<mbox-grep.pl> considers it an error and exits with a
grep-compatible exit code of 2 if both C<-m> and C<-l> are specified.

=item B<-n>

If specified, shows the message number and the line number within the
message (a negative number indicates a line within the message
headers).

=back

=head1 BUGS

If you find any, please let me know.

=head1 SEE ALSO

=over 4

=item L<grep(1)>

=back

=head1 AUTHOR

Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>

=head1 COPYRIGHT

Copyright (C) 2020 by Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
