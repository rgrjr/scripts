#!/usr/bin/perl -w
#
# Given two different lists of RPM versions, report version differences.
# $Id$

use strict;
use Getopt::Long;
use Pod::Usage;
# use Data::Dumper;
require 'rpm.pm';

my $revision = '$Revision$ ';
our $VERSION = $revision =~ /([\d.]+)/ && $1;
my $ID = '$Id$ ';

# Command-line option variables.
my $verbose_p = 0;
my $usage = 0;
my $help = 0;
my $man = 0;
my @rpm_dirs;

### Process command-line arguments.

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose+' => \$verbose_p, 
	   'install-from=s' => sub { push(@rpm_dirs, $_[1]); })
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

warn "$0 version $VERSION:  $ID\n"
    if $verbose_p;

my ($file1, $file2) = @ARGV;
$file1 ||= "rpm -qa |";
$file2 ||= '-';

### Main program.

my $rpms1 = parse_installed_rpms($file1);
my $rpms2 = parse_installed_rpms($file2);
die
    unless %$rpms1 && %$rpms2;

my @to_be_removed;

for my $package_name (sort(keys(%$rpms1))) {
    my $rpm1 = $rpms1->{$package_name};
    my $rpm2 = $rpms2->{$package_name};
    if (! $rpm2) {
	push(@to_be_removed, $rpm1);
    }
    else {
	my ($pkg1, $v1, $r1) = @$rpm1;
	my ($pkg2, $v2, $r2) = @$rpm2;
	my $action = 'ok';
	if ($v1 ne $v2) {
	    $action = 'version';
	}
	elsif ($r1 < $r2) {
	    $action = 'upgrade';
	}
	elsif ($r1 > $r2) {
	    $action = 'downgrade';
	}
	print(join("\t", $pkg1, $v1, $r1, $action, $v2, $r2), "\n")
	    if $action ne 'ok';
    }
}
for my $rpm1 (@to_be_removed) {
    print(join("\t", @$rpm1, 'remove'), "\n");
}
my @rpms_to_install;
for my $package_name (sort(keys(%$rpms2))) {
    if (! exists($rpms1->{$package_name})) {
	my $rpm2 = $rpms2->{$package_name};
	my ($pkg2, $v2, $r2) = @$rpm2;
	print(join("\t", $pkg2, '', '', 'install', $v2, $r2), "\n");
	my $rpm_file_name = "$pkg2-$v2-$r2.i386.rpm";
	my $found_p;
	for my $dir (@rpm_dirs) {
	    my $file = "$dir/$rpm_file_name";
	    $found_p = $file, last
		if -r $file;
	}
	if ($found_p) {
	    push(@rpms_to_install, $found_p);
	}
	elsif ($verbose_p) {
	    warn "[couldn't find rpm for '$rpm_file_name']\n";
	}
    }
}
if (@rpms_to_install) {
    warn(join(' ', 'rpm -ivh', @rpms_to_install), "\n");
    my $result = system('rpm', '-ivh', @rpms_to_install);
    exit($result >> 8);
}
