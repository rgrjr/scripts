#!/usr/local/bin/perl -p
# one-liner cribbed from perl squid faq 6.6
# (http://www.squid-cache.org/Doc/FAQ/FAQ-6.html#ss6.6).  -- rgr, 19-Jul-02.
s/^\d+\.\d+/localtime $&/e;
