#!/usr/bin/perl
#
# Print a summary of the contents of a maildir.
#
# [created.  -- rgr, 12-Dec-16.]
#

use strict;
use warnings;

use Getopt::Long;
use Mail::Header;
use IO::String;
use Mail::Field;

my $verbose_p = 0;
my $dir;

# Selection of /usr/include/sysexits.h constants.
use constant EX_OK => 0;
use constant EX_TEMPFAIL => 75;

### Process command-line arguments.

GetOptions('verbose+' => \$verbose_p,
	   'dir=s' => \$dir);
$dir ||= shift(@ARGV) || '/home/rogers/mail/incoming/spam/new';
die "$0:  No --dir option"
    unless $dir && -d $dir;

### Subroutines.

sub parse_headers {
    my ($message_source) = @_;

    # Read headers into a string.
    my $mbox_from_line = '';
    my $header = '';
    while (<$message_source>) {
	if (! $header && /^From / && ! $mbox_from_line) {
	    $mbox_from_line = $_;
	    # Don't put this in $header.
	    next;
	}
	$header .= $_;
	last
	    # end of headers.
	    if /^$/;
    }

    # Parse headers into a Mail::Header object.
    my $header_stream = IO::String->new($header);
    # Note that supplying a non-file stream to "new" does not work.
    my $head = Mail::Header->new();
    $head->read($header_stream);
    return ($head, $mbox_from_line, $header);
}

### Main code.

for my $file_name (split"\n", `ls $dir`) {
    my $message_source = "$dir/$file_name";
    next
	if ! $file_name || -d $message_source;
    open(my $message_stream, '<', $message_source)
	|| die "$0:  Can't open '$message_source':  $!";
    my ($head) = parse_headers($message_stream);
    my $from_head = $head->get('From') || '';
    my $from = Mail::Field->new('From' => $from_head);
    # warn $from->parse;
    # use Data::Dumper;
    # print Dumper($from);
    my $formatted_from
	= join(', ',
	       map { my $address = $_;
		     my $string = $address->phrase || $address->comment;
		     my $addr = $address->address;
		     if (! $string || $string =~ /=[?]/) {
			 # Don't show encodings.
			 $addr = "<$addr>"
			     # Make sure that bad addresses are obvious.
			     unless $addr =~ /@/;
			 $addr;
		     }
		     else {
			 $string = substr($string, 1, -1)
			     if $string =~ /^".*"$/;
			 $string =~ s/[\240]/ /g;
			 $string =~ s/\s\s+/ /g;
			 $string .= " <$addr>"
			     if ($addr =~ /rgrjr/i
				 || length($string) + length($addr) < 40);
			 $string;
		     }
	       } $from->addr_list);
    printf("[ ]  %-28s  %s\n", $file_name, $formatted_from);
}
