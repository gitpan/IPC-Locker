# IPC::Locker.pm -- distributed lock handler

# RCS Status      : $Id: Server.pm,v 1.12 2001/02/13 17:37:37 wsnyder Exp $
# Author          : Wilson Snyder <wsnyder@wsnyder.org>

######################################################################
#
# This program is Copyright 2000 by Wilson Snyder.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either the GNU General Public License or the
# Perl Artistic License, with the exception that it cannot be placed
# on a CD-ROM or similar media for commercial distribution without the
# prior approval of the author.
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

=item family

The family of transport to use, either INET or UNIX.  Defaults to INET.

=item port

The port number (INET) or name (UNIX) of the lock server.  Defaults to
'lockerd' looked up via /etc/services, else 1751.

=head1 SEE ALSO

C<lockerd>, C<IPC::Locker>, 

=head1 DISTRIBUTION

This package is distributed via CPAN.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################

package IPC::Locker::Server;
require 5.004;
require Exporter;
@ISA = qw(Exporter);

use IPC::Locker;
use Socket;
use IO::Socket;
use IO::Select;

use strict;
use vars qw($VERSION $Debug %Locks %Clients $Select $Interrupts);
use Carp;

######################################################################
#### Configuration Section

# Other configurable settings.
$Debug = 0;

$VERSION = '1.14';

######################################################################
#### Globals

# All held locks
%Locks = ();

######################################################################
#### Creator

sub new {
    # Establish the server
    @_ >= 1 or croak 'usage: IPC::Locker->new ({options})';
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
	#Documented
	port=>$IPC::Locker::Default_Port,
	family=>$IPC::Locker::Default_Family,
	@_,};
    bless $self, $class;
    my $param = {@_};
    if (defined $param->{family} && $param->{family} eq 'UNIX'
	&& !exists($param->{port})) {
    	$self->{port} = $IPC::Locker::Default_UNIX_port;
    }
    return $self;
}

sub start_server {
    my $self = shift;

    # Open the socket
    print "Listening on $self->{port}\n" if $Debug;
    my $server;
    if ($self->{family} eq 'INET') {
    	$server = IO::Socket::INET->new( Proto     => 'tcp',
					 LocalPort => $self->{port},
					 Listen    => SOMAXCONN,
					 Reuse     => 1)
	    or die "$0: Error, socket: $!";
    } elsif ($self->{family} eq 'UNIX') {
    	$server = IO::Socket::UNIX->new(Local => $self->{port},
					Listen    => SOMAXCONN,
					Reuse     => 1)
	    or die "$0: Error, socket: $!\n port=$self->{port}=";
	$self->{unix_socket_created}=1;
    } else {
    	die "IPC::Locker::Server:  What transport do you want to use?";
    }
    $Select = new IO::Select( $server );

    %Clients = ();
    my $timeout=2;
    #$SIG{ALRM} = \&sig_alarm;
    $SIG{INT}= \&sig_INT;
    $SIG{HUP}= \&sig_INT;
    
    while (!$Interrupts) {
    	my ($r, $w, $e, $fh, @a);
	$r = $w = $e = 0;
	print "Pre-Select $!\n" if $Debug;
	$! = 0;
    	@a = IO::Select::select($Select, undef, $Select, $timeout); 
	($r, $w, $e) = @a;
	print "Select $#a $#$r $#$w $#$e $! \n" if $Debug;
        foreach $fh (@$r) {
            if ($fh == $server) {
        	# Create a new socket
        	my $clientfh = $server->accept;
        	$Select->add($clientfh);
		print $clientfh "HELLO\n" if $Debug;
		#
		my $clientvar = {socket=>$clientfh,
				 delayed=>0,
				 input=>'',
			     };
		$Clients{$clientfh}=$clientvar;
	    } else {
		my $data = '';
		my $rc = recv($fh, $data, 1000, 0);
		if ($data eq '') {
        	    # we have finished with the socket
		    delete $Clients{$fh};
        	    $Select->remove($fh);
        	    $fh->close;
 		} else {
		    my $line = $Clients{$fh}->{input}.$data;
		    my @lines = split /\n/, $line;
		    if ($line =~ /\n$/) {
		    	$Clients{$fh}->{input}='';
			print "Nothing Left\n" if $Debug;
		    } else {
		    	$Clients{$fh}->{input}=unshift @lines;
			print "Left: ".$Clients{$fh}->{input}."\n" if $Debug;
		    }
		    unshift(@{$Clients{$fh}->{inputlines}}, @lines);
		    client_service($Clients{$fh});
		    recheck_locks();
		}
	    }
	}
	foreach $fh (@$e) {
	    # we have finished with the socket
	    delete $Clients{$fh};
	    $Select->remove($fh);
	    $fh->close;
        }
	recheck_locks();
	foreach my $cl (values %Clients) {
	    if ($cl->{locked}){
	    	client_service ($cl);
	    }
	}
	$timeout = alarm_time();
	if (!$timeout){
	    $timeout = 2000;
	}
    }
}

######################################################################
######################################################################
#### Client servicing

sub client_service {
    # Loop getting commands from a specific client
    my $clientvar = shift || die;
    
    my $line;
    
    while (defined($line = shift @{$clientvar->{inputlines}})) {
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
	    print "Wait= $wait\n" if $Debug;
	    last if $wait;
	}
	if ($line =~ /^EOF$/m) {
	    client_close ($clientvar);
	    undef $clientvar;
	    last; 
	}
    }
}

sub client_close {
    my $clientvar = shift || die;
    if ($clientvar->{socket}) {
	delete $Clients{$clientvar->{socket}};
	$Select->remove($clientvar->{socket});
	$clientvar->{socket}->close();
    }
    $clientvar->{socket} = undef;
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

	if (!$clientvar->{block} && $locki->{locked}) {
	    last;
	} else {
	    push @{$locki->{waiters}}, $clientvar;
	}
	
	if ($locki->{locked}) {
	    $clientvar->{told_locked} = 1;
	    client_send ($clientvar, "print_waiting $locki->{owner}\n");
	} else {
	    locki_lock($locki);
    	    last if ($locki->{owner} eq $clientvar->{user});
	}

	# Either need to wait for timeout, or someone else to return key
	return 1;	# Exit loop and check if can lock
    }
    client_status ($clientvar);
    0;
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
	print "Waiter count: ".$#{$locki->{waiters}}."\n" if $Debug;
	for (my $n=0; $n <= $#{$locki->{waiters}}; $n++) {
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
    my $status = send $clientfh,$msg,0 ;
    if (!$status) {
	warn "client_send hangup $? $! $status $clientfh " if $Debug;
	client_close ($clientvar);
	return 0;
    }
    return 1;
}

######################################################################
######################################################################
#### Alarm handler

sub sig_INT {
    $Interrupts++;
    #$SIG{INT}= \&sig_INT;
    0;
}

sub alarm_time {
    # Compute alarm interval and set
    my $time = time();
    my $timelimit = undef;
    foreach my $locki (values %Locks) {
	if ($locki->{locked}) {
	    $timelimit = $locki->{timelimit} if (!defined $timelimit
				 || $locki->{timelimit} <= $timelimit);
	}
    }
    return $timelimit ? ($timelimit - $time + 1) : 0;
}

######################################################################
######################################################################
#### Internals

sub locki_lock {
    # Give lock to next requestor that accepts it
    my $locki = shift || die;

    print "Locki_lock:1:Waiter count: ".$#{$locki->{waiters}}."\n" if $Debug;
    while (my $clientvar = shift @{$locki->{waiters}}) {
    	print "Locki_lock:2:Waiter count: ".$#{$locki->{waiters}}."\n" if $Debug;
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

sub DESTROY {
    my $self = shift;
    print "DESTROY\n" if $Debug;
    if (($self->{family} eq 'UNIX') && $self->{unix_socket_created}){
    	unlink $self->{port};
    }
}

######################################################################
#### Package return
1;
