#!/usr/bin/perl -w
#
# hacking qmail queues.
#
#    Modification history:
#
# created.  -- rgr, 4-May-03.
#

use strict;

my $queue = '/mnt/rh60/var/qmail/queue';
my $verbose_p = 0;
$verbose_p ++, shift(@ARGV)
    if @ARGV && ($ARGV[0] eq '-v' || $ARGV[0] eq '--verbose');

sub snarf_data_file_internal {
    my $file_name = shift;
    
    open(IN, $file_name) || die "$0:  Can't open '$file_name':  $!\n";
    my $data;
    my $result = read(IN, $data, 9999);
    warn "$0:  Oops; read of '$file_name' returned $result . . .\n"
	unless $result;
    return ('file_name' => $file_name, 
	    map {
		(substr($_, 0, 1) => substr($_, 1));
	    } split("\0", $data));
}

sub snarf_data_file {
    my ($type, $inode) = @_;

    my $file_name = "$queue/$type/$inode";
    if (! -r $file_name) {
	open(FILES, "find $queue/$type -name $inode |") || die;
	my ($file_name) = <FILES>;
	close(FILES) || die;
	die if ! $file_name;
	chomp($file_name);
    }
    snarf_data_file_internal($file_name);
}

while (@ARGV) {
    my $inode = shift(@ARGV);
    die "$0:  '$inode' is not an inode number.\n"
	unless $inode =~ /^\d+$/;
    open(FILES, "find $queue/mess -name $inode |") || die;
    my ($message_file_name) = <FILES>;
    close(FILES) || die;
    die "$0:  No message file for $inode ??\n"
	if ! $message_file_name;
    chomp($message_file_name);
    my %data = snarf_data_file('todo', $inode);
    print "Message file:  $message_file_name\nData:\t", 
          join("\t", %data), "\n"
	if $verbose_p;
    my $sender = $data{'F'} || die "no sender?\nDied";
    my $recipient = $data{'T'} || die "no recipient?\nDied";
    my $command = "qmail-inject -f$sender $recipient < $message_file_name";
    if (system($command) == 0) {
	unlink($message_file_name, "$queue/intd/$inode");
	unlink($data{'file_name'})
	    if $data{'file_name'};
    }
    else {
	print "Injection failed:  $!\nCommand:  '$command'\n";
    }
}
