#!/usr/bin/perl -w
#
#  Given an access.log format file, count the number of times each page was hit.
#
#    Modification history:
#
# created.  -- rgr, 28-May-00.
# -verbose option.  -- rgr, 2-Jun-00.
# directory totals.  -- rgr, 26-Nov-00.
# -(no-)?(page-totals|summary) options, handle broken log format, skip bad
#	return codes by default (see -all).  -- rgr, 4-Aug-01.
#

use strict;
use Socket;	# for inet_aton

my $warn = 'page-hits.pl';

# input filtering
my %skip_address_p = ();	# addresses to filter out
my $skip_errors_p = 1;
# output formatting
my $use_dns_names_p = 1;
# detail selection
my $verbose_p = 0;
my $print_page_totals_p = 0;
my $print_summary_p = 1;

# Results
my %hits = ();
my %total_hits = ();
my %return_codes = ();

while (@ARGV && $ARGV[0] =~ /^-./) {
    my $arg = shift(@ARGV);
    if ($arg eq '-verbose') {
	$verbose_p++;
    }
    elsif ($arg eq '-all') {
	$skip_errors_p = 0;
    }
    elsif ($arg eq '-summary') {
	$print_summary_p = $arg;
    }
    elsif ($arg eq '-no-summary') {
	$print_summary_p = 0;
    }
    elsif ($arg eq '-page-totals') {
	$print_page_totals_p = $arg;
    }
    elsif ($arg eq '-no-page-totals') {
	$print_page_totals_p = 0;
    }
    elsif ($arg eq '-nodns') {
	$use_dns_names_p = 0;
    }
    elsif ($arg eq '-nolocal') {
	open(IFCFG, "/sbin/ifconfig |") || die;
	my $line;
	while (defined($line = <IFCFG>)) {
	    $skip_address_p{$1}++
		if ($line =~ /inet addr:([0-9.]+)/);
	}
	close(IFCFG);
	# [that was very elegant, but it doesn't consider jan's mac as local.
	# -- rgr, 21-Jul-02.]
	$skip_address_p{'192.168.57.2'}++;
    }
    else {
	warn("Usage:  $warn [-help] [-verbose] [-all] [-nodns] [-nolocal]",
	     "\n\t\t     [-[no-]summary] [-[no-]page-totals]\n");
	exit(0) if $arg eq '-help';
	die "$warn:  '$arg' is unknown; punting.\n";
    }
}

my %ip_to_host_name_cache = ();
sub nslookup_ptr {
    my $ip = shift;

    if (defined($ip_to_host_name_cache{$ip})) {
	$ip_to_host_name_cache{$ip};
    }
    else {
	my ($name) = gethostbyaddr(inet_aton($ip), AF_INET);
	$ip_to_host_name_cache{$ip} = $name;
	$name;
    }
}

sub host_ip_and_name {
    # Return a pretty string with both host name & ip if possible.
    my $ip = shift;
    my $name;

    if (! $use_dns_names_p) {
	"[$ip]";
    }
    elsif ($ip =~ /^192\.168\./) {
	# For some reason, 192.168.1.1 gets mapped to rgr.rgrjr.com, which might
	# be legitimate (if not strictly correct) if the connection was coming
	# from the internal interface.  Since we've lost that information by
	# this point, always use the numeric address.  -- rgr, 16-Apr-00.
	"[$ip]";
    }
    elsif ($name = nslookup_ptr($ip)) {
	"$name ($ip)";
    }
    else {
	"[$ip]";
    }
}

sub split_access_log_line {
    # Split an access.log line into its component fields, based on my skimpy
    # understanding of its syntax.  Fields appear to be of the form (ip, ??, ??,
    # date, request, return_code, return_length, referer, agent), but items are
    # delimited with spaces and may contain internal spaces when enclosed in
    # double-quotes (request or agent) or square brackets (date).  The two "??"
    # entries always show up as "-"; I have no idea what they are for.  -- rgr,
    # 28-May-00.
    my $line = shift;
    my @result = ();

    $line .= ' ';
    # $line =~ /^/g;
    while ($line) {
	die "[runaway; result is (", join(', ', @result), ") elts]\n"
	    if @result > 20;
	if ($line =~ /\G$/gc) {
	    last;
	}
	elsif ($line =~ /\G"([^""]*)" /gc) {
	    push(@result, $1);
	}
	elsif ($line =~ /\G""400 /gc) {
	    # The server generates this broken log format for request and return
	    # code when the request is invalid.  Usually, the agent is a worm in
	    # this case.  -- rgr, 4-Aug-01.
	    push(@result, '', 400);
	}
	elsif ($line =~ /\G\[([^][]*)\] /gc) {
	    push(@result, $1);
	}
	elsif ($line =~ /\G([^ ]*) /gc) {
	    push(@result, $1);
	}
	else {
	    die("$warn:  Can't match '$line'\n  [result is (",
		join(', ', @result), ") elts]\n");
	}
    }
    @result;
}

sub tally {
    # Count the page, plus totals for the parent directories.
    my $page = shift;
    my @components;

    $hits{$page}++;
    @components = split('/', $page);
    pop(@components);	# since we've already incremented it.
    while (@components) {
	my $dir = join('/', @components, '');
	last if $dir eq 'http://';
	$total_hits{$dir}++;
	pop(@components);
    }
}

# print "\$skip_errors_p is $skip_errors_p.\n";
### Main loop.
my $line;
while (defined($line = <>)) {
    chomp($line);
    my ($ip, $ignore1, $ignore2, $date, $request,
	$return_code, $return_length, $referer, $user_agent)
	= split_access_log_line($line);
    $return_codes{$return_code}++;
    next if $skip_address_p{$ip};
    next if $skip_errors_p && $return_code >= 400;
    # Some of these are malformed, so we need to parse the request line.
    if ($request =~ /^(GET|HEAD|POST) +([^ ]+) +HTTP/) {
	# my $method = $1; 
	my $page = $2;
	tally($page);
	print(join("\t", $date, host_ip_and_name($ip), $page), "\n")
	    if $verbose_p;
    }
    else {
	# [too verbose.  -- rgr, 4-Aug-01.]
	# warn "$warn:  Malformatted request at line $.\n";
    }
}

# Print summary results
if ($print_page_totals_p) {
    # sort output descending by number of hits.
    open(OUT, "| sort -k 2 -nr") or die;
    foreach my $page (sort(keys(%hits))) {
	print OUT (join("\t", $page, $hits{$page}), "\n");
    }
    close(OUT);
    print "\n";
}
if ($print_summary_p) {
    print "Totals:\n";
    foreach my $page (sort(keys(%total_hits))) {
	print(join("\t", $page, $total_hits{$page}), "\n");
    }
    foreach my $code (sort(keys(%return_codes))) {
	print("Code $code for $return_codes{$code} hits.\n");
    }
}
