#!/usr/bin/perl -w
# Copyright (C) 2004 by Bob Rogers, all rights reserved.  This program is Open
# Source software; you may use it under the terms of the GNU GPL.
#
# Author:  Bob Rogers <rogers@rgrjr.dyndns.org>
#
# /etc/init.d/upsd.pl
#
# Perl UPS daemon for the APC Smart-UPS 1400 RM with network management card.
#
### BEGIN INIT INFO
# Provides: upsd
# Required-Start:
# X-UnitedLinux-Should-Start: hotplug kbd
# Required-Stop:
# Default-Start: 2 3 4 5
# Default-Stop:
# Description: UPS monitoring daemon for networked APC Smart-UPS 1400 RM.
### END INIT INFO
#
# Requirements:
#	LWP (distributed with perl)
#	logger utility (POSIX.2)
#	/sbin/shutdown
#
# Created 15-Jun-04 by Bob Rogers <rogers@rgrjr.dyndns.org>.  Based very loosely
# on the C version by Slavik Terletsky <ts@polynet.lviv.ua>, as published in the
# UPS-HOWTO by Harvey J. Stein <hjstein@bfr.co.il> (v2.42, 18 November 1997),
# plus some sample daemon code from the Perl documentation (v5.8.1).
#
# $Id$

use strict;
use LWP::UserAgent;
use HTTP::Headers;
use Data::Dumper;
use POSIX qw(setsid);
use IO::Pipe;

my $verbose_p = 0;
my $log_handle;

### configuration setup.

my $config_file_name = '/etc/upsd.conf';
while (@ARGV > 1 && $ARGV[0] =~ /^-./) {
    my $arg = shift(@ARGV);
    if ($arg eq '--config') {
	$config_file_name = shift(@ARGV);
    }
    elsif ($arg eq '--verbose') {
	$verbose_p++;
    }
    else {
	die "$0:  Unknown option '$arg'; died";
    }
}
my %config;
fetch_configuration($config_file_name);
my $daemon_name = $config{daemon_name} || 'upsd';
# 'http://apc/arakfram.htm?1:0'
my $url = $config{status_url};
if (! $url) {
    my $host = $config{ups_host} || $config{ups_ip_address};
    $url = "http://$host/upsstat.htm"
	if $host;
}
die("$0:  Must have either 'status url', or one of 'UPS host' ",
    "or 'UPS IP address' defined in '$config_file_name'.\n")
    unless $url;
my $min_runtime_left  = $config{min_runtime_left};		# in minutes.
$min_runtime_left = 2
    # having 'min_runtime_left = 0' is risky, but supported.
    if ! defined($min_runtime_left);
my $power_up_probe_interval		# seconds between normal pings.
    = $config{power_up_probe_interval} || 60;
my $power_down_probe_interval		# seconds between 'powerfail' pings.
    = $config{power_down_probe_interval} || 10;
my $auth_name = $config{auth_name} || 'apc';
my $auth_password = $config{auth_password} 
    or die "$0:  Must supply an 'auth_password' in '$config_file_name'.\n";
my $shutdown_program = $config{shutdown_program} || '/sbin/shutdown';
my $pid_file_name = $config{pid_file_name} || "/var/run/$daemon_name.pid";

### common setup.

my $ua = LWP::UserAgent->new;
my $h = new HTTP::Headers();
$h->authorization_basic($auth_name, $auth_password);
my $req = HTTP::Request->new('GET', $url, $h);

### subroutines.

sub fetch_configuration {
    # this parses samba-style keyword/value pairs from the named file, and
    # stuffs the results into the global %config hash.
    my $config_file_name = shift;

    open(IN, $config_file_name)
	or die("$0:  Couldn't open configuration file ",
	       "'$config_file_name':  $!\n");
    while (defined(my $line = <IN>)) {
	chomp($line);
	$line =~ s/^\s+//;
	$line =~ s/\s+$//;
	next
	    if ! $line || $line =~ /^#/;
	my ($option, $value) = split(/\s*=\s*/, $line, 2);
	$option = lc($option);
	$option =~ s/\s+/_/g;
	$value = 1
	    if ! defined($value);
	my $maybe_quote = ($value ? substr($value, 0, 1) : '');
	$value = substr($value, 1, -1)
	    if (($maybe_quote eq '"' || $maybe_quote eq "'")
		&& substr($value, -1) eq $maybe_quote);
	# warn "[defining \$config{'$option'} = '$value'.]\n";
	$config{$option} = $value;
    }
    close(IN);
}

sub fetch_ups_status {
    # Make the request -- initially we'll have to do this twice in order for the
    # authentication thing to go properly.
    my $res = $ua->request($req);
    while (! $res->is_success) {
	if ($res->code != 401) {
	    # [dying at this point might be suboptimal; it is probably a
	    # configuration error, but it seems excessive to kill the daemon for
	    # something that could be transient.  -- rgr, 2-Jul-04.]
	    die("$0:  Fatal:  Page request failed, code ", $res->code,
		", message '", $res->message, "'.\n")
		if $res->code >= 400;
	    print("$0:  Page request failed, code ", $res->code, ", message '",
		  $res->message, "'; retrying.\n")
		if $verbose_p;
	}
	$res = $ua->request($req);
    }

    # Extract status from the resulting page.  Fortunately, we can discard the
    # markup and use just the line breaks.
    my $status = '';
    my $state = '';
    my $runtime_remaining;
    for my $raw_line (split("\n", $res->content)) {
	my $line = $raw_line;
	$line =~ s/<[^>]*>//g;
	if ($line =~ /On Battery/) {
	    $status ||= 'powerfail';
	}
	elsif ($line =~ /No Alarms Present/) {
	    $status ||= 'up';
	}
	elsif ($line eq 'Runtime Remaining:') {
	    $state = 'rr';
	}
	elsif ($state eq 'rr') {
	    $runtime_remaining = $line+0;
	    $state = '';
	}
    }
    ($status || 'unknown', $runtime_remaining);
}

sub handle_sigterm {

    if (! unlink($pid_file_name)) {
	$log_handle->print("Couldn't remove PID file '$pid_file_name': $!\n");
    }
    $log_handle->print("Terminating.\n");
    $log_handle->close;
    exit(0);
}

sub run_ups_daemon {
    my $operation = shift;

    my $daemon_p = $operation eq 'start';
    if ($daemon_p && -e $pid_file_name) {
	warn "$0:  upsd.pl is already running as a daemon.\n";
	return 0;
    }
    my $last_status = 'initial';	# force an initial log message.
    my $last_time_left;
    my ($new_status, $time_left) = fetch_ups_status();

    # Put ourself into the background, if requested.
    $SIG{CHLD} = 'IGNORE';
    chdir('/')
	or die "Can't chdir to /: $!";
    if ($daemon_p) {
	# flush our stdin, which we won't need.
	open(STDIN, '/dev/null')
	    or die "Can't read stdin from /dev/null: $!";
	# open a pipe to the 'logger' program, as a way of getting messages into
	# the system log.  first, get rid of stderr, so it isn't held open by
	# the logger fork.
	open(STDERR, '>/dev/null')
	    or die "Can't redirect stderr to /dev/null: $!";
	$log_handle = IO::Pipe->new->writer('logger', '-it', $daemon_name, 
					    '-p', 'daemon.crit');
	# restore stderr (to the terminal, we assume).
	open(STDERR, '>&=STDOUT')
	    or die "Can't redirect stderr to stdout: $!";
	# redirect our stdout to the log.
	open(STDOUT, '>&', $log_handle)
	    or die "Can't redirect stdout to log handle: $!";
	my $pid = fork();
	if (! defined($pid)) {
	    die "0:  fork died:  $!";
	}
	elsif ($pid) {
	    # we are the parent,
	    open(OUT, ">$pid_file_name") or die;
	    print OUT "$pid\n";
	    close(OUT);
	    warn("Started UPS daemon, pid $pid, status '$new_status', ",
		 "$time_left minutes left.\n");
	    return 0;
	}
	# we are the child.
	$SIG{TERM} = \&handle_sigterm;
	setsid()
	    or die "Can't start a new session: $!";
	# [note that this directs warnings to the logger.  -- rgr, 22-Jun-04.]
	open(STDERR, '>&=STDOUT')
	    or die "Can't redirect stderr to stdout: $!";
    }
    else {
	$log_handle = new_from_fd IO::Handle(fileno(STDOUT),"w");
	warn("Running UPS daemon in the foreground.\n");
    }
    die "$0:  Couldn't open output pipe to logger.\nDied"
	unless $log_handle;
    # be sure to write log messages promptly!
    $log_handle->autoflush(1);

    # the interesting status values are 'up' and 'powerfail'; anything else we
    # treat as 'unknown' (e.g. somebody unplugged the network), and ignore.  so
    # the only two transitions of particular interest are 'up=>powerfail', when
    # we need to schedule a shutdown, and 'powerfail=>up', when we need to
    # cancel it.  the transition to "powerfail and zero battery time" is handled
    # specially.  other transitions are logged, as are changes in the amount of
    # battery time left when in 'powerfail' mode.
    my $shutdown_scheduled_p = 0;
    while (1) {
	my $log_p = ($last_status ne $new_status);
	if ($new_status eq 'ok' && $shutdown_scheduled_p) {
	    # cancel shutdown.
	    my $cmd = "$shutdown_program -c 'Power is back.'";
	    system($cmd)
		or $log_handle->print("Error:  Couldn't run \"$cmd\":  $!\n");
	    $shutdown_scheduled_p = 0;
	    $log_p = 1;
	}
	elsif ($new_status ne 'powerfail') {
	    # we might want to log this, but otherwise there's nothing to do.
	}
	# power failure cases.
	elsif (! $shutdown_scheduled_p) {
	    my $time_to_shutdown = $time_left-$min_runtime_left;
	    $time_to_shutdown = 0
		if $time_to_shutdown < 0;
	    my $cmd
		= join(' ', $shutdown_program, '-h',
		       ($time_to_shutdown == 0 ? 'now' : "+$time_to_shutdown"),
		       "'POWER FAILURE!'");
	    $log_handle->print("Status is '$new_status', ",
			       "$time_left minutes left; scheduling shutdown ",
			       ($time_to_shutdown
				? "in $time_to_shutdown minutes"
				: 'IMMEDIATELY'),
			       ".\n");
	    $log_p = 0;
	    if (fork() == 0) {
		# this must be done in a separate process because shutdown
		# blocks and waits for the specified elapsed time.
		exec($cmd)
		    or $log_handle->print("$0:  Couldn't exec \"$cmd\":  $!\n");
	    }
	    # can't do much if this fails.  assume the user is testing, and
	    # pretend that it worked.
	    $shutdown_scheduled_p = 1;
	}
	elsif ($time_left == 0) {
	    # oops; the battery must have run down faster than expected.  try to
	    # shut ourself down immediately.
	    $log_handle->print("Status is '$new_status', ",
		       "$time_left minutes left; shutting down IMMEDIATELY!\n");
	    $log_p = 0;
	    system($shutdown_program, '-h', 'now')
		or $log_handle->print("Error:  Couldn't exec ",
			      "'$shutdown_program now':  $!\n");
	}
	elsif ($last_time_left != $time_left) {
	    # force a "countdown" in the log.
	    $log_p = 1;
	}
	$log_handle->print("Status is '$new_status', ",
			   "$time_left minutes left.\n")
	    if $log_p;
	# set up for the next iteration.
	($last_status, $last_time_left) = ($new_status, $time_left);
	sleep($last_status eq 'up'
	      ? $power_up_probe_interval
	      : $power_down_probe_interval);
	($new_status, $time_left) = fetch_ups_status();
    }
    # never returns.
}

### Main code.

my $operation = shift(@ARGV) || '';
if ($operation eq 'start' || $operation eq 'test') {
    run_ups_daemon($operation);
}
elsif ($operation eq 'stop') {
    if (open(IN, $pid_file_name)) {
	chomp(my $pid = <IN>);
	close(IN);
	if (! kill(15, $pid)) {
	    warn "$0:  Couldn't do 'kill -15 $pid'.\n";
	    exit(1);
	}
	warn("$0:  Daemon $pid terminated.\n");
    }
    else {
	warn("$0:  Couldn't open PID file '$pid_file_name'; ",
	     "daemon not running?\n");
	# don't take an error exit in this case.
    }
}
elsif ($operation eq 'status') {
    my ($status, $runtime_remaining) = fetch_ups_status();
    print "Status '$status', runtime $runtime_remaining minutes.\n";
}
else {
    die "Usage:  $0 [ --config <file> ] (start|stop|status|test)\n";
}
exit(0);
