### Class for representing partitions used to store backups.
#
# [created.  -- rgr, 14-Mar-11.]
#
# $Id$

package Backup::Partition;

use strict;
use warnings;

use base qw(Backup::Thing);

# define instance accessors.
BEGIN {
    Backup::Partition->make_class_slots
	(qw(device_number device_name mount_point
            total_blocks used_blocks avail_blocks use_pct
            dumps_from_level prefixes));
}

sub find_partitions {
    my ($class, $max_free_blocks) = @_;

    # Find free spaces.
    my @partitions;
    open(my $in, 'df |')
	or die("Bug:  Can't open pipe from df:  $!");
    <$in>;	# ignore heading.
    my $line = <$in>;
    while ($line) {
	my $next = <$in>;
	while ($next && $next =~ /^\s/) {
	    # Continuation line.
	    $line .= $next;
	    $next = <$in>;
	}
	my ($device, $total_blocks, $used_blocks, $avail_blocks,
	    $use_pct, $mount_point) = split(' ', $line);
	my ($dev, $inode, $mode, $nlink, $uid, $gid, $rdev, $size,
	    $atime, $mtime, $ctime, $blksize, $blocks) = stat($mount_point);
	if ($dev && (! $max_free_blocks
		     || $avail_blocks < $max_free_blocks)) {
	    push(@partitions,
		 $class->new(device_name => $device,
			     device_number => $dev,
			     mount_point => $mount_point,
			     total_blocks => $total_blocks,
			     used_blocks => $used_blocks,
			     avail_blocks => $avail_blocks,
			     use_pct => $use_pct));
	    warn($mount_point, " dev $dev has ", $avail_blocks,
		 " out of ", $total_blocks, " available ($use_pct).\n")
		if 0;
	}
	$line = $next;
    }
    return @partitions;
}

sub clean_partition {
    my ($self, $config) = @_;
    require Time::Local;

    my $mount_point = $self->mount_point;
    my $verbose_p = $config->verbose_p;
    $verbose_p = $config->find_option('verbose', $mount_point, 0)
	if ! $verbose_p;
    my $test_p = $config->test_p;
    $test_p = $config->find_option('test', $mount_point, 0)
	if ! $test_p;
    my $dumps_from_level = $self->dumps_from_level;
    if (! $dumps_from_level) {
	warn "$0:  Partition $mount_point has no dumps?\n";
	return;
    }
    warn("Checking for excess backups on $mount_point",
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
    return
	# Infinite retention of everything means nothing to do.
	unless $min_odd_days || $min_even_days;
    my @min_days_from_level_class = ($min_odd_days, $min_even_days);

    # Find our minimum free space (in blocks, to avoid overflow).
    my $min_free_gigabytes
	= $config->find_option('min-free-space', $mount_point, 10);
    my $min_free_blocks = $min_free_gigabytes * 1024 * 1024;

    # Perform deletions.
    my $available = $self->avail_blocks;
    my ($n_deletions, $n_slices) = (0, 0);
    for my $level_class (0 .. @$dumps_from_level-1) {
	last
	    if $available > $min_free_blocks;
	my $dumps = $dumps_from_level->[$level_class];
	next
	    unless $dumps;
	warn("  Partition ", $self->mount_point,
	     ' ', ($level_class ? 'even' : 'odd'),
	     " dailies, ", scalar(@$dumps),
	     " total dumps, $available blocks free.\n")
	    if $verbose_p > 1;
	# Delete in chronological order, regardless of prefix.
	for my $dump (sort { $a->date cmp $b->date; } @$dumps) {
	    last
		if $available > $min_free_blocks;
	    next
		if $dump->current_p;

	    # See whether we're still a keeper.  If so, just quit, since the
	    # remaining dumps in this level class will be even newer.
	    my $class_min_days = $min_days_from_level_class[$level_class];
	    if ($class_min_days) {
		my $date = $dump->date;
		my ($year, $month, $dom) = unpack('A4A2A2', $date);
		my $time = Time::Local::timelocal(0, 0, 0,
						  $dom, $month-1, $year-1900);
		my $days_old = int((time-$time)/(24*3600));
		last
		    if $days_old <= $class_min_days;
	    }

	    # It's a goner.
	    $n_deletions++;
	    warn "    delete dump ", $dump->base_name, "\n"
		if $verbose_p > 1;
	    for my $slice (@{$dump->slices}) {
		$n_slices++;
		my $file = $slice->file;
		warn "      delete slice $file\n"
		    if $verbose_p > 2;
		unlink($file)
		    unless $test_p;
		$available += int($slice->size / 1024);
	    }
	}
    }
    warn("  Deleted $n_deletions dumps",
	 ($n_deletions == $n_slices ? '' : " with $n_slices slices"),
	 ", free space now $available blocks.\n")
	if $n_deletions && $verbose_p;
    $self->avail_blocks($available);
}

1;
