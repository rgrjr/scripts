#!/usr/bin/perl
#
# Look for and report bad things in a squid access log on the standard input.
# Right now, this just includes unauthorized proxying; things like worm hits are
# too much of a hassle to bother with.
#
#    Modification history:
#
# created.  -- rgr, 21-Jul-02.
#

push(@INC, '/home/rogers/hacks');
require 'parse-logs.pm';

while (<>) {
    $entry = parse_squid_log_entry($_);
    # any request from the local host/local network is always OK.
    $client_ip = $$entry{'remotehost'};
    next if $client_ip eq '127.0.0.1';
    next if $client_ip =~ /^192\.168\.57\./;
    # any request to a local server is always OK.
    $url = $$entry{'url'};
    next if $url =~ m@^http://(rgrjr\.dyndns\.org|bostonrocks\.dnsalias\.org)@;
    # if squid said "no way," then that's the right thing at this point.
    next if $$entry{'status'} >= 400;
    # otherwise, we have a problem.
    print make_standard_log_entry($entry), "\n";
}

