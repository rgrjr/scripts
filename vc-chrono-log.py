#!/usr/bin/python

import sys
import re
from datetime import timedelta, datetime

def parsedate_tz(date, format):
    # Parse a date string that may have a timezone offset, returning a datetime
    # object in local time.
    tzoffset = None
    m = re.search("(\s+([-+])(\d\d\d\d))$", date)
    if m:
        # date has a numeric timezone.
        tzsign = 1
        if m.group(2) == '-':
            tzsign = -1
        date = date[:-len(m.group(1))]

        # Convert a timezone offset into seconds ; -0500 -> -18000
        tz = int(m.group(3))
        tzoffset = tzsign * ( (tz//100)*60 + (tz % 100)) * 60
        tzoffset -= -18000 # time.timezone
    else:
        tzoffset = 0

    # Now deal with the rest of the date.
    encoded_date = datetime.strptime(date, format)
    if tzoffset:
        return encoded_date + timedelta(0, tzoffset)
    else:
        return encoded_date

class Entry:
    def __init__(self, author=None, commitid=None, encoded_date=None,
                 files=None, msg=None, revision=None):
        self.author = author
        self.commitid = commitid
        self.encoded_date = encoded_date
        self.files = files
        self.msg = msg
        self.revision = revision

    date_format_string = '%Y-%m-%d %H:%M:%S'

    def report(self):
        # [need date formatting.  -- rgr, 14-Mar-09.]
        print "%s:" % (self.encoded_date.strftime(self.date_format_string))
        for line in self.msg.split("\n"):
            # indent by two, skipping empty lines.
            m = re.match('^\s*$', line)
            if not m:
                line = re.sub("^(\t*)", "\\1  ", line)
                print line
        if self.files:
            n_matches = 0
            n_files = 0
            (n_lines_removed, n_lines_added) = (0, 0)
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
    date_fuzz = 120	# in seconds.

    def __init__(self, vcs_name=None):
        self.vcs_name = vcs_name
        self.log_entries = [ ]

    cvs_date_format = "%Y-%m-%d %H:%M:%S"
    date_fuzz = timedelta(0, 120)

    def parse_cvs(self, stream):

        self.vcs_name = "CVS"

        commit_mods = { }
        comment_mods = { }

        def record_file_rev_comment(file_name, file_rev, date_etc, comment):
            # Do the final parsing, create a FileRevision, and stuff it into the
            # appropriate place.
            m = re.match("date: *([^;]+); *", date_etc)
            if not m:
                print >> sys.stderr, \
                    "Oops; can't identify date in '%s' -- skipping." % (date_etc)
            else:
                tz_date = m.group(1)
                encoded_date = parsedate_tz(tz_date, self.cvs_date_format)
                # print >> sys.stderr, "[date %s => %s]" % (date, encoded_date)
                rev = FileRevision(raw_date = tz_date,
                                   encoded_date = encoded_date,
                                   comment = comment,
                                   file_name = file_name,
                                   file_rev = file_rev)
                # [put into comment_mods for now.  -- rgr, 14-Mar-09.]
                if comment in comment_mods:
                    comment_mods[comment].append(rev)
                else:
                    comment_mods[comment] = [ rev ]

        def sort_file_rev_comments():

            # Combine file entries that correspond to a single commit.
            combined_entries = [ ]
            print >> sys.stderr, "[need to handle commitid entries.]"

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

            # Now resort by date.
            combined_entries.sort(None, lambda x: x.encoded_date, True)
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
                date_etc = stream.readline()
                comment = ''
                line = stream.readline()
                if re.match('branches: ', line):
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
                    file_name = m.group(2)
            line = stream.readline()
        if state <> 'none':
            print >> sys.stderr, "Oops; bad final state '%s'" % (state)
        sort_file_rev_comments()

    def parse(self, stream):
        self.parse_cvs(stream)

### Main program

parser = Parser();
parser.parse(sys.stdin)
for entry in parser.log_entries:
    entry.report()
