################################################################################
#
# Minimal IPv4 netblock representation, for testing which addresses are local.
#
# [created.  -- rgr, 16-Feb-21.]
#

package Net::Block;

BEGIN {
    no strict 'refs';
    for my $method (qw{netmask_bits netmask_octets host_octets}) {
	my $field = '_' . $method;
	my $full_method_name = __PACKAGE__.'::'.$method;
	*$full_method_name = sub {
	    my $self = shift;
	    @_ ? ($self->{$field} = shift) : $self->{$field};
	}
    }
}    

sub new {
    my $class = shift;

    my $self = bless({}, $class);
    while (@_) {
	my $method = shift;
	my $argument = shift;
	$self->$method($argument)
	    if $self->can($method);
    }
    $self;
}

sub cidr_string {
    my ($self) = @_;

    return join('.', @{$self->host_octets}) . '/' . $self->netmask_bits;
}

sub parse {
    my ($class, $string) = @_;

    my ($octets, $n_bits) = split(/\//, $string, 2);
    my $host_octets = [ split(/[.]/, $octets) ];
    if (! defined($n_bits)) {
	# Plain class-style address.
	$n_bits = 8 * scalar(@$host_octets);
	my $netmask_octets = [ (255) x scalar(@$host_octets) ];
	push(@$host_octets, 0), push(@$netmask_octets, 0)
	    while @$host_octets < 4;
	return
	    unless @$host_octets == 4;
	return $class->new(netmask_bits => $n_bits,
			   netmask_octets => $netmask_octets,
			   host_octets => $host_octets);
    }
    else {
	# CIDR style; we have to build the netmask ourself.
	push(@$host_octets, 0)
	    while @$host_octets < 4;
	my $netmask_octets = [ ];
	my $bits_left = $n_bits;
	my $idx = 0;	# octet array index.
	for my $host_octet (@$host_octets) {
	    my $net_mask;
	    if ($bits_left > 8) {
		# Full net mask.
		$net_mask =  255;
	    }
	    elsif ($bits_left == 0) {
		# Full host part.
		$net_mask = 0;
	    }
	    else {
		# Partial net/host.  It's easiest to make the host mask in the
		# low-order bits from the rest of the octet, and then take that
		# out of the full octet mask (which is (1 << 8) - 1).
		my $host_mask = (1 << (8 - $bits_left)) - 1;
		$net_mask =  255 - $host_mask;
	    }
	    # This "&=" removes host bits from $host_octets by side effect; it
	    # makes the address_contained_p code a bit cleaner.
	    $host_octet &= $net_mask;
	    push(@$netmask_octets, $net_mask);
	    # Set up for the next octet.
	    $idx++;
	    $bits_left -= 8;
	    $bits_left = 0
		if $bits_left < 0;
	}
	return $class->new(netmask_bits => $n_bits,
			   netmask_octets => $netmask_octets,
			   host_octets => $host_octets);
    }
}

sub address_contained_p {
    my ($self, $address) = @_;

    my $address_octets = [ split(/[.]/, $address) ];
    my $block_octets = $self->host_octets;
    my $block_mask = $self->netmask_octets;
    for my $i (0 .. 3) {
	my $mask = $block_mask->[$i];
	return 1
	    # If the mask is zero, we're into the host part.
	    unless $mask;
	return 0
	    unless ($address_octets->[$i] & $mask) == $block_octets->[$i];
    }
    return 1;
}

1;

__END__

=head1 Net::Block

Class for representing an IPv4 netblock.  This is really only useful
for testing which addresses are within the block; for anything
fancier, or for IPv6 support, you probably want C<Net::Netmask>; see
L<https://metacpan.org/pod/distribution/Net-Netmask/lib/Net/Netmask.pod>.

Instances can be instantiated with the C<new> class method by passing
it the C<host_octets>, C<netmask_bits>, and C<netmask_octets> slots as
keywords, but the values must all be consistent; no validation is done.
Far easier is to use the C<parse> class method, which takes a
partial dotted quad or CIDR spec string, and returns an instance, or
nothing if the string is malformed.

=head2 Accessors and methods

=head3 address_contained_p

Given a dotted-quad string, returns 1 if the address is within our
block, else 0.

=head3 cidr_string

Returns the CIDR string for the netblock, e.g. "192.168.57.0/24".

=head3 host_octets

Returns or sets an arrayref of host octets.

=head3 netmask_bits

Returns or sets the number of bits in the netmask.

=head3 netmask_octets

Returns or sets an arrayref of netmask octets.

=head3 new

Class method, given the C<host_octets>, C<netmask_bits>, and
C<netmask_octets> keywords, create and return a C<Net::Block>
instance.  All keywords should be given, because the block is not
valid unless all three of these slots are initialized, but no
validation is done by the slots or by the C<new> method.

=head3 parse

This class method is the preferred way of creating C<Net::Block>
instances.  Given a spec, an instance is created, initialized, and
returned if the spec can be parsed, else nothing is returned.

The C<parse> method understands both CIDR and partial dotted-quad
specifications for IPv4 addresses (though not IPv6), so both "10" and
"10.0.0.0/8" are equivalent, as are "192.168.57.0/24" and
"192.168.57".  For CIDR, the host bits are always masked out, so
"192.168.57.85/24" and "192.168.57.0/24" are also equivalent.

=cut
