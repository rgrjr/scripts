#!/usr/bin/perl
#
# Testing for the qmail-deliver.pl script.
#
# [created.  -- rgr, 9-Sep-16.]
#

use strict;
use warnings;

use Test::More tests => 51;

# Clean up from old runs, leaving an empty Maildir.
chdir('email') or die "bug";
for my $dir (qw(spam emacs Maildir)) {
    system(qq{rm -fr $dir})
	if -d $dir;
}
unlink(qw(.qmail-spam .qmail-emacs));
ok(0 == system('maildirmake Maildir'), "created Maildir")
    or die "no 'maildirmake' program?\n";

### Subroutines.

sub count_messages {
    # Really, this just counts files.
    my ($maildir, $subdir) = @_;
    $maildir ||= 'Maildir';
    $subdir ||= 'new';

    opendir(my $dir, "$maildir/$subdir") or die "$0:  Bug:  $!";
    my $count = 0;
    while (my $file = readdir($dir)) {
	next
	    if $file =~ /^[.]/;
	$count++;
    }
    closedir($dir);
    return $count;
}

sub deliver_one {
    my ($message_file, $maildir, $expected_messages, %options) = @_;
    my $exit_code = ($options{exit_code} || 0) << 8;
    local $ENV{SENDER} = $options{sender} || 'rogers@rgrjr.dyndns.org';
    local $ENV{LOCAL} = $options{localpart};

    my $command = q{perl -Mlib=.. qmail-deliver2.pl};
    $command .= " --test"
	if $options{test_p};
    $command .= " --redeliver"
	if $options{redeliver_p};
    $command .= " --blacklist=$options{blacklist}"
	if $options{blacklist};
    $command .= " --whitelist=$options{whitelist}"
	if $options{whitelist};
    $command .= " --deadlist=$options{deadlist}"
	if $options{deadlist};
    $command .= " --host-deadlist=$options{host_deadlist}"
	if $options{host_deadlist};
    for my $opt (qw(file file1 file2 file3)) {
	$command .= " $options{$opt}"
	    if $options{$opt};
    }
    my $exit = system(qq{$command < $message_file 2>/dev/null});
    ok($exit_code == $exit, "deliver $message_file")
	or warn "actually got exit code $exit for '$command < $message_file'";
    ok($expected_messages == count_messages($maildir),
       "have $expected_messages messages in $maildir")
	or die "actually have ", count_messages($maildir);
}

### Main code.

## Simple default deliveries.
deliver_one('from-bob.text', 'Maildir', 1);
deliver_one('rgrjr-forged-1.text', 'Maildir', 2);
deliver_one('rgrjr-forged-2.text', 'Maildir', 2,
	    test_p => 1);
deliver_one('rgrjr-forged-2.text', 'Maildir', 3);

## Test extension delivery.
system('echo emacs/ > .qmail-emacs');
deliver_one('rgrjr-forged-1.text', 'Maildir', 3,
	    # This tests invalid maildir delivery.
	    exit_code => 75);
ok(0 == system('maildirmake emacs'), "created emacs maildir");
deliver_one('rgrjr-forged-1.text', 'emacs', 1);
deliver_one('rgrjr-forged-2.text', 'emacs', 2);
ok(3 == count_messages(), "new emacs stuff not delivered to Maildir");

## Test forgery.
ok(0 == system('maildirmake spam'), "created spam maildir");
system('echo spam/ > .qmail-spam');
deliver_one('rgrjr-forged-1.text', 'spam', 1);
ok(3 == count_messages(), "spam not delivered to Maildir");

## Test blacklisting and whitelisting.
system('echo debra@hotmail.com > list.tmp');
deliver_one('from-debra.text', 'spam', 2,
	    blacklist => 'list.tmp',
	    sender => 'debra@somewhere.com');
ok(3 == count_messages(), "blacklisted sender not delivered to Maildir");
deliver_one('from-debra.text', 'Maildir', 4,
	    whitelist => 'list.tmp',
	    sender => 'debra@somewhere.com');
ok(2 == count_messages('spam'),
   "whitelisted sender not delivered to spam");
deliver_one('from-jan.text', 'spam', 3,
	    whitelist => 'list.tmp',
	    sender => 'jan@somewhere.com');
ok(4 == count_messages(),
   "non-whitelisted sender not delivered to Maildir");
unlink('list.tmp');

## Test deadlisting.
system('echo rogers-ilisp@rgrjr.dyndns.org > list.tmp');
system('echo /dev/null > .qmail-dead');
deliver_one('dead-1.text', 'Maildir', 4,
	    deadlist => 'list.tmp',
	    sender => 'debra@somewhere.com');

## Test host deadlisting.
system('echo qq.com > host-deadlist.tmp');
deliver_one('from-debra.text', 'Maildir', 4,
	    host_deadlist => 'host-deadlist.tmp',
	    sender => 'bogus@qq.com');
ok(3 == count_messages('spam'), "still have 3 spam messages");
unlink('host-deadlist.tmp');

## Another forgery test.
deliver_one('viagra-inc.text', 'spam', 4,
	    sender => 'rogerryals@hcsmail.com');

## Test redelivery.
{
    # We have to awkwardly scan through Maildir/new to find the actual file
    # names used.
    my @files;
    opendir(my $new_files, 'Maildir/new') or die;
    while (readdir($new_files)) {
	my $file = "Maildir/new/$_";
	open(my $in, '<', $file) or die;
	while (<$in>) {
	    if (/^$/) {
		last;
	    }
	    elsif (/^Return-Path:/) {
		push(@files, $file);
		last;
	    }
	}
    }
    ok(@files == 2, q{have two files with "Return-Path:" in them});
    deliver_one('/dev/null', 'spam', 5,
		file => $files[0]);
    ok(4 == count_messages(), "Maildir left untouched");
    deliver_one('/dev/null', 'spam', 7,
		redeliver_p => 1,
		file1 => pop(@files),
		file2 => pop(@files));
    ok(2 == count_messages(), "redelivered messages moved out of Maildir");
}

## Test message-id consolidation.
ok(0 == system('mkdir spam/msgid'), "created spam/msgid")
    or die "failed:  $!\n";
deliver_one('viagra-inc.text', 'spam', 8,
	    sender => 'rogerryals@hcsmail.com');
ok(1 == count_messages('spam', 'msgid'), "have one spam msgid");
deliver_one('viagra-inc.text', 'spam', 8,
	    sender => 'rogerryals@hcsmail.com');
ok(1 == count_messages('spam', 'msgid'), "still have one spam msgid");
