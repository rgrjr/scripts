#!/usr/bin/perl

use strict;
use warnings;

### Subroutines

sub usage {
    print(@_, "\n")
	if @_;
    print("Usage:  $0 delta-file config-input-file > config-output-file\n");
    exit(1);
}

# Parse command-line args (such as they are).
my ($delta_file, $config_file) = @ARGV;
usage('Missing delta or config file.')
    unless $config_file;

# Process the delta file.
open(my $delta_in, '<', $delta_file)
    or die "$0:  Cannot read delta file '$delta_file':  $!";
my %text_from_option;
my $text_so_far = '';
while (<$delta_in>) {
    $text_so_far .= $_
	if $text_so_far || $_ ne "\n";
    if (/^\s*(\S+)\s*=/) {
	my $option_name = $1;
	$text_from_option{$option_name} = $text_so_far;
	$text_so_far = '';
    }
}

# Massage the configuration file.
open(my $config_in, '<', $config_file)
    or die "$0:  Cannot read delta file '$config_file':  $!";
$text_so_far = '';
while (<$config_in>) {
    $text_so_far .= $_;
    if (/^\s*(\S+)\s*=/) {
	my $option_name = $1;
	my $substitute_text = $text_from_option{$option_name};
	if (! $substitute_text) {
	    # Leave unchanged.
	    print $text_so_far;
	}
	elsif ($substitute_text eq 1) {
	    # Already substituted, so just ignore.
	}
	else {
	    # Substitute $text_so_far with $substitute_text.
	    print $substitute_text;
	    $text_from_option{$option_name} = 1;
	}
	$text_so_far = '';
    }
}

# Clear the pipe, and handle leftovers.
print $text_so_far;
for my $option_name (sort(keys(%text_from_option))) {
    my $substitute_text = $text_from_option{$option_name};
    print $substitute_text
	unless $substitute_text eq 1;
}

__END__

=head1 NAME

substitute-config.pl -- augment a "key=value" configuration file

=head1 SYNOPSIS

        substitute-config.pl delta-file config-input > config-output

=head1 DESCRIPTION

This script tweaks a "key=value" configuration file with options from
a smaller "delta" file.  The C<config-output> file contains all of the
options specified in the C<delta-file>, plus all options specified in
the C<config-input> file that are not overridden by the delta file.

=head1 BUGS

Options that are multiply defined (i.e. two or more "key=value" pairs
for the same key) are not supported:  Only the last one in the delta
file is used, and all values in C<config-input> are overridden.  (All
values that are not overridden in C<config-input> are passed through,
however.)

Multiple sections, e.g. "[foo]" headings, are not supported.

If you find any others, please let me know.

=head1 COPYRIGHT

Copyright (C) 2013 by Bob Rogers C<E<lt>rogers@rgrjr.dyndns.orgE<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=head1 AUTHOR

Bob Rogers E<lt>rogers@rgrjr.dyndns.org<gt>

=cut
