#!/usr/bin/perl
#
#    Appletalk status.  -- rgr, 22-Apr-00.
#
#    Modification history:
#
# adapted from netatalk-admins@umich.edu posting.  -- rgr, 22-Apr-00.
#

=head1 Original posting
From: Tom Fitzgerald <tfitz@MIT.EDU>
To: jhart@abacus.bates.edu
Cc: "Patrik Schindler" <poc@pocnet.net>,
        "Netatalk List" <netatalk-admins@umich.edu>
Subject: Re: How to determine which Mac s are connected? 
Date: Thu, 23 Mar 2000 15:54:30 -0500

> Patrik Schindler, poc@pocnet.net writes:
> 
> >Indeed, a little goodie to keep track which users were connected from 
> >which machines would be nice, but I have no idea to keep track of 
> >AppleTalk users.
> >

> We use "ps".  Doing a 'ps aux|grep afp' will give you a list of all the 
> afp processes.  The one owned by "root" is the original.  All the others 
> are owned by the login id of the user.  To track down machines, you have 
> to go to the log file: /var/log/messages
> 
>   sudo grep afp /var/log/messages
> 
> will list out everything, including the process ID.  With a little 
> scripting, it would be possible to "join" the two together by process ID, 
> thus matching user with machine.  Hmmmm....maybe I'll write it and donate 
> it to the list.
> 

Here's what I use on Solaris.  It depends on /var/log/syslog having all
afpd log info (so when the syslog gets truncated, the info becomes
unreliable, but oh well).

Output looks like:

# atwho
    USER    GROUP   PID  RSS    STIME        TIME CMD     HOST
 susanrm      mit 25601  940   Mar_20        0:25 afpd    lycra
 namkung      mit 10641  852   Mar_22        0:02 afpd    scanmac-116
 h_chang      mit 16964  864 19:31:26        0:00 afpd    eastgate-four
 susanrm      mit  2621  904 13:56:31        0:00 afpd    cro-g4
   jmack      mit  1959 1028 13:29:12        0:02 afpd    fredrik
(etc)

all fields except the last are from ps(1), so RSS is process memory
size in KB, STIME is process start time, etc.

=cut

use Socket;

$logfile = "/var/log/messages";	# was/var/log/syslog for solaris
%ip = ();		# indexed by pid: IP address of client
%user = ();		# and user logged in on that client

open (LOG, $logfile) || die "Can't open $logfile: $!";
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
