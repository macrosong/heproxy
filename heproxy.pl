#
# HE proxy - HappyElements Tcp Proxy (athena project)
#

use warnings;
use strict;

use IO::Socket::INET;
use IO::Select;

my @allowed_ips = ('all');
my $ioset = IO::Select->new;
my %socket_map;

my $debug = 1;

sub new_conn {
    my ($host, $port) = @_;
    return IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port
    ) || die "Unable to connect to $host:$port: $!";
}

sub new_server {
    my ($host, $port) = @_;
    my $server = IO::Socket::INET->new(
        LocalAddr => $host,
        LocalPort => $port,
        ReuseAddr => 1,
        Listen    => 100
    ) || die "Unable to listen on $host:$port: $!";
}

sub new_connection {
    my $server = shift;
    my $remote_host = shift;
    my $remote_port = shift;
    my $tgw = shift;

    my $client = $server->accept;
    my $client_ip = client_ip($client);

    unless (client_allowed($client)) {
        print "Connection from $client_ip denied.\n" if $debug;
        $client->close;
        return;
    }
    print "Connection from $client_ip accepted.\n" if $debug;

    my $remote = new_conn($remote_host, $remote_port);
    $ioset->add($client);
    $ioset->add($remote);

    $socket_map{$client} = $remote;
    $socket_map{$remote} = $client;

    if($tgw){
        $remote->syswrite("tgw_l7_forward\r\nHost:$remote_host:$remote_port\r\n\r\n");
        print "send tgw package for Tencent.\n";
    }
}

sub close_connection {
    my $client = shift;
    my $client_ip = client_ip($client);
    my $remote = $socket_map{$client};

    $ioset->remove($client);
    $ioset->remove($remote);

    delete $socket_map{$client};
    delete $socket_map{$remote};

    $client->close;
    $remote->close;

    print "Connection from $client_ip closed.\n" if $debug;
}

sub client_ip {
    my $client = shift;
    return $client->peerhost();
    #return inet_ntoa($client->sockaddr);
}

sub client_allowed {
    my $client = shift;
    my $client_ip = client_ip($client);
    return grep { $_ eq $client_ip || $_ eq 'all' } @allowed_ips;
}

die "Usage: $0 <local port> <remote_host:remote_port> <tgw>" unless @ARGV >= 2;

my $local_port = shift;
my ($remote_host, $remote_port) = split ':', shift();
my $tgw = shift;

print "Starting a server on 0.0.0.0:$local_port\n";
my $server = new_server('0.0.0.0', $local_port);
$ioset->add($server);

while (1) {
    for my $socket ($ioset->can_read) {
        if ($socket == $server) {
            new_connection($server, $remote_host, $remote_port, $tgw);
        }
        else {
            next unless exists $socket_map{$socket};
            my $remote = $socket_map{$socket};
            my $buffer;
            my $read = $socket->sysread($buffer, 4096);
            if ($read) {
                if (substr($buffer,0,14) eq "tgw_l7_forward"){
                    print $buffer;
                }
                else {
                    $remote->syswrite($buffer);
                }
            }
            else {
                close_connection($socket);
            }
        }
    }
}