### Class for representing partitions used to store backups.
#
# [created.  -- rgr, 14-Mar-11.]
#

package Backup::Partition;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Partition->make_class_slots
	(qw(device_number device_name host_name mount_point
            total_blocks used_blocks avail_blocks use_pct
            dumps_from_level prefixes));
}

sub host_colon_mount {
    my $self = shift;

    join(':', $self->host_name, $self->mount_point);
}

sub contains_file_p {
    # Must have a file name without a "host:" prefix.
    my ($self, $file_name) = @_;

    my $mount_point = $self->mount_point;
    return 1
	if $file_name eq $mount_point;
    my $len = length($mount_point);
    return
	unless length($file_name) > $len+1;
    return substr($file_name, 0, $len+1) eq "$mount_point/";
}

sub find_partitions {
    my ($class, %options) = @_;
    my $max_free_blocks = $options{max_free_blocks};
    my $partition = $options{partition};

    # Figure out how to get the df listing.
    my $command = 'df';
    # [this must be the same as Backup::Config::new.  -- rgr, 24-Mar-11.]
    chomp(my $local_host = `hostname`);
    my $host;
    if ($partition) {
	my $spec;
	($host, $spec) = split(/:/, $partition);
	if (defined($spec)) {
	    # [shell quoting is probably incomplete.  -- rgr, 24-Mar-11.]
	    $command = qq{ssh '$host' "df '$spec'"};
	}
	else {
	    undef($host);
	    $command = qq{df '$partition'};
	}
    }
    if (! $host) {
	$host = $local_host;
    }
    open(my $in, "$command |")
	or die("Bug:  Can't open pipe from '$command':  $!");

    # Find free spaces.
    my @partitions;
    <$in>;	# ignore heading.
    my $line = <$in>;
    my $next;
    while ($line) {
	$next = <$in>;
	while ($next && $next =~ /^\s/) {
	    # Continuation line.
	    $line .= $next;
	    $next = <$in>;
	}
	my ($device, $total_blocks, $used_blocks, $avail_blocks,
	    $use_pct, $mount_point) = split(' ', $line);
	next
	    # Don't include NFS mounts.
	    if $device =~ /:/;
	if ($device && $mount_point
	        && (! $max_free_blocks || $avail_blocks < $max_free_blocks)) {
	    my $new_partition
		= $class->new(device_name => $device,
			      host_name => $host,
			      mount_point => $mount_point,
			      total_blocks => $total_blocks,
			      used_blocks => $used_blocks,
			      avail_blocks => $avail_blocks,
			      use_pct => $use_pct);
	    push(@partitions, $new_partition);
	    if ($host eq $local_host) {
		# Fill in the device number for a local host.
		my ($dev) = stat($mount_point);
		$new_partition->device_number($dev);
	    }
	    warn($mount_point, " device $device has ", $avail_blocks,
		 " out of ", $total_blocks, " available ($use_pct).\n")
		if 0;
	}
    }
    continue {
	$line = $next;
    }
    return @partitions;
}

sub clean_partition {
    my ($self, $config) = @_;

    # Get the daily dumps for our mount point.
    my $mount_point = $self->mount_point;
    my $verbose_p = $config->verbose_p;
    $verbose_p = $config->find_option('verbose', $mount_point, 0)
	if ! $verbose_p;
    my $test_p = $config->test_p;
    $test_p = $config->find_option('test', $mount_point, 0)
	if ! $test_p;
    my $dumps_from_level = $self->dumps_from_level;
    if (! $dumps_from_level) {
	warn "$0:  Partition $mount_point has no daily dumps.\n"
	    if $verbose_p;
	return;
    }
    my $available = $self->avail_blocks;
    warn("Checking for excess backups on $mount_point, $available blocks free",
	 ($test_p ? ' (test)' : ''), ".\n")
	if $verbose_p;

    # Find our retention limits.
    my $min_odd_days
	= $config->find_option('min-odd-retention', $mount_point, 30);
    undef($min_odd_days)
	if $min_odd_days && $min_odd_days !~ /^\d+$/;
    my $min_even_days
	= $config->find_option('min-even-retention', $mount_point, 90);
    undef($min_even_days)
	if $min_even_days && $min_even_days !~ /^\d+$/;
    my $max_odd_days
	= $config->find_option('max-odd-retention', $mount_point, 0);
    undef($max_odd_days)
	if $max_odd_days && $max_odd_days !~ /^\d+$/;
    my $max_even_days
	= $config->find_option('max-even-retention', $mount_point, 0);
    undef($max_even_days)
	if $max_even_days && $max_even_days !~ /^\d+$/;
    return
	# Infinite retention of everything means nothing to do.
	unless ($min_odd_days || $min_even_days
		|| $max_odd_days || $max_even_days);

    # Find our minimum free space (in blocks, to avoid overflow).
    my $min_free_GiB
	= $config->find_option('min-free-space', $mount_point, 10);
    my $min_free_blocks = $min_free_GiB * 1024 * 1024;

    my ($n_deletions, $n_slices) = (0, 0);
    my $delete_dump = sub {
	# Delete all slices of this dump on the current partition, generating
	# verbose messages, updating $available blocks and other statistics.
	my ($dump) = @_;

	$n_deletions++;
	warn "    delete dump ", $dump->base_name, "\n"
	    if $verbose_p > 1;
	for my $slice (@{$dump->slices}) {
	    my $file = $slice->file;
	    next
		if (substr($file, 0, length($mount_point)+1)
		    ne "$mount_point/");
	    $n_slices++;
	    warn "      delete slice $file\n"
		if $verbose_p > 2;
	    unlink($file)
		unless $test_p;
	    $available += int($slice->size / 1024);
	}
    };

    # Perform deletions above the maximums.
    my @max_days_from_level_class = ($max_odd_days, $max_even_days);
    for my $level_class (0 .. @$dumps_from_level-1) {
	my $max_days = $max_days_from_level_class[$level_class];
	if (! $max_days) {
	    warn("  No max_days for $level_class.\n")
		if $verbose_p > 2;
	    next;
	}
	my @dumps = sort { $a->date cmp $b->date;
	} @{$dumps_from_level->[$level_class]};
	next
	    unless @dumps;
	warn("  Partition $mount_point ", ($level_class ? 'even' : 'odd'),
	     " dailies, ", scalar(@dumps),
	     " total dumps, max days $max_days.\n")
	    if $verbose_p > 1;
	while (@dumps) {
	    # Loop invariant:  The first element of @dumps is the current
	    # candidate, so we must either shift it off if we delete it, or
	    # exit the loop if we keep it.
	    my $dump = $dumps[0];
	    last
		if $dump->current_p;

	    # See whether we're too old.  If not, just quit, since the
	    # remaining dumps in this level class will be even newer.
	    last
		if $dump->age_in_days() <= $max_days;
	    shift(@dumps);
	    $delete_dump->($dump);
	}
	# Update $dumps_from_level with the remainder.
	$dumps_from_level->[$level_class] = [ @dumps ];
    }

    # Perform deletions on the remainder down to the minimums to make space.
    my @min_days_from_level_class = ($min_odd_days, $min_even_days);
    for my $level_class (0 .. @$dumps_from_level-1) {
	last
	    if $available > $min_free_blocks;
	my $min_days = $min_days_from_level_class[$level_class];
	if (! $min_days) {
	    warn("  No min_days for $level_class.\n")
		if $verbose_p > 2;
	    next;
	}
	my $dumps = $dumps_from_level->[$level_class];
	next
	    unless $dumps;
	warn("  Partition $mount_point ", ($level_class ? 'even' : 'odd'),
	     " dailies, ", scalar(@$dumps),
	     " total dumps, min days $min_days, $available blocks free.\n")
	    if $verbose_p > 1;
	# Delete in the reverse order used by show-backups, but regardless of
	# prefix.
	for my $dump (sort { $a->date cmp $b->date || $a->level <=> $b->level;
		      } @$dumps) {
	    warn("    Considering ", $dump->base_name, ', age ',
		 $dump->age_in_days, ".\n")
		if $verbose_p > 2;
	    last
		if $available > $min_free_blocks;
	    next
		if $dump->current_p;

	    # See whether we're still a keeper.  If so, just quit, since the
	    # remaining dumps in this level class will be even newer.
	    last
		if $dump->age_in_days() <= $min_days;
	    $delete_dump->($dump);
	}
    }

    # Wrap up.
    my $fail_p = $available < $min_free_blocks;
    warn(($fail_p ? "$0:  Failed to meet target for $mount_point:  " : '  '),
	 "Deleted $n_slices slices from $n_deletions dumps",
	 ", free space now $available blocks.\n")
	if $fail_p || ($n_deletions && $verbose_p);
    $config->fail_p(1)
	if $fail_p;
    $self->avail_blocks($available);
}

1;
