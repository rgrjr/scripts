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
    Backup::Config->make_class_slots(qw(config_file verbose_p test_p fail_p
                                        host_name stanza_hashes));
}

sub new {
    # Also read a configuration file, if we were given or can find one.
    my $class = shift;

    # Initialize host name.
    my $self = $class->SUPER::new(@_);
    if (! $self->host_name) {
	chomp(my $host_name = `hostname`);
	$self->host_name($host_name);
    }

    # Look for a default config.
    my $config_file = $self->config_file;
    if (! defined($config_file)) {
	if (! @ARGV) {
	    # No options.
	}
	elsif ($ARGV[0] =~ /^--config=(.+)$/) {
	    $config_file = $1;
	    shift(@ARGV);
	}
	elsif ($ARGV[0] =~ /^--config$/) {
	    shift(@ARGV);
	    $config_file = shift(@ARGV);
	}
	if (! $config_file && -d $ENV{HOME}) {
	    my $default_conf = $ENV{HOME} . '/.backup.conf';
	    $config_file = $default_conf
		if -r $default_conf;
	}
	$config_file = '/etc/backup.conf'
	    if ! $config_file && -r '/etc/backup.conf';
    }
    $self->read_from_file($config_file)
	if $config_file;
    return $self;
}

sub read_from_file {
    my ($self, $file_name) = @_;

    open(my $in, $file_name)
	or die "$0:  Cannot open '$file_name':  $!";
    my $stanza = 'default';
    $self->{_stanza_hashes} ||= { };
    $self->config_file($file_name);
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
	    if (! ($stanza eq 'default' || $stanza =~ /:/)) {
		# Needs a host name prefix.
		warn "$file_name:$.: Funny partition name '$stanza'.\n"
		    if $stanza !~ m@^/@;
		$stanza = join(':', $self->host_name, $stanza);
	    }
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

    $stanza = $stanza->host_colon_mount
	# Assume this is a partition object.
	if ref($stanza);
    if ($stanza eq 'default') {
	# Try the default, and then the default default.
	my $result = $self->{_stanza_hashes}{'default'}{$option_name};
	return $result
	    if defined($result);
	return $default
	    if @_ > 3;
	die "$0:  'Option '$option_name' is undefined in '$stanza'.\n";
    }

    # Make sure the stanza name has a "host:".
    my $host_colon;
    if ($stanza !~ /:/) {
	$host_colon = $self->host_name . ':';
	$stanza = $host_colon . $stanza;
    }

    # Try the full name.
    my $result = $self->{_stanza_hashes}{$stanza}{$option_name};
    return $result
	if defined($result);

    # Try the "host:".
    $host_colon ||= ($stanza =~ m/^(.+:)/ && $1);
    if ($host_colon) {
	my $hash = ($self->{_stanza_hashes}{$host_colon}
		    || $self->{_stanza_hashes}{"$host_colon/"});
	$result = $hash && $hash->{$option_name};
	return $result
	    if defined($result);
    }
    return $self->find_option($option_name, 'default', $default);
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
    $stanza ||= $self->host_name . ':';

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
	    for my $suffix ('', 0 .. 9, '.old') {
		my $dir = "$base/scratch$suffix/backups";
		push (@search_roots, $dir)
		    if -d $dir;
	    }
	}
    }
    die "$0:  No search roots.\n"
	unless @search_roots;
    return @search_roots;
}

sub find_partitions_to_clean {
    # Find partitions that want cleaning.
    my ($self) = @_;
    require Backup::Partition;

    my @partitions = Backup::Partition->find_partitions();
    my $partitions_to_clean = [ ];
    for my $partition (@partitions) {
	my $mp = $partition->mount_point;
	my $clean = $self->find_option('clean', $mp, 0);
	next
	    unless $clean;
	$partition->prefixes([ split(/[, ]+/, $clean) ])
	    unless $clean eq '*';

	# Find our minimum free space (in blocks, to avoid overflow).
	my $min_free_gigabytes = $self->find_option('min-free-space', $mp, 10);
	my $min_free_blocks = $min_free_gigabytes * 1024 * 1024;
	my $available = $partition->avail_blocks;
	if ($available >= $min_free_blocks) {
	    my $verbose_p = ($self->verbose_p
			     || $self->find_option('verbose', $mp, 0));
	    warn("Skipping $mp, $available blocks free\n")
		if $verbose_p > 2;
	    next;
	}
	push(@$partitions_to_clean, $partition)
    }
    return $partitions_to_clean;
}

sub local_partition_p {
    my ($self, $partition) = @_;

    return $partition->host_name eq $self->host_name;
}

sub local_file_p {
    my ($self, $file_name) = @_;

    if ($file_name =~ /^([^:]+):([^:]+)$/) {
	my ($host, $local_part) = $file_name =~ //;
	return $local_part
	    if $host eq $self->host_name;
    }
    else {
	# An unqualified file name is always local.
	return $file_name;
    }
}

### Backup operations.

sub sort_dumps_by_partition {
    # Given a hashref of dumps and an arrayref of local partitions, file each
    # dump under its corresponding partition and even/odd level.
    my ($self, $dump_set_from_prefix, $partitions) = @_;

    my %partition_from_dev = map { $_->device_number => $_; } @$partitions;
    my %partition_wants_prefix_p;
    for my $partition (@$partitions) {
	my $prefixes = $partition->prefixes;
	if ($prefixes) {
	    my $dev = $partition->device_number;
	    if (! $dev) {
		# This matters for cleaning old backups.
		my $dev_name = $partition->device_name;
		my $mount_point = $partition->mount_point;
		die "Partition $mount_point ($dev_name) is not local";
	    }
	    for my $prefix (@$prefixes) {
		$partition_wants_prefix_p{$dev}{$prefix}++;
	    }
	}
    }
    for my $set (values(%$dump_set_from_prefix)) {
	$set->mark_current_dumps();
	for my $dump (reverse(@{$set->dumps})) {
	    # Lump the level into a level class.
	    my $level = $dump->level;
	    my $level_class = 0;
	    if ($level <= 1) {
		# Consolidated or full dump.
		next;
	    }
	    elsif ($level & 1) {
		# Odd daily dump.
		$level_class = 0;
	    }
	    else {
		# Even daily dump.
		$level_class = 1;
	    }

	    # File under all interesting partitions, and record slice sizes
	    # while we're at it.
	    my %partition_done_p;
	    for my $slice (@{$dump->slices}) {
		my $file = $slice->file;
		my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size)
		    = stat($file);
		$slice->size($size);
		my $partition = $partition_from_dev{$dev};
		next
		    unless $partition && ! $partition_done_p{$dev}++;
		# Find out if the partition wants us.
		next
		    if ($partition->prefixes
			&& ! $partition_wants_prefix_p{$dev}{$dump->prefix});
		push(@{$partition->{_dumps_from_level}[$level_class]}, $dump);
	    }
	}
    }
}

1;
