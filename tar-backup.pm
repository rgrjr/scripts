### Subroutines for tar backup.

sub do_or_die {
    # Utility function that executes the args and insists on success.  Also
    # responds to $test_p and $verbose_p values.
    my $ignore_return_code_p = $_[0] eq '-ignore-return';
    shift if $ignore_return_code_p;

    warn("$warn:  Executing '", join(' ', @_), "'\n")
	if $test_p || $verbose_p;
    if ($test_p) {
	1;
    }
    elsif (system(@_) == 0) {
	1;
    }
    elsif ($ignore_return_code_p && !($? & 255)) {
	warn("$warn:  Executing '$_[0]' failed:  Code $?\n",
	     ($verbose_p
	      # no sense duplicating this.
	      ? ()
	      : ("Command:  '", join(' ', @_), "'\n")));
	1;
    }
    else {
	die("$warn:  Executing '$_[0]' failed:  $?\n",
	    ($verbose_p
	     # no sense duplicating this.
	     ? ()
	     : ("Command:  '", join(' ', @_), "'\n")),
	    "Died");
    }
}

sub rename_or_die {
    my ($from, $to) = @_;

    rename($from, $to)
	|| die("$warn:  rename('$from', '$to') failed:  $?")
	unless $test_p;
    warn "$warn:  Renamed '$from' to '$to'.\n"
	if $test_p || $verbose_p;
}

1;
