# $Id: Makefile.PL,v 1.5 2001/02/13 15:11:13 wsnyder Exp $
# DESCRIPTION: Perl ExtUtils: Type 'perl Makefile.PL' to create a Makefile for this package

use ExtUtils::MakeMaker;
use Carp;

sub MY::postamble {
"
README: readme.texi
	-rm \$@
	makeinfo \$< --output \$@ --no-headers --no-validate

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
	      EXE_FILES => [qw( lockerd )],
	      'dist'    => {COMPRESS => 'gzip -9f',
			    SUFFIX   => '.gz', 
			    DIST_DEFAULT => 'README all tardist',
			},
	      );

