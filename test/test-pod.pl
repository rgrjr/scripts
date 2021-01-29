#!/usr/bin/perl
#
# Check that all *.pl and *.pm files have Pod documentation.
#
# [created.  -- rgr, 28-Jan-21.]
#

use strict;
use warnings;

use Test::More;

# Run tests only if Test::Pod is installed.
eval 'use Test::Pod 1.00';
if ($@) {
    plan(skip_all => 'Test::Pod required for testing POD syntax.');
}

# Find all Pod files (all_pod_files is a little too indiscriminate).
my @sources;
{
    open(my $in, 'find . -type f |')
	or die "$0:  Failed to open pipe from find";
    while (<$in>) {
	chomp;
	push (@sources, $_)
	    if /[.]p[lm]$/;
    }
}

# Check 'em.
all_pod_files_ok(@sources);

__END__

=head1 NAME

test-pod.pl

=head1 SYNOPSIS

    perl test/test-pod.pl

=head1 DESCRIPTION

This script checks the syntax of all POD in the distribution, but
punts if C<Test::Pod> is not installed.

=cut
