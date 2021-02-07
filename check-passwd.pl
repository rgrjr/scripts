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

__END__

=head1 NAME

check-passwd.pl -- check (e.g.) /etc/passwd for duplicates

=head1 SYNOPSIS

    check-passwd.pl /etc/passwd

=head1 DESCRIPTION

Given a colon-delimited file of

	name:id:other:stuff:...

on the standard input or command line, such as C</etc/passwd> or
C</etc/group>, report duplicate names or IDs.  Do not try to supply
both C</etc/passwd> and C</etc/group> on the same invocation, or
you'll get lots of spurious duplications.

=head1 SEE ALSO

=over 4

=item L<passwd(5)>

=item L<group(5)>

=back

=head1 AUTHOR

Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>

=head1 COPYRIGHT

Copyright (C) 2018 by Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
