# Useful hacks for parsing squid and httpd logs.
#
#    Modification history:
#
# created.  -- rgr, 19-Jul-02.
#

@month_abbreviations = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
			'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
$tz = '-0400';		# [kludge.  -- rgr, 19-Jul-02.]

sub parse_squid_log_entry {
    # Given a line in Squid's native log format, parse it into a hash that maps
    # the obvious field names to values.  See Squid FAQ 6.6
    # (http://www.squid-cache.org/Doc/FAQ/FAQ-6.html#ss6.6) for a description of
    # what these fields mean.
    my $line = shift;
    my ($code_status, $peerstatus_peerhost);
    my $entry = {};

    chomp($line);
    ($$entry{'unix_time'}, $$entry{'elapsed'}, $$entry{'remotehost'},
     $code_status, $$entry{'bytes'}, $$entry{'method'}, $$entry{'url'},
     $$entry{'rfc931'}, $peerstatus_peerhost, $$entry{'mime_type'})
	= split(' ', $line);
    ($$entry{'code'}, $$entry{'status'}) = split('/', $code_status);
    ($$entry{'peerstatus'}, $$entry{'peerhost'})
	= split('/', $peerstatus_peerhost);
    # reformat the time.
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst)
	= localtime($$entry{'unix_time'});
    $$entry{'time'} = sprintf("%02d/%s/%04d:%02d:%02d:%02d %s",
			     $mday, $month_abbreviations[$mon], 1900+$year,
			     $hour, $min, $sec, $tz);
    $entry;
}

sub parse_standard_log_entry {
    # Given a line in the industry-standard log format, parse it into a hash
    # that maps the obvious field names to values.
    my $line = shift;
    my ($time1, $time2);
    my $entry = {};

    chomp($line);
    ($$entry{'remotehost'}, $$entry{'rfc931'}, $$entry{'authuser'},
     $time1, $time2, $$entry{'method'}, $$entry{'url'}, $$entry{'protocol'},
     $$entry{'code'}, $$entry{'bytes'}, $rest) = split(' ', $line, 11);
    # parse out the 'referer' and 'user-agent' fields.
    if ($rest =~ / *"([^""]+)"/) {
	$$entry{'referer'} = $1;
	$rest = $';
	if ($rest =~ / *"([^""]+)"/) {
	    $$entry{'user-agent'} = $1;
	}
    }
    # fix up other fields.
    $$entry{'method'} =~ s/^\"//;
    $$entry{'protocol'} =~ s/\"$//;
    $time1 =~ s/^\[//;
    $time2 =~ s/\]$//;
    $$entry{'time'} = "$time1 $time2";
    # [should parse the time into unix_time, for consistency.  -- rgr,
    # 19-Aug-02.]
    $entry;
}

sub make_standard_log_entry {
    # All but the newline.
    my ($entry) = @_;

    join(' ', $$entry{'remotehost'}, $$entry{'rfc931'}, '-',
	 "[$$entry{'time'}]",
	 "\"$$entry{'method'} $$entry{'url'} HTTP/1.0\"",
	 $$entry{'status'}, $$entry{'bytes'},
	 # these last two are the "referer" and user-agent headers.  squid
	 # doesn't preserve these, though they will be passed through to
	 # aolserver and recorded there in the event of a cache miss.
	 '"'.($$entry{'referer'} || '').'"',
	 '"'.($$entry{'user-agent'} || '').'"');
}
