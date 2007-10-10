#!/usr/bin/ruby
#
# Produce a chronological log for a VC system.
#
# [Created, based on the cvs-chrono-log.pl version.  -- rgr, 30-Dec-06.]
#
# $Id$

# [Kernel.require: p528]
require 'parsedate'

$date_fuzz = 120		# in seconds.

### Hacks.

# [library REXML: p725]
require 'rexml/document'

# Extend REXML with the collect_text method.  This returns a single string for
# all of the text (and none of the elements) in the given element.
module REXML

    class Text
        def collect_text
            value
        end
    end

    class Element
        def collect_text
            self.map { | s | s.collect_text }.join('')
        end
    end

end


### Classes.

# Helper class for producing formatted output.
class LogBase

    # Return a string with the specified field "name: value" pairs, omitting
    # any that are nil.
    def join_fields(field_names)
        field_names.reject do | name |
            # Omit fields that are nil.
            self.send(name).nil?
        end .map do |name|
            # Format the rest.
            name + ': ' + self.send(name)
        end.join(';  ')
    end

end

# Holds a single file revision.  Slots were chosen to be a superset of CVS and
# Subversion information; the revision is per-entry for Subversion but
# per-file for CVS.
class VCFileRevision < LogBase
    # Common slot.
    attr_accessor :file_name
    # CVS slots.
    attr_accessor :author, :encoded_date, :comment, :file_rev
    attr_accessor :state, :lines, :commitid, :revision, :branches
    # Subversion slot.
    attr_accessor :action

    @@per_file_fields = %w(state action lines branches)

    def initialize(hash)
        @file_name = hash['file_name']
        @author = hash['author']
        @encoded_date = hash['encoded_date']
        @comment = hash['comment']
        @file_rev = hash['file_rev']
        @state = hash['state']
        @lines = hash['lines']
        @commitid = hash['commitid']
        @revision = hash['revision']
        @branches = hash['branches']
        @action = hash['action']
    end

    def display
        print('  => ', @file_name)
        print(' ', @file_rev) unless @file_rev.nil?
        print(':  ', join_fields(@@per_file_fields), "\n")
    end

end

# Describes a single commit.  Sometimes this is called a "changeset".
class VCLogEntry < LogBase
    attr_accessor :revision, :commitid, :author, :encoded_date, :message, :files

    @@per_entry_fields = %w(revision author commitid)
    @@date_format_string = '%Y-%m-%d %H:%M:%S'

    def initialize(hash)
        @message = hash['message'] || hash['msg'] || raise("message required")
        @encoded_date = hash['encoded_date'] || raise("encoded_date required")
        @revision = hash['revision']
        @commitid = hash['commitid']

	# CVS sorts the file names, but combining sets of entries with similar
	# dates can make them come unsorted.
        @files = hash['files'] || [ ]
        if @files.length then
            @files = @files.sort { |a, b| a.file_name <=> b.file_name }
        end

        # Default the author from any of the files.
        @author = hash['author']
        if ! @author && @files.length then
            @author = @files[0].author
        end
        raise "VCLogEntry init:  No @author in #{self}" if ! @author
    end

    def display
        # Print "normal" output.

        # [strftime is on p647.]
	print(encoded_date.getlocal.strftime(@@date_format_string), ":\n  ",
              self.join_fields(@@per_entry_fields), "\n")
	self.message.split("\n").each do |line|
            print '  ', line, "\n" if line.length
        end

        # list the files now.
	(n_matches, n_files, lines_removed, lines_added) = [0, 0, 0, 0];
        self.files.each do | entry |
	    entry.display
            lines = entry.lines
            if lines && lines =~ /\+(\d+) -(\d+)/ then
                lines_added += Integer($1)
                lines_removed += Integer($2)
                n_matches += 1
            end
            n_files += 1
        end
	if n_matches > 1 && (lines_removed > 0 || lines_added > 0) then
            print("     Total lines: +#{lines_added} -#{lines_removed}",
	          (n_matches == n_files ? '' : ' (incomplete)'),
                  "\n")
        end
	puts
    end

end

# Helper class for parsing log files.  After the "parse" method returns, the
# @log_entries slot will contain an array of VCLogEntry instances.
class VCLogParser
    attr_reader :log_entries

    def initialize()
        @commit_mods = Hash.new
        @comment_mods = Hash.new
        @log_entries = [ ]
    end

    def parse(stream)
        # Generic parser, assuming we can dispatch on the first character.
        char = stream.getc
        stream.ungetc(char)
        if char == ?< then
            parse_svn_xml(stream)
        else
            parse_cvs(stream)
        end

        # now resort by date from newest to oldest.
        # [Array#sort! is on p439.]
        @log_entries.sort! { |a, b| b.encoded_date <=> a.encoded_date }
    end

    def parse_svn_xml(stream)
        # REXML does the hard part; we just need to traverse the returned
        # document and extract the interesting bits.
        xml = REXML::Document.new(stream)
        xml.elements.each("//logentry") do | logentry |
            rev_number = logentry.attributes['revision']
            raise "No revision in #{logentry.class.name}" if rev_number.nil?
            files = [ ]
            hash = { 'revision' => rev_number, 'files' => files }
            logentry.each do | datum |
                # skip whitespace between elements.
                next if datum.kind_of?(REXML::Text)
                elt_name = datum.expanded_name
                if elt_name == 'paths' then
                    datum.each do | path |
                        next if path.kind_of?(REXML::Text)
                        action = path.attributes['action'] || 'M'
                        text = path.collect_text
                        files << VCFileRevision.new('file_name' => text,
                                                     'action' => action)
                    end
                else
                    hash[elt_name] = datum.collect_text
                end
            end

            # Make sure we have all the right values.
            date = hash['date'] || raise("Bug:  No date")
            # class Time: p642
            # library ParseDate: p713
            hash['encoded_date'] = Time.gm(*ParseDate.parsedate(date))
            @log_entries << VCLogEntry.new(hash)
        end
    end

    def parse_cvs(stream)
        # state is one of %w(none headings descriptions).
        state = 'none'
        file_name = ''
        while line = stream.gets
            if line =~ /^RCS file: / then
                # start of a new entry.
                state = 'headings'
            elsif state == 'descriptions' then
                if not (line =~ /^revision (.*)$/) then
                    STDERR.puts "[oops; expected revision on line #{$.}]\n"
                end
                file_rev = $1
                date_etc = stream.gets.chomp
                comment = ''
                line = stream.gets
                if line =~ /^branches: / then
                    line.chomp!
                    date_etc += '  '+line
                    line = stream.gets
                end
                while line && line !~ /^---+$|^===+$/
                    comment += line
                    line = stream.gets
                end
                record_file_rev_comment(file_name, file_rev, date_etc, comment)
                state = ! line || line =~ /^========/ ? 'none' : 'descriptions'
            elsif state == 'headings' && line =~ /^([^:]+):\s*(.*)/ then
                # processing the file header.
                tag = $1
                if tag == 'description' then
                    # eat the description.
                    line = stream.gets
                    # [there are 28 hyphens and 77 equal signs printed by my
                    # CVS version.  how many are printed by yours?  -- rgr,
                    # 16-Feb-06.]
                    while line && line !~ /^(========|--------)/
                        line = stream.gets
                    end
                    state = line =~ /^========/ ? 'none' : 'descriptions'
                elsif tag == 'Working file' then
                    file_name = $2.chomp
                end
            end
        end
        if state != 'none' then
            STDERR.puts "[oops; final state is #{state}; truncated output?]"
        end
        fill_log_entries
    end

    private

    def record_file_rev_comment(file_name, file_rev, date_etc, comment)
        # Parse further, turn into an object, and accumulate in @commit_mods
        # or @comment_mods as appropriate.  This is internal to parse_cvs.

        date = date_etc.sub!(/date: *([^;]+); */, '') ? $1 : '???'
        if date == '???' then
            STDERR.puts "Oops; can't identify date in '#{date_etc}' -- skipping."
        else
            # class Time: 642
            # library ParseDate: 713
            decoded = ParseDate.parsedate(date)
            encoded_date = Time.gm(*decoded)
            date_etc.sub!(/; *$/, '')

            # Create the attributes as a hash in values.  This is done in two
            # steps because I can't seem to get Hash[] (or its equivalents) to
            # accept *alist.flatten (or equivalents) along with other hash
            # initializers.  (And I'm too lazy to call the methods.)
            alist = date_etc.split(/; +/).
                    map(&lambda { |pair| pair.split(/: */) })
            values = Hash[*alist.flatten]
            values.merge!(Hash['encoded_date' => encoded_date,
                               'comment' => comment,
                               'file_name' => file_name,
                               'file_rev' => file_rev])
            rev = VCFileRevision.new(values)
            commit_id = rev.commitid
            if commit_id then
                @commit_mods[commit_id] ||= [ ]
                @commit_mods[commit_id].push(rev)
            else
                @comment_mods[comment] ||= Hash.new
                @comment_mods[comment][encoded_date] ||= [ ]
                @comment_mods[comment][encoded_date].push(rev)
            end
        end
    end

    # Add a new VCLogEntry to @log_entries.
    def add_entry(message, last_date, commit_id, file_entries)
        entry = VCLogEntry.new('encoded_date' => last_date,
                               'message' => message,
                               'commitid' => commit_id,
                               'files' => file_entries.flatten)
        @log_entries << entry
    end

    # Fill @log_entries with entries made from @commit_mods and @comment_mods.
    def fill_log_entries()
        # combine file entries that correspond to a single commit.
        @commit_mods.each do | commit_id, entries |
            # All entries with the same commitid perforce belong to the same
            # commit, to which no entries without a commitid can belong.
            file_entry = entries[0]
            add_entry(file_entry.comment, file_entry.encoded_date,
                      commit_id, entries)
        end

        # examine remaining entries by comment, then by date, combining all
        # that have the identical comment and nearly the same date.  [we
        # should also refuse to merge them if their modified files are not
        # disjoint.  -- rgr, 29-Aug-05.]
        @comment_mods.each do | comment, date_to_entries |
            # this is the most recent date for a set of related commits.
            last_date = nil
            # the commits themselves.
            file_entries = [ ]
            date_to_entries.keys.sort.each do | date |
                if last_date && date-last_date > $date_fuzz then
                    # the current entry probably represents a "cvs commit"
                    # event that is distinct from any previous entries.
                    add_entry(comment, last_date, nil, file_entries)
                    file_entries = [ ]
                    last_date = nil
                end
                if ! last_date || date > last_date then
                    last_date = date
                end
                file_entries << date_to_entries[date].flatten
            end
            if file_entries.length then
                add_entry(comment, last_date, nil, file_entries)
            end
        end
    end

end

### Main code.

parser = VCLogParser.new
parser.parse(STDIN)
parser.log_entries.each { | entry | entry.display }
