#!/usr/local/bin/perl -w
# $Id: 20_pidstat.t,v 1.6 2003/09/22 19:30:51 wsnyder Exp $
# DESCRIPTION: Perl ExtUtils: Type 'make test' to test this package
# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'
#
# Copyright 1999-2003 by Wilson Snyder.  This program is free software;
# you can redistribute it and/or modify it under the terms of either the GNU
# General Public License or the Perl Artistic License.

use lib "./blib/lib";
use Test;
use strict;
use vars qw (%SLArgs $Serv_Pid);

BEGIN { plan tests => 9 }
BEGIN { require "t/test_utils.pl"; }

END { kill 'TERM', $Serv_Pid; }

#########################
# Constructor

use IPC::PidStat;
$IPC::PidStat::Debug=1;
ok(1);

#########################
# Static checks
ok (IPC::PidStat::local_pid_exists($$));
ok (!IPC::PidStat::local_pid_doesnt_exist($$));

#########################
# Server Constructor

use IPC::PidStat::PidServer;
%SLArgs = (port=>socket_find_free(12345));

if ($Serv_Pid = fork()) {
} else {
    IPC::PidStat::PidServer->new(%SLArgs)->start_server ();
    exit(0);
}
ok (1);
sleep(1); #Let server get established

#########################
# User Constructor

my $exister = new IPC::PidStat
    (%SLArgs,
     );
ok ($exister);

# Send request and check return
ok (check_stat($exister,12345));

ok (check_stat($exister,66666));

ok (check_stat($exister,$$));

# Destructor
undef $exister;
ok (1);

sub check_stat {
    my $exister = shift;
    my $pid = shift;

    my $tries = 5;   # Number of messages to send.  We'll hope one gets
    # through to the server.  Since it's the local host, that seems almost
    # certain.

    my $pid_pre_exists = kill(0,$pid);
    my @recved = $exister->pid_request_recv(pid=>$pid);
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