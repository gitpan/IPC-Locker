# IPC::Locker.pm -- distributed lock handler

# RCS Status      : $Id: Locker.pm,v 1.3 1999/06/02 13:54:52 wsnyder Exp $
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

=head1 PARAMETERS

=item block

Boolean flag, true indicates wait for the lock when calling lock() and die
if a error occurs.  False indicates to just return false.  Defaults to
true.

=item host

The name of the host containing the lock server.

=item port

The port number of the lock server.  Defaults to 1751.

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

=item timeout

The maximum time in seconds that the lock may be held before being forced
open, passed to the server when the lock is created.  Thus if the requestor
dies, the lock will be released after that amount of time.  Defaults to 10
minutes.

=item user

Name to request the lock under, defaults to host_pid_user

=item verbose

True to print messages when waiting for locks.  Defaults false.

=head1 SEE ALSO

C<lockerd>, 

=head1 DISTRIBUTION

This package is distributed via CPAN.

=head1 AUTHORS

Wilson Snyder <wsnyder@ultranet.com>

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
use vars qw($VERSION $Debug $Default_Port);
use Carp;

######################################################################
#### Configuration Section

# Other configurable settings.
$Debug = 0;

$VERSION = "1.10";

######################################################################
#### Useful Globals

$Default_Port = 1751;

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
    $self->request("LOCK");
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
    $self->request("UNLOCK");
    croak $self->{error} if $self->{error};
    return ($self);
}

sub break_lock {
    my $self = shift; ($self) or croak 'usage: $self->break_lock()';
    $self = $self->new(@_) if (!ref($self));
    $self->request("BREAK_LOCK");
    croak $self->{error} if $self->{error};
    return ($self);
}

######################################################################
#### User utilities: owner

sub owner {
    my $self = shift; ($self) or croak 'usage: $self->status()';
    $self = $self->new(@_) if (!ref($self));
    $self->request ("STATUS");
    croak $self->{error} if $self->{error};
    print "Locker->owner = $self->{owner}\n" if $Debug;
    return $self->{owner};
}

######################################################################
######################################################################
#### Guts: Sending and receiving messages

sub request {
    my $self = shift;
    my $cmd = shift;
    my $req = ("user $self->{user}\n"
	       ."lock $self->{lock}\n"
	       ."block $self->{block}\n"
	       ."timeout $self->{timeout}\n"
	       ."$cmd\n");
    print "REQ $req\n" if $Debug;

    my $fh = IO::Socket::INET->new( Proto     => "tcp",
				    PeerAddr  => $self->{host},
				    PeerPort  => $self->{port},
				    );
    $fh or croak "%Error: Can't locate lock server on $self->{host} $self->{port}\n"
	. "\tYou probably need to run lockerd\n$self->request(): Stopped";

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
