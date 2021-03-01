#!/usr/bin/perl
#
# Testing for the qmail-deliver.pl script.
#
# [created.  -- rgr, 9-Sep-16.]
#

use strict;
use warnings;

use Test::More tests => 72;

### Subroutines.

sub clean_up {
    # Clean up from old runs, leaving an empty Maildir.
    for my $dir (qw(spam emacs dead Maildir)) {
	system(qq{rm -fr $dir})
	    if -d $dir;
    }
    unlink(qw(list.tmp .qmail-spam .qmail-emacs .qmail-dead));
}

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

my %boolean_option_p
    = (test_p => " --test",
       redeliver_p => " --redeliver",
       use_deliver_to_p => " --use-delivered-to",
       verbose_p => " --verbose");
my %keyword_option_p
    = (network_prefix => '--network-prefix',
       blacklist => '--blacklist',
       whitelist => '--whitelist',
       deadlist => '--deadlist',
       host_deadlist => '--host-deadlist');

sub deliver_one {
    my ($message_file, $maildir, $expected_messages, @options) = @_;
    my %options = @options;
    my $exit_code = ($options{exit_code} || 0) << 8;
    $options{network_prefix} ||= '10.0.0';
    local $ENV{RECIPIENT} = $options{recipient} || '';
    local $ENV{SENDER} = $options{sender} || 'rogers@rgrjr.dyndns.org';
    local $ENV{LOCAL} = $options{localpart};

    # Set up the command.
    my $command
	= join(' ', q{perl -Mlib=.. ./qmail-deliver.pl --relay 69.164.211.47},
	       q{--add-local rgrjr.dyndns.org --add-local rgrjr.com});
    while (@options) {
	my ($keyword, $value) = (shift(@options), shift(@options));
	if (my $opt = $keyword_option_p{$keyword}) {
	    $command .= " $opt=$value";
	}
	elsif ($opt = $boolean_option_p{$keyword}) {
	    $command .= $opt;
	}
    }
    for my $opt (qw(file file1 file2 file3)) {
	$command .= " $options{$opt}"
	    if $options{$opt};
    }
    # We still discard stderr even if we are passing the --verbose option,
    # because qmail-deliver.pl redirects its stderr to post-deliver.log; this
    # redirection is just to catch a few forged-local-address.pl dribbles when
    # --verbose is not specified.
    my $exit = system(qq{$command < $message_file 2>/dev/null});
    ok($exit_code == $exit, "deliver $message_file")
	or warn "actually got exit code $exit for '$command < $message_file'";
    ok($expected_messages == count_messages($maildir),
       "have $expected_messages messages in $maildir")
	or die "actually have ", count_messages($maildir);
}

### Main code.

## Set up.
chdir('email') or die "bug";
clean_up();
ok(0 == system('maildirmake Maildir'), "created Maildir")
    or die "no 'maildirmake' program?\n";

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
ok(0 == system('maildirmake dead'), "created dead maildir");
system('echo dead/ > .qmail-dead');
deliver_one('dead-1.text', 'dead', 1,
	    deadlist => 'list.tmp',
	    sender => 'debra@somewhere.com');
system('echo rogers-netatalk-devel@rgrjr.dyndns.org >> list.tmp');
deliver_one('netatalk-devel.text', 'dead', 2,
	    recipient => 'rogers-netatalk-devel@rgrjr.dyndns.org',
	    deadlist => 'list.tmp',
	    sender => 'debra@somewhere.com');
ok(0 == system('rm -fr dead'), 'removed dead maildir');

## Test host deadlisting.
system('echo qq.com > host-deadlist.tmp');
system('echo /dev/null > .qmail-dead');
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

## Another blacklist test.
system('echo baoguan@hotmail.com >> list.tmp');
deliver_one('baoguan.text', 'spam', 9,
	    blacklist => 'list.tmp',
	    sender => 'baoguan@hotmail.com');
ok(2 == count_messages(), "blacklisted sender not delivered to Maildir");

## Test local address checking.
system('echo jan@rgrjr.dyndns.org >> list.tmp');
deliver_one('from-jan.text', 'Maildir', 3,
	    network_prefix => '192.168.57',
	    whitelist => 'list.tmp');
deliver_one('from-jan-2.text', 'Maildir', 4,
	    network_prefix => '192.168.57',
	    whitelist => 'list.tmp');
deliver_one('from-jan-3.text', 'Maildir', 5,
	    network_prefix => '192.168.57',
	    whitelist => 'list.tmp');
deliver_one('from-debra.text', 'Maildir', 6,
	    network_prefix => '65.54.168');

## Test delivery of a Postfix bounce message.
deliver_one('bounce-test.text', 'Maildir', 7,
	    network_prefix => '209.85.128.0/17');

## Test the --use-delivered-to feature.
system('echo rogers@modulargenetics.com >> list.tmp');
deliver_one('relay-test.text', 'emacs', 3,
	    whitelist => 'list.tmp',
	    use_deliver_to_p => 1,
	    network_prefix => '209.85.128.0/17');
# The same message will go to Maildir/ without the --use-delivered-to flag.
deliver_one('relay-test.text', 'Maildir', 8,
	    whitelist => 'list.tmp',
	    network_prefix => '209.85.128.0/17');

## Tidy up.
clean_up();

__END__

=head1 NAME

test-qmail-deliver.pl

=head1 SYNOPSIS

    perl email/test-qmail-deliver.pl

=head1 DESCRIPTION

This script tests the C<qmail-deliver.pl> script.  It first does a
"chdir" to the F<email/> subdirectory, then creates a series of
F<.qmail> files and maildirs; for the latter it needs the
C<maildirmake> program on the path.

It then alternates between calling C<qmail-deliver.pl> to deliver
messages sourced from files and counting messages in maildirs to be
sure that they did (or didn't) get to the appropriate maildirs.  The
C<--redeliver> feature is also tested.

=cut
