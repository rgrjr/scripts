#!/usr/bin/perl
#
# Turn a squid log into "Common Logfile Format" as a filter.
#
#    Modification history:
#
# created.  -- rgr, 19-Jul-02.
#

# [note that parse-logs.pm can't handle "-w" yet.  -- rgr, 26-Jul-03.]
require 'parse-logs.pm';

while (<>) {
    print make_standard_log_entry(parse_squid_log_entry($_)), "\n";
}
