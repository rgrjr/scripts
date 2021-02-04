#!/usr/bin/perl
#
# Extract all recipients from an mbox file.
#
# [created.  -- rgr, 28-Sep-03.]
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;

my $help = 0;
my $man = 0;
my $usage = 0;
my $debug_p = 0;
# The stuff in the middle (matched by "\S*") is the envelope sender -- we need
# "\S*" instead of "\S+" because bounces get "<>" as the sender address.  We
# just want to get to the DOW to help eliminate false hits.
my $from_line_regexp = '^From \S* +(Sun|Mon|Tue|Wed|Thu|Fri|Sat) ';
my @target_headers;

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose|v+' => \$debug_p,
	   'header=s' => \@target_headers)
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

### Subroutines.

my %addresses;
@target_headers = qw(Sender From Reply-To)
    unless @target_headers;
my $target_header_regexp = '^(' . join('|', @target_headers) . '): +';
sub process_header_lines {
    for (@_) {
	next
	    unless /$target_header_regexp/io;
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

__END__

=head1 NAME

all-correspondents.pl - extract addresses from mbox files

=head1 SYNOPSIS

    all-correspondents.pl [ --help ] [ --man ] [ --usage ] [ --verbose ... ]
    			  [ mbox-file ... ] > correpondents.text

=head1 DESCRIPTION

Given one or more mbox files on the command line or the standard
input, extract all unique email addresses in "Sender:", "From:", and
"Reply-To:"  headers, and spit them out on the standard output.

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--line-len>
or C<--lin> for C<--line-length>), options with arguments can be given as
two words (e.g. C<--line 100>) or in one word separated by an "="
(e.g. C<--line=100>), and "-" can be used instead of "--".

=over 4

=item B<--header>

Specifies a header to search for addresses.  The header name should be
specified without the trailing colon.  Case is not significant.
Multiple header names may be separated with "|" (which must be escaped
or quoted to protect it from interpretation by the shell) or specified
in multiple C<--header> options.  If not specified, the default
headers are "Sender", "From", and "Reply-To".

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=item B<--verbose>

Prints debugging information if specified.

=back

=head1 BUGS

If you find any, please let me know.

=head1 COPYRIGHT

 Copyright (C) 2003-2021 by Bob Rogers <rogers@rgrjr.dyndns.org>.
 This script is free software; you may redistribute it and/or modify it
 under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>

=cut
