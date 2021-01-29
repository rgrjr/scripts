### Configuration for backup objects.
#
# [created.  -- rgr, 11-Mar-11.]
#

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

	# Always include partitions with max-*-retention values.
	if ($self->find_option('max-even-retention', $mp, 0)
	    || $self->find_option('max-odd-retention', $mp, 0)) {
	    push(@$partitions_to_clean, $partition);
	    next;
	}

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

__END__

=head1 Backup::Config

Backup configuration object.  This object is used to parse, store, and
retrieve the information from a F<backup.conf> file.

=head2 Configuration file format

This is described more fully by the C<clean-backups.pl> script, which
(so far) is the heaviest user of configuration information.

Configuration files have a "stanza" for each partition.  For example:

    # Note that this must be the mount point here.
    [scorpio:/scratch4]
    clean = home, src
    min-free-space = 5

Comments (starting with "#") and blank lines are ignored, keywords and
values appear one per line and are separated by "=", and whitespace is
ignored except when internal to a partition name, keyword, or value.

Partitions are named by the host name followed by a colon and the
mount point without a trailing "/" (e.g. "scorpio:/scratch4" in the
example above).  The host name defaults to the current host, which is
only appropriate for a single-system configuration file.  The
partition must be named by the mount point and not the device name
(which might be something like "/dev/sda4").

The only exception is that a "default" partition may be given
keyword/value pairs that apply for all partitions unless overridden.
Keyword/value pairs appearing before the first partition are also
included in the "default" partition.  All partitions other than
"default" must start with a "/".

When looking for a value, we search the specific partition first, then
the "default" partition (if any), and then use the global default.

=head2 Accessors and methods

=head3 config_file

Returns or sets the configuration file name.  This is normally set by
C<read_from_file>.

=head3 fail_p

Returns or sets a boolean that tells whether C<clean-backups.pl>
failed to make its target of free disk space.

=head3 find_option

Given an option name, a preferred partition, and a last-ditch default
value, look up an option in our C<stanza_hashes>.
The partition parameter may be a C<Backup::Partition>, in which case we
use its C<host_colon_mount> as the partition.  Otherwise,
if partition is not "default" and has no colon, we prefix our host name
and a colon to the partition.

Given the defaulted partition, we look for a stanza for that
partition; if that produces a defined value, we return it.  Otherwise,
we look for a "host:" stanza; if that produces a defined value, we
return that.  Otherwise, we see if the "default" stanza defines a
value, and use that if so.  And if all else fails, we return the
passed last-ditch default value.

=head3 find_partitions_to_clean

For all known partitions (see L<Backup::Partition/find_partitions>,
return an arrayref of C<Backup::Partition> objects that (a) have a
"clean" option and (b) either have a "max-even-retention" or
"max-odd-retention" option or are below the "min-free-space"
threshold.  These are the ones that C<clean-backups.pl> needs to look
at.

=head3 find_prefix

Given a mount point, return its "prefix" option value, or if it has
none, return its last pathname component.  [This won't work for a
C<Backup::Partition> object if it doesn't have the option defined.  It
should also disable search for a "default" prefix, which doesn't make
sense.  -- rgr, 28-Jan-21.]

=head3 find_search_roots

Given an optional partition (object or name), figure out where to
search for backups, and return a list (not an arrayref!).  This works
by looking for the "search-roots" option of the partition object,
which is expected to be a comma-separated list of absolute pathnames.

Failing that, we look for all possible directories of the form
F<"/scratch$suffix/backups"> where C<$suffix> can be a a digit or the
string ".old", with the whole thing optionally preceded by "/alt",
"/old", or "/new" (since this is where I have been known to hide
backups).

=head3 host_name

Returns or sets the local host name.  This is expected to be set by
the C<new> method from the output of the C<hostname> program, which is
the simple (non-domain-qualified) name of the computer on which the
code is currently running.

=head3 local_file_p

Given a file name, return false if it starts with "host:" where "host"
does not match our C<host_name>, else return the file name without any
"host:" prefix.

=head3 local_partition_p

Given a C<Backup::Partition> object, return true if the partition's
C<host_name> matches our C<host_name>.

=head3 new

Initialize our C<host_name> and read a configuration file if we can
find one, possibly shifting one off the front of C<@ARGV> if the first
one is "--config" or starts with "--config=", else defaulting to
F<~/.backup.conf> or F</etc/backup.conf>, whichever is found first.
Returns the new C<Backup::Config> instance.

=head3 read_from_file

Given a file name, read and initialize the configuration from the
file.  This sets the C<config_file> and C<stanza_hashes> slots.
C<read_from_file> is usually called from the C<new> method.

=head3 sort_dumps_by_partition

Given a hashref mapping each prefix to a C<Backup::DumpSet> instance
and an arrayref of local C<Backup::Partition> objects, file each dump
under its corresponding partition into the C<dumps_from_level> slot.
After sorting, this slot will contain an arrayref with two arrayrefs,
the first with C<Backup::Dump> instances for odd daily dumps, the
second with C<Backup::Dump> instances for even daily dumps.

=head3 stanza_hashes

Returns or sets a hashref of option hashrefs, keyed on host/partition
names, e.g. "scorpio:/scratch4", except one of them is usually called
"default".  This is initialized by L</read_from_file> and queried by
L</find_option>.

=head3 test_p

Returns or sets a boolean that controls whether the user wants to skip
the actual operation and just go through the motions.

=head3 verbose_p

Returns or sets an integer that controls how much extra information
the user wants.  The default is C<undef>, so code must take care how
it tests the value.

=cut
