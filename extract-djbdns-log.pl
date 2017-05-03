#!/usr/bin/perl
#
# Produce a human-readable extract of djbdns queries.
#
# [created.  -- rgr, 1-May-17.]
#

use strict;
use warnings;

use Date::Format;

### Process args.

my (%address_p, @prefix_addresses, $current_p);
my $delay = 5;
my $log_directory = '/var/djbdns/dnscache/log/main';
for my $arg (@ARGV) {
    if ($arg =~ /^[\d.]+$/) {
	my $hex = dq2hex($arg);
	if (length($hex) == 8) {
	    # Complete address.
	    $address_p{$hex}++;
	}
	else {
	    # Address prefix.
	    push(@prefix_addresses, $hex);
	}
    }
    else {
	die "$0:  Unknown param '$arg'";
    }
}
die "$0:  No addresses"
    unless %address_p || @prefix_addresses;

### Subroutines.

sub dq2hex {
    # Given dotted-quad notation (which need not actually be four octects),
    # return a hex string without dots.
    my ($string) = @_;

    return join('', map { sprintf '%02x', $_; } split(/[.]/, $string));
}

sub hex2dq {
    # Split a hex string into dotted-quad notation (though we don't actually
    # care how many octets we get).  If the input is not an even number of
    # digits, the *last* digit is assumed to be zero.
    my ($hex_string) = @_;

    return join('.', unpack("C*", pack("H*", $hex_string)));
}

sub parse_tai64_date {
    my ($date_string) = @_;

    my $raw_len = length($date_string);
    my $nanoseconds;
    if ($raw_len == 25 || $raw_len == 33) {
	$nanoseconds = substr($date_string, 17, 8);
	$date_string = substr($date_string, 0, 17);
    }
    if ($date_string =~ /^\@40*([\da-f]+)$/) {
	my $date_hex = $1;
	return hex($1);
    }
    else {
	die "$0:  bad tai64 date string '$date_string'";
    }
}

sub host_match_p {
    my ($host_hex_string) = @_;

    return 1
	if $address_p{$host_hex_string};
    for my $candidate (@prefix_addresses) {
	return 1
	    if $candidate eq substr($host_hex_string, 0, length($candidate));
    }
}

my %file_done_p;

sub maybe_do_file {
    my ($file_name) = @_;

    return
	if $file_done_p{$file_name};
    open(my $in, '<', $file_name)
	or die "$0:  Can't open '$file_name':  $!";
    while (<$in>) {
	next
	    unless /query \d+ ([a-f\d]+):/ && host_match_p($1);
	chomp;
	my ($tai64_date, $tag, $idx, $host_and_ports, $rest)
	    = split(' ', $_, 5);
	my ($host, $port1, $port2) = split(':', $host_and_ports);
	my $hp_dec = join(':', hex2dq($host), hex($port1), hex($port2));
	my $unix_date = parse_tai64_date($tai64_date);
	print(join(' ', time2str('%Y-%m-%d-%T', $unix_date),
		   $tag, $idx, $hp_dec, $rest),
	      "\n");
    }
    $file_done_p{$file_name}++;
}

### Main code.

# print(join("\n", @prefix_addresses, keys(%address_p)), "\n");
my $current_file_name = "$log_directory/current";
if (! -r $current_file_name) {
    die "$0:  '$log_directory' is unreadable or not a djbdns log directory";
}
elsif ($current_p) {
    maybe_do_file($current_file_name);
}
else {
    my ($dev, $inode) = stat($current_file_name);
    while (1) {
	opendir(DIR, $log_directory) or die;
	for my $file (sort(readdir(DIR))) {
	    my $full_name = "$log_directory/$file";
	    maybe_do_file($full_name)
		if $file =~ /^\@/;
	}
	# Wait for $current_file_name to be rolled into the set of old files.
	# [Using fam at this point would be more elegant, but the cost of
	# polling this way is slight.  -- rgr, 3-May-17.]
	($dev, my $new_inode) = stat($current_file_name);
	while ($inode == $new_inode) {
	    sleep($delay);
	    ($dev, $new_inode) = stat($current_file_name);
	}
	$inode = $new_inode;
    }
}
