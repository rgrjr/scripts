#!/usr/local/bin/perl

require '/root/bin/rename-into-tree.pm';

$warn = 'rename-into-tree.pl';
my $verbose_p = 0;
my $delete_dir_p = 0;

while (@ARGV) {
    $arg = shift(@ARGV);
    if ($arg eq '-verbose') {
	$verbose_p++;
    }
    elsif ($arg eq '-delete-dir') {
	$delete_dir_p++;
    }
    else {
	unshift(@ARGV, $arg);
	last;
    }
}
($from, $to) = @ARGV;
die "$warn:  Missing 'from' and 'to' arguments.\nDied"
    unless defined($to);

rename_subtree($from, $to, $delete_dir_p);
