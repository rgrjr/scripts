%% Experimenting with parsing "cvs log" output in Erlang.
%%
%% [created.  -- rgr, 30-Jan-08.] 
%%
%% To test this, get an Erlang shell, and do:
%%
%%	1> c(test).
%%	2> {ok, Result1} = test:test_read_file("test/test-cvs-chrono-log.text").
%%
%% $Id$

-module(test).
-export([test_read_file/1]).

%% 3.9 Records (p.59)
-record(vc_file_revision,
	{ file_name, author, encoded_date, comment, file_rev, state, lines,
	  commitid, revision, branches, action }).
-record(vc_log_file,
	{ rcs_file, working_file, head, commits = [ ] }).

%% Association list lookup.  Optional third arg is the default.
lookup(Key, [ {Key, Value} | _Tail ], _) -> Value;
lookup(Key, [ _ | Tail ], Default) -> lookup(Key, Tail, Default);
lookup(_, [ ], Default) -> Default.
lookup(Key, List) -> lookup(Key, List, none).

parse_kvp(Line) ->
    %% [it would be really nice to be able to factor out these constant regexps,
    %% so Erlang doesn't have to reparse them every time.  -- rgr, 31-Jan-08.]
    case regexp:split(Line, ": *") of
	{ok, [Key]} -> { list_to_atom(Key), true };
	%% [this next throws away extra stuff from (e.g.):  "total revisions: 9;
	%% selected revisions: 9", but we don't use these.  -- rgr, 31-Jan-08.]
	{ok, [Key, Value | _Tail]} -> { list_to_atom(string:strip(Key)), Value }
    end.

make_key_value_pairs(String, Re) ->
    {ok, Lines} = regexp:split(String, Re),
    [ parse_kvp(Line) || Line <- Lines ].

%% Parse a single commit for a single file.
parse_cvs_single_commit(File_name, Description) ->
    {ok, [ Rev_line, Data_line | Text ]} = regexp:split(Description, "\n"),
    {ok, [ _, Revision]} = regexp:split(Rev_line, " "),
    Commit_keys = make_key_value_pairs(Data_line, "; *"),
    #vc_file_revision{ file_name = File_name,
		       author = lookup(author, Commit_keys),
		       encoded_date = lookup(date, Commit_keys),
		       state = lookup(state, Commit_keys),
		       lines = lookup(lines, Commit_keys),
		       comment = string:join(Text, "\n"),
		       revision = Revision}.

%% Parse all entries for a single file.
parse_cvs_single_file_entry(Entry) ->
    {ok, Split_descriptions_re} = regexp:parse("\n----------------*\n"),
    {ok, [Header | Descriptions]} = regexp:split(Entry, Split_descriptions_re),
    Header_keys = make_key_value_pairs(Header, "\n"),
    Working_file = lookup('Working file', Header_keys),
    #vc_log_file{rcs_file = lookup('RCS file', Header_keys),
		 working_file = Working_file,
		 head = lookup(head, Header_keys),
		 commits = [ parse_cvs_single_commit(Working_file, Desc)
			     || Desc <- Descriptions ]}.

%% Only works with CVS data.
test_read_file(File_name) ->
    {ok, Data} = file:read_file(File_name),
    {ok, Re} = regexp:parse("\n================*\n\n"),
    %% io:format("[re is ~p]~n", [Re]),
    {ok, Chunks} = regexp:split(binary_to_list(Data), Re),
    {ok, [ parse_cvs_single_file_entry(C) || C <- Chunks ]}.
