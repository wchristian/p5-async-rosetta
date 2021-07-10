use 5.010;
use strictures;

use Moo;

use IO::Async::Timer::Periodic;
use IO::Async::Loop;
use curry;

has loop => is => ro => default => sub { IO::Async::Loop->new };

__PACKAGE__->new->run;

sub run {
    my ($self) = @_;

    $|++;

    $self->loop->add($_) for IO::Async::Timer::Periodic    #
      ->new( interval => 0.25, on_tick => sub { print "." } )->start;

    $self->do(1)->get;
    $self->do(2)->get;
}

sub do {
    my ( $self, $id ) = @_;
    $self->log_to_db("start")                              #
      ->then( $self->curry::get_object_name($id) )
      ->then( $self->curry::delete_object )->then(
        $self->curry::log_to_db("success"),
        $self->curry::log_to_db("failure"),
      )                                                    #
      ->then( $self->curry::finalize );
}

sub get_object_name {
    my ( $self, $id ) = @_;
    $self->call_external_api( "get_object_name", "name $id" );
}

sub delete_object {
    my ( $self, $name ) = @_;
    $self->call_external_api( "delete_object", $name );
}

sub finalize {
    my ( $self, $msg ) = @_;
    $self->log_to_db("done")->then( sub { say "end"; $self->loop->stop } );
}

sub log_to_db {
    my ( $self, $msg ) = @_;
    $self->call_internal_api( "log_to_db", $msg );
}

sub call_external_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    my $meth =
      ( $call eq "delete_object" and $arg eq "name 2" ) ? "fail" : "done";
    my $future = $self->loop->new_future;
    $self->loop->watch_time( after => 1, code => sub { $future->$meth($arg) } );
    return $future;
}

sub call_internal_api {
    my ( $self, $call, $arg ) = @_;
    say "$call, $arg";
    my $future = $self->loop->new_future;
    $self->loop->watch_time( after => 1, code => sub { $future->done($arg) } );
    return $future;
}
