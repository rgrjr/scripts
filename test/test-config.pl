#!/usr/bin/perl

use strict;
use warnings;

use lib '.';	# so that we test the right thing.

use Test::More tests => 20;
use Backup::Config;

my $config = Backup::Config->new(config_file => '',
				 host_name => 'localhost');
$config->read_from_file(shift(@ARGV) || 'test/backup.conf');

my %expected_values_from_stanza
    = (default => { 'min-odd-retention' => '30',
		    'min-even-retention' => '60',
		    'min-free-space' => '10',
		    clean => 'not defined',
		    'search-roots' => q{/scratch2, /scratch3, /scratch4}},
       'localhost:' => { 'min-odd-retention' => '30',
			 'min-even-retention' => '60',
			 'min-free-space' => '5',
			 clean => 'not defined' },
       'localhost:/scratch2' => { 'min-odd-retention' => '30',
				  'min-even-retention' => '60',
				  'min-free-space' => '5',
				  'clean' => 'home, src' },
       'otherhost:/scratch3' => { 'min-odd-retention' => '30',
				  'min-even-retention' => '60',
				  'min-free-space' => '10',
				  'clean' => '*' });

## Check basic option inheritance.
for my $stanza (sort(keys(%expected_values_from_stanza))) {
    # Check find_option values.
    my $expected_values = $expected_values_from_stanza{$stanza};
    for my $option (sort(keys(%$expected_values))) {
	my $value = $config->find_option($option, $stanza, 'not defined');
	my $expected_value = $expected_values->{$option};
	ok($value eq $expected_value,
	   "$option value is $expected_value in $stanza");
    }
    # Check find_prefix.
    if ($stanza =~ m@.:/.@) {
	my $pfx = $stanza;
	$pfx =~ s{.*:/}{};
	ok($config->find_prefix($stanza) eq $pfx,
	   "got default prefix for $stanza");
    }
}

# Check search roots.
my @search_roots = $config->find_search_roots('/home');
is_deeply(\@search_roots, [ qw(/scratch2 /scratch3 /scratch4) ],
	  'got search roots from default');
