#!/usr/bin/perl -w
#
#    Given a series of log files, generates a period-by-period table of hits.
#
# [created.  -- rgr, 14-Feb-03.]
#
# $Id$

use strict;
use Getopt::Long;

my $squid_format_p = 0;
my $html_format_p = 1;
my $verbose_p = 0;
my $robots_p = 0;
# [this is my definition of "popular."  -- rgr, 14-Feb-03.]
my %excluded_pages = ('/site.css' => 1,
		      '/random/doubleclick.png' => 1,
		      '/linux/striped-blue.png' => 1,
		      '/linux/striped-green.png' => 1,
		      '/linux/striped-brown.png' => 1,
		      '/linux/striped-orange.png' => 1,
		      '/bob/resume.html' => 'last',
		      '/robots.txt' => 1);
my $n_top_hits = 10;

GetOptions(# 'help' => \$help, 'man' => \$man, 
	   'verbose+' => \$verbose_p,
	   'top=i' => \$n_top_hits,
	   'squid!' => \$squid_format_p,
	   'html!' => \$html_format_p,
	   'robots!' => \$robots_p)
    or die("usage:  $0 [ --[no]squid ] [ --[no]html ] ",
	   "[ --[no]robots ] log_file_name ...\n");

# the first file is the one that generates the rankings.
my $log_index = 0;
my %page_entries;
my @most_popular;
my $other_entry = [ 'Other hits:' ];
my $total_entry = [ 'Monthly total hits:' ];
for my $log_name (@ARGV) {
    die "$0:  '$log_name' is not readable:  $!\n"
	unless -r $log_name;
    $log_index++;
    my $log_pipe
	= join(' | ', 
	       "fgrep -v 192.168.57. $log_name ",
	       "fgrep -v 24.34.108.24",
	       ($squid_format_p ? "fgrep -v 66.31.124.111 | squid2std.pl" : ()),
	       "page-hits.pl -page-totals -no-summary");
    warn "[got log pipe '$log_pipe']\n"
	if $verbose_p;
    open(LOG, "$log_pipe |")
	or die;

    my $line;
    my $rank = 0;
    my $total_hits = 0;
    my $other_hits = 0;
    while ($line = <LOG>) {
	last
	    if $line =~ /^Totals:/;
	chomp($line);
	my ($page, $hits) = split("\t", $line);
	next
	    unless $page;
	my $excluded_p = $excluded_pages{$page} || 0;
	next
	    # Don't even count these in "other hits."
	    if $excluded_p;
	$rank++;
	my $entry = $page_entries{$page};
	$entry = $page_entries{$page} = [ $page ]
	    unless $entry;
	$entry->[2*$log_index-1] = $rank;
	$entry->[2*$log_index] = $hits;
	$total_hits += $hits;
	$other_hits += $hits
	    unless defined($entry->[1]) && $entry->[1] <= $n_top_hits;
	push(@most_popular, $entry)
	    if $log_index == 1;
    }
    # make 'other' and 'totals' entries for this file.
    $other_entry->[2*$log_index-1] = '&nbsp;';
    $other_entry->[2*$log_index] = $other_hits;
    $total_entry->[2*$log_index-1] = '&nbsp;';
    $total_entry->[2*$log_index] = $total_hits;
    close(LOG);
}

for my $entry (@most_popular[0..$n_top_hits-1], $other_entry, $total_entry) {
    my $page = $entry->[0];
    if ($html_format_p) {
	my $link = ($page =~ /:/
		    ? $page
		    : "<a href='$page'><tt>$page</tt></a>");
	print("  <tr> <td>$link</td>\n");
	for my $i (1..$log_index) {
	    my $rank = $entry->[2*$i-1] || '--';
	    my $hits = $entry->[2*$i] || '&nbsp;';
	    print("    <td align='right'>$rank</td>\n",
		  "    <td align='right'>$hits</td>\n");
	}
	print("  </tr>\n");
    }
    else {
	print(join("\t", map { $_ || ''; } @$entry), "\n");
    }
}
