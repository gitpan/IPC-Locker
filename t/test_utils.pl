#!/usr/local/bin/perl -w
# $Revision: 1.1 $$Date: 2002/08/22 14:31:51 $$Author: wsnyder $
#DESCRIPTION: Perl ExtUtils: Common routines required by package tests

use IO::File;
use IO::Socket;
use Sys::Hostname;
use vars qw($PERL);

$PERL = "$^X -Iblib/arch -Iblib/lib";

if (!$ENV{HARNESS_ACTIVE}) {
    use lib '.';
    use lib '..';
    use lib "blib/lib";
    use lib "blib/arch";
}

######################################################################
######################################################################
# Socket subroutines

sub socket_find_free {
    my $port = shift;	# Port # to start looking on

    for (; $port<(1<<15); $port++) {
	print "Looking for free port $port\n" if $Debug;
	my $fh;
	$fh = IO::Socket::INET->new( Proto     => "tcp",
				     PeerAddr  => hostname(),
				     PeerPort  => $port,
				     );
	if ($fh) { # Port exists, try again
	    $fh->close();
	    next;
	}
	$fh = IO::Socket::INET->new( Proto     => 'tcp',
				     LocalPort => $port,
				     Listen    => SOMAXCONN,
				     Reuse     => 0);
	if ($fh) {
	    $fh->close();
	    return $port;
	}
    }
    die "%Error: Can't find free socket port\n";
}

1;
