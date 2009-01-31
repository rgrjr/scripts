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
# Ask Perl where to put site-specific *.pm files.
pm-directory  = ${shell eval "`perl -V:installsitelib`"; \
			cd $$installsitelib; \
			pwd}
public-html-directory = /srv/www/htdocs/linux
published-scripts = backup.pl cd-dump.pl vacuum.pl
published-modules = rename-into-tree.pm
html-pages = ${published-scripts:.pl=.pl.html}

base-scripts = ${backup-scripts} ${log-scripts} ${install-scripts} ${vc-scripts}
backup-scripts = backup.pl cd-dump.pl partition-backup-sizes.pl \
		show-backups.pl svn-dump.pl vacuum.pl
# [we call xauth-local-host a script, but really it needs to be sourced.  --
# rgr, 5-Dec-04.]
root-scripts = xauth-local-host
# [tripwire-verify used to be on ${log-scripts}, but it's too system-dependent;
# it has hardwired executable paths and system names.  -- rgr, 8-Aug-03.]
log-scripts = check-logs.pl daily-status.pl extract-subnet.pl squid-log.pl \
		squid2std.pl
log-files = nominal-random.text nominal-shutdown.text nominal-startup.text
# mail manipulation scripts.
mail-scripts = mbox-grep.pl mbox2maildir.pl no-such-user.pl \
		email/forged-local-address.pl
# installation of various things, including these guys.
install-scripts = install.pl install-rpms.pl copy-tree
# utility scripts for version control systems.
vc-scripts = cvs-chrono-log.pl svn-chrono-log.pl vc-chrono-log.rb
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

test-chrono-log:	test-cvs-chrono-log-1 test-cvs-chrono-log-2 \
		test-svn-chrono-log-1a test-svn-chrono-log-1b \
		test-perl-vs-ruby
test-cvs-chrono-log-1:
	./cvs-chrono-log.pl < test/test-cvs-chrono-log.text > $@.tmp
	cmp $@.tmp test/test-cvs-chrono-log.out
	./vc-chrono-log.pl < test/test-cvs-chrono-log.text > $@.tmp
	cmp $@.tmp test/test-cvs-chrono-log.out
	rm -f $@.tmp
test-cvs-chrono-log-2:
	./vc-chrono-log.rb < test/test-cvs-chrono-log.text > $@.tmp
	cmp $@.tmp test/test-cvs-chrono-log.out
	./vc-chrono-log.pl < test/test-cvs-chrono-log.text > $@.tmp
	cmp $@.tmp test/test-cvs-chrono-log.out
	rm -f $@.tmp
test-svn-chrono-log-1a:
	./svn-chrono-log.pl < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	./vc-chrono-log.pl < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	rm -f $@.tmp
test-svn-chrono-log-1b:
	./vc-chrono-log.rb < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/test-svn-chrono-log-1a-out.text
	./vc-chrono-log.pl < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/test-svn-chrono-log-1a-out.text
	rm -f $@.tmp
# This assumes we are in a Subversion working copy, and checks that the Perl and
# Ruby versions get the same thing for the same *current* log.
test-perl-vs-ruby:
	svn log --xml --verbose > $@.tmp.text
	./vc-chrono-log.pl < $@.tmp.text > $@.tmp.pl.text
	./vc-chrono-log.rb < $@.tmp.text > $@.tmp.rb.text
	cmp $@.tmp.pl.text $@.tmp.rb.text
	rm -f $@.tmp.*

test-email:	test-forged-address
test-forged-address:	test-rgrjr-forged-address \
		test-new-forged-address test-postfix-forged-address
rgrjr-config-options = --locals email/rgrjr-locals.text \
		--network-prefix 192.168.57
test-rgrjr-forged-address:
	SENDER=rogers@rgrjr.dyndns.org email/forged-local-address.pl \
		${rgrjr-config-options} --not < email/from-bob.text
	SENDER=jan@rgrjr.com email/forged-local-address.pl \
		${rgrjr-config-options} --not < email/from-jan.text
	SENDER=debra@somewhere.com email/forged-local-address.pl \
		${rgrjr-config-options} --not < email/from-debra.text
	SENDER=rogers@rgrjr.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-1.text
	SENDER=wiieme@foo.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-2.text
# So we don't have a zillion tests in the same target.
test-new-forged-address:
	SENDER=rogerryals@hcsmail.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/viagra-inc.text
	SENDER=rogers@somewhere.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-3.text
	SENDER=rogers@somewhere.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-4.text
	SENDER=rogers@somewhere.com email/forged-local-address.pl \
		--sender-re='@perl.org$$' \
		${rgrjr-config-options} < email/perl6-spam.text
	SENDER=perl6-internals-return-48162-etc@perl.org \
	    email/forged-local-address.pl --sender-re='@perl.org$$' --not \
		${rgrjr-config-options} < email/perl6-non-spam.text
modgen-config-options = --add-local modulargenetics.com \
		--network-prefix 192.168.23
test-postfix-forged-address:
	SENDER=rogers@rgrjr.dyndns.org email/forged-local-address.pl \
		${modgen-config-options} --not < email/modgen-local.msg
	SENDER=somebody@rgrjr.dyndns.org email/forged-local-address.pl \
		${modgen-config-options} --not < email/modgen-lan.msg
	SENDER=somebody@somewhere.com email/forged-local-address.pl \
		${modgen-config-options} --not < email/modgen-external.msg
	SENDER=spammer@modulargenetics.com email/forged-local-address.pl \
		${modgen-config-options} < email/modgen-external.msg

# This can't be put on the "test" target because it's too hard to make test
# cases that last more than a day.
test-show-backups:
	./show-backups.pl > $@.tmp
	cmp $@-1.text $@.tmp
	./show-backups.pl --prefix sequencing > $@.tmp
	cmp $@-2.text $@.tmp
	rm $@.tmp

install:	install-base
install-base:
	${INSTALL} -m 444 ${perl-modules} ${pm-directory}
	mkdir -p ${pm-directory}/Backup
	${INSTALL} -m 444 Backup/*.pm ${pm-directory}/Backup
	${INSTALL} -m 555 ${base-scripts} ${mail-scripts} ${bin-directory}
	${INSTALL} -m 555 ${root-scripts} /root/bin
	${INSTALL} -m 444 ${log-files} /root/bin
	# install burn-backups only if not already there; usually it gets
	# customized per host.
	if [ ! -r /root/bin/burn-backups ]; then \
	    ${INSTALL} -m 555 burn-backups /root/bin; \
	fi
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

${html-pages}:   %.pl.html:	%.pl
	pod2html $^ > $@

publish:	${published-scripts} ${published-modules} ${html-pages}
	install -c -m 444 $^ ${public-html-directory}

### Other oddments.

clean:
	rm -f pod2htm*.tmp ${html-pages}
tags:
	find . -name '*.p[lm]' -o -name '*.rb' \
	    | etags --regex '/[ \t]*\(class\|module\|def\) +\([^ \t()<>]+\)/\2/' -
