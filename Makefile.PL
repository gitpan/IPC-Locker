# $Id: Makefile.PL,v 1.1 1999/03/15 17:11:33 wsnyder Exp $

use ExtUtils::MakeMaker;
use Carp;

sub MY::postamble {
"
README: readme.texi
	-rm \$@
	makeinfo \$< --output \$@ --no-headers --no-validate

maintainer-clean: distclean
	-rm README Makefile
";
}

## Remember to upgrade version number!
WriteMakefile(
	DISTNAME  => 'IPC-Locker',
	NAME      => 'IPC::Locker',
	VERSION_FROM => 'Locker.pm',
	EXE_FILES => [qw( lockerd )],
	'dist'    => {COMPRESS => 'gzip -9f',
		      SUFFIX   => '.gz', 
		      DIST_DEFAULT => 'README all tardist',
		     },
	);

