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
// http://msdn.microsoft.com/en-us/library/system.text.regularexpressions.aspx
using System.Text.RegularExpressions;
// http://msdn.microsoft.com/en-us/library/system.collections.hashtable.aspx
using System.Collections;
// "List<T>" p.215.
using System.Collections.Generic;

public class FileRevision {
    public string comment = "";
    public string raw_date = "";
    public System.DateTime encoded_date;
    public string file_name = "";
    public string file_rev = "";
    public string action = "";
    public string author = "";
    public string state = "";
    public string lines = "";
    public string commitid = "";
    public string branches = "";

    public FileRevision(string raw_date, System.DateTime encoded_date,
			string comment, string file_name, string file_rev) {
	this.raw_date = raw_date;
	this.encoded_date = encoded_date;
	this.comment = comment;
	this.file_name = file_name;
	this.file_rev = file_rev;
    }
}

public class Parser {
    string vcs_name = "unknown";

    enum parse_state { none, headings, descriptions }

    static Regex match_rcs = new Regex("RCS file: ");
    static Regex match_date_etc
	= new Regex("date: *(?<date>[^;]+); *(?<etc>.*)$");
    static Regex match_pair_delim = new Regex("; +");
    static Regex match_pair_parse
	= new Regex("(?<kwd>[^:]+): *(?<val>.*)");

    // For matching individual file revisions.
    Hashtable commit_mods = new Hashtable();
    Hashtable comment_mods = new Hashtable();

    private void record_file_rev_comment(string file_name, string file_rev,
					 string date_etc, string comment) {
	// Console.WriteLine("woop:  '{0}', '{1}', '{2}', '{3}'",
	// file_name, file_rev, date_etc, comment);
	Match m = match_date_etc.Match(date_etc);
	if (m == null) {
	    Console.WriteLine("Oops; can't identify date in '{0}' -- skipping.",
			      date_etc);
	}
	else {
	    string tz_date = m.Groups["date"].ToString();
	    date_etc = m.Groups["etc"].ToString();
	    System.DateTime encoded_date;
	    if (! System.DateTime.TryParse(tz_date, out encoded_date))
		Console.WriteLine("Oops; can't parse date '{0}'.", tz_date);

	    // Unpack the keyword options.
	    Hashtable kwds = new Hashtable();
	    foreach (string pair in match_pair_delim.Split(date_etc)) {
		Match m2 = match_pair_parse.Match(pair);
		if (m2 != null) {
		    String key = m2.Groups["kwd"].ToString();
		    String val = m2.Groups["val"].ToString();
		    kwds.Add(key, val);
		}
	    }

	    // Define the revision.
	    FileRevision rev = new FileRevision(tz_date, encoded_date, comment,
						file_name, file_rev);
	    if (kwds.Contains("action"))
		rev.action = (string) kwds["action"];
	    if (kwds.Contains("author"))
		rev.author = (string) kwds["author"];
	    if (kwds.Contains("state"))
		rev.state = (string) kwds["state"];
	    if (kwds.Contains("lines"))
		rev.lines = (string) kwds["lines"];
	    if (kwds.Contains("commitid"))
		rev.commitid = (string) kwds["commitid"];
	    if (kwds.Contains("branches"))
		rev.branches = (string) kwds["branches"];

	    // Put rev into commit_mods if we have a commitid, else put it
	    // into comment_mods.
	    List<FileRevision> list;
	    string commit_id = rev.commitid;
	    if (commit_id.Length > 0) {
		Console.WriteLine("Have rev.commitid = '{0}'", commit_id);
		list = (List<FileRevision>) commit_mods[commit_id];
		if (list == null) {
		    list = new List<FileRevision>();
		    commit_mods[commit_id] = list;
		}
	    }
	    else {
		list = (List<FileRevision>) comment_mods[comment];
		if (list == null) {
		    list = new List<FileRevision>();
		    comment_mods[comment] = list;
		}
	    }
	    list.Add(rev);
	}
    }

    public void parse_cvs(TextReader input) {

	vcs_name = "CVS";
	parse_state state = parse_state.none;
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
		    comment = comment + line + "\n";
		    line = input.ReadLine();
		}
		// [replace this with record_file_rev_comment.  --
		// rgr, 12-Dec-11.]
		record_file_rev_comment(file_name, file_rev, date_etc, comment);
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
		    // Console.WriteLine("Got tag '{0}'", tag);
		}
	    }
	    line = input.ReadLine();
	}
	if (state != parse_state.none) {
	    Console.WriteLine("Oops; bad final state.");
	}
	Console.WriteLine("Total of {0} commit revs and {1} comment revs.",
			  commit_mods.Count, comment_mods.Count);
    }
}

public class HelloWorld {
    static public void Main () {
	TextReader input = Console.In;
	Parser parser = new Parser();
	parser.parse_cvs(input);
    }
}
