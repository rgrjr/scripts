#!/usr/bin/perl -w
#
#    Generates a page of the most popular pages/directories on the site.
#
#    Modification history:
#
# created.  -- rgr, 14-Feb-03.
# --[no]squid and --[no]html switches.  -- rgr, 2-Apr-03.
#

use strict;
use Getopt::Long;

my $warn = 'make-popular-pages.pl';

my $squid_format_p = 1;
my $html_format_p = 1;
my $robots_p = 0;
# [this is my definition of "popular."  -- rgr, 14-Feb-03.]
my %excluded_pages = ('/site.css' => 1,
		      '/random/doubleclick.png' => 1,
		      '/bob/resume.html' => 'last',
		      '/robots.txt' => 1);

GetOptions(# 'help' => \$help, 'man' => \$man, 'verbose+' => \$verbose_p,
	   'squid!' => \$squid_format_p,
	   'html!' => \$html_format_p,
	   'robots!' => \$robots_p)
    or die("usage:  $warn [ --[no]squid ] [ --[no]html ] ",
	   "[ --[no]robots ] log_file_name\n");

my $log_name = shift(@ARGV);
die "$warn:  '$log_name' is not readable:  $!\n"
    unless -r $log_name;
open(LOG,
     "fgrep -v 192.168.57. $log_name "
     .($squid_format_p ? "| fgrep -v 66.31.124.111 | squid2std.pl " : '')
     ."| page-hits.pl -page-totals |")
    or die;

my $pages = '';		# contains popular page hits.
my $n = 0;
my $line;
while ($n < 10 && ($line = <LOG>)) {
    chomp($line);
    my ($page, $hits) = split("\t", $line);
    my $excluded_p = $excluded_pages{$page} || 0;
    last
	if $excluded_p eq 'last';
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
