#!/usr/bin/python

import sys
import re
import xml.dom.minidom
import unicodedata
import dateutil.parser
import dateutil.tz
from datetime import timedelta
from string import join

class Entry:
    def __init__(self, author=None, commitid=None, encoded_date=None,
                 files=None, msg=None, revision=None, date=None):
        self.author = author
        self.commitid = commitid
        self.encoded_date = encoded_date
        self.files = files
        self.msg = msg
        self.revision = revision

    date_format_string = '%Y-%m-%d %H:%M:%S:'

    def report(self):
        local_date = self.encoded_date.astimezone(dateutil.tz.tzlocal())
        print local_date.strftime(self.date_format_string)
        # [in perl, this is a simple print/join/map over qw(revision author
        # commitid), but i haven't figured out how to do random access of object
        # slots in python yet.  -- rgr, 15-Mar-09.]
        items = [ ]
        if self.revision:
            items.append("revision: %s" % (self.revision))
        if self.author:
            items.append("author: %s" % (self.author))
        if self.commitid:
            items.append("commitid: %s" % (self.commitid))
        if items:
            print '  ' + join(items, ';  ')

        for line in self.msg.split("\n"):
            # indent by two, skipping empty lines.
            m = re.match('^\s*$', line)
            if not m:
                line = re.sub("^(\t*)", "\\1  ", line)
                print line
        if self.files:
            n_matches = 0
            n_files = 0
            (lines_removed, lines_added) = (0, 0)
            self.files.sort(None, lambda x: x.file_name)
            for entry in self.files:
                file_name = entry.file_name
                if entry.file_rev:
                    file_name = file_name + ' ' + entry.file_rev
                result = "  => %s:" % (file_name)
                # qw(state action lines branches)
                if entry.state:
                    result = result + ("  state: %s;" % (entry.state))
                if entry.action:
                    result = result + ("  action: %s;" % (entry.action))
                if entry.lines:
                    result = result + ("  lines: %s;" % (entry.lines))
                if entry.branches:
                    result = result + ("  branches: %s;" % (entry.branches))
                print result[:-1]

                # Accumulate totals.
                lines = entry.lines or ''
                m = re.match("\+(\d+) -(\d+)", lines)
                if m:
                    lines_added += int(m.group(1))
                    lines_removed += int(m.group(2))
                    n_matches += 1
                n_files += 1

            # Summarize the file set.
            if n_matches > 1 and (lines_removed or lines_added):
                incomplete_spew = ''
                if n_matches != n_files:
                    incomplete_spew = ' (incomplete)'
                print("     Total lines: +%s -%s%s"
                      % (lines_added, lines_removed, incomplete_spew))
        print
        
class FileRevision:
    def __init__(self, comment=None, raw_date=None, encoded_date=None,
                 file_name=None, file_rev=None, action=None, author=None,
                 state=None, lines=None, commitid=None, branches=None):
        self.comment = comment
        self.raw_date = raw_date
        self.encoded_date = encoded_date
        self.file_name = file_name
        self.file_rev = file_rev
        self.action = action
        self.author = author
        self.state = state
        self.lines = lines
        self.commitid = commitid
        self.branches = branches

class Parser:
    date_fuzz = timedelta(0, 120)	# in seconds.

    def __init__(self, vcs_name=None):
        self.vcs_name = vcs_name
        self.log_entries = [ ]

    def parse(self, stream):
        # Generic parser, assuming we can dispatch on the first character.
        pos = stream.tell()
        char = stream.read(1)
        stream.seek(pos)
        if char == '<':
            self.parse_svn_xml(stream)
        else:
            self.parse_cvs(stream)

    svn_date_format = "%Y-%m-%dT%H:%M:%S"

    def parse_svn_xml(self, stream):
        # Use xml.dom.minidom to parse stream, and traverse the resulting
        # document, turning all "logentry" elements into Entry objects on
        # log_entries.  Finally, sort log_entries by date.

        def collect_text(node):
            if node.nodeType == xml.dom.Node.TEXT_NODE:
                return node.data
            elif node.nodeType == xml.dom.Node.ELEMENT_NODE:
                result = ''
                for subnode in node.childNodes:
                    result = result + collect_text(subnode)
                return result
            else:
                return ''

        def do_logentry(logentry):
            rev_number = logentry.getAttribute('revision')
            files = [ ]
            hash = { 'revision': rev_number, 'files': files }
            for subnode in logentry.childNodes:
                if subnode.nodeType == xml.dom.Node.ELEMENT_NODE:
                    u_elt_name = subnode.tagName
                    # We have to do this explicit conversion from Unicode to
                    # ASCII because Python barfs on Unicode strings when given
                    # as keyword argument names.
                    elt_name = unicodedata.normalize('NFKD', u_elt_name) \
                        .encode('ascii','ignore')
                    if elt_name == 'paths':
                        for path in subnode.childNodes:
                            if path.nodeType == xml.dom.Node.ELEMENT_NODE:
                                action = path.getAttribute('action') or 'M'
                                text = collect_text(path)
                                file = FileRevision(file_name = text,
                                                    action = action)
                                files.append(file)
                    else:
                        hash[elt_name] = collect_text(subnode)
            # Note that dateutil.parser can handle the fractional second and the
            # "Z" timezone specification.
            encoded_date = dateutil.parser.parse(hash['date'])
            self.log_entries.append(Entry(encoded_date = encoded_date,
                                          **hash))

        def visit_node(node, prefix):
            type = node.nodeType
            if type == xml.dom.Node.ELEMENT_NODE \
                    and node.tagName == 'logentry':
                do_logentry(node)
            else:
                for subnode in node.childNodes:
                    visit_node(subnode, prefix)

        visit_node(xml.dom.minidom.parse(stream), '')
        self.log_entries.sort(None, lambda x: x.encoded_date, True)

    cvs_date_format = "%Y-%m-%d %H:%M:%S"
    match_date_etc = re.compile("date: *([^;]+); *(.*)$", re.DOTALL)

    def parse_cvs(self, stream):

        self.vcs_name = "CVS"

        commit_mods = { }
        comment_mods = { }

        def record_file_rev_comment(file_name, file_rev, date_etc, comment):
            # Do the final parsing, create a FileRevision, and stuff it into the
            # appropriate place.
            date_etc = re.sub(";\n*$", "", date_etc)
            m = self.match_date_etc.match(date_etc)
            if not m:
                print >> sys.stderr, \
                    "Oops; can't identify date in '%s' -- skipping." % (date_etc)
            else:
                tz_date = m.group(1)
                date_etc = m.group(2)
                encoded_date = dateutil.parser.parse(tz_date)

                # Unpack the keyword options.
                kwds = { }
                for pair in re.split("; +", date_etc):
                    (key, value) = re.split(": *", pair, 1)
                    kwds[key] = value

                # Define the revision.
                rev = FileRevision(raw_date = tz_date,
                                   encoded_date = encoded_date,
                                   comment = comment,
                                   file_name = file_name,
                                   file_rev = file_rev,
                                   **kwds)

                # Put rev into commit_mods if we have a commitid, else put it
                # into comment_mods.
                commit_id = rev.commitid
                if commit_id: 
                    if commit_id in commit_mods:
                        commit_mods[commit_id].append(rev)
                    else:
                        commit_mods[commit_id] = [ rev ]
                else:
                    if comment in comment_mods:
                        comment_mods[comment].append(rev)
                    else:
                        comment_mods[comment] = [ rev ]

        def sort_file_rev_comments():

            # Combine file entries that correspond to a single commit.
            combined_entries = [ ]
            for commit_id in commit_mods.keys():
                mods = commit_mods[commit_id]
                mod = mods[0]
                new_entry = \
                    Entry(encoded_date = mod.encoded_date,
                          commitid = commit_id,
                          author = mod.author,
                          msg = mod.comment,
                          files = mods)
                combined_entries.append(new_entry)

            # Examine remaining entries by comment, then by date,
            # combining all that have the identical comment and nearly
            # the same date.  [we should also refuse to merge them if
            # their modified files are not disjoint.  -- rgr,
            # 29-Aug-05.]
            for comment in comment_mods.keys():
                # this is the latest date for a set of commits that we consider
                # related.
                last_date = None
                entries = [ ]
                mods = comment_mods[comment]
                mods.sort(None, lambda x: x.encoded_date)
                for mod in mods:
                    date = mod.encoded_date
                    if last_date and date > last_date:
                        # the current entry probably represents a "cvs commit"
                        # event that is distinct from the previous entry(ies).
                        combined_entries.append(
                            Entry(encoded_date = entries[0].encoded_date,
                                  author = entries[0].author,
                                  msg = comment,
                                  files = entries))
                        entries = [ ]
                        last_date = None
                    if last_date == None:
                        last_date = date + self.date_fuzz
                    entries.append(mod)
                if entries:
                    # Take care of leftovers.
                    combined_entries.append(
                        Entry(encoded_date = entries[0].encoded_date,
                              author = entries[0].author,
                              msg = comment,
                              files = entries))
                # End of comment loop

            # Now resort by date.  We can't just ask for the reversed sort
            # because that puts the first two entries (which happened at the
            # same time when the repository was created) in the opposite order.
            combined_entries.sort(None, lambda x: x.encoded_date)
            combined_entries.reverse()
            self.log_entries = combined_entries

        ## Main code.
        state = 'none'
        line = stream.readline()
        while line:
            if re.match("RCS file: ", line):
                # start of a new entry.
                state = 'headings'
            elif state == 'descriptions':
                m = re.search('revision (.*)$', line)
                file_rev = None
                if not m:
                    print >> sys.stderr, "No file rev"
                else:
                    file_rev = m.group(1)
                date_etc = stream.readline().rstrip("\n")
                comment = ''
                line = stream.readline()
                if re.match('branches: ', line):
                    line = line.rstrip("\n")
                    date_etc = date_etc + '  ' + line
                    line = stream.readline()
                while line and not re.match('^---+$|^===+$', line):
                    comment = comment + line
                    line = stream.readline()
                record_file_rev_comment(file_name, file_rev,
                                        date_etc, comment)
                if not line or re.match('^========', line):
                    state = 'none'
                else:
                    state = 'descriptions'

            elif re.match("^([^:]+):\s*(.*)", line):
                m = re.match("^([^:]+):\s*(.*)", line)
                tag = m.group(1)
                if tag == 'description':
                    # eat the description.
                    line = stream.readline()
                    # [there are 28 hyphens and 77 equal signs printed
                    # by my CVS version.  how many are printed by
                    # yours?  -- rgr, 16-Feb-06.]
                    while line and not re.match('(---------|========)', line):
                        line = stream.readline()
                    if re.match('========', line):
                        state = 'none'
                    else:
                        state = 'descriptions'
                elif tag == 'Working file':
                    file_name = m.group(2).rstrip("\n")
            line = stream.readline()
        if state <> 'none':
            print >> sys.stderr, "Oops; bad final state '%s'" % (state)
        sort_file_rev_comments()

### Main program

parser = Parser();
parser.parse(sys.stdin)
for entry in parser.log_entries:
    entry.report()
