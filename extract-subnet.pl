#!/usr/bin/perl -w
#
#    Given an interface, extract and print the network address in CIDR format,
# e.g. "192.168.1.0/24".  This is pretty simple; most of the work is involved in
# turning the address and mask into subnet/bits format.
#
# [created.  -- rgr, 4-Oct-01.]
#

use strict;

my $iface = shift(@ARGV)
    || die("$0:  Must give an interface name, e.g. 'eth0', ",
	   "on the command line.\n");

open(IN, "ifconfig $iface |") || die;
my $line;
my @network;
my $n_bits = 0;
while (defined($line = <IN>)) {
    if ($line =~ /inet addr: *([\d.]+) .* Mask: *([\d.]+)/) {
	my $addr = $1; my $mask = $2;
	my @addr_octets = split(/\./, $addr);
	my @mask_octets = split(/\./, $mask);
	for my $i (0..3) {
	    my $mask_bits = 0+$mask_octets[$i];
	    $network[$i] = $addr_octets[$i] & $mask_bits;
	    # count the ones in this mask octet.
	    while ($mask_bits) {
		$n_bits++ if $mask_bits & 1;
		$mask_bits >>= 1;
	    }
	}
	last;
    }
}
die "Couldn't find address for '$iface'.\n"
    unless @network;
print (join('.', @network), "/$n_bits\n");
