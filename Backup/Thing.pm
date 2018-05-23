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
