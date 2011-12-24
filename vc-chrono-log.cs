// Produce a chronological log for a VC system.
//
// [created.  -- rgr, 10-Dec-11.]
//
// $Id: vc-chrono-log.rb 218 2009-03-19 02:47:39Z rogers $

// General lib ref:  http://msdn.microsoft.com/en-us/library/gg145045.aspx
using System;
// http://msdn.microsoft.com/en-us/library/system.io.aspx
// http://msdn.microsoft.com/en-us/library/system.io.textreader.aspx
using System.IO;
// "Working with Text Files" p.542.
using System.Text;
// "Using Regular Expressions: Regex"
// http://msdn.microsoft.com/en-us/library/system.text.regularexpressions.aspx
using System.Text.RegularExpressions;
// http://msdn.microsoft.com/en-us/library/system.collections.hashtable.aspx
using System.Collections;
// "List<T>" p.215, http://msdn.microsoft.com/en-us/library/6sh2ey19.aspx
using System.Collections.Generic;
// http://msdn.microsoft.com/en-us/library/system.xml.aspx
using System.Xml;

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

public class Entry {
    public string author = "";
    public string commitid = "";
    public System.DateTime encoded_date;
    public List<FileRevision> files;
    public string msg = "";
    public string revision = "";

    public Entry(System.DateTime encoded_date,
		 string commitid,
		 string author,
		 string msg,
		 List<FileRevision> files) {
	this.encoded_date = encoded_date;
	this.commitid = commitid;
	this.author = author;
	this.msg = msg;
	this.files = files;
    }

    // Some constants for output generation.
    static char[] semicolon_char = {';'};
    static char[] newline_char = {'\n'};

    private static int compare_files_by_name(FileRevision r1,
					     FileRevision r2) {
	// Note that we cannot use the default "culture-sensitive" sorting,
	// since that produces the wrong order, e.g. due to case and treatment
	// of non-alphabetics.
	return String.Compare(r1.file_name, r2.file_name,
			      StringComparison.Ordinal);
    }

    public void report() {
        // string local_date = this.encoded_date.ToString();
	Console.WriteLine("{0}:", encoded_date.ToString("yyyy-MM-dd HH:mm:ss"));

        // [in perl, this is a simple print/join/map over qw(revision author
        // commitid), but random access of object slots in C# is probably too
        // painful.  -- rgr, 16-Dec-11.]
        string items = "";
        if (this.revision.Length > 0)
            items = String.Format("revision: {0}", this.revision);
        if (this.author.Length > 0) {
	    if (items.Length > 0)
		items = items + ";  ";
            items = items + String.Format("author: {0}", this.author);
	}
        if (this.commitid.Length > 0) {
	    if (items.Length > 0)
		items = items + ";  ";
            items = items + String.Format("commitid: {0}", this.commitid);
	}
        if (items.Length > 0)
            Console.WriteLine("  {0}", items.Trim(semicolon_char));

	foreach (string line in this.msg.Trim(newline_char).Split('\n')) {
	    // indent by two, skipping empty lines.
	    // [TBD]
	    Console.WriteLine("  {0}", line);
	}
	if (this.files != null) {
	    int n_matches = 0;
	    int n_files = 0;
	    int lines_removed = 0;
	    int lines_added = 0;
	    this.files.Sort(compare_files_by_name);
	    foreach (FileRevision entry in this.files) {
		// [finish this.  -- rgr, 17-Dec-11.]
		string result
		    = entry.file_rev.Length > 0
		    ? String.Format("  => {0} {1}:",
				    entry.file_name, entry.file_rev)
		    : String.Format("  => {0}:", entry.file_name);
		// qw(state action lines branches)
                if (entry.state.Length > 0)
                    result = result + String.Format("  state: {0};",
						    entry.state);
                if (entry.action.Length > 0)
                    result = result + String.Format("  action: {0};",
						    entry.action);
                if (entry.lines.Length > 0)
                    result = result + String.Format("  lines: {0};",
						    entry.lines);
                if (entry.branches.Length > 0)
                    result = result + String.Format("  branches: {0};",
						    entry.branches);
		Console.WriteLine(result.Trim(semicolon_char));

		// Accumulate totals.
		string lines = entry.lines;
		Match m = Regex.Match(lines, @"\+(?<a>[0-9]+) -(?<r>[0-9]+)");
		if (m != null) {
		    string add_string = m.Groups["a"].ToString();
		    if (add_string.Length > 0) {
			lines_added += Int32.Parse(add_string);
			string rem_string = m.Groups["r"].ToString();
			if (rem_string.Length > 0)
			    lines_removed += Int32.Parse(rem_string);
			n_matches += 1;
		    }
		}
		n_files += 1;
	    }

            // Summarize the file set.
            if (n_matches > 1 && (lines_removed > 1 || lines_added > 1)) {
                string incomplete_spew
		    = n_matches == n_files ? "" : " (incomplete)";
                Console.WriteLine("     Total lines: +{0} -{1}{2}",
				  lines_added, lines_removed, incomplete_spew);
	    }
	}
	Console.WriteLine("");
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

    // Useful "uninitialized" marker.
    static System.DateTime zero_date = new System.DateTime(0);
    // date_disambiguator is a hash of "comment1:comment2" to the number of
    // occurrences, where "comment1" is different from "comment2" and appears
    // just before before it, for two file revisions with the identical date.
    // This is for preserving the order of synthesized commits that happen at
    // the same time; otherwise Sort gives a different permutation of the two
    // initial CVS log entries than do all other languages.
    static Hashtable date_disambiguator = new Hashtable();
    // Date of the last such rev, for recognizing date collisions.
    static System.DateTime last_rev_date = zero_date;
    static string last_rev_comment = "";

    // For matching individual file revisions.
    Hashtable commit_mods = new Hashtable();
    Hashtable comment_mods = new Hashtable();

    // Resulting revisions.
    public List<Entry> log_entries = new List<Entry>();

    public void parse(TextReader stream) {
	// Generic parser, assuming we can dispatch on the first character.
	int first_char = stream.Peek();
	if (first_char == (int) '<')
	    parse_svn_xml(stream);
	else
	    parse_cvs(stream);
    }

    public void parse_svn_xml(TextReader stream) {
	// Use System.Xml.XmlReader to parse stream, in a SAX-like element-at-a-
	// time fashion, turning all <logentry> elements into Entry objects on
	// log_entries.  Finally, sort log_entries by date.
	XmlReaderSettings settings = new XmlReaderSettings();
	settings.IgnoreComments = true;
	settings.IgnoreProcessingInstructions = true;
	settings.IgnoreWhitespace = true;
	settings.ConformanceLevel = ConformanceLevel.Document;
	XmlReader reader = XmlReader.Create(stream, settings);
	reader.ReadStartElement("log");

	// Loop over <logentry> elements.
	while (reader.IsStartElement()) {
	    string rev_number = reader.GetAttribute("revision");
	    if (reader.Name != "logentry")
		Console.WriteLine("[on element {0} instead of 'logentry']",
				  reader.Name);
	    reader.ReadStartElement("logentry");

	    // Parse author and date.  The <author> element is optional, and
	    // omitted in the first commit by cvs2svn.
	    string author = "";
	    if (reader.Name == "author") {
		author = reader.ReadString();
		reader.ReadEndElement();
	    }
	    reader.ReadStartElement("date");
	    string date = reader.ReadString();
	    reader.ReadEndElement();
	    System.DateTime encoded_date = zero_date;
	    if (! System.DateTime.TryParse(date, out encoded_date))
		Console.WriteLine("Oops; can't parse revision {0} date '{1}'.",
				  rev_number, date);

	    // Parse paths.
	    reader.ReadStartElement("paths");
	    List<FileRevision> files = new List<FileRevision>();
	    while (reader.IsStartElement()) {
		string action = reader.GetAttribute("action");
		reader.ReadStartElement("path");
		string pathname = reader.ReadString();
		FileRevision rev = new FileRevision
		    (date, encoded_date, "", pathname, "");
		rev.action = action;
		rev.author = author;
		files.Add(rev);
		reader.ReadEndElement();
	    }
	    reader.ReadEndElement();

	    // Get the commit message.
	    reader.ReadStartElement("msg");
	    string msg = reader.ReadString();
	    reader.ReadEndElement();

	    // Create and add an entry.
	    Entry new_entry = new Entry(encoded_date, "", author, msg, files);
	    new_entry.revision = rev_number;
	    log_entries.Add(new_entry);
	    // End of the <logentry>.
	    reader.ReadEndElement();
	}

	// Now resort by date.
	log_entries.Sort(compare_entries_by_date);
	log_entries.Reverse();
    }

    private void record_file_rev_comment(string file_name, string file_rev,
					 string date_etc, string comment) {
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

	    // Update date_disambiguator if appropriate.
	    if (last_rev_date == encoded_date
		&& last_rev_comment != comment) {
		string key = last_rev_comment + ":" + comment;
		int count = (int) (date_disambiguator[key] == null
				   ? 0
				   : date_disambiguator[key]);
		date_disambiguator[key] = count + 1;
	    }
	    last_rev_date = encoded_date;
	    last_rev_comment = comment;
	}
    }

    private static int compare_revs_by_date(FileRevision r1,
					    FileRevision r2) {
	return r1.encoded_date.CompareTo(r2.encoded_date);
    }

    private static int compare_entries_by_date(Entry r1, Entry r2) {
	int result = r1.encoded_date.CompareTo(r2.encoded_date);
	if (result != 0)
	    return result;
	string msg1 = r1.msg;
	string msg2 = r2.msg;
	if (msg1 == msg2)
	    return 0;

	// The dates are the same, but the commit messages are different.  Use
	// date_disambiguator to try to preserve the original order.
	string key1 = msg1 + ":" + msg2;
	int count1 = (int) (date_disambiguator[key1] == null
			    ? 0
			    : date_disambiguator[key1]);
	string key2 = msg2 + ":" + msg1;
	int count2 = (int) (date_disambiguator[key2] == null
			    ? 0
			    : date_disambiguator[key2]);
	result = count1.CompareTo(count2);
	return result;
    }

    private void sort_file_rev_comments() {
	// Combine file entries that correspond to a single commit.
	foreach (string commit_id in commit_mods.Keys) {
	    List<FileRevision> mods
		= (List<FileRevision>) commit_mods[commit_id];
	    FileRevision mod = mods[0];
	    Entry new_entry
		= new Entry(mod.encoded_date, commit_id, mod.author,
			    mod.comment, mods);
	    log_entries.Add(new_entry);
	}

	// Examine remaining entries by comment, then by date, combining all
	// that have the identical comment and nearly the same date.  [we should
	// also refuse to merge them if their modified files are not disjoint.
	// -- rgr, 29-Aug-05.]
	foreach (string comment in comment_mods.Keys) {
	    System.DateTime last_date = zero_date;
	    List<FileRevision> entries = new List<FileRevision>();
	    List<FileRevision> mods
		= (List<FileRevision>) comment_mods[comment];
	    mods.Sort(compare_revs_by_date);
	    foreach (FileRevision mod in mods) {
		// mod.Display();
		System.DateTime date = mod.encoded_date;
		if (last_date != zero_date && date > last_date) {
		    // the current entry probably represents a "cvs commit"
		    // event that is distinct from the previous entry(ies).
		    FileRevision entry_mod = entries[0];
		    Entry new_entry
			= new Entry(entry_mod.encoded_date, "",
				    entry_mod.author, comment, entries);
		    log_entries.Add(new_entry);
		    entries = new List<FileRevision>();
		    last_date = zero_date;
		}
		if (last_date == zero_date) {
		    last_date = date.AddSeconds(120);
		}
		entries.Add(mod);
	    }
	    if (entries.Count > 0) {
		// Take care of leftovers.
		FileRevision entry_mod = entries[0];
		Entry new_entry
		    = new Entry(entry_mod.encoded_date, "",
				entry_mod.author, entry_mod.comment, entries);
		log_entries.Add(new_entry);
	    }

            // Now resort by date.  We can't just ask for the reversed sort
            // because that puts the first two entries (which happened at the
            // same time when the repository was created) in the opposite order.
            log_entries.Sort(compare_entries_by_date);
	    log_entries.Reverse();
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
	    }
	    line = input.ReadLine();
	}
	if (state != parse_state.none) {
	    Console.WriteLine("Oops; bad final state.");
	}
	sort_file_rev_comments();
    }
}

public class HelloWorld {
    static public void Main () {
	Parser parser = new Parser();
	parser.parse(Console.In);
	foreach (Entry entry in parser.log_entries) {
	    entry.report();
	}
    }
}
