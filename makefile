# Publication of backup scripts and documentation.
#
# [created.  -- rgr, 27-Feb-03.]
#
# $Id$

# make INSTALL_OPTS=--diff install

# [for some reason, this does not work without "perl" as root on alexandria; it
# says "make: execvp: ./install.pl: Permission denied", for reasons obscure.  --
# rgr, 28-Jul-03.]
INSTALL_OPTS = --show
INSTALL = perl ./install.pl ${INSTALL_OPTS}

PREFIX = /usr/local
bin-directory = ${PREFIX}/bin
pm-directory = /usr/lib/perl5/site_perl
public-html-directory = /srv/www/htdocs/linux
published-scripts = backup.pl cd-dump.pl vacuum.pl
published-modules = rename-into-tree.pm
html-pages = ${published-scripts:.pl=.pl.html}

base-scripts = ${backup-scripts} ${log-scripts} ${install-scripts} ${vc-scripts}
backup-scripts = backup.pl cd-dump.pl partition-backup-sizes.pl \
		show-backups.pl svn-dump.pl vacuum.pl
# [we call xauth-local-host a script, but really it needs to be sourced.  --
# rgr, 5-Dec-04.]
root-scripts = xauth-local-host burn-backups
# [tripwire-verify used to be on ${log-scripts}, but it's too system-dependent;
# it has hardwired executable paths and system names.  -- rgr, 8-Aug-03.]
log-scripts = check-logs.pl daily-status.pl extract-subnet.pl squid-log.pl \
		squid2std.pl
log-files = nominal-random.text nominal-shutdown.text nominal-startup.text
# mail manipulation scripts.
mail-scripts = mbox-grep.pl mbox2maildir.pl no-such-user.pl \
		email/forged-local-address.pl
# installation of various things, including these guys.
install-scripts = install.pl install-rpms.pl
# utility scripts for version control systems.
vc-scripts = cvs-chrono-log.pl svn-chrono-log.pl
# note that these are scripts used *by* squid.  -- rgr, 19-Oct-03.
squid-scripts = redirect.pl
# Note that tar-backup.pm is not used by anything at the moment.
perl-modules = parse-logs.pm rename-into-tree.pm tar-backup.pm rpm.pm
# firewall-scripts must go into /etc/init.d to be useful.
firewall-scripts = paranoid firewall
# qmail-scripts and afpd-scripts are not installed by default.
qmail-scripts = qmail-restart qmail-redeliver qifq.pl
afpd-scripts = afpd-stat.pl atwho.pl cp-if-newer.pl rename-into-tree.pl

all:
	@echo Nobody here but us scripts.
	@echo So tell me what you really want to do, e.g. \"make publish\".

test:	test-chrono-log test-email

test-chrono-log:
	./cvs-chrono-log.pl < test/test-cvs-chrono-log.text \
		> test-cvs-chrono-log.tmp
	cmp test-cvs-chrono-log.tmp test/test-cvs-chrono-log.out
	rm -f test-cvs-chrono-log.tmp
test-email:	test-forged-address
test-forged-address:
	SENDER=rogers@rgrjr.dyndns.org email/forged-local-address.pl --not < email/from-bob.text
	SENDER=jan@rgrjr.com email/forged-local-address.pl --not < email/from-jan.text
	SENDER=debra@somewhere.com email/forged-local-address.pl --not < email/from-debra.text
	SENDER=rogers@rgrjr.com email/forged-local-address.pl < email/spam-1.text

install:	install-base
install-base:
	${INSTALL} -m 444 ${perl-modules} ${pm-directory}
	${INSTALL} -m 555 ${base-scripts} ${mail-scripts} ${bin-directory}
	${INSTALL} -m 555 ${root-scripts} /root/bin
	${INSTALL} -m 444 ${log-files} /root/bin
install-qmail:
	${INSTALL} -m 555 ${qmail-scripts} ${bin-directory}
install-afpd:
	${INSTALL} -m 555 ${afpd-scripts} ${bin-directory}
install-squid:
	${INSTALL} -m 555 ${squid-scripts} /usr/sbin
	squid -k reconfigure
install-upsd:
	${INSTALL} -m 555 upsd.pl /etc/init.d
	test -e /etc/upsd.conf \
		|| ${INSTALL} -m 400 upsd.sample.conf /etc/upsd.conf

uninstall-root-bin:
	for file in ${perl-modules} ${base-scripts} ${qmail-scripts} \
			${afpd-scripts} ${squid-scripts}; do \
	    if [ -r /root/bin/$$file ]; then \
		echo Removing /root/bin/$$file; \
		rm -f /root/bin/$$file; \
	    fi; \
	done

diff:
	for file in `ls ${bin-directory} | fgrep -v '~'`; do \
	    if [ -r $$file ]; then \
		diff -u ${bin-directory}/$$file $$file; \
	    fi; \
	done

install-firewall:
	${INSTALL} -m 555 ${firewall-scripts} /etc/init.d
diff-firewall:
	for file in ${firewall-scripts}; do \
	    if [ -r $$file ]; then \
		diff -u /etc/init.d/$$file $$file; \
	    fi; \
	done


${html-pages}:   %.pl.html:	%.pl
	pod2html $^ > $@

publish:	${published-scripts} ${published-modules} ${html-pages}
	install -c -m 444 $^ ${public-html-directory}

### Other oddments.

clean:
	rm -f pod2htm*.tmp ${html-pages}
