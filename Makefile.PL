# $Id: Makefile.PL,v 1.14 2003/09/22 19:30:50 wsnyder Exp $
# DESCRIPTION: Perl ExtUtils: Type 'perl Makefile.PL' to create a Makefile for this package
#
# Copyright 1999-2003 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

require 5.005;
use ExtUtils::MakeMaker;
use Carp;

sub MY::postamble {
"
README: readme.texi
	-rm \$@
	makeinfo \$< --output \$@ --no-headers --no-validate

install::
	\@echo
	\@echo -NOTE: You may want to 'cp init.d/lockerd  /etc/init.d'
	\@echo -NOTE:                 'cp init.d/pidstatd /etc/init.d'
	\@echo -NOTE: And setup appropriate links in /etc/rc.d/rc3.d

install-here::
	make INSTALLMAN1DIR=/usr/local/man/man1 INSTALLMAN3DIR=/usr/local/man/man3 INSTALLBIN=/usr/local/bin INSTALLSCRIPT=/usr/local/bin install

## Maintainer use:
tag:
	cvs tag -F \$(DISTNAME)_\$(VERSION_SYM) .

maintainer-dist: dist tag
	cp \$(DISTVNAME).tar.gz \$(HOME)/src/kits
	mv \$(DISTVNAME).tar.gz \$(HOME)/backpack

maintainer-clean: distclean
	-rm README Makefile

dist: distcheck
";
}

## Remember to upgrade version number!
WriteMakefile(
	      DISTNAME  => 'IPC-Locker',
	      NAME      => 'IPC::Locker',
	      AUTHOR	=> 'Wilson Snyder <wsnyder@wsnyder.org>',
	      ABSTRACT_FROM => 'Locker.pm',
	      VERSION_FROM => 'Locker.pm',
	      PMLIBDIRS => ['lib', 'Locker', 'PidStat',],
	      EXE_FILES => [qw( lockerd pidstatd pidwatch )],
	      'dist'    => {COMPRESS => 'gzip -9f',
			    SUFFIX   => '.gz', 
			    DIST_DEFAULT => 'README all tardist',
			},
	      );

