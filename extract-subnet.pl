#!/usr/local/bin/perl
#
#    Given an interface, extract and print the network address in CIDR format,
# e.g. "192.168.1.0/24".  If no interface is specified, the first one reported
# by ifconfig is used.  This is pretty simple; most of the work is involved in
# turning the address and mask into subnet/bits format.
#
#    Modification history:
#
# created.  -- rgr, 4-Oct-01.
#

open(IN, "ifconfig $ARGV[0] |") || die;
while (defined($line = <IN>)) {
    if ($line =~ /inet addr: *([\d.]+) .* Mask: *([\d.]+)/) {
	$addr = $1; $mask = $2;
	@addr_octets = split(/\./, $addr);
	@mask_octets = split(/\./, $mask);
	$n_bits = 0;
	for ($i = 0; $i < 4; $i++) {
	    $mask_bits = 0+$mask_octets[$i];
	    $network[$i] = $addr_octets[$i] & $mask_bits;
	    # print "$network[$i] = $addr_octets[$i] & $mask_bits;\n";
	    while ($mask_bits) {
		$n_bits++ if $mask_bits & 1;
		$mask_bits >>= 1;
	    }
	}
	last;
    }
}
die "Couldn't find address for '$ARGV[0]'.\nDied "
    unless @network;
print (join('.', @network), "/$n_bits\n");
