#!/usr/bin/perl -w
#
# [created.  -- rgr, 20-Sep-03.]
#

use strict;

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

sub parse_available_rpms {
    my $package_to_data = {};
    while (<>) {
	next
	    unless /^ *-rw/;
	my @words = split(' ');
	my $file = pop(@words);
	my ($package_name, $version, $release, $dot_foo)
	    = parse_package_full_name($file);
	next
	    unless $dot_foo && $dot_foo eq 'i586.rpm';
	$package_to_data->{$package_name}
	    = [$package_name, $version, $release, $file];
    }
    $package_to_data;
}

sub parse_installed_rpms {
    my $package_to_data = {};
    open(IN, "rpm -qa |") || die;
    my $line;
    while (defined($line = <IN>)) {
	chomp($line);
	my ($package_name, $version, $release, $dot_foo)
	    = parse_package_full_name($line);
	$package_to_data->{$package_name}
	    = [$package_name, $version, $release, 'installed'];
    }
    close(IN);
    $package_to_data;
}

my $installed = parse_installed_rpms();
my $available = parse_available_rpms();

for my $package_name (sort(keys(%$installed))) {
    my $inst = $installed->{$package_name};
    my $avail = $available->{$package_name};
    if ($avail && ($avail->[1] ne $inst->[1]
		   || $avail->[2] ne $inst->[2])) {
	print(join("\t", @$inst, @$avail), "\n");
    }
}
