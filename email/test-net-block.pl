#!/usr/bin/perl

use strict;
use warnings;

use lib 'email';	# so that we test the right thing.

use Test::More tests => 22;

use_ok('Net::Block');

### Subroutine.

sub test_block {
    # Run 7 tests on the passed $block_string.
    my ($test_name, $block_string, $expected_bits, $cidr_string,
	$host_octets, $netmask_octets,
	$contained_host, $non_contained_host) = @_;

    my $block = Net::Block->parse($block_string);
    ok($block, "$test_name parsed")
	or die;
    ok($block->netmask_bits == $expected_bits,
       "$test_name has $expected_bits mask bits");
    is($block->cidr_string, $cidr_string,
       "$test_name CIDR string is right");
    is_deeply($block->netmask_octets, $netmask_octets,
	      "$test_name has the expected netmask octets");
    is_deeply($block->host_octets, $host_octets,
	      "$test_name has the expected host octets");
    ok($block->address_contained_p($contained_host),
       "$test_name $contained_host is a contained host");
    ok(! $block->address_contained_p($non_contained_host),
       "$test_name $non_contained_host is not a contained host");
}


### Main code.

## Make a localhost netblock.
test_block('localhost', 127, 8, '127.0.0.0/8',
	   [127, 0, 0, 0], [255, 0, 0, 0],
	   '127.0.0.1', '128.0.0.1');

## Make an ordinary class C netblock.
test_block('class C', '192.168.57', 24, '192.168.57.0/24',
	   [192, 168, 57, 0], [255, 255, 255, 0],
	   '192.168.57.28', '192.168.28.57');

## Make a CIDR netblock.
test_block('CIDR', '73.38.11.6/22', 22, '73.38.8.0/22',
	   [73, 38, 8, 0], [255, 255, 252, 0],
	   # Test two addresses in different class C networks from the original
	   # host, to test how parsing interacts with address_contained_p.
	   '73.38.10.14', '73.38.12.57');
