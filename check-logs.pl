#!/usr/bin/perl -w
#
# Hack to look over the log files.  Do (e.g.)
#
#     check-logs.pl messages.4 messages.3 messages.2 messages.1 messages
#
# in /var/log to do the standard grovel in chronological order.  Or
#
#     check-logs.pl -from 'May 25' -ignore smtp/tcp messages
#
# as another example.
#
#    [old] Modification history:
#
# created.  -- rgr, 13-Feb-00.
# added host_ip_and_name lookup.  -- rgr, 26-Feb-00.
# generalized for messages from other modules/subsystems.  -- rgr, 4-Mar-00.
# ignored messages (doesn't work well yet), 'floppy' module.  -- rgr, 23-Mar-00.
# ignore identd, handle UDP and other protocols.  -- rgr, 6-Apr-00.
# -from arg, pretty port/proto names.  -- rgr, 16-Apr-00.
# -ignore and -report args.  -- rgr, 29-May-00.
# slight %ignored_lines improvement (still v. WSP sensitive).  -- rgr, 7-Oct-00.
# hacked name of port 27374.  -- rgr, 24-Oct-00.
# basic broadcast detection & reporting.  -- rgr, 14-Jan-01.
# accept -n as a synonym for -nodns.  -- rgr, 29-Apr-01.
# Ignore mount/unmount requests from hal.  -- rgr, 18-Aug-01.
# make local network more fluid.  -- rgr, 4-Oct-01.
# initialize_local_addresses: generalized local addr check, include old public
#	addresses for use with old files.  -- rgr, 8-Nov-01.
# initialize_local_addresses: work around pipe flakiness.  -- rgr, 9-Nov-01.
# ignore web/smtp, improve -ignore syntax, cache DNS misses.  -- rgr, 1-Jul-02.
#
# $Id$

use strict;
use Socket;	# for inet_aton

my $nominal_file_directory	# where to look for nominal-*.text files
    = (-r '/root/bin' ? '/root/bin/' : '');

chomp(my $host_name = `hostname`);
$host_name =~ s/\..*//;
my $use_dns_names_p = 1;
my $use_etc_services_p = 0;		# [not a parameter.  -- rgr, 5-Aug-03.]
my $from_date_string = '';		# optional starting date string

# [need a command line interface for this.  -- rgr, 4-Mar-00.]
my %standard_module_dispositions =
    ('pumpd' => 'report',
     'PAM_pwdb' => 'report',
     'named' => 'ignore',
     'identd' => 'ignore',	# got tired of seeing these.  -- rgr, 6-Apr-00.
     'kernel' => 'report',
     # i get tons of errors labelled this way if I try to format a floppy bigger
     # than the hardware/media support.  -- rgr, 23-Mar-00.
     'floppy0' => 'ignore',
     'end_request' => 'ignore',
     # mail is not really interesting, and i have better ways of keeping track
     # of web hits.  -- rgr, 1-Jul-02.
     'smtp/tcp' => 'ignore',
     'www/tcp' => 'ignore',
     # better safe than sorry.
     'default' => 'report');

### Process arguments.
while (@ARGV && $ARGV[0] =~ /^-./) {
    my $arg = shift(@ARGV);
    if ($arg eq '-nodns' || $arg eq '-n') {
	$use_dns_names_p = 0;
    }
    elsif ($arg =~ /^-(ignore|report)($|=)/) {
	my $disposition = $1;
	my $modules = ($2 ? $' : shift(@ARGV));
	foreach my $module (split(',', $modules)) {
	    $standard_module_dispositions{$module} = $disposition;
	}
    }
    elsif ($arg eq '-from') {
	$from_date_string = shift(@ARGV);
    }
    else {
	die "check-logs.pl:  Unknown option '$arg'; died";
    }
}

### Subroutines.

my %local_ip_address_p;
sub initialize_local_addresses {
    my ($line);

    # also preload some recent addresses we have used.  this is intended for use
    # with old log files.
    $local_ip_address_p{'24.218.161.12'} = 100;
    $local_ip_address_p{'66.31.124.64'} = 100;
    $local_ip_address_p{'66.31.87.164'} = 100;
    if (! open(IFC, "/sbin/ifconfig |")) {
	warn "check-logs.pl: couldn't open pipe from ifconfig:  $!\n";
	return 0;
    }
    while (defined($line = <IFC>)) {
	$local_ip_address_p{$1}++
	    if $line =~ /inet addr: *([\d.]+)/;
    }
    close(IFC);
}

my %ip_to_host_name_cache;
sub nslookup_ptr {
    my $ip = shift;

    if (defined($ip_to_host_name_cache{$ip})) {
	$ip_to_host_name_cache{$ip};
    }
    else {
	my ($name) = gethostbyaddr(inet_aton($ip), AF_INET);
	$ip_to_host_name_cache{$ip} = $name || '';
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
	# 192.168.\d+.1 gets mapped to rgr.rgrjr.com by /etc/hosts, which might
	# be legitimate if we knew the connection was coming from the internal
	# interface.  Since we've lost that information by this point, always
	# use the numeric address.  -- rgr, 16-Apr-00.
	"[$ip]";
    }
    elsif ($name = nslookup_ptr($ip)) {
	"$name ($ip)";
    }
    else {
	"[$ip]";
    }
}

my %port_proto_to_service_map;
sub read_port_proto_to_service_map {
    # Read and parse /etc/services in order to build a table of "port/protocol"
    # to service name in the %port_proto_to_service_map hash.
    my ($line, $service, $port_proto);

    open(SVC, "/etc/services") || die;	# this would be really broken.
    while (defined($line = <SVC>)) {
	$line =~ s/#.*//;
	($service, $port_proto) = split(' ', $line);
	if (defined($service) && defined($port_proto)) {
	    $port_proto_to_service_map{$port_proto} = $service;
	}
    }
    # [complete and total kludge.  this is because a popular trojan, known as
    # "sub 7", has usurped this port.  so calling it "asp" is misleading.  --
    # rgr, 24-Oct-00.]  -- rgr, 24-Oct-00.]
    foreach my $medium ('tcp', 'udp') {
	my $svc = $port_proto_to_service_map{"27374/$medium"};
	undef($port_proto_to_service_map{"27374/$medium"})
	    if $svc && $svc eq 'asp';
    }
    close(SVC);
}

sub pretty_port_proto {
    # If a symbolic name exists for the passed port/protocol combination, which
    # should be a string that looks like "25/tcp", return it, e.g. as
    # "smtp/tcp".  We keep the protocol qualification as part of the pretty name
    # because /etc/services is overly broad, assigning the given name to both
    # TCP and UDP.  Here is a quote from the top of the file:
    #
    #	Note that it is presently the policy of IANA to assign a single
    #	well-known port number for both TCP and UDP; hence, most entries here
    #	have two entries even if the protocol doesn't support UDP operations.
    #
    # Besides avoiding the ambiguity that would be introduced if we dropped the
    # protocol tag, it would be unusual -- and therefore interesting and
    # noteworthy -- for someone to try to connect using the "wrong" protocol, so
    # we want to be able to see it.  -- rgr, 16-Apr-00.
    my $port_proto = shift;
    my $result = $port_proto;	# default

    read_port_proto_to_service_map()
	if $use_etc_services_p && ! %port_proto_to_service_map;
    my $pretty_name = $port_proto_to_service_map{lc($port_proto)};
    if (defined($pretty_name)) {
	my ($port, $proto) = split('/', $port_proto);
	$result = "$pretty_name/$proto";
    }
    $result;
}

my $todays_heading_printed_p = '';
sub day_print {
    # generate the day's heading, if not already done.
    my ($day, $line) = @_;

    unless ($day eq $todays_heading_printed_p) {
	print "\n$day:\n";
	$todays_heading_printed_p = $day;
    }
    print $line
	if $line;
}

my %attempts;
my %broadcasts;
my %filtered_source_ip_totals;
my %source_ip_totals;
my %dest_port_totals;
sub day_report {
    # Generate this day's report of internet connection attempts from the
    # %attempts hash, sorted by source host, port/protocol, and disposition, and
    # filtered on port/protocol, updating the %filtered_source_ip_totals hash in
    # the process.  Finally, clear the %attempts hash on completion.
    my $day = shift;
    my $report_string = '';
    my $printed_host_p = 0;
    my $report;

    $report = sub {
	# Print the string as a detail line (or series of lines, generating a
	# header if needed.
	my $string = shift;

	return 0
	    unless $string;
	day_print($day, "  Network host summaries:\n")
	    unless $printed_host_p;
	$printed_host_p++;
	print $string;
    };

    foreach my $source_ip (sort(keys(%attempts))) {
	$report_string = '';
	foreach my $dest_port (sort { $a cmp $b }
			       keys(%{$attempts{$source_ip}})) {
	    my $disp = $standard_module_dispositions{$dest_port};
	    next
		if $disp && $disp eq 'ignore';
	    my $pretty_dest_port = pretty_port_proto($dest_port);
	    $disp = $standard_module_dispositions{$pretty_dest_port};
	    next
		if $disp && $disp eq 'ignore';
	    foreach my $disposition 
		    (sort(keys(%{$attempts{$source_ip}{$dest_port}}))) {
		my $count = $attempts{$source_ip}{$dest_port}{$disposition};
		my $bcasts = $broadcasts{$source_ip}{$dest_port}{$disposition};
		$filtered_source_ip_totals{$source_ip} += $count;
		$report_string
		    .= ("      $pretty_dest_port"
			. " ($count "
			. ($bcasts ? "broadcast " : "")
			. "attempts, disp $disposition)\n");
	    }
	}
	&$report("    From " . host_ip_and_name($source_ip) . "\n"
		 . $report_string)
	    if $report_string;
    }
    # reset.
    %attempts = ();
    $printed_host_p;
}

my %module_messages;
sub parse_firewall_log_event { 
    use strict;
    # given a description (part of a log line), parse it into a hash.
    my $description = shift;
    my %hash;

    if ($description =~ /(\S+) (\S+) (\S+) PROTO=(\d+) ([\d.]+):(\d+) ([\d.]+):(\d+)/) {
	# ipchains log format (2.2 kernels).
	$hash{FORMAT} = 'ipchains';
	my ($chain, $disposition, $interface, $protocol,
	    $source_ip, $source_port, $dest_ip, $dest_port) 
	    = $description =~ //;
	# [we used to check "unless $protocol == 6 && $dest_ip ==
	# $local_host_ip;", but mediaone changed our address.  -- rgr,
	# 26-Feb-00.]  [kludge -- should use /etc/protocols instead.  --
	# rgr, 29-May-00.]
	if ($protocol == 6) {
	    $protocol = 'tcp';
	}
	elsif ($protocol == 17) {
	    $protocol = 'udp';
	}
	else {
	    warn("Odd protocol value:  $description\n");
	}
	# Record.  In order, iptables fields are "IN OUT MAC SRC DST LEN TOS
	# PREC TTL ID PROTO SPT DPT LEN".
	$hash{CHAIN} = $chain;
	$hash{DISP} = $disposition;
	$hash{IN} = $hash{OUT} = $interface;
	$hash{PROTO} = $protocol;
	$hash{SRC} = $source_ip;
	$hash{SPT} = $source_port;
	$hash{DST} = $dest_ip;
	$hash{DPT} = $dest_port;
    }
    elsif ($description =~ /^IN=\S* OUT=\S* MAC=/) {
	# iptables; call it ipchains for simplicity.
	%hash = map {
	    my @stuff = split(/=/, $_, 2);
	    ($stuff[0], $stuff[1] || '');
	} split(' ', $description);
	$hash{DISP} = 'REJECT';
	$hash{FORMAT} = 'iptables';
    }
    else {
	# couldn't parse.
	$hash{FORMAT} = 'unknown';
    }
    %hash;
}

### Initialize shutdown/startup ignored messages, local IP addresses.
initialize_local_addresses();
my %ignored_lines;
foreach my $file ('nominal-shutdown.text', 'nominal-startup.text',
		  'nominal-random.text') {
    if (open(FILE, $nominal_file_directory.$file)) {
	my $line;
	while ($line = <FILE>) {
	    chomp($line);
	    $ignored_lines{$line}++;
	}
	close(FILE);
    }
}

### Main loop.
my $previous_day = '';
my $line;
my $day;
while (defined($line = <>)) {
    chomp($line);
    # $report_p = 0;
    next
	unless $line =~ / +($host_name|h0050da615e79) +/o;
    my $date = $`;  
    my $description = $';
    if ($from_date_string) {
	# bogus date testing, should be good enough if all you want is "Apr 16".
	# -- rgr, 16-Apr-00.
	next
	    if $from_date_string ne substr($date, 0, length($from_date_string));
	# OK, we've hit the start date.
	$from_date_string = '';
    }
    # check for quick win.
    next if $ignored_lines{$description};
    $day = substr($date, 0, 6);
    my $time = substr($date, 7);
    if ($day ne $previous_day) {
	day_report($previous_day)
	    unless $previous_day eq '';
	$previous_day = $day;
    }
    # try to figure out what's reporting.  some modules (e.g. syslogd) have a
    # space and a version number after them, and others (e.g. pumpd, named) have
    # the pid in square brackets.  -- rgr, 4-Mar-00.  [the "." is necessary to
    # match (e.g.) rpc.statd.  -- rgr, 7-Oct-00.]
    my $reporting_module = 'other';
    if ($description =~ m@^([\w\d/.]+)(\[\d+\]| [-.\d]+)?: +@g) {
	$reporting_module = $1;
	$description = substr($description, pos($description));
	$reporting_module =~ s@.*/@@;
	# give the %ignored_lines hash one more try with the newly standardized
	# reporting module name (minus possible pid/version number).
	next if $ignored_lines{"$reporting_module: $description"};
	$module_messages{$reporting_module}++;
	if ($reporting_module eq 'kernel') {
	    # Try to find a better 'module' for kernel messages.
	    if ($description =~ /^Packet log: */) {
		# there are lots of these and they are important, so we
		# reclassify them as 'ipchains' messages, even though that is
		# not strictly correct.
		$reporting_module = 'ipchains';
		$description = $';
	    }
	    elsif ($description =~ /^([\w\d_]+): */) {
		# reclassify.
		$reporting_module = $1;
		$description = $';
	    }
	}
    }
    # find disposition.
    my $disp = $standard_module_dispositions{$reporting_module};
    $disp = $standard_module_dispositions{'default'} || 'unknown'
        unless defined($disp);
    next if $disp eq 'ignore';
    if ($description =~ /^IN=\S* OUT=\S* MAC=/) {
	# iptables; call it ipchains for simplicity.
	$reporting_module = 'ipchains';
    }
    # look for events of particular interest.
    if ($reporting_module eq 'ipchains') {
	# use strict;
	my %hash = parse_firewall_log_event($description);
	# ($chain, $disposition, $interface, $protocol,
	#  $source_ip, $source_port, $dest_ip, $dest_port);
	if ($hash{FORMAT} ne 'unknown') {
	    my $protocol = $hash{PROTO};
	    my $source_ip = $hash{SRC};
	    my $dest_ip = $hash{DST};
	    my $dest_port = $hash{DPT};
	    my $dest_port_proto 
		= ($dest_port ? "$dest_port/$protocol" : "proto=$protocol");
	    my $disposition = $hash{DISP};
	    # Record.
	    $source_ip_totals{$source_ip}++;
	    $dest_port_totals{$dest_port_proto}++;
	    $attempts{$source_ip}{$dest_port_proto}{$disposition}++;
	    $broadcasts{$source_ip}{$dest_port_proto}{$disposition}++
		if ! $local_ip_address_p{$dest_ip};
	    # mark as done.
	    $disp = 'ignore';
	}
	else {
	    # couldn't parse.
	    $disp = 'unknown';
	}
    }
    # Handle leftovers.
    if ($disp eq 'report') {
	day_print($day, "  $time: $reporting_module: $description\n");
    }
    elsif ($disp eq 'unknown') {
	day_print($day, "  Couldn't recognize:  $line\n");
    }
}
# flush any pending.
day_report($day);
# report totals
print "\nMessage totals (unfiltered):\n";
foreach my $reporting_module (sort(keys(%module_messages))) {
    print "  $module_messages{$reporting_module} from $reporting_module\n";
}
print "\nIP host totals:\n";
foreach my $source_ip (keys(%source_ip_totals)) {
    my $raw_count = 0 + $source_ip_totals{$source_ip};
    my $filtered_count = 0 + $filtered_source_ip_totals{$source_ip};
    print("  ", host_ip_and_name($source_ip),
	  ($raw_count == $filtered_count
	   ? " ($raw_count connects)\n"
	   : " ($filtered_count/$raw_count connects)\n"));
}
print "\nDestination port totals:\n";
foreach my $dest_port (sort { $a cmp $b } keys(%dest_port_totals)) {
    print("  ", pretty_port_proto($dest_port),
	  " ($dest_port_totals{$dest_port} connects)\n");
}
