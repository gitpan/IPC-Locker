# IPC::Locker.pm -- distributed lock handler

# RCS Status      : $Id: Locker.pm,v 1.15 2001/02/13 17:37:33 wsnyder Exp $
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

IPC::Locker - Distributed lock handler

=head1 SYNOPSIS

  use IPC::Locker;

  my $lock = IPC::Locker->lock(lock=>'one_per_machine',
				  host=>'example.std.com',
				  port=>223);

  if ($lock->lock()) { something; }
  if ($lock->locked()) { something; }

  $lock->unlock();

=head1 DESCRIPTION

C<IPC::Locker> will query a remote server to obtain a lock.  This is
useful for distributed utilities which run on many machines, and cannot use
file locks or other such mechanisms due to NFS or lack of common file
systems.

=over 4

=item new ([parameter=>value ...]);

Create a lock structure.

=item lock ([parameter=>value ...]);

Try to obtain the lock, return the lock object if successful, else undef.

=item locked ()

Return true if the lock has been obtained.

=item unlock ()

Remove the given lock.  This will be called automatically when the object
is destroyed.

=item break_lock ()

Remove current locker for the given lock.

=item owner ([parameter=>value ...]);

Returns a string of who has the lock or undef if not currently .  Note that
this information is not atomic, and may change asyncronously; do not use
this to tell if the lock will be available, to do that, try to obtain the
lock and then release it if you got it.

=back

=head1 PARAMETERS

=over 4

=item block

Boolean flag, true indicates wait for the lock when calling lock() and die
if a error occurs.  False indicates to just return false.  Defaults to
true.

=item family

The family of transport to use, either INET or UNIX.  Defaults to INET.

=item host

The name of the host containing the lock server.  It may also be a array
of hostnames, where if the first one is down, subsequent ones will be tried.

=item port

The port number (INET) or name (UNIX) of the lock server.  Defaults to
'lockerd' looked up via /etc/services, else 1751.

=item lock

The name of the lock.

=item print_broke

A function to print a message when the lock is broken.  The only argument
is self.  Defaults to print a message if verbose is set.

=item print_obtained

A function to print a message when the lock is obtained after a delay.  The
only argument is self.  Defaults to print a message if verbose is set.

=item print_waiting

A function to print a message when the lock is busy and needs to be waited
for.  The first argument is self, second the name of the lock.  Defaults to
print a message if verbose is set.

=item print_down

A function to print a message when the lock server is unavailable.  The
first argument is self.  Defaults to a croak message.

=item timeout

The maximum time in seconds that the lock may be held before being forced
open, passed to the server when the lock is created.  Thus if the requestor
dies, the lock will be released after that amount of time.  Defaults to 10
minutes.

=item user

Name to request the lock under, defaults to host_pid_user

=item verbose

True to print messages when waiting for locks.  Defaults false.

=back

=head1 SEE ALSO

C<lockerd>, 

=head1 DISTRIBUTION

This package is distributed via CPAN.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################

package IPC::Locker;
require 5.004;
require Exporter;
@ISA = qw(Exporter);

use Sys::Hostname;
use Socket;
use IO::Socket;

use strict;
use vars qw($VERSION $Debug $Default_Port $Default_Family $Default_UNIX_port);
use Carp;

######################################################################
#### Configuration Section

# Other configurable settings.
$Debug = 0;

$VERSION = '1.14';

######################################################################
#### Useful Globals

$Default_Port = 'lockerd';	# Number (1751) or name to lookup in /etc/services
$Default_Port = 1751 if !getservbyname ($Default_Port,"");
$Default_Family = 'INET';
$Default_UNIX_port = '/var/locks/lockerd';

######################################################################
#### Creator

sub new {
    @_ >= 1 or croak 'usage: IPC::Locker->new ({options})';
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $user = hostname() . "_".$$."_" . ($ENV{USER} || "");
    my $self = {
	#Documented
	host=>'localhost', port=>$Default_Port,
	lock=>'lock',
	timeout=>60*10, block=>1,
	user=>$user,
	verbose=>$Debug,
	print_broke=>sub {my $self=shift; print "Broke lock from $_[0] at ".(scalar(localtime))."\n" if $self->{verbose};},
	print_obtained=>sub {my $self=shift; print "Obtained lock at ".(scalar(localtime))."\n" if $self->{verbose};},
	print_waiting=>sub {my $self=shift; print "Waiting for lock from $_[0] at ".(scalar(localtime))."\n" if $self->{verbose};},
	print_down=>undef,
	family=>$Default_Family,
	#Internal
	locked=>0,
	@_,};
    bless $self, $class;
    return $self;
}

######################################################################
#### Accessors

sub locked () {
    my $self = shift; ($self && ref($self)) or croak 'usage: $self->locked()';
    return $self if $self->{locked};
    return undef;
}

######################################################################
#### Constructor

sub lock {
    my $self = shift;
    $self = $self->new(@_) if (!ref($self));
    $self->_request("LOCK");
    croak $self->{error} if $self->{error};
    return ($self) if $self->{locked};
    return undef;
}

######################################################################
#### Destructor/Unlock

sub DESTROY () {
    my $self = shift; ($self && ref($self)) or croak 'usage: $self->DESTROY()';
    $self->unlock();
}

sub unlock {
    my $self = shift; ($self && ref($self)) or croak 'usage: $self->unlock()';
    return if (!$self->{locked});
    $self->_request("UNLOCK");
    croak $self->{error} if $self->{error};
    return ($self);
}

sub break_lock {
    my $self = shift; ($self) or croak 'usage: $self->break_lock()';
    $self = $self->new(@_) if (!ref($self));
    $self->_request("BREAK_LOCK");
    croak $self->{error} if $self->{error};
    return ($self);
}

######################################################################
#### User utilities: owner

sub owner {
    my $self = shift; ($self) or croak 'usage: $self->status()';
    $self = $self->new(@_) if (!ref($self));
    $self->_request ("STATUS");
    croak $self->{error} if $self->{error};
    print "Locker->owner = $self->{owner}\n" if $Debug;
    return $self->{owner};
}

######################################################################
######################################################################
#### Guts: Sending and receiving messages

sub _request {
    my $self = shift;
    my $cmd = shift;
    my $req = ("user $self->{user}\n"
	       ."lock $self->{lock}\n"
	       ."block $self->{block}\n"
	       ."timeout $self->{timeout}\n"
	       ."$cmd\n");
    print "REQ $req\n" if $Debug;

    my $fh;
    if ($self->{family} eq 'INET'){
	my @hostlist = ($self->{host});
	@hostlist = @{$self->{host}} if (ref($self->{host}) eq "ARRAY");

	foreach my $host (@hostlist) {
	    print "Trying host $host\n" if $Debug;
	    $fh = IO::Socket::INET->new( Proto     => "tcp",
					 PeerAddr  => $host,
					 PeerPort  => $self->{port},
					 );
	    if ($fh) {
		if ($host ne $hostlist[0]) {
		    # Reorganize host list so whoever responded is first
		    # This is so if we grab a lock we'll try to return it to the same host
		    $self->{host} = [$host, @hostlist];
		}
		last;
	    }
	}
	if (!$fh) {
	    if (defined $self->{print_down}) {
		&{$self->{print_down}} ($self);
		return;
	    }
	    croak "%Error: Can't locate lock server on " . (join " or ", @hostlist), " $self->{port}\n"
		. "\tYou probably need to run lockerd\n$self->_request(): Stopped";
	}
    } elsif ($self->{family} eq 'UNIX') {
	$fh = IO::Socket::UNIX->new( Peer => $self->{port},
				     )
	    or croak "%Error: Can't locate lock server on $self->{port}.\n"
		. "\tYou probably need to run lockerd\n$self->_request(): Stopped";
    } else {
    	croak "IPC::Locker->_request(): No or wrong transport specified.";
    }
    
    print $fh "$req\nEOF\n";
    while (defined (my $line = <$fh>)) {
	chomp $line;
	next if $line =~ /^\s*$/;
	my @args = split /\s+/, $line;
	my $cmd = shift @args;
	print "RESP $line\n" if $Debug;
	$self->{locked} = $args[0] if ($cmd eq "locked");
	$self->{owner}  = $args[0] if ($cmd eq "owner");
	$self->{error}  = $args[0] if ($cmd eq "error");
	&{$self->{print_obtained}} ($self,@args)  if ($cmd eq "print_obtained");
	&{$self->{print_waiting}}  ($self,@args)  if ($cmd eq "print_waiting");
	&{$self->{print_broke}}    ($self,@args)  if ($cmd eq "print_broke");
	print "$1\n" if ($line =~ /^ECHO\s+(.*)$/ && $self->{verbose});  #debugging
    }
    $fh->close();
}

######################################################################
#### Package return
1;
