#!/usr/bin/perl -w
#
# Given a directory of RPMs, decide which ones to install.
#
# [created.  -- rgr, 30-Dec-03.]
#
# $Id$

use strict;
use Getopt::Long;
use Pod::Usage;
use Data::Dumper;
require 'rpm.pm';

my $revision = '$Revision$ ';
our $VERSION = $revision =~ /([\d.]+)/ && $1;
my $ID = '$Id$ ';

# Command-line option variables.
my $verbose_p = 0;
my $usage = 0;
my $help = 0;
my $man = 0;
my $test_p = 0;
my %system_types_to_install = ();
my $rpm_program_name = 'rpm';
my $upgrade_options = '-Uvh';
my $install_options = '-ivh';

### Process command-line arguments.

GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'verbose+' => \$verbose_p, 'test!' => \$test_p,
	   'system=s' => sub { $system_types_to_install{$_[1]}++; })
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;

$system_types_to_install{'i386'}++
    unless %system_types_to_install;

warn "$0 version $VERSION:  $ID\n"
    if $verbose_p;

### Main program.

my %rpms_to_install;

sub process_rpm_file {
    # Given an RPM file name, decide whether we need to install it.
    my $file = shift;

    my $new_package = new rgrjr::RPM(file_name => $file);
    my $package_name = $new_package->name;
    my $installed = as_installed rgrjr::RPM($package_name);
    my $install_p = '';
    if (! $new_package->newer_than($rpms_to_install{$package_name})) {
	# Oops; we've already found a newer RPM file.
    }
    elsif (! defined($installed->version)) {
	$install_p = 'install';
    }
    elsif ($new_package->newer_than($installed)) {
	# [bug: need to check for upgrades.  -- rgr, 30-Dec-03.]
	warn("[got installed version '", $installed->version,
	     "' release ", $installed->release, " for '$package_name'.]\n");
	$install_p = 'upgrade';
    }
    $new_package->action($install_p);
    $rpms_to_install{$package_name} = $new_package
	if $install_p;
    $install_p;
}

unshift(@ARGV, '.')
    unless @ARGV;
for my $arg (@ARGV) {
    if (-d $arg) {
	# canonicalize directory name.
	$arg =~ s@/\.?$@@;
	opendir(DIR, $arg) || die;
	my $file;
	while (defined($file = readdir(DIR))) {
	    process_rpm_file("$arg/$file")
		if ($file =~ /\.([^.]+)\.rpm$/
		    && $system_types_to_install{$1});
	}
	closedir(DIR);
    }
    elsif (-r $arg) {
	process_rpm_file($arg);
    }
    else {
	warn "$0:  Unknown argument '$arg'; ignoring.\n";
    }
}

# Disposition time.
my @install_files;
my @upgrade_files;
for my $rpm (values(%rpms_to_install)) {
    push(@install_files, $rpm->file_name)
	if $rpm->action eq 'install';
    push(@upgrade_files, $rpm->file_name)
	if $rpm->action eq 'upgrade';
}
my $result = 0;
if (@upgrade_files) {
    warn(join(' ', $rpm_program_name, $upgrade_options, @upgrade_files), "\n");
    $result = system($rpm_program_name, $upgrade_options, @upgrade_files)
	unless $test_p;
    exit($result >> 8)
	if $result;
}
if (@install_files) {
    warn(join(' ', $rpm_program_name, $install_options, @install_files), "\n");
    $result = system($rpm_program_name, $install_options, @install_files)
	unless $test_p;
    exit($result >> 8)
	if $result;
}

package rgrjr::RPM;

# define instance accessors.
sub BEGIN {
  no strict 'refs';
  for my $method (qw(name version release action)) {
    my $field = '_' . $method;
    *$method = sub {
      my $self = shift;
      @_ ? ($self->{$field} = shift, $self) : $self->{$field};
    }
  }
}

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

sub file_name {
    my $self = shift;

    return $self->{_file_name}
        unless @_;
    my $file_name = shift;
    ($self->{_name}, $self->{_version}, $self->{_release})
	= main::parse_package_full_name($file_name);
    $self->{_name} =~ s@.*/@@;
    $self->{_file_name} = $file_name;
    $self;
}

sub as_installed {
    my $self = shift;

    my $package_name = (@_ ? shift : $self->name) or die;
    $self = $self->new(@_)
	unless ref($self);
    my $installed_info = `rpm -q $package_name 2>&1`;
    chomp($installed_info);
    $installed_info = ''
	if $installed_info =~ /is not installed/;
    # warn "[got installed '$installed_info' for '$package_name'.]\n";
    ($self->{_name}, $self->{_version}, $self->{_release})
	= main::parse_package_full_name($installed_info)
	    if $installed_info;
    $self;
}

sub _compare_versions {
    # like cmp, but also returns undef if the version numbering is ambiguous.
    my ($v1, $v2, $i) = @_;

    $i ||= 0;
    warn("[_compare_versions([", join(', ', @$v1), "], [",
	 join(', ', @$v2), "], $i):\n")
	if 0;
    if ($i >= @$v1) {
	($i >= @$v2 ? 0 : -1);
    }
    elsif ($i > @$v2) {
	1;
    }
    elsif ($v1->[$i] eq $v2->[$i]) {
	_compare_versions($v1, $v2, $i+1);
    }
    elsif ($v1->[$i] =~ /\D/ || $v2->[$i] =~ /\D/) {
	# non-digits means we can't compare them in a relative way.
	undef;
    }
    else {
	$v1->[$i] <=> $v2->[$i];
    }
}

sub newer_than {
    my ($self, $other_package) = @_;

    return 1
	if ! $other_package;
    my $other_version = $other_package->version;
    return 1
	# this means not installed.
	if ! defined($other_version);
    my $cmp = _compare_versions([split(/\./, $self->version)],
				[split(/\./, $other_version)]);
    warn "[got '$cmp' for ", $self->version, " vs. $other_version.]\n"
	if 0;
    # note that this preserves the distinction between undef and 0.
    (! $cmp ? $cmp : $cmp > 0);
}