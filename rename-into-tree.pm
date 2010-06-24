# Quickie subroutine to do renames, handling the directory-to-directory case by
# merging into the second directory tree recursively.
#
#    Modification history:
#
# created.  -- rgr, 21-Oct-02.
# rename_subtree: fix bug: return values in ! -e case.  -- rgr, 27-Oct-02.
#

use strict;
use warnings;

sub rename_subtree {
    # Returns 1 if moved successfully, else 0.
    my ($from, $to, $delete_dir_p) = @_;

    if (! -e $to) {
	# should always be safe to rename in this case.
	# warn "$0:  Renamed 'to-write/$file' to 'written/$file'.\n";
	# return 1;
	if (! rename($from, $to)) {
	    warn "$0:  Can't rename '$from' to '$to':  $!";
	    0;
	}
	elsif ($verbose_p) {
	    warn "$0:  Renamed '$from' to '$to'.\n";
	    1;
	}
    }
    elsif (-d $to && -d $from) {
	# directory-to-directory case
	my $files_left = 0;
	warn "$0:  Renaming '$from' contents into '$to.\n"
	    if $verbose_p;
	opendir(FROM, $from) || die;
	foreach my $file (readdir(FROM)) {
	    next if $file eq '.' || $file eq '..';
	    if (! rename_subtree("$from/$file", "$to/$file", 1)) {
		$files_left++;
	    }
	}
	rmdir($from) || warn "$0:  rmdir('$from') failed:  $!"
	    if $delete_dir_p && $files_left == 0;
	warn "$0:  Done renaming '$from' to '$to'.\n"
	    if $verbose_p;
	$files_left ? 0 : 1;
    }
    else {
	warn "$0:  Can't rename $from on top of $to; skipping.\n";
	0;
    }
}

1;
