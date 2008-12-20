#!/usr/bin/perl
#
# Hack to decode Postfix messages as stored in a queue.
#
# [created.  -- rgr, 15-Dec-08.]
#
# $Id:$

use strict;
use warnings;

sub process_file {
    my $stream = shift;

    my $bytes;
    my $in_message_p;
    while (1) {
	read($stream, $bytes, 2)
	    or die "eof";
	my ($code, $n_bytes) = split(//, $bytes);
	$n_bytes = ord($n_bytes);
	if ($n_bytes) {
	    if ($n_bytes > 128) {
		# This means we have a long line.
		read($stream, $bytes, 1)
		    or die "eof";
		$n_bytes = 128*ord($bytes) + $n_bytes%128;
	    }
	    read($stream, $bytes, $n_bytes)
		or die "eof";
	}
	else {
	    $bytes = '';
	}

	# Maybe update the $in_message_p state.
	if ($code eq 'M') {
	    $in_message_p = 1;
	}
	elsif ($code eq 'X') {
	    $in_message_p = 0;
	    next;
	}
	elsif ($code eq 'E') {
	    print "End of message.\n";
	    return;
	}

	# Generate output.
	if ($in_message_p) {
	    $bytes .= "\n"
		if $code eq 'N';
	    print $bytes;
	}
	else {
	    print("$code $n_bytes:  $bytes\n");
	}
    }
}

# Process command-line arguments, else stdin.
if (@ARGV) {
    for my $file (@ARGV) {
	print "*** $file:\n";
	open(my $in, $file)
	    or die;
	process_file($in);
    }
}
else {
    process_file(*STDIN);
}
