# IPC::Locker.pm -- distributed lock handler

# RCS Status      : $Id: Server.pm,v 1.3 1999/06/02 13:54:54 wsnyder Exp $
# Author          : Wilson Snyder <wsnyder@ultranet.com>

######################################################################
#
# This program is Copyright 1998 by Wilson Snyder.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# If you do not have a copy of the GNU General Public License write to
# the Free Software Foundation, Inc., 675 Mass Ave, Cambridge, 
# MA 02139, USA.
######################################################################

=head1 NAME

IPC::Locker::Server - Distributed lock handler server

=head1 SYNOPSIS

  use IPC::Locker::Server;

  IPC::Locker::Server->start_server(port=>1234,);

=head1 DESCRIPTION

C<IPC::Locker::Server> provides the server for the IPC::Locker package.

=over 4

=item start_server ([parameter=>value ...]);

Starts the server.  Does not return.

=head1 PARAMETERS

=item port

The port number of the lock server.  Defaults to 1751.

=head1 SEE ALSO

C<lockerd>, C<IPC::Locker>, 

=head1 DISTRIBUTION

This package is distributed via CPAN.

=head1 AUTHORS

Wilson Snyder <wsnyder@ultranet.com>

=cut

######################################################################

package IPC::Locker::Server;
require 5.004;
require Exporter;
@ISA = qw(Exporter);

use IPC::Locker;
use Socket;
use IO::Socket;

use strict;
use vars qw($VERSION $Debug %Locks);
use Carp;

######################################################################
#### Configuration Section

# Other configurable settings.
$Debug = 0;

$VERSION = $IPC::Locker::VERSION;

######################################################################
#### Globals

# All held locks
%Locks = ();

######################################################################
#### Creator

sub start_server {
    # Establish the server
    @_ >= 1 or croak 'usage: IPC::Locker->new ({options})';
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
	#Documented
	port=>$IPC::Locker::Default_Port,
	@_,};
    bless $self, $class;

    # Open the socket
    print "Listening on $self->{port}\n" if $Debug;
    my $server = IO::Socket::INET->new( Proto     => 'tcp',
					LocalPort => $self->{port},
					Listen    => SOMAXCONN,
					Reuse     => 1)
	or die "$0: Error, socket: $!";

    $SIG{ALRM} = \&sig_alarm;

    while (my $clientfh = $server->accept()) {
	alarm (0);
	print $clientfh "HELLO\n" if $Debug;
	#
	my $clientvar = {socket=>$clientfh,
			 delayed=>0,
		     };
	client_service ($clientvar);
	recheck_locks();
    }
}

######################################################################
######################################################################
#### Client servicing

sub client_service {
    # Loop getting commands from a specific client
    my $clientvar = shift || die;
    
    while (1) {
	my $clientfh = $clientvar->{socket};
	last if (!defined $clientfh);
	last if (!defined (my $line = <$clientfh>));
	chomp $line;
	print "REQ $line\n" if $Debug;
	$clientvar->{user} = $1 if ($line =~ /^user\s+(\S*)$/m);
	$clientvar->{lock} = $1 if ($line =~ /^lock\s+(\S*)$/m);
	$clientvar->{block} = $1 if ($line =~ /^block\s+(\S*)$/m);
	$clientvar->{timeout} = $1 if ($line =~ /^timeout\s+(\S*)$/m);
	# Commands
	client_unlock ($clientvar) if ($line =~ /^UNLOCK$/m);
	client_status ($clientvar) if ($line =~ /^STATUS$/m);
	client_break  ($clientvar) if ($line =~ /^BREAK_LOCK$/m);
	die "restart"              if ($line =~ /^RESTART$/m);
	if ($line =~ /^LOCK$/m) {
	    my $wait = client_lock ($clientvar);
	    last if $wait;
	}
	if ($line =~ /^EOF$/m) {
	    $clientvar->{socket}->close();
	    $clientvar->{socket} = undef;
	    undef $clientvar;
	    last;
	}
    }
}

sub client_status {
    # Send status of lock back to client
    my $clientvar = shift || die;
    my $locki = locki_lookup ($clientvar->{lock});
    $clientvar->{locked} = ($locki->{owner} eq $clientvar->{user})?1:0;
    $clientvar->{owner} = $locki->{owner};
    if ($clientvar->{locked} && $clientvar->{told_locked}) {
	$clientvar->{told_locked} = 0;
	client_send ($clientvar, "print_obtained\n");
    }
    client_send ($clientvar, "owner $locki->{owner}\n");
    client_send ($clientvar, "locked $clientvar->{locked}\n");
    client_send ($clientvar, "error $clientvar->{error}\n") if $clientvar->{error};
    return client_send ($clientvar, "\n\n");
}

sub client_lock {
    # Client wants this lock, return true if delayed transaction
    my $clientvar = shift || die;
    my $locki = locki_lookup ($clientvar->{lock});
    while (1) {
	# Already locked by this guy?
	last if ($locki->{owner} eq $clientvar->{user} && $locki->{locked});

	# Non blocking?
	last if (!$clientvar->{block} && $locki->{locked} && !defined $locki->{waiters}[0]);

	if ($locki->{locked}) {
	    $clientvar->{told_locked} = 1;
	    client_send ($clientvar, "print_waiting $locki->{owner}\n");
	}

	# Either need to wait for timeout, or someone else to return key
	push @{$locki->{waiters}}, $clientvar;
	return 1;	# Exit loop and check if can lock
    }
    client_status ($clientvar);
}

sub client_break {
    my $clientvar = shift || die;
    my $locki = locki_lookup ($clientvar->{lock});
    if ($locki->{locked}) {
	print "broke lock   $locki->{lock} User $clientvar->{user}\n" if $Debug;
	client_send ($clientvar, "print_broke $locki->{owner}\n");
	locki_unlock ($locki);
    }
    client_status ($clientvar);
}

sub client_unlock {
    # Client request to unlock the given lock
    my $clientvar = shift || die;
    my $locki = locki_lookup ($clientvar->{lock});
    if ($locki->{owner} eq $clientvar->{user}) {
	print "Unlocked   $locki->{lock} User $clientvar->{user}\n" if $Debug;
	locki_unlock ($locki);
    } else {
	# Doesn't hold lock but might be waiting for it.
	for (my $n=0; $n <= (length @{$locki->{waiters}}); $n++) {
	    if ($locki->{waiters}[$n]{user} eq $clientvar->{user}) {
		print "Dewait     $locki->{lock} User $clientvar->{user}\n" if $Debug;
		splice @{$locki->{waiters}}, $n, 1;
	    }
	}
    }
    client_status ($clientvar);
}

sub client_send {
    # Send a string to the client, return 1 if success
    my $clientvar = shift || die;
    my $msg = shift;

    my $clientfh = $clientvar->{socket};
    return 0 if (!$clientfh);
    print "RESP $clientfh '$msg" if $Debug;

    local $SIG{PIPE} = 'IGNORE';
    my $status = print $clientfh $msg;
    if ($? || !$status) {
	warn "client_send hangup $clientfh $?" if $Debug;
	undef $clientvar->{socket};
	return 0;
    }
    return 1;
}

######################################################################
######################################################################
#### Alarm handler

sub sig_alarm {
    print "Alarm\n" if $Debug;
    alarm(0);
    $SIG{ALRM} = \&sig_alarm;
    recheck_locks();
}

sub set_alarm {
    # Compute alarm interval and set
    my $time = time();
    my $timelimit = undef;
    foreach my $locki (values %Locks) {
	if ($locki->{locked}) {
	    $timelimit = $locki->{timelimit} if (!defined $timelimit
						 || $locki->{timelimit} <= $time);
	}
    }
    my $alarm = $timelimit ? ($timelimit - $time + 1) : 0;
    if ($alarm > 0) {
	print "Alarming in $alarm\n" if $Debug;
	alarm ($alarm);
    }
}

######################################################################
######################################################################
#### Internals

sub locki_lock {
    # Give lock to next requestor that accepts it
    my $locki = shift || die;

    while (my $clientvar = shift @{$locki->{waiters}}) {
	$locki->{locked} = 1;
	$locki->{owner} = $clientvar->{user};
	$locki->{timelimit} = $clientvar->{timeout} + time();
	print "Issuing $locki->{lock} $locki->{owner}\n" if $Debug;
	if (client_status ($clientvar)) {
	    # Worked ok
	    last;
	}
	# Else hung up, didn't get the lock, give to next guy
	print "Hangup  $locki->{lock} $locki->{owner}\n" if $Debug;
	locki_unlock ($locki);
    }
}

sub locki_unlock {
    # Unlock this lock
    my $locki = shift || die;
    $locki->{locked} = 0;
    $locki->{owner} = "unlocked";
}

sub recheck_locks {
    # Main loop to see if any locks have changed state
    alarm (0);	# So doesn't trigger in this loop
    my $time = time();
    foreach my $locki (values %Locks) {
	if ($locki->{locked} && $locki->{timelimit} <= $time) {
	    print "Timeout $locki->{lock} $locki->{owner}\n" if $Debug;
	    locki_unlock ($locki);
	}
	while (!$locki->{locked} && defined $locki->{waiters}[0]) {
	    locki_lock ($locki);
	}
    }
    set_alarm();
}

sub locki_lookup {
    my $lockname = shift || "lock";
    # Return hash for given lock name, create if doesn't exist
    if (!defined $Locks{$lockname}{lock}) {
	$Locks{$lockname} = {
	    lock=>$lockname,
	    locked=>0,
	    owner=>"unlocked",
	    waiters=>[],
	};
    }
    return $Locks{$lockname};
}

######################################################################
#### Package return
1;
