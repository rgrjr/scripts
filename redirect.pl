#!/usr/bin/perl -w
#
# Squid redirector.  After modifying this script, you must do
#
#	/usr/sbin/squid -k reconfigure
#
# to get Squid to restart the new version.
#
#    [old] Modification history:
#
# created.  -- rgr, 15-Jul-02.
# added debugging code.  -- rgr, 18-Jul-02.
# started working on advertising filtering.  -- rgr, 19-Jul-02.
# new $local_server_http_url var, moved to port 86.  -- rgr, 26-Jul-02.
# ads.x10.com.  -- rgr, 2-Aug-02.
# networking.earthweb.com ads.  -- rgr, 8-Aug-02.
# added geocrawler (geoads.osdn.com & gcads.osdn.com).  -- rgr, 26-Oct-02.
# some geocrawler ad urls start with "//".  punt.  -- rgr, 4-Nov-02.
# punt raw IPs.  -- rgr, 7-Nov-02.
# close some more sfads.osdn.com cases.  -- rgr, 20-Apr-03.
# updated for SuSE 8.1 (squid-2.4.STABLE7-67), move local server back to port 
#	80, added to CVS.  -- rgr, 19-Oct-03.
#
# $Id$

# $debug_log_file_name = '/usr/local/squid/libexec/debug/redirector.log';

$local_server_http_url = 'http://rgrjr.dyndns.org';
$doubleclick_image = "$local_server_http_url/random/doubleclick.png";
$access_denied_url = "$local_server_http_url/random/access-denied.html";

# Note that these cannot end in "/", due to the regexp used.
%url_map
    = (# [rgrjr.dyndns.org now live directly on port 80.  -- rgr, 19-Oct-03.]
       # 'http://rgrjr.dyndns.org' => "$local_server_http_url",
       # 'http://rgrjr.dyndns.org:80' => "$local_server_http_url",
       # [this assumes an SSH connection opened with "-L 8081:alexandria:80".
       # -- rgr, 19-Oct-03.]
       'http://alexandria' => 'http://127.0.0.1:8081',
       'http://bostonrocks.dnsalias.org' => 'http://bostonrocks.dnsalias.org:8080',
       'http://bostonrocks.dnsalias.org:80' => 'http://bostonrocks.dnsalias.org:8080',
       # this allows connection requests to the test server to get through.
       'http://bostonrocks.dnsalias.org:8000' => 'http://bostonrocks.dnsalias.org:8000',
       );
$|=1;

while (<>) {
    if (m@^https?://[^/]+@
	&& defined($replacement = $url_map{$&})) {
	chomp($orig_line = $_);
	s@@$replacement@;
	print;
	if ($debug_log_file_name) {
	    if (open(DEBUG, ">>$debug_log_file_name")) {
		print DEBUG $orig_line, "\n", $_;
		close(DEBUG);
	    }
	} 
    }
    elsif (m@^//@) {
	# geocrawler brokenness.
	print "$doubleclick_image\n";
    }
    elsif (m@^https?://[a-z]+\.osdn\.com/cgi-bin/ad_default\.pl\?display@i) {
	# covers sourceforge and geocrawler.  [really ought to have a separate
	# image for this.  -- rgr, 20-Jul-02.]
	print "$doubleclick_image\n";
    }
    elsif (m@\.gif[ ?]@) {
	# GIF image; probably an ad, almost certainly animated.  (Non-animated
	# .PNG ads are not nearly as obnoxious.)  [once we get some data, we'll
	# try to systematize this a little better.  -- rgr, 8-Aug-02.]
	if (m@^://.*\.doubleclick\.net/@i) {
	    print "$doubleclick_image\n";
	}
	if (m@^://[0-9.]+/@i) {
	    # Always croak on gifs that come from an anonymous IP address.  --
	    # rgr, 7-Nov-02.
	    print "$doubleclick_image\n";
	}
	elsif (m@^http://www.anywho.com/img/promos/@i) {
	    # [really ought to have a separate image for this.  -- rgr,
	    # 26-Aug-02.]
	    print "$doubleclick_image\n";
	}
	elsif (m@http://[a-z]*ads.osdn.com/@i) {
	    # [fmads.osdn.com are seen on freshmeat.net sites.  -- rgr,
	    # 28-Aug-02.]  [also catches some more sfads.osdn.com cases.  --
	    # rgr, 20-Apr-03.]
	    print "$doubleclick_image\n";
	}
	elsif (m@^http://networking.earthweb.com/RealMedia/ads/@i) {
	    # [really ought to have a separate image for this.  this is rather
	    # obscure, though.  -- rgr, 8-Aug-02.]
	    print "$doubleclick_image\n";
	}
	elsif (m@^http://view\.atdmt\.com/AVE/view/@i
	       || m@^http://ads\.x10\.com/@i
	       || m@^http://[a-z0-9.]+\.yimg\.com/us\.yimg\.com/[ai]/@i) {
	    # maps.yahoo.com ads.
	    print "$doubleclick_image\n";
	}
	else {
	    # not an ad (or not one that we recognize).
	    print;
	}
    }
    else {
	# print "$access_denied_url\n";
	print;
    }
}
