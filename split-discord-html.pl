#!/usr/bin/perl
#
# Split an HTML Discord direct messaging conversation into smaller chunks.
#
# [created.  -- rgr, 23-Dec-20.]
#

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use Date::Parse;
use Date::Format;

# This is because we add a little after the end.
use constant MAX_SIZE_FUZZ => 160;

use constant SECS_PER_DAY => 24 * 3600;

### Get command-line options.

my $compress_p = 1;
my $usage = 0;
my $help = 0;
my $man = 0;
my $max_chunk_size = 25;
GetOptions('help' => \$help, 'man' => \$man, 'usage' => \$usage,
	   'size=f' => \$max_chunk_size,
	   'compress!' => \$compress_p)
    or pod2usage(2);
pod2usage(2) if $usage;
pod2usage(1) if $help;
pod2usage(-exitstatus => 0, -verbose => 2) if $man;
my $file_name = shift(@ARGV)
    or pod2usage("$0:  Need an HTML file name on the command line.");
pod2usage("$0:  Too many arguments.")
    if @ARGV;
$max_chunk_size = int($max_chunk_size * 1024 * 1024);
my $html_preamble = '';
my ($chunk, @chunks);

### Subroutines.

my ($n_total_messages, $n_total_groups, $n_groups, $n_messages) = (0, 0, 0, 0);
sub read_group {
    # Given an input stream and the first line of a message group, read in the
    # complete message group, returning it as a single string, followed by its
    # parsed time and the next line from the file.
    my ($in, $line) = @_;

    my $group = $line;
    my $time;
    while (defined($line = <$in>)) {
	next
	    if $compress_p && ($line eq "\n" || $line eq "\r\n");
	$group .= $line;
	last
	    if $line =~ m@^</div>@;
	$time = str2time($1)
	    if $line =~ m@<span class="chatlog__timestamp">(.*)</span>@;
	$n_messages++
	    if $line =~ /<div class="chatlog__message "/;
    }
    $n_groups++;

    # Skip to the next nonblank line.
    while (defined($line = <$in>)) {
	last
	    unless $line eq "\n" || $line eq "\r\n";
	$group .= $line
	    unless $compress_p;
    }
    return ($group, $time, $line);
}

sub read_day {
    # Similar to read_group, given an input stream, a message group (possibly
    # undef) and its time, and the first line of the following message group,
    # read in a series of message groups that are all on the same day,
    # returning it as a single string, followed by the parsed time of its first
    # message group, the next message group (if any) and its parsed time, and
    # the next input line from the file.
    my ($in, $group, $time, $line) = @_;

    ($group, $time, $line) = read_group($in, $line)
	unless $group;
    return
	unless $group;
    my $day = $group;
    (my $next_group, my $next_time, $line) = read_group($in, $line);
    while ($next_group
	   && int($time / SECS_PER_DAY) == int($next_time / SECS_PER_DAY)) {
	$day .= $next_group;
	($next_group, $next_time, $line) = read_group($in, $line);
    }
    return ($day, $time, $next_group, $next_time, $line);
}

sub finish_chunk {
    # Close out this chunk and reset for the next one.
    my ($next_chunk) = @_;

    # Finish output.
    my $out = $chunk->chunk_out;
    print $out "</div>\n\n";	# close the "chatlog" division.
    print $out <<POSTAMBLE;
<div class="postamble">
    <div class="postamble__entry">$n_messages messages in $n_groups message groups in this chunk.</div>
</div>

POSTAMBLE

    # Update totals.
    $chunk->n_messages($n_messages);
    $chunk->n_groups($n_groups);
    $n_total_groups += $n_groups;
    $n_total_messages += $n_messages;
    $n_messages = $n_groups = 0;

    # End the file.
    print $out "</body>\n</html>\n";
    close($out);
    $chunk->chunk_out(undef);
    undef($chunk);
}

sub add_content_to_chunk {
    # Add $content to the end of the current chunk, starting a new chunk if it
    # is too long.
    my ($content, $time) = @_;

    # First, see if we need to start a new chunk.
    my ($chunk_name, $new_chunk);
    if (! $chunk
	|| $chunk->chunk_len + length($content) + MAX_SIZE_FUZZ
	    > $max_chunk_size) {
	$chunk_name = $file_name;
	$chunk_name =~ s/[.]html$//i;
	$chunk_name .= time2str('-%Y-%m-%d.html', $time);
	$new_chunk = DiscordChunkFile->new
	    (chunk_file_name => $chunk_name, chunk_len => 0,
	     first_time => $time, last_time => $time);
	push(@chunks, $new_chunk);
	finish_chunk($new_chunk)
	    if $chunk;
    }

    # Start the new chunk.
    if (! $chunk) {
	open(my $out, '>', $chunk_name)
	    or die("$0:  Could not open '$chunk_name' for writing:  $!");
	$chunk = $new_chunk;
	$chunk->chunk_out($out);
	print $out $html_preamble;
	$chunk->chunk_len(length($html_preamble));
    }

    # Add the new content.
    my $out = $chunk->chunk_out;
    print $out $content;
    $chunk->last_time($time);
    $chunk->chunk_len($chunk->chunk_len + length($content));
}

### Main program.

# The file consists of minimal <!DOCTYPE> and <html> tags, a long <head>
# section, and a <body>.  The <body> has the following structure:
#
#    <body>
#    <div class="preamble">
#    </div>
#    <div class="chatlog">
#    <div class="chatlog__message-group">
#        <div class="chatlog__author-avatar-container">
#        </div>
#        <div class="chatlog__messages">
#          <span class="chatlog__timestamp"> ... </span>
#          <div class="chatlog__message " . . .>
#            <div class="chatlog__content">
#            </div>
#          </div>
#          . . .
#        </div>
#    </div>
#    . . .
#    </div>
#    <div class="postamble">
#    </div>
#    </body>
#
# The "<body>", "</body>", and all "<div>" and "</div>" tags aligned with them
# start in the first column; the others are indented to various degrees.  The
# HTML is also generously larded with blank lines that are not shown.  Each
# chatlog__message-group is from a single author at a single time, and each
# chatlog__message consists of text from a single transmission.  There may be
# other things besides chatlog__content inside the message container.  We are
# mostly interested in processing whole chatlog__message-group divisions and
# extracting dates so we can avoid splitting a conversation in the middle of a
# day.
#
# The postamble is literally just this:
#
#	<div class="postamble">
#	    <div class="postamble__entry">Exported 464 message(s)</div>
#	</div>
#
# So we just generate a new one when we finish a chunk, and ignore it on input.
# (It could serve as end-of-file when we see it on input, but the isolated
# "</div>" for the all-encompassing "chatlog" serves that purpose.)
#

open(my $in, '<', $file_name)
    or die "$0:  Can't open '$file_name' for reading:  $!";

# Scarf the preamble.
while (<$in>) {
    next
	if $compress_p && ($_ eq "\n" || $_ eq "\r\n");
    last
	if /class="chatlog__message-group"/;
    $html_preamble .= $_;
}
die "$0:  No content.\n"
    unless $_;
# Sanity check.
die "$0:  The --size parameter is too small.\n"
    unless 2 * length($html_preamble) < $max_chunk_size;

# Process the body of the file by chunks.
my ($day, $time, $next_group, $next_time, $next_line)
    = read_day($in, undef, undef, $_);
# If $next_line is "</div>" then that is the end of the "chatlog" division, and
# we're about to hit end-of-file.
while ($next_line && $next_line ne "</div>\n") {
    add_content_to_chunk($day, $time);
    ($day, $time, $next_group, $next_time, $next_line)
	= read_day($in, $next_group, $next_time, $next_line);
}
add_content_to_chunk($day, $time)
    if $day;
finish_chunk();

# Write the index file.
{
    my $index_name = $file_name;
    $index_name =~ s/[.]html$//i;
    $index_name .= '-index.html';
    open(my $out, '>', $index_name)
	or die("$0:  Could not open '$index_name' for writing:  $!");
    print $out $html_preamble;
    print $out "<ul>\n";
    for my $chunk (@chunks) {
	print $out $chunk->make_index_line();
    }
    print $out "</ul>\n";
    print $out ("<p>Total of $n_total_messages messages ",
		"in $n_total_groups message groups.</p>\n");
    print $out "</body>\n</html>\n";
}

### ======================================================================

package DiscordChunkFile;

use strict;
use warnings;

use Date::Format;

# Class for recording chunk file information for later disgorging into the
# index file.

BEGIN {
    no strict 'refs';
    for my $method (qw{chunk_file_name chunk_out chunk_len},
		    qw{first_time last_time n_messages n_groups}) {
	my $field = '_' . $method;
	my $full_method_name = 'DiscordChunkFile::'.$method;
	*$full_method_name = sub {
	    my $self = shift;
	    @_ ? ($self->{$field} = shift) : $self->{$field};
	}
    }
}

sub new {
    my $class = shift;

    my $self = bless({}, $class);
    while (@_) {
	my $method = shift;
	my $argument = shift;
	$self->$method($argument);
    }
    $self;
}

sub make_index_line {
    my ($self) = @_;

    my $chunk_file_name = $self->chunk_file_name;
    my $start = time2str('%Y-%m-%d', $self->first_time);
    my $end = time2str('%Y-%m-%d', $self->last_time);
    my $n_messages = $self->n_messages;
    my $n_groups = $self->n_groups;
    return join(' ', "  <li> <a href='$chunk_file_name' ",
		"title='$n_messages messages in $n_groups message groups'>",
		"From $start through $end</a></li>\n");
}

__END__

=head1 NAME

split-discord-html.pl -- split a Discord direct messaging HTML log file

=head1 SYNOPSIS

    split-discord-html.pl [ --help ] [ --man ] [ --usage ]
		[ --size=<megabytes-per-file> ] [ --[no]compress ]

where:

    Parameter Name     Deflt  Explanation
     --compress         yes   Whether to remove empty lines.
     --help                   Print detailed help.
     --man                    Print man page.
     --size             25    Max chunk file size in megabytes
     --usage                  Print this synopsis.

=head1 DESCRIPTION

This script takes the name of a single large HTML file that is the
output of a Discord direct messaging log.  These can cover many years,
and add up to hundreds of megabytes, which strains the resources of
even then most capable computer/browser combinations.  This script
splits up the file into smaller files that are named with the original
file name and the date of the first message, plus an index file that
links to them all displaying start/end dates.  The maximum size of the
smaller files is selectable with the C<--size> option and defaults to
25MiB.

Fortunately, all other media (images, videos, avatar icons, etc.) are
hosted separately, so this script only needs to deal with HTML.  As
long as the files it produces are hosted together in the same
directory, they will continue to reference each other and the external
media exactly as well as the original file does.

=head1 OPTIONS

As with all other C<Getopt::Long> scripts, option names can be
abbreviated to anything long enough to be unambiguous (e.g. C<--sli>
or C<--sl> for C<--slices>), options with arguments can be given as
two words (e.g. C<--prefix home>) or in one word separated by an "="
(e.g. C<--prefix=home>), and "-" can be used instead of "--".

=over 4

=item B<--compress>

=item B<--nocompress>

Specifies whether to omit blank HTML lines.  The default is
C<--compress> (even though this is useful mostly for debugging).

=item B<--help>

Prints the L<"SYNOPSIS"> and L<"OPTIONS"> sections of this documentation.

=item B<--man>

Prints the full documentation in the Unix `manpage' style.

=item B<--size>

Specifies the maximum size of each HTML "chunk" file, in MiB (1048576
bytes).  Each such file will be slightly smaller than the specified
maximum, in order to avoid breaking a day's chat between two files,
and the total size of all files will be somewhat larger than the input
file due to the need to repeat the header information in each file.

=item B<--usage>

Prints just the L<"SYNOPSIS"> section of this documentation.

=back

=head1 EXAMPLES

Given the following initial directory contents:

    > ls -l test*
    -rw-r--r-- 1 rogers users 369572 12-22 22:52 test.html
    > 

We can split test.html into approximately 100K chunks with the
following command:

    > perl split-discord-html.pl test.html --size 0.1
    > ls -l test*
    -rw-r--r-- 1 rogers users 100483 12-24 15:24 test-2019-10-14.html
    -rw-r--r-- 1 rogers users 103225 12-24 15:24 test-2020-03-24.html
    -rw-r--r-- 1 rogers users 101784 12-24 15:24 test-2020-05-04.html
    -rw-r--r-- 1 rogers users  94362 12-24 15:24 test-2020-06-11.html
    -rw-r--r-- 1 rogers users 369572 12-22 22:52 test.html
    -rw-r--r-- 1 rogers users  12049 12-24 15:24 test-index.html
    > 

Note that C<split-discord-html.pl> expects its inpupt file to have a
".html" extension; if not, the output files will not be so nicely
named.

=head1 BUGS

If you find any, please let me know.

=head1 SEE ALSO

=over 4

=item L<https://discord.com/>

=back

=head1 AUTHOR

Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>

=head1 COPYRIGHT

Copyright (C) 2020 by Bob Rogers C<E<lt> rogers@rgrjr.com E<gt>>.
This script is free software; you may redistribute it
and/or modify it under the same terms as Perl itself.

=cut
