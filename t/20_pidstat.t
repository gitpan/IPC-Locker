#!/usr/local/bin/perl -w
#$Id: 20_pidstat.t,v 1.3 2002/07/28 21:33:53 wsnyder Exp $
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

use lib "./blib/lib";
use strict;
use vars qw ($Loaded %SLArgs);

%SLArgs = ();

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..8\n";
	print "****NOTE****: You need './pidstatd &' running for this test!\n";
    }

END {print "not ok 1\n" unless $Loaded;}
use IPC::PidStat;
$IPC::PidStat::Debug=1;
$Loaded = 1;
print "ok 1\n";

######################### End of black magic.

# Static checks
print +(IPC::PidStat::local_pid_exists($$) ? "ok 2\n" : "not ok 2\n");
print +(!IPC::PidStat::local_pid_doesnt_exist($$) ? "ok 3\n" : "not ok 3\n");

# Constructor
my $exister = new IPC::PidStat
    (%SLArgs,
     );
print +($exister ? "ok 4\n" : "not ok 4\n");

# Send request and check return
print +((check_stat($exister,12345)
	 ) ? "ok 5\n" : "not ok 5\n");

print +((check_stat($exister,66666)
	 ) ? "ok 6\n" : "not ok 6\n");

print +((check_stat($exister,$$)
	 ) ? "ok 7\n" : "not ok 7\n");

# Destructor
undef $exister;
print "ok 8\n";

sub check_stat {
    my $exister = shift;
    my $pid = shift;

    my $tries = 5;   # Number of messages to send.  We'll hope one gets
    # through to the server.  Since it's the local host, that seems almost
    # certain.

    my $pid_pre_exists = kill(0,$pid);
    my @recved;
    for (my $try=0; $try<$tries; $try++) {
	$exister->pid_request(pid=>$pid);
	eval {
	    local $SIG{ALRM} = sub { die "Timeout\n"; };
	    alarm(1);
	    @recved = $exister->recv_stat();
	};
	last if defined $recved[0];
    }
    my $pid_post_exists = kill(0,$pid);  # Test again, may have changed state when request in flight.
    if (!defined $recved[0]) {
	warn "\n%Error: Null response for pid $pid: @recved,";
	warn "%Error: Perhaps you forgot to './pidstatd &' for this test?\n";
	return 0;
    } elsif ($recved[0]!=$pid) {
	warn "%Error: Bad PID response for pid $pid: @recved,";
	return 0;
    } elsif ($recved[1]!=$pid_pre_exists && $recved[1]!=$pid_post_exists) {
	warn "%Error: Bad Exists for pid $pid: @recved,";
	return 0;
    }
    return 1;
}
