# Publication of backup scripts and documentation.
#
#    Modification history:
#
# created.  -- rgr, 27-Feb-03.
#

all:
	@echo Tell me what you really want me to do, e.g. \"make publish\".

public-html-directory = /usr/local/aolserver/servers/rgrjr/pages/linux
published-scripts = backup.pl
html-pages = ${published-scripts:.pl=.pl.html}

${html-pages}:   %.pl.html:	%.pl
	pod2html $^ > $@

publish:	${published-scripts} ${html-pages}
	install -c -m 444 $^ ${public-html-directory}
