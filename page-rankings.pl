#!/usr/bin/perl -w
#
#    Generates a page of the most popular pages/directories on the site.
#
# [created.  -- rgr, 14-Feb-03.]
#
# $Id$

use strict;
use Getopt::Long;

my $warn = 'make-popular-pages.pl';

my $squid_format_p = 1;
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
    or die("usage:  $warn [ --[no]squid ] [ --[no]html ] ",
	   "[ --[no]robots ] log_file_name\n");

my $log_name = shift(@ARGV);
die "$warn:  '$log_name' is not readable:  $!\n"
    unless -r $log_name;
my $log_pipe
    = join(' | ', 
	   "fgrep -v 192.168.57. $log_name ",
	   "fgrep -v 24.34.108.24",
	   ($squid_format_p ? "fgrep -v 66.31.124.111 | squid2std.pl" : ()),
	   "page-hits.pl -page-totals");
warn "[got log pipe '$log_pipe']\n"
    if $verbose_p;
open(LOG, "$log_pipe |")
    or die;

my $pages = '';		# contains popular page hits.
my $n = 0;
my $line;
while ($n < $n_top_hits && ($line = <LOG>)) {
    chomp($line);
    my ($page, $hits) = split("\t", $line);
    my $excluded_p = $excluded_pages{$page} || 0;
    # last if $excluded_p eq 'last';
    next
	if $excluded_p;
    $n++;
    if ($html_format_p) {
	$pages .= join("\n    ",
		       "  <tr> <td align='right'>$n</td>",
		       "<td> <a href='$page'><tt>$page</tt></a></td>",
		       "<td align='right'> $hits</td>\n  </tr>\n");
    }
    else {
	print join("\t", $hits, $page), "\n";
    }
}
close(LOG);
exit(0)
    if ! $html_format_p;
print <<EOF1
<h3>Most popular pages</h3>

<blockquote>
<table cellpadding="2">
  <tr> <th>Rank</th> <th>Page URL</th> <th>Hits</th></tr>
$pages
</table>
</blockquote>
EOF1
    ;
