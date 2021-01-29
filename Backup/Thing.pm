### Base class for backup objects.
#
# [created.  -- rgr, 3-Mar-08.]
#

package Backup::Thing;

use strict;
use warnings;

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

sub make_class_slots {
    my ($class, @slot_names) = @_;

    no strict 'refs';
    for my $method (@slot_names) {
	my $field = '_' . $method;
	my $full_method_name = $class.'::'.$method;
	*$full_method_name = sub {
	    my $self = shift;
	    @_ ? ($self->{$field} = shift) : $self->{$field};
	}
    }
}    

1;

__END__

=head1 Backup::Thing

Base class for backup objects.  This exists mostly to define and
initialize instance slots.

=head2 Accessors and methods

=head3 make_class_slots

Class method that builds slot accessors given slot names as the method
arguments.  Each accessor method retrieves the value if given no
arguments, else sets the value to the first argument.

=head3 new

Class method that builds an instance and initializes its slots.  After
creating and blessing an empty instance, the remaining arguments are
taken as alternate keyword/value pairs, and are processed in
left-to-right order.  If the instance handles the keyword as a
messages, it is passed the value as an argument, which normally sets a
slot.  But the method need not be a slot accessor, and the C<new>
method does nothing if the keyword is not handled, so that extra
values can be used by subclass methods.  Finally, the new instance is
returned.

=cut
