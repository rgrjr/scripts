#!/usr/bin/perl

use strict;
use warnings;

use lib '.';	# so that we test the right thing.

use Test::More tests => 137;

BEGIN {
    use_ok('Backup::Slice');
    use_ok('Backup::DumpSet');
}

### Subroutines.

sub test_dump_order {
    # Two tests per invocation.
    my ($dump1, $dump2, $cmp) = @_;

    my $file_stem_1 = $dump1->file_stem;
    my $file_stem_2 = $dump2->file_stem;
    ok($cmp == $dump1->entry_cmp($dump2),
       "dump $file_stem_1 cmp $file_stem_2 is $cmp");
    ok(-$cmp == $dump2->entry_cmp($dump1),
       "dump $file_stem_2 cmp $file_stem_1 is ".-$cmp);
}

sub test_slice_order {
    # Two tests per invocation.
    my ($entry1, $entry2, $cmp) = @_;

    my $base_name_1 = $entry1->base_name;
    my $base_name_2 = $entry2->base_name;
    ok($cmp == $entry1->entry_cmp($entry2),
       "slice $base_name_1 cmp $base_name_2 is $cmp");
    ok(-$cmp == $entry2->entry_cmp($entry1),
       "slice $base_name_2 cmp $base_name_1 is ".-$cmp);
}

sub check_current {
    # 9 tests per invocation.
    my $set = shift;

    $set->mark_current_dumps();
    my @current = $set->current_dumps;
    ok(@current == 3, "have 3 current entries");
    my @current_p = qw(1 1 0 0 0 0 0 1);
    for my $idx (0..@current_p-1) {
	my $dump = $set->dumps->[$idx];
	my $current_p = $current_p[$idx];
	ok(! $current_p == ! $dump->current_p,
	   join(' ', $dump->file_stem,
		$current_p ? 'is' : 'is not',
		'current'));
    }
}

### Main code.

my @specs
    = ([ qw(home-20100628-l3.1.dar 20100628 3 1 0) ],
       [ qw(home-20100626-l1.1.dar 20100626 1 1 0) ],
       [ qw(home-20100626-l1.2.dar 20100626 1 2 0) ],
       [ qw(home-20100626-l1.3.dar 20100626 1 3 0) ],
       [ qw(home-20100625-l7.1.dar 20100625 7 1 0) ],
       [ qw(home-20100624-l4.1.dar 20100624 4 1 0) ],
       [ qw(home-20100623-l5.1.dar 20100623 5 1 0) ],
       [ qw(home-20100622-l2.1.dar 20100622 2 1 0) ],
       [ qw(home-20100621-l1.1.dar 20100621 1 1 0) ],
       [ qw(home-20100612-l0.1.dar 20100612 0 1 0) ],
       [ qw(home-20100612-l0.2.dar 20100612 0 2 0) ],
       [ qw(home-20100612-l0.3.dar 20100612 0 3 0) ],
       [ qw(home-20100612-l0-cat.1.dar 20100612 0 1 1) ]
    );

# Create a dump set with these.
my $set = Backup::DumpSet->new(prefix => 'home');
ok($set->prefix eq 'home', "prefix set to 'home'");
for my $spec (@specs) {
    $set->add_slice(@$spec);
}
check_current($set);

# Check the order of dumps.
my $n_dumps = scalar(@{$set->dumps});
for my $i (0..$n_dumps-1) {
    for my $j ($i..$n_dumps-1) {
	test_dump_order($set->dumps->[$i], $set->dumps->[$j], $i <=> $j);
    }
}

# Check the order of slices within dumps.
for my $i (0..$n_dumps-1) {
    my $slices = $set->dumps->[$i]->slices;
    my $n_slices = @$slices;
    for my $j (0..$n_slices-1) {
	my $slice_j = $slices->[$j];
	for my $k ($j..$n_slices-1) {
	    my $slice_k = $slices->[$k];
	    my $result = ($slice_j->catalog_p
			  ? ($slice_k->catalog_p ? $j <=> $k : 1)
			  : ($slice_k->catalog_p ? -1 : $j <=> $k));
	    test_slice_order($slice_j, $slice_k, $result);
	}
    }
}

# Create a new dump set with a permutation.
my $set2 = Backup::DumpSet->new(prefix => 'home');
for my $idx (qw(0 11 3 1 10 5 9 7 12 2 4 6 8)) {
    $set2->add_slice(@{$specs[$idx]});
}
check_current($set2);

__END__

=head1 NAME

test-backup-classes.pl

=head1 SYNOPSIS

    perl test/test-backup-classes.pl

=head1 DESCRIPTION

Make sure that the backup classes work properly.

=cut
