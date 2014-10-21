#!/usr/bin/perl

package IPC::Open3::Callback::NullLogger;
{
  $IPC::Open3::Callback::NullLogger::VERSION = '1.00_01';
}

use AutoLoader;

our $LOG_TO_STDOUT = 0;

sub AUTOLOAD {
    shift;
    print( "IPC::Open3::Callback::NullLogger: @_\n" ) if $LOG_TO_STDOUT;
}

sub new {
    return bless( {}, shift );
}

no AutoLoader;

package IPC::Open3::Callback;
{
  $IPC::Open3::Callback::VERSION = '1.00_01';
}

use strict;
use warnings;

use Exporter qw(import);
our @EXPORT_OK = qw(safe_open3);

use Data::Dumper;
use IO::Select;
use IO::Socket;
use IPC::Open3;
use Symbol qw(gensym);

my $logger;
eval {
    require Log::Log4perl;
    $logger = Log::Log4perl->get_logger( 'IPC::Open3::Callback' );
};
if ( $@ ) {
    $logger = IPC::Open3::Callback::NullLogger->new();
}

sub new {
    my $prototype = shift;
    my $class = ref( $prototype ) || $prototype;
    my $self = {};
    bless( $self, $class );

    my %args = @_;

    $self->{out_callback} = $args{out_callback};
    $self->{err_callback} = $args{err_callback};
    $self->{buffer_output} = $args{buffer_output};
    $self->{select_timeout} = $args{select_timeout};

    return $self;
}

sub append_to_buffer {
    my $self = shift;
    my $buffer_ref = shift;
    my $data = $$buffer_ref . shift;
    my $flush = shift;

    my @lines = split( /\n/, $data, -1 );

    # save the last line in the buffer as it may not yet be a complete line
    $$buffer_ref = $flush ? '' : pop( @lines );
    
    # return all complete lines
    return @lines;
}

sub nix_open3 {
    my @command = @_;

    my ($in_fh, $out_fh, $err_fh) = (gensym(), gensym(), gensym());
    return ( open3( $in_fh, $out_fh, $err_fh, @command ),
        $in_fh, $out_fh, $err_fh );
}

sub run_command {
    my $self = shift;
    my @command = @_;
    my $options = {};
    
    # if last arg is hashref, its command options not arg...
    if ( ref( $command[-1] ) eq 'HASH' ) {
        $options = pop(@command);
    }
    
    my ($out_callback, $out_buffer_ref, $err_callback, $err_buffer_ref);
    $out_callback = $options->{out_callback} || $self->{out_callback};
    $err_callback = $options->{err_callback} || $self->{err_callback};
    if ( $options->{buffer_output} || $self->{buffer_output} ) {
        $out_buffer_ref = \'';
        $err_buffer_ref = \'';
    }

    $logger->debug( sub { "running '" . join( ' ', @command ) . "'" } );
    my ($pid, $in_fh, $out_fh, $err_fh) = safe_open3( @command );

    my $select = IO::Select->new();
    $select->add( $out_fh, $err_fh );

    while ( my @ready = $select->can_read( $self->{select_timeout} ) ) {
        if ( $self->{input_buffer} ) {
            syswrite( $in_fh, $self->{input_buffer} );
            delete( $self->{input_buffer} );
        }
        foreach my $fh ( @ready ) {
            my $line;
            my $bytes_read = sysread( $fh, $line, 1024 );
            if ( ! defined( $bytes_read ) && !$!{ECONNRESET} ) {
                $logger->error( "sysread failed: ", sub { Dumper( %! ) } );
                die( "error in running '" . join( ' ' . @command ) . "': $!" );
            }
            elsif ( ! defined( $bytes_read) || $bytes_read == 0 ) {
                $select->remove( $fh );
                next;
            }
            else {
                if ( $fh == $out_fh ) {
                    $self->write_to_callback( $out_callback, $line, $out_buffer_ref, 0, $pid );
                }
                elsif ( $fh == $err_fh ) {
                    $self->write_to_callback( $err_callback, $line, $err_buffer_ref, 0, $pid );
                }
                else {
                    die( "impossible... somehow got a filehandle i dont know about!" );
                }
            }
        }
    }
    # flush buffers
    $self->write_to_callback( $out_callback, '', $out_buffer_ref, 1, $pid );
    $self->write_to_callback( $err_callback, '', $err_buffer_ref, 1, $pid );

    waitpid( $pid, 0 );
    my $exit_code = $? >> 8;

    $logger->debug( "exited '" . join( ' ', @command ) . "' with code $exit_code" );
    return $exit_code;
}

sub safe_open3 {
    return ( $^O =~ /MSWin32/ ) ? win_open3( @_ ) : nix_open3( @_ );
}

sub send_input {
    my $self = shift;
    $self->{input_buffer} = shift;
}

sub win_open3 {
    my @command = @_;

    my ($in_read, $in_write) = win_pipe();
    my ($out_read, $out_write) = win_pipe();
    my ($err_read, $err_write) = win_pipe();
    
    my $pid = open3( '>&'.fileno($in_read), 
        '<&'.fileno($out_write), 
        '<&'.fileno($err_write),
         @command );
    
    return ( $pid, $in_write, $out_read, $err_read );
}

sub win_pipe {
    my ($read, $write) = IO::Socket->socketpair( AF_UNIX, SOCK_STREAM, PF_UNSPEC );
    $read->shutdown( SHUT_WR );  # No more writing for reader
    $write->shutdown( SHUT_RD );  # No more reading for writer

    return ($read, $write);
}

sub write_to_callback {
    my $self = shift;
    my $callback = shift;
    my $data = shift;
    my $buffer_ref = shift;
    my $flush = shift;
    my $pid = shift;
    
    return if ( ! defined( $callback ) );
    
    if ( ! defined( $buffer_ref ) ) {
        &{$callback}( $data, $pid );
        return;
    }
    
    &{$callback}( $_ ) foreach ( $self->append_to_buffer( $buffer_ref, $data, $flush ) ) ;
}

1;
__END__
=head1 NAME


=head1 VERSION

version 1.00_01
IPC::Open3::Callback - An extension to Open3 that will feed out and err to
callbacks instead of requiring the caller to handle them.

=head1 SYNOPSIS

  use IPC::Open3::Callback;
  my $runner = IPC::Open3::Callback->new( 
      out_callback => sub {
          print( "$_[0]\n" );
      },
      err_callback => sub {
          print( STDERR "$_[0]\n" );
      } );
  $runner->run_command( 'echo Hello World' );
  

=head1 DESCRIPTION

This module feeds output and error stream from a command to supplied callbacks.  
Thus, this class removes the necessity of dealing with IO::Select by hand and
also provides a workaround for Windows systems.

=head2 CONSTRUCTOR

=over 4

=item new( [ out_callback => SUB ], [ err_callback => SUB ] )

The constructor creates a new object and attaches callbacks for STDOUT and
STDERR streams from commands that will get run on this object.

=back

=head1 METHODS

=over 4

=item run_command( [ COMMAND_LIST ] )

Returns the value of the 'verbose' property.  When called with an
argument, it also sets the value of the property.  Use a true or false
Perl value, such as 1 or 0.

=back

=head1 AUTHOR

Lucas Theisen (lucastheisen@pastdev.com)

=head1 COPYRIGHT

Copyright 2013 pastdev.com.  All rights reserved.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

IPC::Open3(1).

=cut
