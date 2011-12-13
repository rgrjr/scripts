// Produce a chronological log for a VC system.
//
// [created.  -- rgr, 10-Dec-11.]
//
// $Id: vc-chrono-log.rb 218 2009-03-19 02:47:39Z rogers $

using System;
using System.IO;
// "Working with Text Files" p.542.
using System.Text;
// "Using Regular Expressions: Regex"
using System.Text.RegularExpressions;

public class Parser {
    string vcs_name = "unknown";

    enum parse_state { none, headings, descriptions }

    public void parse_cvs(TextReader input) {

	vcs_name = "CVS";
	parse_state state = parse_state.none;
	Regex match_rcs = new Regex("RCS file: ");
	string file_name = "";
	string file_rev = "";

	string line = input.ReadLine();
	while (line != null) {
	    if (match_rcs.IsMatch(line)) {
		state = parse_state.headings;
	    }
	    else if (state == parse_state.descriptions) {
		Match m = Regex.Match(line, @"revision (?<rev>.*)$");
		if (m == null) {
		    Console.WriteLine("No file rev");
		}
		else {
		    file_rev = m.Groups["rev"].ToString();
		}
		string date_etc = input.ReadLine();
		string comment = "";
		line = input.ReadLine();
		if (Regex.IsMatch(line, "branches: ")) {
		    // [rstrip not needed?  -- rgr, 11-Dec-11.]
		    date_etc = date_etc + "  " + line;
		    line = input.ReadLine();
		}
		while (line != null
		       && ! Regex.IsMatch(line, "^---+$|^===+$")) {
		    comment = comment + line;
		    line = input.ReadLine();
		}
		// [replace this with record_file_rev_comment.  --
		// rgr, 12-Dec-11.]
		Console.WriteLine("woop:  '{0}', '{1}', '{2}', '{3}'",
				  file_name, file_rev, date_etc, comment);
                if (line == null || Regex.IsMatch(line, "^========"))
                    state = parse_state.none;
                else
                    state = parse_state.descriptions;
	    }
	    else if (Regex.IsMatch(line, @"^([^:]+):\s*(.*)")) {
		Match m = Regex.Match(line, @"^(?<tag>[^:]+):\s*(?<val>.*)");
		string tag = m.Groups["tag"].ToString();
		if (tag.Equals("description")) {
		    // eat the description.
		    line = input.ReadLine();
                    // [there are 28 hyphens and 77 equal signs printed
                    // by my CVS version.  how many are printed by
                    // yours?  -- rgr, 16-Feb-06.]
		    while (line != null
			   && ! Regex.IsMatch(line, "(---------|========)")) {
			line = input.ReadLine();
		    }
		    if (line == null || Regex.IsMatch(line, "======="))
			state = parse_state.none;
		    else {
			state = parse_state.descriptions;
		    }
		}
		else if (tag.Equals("Working file")) {
		    file_name = m.Groups["val"].ToString();
		}
		else {
		    Console.WriteLine("Got tag '{0}'", tag);
		}
	    }
	    line = input.ReadLine();
	}
	if (state != parse_state.none) {
	    Console.WriteLine("Oops; bad final state.");
	}
    }
}

public class HelloWorld {
    static public void Main () {
	TextReader input = Console.In;
	Parser parser = new Parser();
	parser.parse_cvs(input);
    }
}
