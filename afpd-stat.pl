#!/usr/bin/perl
#
# Status of afpd connections.  Posted to netatalk-admins@umich.edu by Tom
# Fitzgerald <tfitz@MIT.EDU> on 23-Mar-00.
#
#    Modification history:
#
# modified.  -- rgr, 23-Mar-00.
#

use Socket;

%ip = ();		# indexed by pid: IP address of client
%user = ();		# and user logged in on that client

open (LOG, "/var/log/messages") || die "Can't open syslog: $!";
while (<LOG>) {
    next unless / afpd\[.*( login | logout | session| server_child)/;
    @a = split (' ');
    ($pid = $a[4]) =~ s/^afpd\[(.*)\]:$/$1/;
    if ($a[6] =~ /^session:/) {
        ($ip = $a[8]) =~ s/:.*//;
        $ip {$pid} = $ip;
    } elsif ($a[5] eq "login") {
        $user {$pid} = $a[6];
    } elsif ($a[5] eq "logout") {
        delete $ip {$pid};
        delete $user {$pid};
    } elsif ($a[5] =~ /^server_child/) {
        $pid = $a[6];
        delete $ip {$pid};
        delete $user {$pid};
    }
}
close LOG;

open (PS, "ps -ae -o user,group,pid,rss,stime,time,fname|")
   || die "Can't fork ps: $!";

$_ = <PS>;
chop;
printf "%-57s %s\n", $_, "HOST";
while (<PS>) {
    next if /^    root / || !/afpd$/;
    chop;
    @a = split(' ');
    $pid = $a[2];
    $packip = pack ('C4', split (/\./, $ip{$pid}));
    ($name, $rest) = gethostbyaddr ($packip, AF_INET);
    printf "%-57s %s\n", $_, $name;
}
close PS;
