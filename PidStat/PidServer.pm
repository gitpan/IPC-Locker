# IPC::Locker.pm -- distributed lock handler
# $Id: PidServer.pm,v 1.6 2003/07/24 17:25:43 wsnyder Exp $
# Wilson Snyder <wsnyder@wsnyder.org>
######################################################################
#
# This program is Copyright 2001 by Wilson Snyder.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of either the GNU General Public License or the
# Perl Artistic License.
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

package IPC::PidStat::PidServer;
require 5.004;
require Exporter;
@ISA = qw(Exporter);

use IPC::Locker;
use Socket;
use IO::Socket;
use Sys::Hostname;

use strict;
use vars qw($VERSION $Debug $Hostname);
use Carp;

######################################################################
#### Configuration Section

# Other configurable settings.
$Debug = 0;

$VERSION = '1.420';

$Hostname = hostname();

######################################################################
#### Creator

sub new {
    # Establish the server
    @_ >= 1 or croak 'usage: IPC::PidStat::PidServer->new ({options})';
    my $proto = shift;
    my $class = ref($proto) || $proto;
    my $self = {
	#Documented
	port=>$IPC::Locker::Default_PidStat_Port,
	@_,};
    bless $self, $class;
    return $self;
}

sub start_server {
    my $self = shift;

    # Open the socket
    print "Listening on $self->{port}\n" if $Debug;
    my $server = IO::Socket::INET->new( Proto     => 'udp',
					LocalPort => $self->{port},
					Reuse     => 1)
	    or die "$0: Error, socket: $!";

    while (1) {
	my $in_msg;
	next unless $server->recv($in_msg, 8192);
	print "Got msg $in_msg\n" if $Debug;
	if ($in_msg =~ /^PIDR (\d+)/) {  # PID request
	    my $pid = $1;
	    $! = undef;
	    my $exists = IPC::PidStat::local_pid_exists($pid);
	    if (defined $exists) {  # Else perhaps we're not running as root?
		my $out_msg = "EXIS $pid $exists $Hostname";  # PID response
		print "   Send msg $out_msg\n" if $Debug;
		$server->send($out_msg);  # or die... But we'll ignore errors
	    }
	}
    }
}

######################################################################
#### Package return
1;
=pod

=head1 NAME

IPC::PidStat::PidServer - Process ID existance server

=head1 SYNOPSIS

  use IPC::PidStat::PidServer;

  IPC::PidStat::PidServer->start_server(port=>1234,);

=head1 DESCRIPTION

C<IPC::PidStat::PidServer> responds to UDP requests that contain a PID with
a packet indicating the PID and if the PID currently exists.

The Perl IPC::Locker package optionally uses this daemon to break locks
for PIDs that no longer exists.

=over 4

=item start_server ([parameter=>value ...]);

Starts the server.  Does not return.

=head1 PARAMETERS

=item port

The port number (INET) or name (UNIX) of the lock server.  Defaults to
'pidstatd' looked up via /etc/services, else 1752.

=head1 SEE ALSO

C<pidstatd>, C<IPC::Locker>, C<IPC::PidStat>

=head1 DISTRIBUTION

This package is distributed via CPAN.

=head1 AUTHORS

Wilson Snyder <wsnyder@wsnyder.org>

=cut

######################################################################
