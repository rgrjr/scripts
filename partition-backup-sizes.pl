#!/usr/bin/perl -w
#
#    Report the number of file blocks (kilobytes) that need to be dumped at the
# given level (default is 9) for each mounted ext2 filesystem.
#
#    Modification history:
#
# created.  -- rgr, 24-Mar-01.
# print $mount_point last, so fields line up.  -- rgr, 31-Mar-01.
# changed default level to 9.  -- rgr, 27-Apr-01.
# skip the zip (and /scratch).  -- rgr, 9-Jun-01.
# put level in output.  -- rgr, 3-Mar-02.
# include ext3, don't test $ARGV[0] if it doesn't exist.  -- rgr, 11-May-03.
#

$level = (@ARGV && $ARGV[0] =~ /^\d$/ ? shift(@ARGV) : 9);
$filter_p = @ARGV > 0;
while (@ARGV) {
    $filter{shift(@ARGV)}++;
}

open(MTAB, '/etc/mtab') || die;
while (defined($line = <MTAB>)) {
    chomp($line);
    ($device, $mount_point, $fstype) = split(' ', $line);
    next if $fstype !~ /^ext/;
    next
	if $mount_point eq '/mnt/zip'
	    || $mount_point eq '/scratch';
    next
	if $filter_p
	    && ! (defined($filter{$mount_point})
		  || defined($filter{$device}));
    open(DUMP, "dump -S -$level $device 2>/dev/null |") || die;
    while (defined($line = <DUMP>)) {
	chomp($line);
	printf("%s\t%s\t%5d\t%s\n", $device, $level, $line/1024, $mount_point)
	    if $line =~ /^\d+$/;
    }
    close(DUMP);
}
close(MTAB);
