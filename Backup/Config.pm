### Configuration for backup objects.
#
# [created.  -- rgr, 11-Mar-11.]
#
# $Id$

package Backup::Config;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Config->make_class_slots(qw(stanza_hashes config_name));
}

sub read_from_file {
    my ($self, $file_name) = @_;

    open(my $in, $file_name)
	or die "$0:  Cannot open '$file_name':  $!";
    my $stanza = 'default';
    $self->{_stanza_hashes} ||= { };
    while (<$in>) {
	if (/^\s*#/) {
	    # Comment.
	}
	elsif (/^\s*$/) {
	    # Empty.
	}
	elsif (/^\[\s*(.*)\s*?\]/) {
	    # New stanza.
	    $stanza = $1;
	}
	elsif (/^\s*([^=]*)=\s*(.*)/) {
	    my ($key, $value) = //;
	    $key =~ s/\s+$//;
	    $self->{_stanza_hashes}{$stanza}{$key} = $value;
	}
	else {
	    warn "$file_name:$.:  Unrecognized option format.\n";
	}
    }
}

sub find_option {
    my ($self, $option_name, $stanza, $default) = @_;
    $stanza ||= $self->config_name;

    my $result = $self->{_stanza_hashes}{$stanza}{$option_name};
    $result = $self->{_stanza_hashes}{'default'}{$option_name}
        unless defined($result);
    return $result
	if defined($result);
    return $default
	if @_ > 3;
    die "$0:  'Option '$option_name' is undefined in '$stanza'.\n";
}

sub find_prefix {
    # Find the backup name prefix for a given mount point.
    my ($self, $mount_point) = @_;

    my $value = $self->find_option('prefix', $mount_point, '');
    return $value
	if $value;
    # Default to the last pathname component.
    $value = $mount_point;
    $value =~ s@.*/@@;
    return $value;
}

sub find_search_roots {
    # Figure out where to search for backups.
    my ($self, $stanza) = @_;

    my $search_roots = $self->find_option('search-roots', $stanza, '');
    my @search_roots;
    if ($search_roots) {
	@search_roots = split(/[, ]+/, $search_roots);
    }
    else {
	# Traditional default.
	for my $base ('', '/alt', '/old', '/new') {
	    next
		if $base && ! -d $base;
	    for my $root (qw(scratch scratch2 scratch3 scratch4 scratch.old)) {
		my $dir = "$base/$root/backups";
		push (@search_roots, $dir)
		    if -d $dir;
	    }
	}
    }
    die "$0:  No search roots.\n"
	unless @search_roots;
    return @search_roots;
}

1;
