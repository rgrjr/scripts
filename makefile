# Publication of backup scripts and documentation.
#
#    Modification history:
#
# created.  -- rgr, 27-Feb-03.
#

all:
	@echo Tell me what you really want me to do, e.g. \"make publish\".

public-html-directory = /usr/local/aolserver/servers/rgrjr/pages/linux
published-scripts = backup.pl cd-dump.pl
html-pages = ${published-scripts:.pl=.pl.html}

all-scripts = ${backup-scripts} ${log-scripts} ${qmail-scripts} ${afpd-scripts}
backup-scripts = backup.pl cd-dump.pl partition-backup-sizes.pl
log-scripts = check-logs.pl daily-status.pl extract-subnet.pl squid-log.pl \
		tripwire-verify
qmail-scripts = qmail-restart qmail-redeliver qifq.pl
afpd-scripts = afpd-stat.pl atwho.pl cp-if-newer.pl rename-into-tree.pl

install:
	./install.pl -c -m 755 ${all-scripts} /root/bin

${html-pages}:   %.pl.html:	%.pl
	pod2html $^ > $@

publish:	${published-scripts} ${html-pages}
	install -c -m 444 $^ ${public-html-directory}
