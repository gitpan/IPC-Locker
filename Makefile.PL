# $Id: Makefile.PL,v 1.3 2000/01/21 14:45:41 wsnyder Exp $

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
	      AUTHOR	=> 'Wilson Snyder <wsnyder@world.std.com>',
	      ABSTRACT_FROM => 'Locker.pm',
	      VERSION_FROM => 'Locker.pm',
	      EXE_FILES => [qw( lockerd )],
	      'dist'    => {COMPRESS => 'gzip -9f',
			    SUFFIX   => '.gz', 
			    DIST_DEFAULT => 'README all tardist',
			},
	      );

