### Random RPM stuff.
#
# [created (split out of version-diffs.pl).  -- rgr, 30-Dec-03.]
#
# $Id$

### Subroutines.

sub parse_package_full_name {
    # May also be a file name.
    my $full_name = shift;

    my @components = split(/-/, $full_name);
    my ($package_name, $version, $release, $dot_foo);
    if (@components >= 3) {
	my $release_dot_foo = pop(@components);
	($release, $dot_foo) = split(/\./, $release_dot_foo, 2);
	$version = pop(@components);
	$package_name = join('-', @components);
    }
    ($package_name, $version, $release, $dot_foo);
}

sub parse_installed_rpms {
    my $file = shift;

    my $package_to_data = {};
    open(IN, $file) || die;
    my $line;
    while (defined($line = <IN>)) {
	chomp($line);
	my ($package_name, $version, $release, $dot_foo)
	    = parse_package_full_name($line);
	$package_to_data->{$package_name}
	    = [$package_name, $version, $release];
    }
    close(IN);
    $package_to_data;
}

1;
