#!/usr/bin/perl

use strict;
use warnings;

use Test::More tests => 2 + 13*6 + 2 + 7*2 + 2*14;

BEGIN {
    use_ok('Backup::Entry');
    use_ok('Backup::DumpSet');
}

sub test_new {
    # Six tests per invocation.
    my ($raw_file, $prefix, $date, $level, $index, $catalog_p) = @_;

    my $e1 = Backup::Entry->new_from_file($raw_file);
    ok($e1, "parsed '$raw_file'");
    ok($e1->prefix eq $prefix, "prefix is '$prefix'");
    ok($e1->date eq $date, "date is '$date'");
    ok($e1->level == $level, "level is $level");
    ok($e1->index == $index, "index is $index");
    ok(! $e1->catalog_p == ! $catalog_p,
       ($catalog_p ? 'is' : 'not').' a catalog');
    return $e1;
}

my @entries
    = (test_new('home-20100628-l3.1.dar', qw(home 20100628 3 1 0)),
       test_new('home-20100626-l1.1.dar', qw(home 20100626 1 1 0)),
       test_new('home-20100626-l1.2.dar', qw(home 20100626 1 2 0)),
       test_new('home-20100626-l1.3.dar', qw(home 20100626 1 3 0)),
       test_new('home-20100625-l7.1.dar', qw(home 20100625 7 1 0)),
       test_new('home-20100624-l4.1.dar', qw(home 20100624 4 1 0)),
       test_new('home-20100623-l5.1.dar', qw(home 20100623 5 1 0)),
       test_new('home-20100622-l2.1.dar', qw(home 20100622 2 1 0)),
       test_new('home-20100621-l1.1.dar', qw(home 20100621 1 1 0)),
       test_new('home-20100612-l0.1.dar', qw(home 20100612 0 1 0)),
       test_new('home-20100612-l0.2.dar', qw(home 20100612 0 2 0)),
       test_new('home-20100612-l0.3.dar', qw(home 20100612 0 3 0)),
       test_new('home-20100612-l0-cat.1.dar', qw(home 20100612 0 1 1))
    );
ok(@entries == 13, "have 13 entries");

sub test_order {
    # Two tests per invocation.
    my ($idx1, $idx2, $cmp) = @_;

    my $entry1 = $entries[$idx1];
    my $entry2 = $entries[$idx2];
    my $base_name_1 = $entry1->base_name;
    my $base_name_2 = $entry2->base_name;
    ok($cmp == $entry1->entry_cmp($entry2),
       "$base_name_1 cmp $base_name_2 is $cmp");
    ok(-$cmp == $entry2->entry_cmp($entry1),
       "$base_name_2 cmp $base_name_1 is ".-$cmp);
}

test_order(0, 1, -1);
test_order(1, 2, -1);
test_order(2, 3, -1);
test_order(4, 5, -1);
test_order(0, 8, -1);
test_order(9, 8, 1);
test_order(9, 9, 0);

sub check_current {
    # 14 tests per invocation.
    my $set = shift;

    $set->mark_current_entries();
    my @current = $set->current_entries;
    ok(@current == 8, "have 8 current entries");
    my @current_p = qw(1 1 1 1 0 0 0 0 0 1 1 1 1);
    for my $idx (0..12) {
	my $entry = $entries[$idx];
	my $current_p = $current_p[$idx];
	ok(! $current_p == ! $entry->current_p,
	   join(' ', $entry->base_name,
		$current_p ? 'is' : 'is not',
		'current'));
    }
}

# Create a dump set with these.
my $set = Backup::DumpSet->new(prefix => 'home');
ok($set->prefix eq 'home', "prefix set to 'home'");
for my $entry (@entries) {
    $set->add_dump_entry($entry);
}
$set->mark_current_entries();
check_current($set);

# Create a new dump set with a permutation (after resetting).
for my $entry (@entries) {
    $entry->current_p(0);
}
my $set2 = Backup::DumpSet->new(prefix => 'home');
for my $idx (qw(0 11 3 1 10 5 9 7 12 2 4 6 8)) {
    $set2->add_dump_entry($entries[$idx]);
}
check_current($set2);
