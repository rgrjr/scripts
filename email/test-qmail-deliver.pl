#!/usr/bin/perl
#
# Testing for the qmail-deliver.pl script.
#
# [created.  -- rgr, 9-Sep-16.]
#

use strict;
use warnings;

use Test::More tests => 28;

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

sub count_new_messages {
    my ($maildir) = @_;
    $maildir ||= 'Maildir';

    opendir(my $dir, "$maildir/new") or die "$0:  Bug:  $!";
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
    local $ENV{LOCAL} = $options{localpart} || 'rogers';

    my $command = q{perl -Mlib=.. qmail-deliver.pl};
    $command .= " --blacklist=$options{blacklist}"
	if $options{blacklist};
    $command .= " --whitelist=$options{whitelist}"
	if $options{whitelist};
    my $exit = system(qq{$command < $message_file 2>/dev/null});
    ok($exit_code == $exit, "deliver $message_file")
	or warn "actually got exit code $exit";
    ok($expected_messages == count_new_messages($maildir),
       "have $expected_messages messages in $maildir");
}

### Main code.

## Simple default deliveries.
deliver_one('from-bob.text', 'Maildir', 1);
deliver_one('rgrjr-forged-1.text', 'Maildir', 2,
	    localpart => 'rogers-emacs');
deliver_one('rgrjr-forged-2.text', 'Maildir', 3,
	    localpart => 'rogers-emacs');

## Test extension delivery.
system('echo emacs/ > .qmail-emacs');
deliver_one('rgrjr-forged-1.text', 'Maildir', 3,
	    localpart => 'rogers-emacs',
	    # This tests invalid maildir delivery.
	    exit_code => 75);
ok(0 == system('maildirmake emacs'), "created emacs maildir");
deliver_one('rgrjr-forged-1.text', 'emacs', 1,
	    localpart => 'rogers-emacs');
deliver_one('rgrjr-forged-2.text', 'emacs', 2,
	    localpart => 'rogers-emacs');
ok(3 == count_new_messages(), "new emacs stuff not delivered to Maildir");

## Test forgery.
ok(0 == system('maildirmake spam'), "created spam maildir");
system('echo spam/ > .qmail-spam');
deliver_one('rgrjr-forged-1.text', 'spam', 1,
	    localpart => 'rogers-emacs');
ok(3 == count_new_messages(), "spam not delivered to Maildir");

## Test blacklisting and whitelisting.
system('echo debra@hotmail.com > list.tmp');
deliver_one('from-debra.text', 'spam', 2,
	    blacklist => 'list.tmp',
	    sender => 'debra@somewhere.com');
ok(3 == count_new_messages(), "blacklisted sender not delivered to Maildir");
deliver_one('from-debra.text', 'Maildir', 4,
	    whitelist => 'list.tmp',
	    sender => 'debra@somewhere.com');
ok(2 == count_new_messages('spam'),
   "whitelisted sender not delivered to spam");
deliver_one('from-jan.text', 'spam', 3,
	    whitelist => 'list.tmp',
	    sender => 'jan@somewhere.com');
ok(4 == count_new_messages(),
   "non-whitelisted sender not delivered to Maildir");
unlink('list.tmp');
