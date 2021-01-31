# Script publication, testing, and documentation.
#
# [created.  -- rgr, 27-Feb-03.]
#

# make INSTALL_OPTS=--diff install

# [install.pl may not work without "perl", as it may not be executable.]
INSTALL_OPTS = --show
INSTALL = perl install.pl ${INSTALL_OPTS}

PREFIX = /usr/local
bin-directory = ${PREFIX}/bin
# Ask Perl where to put site-specific *.pm files.
pm-directory  = ${shell eval "`perl -V:installsitelib`"; \
			cd $$installsitelib; \
			pwd}

# All but ${backup-scripts}.
base-scripts =  ${log-scripts} ${install-scripts} \
		${vc-scripts} ${misc-scripts}
backup-scripts = backup.pl backup-dbs.pl clean-backups.pl cd-dump.pl \
		 show-backups.pl svn-dump.pl vacuum.pl
# [we call xauth-local-host a script, but really it needs to be sourced.  --
# rgr, 5-Dec-04.]
root-scripts = xauth-local-host
log-scripts = find-net-mounts.pl
# mail manipulation scripts.
mail-scripts = mbox-grep.pl mbox2maildir.pl no-such-user.pl \
		email/forged-local-address.pl
# installation of various things, including these guys.
install-scripts = install.pl copy-tree substitute-config.pl
# utility scripts for version control systems.
vc-scripts =    cvs-chrono-log.pl svn-chrono-log.pl \
		vc-chrono-log.pl vc-chrono-log.rb
# random stuff that doesn't belong anywhere else.
misc-scripts =	sdiff.pl html-diff.pl split-discord-html.pl
perl-modules = 
# firewall-scripts must go into /etc/init.d to be useful.
firewall-scripts = paranoid firewall

all:
	@echo Nobody here but us scripts.
	@echo So tell me what you really want to do, e.g. \"make test\".

test:	test-diff test-chrono-log test-email test-backup

test-chrono-log:	test-cvs-chrono-log-1 test-cvs-chrono-log-2 \
			test-cvs-chrono-log-3 test-svn-chrono-log-1a \
			test-git-chrono-log-1
test-cvs-chrono-log-1:
	./cvs-chrono-log.pl < test/test-cvs-chrono-log.text > $@.tmp
	cmp test/test-cvs-chrono-log.out $@.tmp
	./vc-chrono-log.pl < test/test-cvs-chrono-log.text > $@.tmp
	cmp test/test-cvs-chrono-log.out $@.tmp
	rm -f $@.tmp
test-cvs-chrono-log-2:
	./vc-chrono-log.rb < test/test-cvs-chrono-log.text > $@.tmp
	cmp test/test-cvs-chrono-log.out $@.tmp
	rm -f $@.tmp
test-cvs-chrono-log-3:
	./vc-chrono-log.py < test/test-cvs-chrono-log.text > $@.tmp
	cmp test/test-cvs-chrono-log.out $@.tmp
	rm -f $@.tmp
# Test CVS "commitid" processing.
test-cvs-chrono-log-4:		vc-chrono-log.exe
	./vc-chrono-log.pl < test/$@.text > $@.tmp
	cmp test/$@.out $@.tmp
	./vc-chrono-log.rb < test/$@.text > $@.tmp
	cmp test/$@.out $@.tmp
	./vc-chrono-log.py < test/$@.text > $@.tmp
	cmp test/$@.out $@.tmp
	rm -f $@.tmp
test-svn-chrono-log-1a:
	./svn-chrono-log.pl < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	./vc-chrono-log.pl < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	./vc-chrono-log.rb < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	./vc-chrono-log.py < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp $@.tmp test/$@-out.text
	rm -f $@.tmp
test-git-chrono-log-1:
	./vc-chrono-log.pl < test/$@-in.text > $@.tmp
	cmp test/$@.text $@.tmp
	./vc-chrono-log.pl < test/$@-stat-in.text > $@.tmp
	cmp test/$@-stat.text $@.tmp
# Test tags.
	cat test/$@-tags.text test/$@-in.text | ./vc-chrono-log.pl > $@.tmp
	cmp test/$@-tag-out.text $@.tmp
	cat test/$@-tags.text test/$@-in.text \
		| perl -pe 's/.{30}$$// if /^commit /;' \
		| ./vc-chrono-log.pl --abbrev 7 > $@.tmp
	cmp test/$@-tag-out.text $@.tmp
# Test commit ID abbreviation.
	./vc-chrono-log.pl --abbrev 7 < test/$@-in.text > $@.tmp
	cmp test/$@.text $@.tmp
	cat test/$@-tags.text test/$@-in.text \
		| perl -pe 's/.{20}$$// if /^commit /;' \
		| ./vc-chrono-log.pl --abbrev 10 > $@.tmp
	cmp test/$@-long-tag.text $@.tmp
	rm -f $@.tmp
# Test the C# version separately, since "mono" may not be installed.
vc-chrono-log.exe:		vc-chrono-log.cs
	gmcs $^
test-csharp-chrono-log:	vc-chrono-log.exe
	mono vc-chrono-log.exe < test/test-cvs-chrono-log.text > $@.tmp
	cmp test/test-cvs-chrono-log.out $@.tmp
	mono vc-chrono-log.exe < test/test-cvs-chrono-log-4.text > $@.tmp
	cmp test/test-cvs-chrono-log-4.out $@.tmp
	mono $^ < test/test-svn-chrono-log-1.xml > $@.tmp
	cmp test/test-svn-chrono-log-1a-out.text $@.tmp
	rm -f $@.tmp
# This assumes we are in a Subversion working copy, and checks that the Perl,
# Ruby, Python, and C# versions get the same thing for the same *current* log.
# [It is no longer on test-chrono-log because I no longer have a Subversion
# repo for this project.  -- rgr, 26-Jan-21.]
test-compare-languages:	vc-chrono-log.exe
	(cd ../scripts.svn && svn log --xml --verbose) > $@.tmp.xml
	./vc-chrono-log.pl < $@.tmp.xml > $@.tmp.pl.text
	mono $^ < $@.tmp.xml > $@.tmp.cs.text
	cmp $@.tmp.pl.text $@.tmp.cs.text
	./vc-chrono-log.rb < $@.tmp.xml > $@.tmp.rb.text
	cmp $@.tmp.pl.text $@.tmp.rb.text
	./vc-chrono-log.py < $@.tmp.xml > $@.tmp.py.text
	cmp $@.tmp.pl.text $@.tmp.py.text
	rm -f $@.tmp.*

test-email:	test-forged-address test-deliver
test-deliver:
	perl email/test-qmail-deliver.pl
test-forged-address:	test-rgrjr-forged-address \
		test-nonforged-addresses \
		test-new-forged-address test-postfix-forged-address \
		test-postfix-forged-2
rgrjr-config-options = --locals email/rgrjr-locals.text \
		--network-prefix 192.168.57
test-rgrjr-forged-address:
	SENDER=rogers@rgrjr.dyndns.org perl -Mlib=. email/forged-local-address.pl \
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
		${rgrjr-config-options} < email/spam-5.text
	SENDER=rogers@somewhere.com email/forged-local-address.pl \
		--sender-re='@perl.org$$' \
		${rgrjr-config-options} < email/perl6-spam.text
	SENDER=invokingsd0@rayongzone.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-6.text
	SENDER=whoever@wherever.com email/forged-local-address.pl \
		${rgrjr-config-options} < email/spam-7.text
test-nonforged-addresses:
	SENDER=perl6-internals-return-48162-etc@perl.org \
	    email/forged-local-address.pl --sender-re='@perl.org$$' --not \
		${rgrjr-config-options} < email/perl6-non-spam.text
	SENDER=jan@rgrjr.dyndns.org email/forged-local-address.pl --not \
		${rgrjr-config-options} < email/from-jan-2.text
	SENDER=jan@rgrjr.dyndns.org email/forged-local-address.pl --not \
		${rgrjr-config-options} < email/from-jan-3.text
	SENDER=root@rgrjr.com email/forged-local-address.pl --not \
		${rgrjr-config-options} < email/rgrjr-non-spam-1.text
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
test-postfix-forged-2:
	SENDER=rogers@somewhere.org email/forged-local-address.pl \
		${rgrjr-config-options} < email/rgrjr-forged-1.text
	SENDER=somebody@someewhere.org email/forged-local-address.pl \
		${rgrjr-config-options} < email/rgrjr-forged-2.text

test-backup:	test-backup-classes
test-backup-classes:
	perl -MTest::Harness -e 'runtests(@ARGV);' \
		test/test-backup-classes.pl \
		test/test-config.pl
# This is too ephemeral to add as a test-backup dependency.
test-vacuum:
	perl -Mlib=. ./vacuum.pl --test --prefix home --min-free 100 \
		/scratch3/backups orion:/scratch2/backups > $@.tmp
	cmp $@.text $@.tmp
	perl -Mlib=. ./vacuum.pl --config /dev/null --test > $@.tmp
	test -z "`cat $@.tmp`"
	perl -Mlib=. ./vacuum.pl --config backup.conf --test > $@.tmp
	cmp $@.text $@.tmp
	rm -f $@.tmp

## Testing the html-diff.pl script.
test-diff:	test-diff-tok-1 test-diff-1 test-diff-2 test-diff-3 \
		test-diff-4 test-diff-5 test-diff-6
test-diff-tok-1:
	./html-diff.pl --test-split test/html/$@-in.patch > $@.tmp
	cmp test/html/$@.patch $@.tmp
	rm -f $@.tmp
test-diff-1:	test/html/test-diff-tok-1-in.patch
	./html-diff.pl $^ > $@.tmp
	cmp test/html/$@.patch $@.tmp
	./html-diff.pl --line-length 40 $^ > $@.tmp
	cmp test/html/$@-40.patch $@.tmp
	./html-diff.pl --line-length 0 $^ > $@.tmp
	cmp test/html/$@-0.patch $@.tmp
	rm -f $@.tmp
test-diff-2:
	./html-diff.pl test/html/$@-in.patch > $@.tmp
	cmp test/html/$@.patch $@.tmp
	rm -f $@.tmp
test-diff-3:
	./html-diff.pl test/html/$@-in.patch > $@.tmp
	cmp test/html/$@.patch $@.tmp
	rm -f $@.tmp
test-diff-4:
	./html-diff.pl test/html/$@-in.patch > $@.tmp
	cmp test/html/$@.patch $@.tmp
	rm -f $@.tmp
# Regression test for pure line insertion/deletion.
test-diff-5:
	./html-diff.pl test/html/$@-in.patch > $@.tmp
	cmp test/html/$@.patch $@.tmp
	rm -f $@.tmp
# Regression test for line breaks.
test-diff-6:
	./html-diff.pl < test/html/$@-in.patch > $@.tmp
	cmp test/html/$@-out.patch $@.tmp
	rm -f $@.tmp
# Another regression test for line breaks.
test-diff-7:
	./html-diff.pl < test/html/$@-in.patch > $@.tmp
	cmp test/html/$@-out.patch $@.tmp
	rm -f $@.tmp

# This can't be put on the "test" target because it's too hard to make test
# cases that last more than a day.
test-show-backups:
	./show-backups.pl > $@.tmp
	cmp $@-1.text $@.tmp
	./show-backups.pl --prefix shared > $@.tmp
	cmp $@-2.text $@.tmp
	./show-backups.pl --prefix home --sl > $@.tmp
	cmp $@-3.text $@.tmp
	./show-backups.pl --sort=date > $@.tmp
	cmp $@-4.text $@.tmp
	./show-backups.pl --level 1 --size-by-date > $@.tmp
	cmp $@-5.text $@.tmp
	rm $@.tmp

install:	install-base
install-base:
	${INSTALL} -m 444 ${perl-modules} ${pm-directory}
	${INSTALL} -m 555 ${base-scripts} ${mail-scripts} ${bin-directory}
	${INSTALL} -m 555 ${root-scripts} /root/bin
# install burn-backups only if not already there; usually it gets
# customized per host.
	if [ ! -r /root/bin/burn-backups ]; then \
	    ${INSTALL} -m 555 burn-backups /root/bin; \
	fi
install-backup:
	mkdir -p ${pm-directory}/Backup
	${INSTALL} -m 444 Backup/*.pm ${pm-directory}/Backup
	${INSTALL} -m 555 ${backup-scripts} ${bin-directory}

uninstall-root-bin:
	for file in ${perl-modules} ${base-scripts}; do \
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

### Other oddments.

clean:
	rm -f *.tmp
tags:
	find . -name '*.p[lm]' -o -name '*.rb' -o -name '*.el' \
		-o -name '*.erl' -o -name '*.py' \
	    | etags --regex '/[ \t]*\(class\|module\|def\) +\([^ \t()<>]+\)/\2/' -
