#!/usr/bin/perl
#
# Extract fstab rows based on our current network configuration.
#
# [created.  -- rgr, 10-May-17.]
#

use strict;
use warnings;

use NetAddr::IP;

my $loopback = NetAddr::IP->new('127.0.0.0/8');
sub find_our_networks {
    # Return a list of NetAddr::IP objects describing the subnet for each
    # network address that belongs to an interface that is "up", as reported by
    # the "ip" command.
    my @networks;
    open(my $in, 'ip a show up |') or die "can't open pipe from ip:  $!";
    while (<$in>) {
	next
	    unless m@inet ([\d.]+/\d+) @;
	my $addr = NetAddr::IP->new($1);
	next
	    # Don't bother collecting loopback addresses.
	    if $addr->within($loopback);
	my $net = NetAddr::IP->new_no($addr->addr, $addr->mask);
	push(@networks, $net);
    }
    return @networks;
}

my @our_networks = find_our_networks();

my %host_on_our_network_p;
sub host_on_our_network_p {
    # Given a host name, use gethostbyname to resolve it to one or more
    # addresses, and return true if any of those addresses is on any of the
    # subnets that we can talk to directly.  The result is cached, in case we
    # need to ask for it again.
    my ($host) = @_;

    return $host_on_our_network_p{$host}
        if defined($host_on_our_network_p{$host});
    my $local_p = 0;
    my ($name, $aliases, $af, $len, @host_addresses) = gethostbyname($host);
    for my $raw_host_addr (@host_addresses) {
	my $host_addr = NetAddr::IP->new_from_aton($raw_host_addr);
	for my $our_net (@our_networks) {
	    $local_p++
		if $our_net->contains($host_addr);
	}
    }
    $host_on_our_network_p{$host} = $local_p;
    $host_on_our_network_p{$name} = $local_p;
    return $local_p;
}

### Main code.

while (<>) {
    next
	if /^\s*#/;
    my ($device, $mount_point, $fstype, $options) = split(' ');
    my ($host, $exported_fs) = split(':', $device);
    next
	# $exported_fs will be missing if $device has no ":".
	unless ($fstype =~ /nfs/ && $exported_fs
		&& $options =~ /noauto/);
    next
	if @our_networks && ! host_on_our_network_p($host);
    # If all network connections seem to be down, we must include all NFS
    # mounts for forced unmounting.
    warn("Found $fstype host '$host' for mount point '$mount_point'.\n");
    print(join(' ', $device, $mount_point, $fstype, $options), "\n");
}

__END__

=head1 NAME

find-net-mounts.pl -- extract fstab rows based on interfaces that are up

=head1 SYNOPSIS

    find-net-mounts.pl /etc/fstab

=head1 DESCRIPTION

Given a file in the format of F</etc/fstab>, either named on the
command line or on the standard input, this script extracts NFS mounts
that are expected to be reachable from one of the network interfaces
as currently configured, and spits them out on the standard output in
the somewhat condensed fstab format expected for C<$NET_MOUNTS> by
F</etc/NetworkManager/dispatcher.d/nfs>.  As a special case, all NFS
mounts are extracted if we have no interfaces with IPv4 addresses
assigned (not including loopback addresses); this causes all of them that
had been mounted to be unmounted.

In order for this to work, each such fstab entry must (a) be marked as
"noauto" (so the normal boot-time mounting doesn't happen), and (b)
have an NFS server host name that can be easily resolved.  While it is
theoretically possible to use a host name that cannot be found when
it's not on the network, that may cause DNS delays.  Accordingly, it
is probably most robust to have C</etc/hosts> entries for each host
named in F</etc/fstab>.

=cut
