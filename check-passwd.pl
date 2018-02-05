#!/usr/bin/perl -w
#
# Find duplicates by name or ID in /etc/passwd or /etc/group.
#
# [created.  -- rgr, 5-Feb-18.]
#

use strict;
use warnings;

# Read the input.
my (%names_from_id, %ids_from_name);
while (<>) {
    my ($name, $pass, $id) = split(':');
    push(@{$ids_from_name{$name}}, $id);
    push(@{$names_from_id{$id}}, $name);
}

# And find collisions.
for my $name (keys(%names_from_id)) {
    my $ids = $names_from_id{$name};
    print "$name is duplicated with ids ", join(', ', @$ids), ".\n"
	if @$ids > 1;
}
for my $id (keys(%names_from_id)) {
    my $names = $names_from_id{$id};
    print "$id is duplicated for ", join(', ', @$names), ".\n"
	if @$names > 1;
}
