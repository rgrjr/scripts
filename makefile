# Publication of backup scripts and documentation.
#
# [created.  -- rgr, 27-Feb-03.]
#
# $Id$

# [for some reason, this does not work without "perl" as root on alexandria; it
# says "make: execvp: ./install.pl: Permission denied", for reasons obscure.  --
# rgr, 28-Jul-03.]
INSTALL = perl ./install.pl -show

public-html-directory = /usr/local/aolserver/servers/rgrjr/pages/linux
published-scripts = backup.pl cd-dump.pl
html-pages = ${published-scripts:.pl=.pl.html}

root-scripts = ${backup-scripts} ${log-scripts}
backup-scripts = backup.pl cd-dump.pl partition-backup-sizes.pl vacuum.pl
log-scripts = check-logs.pl daily-status.pl extract-subnet.pl squid-log.pl \
		tripwire-verify
log-files = nominal-random.text nominal-shutdown.text nominal-startup.text
# Note that tar-backup.pm is not used by anything at the moment.
perl-modules = parse-logs.pm rename-into-tree.pm tar-backup.pm
# qmail-scripts and afpd-scripts are not installed by default.
qmail-scripts = qmail-restart qmail-redeliver qifq.pl
afpd-scripts = afpd-stat.pl atwho.pl cp-if-newer.pl rename-into-tree.pl

all:
	@echo Nobody here but us scripts.
	@echo So tell me what you really want to do, e.g. \"make publish\".

install:	install-base install-qmail install-afpd
install-base:
	${INSTALL} -m 555 ${root-scripts} /root/bin
	${INSTALL} -m 444 ${perl-modules} ${log-files} /root/bin
install-qmail:
	${INSTALL} -m 555 ${qmail-scripts} /root/bin
install-afpd:
	${INSTALL} -m 555 ${afpd-scripts} /root/bin

${html-pages}:   %.pl.html:	%.pl
	pod2html $^ > $@

publish:	${published-scripts} ${html-pages}
	install -c -m 444 $^ ${public-html-directory}
